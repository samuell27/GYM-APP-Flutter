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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _views[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF0a0a0a),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF22c55e),
        unselectedItemColor: Colors.grey.shade600,
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.dumbbell), label: 'Treinos'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.barChart2), label: 'Progresso'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Perfil'),
        ],
      ),
    );
  }
}
