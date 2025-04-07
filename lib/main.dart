import 'package:flutter/material.dart';
import 'dart:io';  // Add this for File
import 'package:path/path.dart';  // Add this for join
import 'package:path_provider/path_provider.dart';
import 'screens/learn_screen.dart';
import 'screens/dictionary_screen.dart';
import 'helpers/dictionary_helper.dart';
import 'helpers/fsrs_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize DatabaseHelper with FFI support
    debugPrint("Starting initialization...");
    await DictionaryHelper.initialize();
    
    // Test dictionary database
    await DictionaryHelper.debugTableStructure();
    final fts5Works = await DictionaryHelper.testFTS5Functionality();
    debugPrint('FTS5 functionality is ${fts5Works ? 'available' : 'not available'}.');
    
    // Initialize and verify FSRS database
    debugPrint("Initializing FSRS...");
    await FSRSHelper.initialize();
    
    // Verify database paths to ensure proper setup
    debugPrint("Database paths:");
    final docDir = await getApplicationDocumentsDirectory();
    debugPrint("Documents directory: ${docDir.path}");
    final fsrsPath = join(docDir.path, "fsrs.db");
    final dictPath = join(docDir.path, "jmdict_fts5.db");
    debugPrint("FSRS database path: $fsrsPath (exists: ${await File(fsrsPath).exists()})");
    debugPrint("Dictionary path: $dictPath (exists: ${await File(dictPath).exists()})");
  } catch (e) {
    debugPrint("Error during initialization: $e");
  }
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(), // Dark mode theme
      home: MainScreen(),
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
  Future<void>? _databaseFuture;

  @override
  void initState() {
    super.initState();
    _databaseFuture = FSRSHelper.getDatabase();
  }

  final List<Widget> _screens = [LearnScreen(), DictionaryScreen()];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _databaseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        } else {
          return Scaffold(
            body: _screens[_selectedIndex],
            bottomNavigationBar: BottomNavigationBar(
              backgroundColor: const Color.fromARGB(255, 9, 12, 43), // Black bottom tab
              selectedItemColor: Colors.white, // White for selected item
              unselectedItemColor: Colors.grey, // Grey for unselected items
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
          );
        }
      },
    );
  }
}