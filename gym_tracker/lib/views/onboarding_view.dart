import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- IMPORTAÇÃO DO FIREBASE


class OnboardingView extends StatefulWidget {
  final VoidCallback onFinish;

  const OnboardingView({super.key, required this.onFinish});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  int _step = 1;
  final int _totalSteps = 5;

  bool _isLoginMode = false;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  String _gender = 'Masculino';
  String _experience = '';
  String _trainingDays = '';
  String _goal = '';

  bool _isNextEnabled() {
    if (_step == 1) {
      if (_isLoginMode) {
        return _emailController.text.trim().isNotEmpty &&
            _emailController.text.contains('@');
      } else {
        return _nameController.text.trim().isNotEmpty &&
            _emailController.text.trim().isNotEmpty &&
            _emailController.text.contains('@');
      }
    }
    if (_step == 2) return _ageController.text.isNotEmpty && _gender.isNotEmpty;
    if (_step == 3)
      return _weightController.text.isNotEmpty &&
          _heightController.text.isNotEmpty;
    if (_step == 4) return _experience.isNotEmpty && _trainingDays.isNotEmpty;
    if (_step == 5) return _goal.isNotEmpty;
    return false;
  }

  void _nextStep() async {
    if (_step < _totalSteps) {
      setState(() => _step++);
    } else {
      _saveNewUserAndFinish();
    }
  }

  // --- LOGIN: PUXA OS DADOS DO FIREBASE ---
  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      final String email = _emailController.text.trim().toLowerCase();
      final prefs = await SharedPreferences.getInstance();

      // Procura o documento do utilizador no Firebase usando o e-mail
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(email).get();

