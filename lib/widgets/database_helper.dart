import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static const String _dbName = "jmdict_fts5.db";

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    // Enable sqlite3_flutter_libs
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String dbPath = join(documentsDirectory.path, _dbName);

    if (!await File(dbPath).exists()) {
      ByteData data = await rootBundle.load("assets/$_dbName");
      List<int> bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // Verify FTS5 support
        try {
          await db.rawQuery('SELECT sqlite_compileoption_used("fts5")');
          print('FTS5 is available');
        } catch (e) {
          print('FTS5 is not available: $e');
        }
      },
    );
  }
}