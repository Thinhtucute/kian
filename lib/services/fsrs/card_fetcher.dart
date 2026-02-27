import 'package:flutter/foundation.dart';
import '../../helpers/fsrs/fsrs_database.dart';
import 'package:sqflite/sqflite.dart';
import '../../helpers/dictionary_helper.dart';
import '../../helpers/logger.dart';

class FSRSCardService {
  // Add a dictionary entry to FSRS
  static Future<bool> addCard(int entSeq) async {
    try {
      kLog('Adding entry $entSeq to FSRS');
      final db = await FSRSDatabase.getDatabase();
      final now = DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24); // Convert to days

      // Check if already exists
      final existing = await db.query('cards',
          where: 'ent_seq = ?', whereArgs: [entSeq], limit: 1);
      if (existing.isNotEmpty) return false;

      // Add to cards table
      await db.insert('cards', {
        'ent_seq': entSeq,
        'type': 0,
        'queue': 0,
        'stability': 0,
        'difficulty': 6.4133,
        'due': now,
        'last_review': null,
        'reps': 0,
        'lapses': 0,
        'left': 2,
      });

      return true;
    } catch (e) {
      kLog('Error adding card: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getCard(int entSeq) async {
    final db = await FSRSDatabase.getDatabase();
    final result = await db.query(
      'cards',
      where: 'ent_seq = ?',
      whereArgs: [entSeq],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  static Future<List<Map<String, dynamic>>> getAllCards() async {
    final db = await FSRSDatabase.getDatabase();
    return await db.query('cards');
  }

  static Future<int> getCardCount() async {
    final db = await FSRSDatabase.getDatabase();
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM cards');
    return result.first['count'] as int;
  }

  static Future<void> upsertCard(Map<String, dynamic> card) async {
    final db = await FSRSDatabase.getDatabase();
    await db.insert('cards', card,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Get cards due for review
  static Future<List<Map<String, dynamic>>> getDueCards(
      {int limit = 999999}) async {
    final db = await FSRSDatabase.getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24);

    List<Map<String, dynamic>> reviews = [];

    // Review cards
    reviews = await db.query('cards',
        where: 'due <= ? AND type = ?',
        whereArgs: [now, 2],
        orderBy: 'due ASC',
        limit: limit);
    kLog('Review cards query returned: ${reviews.length}');

    // Relearning cards
    if (reviews.isEmpty) {
      reviews = await db.query('cards',
          where: 'due <= ? AND left = ?',
          whereArgs: [now, 1],
          orderBy: 'due ASC',
          limit: limit);
      kLog('Relearning cards query returned: ${reviews.length}');
    }

    // Fallback
    if (reviews.isEmpty) {
      reviews = await db.query('cards',
          where: 'due <= ?',
          whereArgs: [now],
          orderBy: 'due ASC',
          limit: limit);
      kLog('Fallback query returned: ${reviews.length}');
    }

    if (reviews.isEmpty) return [];

    // Enrich with dictionary data
    List<Map<String, dynamic>> enrichedCards = [];
    for (var card in reviews) {
      final entSeq = card['ent_seq'] as int;
      try {
        final entry = await DictionaryHelper.getEntryById(entSeq);
        if (entry != null) {
          Map<String, dynamic> enrichedCard = {...card};
          enrichedCard['keb'] = entry['keb'];
          enrichedCard['reb'] = entry['reb'];
          enrichedCard['gloss'] = entry['gloss'];
          enrichedCards.add(enrichedCard);
        }
      } catch (e) {
        kLog('Error enriching card $entSeq: $e');
      }
    }

    return enrichedCards;
  }

  // Get card statistics
  static Future<Map<String, dynamic>> getCardStats(int entSeq) async {
    final db = await FSRSDatabase.getDatabase();

    final cards =
        await db.query('cards', where: 'ent_seq = ?', whereArgs: [entSeq]);
    if (cards.isEmpty) return {'found': false};

    final card = cards.first;
    final reviews = await db.query('reviews',
        where: 'ent_seq = ?', whereArgs: [entSeq], orderBy: 'timestamp DESC');

    int totalReviews = reviews.length;
    int successfulReviews = reviews.where((r) => r['rating'] == 2).length;
    double successRate =
        totalReviews > 0 ? successfulReviews / totalReviews : 0.0;

    return {
      'found': true,
      'reps': card['reps'],
      'lapses': card['lapses'],
      'difficulty': card['difficulty'],
      'stability': card['stability'],
      'due_date': DateTime.fromMillisecondsSinceEpoch(
          ((card['due'] as double) * 1000 * 60 * 60 * 24).toInt()),
      'success_rate': successRate,
      'review_history': reviews,
    };
  }
}
