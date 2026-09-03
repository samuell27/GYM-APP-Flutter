import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'views/onboarding_view.dart';
import 'views/home_view.dart';
import 'views/profile_view.dart';

void main() {
  runApp(const GymTrackerApp());
}

class GymTrackerApp extends StatelessWidget {
  const GymTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GymTracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0a),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22c55e),
          surface: Color(0xFF1c1c1e),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// Controla se mostra o Onboarding ou o App Principal
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isNewUser = true;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Se for nulo, significa que é a primeira vez (true)
      _isNewUser = prefs.getBool('isNewUser') ?? true;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF22c55e))));
    }

    if (_isNewUser) {
      return OnboardingView(
        onFinish: () => setState(() => _isNewUser = false),
      );
    }

    return const MainNavigation();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _views = [
    const HomeView(), // A nossa nova Home ligada!
    const Center(child: Text('Treinos', style: TextStyle(fontSize: 24))),
    const Center(child: Text('Progresso', style: TextStyle(fontSize: 24))),
    const Center(child: Text('Perfil', style: TextStyle(fontSize: 24))),
    const ProfileView(),
  ];

  final List<Map<String, dynamic>> _navItems = [
    {'icon': LucideIcons.home, 'label': 'Início'},
    {'icon': LucideIcons.dumbbell, 'label': 'Treinos'},
    {'icon': LucideIcons.barChart2, 'label': 'Progresso'},
    {'icon': LucideIcons.user, 'label': 'Perfil'},
  ];

@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _views[_currentIndex],
      // --- BARRA DE NAVEGAÇÃO CUSTOMIZADA E ANIMADA ---
      bottomNavigationBar: Container(
        height: 88, // Altura confortável para os dedos
        padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16, top: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0a0a0a).withOpacity(0.95),
          border: const Border(top: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_navItems.length, (index) {
            bool isSelected = _currentIndex == index;

            return GestureDetector(
              onTap: () => setState(() => _currentIndex = index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic, // Curva suave e elástica
                padding: EdgeInsets.symmetric(
                  horizontal: isSelected ? 20 : 12, 
                  vertical: 12
                ),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? const Color(0xFF22c55e).withOpacity(0.15) 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    // Animação de escala e cor no ícone
                    AnimatedScale(
                      scale: isSelected ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        _navItems[index]['icon'],
                        color: isSelected ? const Color(0xFF22c55e) : Colors.grey.shade600,
                        size: 24,
                      ),
                    ),
                    
                    // O texto só aparece se o ícone estiver selecionado
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: SizedBox(
                        width: isSelected ? null : 0,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            _navItems[index]['label'],
                            style: const TextStyle(
                              color: Color(0xFF22c55e),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
