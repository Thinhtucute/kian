import 'dart:math';
import 'package:flutter/foundation.dart';
import 'fsrs_database.dart';
import 'fsrs_algorithm.dart';

class FSRSReviewService {
  static Future<Map<String, dynamic>> processReview(int entryId, bool isGood,
      {int? reviewDuration}) async {
    final db = await FSRSDatabase.getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Get current card state
    final cards =
        await db.query('cards', where: 'entry_id = ?', whereArgs: [entryId]);
    if (cards.isEmpty) throw Exception('Card not found');

    final card = cards.first;

    // Get FSRS parameters
    final params = await db.query('fsrs_config', limit: 1);
    final config = params.first;

    // Calculate elapsed time in minutes
    final lastReview = card['last_review'] as int?;
    final elapsedMinutes = lastReview != null ? (now - lastReview) / 60.0 : 0.0;

    // Current state
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();

    // Calculate retrievability
    final retrievability = lastReview != null
        ? FSRSAlgorithm.calculateRetrievability(elapsedMinutes, stability)
        : 1.0;

    // Update difficulty
    final w = (config['w'] as num).toDouble();
    final newDifficulty = FSRSAlgorithm.updateDifficulty(difficulty, isGood, w);

    // Update stability and calculate next interval
    double newStability;
    int newLapses = (card['lapses'] as int);

    if (isGood) {
      newStability =
          FSRSAlgorithm.updateStability(stability, difficulty, retrievability);
    } else {
      newStability = difficulty * 30.0; // Reset to ~30 minutes
      newLapses++;
    }

    // Calculate next due date
    final targetRetention = (config['target_retention'] as num).toDouble();
    double nextIntervalMinutes =
        FSRSAlgorithm.calculateInterval(newStability, targetRetention);

    // Minimum 2-day interval for Good reviews
    if (isGood) {
      final againInterval = difficulty * 30.0;
      nextIntervalMinutes =
          max(nextIntervalMinutes, max(againInterval * 2, 2880.0));
      debugPrint(
          'Enforcing minimum interval: ${nextIntervalMinutes} minutes for good review');
    }

    // Convert to seconds for database
    final newDue = now + (nextIntervalMinutes * 60).round();

    debugPrint('Review processed for entry $entryId:');
    debugPrint('Current time: $now (${DateTime.fromMillisecondsSinceEpoch(now * 1000)})');
    debugPrint('Next interval: ${nextIntervalMinutes} minutes');
    debugPrint('New due time: $newDue (${DateTime.fromMillisecondsSinceEpoch(newDue * 1000)})');
    debugPrint('Hours until due: ${(newDue - now) / 3600} hours');

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
      'formatted_interval': FSRSAlgorithm.formatInterval(nextIntervalMinutes)
    };
  }

  static Future<Map<String, String>> getPredictedIntervals(int entryId) async {
    final db = await FSRSDatabase.getDatabase();

    final cards =
        await db.query('cards', where: 'entry_id = ?', whereArgs: [entryId]);
    if (cards.isEmpty) return {'again': '< 10 min', 'good': '1 day'};

    final params = await db.query('fsrs_config', limit: 1);
    return FSRSAlgorithm.getPredictedIntervals(cards.first, params.first);
  }
}
