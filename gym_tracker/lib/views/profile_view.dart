import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  String _goal = 'Hipertrofia';
  String _aiProvider = 'gemini';
  final String _geminiModel = 'gemini-1.5-flash';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('userName') ?? 'Utilizador';
      _ageController.text = prefs.getString('userAge') ?? '';
      _weightController.text = prefs.getString('userWeight') ?? '';
      _heightController.text = prefs.getString('userHeight') ?? '';
      _goal = prefs.getString('userGoal') ?? 'Hipertrofia';
      _apiKeyController.text = prefs.getString('apiKey') ?? '';
      _aiProvider = prefs.getString('aiProvider') ?? 'gemini';
    });
  }

  Future<void> _saveData(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void _showEditProfileDialog() {
    String tempGoal = _goal;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1c1c1e),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  const Text('Os Seus Dados',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  _buildProfileTextField(
                      'Nome', _nameController, TextInputType.name),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildProfileTextField(
                              'Idade', _ageController, TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildProfileTextField('Peso (kg)',
                              _weightController, TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildProfileTextField('Altura (cm)',
                              _heightController, TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Objetivo Principal',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0a0a0a),
                        borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: tempGoal,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1c1c1e),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        items: [
                          'Hipertrofia',
                          'Emagrecimento',
                          'Manutenção',
                          'Força'
                        ].map((String value) {
                          return DropdownMenuItem<String>(
                              value: value, child: Text(value));
                        }).toList(),
                        onChanged: (newValue) {
                          setModalState(() => tempGoal = newValue!);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        setState(() => _goal = tempGoal);

                        _saveData('userName', _nameController.text.trim());
                        _saveData('userAge', _ageController.text.trim());
                        _saveData('userWeight', _weightController.text.trim());
                        _saveData('userHeight', _heightController.text.trim());
                        _saveData('userGoal', _goal);

                        try {
                          final prefs = await SharedPreferences.getInstance();
                          final String userEmail =
                              prefs.getString('userEmail') ?? '';

                          if (userEmail.isNotEmpty) {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(userEmail)
                                .update({
                              'name': _nameController.text.trim(),
                              'age': _ageController.text.trim(),
                              'weight': _weightController.text.trim(),
                              'height': _heightController.text.trim(),
                              'goal': _goal,
                            });
                          }
                        } catch (e) {
                          debugPrint('Erro ao atualizar perfil na nuvem: $e');
                        }

                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22c55e),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('SALVAR ALTERAÇÕES',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          });
        });
  }

  Widget _buildProfileTextField(
      String label, TextEditingController controller, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF0a0a0a),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _showAiSettingsBottomSheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1c1c1e),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Icon(LucideIcons.sparkles, color: Color(0xFF22c55e)),
                      SizedBox(width: 12),
                      Text('Configurações de IA',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Provedor AI',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0a0a0a),
                        borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _aiProvider,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1c1c1e),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        items: ['gemini', 'openai'].map((String value) {
                          return DropdownMenuItem<String>(
                              value: value, child: Text(value.toUpperCase()));
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setModalState(() => _aiProvider = newValue);
                            setState(() => _aiProvider = newValue);
                            _saveData('aiProvider', newValue);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('API Key',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Sua chave secreta...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF0a0a0a),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => _saveData('apiKey', val),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          });
        });
  }

  Future<void> _showLogoutConfirmation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1c1c1e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(LucideIcons.logOut, color: Colors.white),
              SizedBox(width: 12),
              Text('Sair da Conta',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Deseja realmente sair? O seu histórico e treinos continuarão salvos na nuvem.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22c55e),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sim, sair',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1c1c1e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(LucideIcons.alertOctagon, color: Colors.redAccent),
              SizedBox(width: 12),
              Text('Apagar Conta?',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Deseja realmente apagar seus dados? Todo o seu histórico (no dispositivo e na nuvem) será apagado para sempre.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
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
              child: const Text('Sim, apagar',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final String userEmail = prefs.getString('userEmail') ?? '';

        if (userEmail.isNotEmpty) {
          var snapshot = await FirebaseFirestore.instance
              .collection('workout_history')
              .where('userEmail', isEqualTo: userEmail)
              .get();

          for (var doc in snapshot.docs) {
            await doc.reference.delete();
          }
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userEmail)
              .delete();
        }
      } catch (e) {
        debugPrint('Erro ao apagar dados da nuvem: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String name = _nameController.text.trim();
    String initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('O seu Perfil',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1)),
            const SizedBox(height: 24),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showEditProfileDialog,
                borderRadius: BorderRadius.circular(24),
                child: Container(
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
                        backgroundColor:
                            const Color(0xFF22c55e).withOpacity(0.2),
                        child: Text(initial,
                            style: const TextStyle(
                                color: Color(0xFF22c55e),
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isNotEmpty ? name : 'Utilizador',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text('Objetivo: ',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 14)),
                                Text(_goal,
                                    style: const TextStyle(
                                        color: Color(0xFF22c55e),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevronRight, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text('SISTEMA',
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showAiSettingsBottomSheet,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1c1c1e),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.bot, color: Colors.white70, size: 20),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text('Configurações de IA',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                      Icon(LucideIcons.chevronRight,
                          color: Colors.grey, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _showLogoutConfirmation,
                icon: const Icon(LucideIcons.logOut, color: Colors.white),
                label: const Text('SAIR DA CONTA',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _showDeleteConfirmation,
                icon: const Icon(LucideIcons.trash2, color: Colors.red),
                label: const Text('APAGAR CONTA E DADOS',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.withOpacity(0.3)),
                  backgroundColor: Colors.red.withOpacity(0.05),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
                child: Text('GymTracker Flutter v1.0',
                    style: TextStyle(color: Colors.grey, fontSize: 12))),
          ],
        ),
      ),
    );
  }
}
