import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <-- Necessário para identificar o utilizador atual
import 'package:image_picker/image_picker.dart';
import '../services/ai_service.dart';
import 'active_workout_view.dart';
import 'ai_generation_view.dart';

class WorkoutsView extends StatefulWidget {
  const WorkoutsView({super.key});

  @override
  State<WorkoutsView> createState() => _WorkoutsViewState();
}

class _WorkoutsViewState extends State<WorkoutsView> {
  final List<String> _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  late String _selectedDay;

  Map<String, List<Map<String, dynamic>>> _workouts = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _days[DateTime.now().weekday - 1];
    _loadWorkouts();
  }

  // --- CARREGAMENTO SEGURO (Isolado por UID) ---
  Future<void> _loadWorkouts() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Puxa o utilizador atual
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';
    
    // A chave agora é única por utilizador
    final String? savedData = prefs.getString('gym_workouts_$uid');

    if (savedData != null) {
      final Map<String, dynamic> decodedData = jsonDecode(savedData);
      setState(() {
        _workouts = decodedData.map((key, value) =>
            MapEntry(key, List<Map<String, dynamic>>.from(value)));
      });
    } else {
      setState(() {
        for (var day in _days) {
          _workouts[day] = [];
        }
      });
    }
  }

  // --- GRAVAÇÃO SEGURA (Isolada por UID) ---
  Future<void> _saveWorkouts() async {
    final prefs = await SharedPreferences.getInstance();
    
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'default';
    
    // Salva na chave única do utilizador
    await prefs.setString('gym_workouts_$uid', jsonEncode(_workouts));
  }

  void _addExercise() {
    setState(() {
      _workouts[_selectedDay] ??= [];
      _workouts[_selectedDay]!.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': '',
        'sets': '4',
        'reps': '10-12',
        'rest': '60',
        'load': '0',
      });
    });
    _saveWorkouts();
  }

  void _removeExercise(String id) {
    setState(() {
      _workouts[_selectedDay]?.removeWhere((ex) => ex['id'] == id);
    });
    _saveWorkouts();
  }

  void _updateExercise(String id, String field, String value) {
    final index = _workouts[_selectedDay]?.indexWhere((ex) => ex['id'] == id);
    if (index != null && index != -1) {
      setState(() {
        _workouts[_selectedDay]![index][field] = value;
      });
      _saveWorkouts();
    }
  }

  // --- NOVA FUNÇÃO: LER FICHA POR FOTO/PDF ---
  Future<void> _importFromImage(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    
    // Abre a galeria (também pode ser alterado para ImageSource.camera se quiser direto a câmera)
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image == null) return;
    if (!context.mounted) return;

    // Mostra um indicador de carregamento bloqueante enquanto a IA processa
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF22c55e)),
            SizedBox(height: 16),
            Text('A ler ficha...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ],
        )
      ),
    );

    try {
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Envia para o Gemini Vision
      final jsonResponse = await AiWorkoutService.analyzeWorkoutImage(base64Image);
      final data = jsonDecode(jsonResponse);
      final List<dynamic> exercisesList = data['exercises'] ?? [];

      final List<Map<String, dynamic>> newExercises = exercisesList.map((ex) {
        return {
          'id': DateTime.now().microsecondsSinceEpoch.toString() + UniqueKey().toString(),
          'name': ex['name']?.toString() ?? 'Exercício',
          'sets': ex['sets']?.toString() ?? '4',
          'reps': ex['reps']?.toString() ?? '10-12',
          'rest': '60',
          'load': ex['load']?.toString() ?? '0',
        };
      }).toList();

      if (!context.mounted) return;
      Navigator.pop(context); // Fecha o loading

      // Insere os exercícios novos no dia atual
      setState(() {
        _workouts[_selectedDay] ??= [];
        _workouts[_selectedDay]!.addAll(newExercises);
      });
      _saveWorkouts();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ficha importada com sucesso!'), backgroundColor: Colors.green),
      );

    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Fecha o loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao processar imagem: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1c1c1e),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  ListTile(
                    leading: const Icon(LucideIcons.penTool, color: Colors.white),
                    title: const Text('Adicionar Manualmente',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _addExercise();
                    },
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.camera, color: Colors.blueAccent),
                    title: const Text('Ler Ficha (Foto/Print)',
                        style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _importFromImage(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.sparkles, color: Color(0xFF22c55e)),
                    title: const Text('Gerar Dia com IA',
                        style: TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _showAiWorkoutDialog(context);
                    },
                  ),
                ],
              ),
            ),
          );
        });
  }

  Future<void> _showAiWorkoutDialog(BuildContext context) async {
    TextEditingController muscleController = TextEditingController();
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1c1c1e),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(LucideIcons.bot, color: Color(0xFF22c55e)),
                  const SizedBox(width: 12),
                  Text('Preencher $_selectedDay',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
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
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  : TextField(
                      controller: muscleController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'Ex: Costas e Bíceps',
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
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (muscleController.text.trim().isEmpty) return;
                          setStateDialog(() => isLoading = true);

                          try {
                            // 1. Recebe a String do serviço de IA
                            final jsonResponse = await AiWorkoutService.generateWorkout(muscleController.text);
                            
                            // 2. Descodifica a String para JSON
                            final data = jsonDecode(jsonResponse);
                            
                            // 3. Extrai a lista em segurança
                            final List<dynamic> exercisesList = data['exercises'] ?? [];

                            // 4. Mapeia os exercícios agora que é uma lista válida
                            final List<Map<String, dynamic>> newExercises = exercisesList.map((ex) {
                              return {
                                'id': DateTime.now().microsecondsSinceEpoch.toString() + UniqueKey().toString(),
                                'name': ex['name']?.toString() ?? 'Exercício',
                                'sets': ex['sets']?.toString() ?? '4',
                                'reps': ex['reps']?.toString() ?? '10-12',
                                'rest': '60',
                                'load': ex['load']?.toString() ?? '0',
                              };
                            }).toList();

                            if (!context.mounted) return;
                            Navigator.pop(context);

                            setState(() {
                              _workouts[_selectedDay] ??= [];
                              _workouts[_selectedDay]!.addAll(newExercises);
                            });
                            _saveWorkouts();
                          } catch (e) {
                            setStateDialog(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(e.toString().replaceAll('Exception: ', '')),
                                  backgroundColor: Colors.red),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22c55e),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Gerar',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
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
    final currentExercises = _workouts[_selectedDay] ?? [];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Os seus Treinos',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1)),
                IconButton(
                  onPressed: () => _showAddOptions(context),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF14281d),
                    side: BorderSide(color: const Color(0xFF22c55e).withOpacity(0.3)),
                  ),
                  icon: const Icon(LucideIcons.plus, color: Color(0xFF22c55e)),
                )
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: _days.map((day) {
                bool isSelected = _selectedDay == day;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF22c55e) : const Color(0xFF1c1c1e),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected
                                ? const Color(0xFF22c55e)
                                : Colors.white.withOpacity(0.05)),
                      ),
                      child: Text(day,
                          style: TextStyle(
                              color: isSelected ? Colors.black : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: currentExercises.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.dumbbell, size: 48, color: Colors.grey.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        const Text('Dia de descanso?',
                            style: TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Nenhum exercício planejado para hoje.',
                            style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          itemCount: currentExercises.length,
                          itemBuilder: (context, index) {
                            final ex = currentExercises[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1c1c1e),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: const Color(0xFF0a0a0a),
                                            borderRadius: BorderRadius.circular(8)),
                                        child: Text('${index + 1}',
                                            style: const TextStyle(
                                                color: Color(0xFF22c55e),
                                                fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: ex['name'],
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(
                                              hintText: 'Nome do Exercício',
                                              hintStyle: TextStyle(color: Colors.grey),
                                              border: InputBorder.none,
                                              isDense: true,
                                              contentPadding: EdgeInsets.zero),
                                          onChanged: (val) =>
                                              _updateExercise(ex['id'], 'name', val),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _removeExercise(ex['id']),
                                        icon: const Icon(LucideIcons.trash2,
                                            color: Colors.redAccent, size: 20),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      _buildEditableMetric('SÉRIES', ex['sets'].toString(),
                                          (val) => _updateExercise(ex['id'], 'sets', val)),
                                      _buildEditableMetric('REPS', ex['reps'].toString(),
                                          (val) => _updateExercise(ex['id'], 'reps', val)),
                                      _buildEditableMetric('PAUSA(s)', ex['rest'].toString(),
                                          (val) => _updateExercise(ex['id'], 'rest', val)),
                                      _buildEditableMetric('CARGA(kg)', ex['load'].toString(),
                                          (val) => _updateExercise(ex['id'], 'load', val)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 64,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ActiveWorkoutView(
                                    day: _selectedDay,
                                    exercises: currentExercises,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(LucideIcons.play, color: Colors.black, size: 24),
                            label: const Text('INICIAR TREINO',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22c55e),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              elevation: 8,
                              shadowColor: const Color(0xFF22c55e).withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableMetric(
      String label, String initialValue, Function(String) onChanged) {
    return Expanded(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFF0a0a0a), borderRadius: BorderRadius.circular(8)),
            child: TextFormField(
              initialValue: initialValue,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4)),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}