import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';
import 'active_workout_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String _userName = 'Utilizador';
  String _userGoal = 'Geral';
  String _greeting = 'Olá';

  // Variáveis Dinâmicas
  final List<String> _daysOfWeek = [
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
    'Dom'
  ];
  String _todayStr = 'Seg';
  int _todayExerciseCount = 0;
  List<Map<String, dynamic>> _todayExercisesList = [];

  int _totalWorkouts = 0;
  int _weeklyWorkouts = 0;
  int _streak = 0;
  Set<String> _activeDaysThisWeek = {};

  @override
  void initState() {
    super.initState();
    _calculateGreeting();
    _loadData();
  }

  void _calculateGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = 'Bom dia';
    } else if (hour < 19) {
      _greeting = 'Boa tarde';
    } else {
      _greeting = 'Boa noite';
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime now = DateTime.now();
    _todayStr =
        _daysOfWeek[now.weekday - 1]; // weekday vai de 1 (Seg) a 7 (Dom)

    // 1. Carregar Perfil
    setState(() {
      _userName = prefs.getString('userName') ?? 'Utilizador';
      _userGoal = prefs.getString('userGoal') ?? 'Geral';
      if (_userName.trim().isEmpty) _userName = 'Utilizador';
    });

    // 2. Carregar o Treino de Hoje
    final String? savedWorkouts = prefs.getString('gym_workouts');
    if (savedWorkouts != null) {
      final Map<String, dynamic> decodedWorkouts = jsonDecode(savedWorkouts);
      if (decodedWorkouts[_todayStr] != null) {
        setState(() {
          _todayExercisesList =
              List<Map<String, dynamic>>.from(decodedWorkouts[_todayStr]);
          _todayExerciseCount = _todayExercisesList.length;
        });
      }
    }

    // 3. Carregar Histórico e Calcular Estatísticas
    final String? historyJson = prefs.getString('workout_history');
    if (historyJson != null) {
      List<dynamic> history = jsonDecode(historyJson);
      _calculateStats(history, now);
    }
  }

  void _calculateStats(List<dynamic> history, DateTime now) {
    int currentStreak = 0;
    int weekCount = 0;
    Set<String> activeDays = {};

    // Extrai todas as datas do histórico para um Set (mais rápido para pesquisar)
    Set<String> historyDates = history.map((w) => w['date'].toString()).toSet();

    // Calcula Início da Semana (Segunda-feira)
    DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));

    // Verifica a atividade desta semana (para as bolinhas e o contador)
    for (int i = 0; i < 7; i++) {
      DateTime day = startOfWeek.add(Duration(days: i));
      String dateStr =
          '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
      if (historyDates.contains(dateStr)) {
        activeDays.add(_daysOfWeek[i]);
        weekCount++;
      }
    }

    // Calcula a Sequência (Streak) olhando para os dias anteriores
    DateTime checkDate = now;
    while (true) {
      String checkStr =
          '${checkDate.day.toString().padLeft(2, '0')}/${checkDate.month.toString().padLeft(2, '0')}';
      if (historyDates.contains(checkStr)) {
        currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1)); // recua 1 dia
      } else {
        // Se não treinou hoje, mas treinou ontem, a streak ainda não quebrou
        if (currentStreak == 0 && checkDate.day == now.day) {
          checkDate = checkDate.subtract(const Duration(days: 1));
          String yesterdayStr =
              '${checkDate.day.toString().padLeft(2, '0')}/${checkDate.month.toString().padLeft(2, '0')}';
          if (historyDates.contains(yesterdayStr)) {
            currentStreak++;
            checkDate = checkDate.subtract(const Duration(days: 1));
            continue;
          }
        }
        break; // Quebrou a sequência
      }
    }

    setState(() {
      _totalWorkouts = history.length;
      _weeklyWorkouts = weekCount;
      _activeDaysThisWeek = activeDays;
      _streak = currentStreak;
    });
  }

  // --- FUNÇÃO DO POPUP DA IA ---
  Future<void> _showAiWorkoutDialog(BuildContext context) async {
    TextEditingController muscleController = TextEditingController();
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1c1c1e),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(LucideIcons.bot, color: Color(0xFF22c55e)),
                  SizedBox(width: 12),
                  Text('Treino Inteligente',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ],
              ),
              content: isLoading
                  ? const SizedBox(
                      height: 100,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF22c55e)),
                            SizedBox(height: 16),
                            Text('A gerar série ideal...',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  : TextField(
                      controller: muscleController,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'Ex: Peito, Costas, Pernas...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF0a0a0a),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
              actions: isLoading
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (muscleController.text.trim().isEmpty) return;

                          setState(() => isLoading = true);

                          try {
                            final exercises =
                                await AiWorkoutService.generateWorkout(
                                    muscleController.text);

                            if (!context.mounted) return;
                            Navigator.pop(context); // Fecha o popup

                            // Abre a tela de treino com o resultado
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ActiveWorkoutView(
                                  day:
                                      'IA: ${muscleController.text.trim().toUpperCase()}',
                                  exercises: exercises,
                                ),
                              ),
                            ).then((_) =>
                                _loadData()); // Atualiza estatísticas ao voltar
                          } catch (e) {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22c55e),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Gerar',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String initial =
        _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors
          .transparent, // Mantém a cor de fundo integrada com as abas inferiores
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
              bottom: 100.0), // Espaço para o menu inferior
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- CABEÇALHO ---
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_greeting, $_userName 👋',
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('Hora de treinar!',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5)),
                      ],
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF22c55e).withOpacity(0.2),
                      child: Text(initial,
                          style: const TextStyle(
                              color: Color(0xFF22c55e),
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ),
                  ],
                ),
              ),

              // --- ESTATÍSTICAS REAIS ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildStatCard(LucideIcons.flame, Colors.orange, '$_streak',
                        'SEQUÊNCIA'),
                    const SizedBox(width: 12),
                    _buildStatCard(LucideIcons.zap, const Color(0xFF22c55e),
                        '$_weeklyWorkouts', 'ESTA SEM.'),
                    const SizedBox(width: 12),
                    _buildStatCard(LucideIcons.trophy, Colors.amber,
                        '$_totalWorkouts', 'TOTAL'),
                  ],
                ),
              ),

              // --- ATIVIDADE DA SEMANA ---
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1c1c1e),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ATIVIDADE DA SEMANA',
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _daysOfWeek.map((day) {
                          bool isCompleted = _activeDaysThisWeek.contains(day);
                          bool isToday = day == _todayStr;

                          return Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isCompleted
                                      ? const Color(0xFF22c55e)
                                      : const Color(0xFF0a0a0a),
                                  shape: BoxShape.circle,
                                  border: isCompleted
                                      ? null
                                      : Border.all(
                                          color: isToday
                                              ? const Color(0xFF22c55e)
                                                  .withOpacity(0.5)
                                              : Colors.white.withOpacity(0.05),
                                          width: isToday ? 2 : 1),
                                  boxShadow: isCompleted
                                      ? [
                                          BoxShadow(
                                              color: const Color(0xFF22c55e)
                                                  .withOpacity(0.4),
                                              blurRadius: 8)
                                        ]
                                      : [],
                                ),
                                child: isCompleted
                                    ? const Icon(LucideIcons.check,
                                        color: Colors.black, size: 16)
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(day,
                                  style: TextStyle(
                                      color: isCompleted || isToday
                                          ? const Color(0xFF22c55e)
                                          : Colors.grey,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              // --- PLANO ATIVO (TREINO DE HOJE) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Plano Ativo',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14281d),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                            color: const Color(0xFF22c55e).withOpacity(0.2)),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FOCO: ${_userGoal.toUpperCase()}',
                                  style: const TextStyle(
                                      color: Color(0xFF22c55e),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5)),
                              const SizedBox(height: 8),
                              Text('Treino de $_todayStr',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(
                                  _todayExerciseCount > 0
                                      ? '$_todayExerciseCount exercícios planeados'
                                      : 'Dia de descanso planeado',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 14)),
                            ],
                          ),
                          if (_todayExerciseCount > 0)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ActiveWorkoutView(
                                        day: _todayStr,
                                        exercises: _todayExercisesList,
                                      ),
                                    ),
                                  ).then((_) => _loadData());
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22c55e),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: const Color(0xFF22c55e)
                                              .withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2)
                                    ],
                                  ),
                                  child: const Icon(LucideIcons.play,
                                      color: Colors.black, size: 28),
                                ),
                              ),
                            )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // --- BOTÃO FLUTUANTE DA INTELIGÊNCIA ARTIFICIAL ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAiWorkoutDialog(context),
        backgroundColor: const Color(0xFF22c55e),
        icon: const Icon(LucideIcons.sparkles, color: Colors.black),
        label: const Text('IA',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1c1c1e),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 6),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
