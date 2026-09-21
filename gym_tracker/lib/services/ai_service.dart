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
}