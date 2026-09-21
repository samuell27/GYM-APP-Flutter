import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ai_generation_view.dart'; 
import 'active_workout_view.dart'; // <-- Adicionado para o atalho de treino

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool _isLoading = true;
  String _userName = 'Atleta';
  String _userGoal = 'HIPERTROFIA';
  
  int _totalWorkouts = 0;
  int _workoutsThisWeek = 0;
  int _streak = 0;
  
  // Array fixo de Segunda a Domingo
  final List<String> _daysOfWeek = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  List<bool> _weekActivity = List.filled(7, false);
  
  String _todayDayStr = '';
  bool _hasWorkoutToday = false;
  List<Map<String, dynamic>> _todayExercises = []; // <-- Guarda os exercícios de hoje

  @override
  void initState() {
    super.initState();
    _todayDayStr = _daysOfWeek[DateTime.now().weekday - 1];
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';
    final prefs = await SharedPreferences.getInstance();

    // --- BUSCA O NOME ---
    String? finalName = prefs.getString('userName') ?? prefs.getString('name');
    if (finalName == null || finalName.trim().isEmpty) {
      if (user != null && user.displayName != null && user.displayName!.trim().isNotEmpty) {
        finalName = user.displayName;
      }
    }
    if ((finalName == null || finalName.trim().isEmpty) && user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && doc.data()!.containsKey('name')) {
          finalName = doc.data()!['name'];
          await prefs.setString('userName', finalName!);
        }
      } catch (e) {
        debugPrint('Erro Firestore: $e');
      }
    }
    if (finalName == null || finalName.trim().isEmpty) {
      finalName = user?.email?.split('@').first ?? 'Atleta';
    }

    _userName = finalName;
    _userGoal = prefs.getString('userGoal') ?? 'HIPERTROFIA';

    // --- CARREGA O HISTÓRICO ISOLADO ---
    final String? historyJson = prefs.getString('workout_history_$uid');
    if (historyJson != null) {
      try {
        List<dynamic> history = jsonDecode(historyJson);
        _calculateStats(history);
      } catch (e) {
        debugPrint('Erro ao decodificar histórico: $e');
      }
    }

    // --- VERIFICA O TREINO DE HOJE ---
    final String? workoutsJson = prefs.getString('gym_workouts_$uid');
    if (workoutsJson != null) {
      try {
        Map<String, dynamic> plans = jsonDecode(workoutsJson);
        if (plans.containsKey(_todayDayStr) && plans[_todayDayStr] is List) {
          final dailyPlan = plans[_todayDayStr] as List;
          _hasWorkoutToday = dailyPlan.isNotEmpty;
          
          if (_hasWorkoutToday) {
            // Guarda a lista de exercícios para enviar para o atalho
            _todayExercises = List<Map<String, dynamic>>.from(dailyPlan);
          }
        }
      } catch (e) {
        debugPrint('Erro ao ler plano de hoje: $e');
      }
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  void _calculateStats(List<dynamic> history) {
    _totalWorkouts = history.length;
    _workoutsThisWeek = 0;
    
    Set<String> historyDates = history.map((w) {
      if (w is Map && w['dateIso'] != null) {
        final d = DateTime.tryParse(w['dateIso'].toString());
        if (d != null) return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      return '';
    }).where((s) => s.isNotEmpty).toSet();

    final now = DateTime.now();
    
    // 1. Calcula os dias da semana atual (Segunda a Domingo)
    int currentWeekday = now.weekday; // 1 = Seg, 7 = Dom
    DateTime monday = now.subtract(Duration(days: currentWeekday - 1));
    
    for (int i = 0; i < 7; i++) {
      DateTime day = monday.add(Duration(days: i));
      String dateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      
      if (historyDates.contains(dateStr)) {
        _weekActivity[i] = true;
        _workoutsThisWeek++;
      } else {
        _weekActivity[i] = false;
      }
    }

    // 2. Calcula a Sequência (Streak)
    int currentStreak = 0;
    DateTime checkDate = now;
    String checkDateStr = '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
    
    // Se não treinou hoje, começa a contar de ontem
    if (!historyDates.contains(checkDateStr)) {
      checkDate = checkDate.subtract(const Duration(days: 1));
      checkDateStr = '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
    }

    while (historyDates.contains(checkDateStr)) {
      currentStreak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
      checkDateStr = '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
    }
    
    _streak = currentStreak;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF22c55e)));

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- CABEÇALHO ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_getGreeting()}, ${_userName.split(' ').first} 👋', 
                            style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Hora de treinar!', 
                            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF14281d), // Verde muito escuro
                    radius: 24,
                    child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'U', 
                        style: const TextStyle(color: Color(0xFF22c55e), fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // --- ESTATÍSTICAS (3 CARDS) ---
              Row(
                children: [
                  _buildStatCard(LucideIcons.flame, Colors.orange, _streak.toString(), 'SEQUÊNCIA'),
                  const SizedBox(width: 12),
                  _buildStatCard(LucideIcons.zap, const Color(0xFF22c55e), _workoutsThisWeek.toString(), 'ESTA SEM.'),
                  const SizedBox(width: 12),
                  _buildStatCard(LucideIcons.trophy, Colors.amber, _totalWorkouts.toString(), 'TOTAL'),
                ],
              ),
              const SizedBox(height: 32),
              
              // --- ATIVIDADE DA SEMANA ---
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1c1c1e),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ATIVIDADE DA SEMANA', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        bool isActive = _weekActivity[index];
                        return Column(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isActive ? const Color(0xFF22c55e) : const Color(0xFF0a0a0a),
                                shape: BoxShape.circle,
                                boxShadow: isActive ? [
                                  BoxShadow(color: const Color(0xFF22c55e).withOpacity(0.4), blurRadius: 12, spreadRadius: 2)
                                ] : [],
                              ),
                              child: isActive ? const Icon(LucideIcons.check, color: Colors.black, size: 20) : null,
                            ),
                            const SizedBox(height: 12),
                            Text(_daysOfWeek[index], 
                                style: TextStyle(color: isActive ? const Color(0xFF22c55e) : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // --- PLANO ATIVO ---
              const Text('Plano Ativo', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0d1f15), // Fundo verde escuro estilo dashboard antigo
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FOCO: ${_userGoal.toUpperCase()}', 
                              style: const TextStyle(color: Color(0xFF22c55e), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          const SizedBox(height: 12),
                          Text('Treino de $_todayDayStr', 
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
                          const SizedBox(height: 8),
                          Text(_hasWorkoutToday ? '${_todayExercises.length} exercícios planeados' : 'Dia de descanso planeado', 
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
                        ],
                      ),
                    ),
                    
                    // --- BOTÃO DE PLAY (Só aparece se houver treino) ---
                    if (_hasWorkoutToday)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActiveWorkoutView(
                                day: _todayDayStr,
                                exercises: _todayExercises,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22c55e),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF22c55e).withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(LucideIcons.play, color: Colors.black, size: 28),
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 80), // Espaço para o botão flutuante não tapar o card
            ],
          ),
        ),
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AiGenerationView()));
        },
        backgroundColor: const Color(0xFF22c55e),
        icon: const Icon(LucideIcons.sparkles, color: Colors.black),
        label: const Text('GERAR TREINO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1c1c1e),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }
}