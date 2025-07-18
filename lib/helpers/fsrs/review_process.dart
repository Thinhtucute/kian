import 'dart:math';
import 'package:flutter/foundation.dart';
import 'fsrs_database.dart';
import 'fsrs_algorithm.dart';

class FSRSReviewService {
  static const double targetRetention = 0.9; // Use as needed

  static Future<Map<String, dynamic>> processReview(int entryId, bool isGood,
      {int? reviewDuration}) async {
    final db = await FSRSDatabase.getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 60000;

    // Get current card state
    final cards =
        await db.query('cards', where: 'entry_id = ?', whereArgs: [entryId]);
    if (cards.isEmpty) throw Exception('Card not found');

    final card = cards.first;

    // Calculate elapsed time
    final lastReview = card['last_review'] as int?;
    final elapsedMinutes =
        lastReview != null ? (now - lastReview).toDouble() : 0.0;

    // Current state
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();
    final reps = (card['reps'] as int);
    final lapses = (card['lapses'] as int);

    // Calculate retrievability (now uses difficulty)
    final retrievability = lastReview != null
        ? FSRSAlgorithm.calculateRetrievability(
            elapsedMinutes, stability, difficulty)
        : 1.0;

    // Update difficulty using reps/lapses/rating/retrievability
    final newDifficulty = FSRSAlgorithm.updateDifficulty(
      difficulty,
      isGood,
      isGood ? 3 : 1, // rating: 3=Good, 1=Again
      retrievability,
      reps,
      lapses,
    );

    // Update stability and calculate next interval
    double newStability;
    int newLapses = lapses;

    if (isGood) {
      newStability = FSRSAlgorithm.updateStabilityGood(
        stability,
        retrievability,
        reps: reps,
        lapses: lapses,
      );
    } else {
      newStability = FSRSAlgorithm.updateStabilityAgain(
        difficulty,
        reps: reps,
        lapses: lapses,
      );
      newLapses++;
    }

    // Calculate next due date
    double nextIntervalMinutes =
        FSRSAlgorithm.calculateInterval(newStability, targetRetention);

    // Only enforce minimum for new cards or cards recovering from lapses
    if (isGood) {
      // Check if this is a new card or lapsed
      if (reps == 0 || lapses > 0) {
        final againInterval = difficulty * 30.0;
        nextIntervalMinutes =
            max(nextIntervalMinutes, max(againInterval * 2, 2880.0));
        debugPrint(
            'New/Recovery card - enforcing minimum interval: $nextIntervalMinutes minutes');
      } else {
        debugPrint(
            'Mature card - using calculated interval: $nextIntervalMinutes minutes');
      }
    }

    // Store due in minutes for database
    final newDue = now + nextIntervalMinutes.round();

    debugPrint('Review processed for entry $entryId:');
    debugPrint('1. Stability: $stability → $newStability');
    debugPrint('2. Difficulty: $difficulty → $newDifficulty');
    debugPrint('3. Retrievability: $retrievability');
    debugPrint('4. Reps: $reps → ${reps + 1}');
    debugPrint('5. Lapses: $lapses → $newLapses');
    debugPrint('6. Current time: $now (${DateTime.fromMillisecondsSinceEpoch(now * 60000)})');
    debugPrint('7. Next interval: $nextIntervalMinutes minutes');
    debugPrint('8. New due time: $newDue (${DateTime.fromMillisecondsSinceEpoch(newDue * 60000)})');
    debugPrint('9. Hours until due: ${(newDue - now) / 60} hours');

    // Update card
    await db.update(
        'cards',
        {
          'stability': newStability,
          'difficulty': newDifficulty,
          'due': newDue,
          'last_review': now,
          'reps': reps + 1,
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

    final card = cards.first;
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();
    final lastReview = card['last_review'] as int?;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final elapsedMinutes =
        lastReview != null ? (now - lastReview).toDouble() : 0.0;
    final retrievability = lastReview != null
        ? FSRSAlgorithm.calculateRetrievability(
            elapsedMinutes, stability, difficulty)
        : 1.0;
    final reps = (card['reps'] as int);
    final lapses = (card['lapses'] as int);

    return FSRSAlgorithm.getPredictedIntervals(
      stability,
      difficulty,
      retrievability,
      targetRetention,
      reps: reps,
      lapses: lapses,
    );
  }
}