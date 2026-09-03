import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  String _goal = 'Hipertrofia';
  String _aiProvider = 'gemini';
  String _geminiModel = 'gemini-2.5-flash-lite';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('userName') ?? 'Utilizador';
      _goal = prefs.getString('userGoal') ?? 'Hipertrofia';
      _apiKeyController.text = prefs.getString('apiKey') ?? '';
      _aiProvider = prefs.getString('aiProvider') ?? 'gemini';
      _geminiModel = prefs.getString('geminiModel') ?? 'gemini-2.5-flash-lite';
    });
  }

  Future<void> _saveData(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    String initial = _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'U';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('O seu Perfil', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
            const SizedBox(height: 24),
            
            // Cartão de Resumo
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1c1c1e),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF22c55e).withOpacity(0.2),
                    child: Text(initial, style: const TextStyle(color: Color(0xFF22c55e), fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nameController.text, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Objetivo: ', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            Text(_goal, style: const TextStyle(color: Color(0xFF22c55e), fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text('CONFIGURAÇÕES DE IA', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 16),

            // Configurações de IA
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1c1c1e),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Provedor AI', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: const Color(0xFF0a0a0a), borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _aiProvider,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1c1c1e),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: ['gemini', 'openai'].map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value.toUpperCase()));
                        }).toList(),
                        onChanged: (newValue) {
                          setState(() => _aiProvider = newValue!);
                          _saveData('aiProvider', newValue!);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('API Key', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Sua chave secreta...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF0a0a0a),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => _saveData('apiKey', val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
            
            // Botão Apagar Conta
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Apaga os dados e limpa a memória
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                },
                icon: const Icon(LucideIcons.logOut, color: Colors.red),
                label: const Text('APAGAR CONTA E DADOS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.withOpacity(0.3)),
                  backgroundColor: Colors.red.withOpacity(0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: Text('GymTracker Flutter v1.0', style: TextStyle(color: Colors.grey, fontSize: 12))),
          ],
        ),
      ),
    );
  }
}
