import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // For importBundledDatabase()

class FSRSDatabase {
  static Database? _database;
  static const String _dbName = "fsrs.db";
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  static Future<Database> getDatabase() async {
    await initialize();
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String dbPath = join(documentsDirectory.path, _dbName);

    bool dbExists = await File(dbPath).exists();

    try {
      return await openDatabase(
        dbPath,
        version: 3,
        onCreate: dbExists
            ? null
            : (Database db, int version) async {
                await _createTables(db);
              },
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          final result =
              await db.rawQuery('SELECT COUNT(*) as count FROM cards');
          final count = Sqflite.firstIntValue(result) ?? 0;
          debugPrint('FSRS database opened with $count cards');
        },
      );
    } catch (e) {
      debugPrint('Error opening database: $e');

      if (e.toString().contains('no such table')) {
        debugPrint('Schema issue detected - recreating database');
        await File(dbPath).delete();
        return await openDatabase(
          dbPath,
          version: 3,
          onCreate: (Database db, int version) async {
            await _createTables(db);
          },
        );
      }
      rethrow;
    }
  }

  static Future<void> _createTables(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
      CREATE TABLE cards (
        ent_seq INTEGER PRIMARY KEY,
        type INTEGER NOT NULL DEFAULT 0, -- 0: new, 1: learning, 2: review, 3:relearning
        queue INTEGER NOT NULL DEFAULT 0, -- 0: new, 1: learning, 2: review, 3: relearning
        due REAL NOT NULL,
        last_review REAL,
        reps INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        left INTEGER NOT NULL DEFAULT 2,
        stability REAL NOT NULL DEFAULT 2.3065,
        difficulty REAL NOT NULL DEFAULT 6.4133
      )
      ''');
      await txn.execute('CREATE INDEX idx_cards_due ON cards(due)');
    });
    debugPrint('FSRS schema created');
  }

// Import bundled database from assets if not exists in main.dart
  static Future<void> importBundledDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String dbPath = join(documentsDirectory.path, _dbName);
    if (await File(dbPath).exists()) {
      debugPrint("Database already exists at $dbPath");
      return;
    }
    try {
      ByteData data = await rootBundle.load('assets/cards.db');
      List<int> bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes);
      _database = null;
      _initialized = false;
      debugPrint("Imported cards.db from assets");
    } catch (e) {
      debugPrint("Error importing database: $e");
    }
  }
}
