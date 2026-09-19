import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Importações das suas views
import 'views/home_view.dart';
import 'views/workouts_view.dart';
import 'views/progress_view.dart';
import 'views/profile_view.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        primaryColor: const Color(0xFF22c55e),
        scaffoldBackgroundColor: const Color(0xFF0a0a0a),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1c1c1e),
          selectedItemColor: Color(0xFF22c55e),
          unselectedItemColor: Colors.grey,
        ),
      ),
      // StreamBuilder para detetar mudanças de sessão (Login / Logout)
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF22c55e)),
              ),
            );
          }
          
          if (snapshot.hasData) {
            // Utilizador autenticado: Mostra a aplicação principal
            return const MainNavigator();
          }
          
          // Utilizador não autenticado: Aqui chamaria a sua tela de Login ou Onboarding.
          // Se tiver uma OnboardingView(), basta colocar aqui em vez deste Scaffold.
          return const Scaffold(
            body: Center(
              child: Text('Sessão terminada. Por favor, inicie sessão novamente.', style: TextStyle(color: Colors.white)),
            ),
          );
        },
      ),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;

  // Lista de ecrãs. Note que a ProgressView não tem 'const' devido à forma como a construímos.
  final List<Widget> _views = [
    const HomeView(),
    const WorkoutsView(),
    const ProgressView(), 
    const ProfileView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          // Transição premium combinando Fade e Slide
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.05), // Começa ligeiramente abaixo
                end: Offset.zero, // Termina na posição original
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Container(
          // O ValueKey é obrigatório para o Flutter detetar a troca e animar
          key: ValueKey<int>(_currentIndex), 
          child: _views[_currentIndex],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            // Apenas aciona a reconstrução se estiver a mudar para um separador diferente
            if (_currentIndex != index) {
              setState(() => _currentIndex = index);
            }
          },
          backgroundColor: const Color(0xFF1c1c1e),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF22c55e),
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: false,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Início'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.dumbbell), label: 'Treinos'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.barChart2), label: 'Progresso'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}