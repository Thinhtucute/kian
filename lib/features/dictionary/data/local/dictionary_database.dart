import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:kian/core/logger.dart';

class DictionaryDatabase {
  static Database? _database;
  static const String _dbName = 'dictionary.db';
  static bool _initialized = false;
  static const List<String> _expectedTables = [
    'entry',
    'headword',
    'sense',
    'definition',
    'example',
    'headword_fts',
    'definition_fts',
  ];

  static Future<void> initialize() async {
    if (_initialized) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    _initialized = true;
  }

  static Future<Database> getDatabase() async {
    await initialize();

    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, _dbName);

    if (!await _hasValidDatabase(File(dbPath))) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      final data = await rootBundle.load('assets/$_dbName');
      final bytes = data.buffer.asUint8List();
      await dbFile.writeAsBytes(bytes, flush: true);
    }

    return openDatabase(
      dbPath,
      readOnly: true,
      onOpen: (db) async {
        kLog('Dictionary database opened in read-only mode');
      },
    );
  }

  static Future<bool> _hasValidDatabase(File dbFile) async {
    if (!await dbFile.exists() || await dbFile.length() == 0) {
      return false;
    }

    try {
      final db = await openDatabase(
        dbFile.path,
        readOnly: true,
      );

      try {
        final tables = await db.rawQuery("""
          SELECT name
          FROM sqlite_master
          WHERE type = 'table'
        """);
        final tableNames = tables
            .map((row) => row['name']?.toString())
            .whereType<String>()
            .toSet();

        return _expectedTables.every(tableNames.contains);
      } finally {
        await db.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> debugTableStructure() async {
    final db = await getDatabase();

    kLog('\nChecking dictionary structure...');
    final mainTables = ['entry', 'headword', 'sense', 'definition', 'example'];

    for (final table in mainTables) {
      try {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        kLog('\n$table columns:');
        for (var col in columns) {
          kLog('  ${col['name']} (${col['type']})');
        }

        final sample = await db.rawQuery('SELECT * FROM $table LIMIT 1');
        if (sample.isNotEmpty) {
          kLog('- Sample row: ${sample.first}');
        } else {
          kLog('- No data in table');
        }
      } catch (e) {
        kLog('Error checking $table: $e');
      }
    }

    kLog('\nChecking FTS5 tables...');
    final ftsTables = ['headword_fts', 'definition_fts', 'example_fts'];

    for (final table in ftsTables) {
      try {
        final sample = await db.rawQuery('SELECT * FROM $table LIMIT 1');
        kLog('\n$table available columns:');
        if (sample.isNotEmpty) {
          kLog('- Columns: ${sample.first.keys.join(', ')}');
          kLog('- Sample: ${sample.first}');
        } else {
          kLog('  Table exists but is empty');
        }
      } catch (e) {
        kLog('Error checking $table: $e');
      }
    }
  }

  static Future<bool> testFTS5Functionality() async {
    final db = await getDatabase();
    kLog('\nTesting FTS5 functionality...');

    try {
      const testQuery = '食べ*';

      final results = await db.rawQuery("""
        SELECT * FROM headword_fts
        WHERE text MATCH ?
        LIMIT 5
      """, [testQuery]);

      if (results.isNotEmpty) {
        kLog('✅ FTS5 MATCH query worked. Found ${results.length} results for "$testQuery"');
        kLog('First result: ${results.first}');
        return true;
      } else {
        kLog('⚠️ FTS5 MATCH query syntax worked but no results found for "$testQuery"');
        final backup = await db.rawQuery("""
          SELECT * FROM headword_fts
          WHERE text MATCH ?
          LIMIT 5
        """, ['人*']);

        if (backup.isNotEmpty) {
          kLog('✅ Backup FTS5 test worked. Found ${backup.length} results for "人*"');
          return true;
        }
        kLog('No results found for common words. Check your data.');
        return false;
      }
    } catch (e) {
      kLog('❌ FTS5 MATCH query failed with error: $e');
      kLog('FTS5 functionality appears to be unavailable');
      return false;
    }
  }
}
