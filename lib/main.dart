import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/learn_screen.dart';
import 'screens/dictionary_screen.dart';
import 'screens/login_screen.dart';
import 'models/session_model.dart';
import 'models/sync_model.dart';
import 'services/cloud/auth_service.dart';
import 'screens/bootstrap_screen.dart';
import 'widgets/sync_banner.dart';
import 'core/db_factory.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DatabaseFactories.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const BootstrapScreen(
        child: AuthWrapper(),
      ),
    );
  }
}

// Wrapper to handle auth state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && AuthService.isLoggedIn) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [LearnScreen(), DictionaryScreen()];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
          return MultiProvider( 
            providers: [
              ChangeNotifierProvider(
                create: (_) => LearnSessionModel(),
              ),
              ChangeNotifierProvider(
                create: (_) => SyncModel(),
              ),
            ],
            child: Scaffold(
              body: Stack(
                children: [
                  _screens[_selectedIndex],
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: const SyncBanner(),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: BottomNavigationBar(
                backgroundColor: const Color.fromARGB(255, 9, 12, 43),
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.grey,
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.school),
                    label: 'Learn',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.book),
                    label: 'Dictionary',
                  ),
                ],
              ),
            ),
          );
    }
}
