import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../models/workout.dart';

class ActiveWorkoutView extends StatefulWidget {
  final String day;
  final List<Map<String, dynamic>>
      exercises; // Mantém Map na entrada até refatorarmos a IA

  const ActiveWorkoutView(
      {super.key, required this.day, required this.exercises});

  @override
  State<ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends State<ActiveWorkoutView> {
  // Estado fortemente tipado
  List<Exercise> _activeExercises = [];

  // Timer de treino resistente a background
  Timer? _timer;
  int _elapsedSeconds = 0;
  DateTime? _resumeTime;
  int _secondsBeforePause = 0;
  bool _isPaused = false;
  bool _isSaving = false;

  // Timer de descanso resistente a background
  Timer? _restTimer;
  int _restTime = 0;
  DateTime? _restTargetTime;
  bool _isResting = false;
  int _preferredRestTime = 60;

  @override
  void initState() {
    super.initState();
    _initializeModels();
    _loadPreferredRestTime();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferredRestTime() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _preferredRestTime = prefs.getInt('preferred_rest_time') ?? 60;
    });
  }

  // Converte a entrada bruta da IA em objetos tipados
  void _initializeModels() {
    _activeExercises = widget.exercises.map((exMap) {
      int setsCount = int.tryParse(exMap['sets'].toString()) ?? 4;
      String repsStr = exMap['reps'].toString();
      int targetReps = int.tryParse(repsStr.split('-').last) ?? 10;
      int targetWeight = int.tryParse(exMap['load'].toString()) ?? 0;

      List<SetLog> sets = List.generate(
          setsCount,
          (index) => SetLog(
                weight: targetWeight,
                reps: targetReps,
                isCompleted: false,
              ));

      return Exercise(
        id: exMap['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: exMap['name']?.toString() ?? 'Exercício',
        sets: sets,
      );
    }).toList();
  }

  // Cronômetro baseado em delta de tempo real
  void _startTimer() {
    _resumeTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && _resumeTime != null) {
        setState(() {
          _elapsedSeconds = _secondsBeforePause +
              DateTime.now().difference(_resumeTime!).inSeconds;
        });
      }
    });
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _secondsBeforePause = _elapsedSeconds;
      } else {
        _resumeTime = DateTime.now();
      }
    });
  }

  // Descanso baseado em alvo de tempo futuro
  void _startRestTimer(int seconds) {
    _restTimer?.cancel();
    _restTargetTime = DateTime.now().add(Duration(seconds: seconds));

    setState(() {
      _restTime = seconds;
      _isResting = true;
    });

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (_restTargetTime != null && now.isBefore(_restTargetTime!)) {
        setState(() => _restTime = _restTargetTime!.difference(now).inSeconds);
      } else {
        timer.cancel();
        setState(() => _isResting = false);
        FlutterRingtonePlayer().playNotification();
      }
    });
  }

  void _removeExercise(String exId) {
    setState(() {
      _activeExercises.removeWhere((ex) => ex.id == exId);
    });
  }

  void _showAddExerciseDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController setsCtrl = TextEditingController(text: '4');
    TextEditingController repsCtrl = TextEditingController(text: '10');

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1c1c1e),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Adicionar Extra',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nome da Máquina/Exercício',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF0a0a0a),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: setsCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Séries',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF0a0a0a),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: repsCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Reps',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF0a0a0a),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) return;

                  int sets = int.tryParse(setsCtrl.text) ?? 4;
                  int reps = int.tryParse(repsCtrl.text) ?? 10;

                  setState(() {
                    _activeExercises.add(Exercise(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text.trim(),
                      sets: List.generate(
                          sets,
                          (index) => SetLog(
                              weight: 0, reps: reps, isCompleted: false)),
                    ));
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22c55e),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Adicionar',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              )
            ],
          );
        });
  }

  Future<void> _handleCancelButton() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1c1c1e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: Colors.orange),
              SizedBox(width: 12),
              Text('Atenção',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Deseja realmente cancelar o seu progresso? Tudo o que fez até agora será perdido.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar ao Treino',
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sim, cancelar',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _changeDefaultRestTime() async {
    int? newTime = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1c1c1e),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Definir Descanso',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _timeOption(30, '30 Segundos'),
                _timeOption(45, '45 Segundos'),
                _timeOption(60, '1 Minuto'),
                _timeOption(90, '1 Minuto e 30s'),
                _timeOption(120, '2 Minutos'),
              ],
            ),
          );
        });

    if (newTime != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('preferred_rest_time', newTime);
      setState(() => _preferredRestTime = newTime);
    }
  }

  Widget _timeOption(int seconds, String label) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: _preferredRestTime == seconds
          ? const Icon(LucideIcons.check, color: Color(0xFF22c55e))
          : null,
      onTap: () => Navigator.pop(context, seconds),
    );
  }

  String get _formattedTime {
    int m = _elapsedSeconds ~/ 60;
    int s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _formattedRestTime {
    int m = _restTime ~/ 60;
    int s = _restTime % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _toggleSet(Exercise exercise, int setIndex) {
    setState(() {
      bool isDone = exercise.sets[setIndex].isCompleted;
      exercise.sets[setIndex].isCompleted = !isDone;

      if (!isDone) {
        _startRestTimer(_preferredRestTime);
      }
    });
  }

  double get _progress {
    int total = 0;
    int completed = 0;
    for (var ex in _activeExercises) {
      total += ex.sets.length;
      completed += ex.sets.where((s) => s.isCompleted).length;
    }
    return total == 0 ? 0 : completed / total;
  }

  Future<void> _finishAndSaveWorkout() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Utilizador não autenticado.');

      List<Exercise> completedExercises = [];
      int totalVolume = 0;

      for (var ex in _activeExercises) {
        var completedSets = ex.sets.where((s) => s.isCompleted).toList();

        if (completedSets.isNotEmpty) {
          for (var set in completedSets) {
            totalVolume += (set.weight * set.reps);
          }
          completedExercises.add(Exercise(
            id: ex.id,
            name: ex.name,
            sets: completedSets,
            restSeconds: ex.restSeconds,
          ));
        }
      }

      if (completedExercises.isNotEmpty) {
        final session = WorkoutSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          dateIso: DateTime.now().toIso8601String(),
          name: 'Treino de ${widget.day}',
          exercises: completedExercises,
          userUid: user.uid,
        );

        // Firebase: Salva o objeto serializado de forma segura
        await FirebaseFirestore.instance
            .collection('workout_history')
            .add(session.toJson());

        // Cache local: Adiciona ao início da lista
        final prefs = await SharedPreferences.getInstance();
        final String? historyJson = prefs.getString('workout_history');
        List<dynamic> history =
            historyJson != null ? jsonDecode(historyJson) : [];
        history.insert(0, session.toJson());
        await prefs.setString('workout_history', jsonEncode(history));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Treino concluído com sucesso!'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao salvar: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Column(
          children: [
            // --- CABEÇALHO ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('EM ANDAMENTO',
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5)),
                            const SizedBox(height: 4),
                            Text('Treino de ${widget.day}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_formattedTime,
                                  style: TextStyle(
                                      color: _isPaused
                                          ? Colors.orange
                                          : const Color(0xFF22c55e),
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace')),
                              Text(_isPaused ? 'PAUSADO' : 'TEMPO',
                                  style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5)),
                            ],
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _togglePause,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _isPaused
                                    ? Colors.orange.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _isPaused
                                        ? Colors.orange.withOpacity(0.5)
                                        : Colors.transparent),
                              ),
                              child: Icon(
                                _isPaused
                                    ? LucideIcons.play
                                    : LucideIcons.pause,
                                color: _isPaused ? Colors.orange : Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: const Color(0xFF1c1c1e),
                        color: const Color(0xFF22c55e),
                        minHeight: 6),
                  ),
                ],
              ),
            ),

            // --- LISTA DE EXERCÍCIOS TIPADA ---
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ..._activeExercises.asMap().entries.map((entry) {
                    final exIndex = entry.key;
                    final ex = entry.value;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text('${exIndex + 1}. ${ex.name}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                icon: const Icon(LucideIcons.trash2,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () => _removeExercise(ex.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(ex.sets.length, (setIndex) {
                            final setLog = ex.sets[setIndex];
                            final isCompleted = setLog.isCompleted;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? const Color(0xFF22c55e).withOpacity(0.1)
                                    : const Color(0xFF1c1c1e),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: isCompleted
                                        ? const Color(0xFF22c55e)
                                            .withOpacity(0.5)
                                        : Colors.white.withOpacity(0.05)),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _toggleSet(ex, setIndex),
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? const Color(0xFF22c55e)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: isCompleted
                                                ? const Color(0xFF22c55e)
                                                : Colors.grey),
                                      ),
                                      child: isCompleted
                                          ? const Icon(LucideIcons.check,
                                              color: Colors.black, size: 20)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text('Série ${setIndex + 1}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  _buildMiniInput(
                                      'kg',
                                      setLog.weight.toString(),
                                      (val) => setLog.weight =
                                          int.tryParse(val) ?? 0),
                                  const SizedBox(width: 8),
                                  _buildMiniInput(
                                      'reps',
                                      setLog.reps.toString(),
                                      (val) =>
                                          setLog.reps = int.tryParse(val) ?? 0),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                  OutlinedButton.icon(
                    onPressed: _showAddExerciseDialog,
                    icon:
                        const Icon(LucideIcons.plus, color: Color(0xFF22c55e)),
                    label: const Text('ADICIONAR EXERCÍCIO',
                        style: TextStyle(
                            color: Color(0xFF22c55e),
                            fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                          color: const Color(0xFF22c55e).withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      backgroundColor:
                          const Color(0xFF22c55e).withOpacity(0.05),
                    ),
                  ),
                ],
              ),
            ),

            // --- BANNER DO TEMPORIZADOR DE DESCANSO ---
            if (_isResting)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1c1c1e),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF3b82f6).withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _changeDefaultRestTime,
                      child: const Row(
                        children: [
                          Icon(LucideIcons.settings,
                              color: Color(0xFF3b82f6), size: 20),
                          SizedBox(width: 8),
                          Text('Descanso',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_restTime > 15) {
                              _restTargetTime = _restTargetTime
                                  ?.subtract(const Duration(seconds: 15));
                              setState(() => _restTime -= 15);
                            }
                          },
                          child: const Icon(LucideIcons.minusSquare,
                              color: Colors.white54, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text(_formattedRestTime,
                            style: const TextStyle(
                                color: Color(0xFF3b82f6),
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace')),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            _restTargetTime = _restTargetTime
                                ?.add(const Duration(seconds: 15));
                            setState(() => _restTime += 15);
                          },
                          child: const Icon(LucideIcons.plusSquare,
                              color: Colors.white54, size: 24),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () {
                            _restTimer?.cancel();
                            setState(() => _isResting = false);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(LucideIcons.x,
                                color: Colors.white54, size: 20),
                          ),
                        )
                      ],
                    )
                  ],
                ),
              ),

            // --- BOTÕES FINAIS ---
            Padding(
              padding: const EdgeInsets.only(
                  left: 24, right: 24, bottom: 24, top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _handleCancelButton,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                            color: _isSaving ? Colors.grey : Colors.redAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('CANCELAR',
                          style: TextStyle(
                              color: _isSaving ? Colors.grey : Colors.redAccent,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _finishAndSaveWorkout,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF22c55e),
                        disabledBackgroundColor:
                            const Color(0xFF22c55e).withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('CONCLUIR TREINO',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInput(
      String hint, String initial, Function(String) onChanged) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: const Color(0xFF0a0a0a),
          borderRadius: BorderRadius.circular(8)),
      child: TextFormField(
        initialValue: initial,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 10),
            border: InputBorder.none),
        onChanged: onChanged,
      ),
    );
  }
}
