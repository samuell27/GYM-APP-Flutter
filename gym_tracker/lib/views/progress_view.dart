import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';

class ProgressView extends StatefulWidget {
  const ProgressView({super.key});

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  bool _isLoading = true;
  List<dynamic> _workoutHistory = [];
  
  // Estatísticas e Gráfico
  int _totalWorkouts = 0;
  int _totalVolume = 0;
  int _activeDaysThisMonth = 0;
  int _workoutsThisWeek = 0;
  List<BarChartGroupData> _chartData = [];
  double _maxChartVolume = 0;

  @override
  void initState() {
    super.initState();
    _loadAndSyncData();
  }

  Future<void> _loadAndSyncData() async {
    try {
      setState(() => _isLoading = true);
      await _loadLocalHistory();
      await _syncWithFirebase();
      _calculateStats();
    } catch (e) {
      debugPrint('Erro ao processar treinos antigos: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('workout_history');
      _workoutHistory = [];
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadLocalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('workout_history');
    if (historyJson != null) {
      try {
        _workoutHistory = jsonDecode(historyJson);
      } catch (e) {
        _workoutHistory = [];
      }
    }
  }

  Future<void> _syncWithFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('workout_history')
          .where('userUid', isEqualTo: user.uid)
          .get();

      if (snapshot.docs.isNotEmpty) {
        Set<String> localIds = _workoutHistory
            .whereType<Map<String, dynamic>>()
            .map((w) => w['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        bool hasNewData = false;

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final String id = data['id']?.toString() ?? doc.id;

          if (!localIds.contains(id)) {
            _workoutHistory.add(data);
            hasNewData = true;
          }
        }

        if (hasNewData) {
          _workoutHistory.sort((a, b) {
            if (a is! Map || b is! Map) return 0;
            final dateA = DateTime.tryParse(a['dateIso']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            final dateB = DateTime.tryParse(b['dateIso']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            return dateB.compareTo(dateA);
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('workout_history', jsonEncode(_workoutHistory));
        }
      }
    } catch (e) {
      debugPrint('Erro no sync com Firebase: $e');
    }
  }

  Future<void> _deleteWorkout(String workoutId) async {
    if (workoutId.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1c1c1e),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(LucideIcons.alertOctagon, color: Colors.redAccent),
              SizedBox(width: 12),
              Text('Apagar Treino', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Deseja realmente apagar este treino do seu histórico? Os seus gráficos de volume também serão atualizados.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.15),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sim, apagar', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          var snapshot = await FirebaseFirestore.instance
              .collection('workout_history')
              .where('id', isEqualTo: workoutId)
              .where('userUid', isEqualTo: user.uid)
              .get();
              
          for (var doc in snapshot.docs) {
            await doc.reference.delete();
          }
        }

        _workoutHistory.removeWhere((w) => w is Map && w['id']?.toString() == workoutId);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('workout_history', jsonEncode(_workoutHistory));
        
        _calculateStats();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Treino apagado com sucesso!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao apagar treino: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _calculateStats() {
    _totalWorkouts = _workoutHistory.length;
    _totalVolume = 0;
    _workoutsThisWeek = 0;
    _activeDaysThisMonth = 0;
    _maxChartVolume = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);
    
    Set<String> uniqueDaysThisMonth = {};
    Map<int, double> volumePerDay = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};

    for (var workout in _workoutHistory) {
      if (workout is! Map<String, dynamic>) continue; 
      
      double workoutVolume = 0;

      if (workout['exercises'] is List) {
        for (var ex in workout['exercises']) {
          if (ex is Map<String, dynamic> && ex['sets'] is List) {
            for (var set in ex['sets']) {
              if (set is Map<String, dynamic> && (set['isCompleted'] == true || set['isCompleted'] == 'true')) {
                int weight = int.tryParse(set['weight'].toString()) ?? 0;
                int reps = int.tryParse(set['reps'].toString()) ?? 0;
                int volume = (weight * reps);
                _totalVolume += volume;
                workoutVolume += volume;
              }
            }
          }
        }
      }

      DateTime? workoutDate = DateTime.tryParse(workout['dateIso']?.toString() ?? '');
      
      if (workoutDate != null) {
        if (workoutDate.isAfter(startOfWeek.subtract(const Duration(days: 1)))) {
          _workoutsThisWeek++;
        }
        if (workoutDate.isAfter(startOfMonth.subtract(const Duration(days: 1)))) {
          uniqueDaysThisMonth.add('${workoutDate.year}-${workoutDate.month}-${workoutDate.day}');
        }

        // Lógica do Gráfico: Volume dos últimos 7 dias
        final wDate = DateTime(workoutDate.year, workoutDate.month, workoutDate.day);
        final difference = today.difference(wDate).inDays;
        
        if (difference >= 0 && difference < 7) {
          int index = 6 - difference; // 6 é hoje, 0 é há 6 dias atrás
          volumePerDay[index] = (volumePerDay[index] ?? 0) + workoutVolume;
          if (volumePerDay[index]! > _maxChartVolume) {
            _maxChartVolume = volumePerDay[index]!;
          }
        }
      }
    }
    
    _activeDaysThisMonth = uniqueDaysThisMonth.length;
    
    // Geração das barras do gráfico
    _chartData = volumePerDay.entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value,
            color: const Color(0xFF22c55e),
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: _maxChartVolume == 0 ? 100 : _maxChartVolume * 1.1,
              color: Colors.white.withOpacity(0.05),
            ),
          )
        ],
      );
    }).toList();
  }

  String _formatDate(String? dateIso) {
    if (dateIso == null) return 'Data desconhecida';
    final date = DateTime.tryParse(dateIso);
    if (date == null) return dateIso; 

    final months = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    return '${date.day.toString().padLeft(2, '0')} de ${months[date.month - 1]}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getDayName(int daysAgo) {
    final date = DateTime.now().subtract(Duration(days: daysAgo));
    final days = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    return days[date.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22c55e)));
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text('Progresso', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                Row(
                  children: [
                    Expanded(child: _buildStatCard('Treinos', _totalWorkouts.toString(), LucideIcons.activity)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatCard('Dias no Mês', _activeDaysThisMonth.toString(), LucideIcons.flame, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildStatCard('Carga Total', '${(_totalVolume / 1000).toStringAsFixed(1)}t', LucideIcons.dumbbell, color: Colors.blueAccent)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatCard('Esta Semana', _workoutsThisWeek.toString(), LucideIcons.calendarCheck, color: Colors.purpleAccent)),
                  ],
                ),

                const SizedBox(height: 32),
                
                // --- GRÁFICO DE VOLUME ---
                const Text('VOLUME (ÚLTIMOS 7 DIAS)', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  padding: const EdgeInsets.only(top: 24, right: 16, left: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1c1c1e),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: _maxChartVolume == 0 ? 100 : _maxChartVolume * 1.1,
                      barTouchData: BarTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(_getDayName(6 - value.toInt()), style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                              );
                            },
                            reservedSize: 28,
                          ),
                        ),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _maxChartVolume == 0 ? 25 : (_maxChartVolume / 4).clamp(1.0, double.infinity),
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: _chartData,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                const Text('HISTÓRICO', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 16),

                // --- LISTA DE TREINOS ---
                if (_workoutHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(LucideIcons.history, color: Colors.white24, size: 48),
                        SizedBox(height: 16),
                        Text('Nenhum treino registrado ainda.', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  )
                else
                  ..._workoutHistory.map((workout) {
                    final int exCount = (workout['exercises'] is List) ? (workout['exercises'] as List).length : 0;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1c1c1e),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.all(20),
                          iconColor: const Color(0xFF22c55e),
                          collapsedIconColor: Colors.grey,
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  workout['name'] ?? 'Treino',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22c55e).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _formatDate(workout['dateIso']),
                                  style: const TextStyle(color: Color(0xFF22c55e), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.dumbbell, color: Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Text('$exCount exercícios concluídos', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                              ],
                            ),
                          ),
                          children: [
                            if (workout['exercises'] is List)
                              ...((workout['exercises'] as List).map((ex) {
                                if (ex is! Map) return const SizedBox.shrink();
                                
                                final String exName = ex['name']?.toString() ?? 'Exercício';
                                final List sets = ex['sets'] is List ? ex['sets'] as List : [];
                                
                                final completedSets = sets.where((s) => s is Map && (s['isCompleted'] == true || s['isCompleted'] == 'true')).toList();
                                
                                if (completedSets.isEmpty) return const SizedBox.shrink();

                                return Padding(
                                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(exName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(height: 8),
                                      ...completedSets.map((set) {
                                        final String weight = (set as Map)['weight']?.toString() ?? '0';
                                        final String reps = set['reps']?.toString() ?? '0';

                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              const Icon(LucideIcons.check, color: Color(0xFF22c55e), size: 16),
                                              const SizedBox(width: 8),
                                              Text('$weight kg  ×  $reps reps', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                );
                              }).toList()),
                              
                            Padding(
                              padding: const EdgeInsets.only(right: 16, bottom: 16),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _deleteWorkout(workout['id']?.toString() ?? ''),
                                  icon: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 18),
                                  label: const Text('Apagar Treino', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.redAccent.withOpacity(0.1),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, {Color color = const Color(0xFF22c55e)}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1c1c1e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}