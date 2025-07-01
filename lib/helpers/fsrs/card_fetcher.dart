import 'package:flutter/foundation.dart';
import 'fsrs_database.dart';
import '../dictionary_helper.dart';

class FSRSCardService {
  // Add a dictionary entry to FSRS
  static Future<bool> addCard(int entryId) async {
    try {
      debugPrint('Adding entry $entryId to FSRS');
      final db = await FSRSDatabase.getDatabase();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Check if already exists
      final existing = await db.query('cards',
          where: 'entry_id = ?', whereArgs: [entryId], limit: 1);
      if (existing.isNotEmpty) return false;

      // Add to cards table
      await db.insert('cards', {
        'entry_id': entryId,
        'stability': 2880.0,
        'difficulty': 0.3,
        'due': now,
        'last_review': null,
        'reps': 0,
        'lapses': 0,
        'suspended': 0,
        'created_at': now
      });

      return true;
    } catch (e) {
      debugPrint('Error adding card: $e');
      return false;
    }
  }

  // Get cards due for review
  static Future<List<Map<String, dynamic>>> getDueCards({int limit = 20}) async {
    final db = await FSRSDatabase.getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Get cards due now
    final dueCards = await db.query('cards',
        where: 'due <= ? AND suspended = 0',
        whereArgs: [now],
        orderBy: 'due ASC',
        limit: limit);

    List<Map<String, dynamic>> cardsToReview = dueCards;
    bool showingSoonDue = false;

    // If no due cards, get cards due within 24h
    if (dueCards.isEmpty) {
      final soonDueCards = await db.query('cards',
          where: 'due > ? AND due <= ? AND suspended = 0',
          whereArgs: [now, now + 86400],
          orderBy: 'due ASC',
          limit: limit);
      cardsToReview = soonDueCards;
      showingSoonDue = true;
    }

    if (cardsToReview.isEmpty) return [];

    // Enrich with dictionary data
    List<Map<String, dynamic>> enrichedCards = [];
    for (var card in cardsToReview) {
      final entryId = card['entry_id'] as int;
      try {
        final entry = await DictionaryHelper.getEntryById(entryId);
        if (entry != null) {
          Map<String, dynamic> enrichedCard = {...card};
          enrichedCard['keb'] = entry['keb'];
          enrichedCard['reb'] = entry['reb'];
          enrichedCard['gloss'] = entry['gloss'];
          enrichedCard['due_early'] = showingSoonDue;
          if (showingSoonDue) {
            enrichedCard['hours_until_due'] = ((card['due'] as int) - now) / 3600;
          }
          enrichedCards.add(enrichedCard);
        }
      } catch (e) {
        debugPrint('Error enriching card $entryId: $e');
      }
    }

    return enrichedCards;
  }

  // Get card statistics
  static Future<Map<String, dynamic>> getCardStats(int entryId) async {
    final db = await FSRSDatabase.getDatabase();

    final cards = await db.query('cards', where: 'entry_id = ?', whereArgs: [entryId]);
    if (cards.isEmpty) return {'found': false};

    final card = cards.first;
    final reviews = await db.query('reviews',
        where: 'entry_id = ?', whereArgs: [entryId], orderBy: 'timestamp DESC');

    int totalReviews = reviews.length;
    int successfulReviews = reviews.where((r) => r['rating'] == 1).length;
    double successRate = totalReviews > 0 ? successfulReviews / totalReviews : 0.0;

    return {
      'found': true,
      'reps': card['reps'],
      'lapses': card['lapses'],
      'difficulty': card['difficulty'],
      'stability': card['stability'],
      'due_date': DateTime.fromMillisecondsSinceEpoch((card['due'] as int) * 1000),
      'success_rate': successRate,
      'review_history': reviews,
    };
  }
}