import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import '../services/ai_service.dart';
import '../services/health_service.dart';
import '../widgets/animated_gym_icon.dart';
import '../widgets/exercise_media_preview.dart';

class ActiveSet {
  bool isCompleted;
  double weight;
  int reps;
  ActiveSet({required this.isCompleted, required this.weight, required this.reps});
}

class ActiveExercise {
  String name;
  List<ActiveSet> sets;
  int restSeconds;
  bool showMedia;
  int swapVersion; // Garante a atualização dos campos de peso ao trocar de exercício

  ActiveExercise({
    required this.name,
    required this.sets,
    required this.restSeconds,
    this.showMedia = true,
    this.swapVersion = 0,
  });
}

class ActiveWorkoutView extends StatefulWidget {
  final String day;
  final List<dynamic> exercises; 

  const ActiveWorkoutView({
    super.key,
    required this.day,
    required this.exercises,
  });

  @override
  State<ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends State<ActiveWorkoutView> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<ActiveExercise> _activeExercises = [];
  
  late final DateTime _workoutStartTime;

  // --- 1. CRONÓMETRO GERAL DO TREINO ---
  Timer? _workoutTimer;
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isWorkoutPaused = ValueNotifier<bool>(false);

  // --- 2. TEMPORIZADOR DE DESCANSO ---
  Timer? _restTimer;
  final ValueNotifier<int> _restTime = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isResting = ValueNotifier<bool>(false);
  DateTime? _restTargetTime;

  String get _formattedHeaderTitle {
    final raw = widget.day.trim();
    if (raw.toLowerCase().startsWith('treino')) {
      return raw;
    }
    return 'Treino de $raw';
  }

  @override
  void initState() {
    super.initState();
    _workoutStartTime = DateTime.now();
    _startWorkoutStopwatch();
    _initializeWorkout();
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _restTimer?.cancel();
    _elapsedSeconds.dispose();
    _isWorkoutPaused.dispose();
    _restTime.dispose();
    _isResting.dispose();
    super.dispose();
  }

