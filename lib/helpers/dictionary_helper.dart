import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

class DictionaryHelper {
  static final DictionaryHelper _instance = DictionaryHelper._internal();
  static Database? _database;
  static const String _dbName = "jmdict_fts5.db";
  static bool _initialized = false;

  factory DictionaryHelper() {
    return _instance;
  }

  DictionaryHelper._internal();

  static Future<void> initialize() async {
    if (_initialized) return;
    // Initialize FFI for proper FTS5 support
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
      readOnly: true,
      onOpen: (db) async {
        debugPrint('Dictionary database opened in read-only mode');
      },
    );
  }

  static Future<void> debugTableStructure() async {
    final db = await getDatabase();

    debugPrint('\nChecking dictionary structure...');
    final mainTables = ['kanji_element', 'reading_element', 'sense', 'gloss'];

    for (final table in mainTables) {
      try {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        debugPrint('\n$table columns:');
        for (var col in columns) {
          debugPrint('  ${col['name']} (${col['type']})');
        }

        // Get sample data
        final sample = await db.rawQuery('SELECT * FROM $table LIMIT 1');
        if (sample.isNotEmpty) {
          debugPrint('  Sample row: ${sample.first}');
        } else {
          debugPrint('  No data in table');
        }
      } catch (e) {
        debugPrint('Error checking $table: $e');
      }
    }

    debugPrint('\nChecking FTS5 tables...');
    final ftsTables = ['kanji_fts', 'reading_fts', 'gloss_fts'];

    for (final table in ftsTables) {
      try {
        // Try a simple query to understand structure
        final sample = await db.rawQuery('SELECT * FROM $table LIMIT 1');
        debugPrint('\n$table available columns:');
        if (sample.isNotEmpty) {
          debugPrint('  Columns: ${sample.first.keys.join(', ')}');
          debugPrint('  Sample: ${sample.first}');
        } else {
          debugPrint('  Table exists but is empty');
        }
      } catch (e) {
        debugPrint('Error checking $table: $e');
      }
    }
  }

  static Future<bool> testFTS5Functionality() async {
    final db = await getDatabase();
    debugPrint('\nTesting FTS5 functionality...');

    try {
      // Find a word that should exist in your database
      const testQuery = "食べ*";

      // Try an FTS5 search using MATCH
      final results = await db.rawQuery("""
        SELECT * FROM kanji_fts 
        WHERE keb MATCH ? 
        LIMIT 5
      """, [testQuery]);

      if (results.isNotEmpty) {
        debugPrint(
            '✅ FTS5 MATCH query worked! Found ${results.length} results for "$testQuery"');
        debugPrint('First result: ${results.first}');
        return true;
      } else {
        debugPrint(
            '⚠️ FTS5 MATCH query syntax worked but no results found for "$testQuery"');
        // Try another common word
        final backup = await db.rawQuery("""
          SELECT * FROM kanji_fts 
          WHERE keb MATCH ? 
          LIMIT 5
        """, ["人*"]);

        if (backup.isNotEmpty) {
          debugPrint(
              '✅ Backup FTS5 test worked! Found ${backup.length} results for "人*"');
          return true;
        }
        debugPrint('No results found for common words. Check your data.');
        return false;
      }
    } catch (e) {
      debugPrint('❌ FTS5 MATCH query failed with error: $e');
      debugPrint('FTS5 functionality appears to be unavailable');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getEntryById(int entryId) async {
    try {
      final db = await getDatabase();

      debugPrint('Looking up dictionary entry: $entryId');

      // First verify the entry exists in the reading table (all entries should have readings)
      final entryCheck = await db.rawQuery(
          'SELECT ent_seq FROM reading_element WHERE ent_seq = ? LIMIT 1',
          [entryId]);

      if (entryCheck.isEmpty) {
        debugPrint('No entry found with ID $entryId');
        return null;
      }

      // Get reading (should always exist)
      final reading = await db.rawQuery(
          'SELECT reb FROM reading_element WHERE ent_seq = ? LIMIT 1',
          [entryId]);

      // Get kanji (might not exist for kana-only words)
      final kanji = await db.rawQuery(
          'SELECT keb FROM kanji_element WHERE ent_seq = ? LIMIT 1', [entryId]);

      // Determine if this is a kana-only word
      final isKanaOnly = kanji.isEmpty && reading.isNotEmpty;

      // Get gloss/meaning using a simple join
      final gloss = await db.rawQuery('''
      SELECT g.gloss 
      FROM gloss g
      JOIN sense s ON g.sense_id = s.id
      WHERE s.ent_seq = ?
      LIMIT 1
    ''', [entryId]);

      // Build response
      final result = {
        'ent_seq': entryId,
        'keb': kanji.isNotEmpty ? kanji.first['keb'] : null,
        'reb': reading.isNotEmpty ? reading.first['reb'] : null,
        'gloss': gloss.isNotEmpty ? gloss.first['gloss'] : null,
        'is_kana_only': isKanaOnly,
      };

      debugPrint('Found entry: $result');
      return result;
    } catch (e) {
      debugPrint('Error in getEntryById: $e');
      return null;
    }
  }
}
