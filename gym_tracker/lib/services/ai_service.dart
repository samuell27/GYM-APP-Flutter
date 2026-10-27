import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiWorkoutService {
  static Future<String> generateWorkout(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    
    final apiKey = prefs.getString('apiKey') ?? '';
    String model = prefs.getString('geminiModel') ?? 'gemini-3.8-flash';
    
    // Trava de segurança: Se o cache antigo ainda tiver a versão 1.5, força a transição para a 3.8
    if (model == 'gemini-1.5-flash') {
      model = 'gemini-3.8-flash';
      await prefs.setString('geminiModel', model);
    }
    
    final age = prefs.getString('userAge') ?? 'Não informado';
    final weight = prefs.getString('userWeight') ?? 'Não informado';
    final goal = prefs.getString('userGoal') ?? 'Hipertrofia';

    if (apiKey.trim().isEmpty) {
      throw Exception('A chave da API está vazia ou não foi carregada. Vá ao Perfil e clique em "Salvar Alterações".');
    }

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${apiKey.trim()}');

    final enrichedPrompt = '''
    Atua como um personal trainer especialista.
    O utilizador tem as seguintes características:
    - Idade: $age anos
    - Peso: $weight kg
    - Objetivo: $goal
    
    Pedido do utilizador: $prompt
    
    Retorna o treino ESTRITAMENTE num formato JSON válido, com a seguinte estrutura e mais nada:
    {
      "name": "Nome do Treino (ex: Treino A - Peito)",
      "exercises": [
        {
          "name": "Nome do Exercício",
          "sets": 4,
          "reps": "10-12",
          "load": 20
        }
      ]
    }
    ''';

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": enrichedPrompt}
              ]
            }
          ],
          "generationConfig": {
            "responseMimeType": "application/json", 
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final content = data['candidates'][0]['content'];
          if (content != null && content['parts'] != null && content['parts'].isNotEmpty) {
            String textResponse = content['parts'][0]['text'];
            
            textResponse = textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
            
            return textResponse;
          }
        }
        throw Exception('Formato de resposta inesperado da API.');
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Erro desconhecido';
        throw Exception('Erro ${response.statusCode}: $errorMessage');
      }
    } catch (e) {
      throw Exception('$e');
    }
  }
  static Future<String> analyzeWorkoutImage(String base64Image) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('apiKey') ?? '';
    String model = prefs.getString('geminiModel') ?? 'gemini-3.8-flash';
    
    if (model == 'gemini-1.5-flash') {
      model = 'gemini-3.8-flash';
      await prefs.setString('geminiModel', model);
    }

    final experience = prefs.getString('userExperience') ?? 'Intermediário';
    final goal = prefs.getString('userGoal') ?? 'Hipertrofia';

    if (apiKey.trim().isEmpty) {
      throw Exception('Chave da API vazia.');
    }

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${apiKey.trim()}');

    final prompt = '''
    Analisa esta imagem que contém um roteiro de treinos (pode ser uma foto de papel ou print de PDF).
    Extrai todos os exercícios listados.
    
    REGRAS DE INFERÊNCIA:
    - Se a imagem indicar séries e repetições (ex: 3x12), usa esses valores.
    - Se a imagem NÃO indicar séries/repetições, infere os melhores valores baseados num utilizador de nível $experience com foco em $goal.
    - Se não houver carga (kg) indicada, define "load": 0.
    
    Retorna ESTRITAMENTE num formato JSON válido:
    {
      "name": "Nome do Treino Identificado (ex: Treino A, Costas, etc)",
      "exercises": [
        {
          "name": "Nome do Exercício",
          "sets": 4,
          "reps": "10-12",
          "load": 0
        }
      ]
    }
    ''';

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
                {
                  "inlineData": {
                    "mimeType": "image/jpeg",
                    "data": base64Image
                  }
                }
              ]
            }
          ],
          "generationConfig": {
            "responseMimeType": "application/json", 
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          String textResponse = data['candidates'][0]['content']['parts'][0]['text'];
          return textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
        }
        throw Exception('Formato de resposta inesperado.');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('Erro ${response.statusCode}: ${errorData['error']?['message']}');
      }
    } catch (e) {
      throw Exception('$e');
    }
  }
  static Future<String> explainExercise(String exerciseName) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('apiKey') ?? '';
    String model = prefs.getString('geminiModel') ?? 'gemini-3.8-flash';

    if (model == 'gemini-1.5-flash') {
      model = 'gemini-3.8-flash';
      await prefs.setString('geminiModel', model);
    }

    if (apiKey.trim().isEmpty) {
      throw Exception('A chave da API está vazia.');
    }

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${apiKey.trim()}');

    final prompt = '''
    Atua como um personal trainer especialista em biomecânica.
    Explica de forma breve, direta e segura como executar o exercício "$exerciseName".
    Divide a resposta em 2 pontos curtos:
    1. Postura inicial.
    2. Movimento e Respiração.
    Não uses formatações complexas, apenas texto limpo.
    ''';

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": prompt}]}],
          "generationConfig": {"temperature": 0.3} // Temperatura baixa para respostas diretas e factuais
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'].trim();
        }
        throw Exception('Resposta vazia da IA.');
      } else {
        throw Exception('Erro ao contactar a IA.');
      }
    } catch (e) {
      throw Exception('Erro: $e');
    }
  }

  /// Calcula as calorias gastas no treino usando o Gemini com base nos exercícios, cargas, reps e duração
  static Future<int> estimateWorkoutCalories({
    required List<Map<String, dynamic>> completedExercises,
    required int durationMinutes,
  }) async {
    // Cálculo de segurança (fallback) caso esteja sem internet no momento de fechar o treino
    int totalSets = 0;
    for (var ex in completedExercises) {
      if (ex['sets'] is List) {
        totalSets += (ex['sets'] as List).where((s) => s['isCompleted'] == true).length;
      }
    }
    final int fallbackCalories = (totalSets * 6) + (durationMinutes * 3);

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('apiKey') ?? '';
      String model = prefs.getString('geminiModel') ?? 'gemini-3.8-flash';

      if (model == 'gemini-1.5-flash') {
        model = 'gemini-3.8-flash';
        await prefs.setString('geminiModel', model);
      }

      if (apiKey.trim().isEmpty) return fallbackCalories;

      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${apiKey.trim()}');

      // Monta o resumo detalhado do que o utilizador realmente levantou
      StringBuffer summary = StringBuffer();
      for (var ex in completedExercises) {
        summary.writeln('- Exercício: ${ex['name']}');
        if (ex['sets'] is List) {
          for (var s in ex['sets']) {
            if (s['isCompleted'] == true) {
              summary.writeln('  • Série concluída: ${s['weight']} kg x ${s['reps']} reps');
            }
          }
        }
      }

      final prompt = '''
      Atua como um fisiologista do exercício especialista em musculação e hipertrofia.
      Calcula uma estimativa realista de calorias gastas (em kcal) para esta sessão de treino:
      Duração total da sessão: $durationMinutes minutos.
      Exercícios, cargas e repetições executadas:
      $summary

      Avalia se os exercícios são compostos/multiarticulares (que exigem maior recrutamento muscular e gasto energético) ou isolados, bem como a tonelagem levantada (carga x repetições) e a duração.
      Responde APENAS com um número inteiro representando o total estimado de kcal (exemplo: 310). Não escrevas mais nenhuma palavra, explicação ou unidade.
      ''';

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": prompt}]}],
          "generationConfig": {"temperature": 0.1}
        }),
      ).timeout(const Duration(seconds: 8)); // Timeout de 8s para não travar a finalização

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          String text = data['candidates'][0]['content']['parts'][0]['text'].toString().trim();
          final RegExp regExp = RegExp(r'\d+');
          final match = regExp.firstMatch(text);
          if (match != null) {
            int? aiCalories = int.tryParse(match.group(0)!);
            if (aiCalories != null && aiCalories > 0) {
              return aiCalories;
            }
          }
        }
      }
      return fallbackCalories;
    } catch (e) {
      debugPrint('Aviso: Usando cálculo de calorias offline ($e)');
      return fallbackCalories;
    }
  }


}