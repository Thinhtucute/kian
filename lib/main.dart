import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/learn_screen.dart';
import 'screens/dictionary_screen.dart';
import 'helpers/dictionary_helper.dart';
import 'helpers/fsrs/fsrs_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    debugPrint("Starting FFI support initialization...");
    await DictionaryHelper.initialize();
    
    await DictionaryHelper.debugTableStructure();
    final fts5Works = await DictionaryHelper.testFTS5Functionality();
    debugPrint('FTS5 functionality is ${fts5Works ? 'available' : 'not available'}.');
    
    debugPrint("Initializing database...");
    await FSRSDatabase.initialize();
    
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
      theme: ThemeData.dark(),
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
    _databaseFuture = FSRSDatabase.getDatabase();
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
          );
        }
      },
    );
  }
}