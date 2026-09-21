import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/ai_service.dart';
import 'active_workout_view.dart';

class AiGenerationView extends StatefulWidget {
  const AiGenerationView({super.key});

  @override
  State<AiGenerationView> createState() => _AiGenerationViewState();
}

class _AiGenerationViewState extends State<AiGenerationView> {
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;

  Future<void> _generate() async {
    if (_promptController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus(); // Recolhe o teclado

    try {
      final jsonResponse = await AiWorkoutService.generateWorkout(_promptController.text);
      final data = jsonDecode(jsonResponse);

      final String workoutName = data['name'] ?? 'Treino Gerado IA';
      final List<dynamic> exList = data['exercises'] ?? [];
      
      // Converte a resposta genérica para a lista tipada que o ActiveWorkoutView espera
      final List<Map<String, dynamic>> exercises = List<Map<String, dynamic>>.from(exList);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveWorkoutView(
              day: workoutName,
              exercises: exercises,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')), 
            backgroundColor: Colors.redAccent, 
            duration: const Duration(seconds: 5)
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Assistente IA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.bot, color: Color(0xFF22c55e), size: 48),
            const SizedBox(height: 16),
            const Text('O que quer treinar hoje?', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Descreva o seu objetivo de forma simples. Ex: "Treino de pernas rápido com foco em quadríceps".', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 32),
            TextField(
              controller: _promptController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Digite o seu objetivo aqui...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF1c1c1e),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _generate,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF22c55e),
                  disabledBackgroundColor: const Color(0xFF22c55e).withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isLoading ? const SizedBox.shrink() : const Icon(LucideIcons.sparkles, color: Colors.black),
                label: _isLoading 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('GERAR TREINO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
