import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static const String _dbName = "jmdict_fts5.db";
  static bool _initialized = false;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

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
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        print('Database opened with FFI support');
      },
    );
  }

  static Future<void> debugTableStructure() async {
    final db = await getDatabase();

    print('\nChecking database structure...');
    final mainTables = ['kanji_element', 'reading_element', 'sense', 'gloss'];

    for (final table in mainTables) {
      try {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        print('\n$table columns:');
        for (var col in columns) {
          print('  ${col['name']} (${col['type']})');
        }

        // Get sample data
        final sample = await db.rawQuery('SELECT * FROM $table LIMIT 1');
        if (sample.isNotEmpty) {
          print('  Sample row: ${sample.first}');
        } else {
          print('  No data in table');
        }
      } catch (e) {
        print('Error checking $table: $e');
      }
    }

    print('\nChecking FTS5 tables...');
    final ftsTables = ['kanji_fts', 'reading_fts', 'gloss_fts'];

    for (final table in ftsTables) {
      try {
        // Try a simple query to understand structure
        final sample = await db.rawQuery('SELECT * FROM $table LIMIT 1');
        print('\n$table available columns:');
        if (sample.isNotEmpty) {
          print('  Columns: ${sample.first.keys.join(', ')}');
          print('  Sample: ${sample.first}');
        } else {
          print('  Table exists but is empty');
        }
      } catch (e) {
        print('Error checking $table: $e');
      }
    }
  }

  static Future<bool> testFTS5Functionality() async {
    final db = await getDatabase();
    print('\nTesting FTS5 functionality...');

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
        print(
            '✅ FTS5 MATCH query worked! Found ${results.length} results for "$testQuery"');
        print('First result: ${results.first}');
        return true;
      } else {
        print(
            '⚠️ FTS5 MATCH query syntax worked but no results found for "$testQuery"');
        // Try another common word
        final backup = await db.rawQuery("""
          SELECT * FROM kanji_fts 
          WHERE keb MATCH ? 
          LIMIT 5
        """, ["人*"]);

        if (backup.isNotEmpty) {
          print(
              '✅ Backup FTS5 test worked! Found ${backup.length} results for "人*"');
          return true;
        }
        print('No results found for common words. Check your data.');
        return false;
      }
    } catch (e) {
      print('❌ FTS5 MATCH query failed with error: $e');
      print('FTS5 functionality appears to be unavailable');
      return false;
    }
  }

  static Future<void> initializeFSRS() async {
    final db = await getDatabase();

    await db.transaction((txn) async {
      // Card state table - tracks review status of dictionary entries
      await txn.execute('''
    CREATE TABLE IF NOT EXISTS cards (
      entry_id INTEGER PRIMARY KEY,
      stability REAL NOT NULL DEFAULT 1.0,
      difficulty REAL NOT NULL DEFAULT 0.3,
      due INTEGER NOT NULL,
      last_review INTEGER,
      reps INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0,
      suspended INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''');

      // Review log table - records each review
      await txn.execute('''
    CREATE TABLE IF NOT EXISTS reviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      timestamp INTEGER NOT NULL,
      rating INTEGER NOT NULL, 
      elapsed_days REAL NOT NULL,
      scheduled_days REAL NOT NULL,
      review_duration INTEGER,
      FOREIGN KEY(entry_id) REFERENCES cards(entry_id)
    )
    ''');

      // FSRS parameters
      await txn.execute('''
    CREATE TABLE IF NOT EXISTS fsrs_config (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      w REAL NOT NULL DEFAULT 0.1,
      target_retention REAL NOT NULL DEFAULT 0.9
    )
    ''');

      // Insert default parameters if not exists
      await txn.execute('''
    INSERT OR IGNORE INTO fsrs_config (id, w, target_retention) 
    VALUES (1, 0.1, 0.9)
    ''');

      // Create indexes for performance
      await txn
          .execute('CREATE INDEX IF NOT EXISTS idx_cards_due ON cards(due)');
      await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_reviews_entry ON reviews(entry_id)');
    });

    print('FSRS schema initialized');
  }

// Add a dictionary entry to the spaced repetition system
  static Future<bool> addToFSRS(int entryId) async {
    final db = await getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Check if entry exists in the dictionary
    final entry = await db.query('kanji_element',
        where: 'ent_seq = ?', whereArgs: [entryId], limit: 1);

    if (entry.isEmpty) {
      return false;
    }

    // Check if already added
    final existing = await db.query('cards',
        where: 'entry_id = ?', whereArgs: [entryId], limit: 1);

    if (existing.isNotEmpty) {
      return false; // Already added
    }

    // Add to cards table
    await db.insert('cards', {
      'entry_id': entryId,
      'stability': 1.0, // Initial stability (1 day)
      'difficulty': 0.3, // Initial difficulty (moderate)
      'due': now, // Due immediately
      'last_review': null,
      'reps': 0,
      'lapses': 0,
      'suspended': 0,
      'created_at': now
    });

    return true;
  }

