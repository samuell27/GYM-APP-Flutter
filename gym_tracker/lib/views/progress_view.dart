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
  List<dynamic> _history = [];
  List<FlSpot> _chartData = [];
  double _maxVolume = 0;

  @override
  void initState() {
    super.initState();
    _syncAndLoadHistory();
  }

  Future<void> _syncAndLoadHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final uid = user.uid;
      final prefs = await SharedPreferences.getInstance();

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('workout_history')
            .where('userUid', isEqualTo: uid)
            .get();

        List<dynamic> cloudHistory = snapshot.docs.map((doc) {
          var data = doc.data();
          data['docId'] = doc.id; 
          return data;
        }).toList();

        cloudHistory.sort((a, b) {
          String dateA = a['dateIso'] ?? '';
          String dateB = b['dateIso'] ?? '';
          return dateB.compareTo(dateA);
        });

        await prefs.setString('workout_history_$uid', jsonEncode(cloudHistory));
        _history = cloudHistory;
        
      } catch (e) {
        debugPrint('Modo Offline: Não foi possível sincronizar com a nuvem. Carregando cache local. Erro: $e');
        final String? localData = prefs.getString('workout_history_$uid');
        if (localData != null) {
          _history = jsonDecode(localData);
        }
      }

      _calculateChartData();

    } catch (e) {
      debugPrint('Erro crítico ao carregar histórico: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateChartData() {
    final now = DateTime.now();
    List<FlSpot> spots = [];
    double maxVol = 0;

    for (int i = 6; i >= 0; i--) {
      DateTime targetDate = now.subtract(Duration(days: i));
      String targetDateStr = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      
      double dailyVolume = 0;

      for (var workout in _history) {
        if (workout is! Map) continue;
        
        String wDateIso = workout['dateIso']?.toString() ?? '';
        if (wDateIso.isEmpty) continue;

        DateTime? wDate = DateTime.tryParse(wDateIso);
        if (wDate != null) {
          String wDateStr = '${wDate.year}-${wDate.month.toString().padLeft(2, '0')}-${wDate.day.toString().padLeft(2, '0')}';
          
          if (wDateStr == targetDateStr) {
            if (workout['exercises'] is List) {
              for (var ex in workout['exercises']) {
                if (ex['sets'] is List) {
                  for (var set in ex['sets']) {
                    if (set['isCompleted'] == true || set['isCompleted'] == 'true') {
                      double weight = double.tryParse(set['weight']?.toString() ?? '0') ?? 0;
                      double reps = double.tryParse(set['reps']?.toString() ?? '0') ?? 0;
                      dailyVolume += (weight * reps);
                    }
                  }
                }
              }
            }
          }
        }
      }

      if (dailyVolume > maxVol) maxVol = dailyVolume;
      spots.add(FlSpot((6 - i).toDouble(), dailyVolume));
    }

    _chartData = spots;
    _maxVolume = maxVol > 0 ? maxVol + (maxVol * 0.2) : 100;
  }

  Future<void> _deleteWorkout(int index) async {
    final workout = _history[index];
    final String? docId = workout['docId'];

    setState(() {
      _history.removeAt(index);
      _calculateChartData();
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'default';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_history_$uid', jsonEncode(_history));

      if (docId != null) {
        await FirebaseFirestore.instance.collection('workout_history').doc(docId).delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Treino apagado do histórico.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Erro ao apagar treino: $e');
    }
  }

  String _formatDate(String? dateIso) {
    if (dateIso == null || dateIso.isEmpty) return 'Data Desconhecida';
    final d = DateTime.tryParse(dateIso);
    if (d == null) return 'Data Inválida';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  // --- LÓGICA DE CONSTRUÇÃO DOS DETALHES DO TREINO (O MIOLO DA SANFONA) ---
  List<Widget> _buildWorkoutDetails(dynamic exercisesData) {
    if (exercisesData is! List || exercisesData.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(8.0), child: Text('Nenhum detalhe salvo.', style: TextStyle(color: Colors.grey)))];
    }
    
    return exercisesData.map((ex) {
      if (ex is! Map) return const SizedBox.shrink();
      
      final String exName = ex['name']?.toString() ?? 'Exercício';
      final List sets = ex['sets'] is List ? ex['sets'] as List : [];
      
      // Filtra para mostrar apenas as séries que você realmente concluiu
      final completedSets = sets.where((s) => s is Map && (s['isCompleted'] == true || s['isCompleted'] == 'true')).toList();
      
      if (completedSets.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• $exName', style: const TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...completedSets.asMap().entries.map((entry) {
              final setIndex = entry.key;
              final setData = entry.value as Map;
              
              final String weight = setData['weight']?.toString() ?? '0';
              final String reps = setData['reps']?.toString() ?? '0';
              
              return Padding(
                padding: const EdgeInsets.only(left: 16.0, bottom: 6.0),
                child: Row(
                  children: [
                    Text('Série ${setIndex + 1}:', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text('$weight kg', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    const Text('x', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text('$reps reps', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }).toList();
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
            padding: EdgeInsets.fromLTRB(24, 40, 24, 16),
            child: Text(
              'O seu Progresso',
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
            ),
          ),
          
          // --- GRÁFICO DE VOLUME (fl_chart) ---
          Container(
            height: 220,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1c1c1e),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(LucideIcons.trendingUp, color: Color(0xFF22c55e), size: 18),
                    SizedBox(width: 8),
                    Text('Volume Semanal (Carga x Reps)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true, 
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), 
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              final date = DateTime.now().subtract(Duration(days: 6 - value.toInt()));
                              final days = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(days[date.weekday % 7], style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0, maxX: 6, minY: 0, maxY: _maxVolume,
                      lineBarsData: [
                        LineChartBarData(
                          spots: _chartData,
                          isCurved: true,
                          color: const Color(0xFF22c55e),
                          barWidth: 4,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF22c55e).withOpacity(0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('HISTÓRICO', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 16),

          // --- LISTA DE TREINOS (AGORA COM EXPANSION TILE) ---
          Expanded(
            child: _history.isEmpty
                ? const Center(
                    child: Text('Nenhum treino registado ainda.', style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final workout = _history[index];
                      final String wName = workout['name']?.toString() ?? 'Treino';
                      final String wDate = _formatDate(workout['dateIso']?.toString());
                      
                      int exercisesCount = 0;
                      if (workout['exercises'] is List) {
                        exercisesCount = (workout['exercises'] as List).length;
                      }

                      // ValueKey baseado no ID da nuvem ou no hash, evita que a lista se perca ao apagar um item
                      final itemKey = ValueKey(workout['docId'] ?? workout.hashCode.toString());

                      return Dismissible(
                        key: itemKey,
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(LucideIcons.trash2, color: Colors.white),
                        ),
                        onDismissed: (direction) => _deleteWorkout(index),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1c1c1e),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Theme(
                            // Remove as linhas indesejadas do ExpansionTile padrão do Flutter
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              iconColor: const Color(0xFF22c55e),
                              collapsedIconColor: Colors.grey,
                              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0a0a0a),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(LucideIcons.dumbbell, color: Color(0xFF22c55e), size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(wName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text('$exercisesCount exercícios', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Text(wDate, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              children: _buildWorkoutDetails(workout['exercises']),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}