  void _startWorkoutStopwatch() {
    _workoutTimer?.cancel();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isWorkoutPaused.value) {
        _elapsedSeconds.value++;
      }
    });
  }

  void _toggleWorkoutPause() {
    _isWorkoutPaused.value = !_isWorkoutPaused.value;
  }

  Future<void> _initializeWorkout() async {
    for (var ex in widget.exercises) {
      int setsCount = int.tryParse(ex['sets']?.toString() ?? '4') ?? 4;
      int restSecs = int.tryParse(ex['rest']?.toString() ?? '60') ?? 60;
      double load = double.tryParse(ex['load']?.toString() ?? '0') ?? 0;
      
      int reps = 10;
      String repsStr = ex['reps']?.toString() ?? '10';
      if (repsStr.contains('-')) {
        reps = int.tryParse(repsStr.split('-')[0]) ?? 10;
      } else {
        reps = int.tryParse(repsStr) ?? 10;
      }

      List<ActiveSet> activeSets = List.generate(
        setsCount, 
        (index) => ActiveSet(isCompleted: false, weight: load, reps: reps)
      );
      
      _activeExercises.add(ActiveExercise(
        name: ex['name']?.toString() ?? 'Exercício',
        sets: activeSets,
        restSeconds: restSecs,
        showMedia: true,
      ));
    }

    await _loadHistoryAndPreFill();
    await _saveAsPlannedWorkoutForToday();
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Salva os exercícios atuais (incluindo trocas e adições) no Plano Ativo de hoje
  Future<void> _saveAsPlannedWorkoutForToday() async {
    if (_activeExercises.isEmpty && widget.exercises.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'default';

      const List<String> daysOfWeek = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
      final String todayDayStr = daysOfWeek[DateTime.now().weekday - 1];

      Map<String, dynamic> plans = {};
      final String? workoutsJson = prefs.getString('gym_workouts_$uid');
      if (workoutsJson != null) {
        try {
          plans = Map<String, dynamic>.from(jsonDecode(workoutsJson));
        } catch (_) {}
      }

      final List<Map<String, dynamic>> exercisesToSave = _activeExercises.isNotEmpty
          ? _activeExercises.map((ex) => {
                'name': ex.name,
                'sets': ex.sets.length.toString(),
                'reps': ex.sets.isNotEmpty ? ex.sets.first.reps.toString() : '10',
                'load': ex.sets.isNotEmpty
                    ? ex.sets.first.weight.toString().replaceAll('.0', '')
                    : '0',
                'rest': ex.restSeconds.toString(),
              }).toList()
          : List<Map<String, dynamic>>.from(
              widget.exercises.map((e) => Map<String, dynamic>.from(e as Map)),
            );

      plans[todayDayStr] = exercisesToSave;
      await prefs.setString('gym_workouts_$uid', jsonEncode(plans));
      await prefs.setString('workout_title_${uid}_$todayDayStr', _formattedHeaderTitle);

      if (user != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'workouts': plans}, SetOptions(merge: true))
            .catchError((_) {});
      }
    } catch (e) {
      debugPrint('Erro ao salvar treino no plano de hoje: $e');
    }
  }

  Future<void> _cancelAndSaveForLater() async {
    _workoutTimer?.cancel();
    _restTimer?.cancel();
    await _saveAsPlannedWorkoutForToday();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Treino salvo no Plano Ativo para fazer mais tarde!'),
          backgroundColor: Color(0xFF22c55e),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _loadHistoryAndPreFill() async {
    for (var activeEx in _activeExercises) {
      await _loadHistoryForSingleExercise(activeEx);
    }
  }

  /// Busca no histórico a última carga e repetições usadas para um exercício específico
  Future<bool> _loadHistoryForSingleExercise(ActiveExercise activeEx) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';

    final String? savedData = prefs.getString('workout_history_$uid');
    if (savedData == null) return false;

    try {
      List<dynamic> history = jsonDecode(savedData);
      final targetName = activeEx.name.trim().toLowerCase();

      for (var workout in history) {
        if (workout['exercises'] != null) {
          for (var pastEx in workout['exercises']) {
            final pastName = (pastEx['name'] ?? '').toString().trim().toLowerCase();
            if (pastName == targetName && pastEx['sets'] != null) {
              List<dynamic> pastSets = pastEx['sets'];
              for (int i = 0; i < activeEx.sets.length && i < pastSets.length; i++) {
                activeEx.sets[i].weight = double.tryParse(pastSets[i]['weight']?.toString() ?? '0') ?? 0;
                activeEx.sets[i].reps = int.tryParse(pastSets[i]['reps']?.toString() ?? '10') ?? 10;
              }
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao extrair histórico do exercício: $e');
    }
    return false;
  }

  // --- 3. SUGESTÕES INTELIGENTES DE SUBSTITUIÇÃO (IA + FALLBACK INSTANTÂNEO) ---
  List<String> _getInstantFallbackAlternatives(String currentName) {
    final pt = currentName.toLowerCase();
    if (pt.contains('supino') && pt.contains('inclinado')) {
      return ['Supino Inclinado com Halteres', 'Supino Inclinado na Máquina', 'Supino Inclinado no Smith', 'Crossover Polia Baixa'];
    }
    if (pt.contains('supino')) {
      return ['Supino Reto com Halteres', 'Supino Reto na Máquina', 'Supino Reto com Barra', 'Crossover Polia Média'];
    }
    if (pt.contains('voador') || pt.contains('crucifixo') || pt.contains('crossover')) {
      return ['Crucifixo com Halteres', 'Voador (Peck Deck)', 'Crossover Polia Alta', 'Flexão de Braços'];
    }
    if (pt.contains('puxada')) {
      return ['Puxada Frontal Aberta', 'Puxada com Triângulo', 'Puxada Supinada', 'Barra Fixa'];
    }
    if (pt.contains('remada')) {
      return ['Remada Baixa no Triângulo', 'Remada Unilateral (Serrote)', 'Remada Máquina Articulada', 'Remada Curvada com Barra'];
    }
    if (pt.contains('scott') || pt.contains('rosca') || pt.contains('martelo')) {
      return ['Rosca Scott na Máquina', 'Rosca Direta na Polia', 'Rosca Alternada com Halteres', 'Rosca Martelo com Halteres'];
    }
    if (pt.contains('tríceps') || pt.contains('triceps')) {
      return ['Tríceps Corda na Polia', 'Tríceps Barra Reta na Polia', 'Tríceps Testa com Halteres', 'Tríceps Francês'];
    }
    if (pt.contains('desenvolvimento') || pt.contains('elevação') || pt.contains('ombro')) {
      return ['Desenvolvimento com Halteres', 'Desenvolvimento na Máquina', 'Elevação Lateral com Halteres', 'Elevação Lateral na Polia'];
    }
    if (pt.contains('leg press') || pt.contains('agachamento') || pt.contains('hack')) {
      return ['Leg Press 45', 'Agachamento no Hack', 'Agachamento no Smith', 'Passada com Halteres'];
    }
    if (pt.contains('extensora')) {
      return ['Cadeira Extensora Unilateral', 'Agachamento no Hack', 'Leg Press 45', 'Afundo com Halteres'];
    }
    if (pt.contains('flexora') || pt.contains('stiff')) {
      return ['Mesa Flexora', 'Cadeira Flexora', 'Stiff com Halteres', 'Stiff com Barra'];
    }
    return [
      'Supino Reto com Halteres',
      'Puxada Frontal na Polia',
      'Desenvolvimento com Halteres',
      'Rosca Direta na Polia',
    ];
  }

  Future<List<String>> _fetchAiAlternatives(String exerciseName) async {
    final fallback = _getInstantFallbackAlternatives(exerciseName)
        .where((e) => e.toLowerCase() != exerciseName.trim().toLowerCase())
        .toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('apiKey') ?? '';
      String model = prefs.getString('geminiModel') ?? 'gemini-2.5-flash';
      if (apiKey.trim().isEmpty) return fallback;

      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${apiKey.trim()}');
      final prompt = '''
      O utilizador está no ginásio e o aparelho do exercício "$exerciseName" está ocupado.
      Sugere exatamente 4 exercícios substitutos equivalentes que trabalhem o mesmo músculo principal usando outros equipamentos (ex: halteres, polia/cabo, barra livre ou outra máquina).
      Responde APENAS com os 4 nomes em Português separados por ponto e vírgula (;), sem numeração e sem explicações.
      Exemplo: Supino Reto com Halteres; Crossover na Polia Média; Supino no Smith; Voador Máquina
      ''';

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": prompt}]}],
          "generationConfig": {"temperature": 0.3}
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String raw = data['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '';
        final List<String> parsed = raw
            .split(';')
            .map((s) => s.replaceAll('\n', '').trim())
            .where((s) => s.isNotEmpty && s.toLowerCase() != exerciseName.trim().toLowerCase())
            .toList();
        if (parsed.isNotEmpty) return parsed.take(4).toList();
      }
    } catch (_) {}

    return fallback;
  }

  /// Modal para Trocar/Substituir um exercício quando a máquina estiver ocupada
  Future<void> _showSwapExerciseModal(int index) async {
    final currentEx = _activeExercises[index];
    final TextEditingController customNameCtrl = TextEditingController(text: currentEx.name);

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1c1c1e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 24.0,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24.0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.arrowLeftRight, color: Color(0xFF22c55e), size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Trocar Exercício',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.grey),
                      onPressed: () => Navigator.pop(modalContext),
                    ),
                  ],
                ),
                Text(
                  'Aparelho ocupado? Escolha um substituto para "${currentEx.name}" ou digite abaixo:',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),

                // Campo para digitar qualquer nome manualmente
                TextField(
                  controller: customNameCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Nome do novo exercício',
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF0a0a0a),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(LucideIcons.check, color: Color(0xFF22c55e)),
                      onPressed: () {
                        if (customNameCtrl.text.trim().isNotEmpty) {
                          Navigator.pop(modalContext, customNameCtrl.text.trim());
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: const [
                    AnimatedGymIcon(
                      icon: LucideIcons.sparkles,
                      color: Color(0xFF22c55e),
                      size: 16,
                      type: GymAnimationType.sparkle,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'SUGESTÕES EQUIVALENTES (IA)',
                      style: TextStyle(color: Color(0xFF22c55e), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                FutureBuilder<List<String>>(
                  future: _fetchAiAlternatives(currentEx.name),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF22c55e), strokeWidth: 2)),
                      );
                    }
                    final suggestions = snapshot.data ?? _getInstantFallbackAlternatives(currentEx.name);

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suggestions.map((suggestion) {
                        return ActionChip(
                          backgroundColor: const Color(0xFF14281d),
                          side: BorderSide(color: const Color(0xFF22c55e).withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          label: Text(
                            suggestion,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => Navigator.pop(modalContext, suggestion),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (customNameCtrl.text.trim().isNotEmpty) {
                        Navigator.pop(modalContext, customNameCtrl.text.trim());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22c55e),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'CONFIRMAR TROCA',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((selectedNewName) async {
      if (selectedNewName != null && selectedNewName is String && selectedNewName.trim().isNotEmpty) {
        final cleanName = selectedNewName.trim();
        if (cleanName.toLowerCase() == currentEx.name.trim().toLowerCase()) return;

        setState(() {
          currentEx.name = cleanName;
          currentEx.swapVersion++;
          for (var s in currentEx.sets) {
            s.isCompleted = false;
            s.weight = 0;
          }
        });

        // Se o utilizador já fez esse exercício substituto no passado, puxa o peso do histórico!
        await _loadHistoryForSingleExercise(currentEx);
        if (mounted) {
          setState(() => currentEx.swapVersion++);
        }
        await _saveAsPlannedWorkoutForToday();
      }
    });
  }

  /// Modal para Adicionar um Novo Exercício durante o treino em andamento
  Future<void> _showAddExerciseModal() async {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController setsCtrl = TextEditingController(text: '4');
    final TextEditingController repsCtrl = TextEditingController(text: '10');
    final TextEditingController restCtrl = TextEditingController(text: '60');

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1c1c1e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 24.0,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24.0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.plusCircle, color: Color(0xFF22c55e), size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Adicionar Exercício ao Treino',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.grey),
                      onPressed: () => Navigator.pop(modalContext),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Nome do exercício (ex: Supino com Halteres)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF0a0a0a),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: setsCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Séries',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0a0a0a),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: repsCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Reps',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0a0a0a),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: restCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Descanso (s)',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0a0a0a),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (nameCtrl.text.trim().isEmpty) return;
                      Navigator.pop(modalContext, {
                        'name': nameCtrl.text.trim(),
                        'sets': int.tryParse(setsCtrl.text) ?? 4,
                        'reps': int.tryParse(repsCtrl.text) ?? 10,
                        'rest': int.tryParse(restCtrl.text) ?? 60,
                      });
                    },
                    icon: const Icon(LucideIcons.plus, color: Colors.black, size: 18),
                    label: const Text(
                      'ADICIONAR AGORA',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22c55e),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((result) async {
      if (result != null && result is Map<String, dynamic>) {
        final int setsCount = result['sets'] as int;
        final int repsCount = result['reps'] as int;
        final int restSecs = result['rest'] as int;

        final newEx = ActiveExercise(
          name: result['name'].toString(),
          sets: List.generate(
            setsCount,
            (_) => ActiveSet(isCompleted: false, weight: 0, reps: repsCount),
          ),
          restSeconds: restSecs,
          showMedia: true,
        );

        await _loadHistoryForSingleExercise(newEx);

        if (mounted) {
          setState(() {
            _activeExercises.add(newEx);
          });
        }
        await _saveAsPlannedWorkoutForToday();
      }
    });
  }

  void _startRestTimer(int seconds) {
    _restTimer?.cancel();
    
    _isResting.value = true;
    _restTime.value = seconds;
    _restTargetTime = DateTime.now().add(Duration(seconds: seconds));

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (_restTargetTime != null && now.isBefore(_restTargetTime!)) {
        _restTime.value = _restTargetTime!.difference(now).inSeconds;
      } else {
        timer.cancel();
        _isResting.value = false;
        
        Vibration.hasVibrator().then((hasVibrator) {
          if (hasVibrator == true) {
            Vibration.vibrate(pattern: [0, 1000, 500, 1000]);
          }
        });

        FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          ios: IosSounds.glass,
          asAlarm: true, 
          volume: 1.0,
        );

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF22c55e),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Center(
                child: AnimatedGymIcon(
                  icon: LucideIcons.bellRing,
                  color: Colors.black,
                  size: 48,
                  type: GymAnimationType.flame,
                ),
              ),
              content: const Text(
                'DESCANSO CONCLUÍDO!', 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      FlutterRingtonePlayer().stop();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('BORA PRA SÉRIE!', style: TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                )
              ],
            )
          );
        }
      }
    });
  }

  void _addRestSeconds(int extraSeconds) {
    if (_restTargetTime != null && _isResting.value) {
      _restTargetTime = _restTargetTime!.add(Duration(seconds: extraSeconds));
      _restTime.value = _restTargetTime!.difference(DateTime.now()).inSeconds;
    }
  }

  Future<void> _showAiExerciseHelp(String exerciseName) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1c1c1e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return FutureBuilder<String>(
          future: AiWorkoutService.explainExercise(exerciseName),
          builder: (context, snapshot) {
            final youtubeLink = 'https://www.youtube.com/results?search_query=como+executar+${exerciseName.replaceAll(' ', '+')}';

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24.0, right: 24.0, top: 24.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AnimatedGymIcon(
                        icon: LucideIcons.sparkles,
                        color: Color(0xFF22c55e),
                        size: 24,
                        type: GymAnimationType.sparkle,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Como executar: $exerciseName',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),

                  ExerciseMediaPreview(
                    exerciseName: exerciseName,
                    height: 210,
                  ),
                  const SizedBox(height: 16),
                  
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF22c55e))),
                    )
                  else if (snapshot.hasError)
                    const Text('Não foi possível carregar a dica textual.', style: TextStyle(color: Colors.redAccent))
                  else
                    Text(
                      snapshot.data ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                    ),
                  
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  
                  const Text('Ver vídeo completo no YouTube:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                    child: SelectableText(
                      youtubeLink,
                      style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Copie o link acima para colar no navegador ou no YouTube.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _finishWorkout() async {
    if (_isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';
    
    List<Map<String, dynamic>> finalExercises = [];

    for (var ex in _activeExercises) {
      List<Map<String, dynamic>> finalSets = [];
      for (var set in ex.sets) {
        finalSets.add({
          'isCompleted': set.isCompleted,
          'weight': set.weight,
          'reps': set.reps,
        });
      }
      
      if (finalSets.any((s) => s['isCompleted'] == true)) {
        finalExercises.add({
          'name': ex.name,
          'sets': finalSets,
        });
      }
    }

    if (finalExercises.isEmpty) {
      await _cancelAndSaveForLater();
      return;
    }

    setState(() => _isSaving = true);
    _workoutTimer?.cancel();
    _restTimer?.cancel();

    try {
      await _saveAsPlannedWorkoutForToday();

      final DateTime endTime = DateTime.now();
      int durationMinutes = _elapsedSeconds.value ~/ 60;
      if (durationMinutes < 1) durationMinutes = 1;

      final int estimatedCalories = await AiWorkoutService.estimateWorkoutCalories(
        completedExercises: finalExercises,
        durationMinutes: durationMinutes,
      );

      final workoutData = {
        'name': _formattedHeaderTitle,
        'dateIso': endTime.toIso8601String(),
        'userUid': uid,
        'calories': estimatedCalories,
        'durationMinutes': durationMinutes,
        'exercises': finalExercises,
      };

      final prefs = await SharedPreferences.getInstance();
      List<dynamic> history = [];
      final String? savedData = prefs.getString('workout_history_$uid');
      if (savedData != null) history = jsonDecode(savedData);
      
      history.insert(0, workoutData);
      await prefs.setString('workout_history_$uid', jsonEncode(history));

      await FirebaseFirestore.instance.collection('workout_history').add(workoutData);

      final bool syncedHealth = await HealthService.saveWorkout(
        title: '$_formattedHeaderTitle - GymTracker',
        startTime: _workoutStartTime,
        endTime: endTime,
        caloriesBurned: estimatedCalories,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncedHealth 
                  ? 'Treino salvo! Gasto estimado pela IA: $estimatedCalories kcal 🔥 (Sincronizado)' 
                  : 'Treino salvo! Gasto estimado pela IA: $estimatedCalories kcal 🔥',
            ),
            backgroundColor: Colors.green,
          )
        );
        Navigator.pop(context);
      }
    } catch(e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0a0a0a),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF22c55e))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0a0a0a),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EM ANDAMENTO', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text(
                          _formattedHeaderTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.8),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  ValueListenableBuilder<bool>(
                    valueListenable: _isWorkoutPaused,
                    builder: (context, isPaused, child) {
                      return Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ValueListenableBuilder<int>(
                                valueListenable: _elapsedSeconds,
                                builder: (context, elapsed, child) {
                                  return Text(
                                    _formatTime(elapsed),
                                    style: TextStyle(
                                      color: isPaused ? Colors.orange : const Color(0xFF22c55e),
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      height: 1.0,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isPaused ? 'PAUSADO' : 'TEMPO',
                                style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _toggleWorkoutPause,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1c1c1e),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isPaused ? LucideIcons.play : LucideIcons.pause,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                ],
              ),
            ),

            // --- BARRA DE DESCANSO ATIVO ---
            ValueListenableBuilder<bool>(
              valueListenable: _isResting,
              builder: (context, isResting, child) {
                if (!isResting) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  color: const Color(0xFF14281d),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const AnimatedGymIcon(
                            icon: LucideIcons.timer,
                            color: Color(0xFF22c55e),
                            size: 18,
                            type: GymAnimationType.heartbeat,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'DESCANSO: ',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          ValueListenableBuilder<int>(
                            valueListenable: _restTime,
                            builder: (context, restSecs, child) {
                              return Text(
                                _formatTime(restSecs),
                                style: const TextStyle(color: Color(0xFF22c55e), fontSize: 16, fontWeight: FontWeight.w900),
                              );
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _addRestSeconds(15),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('+15s', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              _restTimer?.cancel();
                              _isResting.value = false;
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.black26,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Pular', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            
            // --- LISTA DE EXERCÍCIOS + BOTÃO DE ADICIONAR EXERCÍCIO ---
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: _activeExercises.length + 1,
                itemBuilder: (context, index) {
                  // Último item da lista: Botão de Adicionar Novo Exercício
                  if (index == _activeExercises.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                      child: OutlinedButton.icon(
                        onPressed: _showAddExerciseModal,
                        icon: const Icon(LucideIcons.plusCircle, color: Color(0xFF22c55e), size: 20),
                        label: const Text(
                          'ADICIONAR EXERCÍCIO AO TREINO',
                          style: TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: const Color(0xFF22c55e).withOpacity(0.5), width: 1.5),
                          backgroundColor: const Color(0xFF14281d).withOpacity(0.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    );
                  }

                  final ex = _activeExercises[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showSwapExerciseModal(index),
                                child: Text(
                                  '${index + 1}. ${ex.name}',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            // BOTÃO DE TROCAR EXERCÍCIO (MÁQUINA OCUPADA)
                            IconButton(
                              icon: const Icon(LucideIcons.arrowLeftRight, color: Colors.amber, size: 20),
                              tooltip: 'Trocar exercício',
                              onPressed: () => _showSwapExerciseModal(index),
                            ),
                            IconButton(
                              icon: Icon(
                                ex.showMedia ? LucideIcons.eyeOff : LucideIcons.video,
                                color: ex.showMedia ? Colors.grey : const Color(0xFF22c55e),
                                size: 20,
                              ),
                              tooltip: ex.showMedia ? 'Ocultar demonstração' : 'Ver demonstração',
                              onPressed: () {
                                setState(() => ex.showMedia = !ex.showMedia);
                              },
                            ),
                            IconButton(
                              icon: const AnimatedGymIcon(
                                icon: LucideIcons.sparkles,
                                color: Color(0xFF22c55e),
                                size: 22,
                                type: GymAnimationType.sparkle,
                              ),
                              tooltip: 'Como fazer?',
                              onPressed: () => _showAiExerciseHelp(ex.name),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                setState(() => _activeExercises.removeAt(index));
                                _saveAsPlannedWorkoutForToday();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (ex.showMedia) ...[
                          ExerciseMediaPreview(
                            key: ValueKey('media_${ex.name}_${ex.swapVersion}'),
                            exerciseName: ex.name,
                            height: 185,
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        ...ex.sets.asMap().entries.map((entry) {
                          final setIndex = entry.key;
                          final setItem = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: setItem.isCompleted ? const Color(0xFF14281d) : const Color(0xFF1c1c1e),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: setItem.isCompleted ? const Color(0xFF22c55e).withOpacity(0.5) : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() => setItem.isCompleted = !setItem.isCompleted);
                                    if (setItem.isCompleted) {
                                      FocusScope.of(context).unfocus();
                                      _startRestTimer(ex.restSeconds);
                                    }
                                  },
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: setItem.isCompleted ? const Color(0xFF22c55e) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: setItem.isCompleted ? const Color(0xFF22c55e) : Colors.grey),
                                    ),
                                    child: setItem.isCompleted ? const Icon(LucideIcons.check, color: Colors.black, size: 16) : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text('Série ${setIndex + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                Container(
                                  width: 60,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(color: const Color(0xFF0a0a0a), borderRadius: BorderRadius.circular(8)),
                                  child: TextFormField(
                                    key: ValueKey('w_${index}_${setIndex}_${ex.swapVersion}'),
                                    initialValue: setItem.weight.toString().replaceAll('.0', ''),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                                    onChanged: (val) => setItem.weight = double.tryParse(val) ?? 0,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 60,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(color: const Color(0xFF0a0a0a), borderRadius: BorderRadius.circular(8)),
                                  child: TextFormField(
                                    key: ValueKey('r_${index}_${setIndex}_${ex.swapVersion}'),
                                    initialValue: setItem.reps.toString(),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                                    onChanged: (val) => setItem.reps = int.tryParse(val) ?? 0,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                ex.sets.add(ActiveSet(
                                  isCompleted: false, 
                                  weight: ex.sets.isNotEmpty ? ex.sets.last.weight : 0, 
                                  reps: ex.sets.isNotEmpty ? ex.sets.last.reps : 10
                                ));
                              });
                            },
                            icon: const Icon(LucideIcons.plusCircle, color: Color(0xFF22c55e), size: 18),
                            label: const Text('Adicionar Série', style: TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // --- RODAPÉ COM BOTÕES DE AÇÃO ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0a0a0a),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _cancelAndSaveForLater,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('CANCELAR', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _finishWorkout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22c55e),
                        disabledBackgroundColor: const Color(0xFF14281d),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Color(0xFF22c55e), strokeWidth: 2),
                                ),
                                SizedBox(width: 10),
                                Text('CALCULANDO KCAL...', style: TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.w900, fontSize: 13)),
                              ],
                            )
                          : const Text('CONCLUIR TREINO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
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
}