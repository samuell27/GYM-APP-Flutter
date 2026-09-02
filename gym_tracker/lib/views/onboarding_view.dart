import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';


class OnboardingView extends StatefulWidget {
  final VoidCallback onFinish;

  const OnboardingView({super.key, required this.onFinish});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  int _step = 1;
  final int _totalSteps = 5;

  // Controladores de texto para guardar os dados
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  
  String _gender = '';
  String _experience = '';
  String _trainingDays = '';
  String _goal = '';

  // Verifica se o botão "Continuar" deve estar ativado
  bool _isNextEnabled() {
    if (_step == 1) return _nameController.text.trim().isNotEmpty;
    if (_step == 2) return _ageController.text.isNotEmpty && _gender.isNotEmpty;
    if (_step == 3) return _weightController.text.isNotEmpty && _heightController.text.isNotEmpty;
    if (_step == 4) return _experience.isNotEmpty && _trainingDays.isNotEmpty;
    if (_step == 5) return _goal.isNotEmpty;
    return false;
  }

  void _nextStep() async {
    if (_step < _totalSteps) {
      setState(() => _step++);
    } else {
      // Guardar no armazenamento local e finalizar
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isNewUser', false);
      await prefs.setString('userName', _nameController.text.trim());
      await prefs.setString('userGoal', _goal);
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de progresso e botão de voltar
              if (_step > 1)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                      onPressed: () => setState(() => _step--),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFF1c1c1e)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: List.generate(
                          _totalSteps - 1,
                          (index) => Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 6,
                              decoration: BoxDecoration(
                                color: index < _step - 1 
                                    ? const Color(0xFF22c55e) 
                                    : const Color(0xFF1c1c1e),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('${_step - 1}/${_totalSteps - 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: _buildCurrentStep(),
                  ),
                ),
              ),

              // Botão Continuar
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isNextEnabled() ? _nextStep : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22c55e),
                    disabledBackgroundColor: const Color(0xFF22c55e).withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    _step == _totalSteps ? "COMEÇAR" : "CONTINUAR",
                    style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    if (_step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF14281d), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.2))),
            child: const Icon(LucideIcons.dumbbell, color: Color(0xFF22c55e), size: 32),
          ),
          const SizedBox(height: 24),
          const Text('Bem-vindo ao', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
          const Text('GymTracker', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Color(0xFF22c55e), height: 1.1)),
          const SizedBox(height: 16),
          const Text('Vamos configurar o seu perfil\npara personalizar os seus treinos.', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 40),
          const Text('COMO VOCÊ SE CHAMA?', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.user, color: Color(0xFF22c55e)),
              hintText: 'O seu nome',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: const Color(0xFF1c1c1e),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onChanged: (val) => setState(() {}),
          ),
        ],
      );
    }
    
    // Passos 2 ao 5
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _step == 2 ? 'Um pouco\nsobre você' : 
          _step == 3 ? 'As suas\nmedidas' : 
          _step == 4 ? 'O seu\nritmo' : 'O seu\nobjetivo', 
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF22c55e), height: 1.1)
        ),
        const SizedBox(height: 40),
        
        if (_step == 2) ...[
          TextField(controller: _ageController, keyboardType: TextInputType.number, decoration: _inputDeco('Idade (Ex: 24)'), onChanged: (_) => setState((){})),
          const SizedBox(height: 16),
          _buildOptionBtn('Masculino', _gender, (v) => setState(() => _gender = v)),
          _buildOptionBtn('Feminino', _gender, (v) => setState(() => _gender = v)),
        ],
        
        if (_step == 3) ...[
          TextField(controller: _weightController, keyboardType: TextInputType.number, decoration: _inputDeco('Peso Atual (kg)'), onChanged: (_) => setState((){})),
          const SizedBox(height: 16),
          TextField(controller: _heightController, keyboardType: TextInputType.number, decoration: _inputDeco('Altura (cm)'), onChanged: (_) => setState((){})),
        ],

        if (_step == 4) ...[
          const Text('Experiência:', style: TextStyle(color: Colors.white54)),
          _buildOptionBtn('Iniciante', _experience, (v) => setState(() => _experience = v)),
          _buildOptionBtn('Avançado', _experience, (v) => setState(() => _experience = v)),
          const SizedBox(height: 16),
          const Text('Dias na semana:', style: TextStyle(color: Colors.white54)),
          Row(children: ['3', '4', '5'].map((d) => Expanded(child: Padding(padding: const EdgeInsets.all(4.0), child: _buildOptionBtn(d, _trainingDays, (v) => setState(() => _trainingDays = v))))).toList()),
        ],

        if (_step == 5) ...[
          _buildOptionBtn('Hipertrofia', _goal, (v) => setState(() => _goal = v)),
          _buildOptionBtn('Emagrecimento', _goal, (v) => setState(() => _goal = v)),
          _buildOptionBtn('Força', _goal, (v) => setState(() => _goal = v)),
        ]
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: const Color(0xFF1c1c1e), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none));

  Widget _buildOptionBtn(String text, String groupValue, Function(String) onSelect) {
    bool isSelected = groupValue == text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () => onSelect(text),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF22c55e).withOpacity(0.1) : const Color(0xFF1c1c1e),
            border: Border.all(color: isSelected ? const Color(0xFF22c55e) : Colors.transparent),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? const Color(0xFF22c55e) : Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
