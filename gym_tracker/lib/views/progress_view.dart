import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProgressView extends StatefulWidget {
  const ProgressView({super.key});

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  bool _isLoading = true;
  List<dynamic> _workoutHistory = [];

  // Estatísticas
  int _totalWorkouts = 0;
  int _totalVolume = 0;
  int _activeDaysThisMonth = 0; // Substitui a 'Streak' falha
  int _workoutsThisWeek = 0;

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
      debugPrint('Erro ao processar treinos antigos (limpando cache): $e');
      // Limpa os dados corrompidos para não travar o aplicativo
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('workout_history');
      _workoutHistory = [];
    } finally {
      // O finally garante que o ecrã destrava independentemente de erros
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
        debugPrint('Erro ao descodificar histórico local: $e');
        _workoutHistory = [];
      }
    }
  }

  Future<void> _syncWithFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return; // Só sincroniza se estiver logado

      final snapshot = await FirebaseFirestore.instance
          .collection('workout_history')
          .where('userUid', isEqualTo: user.uid)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Mapeia os IDs locais para não duplicar nem apagar o que não subiu
        Set<String> localIds = _workoutHistory
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
          // Ordena cronologicamente do mais recente para o mais antigo usando ISO 8601
          _workoutHistory.sort((a, b) {
            final dateA = DateTime.tryParse(a['dateIso']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final dateB = DateTime.tryParse(b['dateIso']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
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

  void _calculateStats() {
    _totalWorkouts = _workoutHistory.length;
    _totalVolume = 0;
    _workoutsThisWeek = 0;
    _activeDaysThisMonth = 0;

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);

    Set<String> uniqueDaysThisMonth = {};

    for (var workout in _workoutHistory) {
      // Verificações de segurança para ignorar históricos de versões antigas do app
      if (workout is! Map<String, dynamic>) continue;

      if (workout['exercises'] is List) {
        for (var ex in workout['exercises']) {
          if (ex is Map<String, dynamic> && ex['sets'] is List) {
            for (var set in ex['sets']) {
              if (set is Map<String, dynamic> &&
                  (set['isCompleted'] == true ||
                      set['isCompleted'] == 'true')) {
                int weight = int.tryParse(set['weight'].toString()) ?? 0;
                int reps = int.tryParse(set['reps'].toString()) ?? 0;
                _totalVolume += (weight * reps);
              }
            }
          }
        }
      }

      DateTime? workoutDate =
          DateTime.tryParse(workout['dateIso']?.toString() ?? '');

      if (workoutDate != null) {
        if (workoutDate
            .isAfter(startOfWeek.subtract(const Duration(days: 1)))) {
          _workoutsThisWeek++;
        }
        if (workoutDate
            .isAfter(startOfMonth.subtract(const Duration(days: 1)))) {
          uniqueDaysThisMonth.add(
              '${workoutDate.year}-${workoutDate.month}-${workoutDate.day}');
        }
      }
    }

    _activeDaysThisMonth = uniqueDaysThisMonth.length;
  }

  // Formata a data ISO para exibição amigável ("17 de Set, 14:30")
  String _formatDate(String? dateIso) {
    if (dateIso == null) return 'Data desconhecida';
    final date = DateTime.tryParse(dateIso);
    if (date == null) return dateIso; // Fallback se ainda for o formato antigo

    final months = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez'
    ];
    return '${date.day.toString().padLeft(2, '0')} de ${months[date.month - 1]}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22c55e)));
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text('Progresso',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1)),
          ),

          // --- ESTATÍSTICAS ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Expanded(
                    child: _buildStatCard('Treinos', _totalWorkouts.toString(),
                        LucideIcons.activity)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildStatCard('Dias no Mês',
                        _activeDaysThisMonth.toString(), LucideIcons.flame,
                        color: Colors.orange)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Expanded(
                    child: _buildStatCard(
                        'Carga Total',
                        '${(_totalVolume / 1000).toStringAsFixed(1)}t',
                        LucideIcons.dumbbell,
                        color: Colors.blueAccent)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildStatCard('Esta Semana',
                        _workoutsThisWeek.toString(), LucideIcons.calendarCheck,
                        color: Colors.purpleAccent)),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Text('HISTÓRICO',
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ),
          const SizedBox(height: 16),

          // --- LISTA DE TREINOS ---
          Expanded(
            child: _workoutHistory.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.history,
                            color: Colors.white24, size: 48),
                        SizedBox(height: 16),
                        Text('Nenhum treino registado ainda.',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _workoutHistory.length,
                    itemBuilder: (context, index) {
                      final workout = _workoutHistory[index];
                      final int exCount = (workout['exercises'] is List) ? (workout['exercises'] as List).length : 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1c1c1e),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    workout['name'] ?? 'Treino',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22c55e)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatDate(workout['dateIso']),
                                    style: const TextStyle(
                                        color: Color(0xFF22c55e),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(LucideIcons.dumbbell,
                                    color: Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Text('$exCount exercícios concluídos',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon,
      {Color color = const Color(0xFF22c55e)}) {
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
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
