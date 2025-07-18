import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

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

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        await _createTables(db);
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        debugPrint('FSRS database opened');
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.transaction((txn) async {
      // Cards table
      await txn.execute('''
      CREATE TABLE cards (
        entry_id INTEGER PRIMARY KEY,
        stability REAL NOT NULL DEFAULT 2880.0,
        difficulty REAL NOT NULL DEFAULT 0.3,
        due INTEGER NOT NULL,
        last_review INTEGER,
        reps INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        suspended INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
      ''');

      // Reviews table
      await txn.execute('''
      CREATE TABLE reviews (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        rating INTEGER NOT NULL, 
        elapsed_minutes REAL NOT NULL,
        scheduled_minutes REAL NOT NULL,
        review_duration INTEGER
      )
      ''');

      // Create indexes for performance
      await txn.execute('CREATE INDEX idx_cards_due ON cards(due)');
      await txn.execute('CREATE INDEX idx_reviews_entry ON reviews(entry_id)');
    });

    debugPrint('FSRS schema created');
  }
}
