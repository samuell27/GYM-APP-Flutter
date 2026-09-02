import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String _userName = 'Utilizador';
  String _userGoal = 'Geral';
  String _greeting = 'Olá';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _calculateGreeting();
  }

  void _calculateGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = 'Bom dia';
    } else if (hour < 19) {
      _greeting = 'Boa tarde';
    } else {
      _greeting = 'Boa noite';
    }
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? 'Utilizador';
      _userGoal = prefs.getString('userGoal') ?? 'Geral';
      if (_userName.trim().isEmpty) _userName = 'Utilizador';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Pega a primeira letra do nome para o Avatar
    final String initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- CABEÇALHO ---
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_greeting, $_userName 👋', style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('Hora de treinar!', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ],
                  ),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF22c55e).withOpacity(0.2),
                    child: Text(initial, style: const TextStyle(color: Color(0xFF22c55e), fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ],
              ),
            ),

            // --- ESTATÍSTICAS (MOCK) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildStatCard(LucideIcons.flame, Colors.orange, '0', 'SEQUÊNCIA'),
                  const SizedBox(width: 12),
                  _buildStatCard(LucideIcons.zap, const Color(0xFF22c55e), '0', 'ESTA SEM.'),
                  const SizedBox(width: 12),
                  _buildStatCard(LucideIcons.trophy, Colors.amber, '0', 'TOTAL'),
                ],
              ),
            ),

            // --- ATIVIDADE DA SEMANA ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1c1c1e),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ATIVIDADE DA SEMANA', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'].map((day) {
                        bool isToday = day == 'qui'; // Mock para visualização
                        return Column(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isToday ? const Color(0xFF22c55e) : const Color(0xFF0a0a0a),
                                shape: BoxShape.circle,
                                border: isToday ? null : Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: isToday ? [BoxShadow(color: const Color(0xFF22c55e).withOpacity(0.4), blurRadius: 8)] : [],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(day, style: TextStyle(color: isToday ? const Color(0xFF22c55e) : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            // --- PLANO ATIVO ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Plano Ativo', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {}, 
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: const Text('Ver treino >', style: TextStyle(color: Color(0xFF22c55e), fontSize: 14)),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14281d),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.2)),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FOCO: ${_userGoal.toUpperCase()}', style: const TextStyle(color: Color(0xFF22c55e), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                            const SizedBox(height: 8),
                            const Text('Treino de Hoje', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            const Text('0 exercícios planeados', style: TextStyle(color: Colors.grey, fontSize: 14)),
                          ],
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22c55e),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFF22c55e).withOpacity(0.3), blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: const Icon(LucideIcons.play, color: Colors.black, size: 28),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1c1c1e),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 6),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}