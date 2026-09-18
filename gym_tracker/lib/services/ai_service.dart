import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiWorkoutService {
  // <-- O nome exato que as suas telas procuram!
  static Future<List<Map<String, dynamic>>> generateWorkout(
      String focusDay) async {
    final prefs = await SharedPreferences.getInstance();

    final apiKey = prefs.getString('apiKey') ?? '';
    final model = prefs.getString('geminiModel') ?? 'gemini-1.5-flash';

    if (apiKey.isEmpty) {
      throw Exception(
          'Chave da API Gemini não encontrada. Vá ao seu Perfil e configure a chave.');
    }

    final age = prefs.getString('userAge') ?? 'Desconhecido';
    final weight = prefs.getString('userWeight') ?? 'Desconhecido';
    final goal = prefs.getString('userGoal') ?? 'Hipertrofia';

    final prompt = '''
    Atue como um Personal Trainer de elite.
    
    Perfil do meu aluno:
    - Idade: $age anos
    - Peso: $weight kg
    - Objetivo Principal: $goal
    
    Gere um treino excelente focado em: $focusDay.
    Ajuste o volume, as repetições e as cargas estimadas (em kg) com base no objetivo de $goal.
    
    RETORNE APENAS UM ARRAY JSON VÁLIDO. NÃO USE formatação markdown (```json).
    O formato exato obrigatório é:
    [
      {
        "id": "1",
        "name": "Nome do Exercício",
        "sets": 4,
        "reps": "8-12",
        "load": 20
      }
    ]
    ''';

    final url = Uri.parse(
        '[https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey](https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey)');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ],
          "generationConfig": {
            "temperature": 0.7,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String rawText = data['candidates'][0]['content']['parts'][0]['text'];

        rawText =
            rawText.replaceAll('```json', '').replaceAll('```', '').trim();

        final List<dynamic> jsonList = jsonDecode(rawText);

        return jsonList.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        throw Exception(
            'Erro na API Gemini: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      throw Exception('Falha ao gerar treino: $e');
    }
  }
}
