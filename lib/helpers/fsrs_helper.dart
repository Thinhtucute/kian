import 'dart:io';
import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dictionary_helper.dart';
import 'package:flutter/foundation.dart';

class FSRSHelper {
  static final FSRSHelper _instance = FSRSHelper._internal();
  static Database? _database;
  static const String _dbName = "fsrs.db";
  static bool _initialized = false;

  factory FSRSHelper() {
    return _instance;
  }

  FSRSHelper._internal();

  static Future<void> initialize() async {
    if (_initialized) return;

    // Make sure dictionary helper is initialized
    await DictionaryHelper.initialize();

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
        stability REAL NOT NULL DEFAULT 30.0,
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

      // FSRS parameters table
      await txn.execute('''
      CREATE TABLE fsrs_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        w REAL NOT NULL DEFAULT 0.1,
        target_retention REAL NOT NULL DEFAULT 0.9
      )
      ''');

      // Insert default parameters
      await txn.execute('''
      INSERT INTO fsrs_config (id, w, target_retention) 
      VALUES (1, 0.1, 0.9)
      ''');

      // Create indexes for performance
      await txn.execute('CREATE INDEX idx_cards_due ON cards(due)');
      await txn.execute('CREATE INDEX idx_reviews_entry ON reviews(entry_id)');
    });

    debugPrint('FSRS schema created');
  }

  // Add a dictionary entry to the spaced repetition system
  static Future<bool> addToFSRS(int entryId) async {
    try {
      debugPrint('Starting addToFSRS for entry ID: $entryId');

      final db = await getDatabase();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Check if already added to FSRS first (this is a fast check)
      debugPrint('Checking if entry already exists in FSRS...');
      final existing = await db.query('cards',
          where: 'entry_id = ?', whereArgs: [entryId], limit: 1);

      if (existing.isNotEmpty) {
        debugPrint('Entry already exists in FSRS');
        return false;
      }

      // Now try to find it in the dictionary
      debugPrint('Checking if entry exists in dictionary...');
      try {
        final entry = await DictionaryHelper.getEntryById(entryId);

        if (entry == null) {
          debugPrint('Entry with ID $entryId not found in dictionary');
          return false;
        }

        debugPrint('Found dictionary entry: $entry');
      } catch (dictError) {
        // Just log but continue - we'll add the entry anyway
        debugPrint('Warning: Could not verify dictionary entry: $dictError');
        // We'll continue and add the card even if dictionary lookup fails
      }

      // Add to cards table
      debugPrint('Adding entry to FSRS...');
      await db.insert('cards', {
        'entry_id': entryId,
        'stability': 30.0,
        'difficulty': 0.3,
        'due': now,
        'last_review': null,
        'reps': 0,
        'lapses': 0,
        'suspended': 0,
        'created_at': now
      });

      debugPrint('Successfully added entry $entryId to FSRS');
      return true;
    } catch (e) {
      debugPrint('Error in addToFSRS: $e');
      return false;
    }
  }

  // Get the next due cards for review
  static Future<List<Map<String, dynamic>>> getDueCards({int limit = 20}) async {
    final db = await getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // First try to get cards that are already due
    final dueCards = await db.query('cards',
        where: 'due <= ? AND suspended = 0',
        whereArgs: [now],
        orderBy: 'due ASC',
        limit: limit);

    // If we have due cards, use those
    List<Map<String, dynamic>> cardsToReview = dueCards;
    bool showingSoonDue = false;

    // If no due cards are found, get cards due within 24 hours
    if (dueCards.isEmpty) {
      final soonDueCards = await db.query('cards',
          where: 'due > ? AND due <= ? AND suspended = 0',
          whereArgs: [now, now + 86400], // + 24 hours
          orderBy: 'due ASC',
          limit: limit);
      cardsToReview = soonDueCards;
      showingSoonDue = true;
    }
    // If we still don't have cards to review, return empty list
    if (cardsToReview.isEmpty) {
      return [];
    }

    // Enrich with dictionary data
    List<Map<String, dynamic>> enrichedCards = [];
    for (var card in cardsToReview) {
      final entryId = card['entry_id'] as int;

      try {
        final entry = await DictionaryHelper.getEntryById(entryId);

        if (entry != null) {
          // Combine card data with dictionary data
          Map<String, dynamic> enrichedCard = {...card};
          enrichedCard['keb'] = entry['keb'];
          enrichedCard['reb'] = entry['reb'];
          enrichedCard['gloss'] = entry['gloss'];

          // Add metadata for soon-due cards
          if (showingSoonDue) {
            enrichedCard['due_early'] = true;
            enrichedCard['hours_until_due'] =
                ((card['due'] as int) - now) / 3600;
          } else {
            enrichedCard['due_early'] = false;
          }

          enrichedCards.add(enrichedCard);
        }
      } catch (e) {
        debugPrint('Error enriching card $entryId: $e');
        // Continue with next card
      }
    }

    return enrichedCards;
  }

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

    // Calculate elapsed time since last review in MINUTES
    final lastReview = card['last_review'] as int?;
    final elapsedMinutes = lastReview != null
        ? (now - lastReview) / 60.0 // Convert seconds to minutes
        : 0.0;

    // Current state
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();

    // Calculate retrievability based on elapsed time
    final retrievability = lastReview != null
        ? _calculateRetrievability(elapsedMinutes, stability)
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
      newStability = difficulty * 30.0; // Reset to ~30 minutes
      newLapses++;
    }

    // Calculate next due date based on target retention (in minutes)
    final targetRetention = (config['target_retention'] as num).toDouble();
    final nextIntervalMinutes =
        _calculateInterval(newStability, targetRetention);

    // Convert minutes to seconds for database storage
    final newDue = now + (nextIntervalMinutes * 60).round();

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
      'elapsed_minutes': elapsedMinutes,
      'scheduled_minutes': nextIntervalMinutes,
      'review_duration': reviewDuration
    });

    return {
      'due': newDue,
      'stability': newStability,
      'difficulty': newDifficulty,
      'interval_minutes': nextIntervalMinutes,
      'formatted_interval': _formatInterval(nextIntervalMinutes)
    };
  }

  // Get statistics for a card
  static Future<Map<String, dynamic>> getCardStats(int entryId) async {
    final db = await getDatabase();

    // Get card state
    final cards =
        await db.query('cards', where: 'entry_id = ?', whereArgs: [entryId]);

    if (cards.isEmpty) {
      return {'found': false};
    }

    final card = cards.first;

    // Get review history
    final reviews = await db.query('reviews',
        where: 'entry_id = ?', whereArgs: [entryId], orderBy: 'timestamp DESC');

    // Calculate success rate
    int totalReviews = reviews.length;
    int successfulReviews = reviews.where((r) => r['rating'] == 1).length;
    double successRate =
        totalReviews > 0 ? successfulReviews / totalReviews : 0.0;

    return {
      'found': true,
      'reps': card['reps'],
      'lapses': card['lapses'],
      'difficulty': card['difficulty'],
      'stability': card['stability'],
      'due_date':
          DateTime.fromMillisecondsSinceEpoch((card['due'] as int) * 1000),
      'success_rate': successRate,
      'review_history': reviews,
    };
  }

  // Helper methods for FSRS calculations
  static double _calculateRetrievability(
      double elapsedMinutes, double stabilityMinutes) {
    return exp(-elapsedMinutes / stabilityMinutes);
  }

  static double _updateDifficulty(double difficulty, bool recalled, double w) {
    final delta = recalled ? (1.0 - difficulty) : -difficulty;
    final newDifficulty = difficulty + w * delta;
    return newDifficulty.clamp(0.1, 1.0);
  }

  static double _updateStability(
      double stabilityMinutes, double difficulty, double retrievability) {
    final a = 0.5 / difficulty;
    return stabilityMinutes * (1.0 + a * (1.0 - retrievability));
  }

  static double _calculateInterval(
      double stabilityMinutes, double targetRetention) {
    final exactInterval = -stabilityMinutes * log(targetRetention);
    final randomFactor = 0.95 + (0.1 * DateTime.now().millisecond / 1000);
    return max(10.0, exactInterval * randomFactor);
  }

  static String _formatInterval(double minutes) {
    if (minutes < 60) {
      return '${minutes.round()} min';
    } else if (minutes < 1440) {
      // Less than a day
      return '${(minutes / 60).round()} hr';
    } else if (minutes < 43200) {
      // Less than a month
      return '${(minutes / 1440).round()} days';
    } else {
      return '${(minutes / 43200).round()} months';
    }
  }
}
