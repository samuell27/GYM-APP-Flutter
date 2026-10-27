import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/health_service.dart';
import '../widgets/animated_gym_icon.dart';
import 'ai_generation_view.dart'; 
import 'active_workout_view.dart';

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
  int _todayCalories = 0;

  bool _isHealthConnected = false;
  bool _isSyncingHealth = false;
  int _todaySteps = 0;
  
  final List<String> _daysOfWeek = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  List<bool> _weekActivity = List.filled(7, false);
  
  String _todayDayStr = '';
  String _todayWorkoutTitle = '';
  bool _hasWorkoutToday = false;
  List<Map<String, dynamic>> _todayExercises = [];

  @override
  void initState() {
    super.initState();
    _todayDayStr = _daysOfWeek[DateTime.now().weekday - 1];
    _todayWorkoutTitle = 'Treino de $_todayDayStr';
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
    _hasWorkoutToday = false;
    _todayExercises = [];
    _todayWorkoutTitle = 'Treino de $_todayDayStr';

    final String? workoutsJson = prefs.getString('gym_workouts_$uid');
    if (workoutsJson != null) {
      try {
        Map<String, dynamic> plans = jsonDecode(workoutsJson);

        // 1. Verifica se já existe treino na chave exata do dia da semana (Seg, Ter, Qua...)
        if (plans.containsKey(_todayDayStr) && plans[_todayDayStr] is List && (plans[_todayDayStr] as List).isNotEmpty) {
          _hasWorkoutToday = true;
          _todayExercises = List<Map<String, dynamic>>.from(plans[_todayDayStr]);
          final String? customTitle = prefs.getString('workout_title_${uid}_$_todayDayStr');
          if (customTitle != null && customTitle.isNotEmpty) {
            _todayWorkoutTitle = customTitle;
          }
        } else {
          // 2. Fallback: Se a IA salvou o treino com um nome personalizado (ex: "Treino de Peito - Máquina"),
          // pega o treino personalizado mais recente e planeia automaticamente para hoje!
          for (final entry in plans.entries.toList().reversed) {
            if (!_daysOfWeek.contains(entry.key) && entry.value is List && (entry.value as List).isNotEmpty) {
              _hasWorkoutToday = true;
              _todayWorkoutTitle = entry.key;
              _todayExercises = List<Map<String, dynamic>>.from(entry.value);
              
              // Sincroniza também na chave do dia de hoje para ficar fixo no plano
              plans[_todayDayStr] = entry.value;
              await prefs.setString('gym_workouts_$uid', jsonEncode(plans));
              await prefs.setString('workout_title_${uid}_$_todayDayStr', entry.key);
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Erro ao ler plano de hoje: $e');
      }
    }

    // --- VERIFICA CONEXÃO COM GOOGLE HEALTH E PASSOS ---
    _isHealthConnected = prefs.getBool('health_connected_$uid') ?? false;
    if (_isHealthConnected) {
      _todaySteps = await HealthService.getTodaySteps();
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  /// Abre a tela de Gerar Treino com IA e vincula automaticamente o treino gerado ao dia de hoje
  Future<void> _openAiGeneratorAndPlanForToday() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';
    final prefs = await SharedPreferences.getInstance();

    // Tira uma "fotografia" dos treinos antes de abrir a IA para descobrir o que foi gerado de novo
    Map<String, dynamic> beforePlans = {};
    final String? beforeJson = prefs.getString('gym_workouts_$uid');
    if (beforeJson != null) {
      try {
        beforePlans = Map<String, dynamic>.from(jsonDecode(beforeJson));
      } catch (_) {}
    }

    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiGenerationView()));

    // Ao voltar da tela de IA, verifica qual treino foi adicionado ou alterado e planeia para HOJE
    final String? afterJson = prefs.getString('gym_workouts_$uid');
    if (afterJson != null) {
      try {
        Map<String, dynamic> afterPlans = Map<String, dynamic>.from(jsonDecode(afterJson));
        String? newlyGeneratedKey;
        List<dynamic>? newlyGeneratedExercises;

        for (final entry in afterPlans.entries) {
          if (entry.value is List && (entry.value as List).isNotEmpty) {
            final beforeVal = jsonEncode(beforePlans[entry.key]);
            final afterVal = jsonEncode(entry.value);
            if (!beforePlans.containsKey(entry.key) || beforeVal != afterVal) {
              newlyGeneratedKey = entry.key;
              newlyGeneratedExercises = entry.value as List<dynamic>;
            }
          }
        }

        if (newlyGeneratedExercises != null && newlyGeneratedExercises.isNotEmpty) {
          afterPlans[_todayDayStr] = newlyGeneratedExercises;
          await prefs.setString('gym_workouts_$uid', jsonEncode(afterPlans));

          if (newlyGeneratedKey != null && !_daysOfWeek.contains(newlyGeneratedKey)) {
            await prefs.setString('workout_title_${uid}_$_todayDayStr', newlyGeneratedKey);
          } else {
            await prefs.remove('workout_title_${uid}_$_todayDayStr');
          }

          if (user != null) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .set({'workouts': afterPlans}, SetOptions(merge: true))
                .catchError((_) {});
          }
        }
      } catch (e) {
        debugPrint('Erro ao vincular treino gerado ao dia de hoje: $e');
      }
    }

    await _loadData();
  }

  Future<void> _connectOrSyncHealth() async {
    setState(() => _isSyncingHealth = true);
    
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';
    final prefs = await SharedPreferences.getInstance();

    final bool authorized = await HealthService.requestPermissions();
    if (authorized) {
      final int steps = await HealthService.getTodaySteps();
      await prefs.setBool('health_connected_$uid', true);
      
      if (mounted) {
        setState(() {
          _isHealthConnected = true;
          _todaySteps = steps;
          _isSyncingHealth = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Health conectado e sincronizado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() => _isSyncingHealth = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível conectar ao Google Health. Verifique o Health Connect.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _calculateStats(List<dynamic> history) {
    _totalWorkouts = history.length;
    _workoutsThisWeek = 0;
    _todayCalories = 0;
    
    final now = DateTime.now();
    final String todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    Set<String> historyDates = {};

    for (var w in history) {
      if (w is Map && w['dateIso'] != null) {
        final d = DateTime.tryParse(w['dateIso'].toString());
        if (d != null) {
          final String dStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          historyDates.add(dStr);

          if (dStr == todayStr) {
            int? wCal = int.tryParse(w['calories']?.toString() ?? '');
            if (wCal != null && wCal > 0) {
              _todayCalories += wCal;
            } else if (w['exercises'] is List) {
              int setsToday = 0;
              for (var ex in w['exercises']) {
                if (ex is Map && ex['sets'] is List) {
                  setsToday += (ex['sets'] as List).where((s) => s['isCompleted'] == true).length;
                }
              }
              _todayCalories += (setsToday * 8);
            }
          }
        }
      }
    }
    
    int currentWeekday = now.weekday;
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

    int currentStreak = 0;
    DateTime checkDate = now;
    String checkDateStr = todayStr;
    
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

  String _formatPlanTitle(String raw) {
    if (raw.toLowerCase().startsWith('treino')) return raw;
    return 'Treino de $raw';
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
                    backgroundColor: const Color(0xFF14281d),
                    radius: 24,
                    child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'U', 
                        style: const TextStyle(color: Color(0xFF22c55e), fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // --- ESTATÍSTICAS PRINCIPAIS ---
              Row(
                children: [
                  _buildStatCard(LucideIcons.flame, Colors.orange, _streak.toString(), 'SEQUÊNCIA', GymAnimationType.flame),
                  const SizedBox(width: 12),
                  _buildStatCard(LucideIcons.zap, const Color(0xFF22c55e), _workoutsThisWeek.toString(), 'ESTA SEM.', GymAnimationType.float),
                  const SizedBox(width: 12),
                  _buildStatCard(LucideIcons.trophy, Colors.amber, _totalWorkouts.toString(), 'TOTAL', GymAnimationType.float),
                ],
              ),
              const SizedBox(height: 16),

              // --- PAINEL DE ENERGIA DO DIA ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1c1c1e),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isHealthConnected 
                        ? const Color(0xFF22c55e).withOpacity(0.3) 
                        : Colors.white.withOpacity(0.05),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const AnimatedGymIcon(
                                  icon: LucideIcons.flame,
                                  color: Colors.orange,
                                  size: 22,
                                  type: GymAnimationType.flame,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'GASTO HOJE (IA)',
                                      style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_todayCalories kcal',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        Container(width: 1, height: 36, color: Colors.white10),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF14281d),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const AnimatedGymIcon(
                                  icon: LucideIcons.footprints,
                                  color: Color(0xFF22c55e),
                                  size: 22,
                                  type: GymAnimationType.float,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PASSOS HOJE',
                                      style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isHealthConnected ? '$_todaySteps' : '--',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            AnimatedGymIcon(
                              icon: LucideIcons.heartPulse,
                              color: _isHealthConnected ? const Color(0xFF22c55e) : Colors.grey,
                              size: 16,
                              type: GymAnimationType.heartbeat,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isHealthConnected ? 'Google Health Conectado' : 'Sincronizar com Google Health',
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        _isSyncingHealth
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Color(0xFF22c55e), strokeWidth: 2),
                              )
                            : SizedBox(
                                height: 32,
                                child: ElevatedButton(
                                  onPressed: _connectOrSyncHealth,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isHealthConnected ? const Color(0xFF14281d) : const Color(0xFF22c55e),
                                    foregroundColor: _isHealthConnected ? const Color(0xFF22c55e) : Colors.black,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text(
                                    _isHealthConnected ? 'Atualizar' : 'Conectar',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              
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
                  color: const Color(0xFF0d1f15),
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
                          Text('HOJE ($_todayDayStr) • FOCO: ${_userGoal.toUpperCase()}', 
                              style: const TextStyle(color: Color(0xFF22c55e), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 10),
                          Text(
                            _formatPlanTitle(_todayWorkoutTitle), 
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.8),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(_hasWorkoutToday ? '${_todayExercises.length} exercícios planeados para hoje' : 'Dia de descanso planeado', 
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
                        ],
                      ),
                    ),
                    
                    if (_hasWorkoutToday) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActiveWorkoutView(
                                day: _todayWorkoutTitle,
                                exercises: _todayExercises,
                              ),
                            ),
                          );
                          _loadData();
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
                  ],
                ),
              ),
              
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAiGeneratorAndPlanForToday,
        backgroundColor: const Color(0xFF22c55e),
        icon: const AnimatedGymIcon(
          icon: LucideIcons.sparkles,
          color: Colors.black,
          size: 22,
          type: GymAnimationType.sparkle,
        ),
        label: const Text('GERAR TREINO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, Color iconColor, String value, String label, GymAnimationType animType) {
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
                AnimatedGymIcon(
                  icon: icon,
                  color: iconColor,
                  size: 20,
                  type: animType,
                ),
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