// Get the next due cards for review
  static Future<List<Map<String, dynamic>>> getDueCards(
      {int limit = 20}) async {
    final db = await getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Get due cards joined with dictionary data
    return await db.rawQuery('''
    SELECT c.*, k.keb, r.reb, g.gloss
    FROM cards c
    LEFT JOIN kanji_element k ON c.entry_id = k.ent_seq
    LEFT JOIN reading_element r ON c.entry_id = r.ent_seq AND r.id = (
      SELECT MIN(id) FROM reading_element WHERE ent_seq = c.entry_id
    )
    LEFT JOIN sense s ON c.entry_id = s.ent_seq AND s.id = (
      SELECT MIN(id) FROM sense WHERE ent_seq = c.entry_id
    )
    LEFT JOIN gloss g ON s.id = g.sense_id AND g.id = (
      SELECT MIN(id) FROM gloss WHERE sense_id = s.id
    )
    WHERE c.due <= ? AND c.suspended = 0
    GROUP BY c.entry_id
    ORDER BY c.due ASC
    LIMIT ?
  ''', [now, limit]);
  }

// Process a review response (again=false, good=true)
  static Future<Map<String, dynamic>> processReview(int entryId, bool isGood,
      {int? reviewDuration}) async {
    final db = await getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Get current card state
    final cards =
        await db.query('cards', where: 'entry_id = ?', whereArgs: [entryId]);

    if (cards.isEmpty) {
      throw Exception('Card not found');
    }

    final card = cards.first;

    // Get FSRS parameters
    final params = await db.query('fsrs_config', limit: 1);
    final config = params.first;

    // Calculate elapsed time since last review
    final lastReview = card['last_review'] as int?;
    final elapsedDays = lastReview != null
        ? (now - lastReview) / 86400.0 // Convert seconds to days
        : 0.0;

    // Current state
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();

    // Calculate retrievability based on elapsed time
    final retrievability = lastReview != null
        ? _calculateRetrievability(elapsedDays, stability)
        : 1.0;

    // Update difficulty
    final w = (config['w'] as num).toDouble();
    final newDifficulty = _updateDifficulty(difficulty, isGood, w);

    // Update stability and calculate next interval
    double newStability;
    int newLapses = (card['lapses'] as int);

    if (isGood) {
      // If successful recall, increase stability
      newStability = _updateStability(stability, difficulty, retrievability);
    } else {
      // If forgotten, reset stability and increment lapses
      newStability = difficulty * 1.0; // Reset to base value
      newLapses++;
    }

    // Calculate next due date based on target retention
    final targetRetention = (config['target_retention'] as num).toDouble();
    final nextInterval = _calculateInterval(newStability, targetRetention);
    final newDue =
        now + (nextInterval * 86400).round(); // Convert days to seconds

    // Update card
    await db.update(
        'cards',
        {
          'stability': newStability,
          'difficulty': newDifficulty,
          'due': newDue,
          'last_review': now,
          'reps': (card['reps'] as int) + 1,
          'lapses': newLapses
        },
        where: 'entry_id = ?',
        whereArgs: [entryId]);

    // Log the review
    await db.insert('reviews', {
      'entry_id': entryId,
      'timestamp': now,
      'rating': isGood ? 1 : 0,
      'elapsed_days': elapsedDays,
      'scheduled_days': nextInterval,
      'review_duration': reviewDuration
    });

    return {
      'due': newDue,
      'stability': newStability,
      'difficulty': newDifficulty,
      'interval_days': nextInterval
    };
  }

// Helper methods for FSRS calculations
  static double _calculateRetrievability(double elapsedDays, double stability) {
    // R(t) = e^(-t/S)
    return exp(-elapsedDays / stability);
  }

  static double _updateDifficulty(double difficulty, bool recalled, double w) {
    // D_new = D_old + W × (if_recalled ? (1 - D_old) : (0 - D_old))
    final delta = recalled ? (1.0 - difficulty) : -difficulty;
    final newDifficulty = difficulty + w * delta;

    // Keep difficulty between 0.1 and 1.0
    return newDifficulty.clamp(0.1, 1.0);
  }

  static double _updateStability(
      double stability, double difficulty, double retrievability) {
    // S_new = S_old × (1 + a × (1 - R(t)))
    // Where a is a scaling factor, we'll use (1/difficulty) as the scaling factor
    final a = 0.5 / difficulty;
    return stability * (1.0 + a * (1.0 - retrievability));
  }

  static double _calculateInterval(double stability, double targetRetention) {
    // t = -S × ln(Target_retention)
    // But we'll add a small random factor to avoid same-day reviews
    final exactInterval = -stability * log(targetRetention);
    final randomFactor = 0.95 + (0.1 * DateTime.now().millisecond / 1000);

    // Minimum interval of 1 day
    return max(1.0, exactInterval * randomFactor);
  }
}
