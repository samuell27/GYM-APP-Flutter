import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiWorkoutService {
  static Future<List<Map<String, dynamic>>> generateWorkout(
      String muscleGroup) async {
    final prefs = await SharedPreferences.getInstance();

    // Busca os dados exatos que você salvou na tela de Perfil
    final apiKey = prefs.getString('apiKey') ?? '';
    final modelName = prefs.getString('geminiModel') ?? 'gemini-3.8-flash';

    if (apiKey.trim().isEmpty) {
      throw Exception(
          'Chave da API não configurada. Vá ao Perfil e adicione a sua chave.');
    }

    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
    );

    final prompt = '''
    Atue como um personal trainer especialista em hipertrofia.
    Crie um treino focado no seguinte grupo muscular: $muscleGroup.
    Dê preferência a exercícios realizados em máquinas.
    
    RETORNE APENAS UM JSON VÁLIDO contendo um array de exercícios. Não inclua textos, saudações ou marcações de markdown (como ```json).
    
    Siga ESTE formato exato:
    [
      {
        "id": "ex_1",
        "name": "Nome do Exercício",
        "sets": "4",
        "reps": "10-12",
        "load": 0
      }
    ]
    ''';

    final response = await model.generateContent([Content.text(prompt)]);
    String responseText = response.text?.trim() ?? '[]';

    // Limpeza de segurança caso a IA envie marcações Markdown
    if (responseText.startsWith('```')) {
      responseText = responseText.replaceAll(RegExp(r'^```json\n?'), '');
      responseText = responseText.replaceAll(RegExp(r'^```\n?'), '');
      responseText = responseText.replaceAll(RegExp(r'```$'), '');
    }

    try {
      List<dynamic> parsedJson = jsonDecode(responseText.trim());
      return List<Map<String, dynamic>>.from(parsedJson);
    } catch (e) {
      throw Exception('A IA gerou um formato inválido. Tente novamente.');
    }
  }
}