      if (doc.exists) {
        final data = doc.data()!;

        // Salva localmente tudo o que veio da nuvem
        await prefs.setBool('isNewUser', false);
        await prefs.setString('userEmail', email);
        await prefs.setString('userName', data['name'] ?? email.split('@')[0]);
        await prefs.setString('userAge', data['age'] ?? '');
        await prefs.setString('userWeight', data['weight'] ?? '');
        await prefs.setString('userHeight', data['height'] ?? '');
        await prefs.setString('userGoal', data['goal'] ?? 'Hipertrofia');

        if (mounted) widget.onFinish();
      } else {
        // Se o e-mail não existir na base de dados
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Conta não encontrada. Por favor, crie uma conta.'),
                backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro no login: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- REGISTO: SALVA OS DADOS NO FIREBASE ---
  Future<void> _saveNewUserAndFinish() async {
    setState(() => _isLoading = true);

    try {
      final String email = _emailController.text.trim().toLowerCase();
      final String name = _nameController.text.trim();
      final String age = _ageController.text.trim();
      final String weight = _weightController.text.trim();
      final String height = _heightController.text.trim();

      // 1. Salva no cache do telemóvel
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isNewUser', false);
      await prefs.setString('userName', name);
      await prefs.setString('userEmail', email);
      await prefs.setString('userAge', age);
      await prefs.setString('userWeight', weight);
      await prefs.setString('userHeight', height);
      await prefs.setString('userGoal', _goal);

      // 2. Salva o perfil completo na coleção 'users'
      await FirebaseFirestore.instance.collection('users').doc(email).set({
        'name': name,
        'email': email,
        'age': age,
        'weight': weight,
        'height': height,
        'gender': _gender,
        'experience': _experience,
        'trainingDays': _trainingDays,
        'goal': _goal,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) widget.onFinish();
    } catch (e) {
      debugPrint('Erro ao criar conta: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro de ligação: $e'),
              backgroundColor: Colors.redAccent),
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
      body: Stack(
        children: [
          if (_step == 1)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.6,
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                        'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?auto=format&fit=crop&w=800&q=80'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF0a0a0a).withOpacity(0.5),
                        const Color(0xFF0a0a0a),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_step > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.arrowLeft,
                              color: Colors.white),
                          onPressed: () => setState(() => _step--),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF1c1c1e),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Row(
                            children: List.generate(
                              _totalSteps - 1,
                              (index) => Expanded(
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  height: 4,
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
                        Text('${_step - 1}/${_totalSteps - 1}',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildCurrentStep(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      if (_step == 1 && !_isLoginMode)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDot(true),
                            _buildDot(false),
                            _buildDot(false),
                          ],
                        ),
                      if (_step == 1 && !_isLoginMode)
                        const SizedBox(height: 24),
                      Row(
                        children: [
                          if (_step > 1) ...[
                            SizedBox(
                              height: 56,
                              width: 56,
                              child: OutlinedButton(
                                onPressed: () => setState(() => _step--),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  side: BorderSide(
                                      color: Colors.white.withOpacity(0.1)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  backgroundColor: const Color(0xFF1c1c1e),
                                ),
                                child: const Icon(LucideIcons.arrowLeft,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: (_isNextEnabled() && !_isLoading)
                                    ? (_isLoginMode ? _handleLogin : _nextStep)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22c55e),
                                  disabledBackgroundColor:
                                      const Color(0xFF22c55e).withOpacity(0.3),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            color: Colors.black,
                                            strokeWidth: 2))
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _isLoginMode
                                                ? "ENTRAR"
                                                : (_step == _totalSteps
                                                    ? "COMEÇAR"
                                                    : "CONTINUAR"),
                                            style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                              _isLoginMode
                                                  ? LucideIcons.logIn
                                                  : LucideIcons.arrowRight,
                                              color: Colors.black,
                                              size: 20),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 16,
      height: 4,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF22c55e) : const Color(0xFF1c1c1e),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildStepHeader(String textWhite, String textGreen, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(textWhite,
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.1)),
        Text(textGreen,
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Color(0xFF22c55e),
                height: 1.1)),
        const SizedBox(height: 16),
        Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCurrentStep() {
    if (_step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF14281d),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF22c55e).withOpacity(0.2))),
            child: const Icon(LucideIcons.dumbbell,
                color: Color(0xFF22c55e), size: 32),
          ),
          const SizedBox(height: 24),
          Text(_isLoginMode ? 'Bem-vindo de volta ao' : 'Bem-vindo ao',
              style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.1)),
          const Text('GymTracker',
              style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF22c55e),
                  height: 1.1)),
          const SizedBox(height: 16),
          Text(
              _isLoginMode
                  ? 'Acesse a sua conta para continuar a\nacompanhar a sua evolução.'
                  : 'Vamos configurar o seu perfil\npara personalizar os seus treinos.',
              style: const TextStyle(
                  color: Colors.grey, fontSize: 14, height: 1.5)),
          const SizedBox(height: 40),
          if (!_isLoginMode) ...[
            _buildLabel('COMO VOCÊ SE CHAMA?'),
            _buildTextField(_nameController, 'O seu nome', LucideIcons.user,
                TextInputType.name),
            const SizedBox(height: 24),
          ],
          _buildLabel(_isLoginMode
              ? 'O SEU E-MAIL'
              : 'O SEU E-MAIL (PARA SALVAR O PROGRESSO)'),
          _buildTextField(_emailController, 'exemplo@email.com',
              LucideIcons.mail, TextInputType.emailAddress),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                  _nameController.clear();
                  _emailController.clear();
                });
              },
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                _isLoginMode
                    ? 'Ainda não tem conta? Crie uma'
                    : 'Já tem conta? Faça login',
                style: const TextStyle(
                    color: Color(0xFF22c55e),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_step == 2) ...[
          _buildStepHeader('Um pouco', 'sobre você',
              'Isto nos ajuda a ajustar o volume\ne intensidade dos seus treinos.'),
          _buildLabel('IDADE'),
          _buildTextField(
              _ageController, '24', LucideIcons.calendar, TextInputType.number),
          const SizedBox(height: 24),
          _buildLabel('GÊNERO'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFF1c1c1e),
                borderRadius: BorderRadius.circular(16)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _gender,
                isExpanded: true,
                dropdownColor: const Color(0xFF1c1c1e),
                icon: const Icon(LucideIcons.chevronDown,
                    color: Colors.grey, size: 20),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                items: ['Masculino', 'Feminino'].map((String value) {
                  return DropdownMenuItem<String>(
                      value: value,
                      child: Row(children: [
                        const Icon(LucideIcons.user,
                            color: Color(0xFF22c55e), size: 20),
                        const SizedBox(width: 12),
                        Text(value)
                      ]));
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) setState(() => _gender = newValue);
                },
              ),
            ),
          ),
          const SizedBox(height: 40),
          _buildInfoBanner(),
        ],
        if (_step == 3) ...[
          _buildStepHeader('As suas', 'medidas',
              'Para acompanharmos a sua evolução\nao longo do tempo.'),
          _buildLabel('PESO ATUAL (KG)'),
          _buildTextField(_weightController, 'Ex: 75.5', LucideIcons.scale,
              TextInputType.number),
          const SizedBox(height: 24),
          _buildLabel('ALTURA (CM)'),
          _buildTextField(_heightController, 'Ex: 175', LucideIcons.ruler,
              TextInputType.number),
        ],
        if (_step == 4) ...[
          _buildStepHeader('O seu', 'ritmo',
              'A consistência é o segredo para\nresultados duradouros.'),
          _buildLabel('EXPERIÊNCIA'),
          _buildOptionBtn(
              'Iniciante', _experience, (v) => setState(() => _experience = v)),
          _buildOptionBtn(
              'Avançado', _experience, (v) => setState(() => _experience = v)),
          const SizedBox(height: 24),
          _buildLabel('DIAS NA SEMANA'),
          Row(
              children: ['3', '4', '5']
                  .map((d) => Expanded(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: _buildOptionBtn(d, _trainingDays,
                              (v) => setState(() => _trainingDays = v)))))
                  .toList()),
        ],
        if (_step == 5) ...[
          _buildStepHeader('O seu', 'objetivo',
              'O que você deseja alcançar\ncom os seus treinos?'),
          _buildLabel('FOCO PRINCIPAL'),
          _buildOptionBtn(
              'Hipertrofia', _goal, (v) => setState(() => _goal = v)),
          _buildOptionBtn(
              'Emagrecimento', _goal, (v) => setState(() => _goal = v)),
          _buildOptionBtn('Força', _goal, (v) => setState(() => _goal = v)),
          _buildOptionBtn(
              'Manutenção', _goal, (v) => setState(() => _goal = v)),
        ]
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(text,
          style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint,
      IconData icon, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF22c55e), size: 20),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: const Color(0xFF1c1c1e),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
      ),
      onChanged: (val) => setState(() {}),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF22c55e).withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.2))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.wand2, color: Color(0xFF22c55e), size: 24),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Personalização inteligente',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text('Seus treinos serão ajustados\ncom base no seu perfil.',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        height: 1.4))
              ]))
        ],
      ),
    );
  }

  Widget _buildOptionBtn(
      String text, String groupValue, Function(String) onSelect) {
    bool isSelected = groupValue == text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () => onSelect(text),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF14281d)
                  : const Color(0xFF1c1c1e),
              border: Border.all(
                  color: isSelected
                      ? const Color(0xFF22c55e)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(16)),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isSelected ? const Color(0xFF22c55e) : Colors.white,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
