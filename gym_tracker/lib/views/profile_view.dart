import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- Necessário para a Área de Transferência (Clipboard)
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedGoal = 'Hipertrofia';

  final List<String> _goals = ['Hipertrofia', 'Emagrecimento', 'Manutenção', 'Força'];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _ageController.text = prefs.getString('userAge') ?? '';
      _weightController.text = prefs.getString('userWeight') ?? '';
      _apiKeyController.text = prefs.getString('apiKey') ?? '';

      String savedGoal = prefs.getString('userGoal') ?? 'Hipertrofia';
      if (_goals.contains(savedGoal)) {
        _selectedGoal = savedGoal;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('userAge', _ageController.text.trim());
      await prefs.setString('userWeight', _weightController.text.trim());
      await prefs.setString('userGoal', _selectedGoal);
      await prefs.setString('apiKey', _apiKeyController.text.trim());
      await prefs.setString('geminiModel', 'gemini-1.5-flash');

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'age': _ageController.text.trim(),
          'weight': _weightController.text.trim(),
          'goal': _selectedGoal,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil e IA atualizados com sucesso!'), backgroundColor: Color(0xFF22c55e)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // NOVA FUNÇÃO: Gera o CSV e copia para a área de transferência
  Future<void> _exportToCSV() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historyJson = prefs.getString('workout_history');
      
      if (historyJson == null || historyJson.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum treino para exportar.'), backgroundColor: Colors.orange),
        );
        return;
      }

      List<dynamic> history = jsonDecode(historyJson);
      
      // Cabeçalho do CSV
      String csvData = "Data,Treino,Exercicio,Serie,Peso(kg),Repeticoes\n";

      for (var workout in history) {
        if (workout is! Map) continue;
        
        String dateIso = workout['dateIso']?.toString() ?? '';
        // Tenta formatar a data para ficar mais limpa no Excel, senão usa o ISO bruto
        String dateStr = dateIso;
        if (dateIso.isNotEmpty) {
          final d = DateTime.tryParse(dateIso);
          if (d != null) {
            dateStr = "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
          }
        }
        
        String workoutName = workout['name']?.toString().replaceAll(',', '') ?? 'Treino';

        if (workout['exercises'] is List) {
          for (var ex in workout['exercises']) {
            if (ex is! Map) continue;
            
            String exName = ex['name']?.toString().replaceAll(',', '') ?? 'Exercicio';
            
            if (ex['sets'] is List) {
              int setNumber = 1;
              for (var set in ex['sets']) {
                if (set is Map && (set['isCompleted'] == true || set['isCompleted'] == 'true')) {
                  String weight = set['weight']?.toString() ?? '0';
                  String reps = set['reps']?.toString() ?? '0';
                  
                  // Adiciona a linha ao CSV
                  csvData += "$dateStr,$workoutName,$exName,$setNumber,$weight,$reps\n";
                }
                setNumber++;
              }
            }
          }
        }
      }

      // Copia para a área de transferência do dispositivo
      await Clipboard.setData(ClipboardData(text: csvData));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup CSV copiado! Cole no Excel ou Bloco de Notas.'), 
            backgroundColor: Colors.blueAccent,
            duration: Duration(seconds: 4),
          ),
        );
        HapticFeedback.heavyImpact(); // Dá um toque físico para confirmar a ação
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar dados: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22c55e)));
    }

    final user = FirebaseAuth.instance.currentUser;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Perfil', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(height: 8),
              Text(user?.email ?? 'Usuário não autenticado', style: const TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 32),

              // --- DADOS FÍSICOS ---
              const Text('MÉTRICAS FÍSICAS', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1c1c1e),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildTextField('Idade (anos)', _ageController, LucideIcons.calendar, isNumber: true)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildTextField('Peso (kg)', _weightController, LucideIcons.scale, isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      value: _selectedGoal,
                      dropdownColor: const Color(0xFF1c1c1e),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Objetivo Principal',
                        labelStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(LucideIcons.target, color: Color(0xFF22c55e)),
                        filled: true,
                        fillColor: const Color(0xFF0a0a0a),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: _goals.map((goal) => DropdownMenuItem(value: goal, child: Text(goal))).toList(),
                      onChanged: (val) => setState(() => _selectedGoal = val!),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // --- CONFIGURAÇÃO DA IA ---
              const Text('INTELIGÊNCIA ARTIFICIAL', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1c1c1e),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: _buildTextField('Chave da API Gemini', _apiKeyController, LucideIcons.key, isPassword: true),
              ),

              const SizedBox(height: 32),

              // --- BOTÕES DE AÇÃO ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF22c55e),
                    disabledBackgroundColor: const Color(0xFF22c55e).withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('SALVAR ALTERAÇÕES', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 16),
              
              // NOVO BOTÃO DE EXPORTAÇÃO
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _exportToCSV,
                  icon: const Icon(LucideIcons.download, color: Colors.blueAccent),
                  label: const Text('Exportar Dados (CSV)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.blueAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(LucideIcons.logOut, color: Colors.redAccent),
                  label: const Text('Terminar Sessão', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool isNumber = false, bool isPassword = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF0a0a0a),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Campo obrigatório';
        return null;
      },
    );
  }
}