import 'package:flutter/foundation.dart';
import 'fsrs_database.dart';
import 'fsrs_algorithm.dart';

class FSRSReviewService {
  static const double targetRetention = 0.9;

  static Future<Map<String, dynamic>> processReview(int entSeq, bool isGood,
      {int? reviewDuration}) async {
    final db = await FSRSDatabase.getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch ~/
        (1000 * 60 * 60 * 24); // Convert to days

    // Get current card state
    final cards =
        await db.query('cards', where: 'ent_seq = ?', whereArgs: [entSeq]);
    if (cards.isEmpty) throw Exception('Card not found');

    final card = cards.first;

    // Calculate elapsed time
    final lastReview = card['last_review'] as int?;
    final elapsedDays = lastReview != null
        ? (now - lastReview) // Calculate actual days since last review
        : 2.0;
    // Current state
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();
    final reps = (card['reps'] as int);
    final lapses = (card['lapses'] as int);

    // Determine card state
    final isNewCard = lastReview == null;
    final isLearning =
        reps < 3; // Cards with less than 3 reps are in learning phase

    // Convert boolean isGood to rating string
    final String rating = isGood ? 'good' : 'again';

    // Use the corrected FSRS algorithm
    final FSRSAlgorithm fsrs = FSRSAlgorithm(requestRetention: targetRetention);
    final result = fsrs.processReview(
      entSeq: entSeq,
      rating: rating,
      currentStability: stability,
      currentDifficulty: difficulty,
      elapsedDays: elapsedDays.toDouble(),
      isNewCard: isNewCard,
      isLearningCard: isLearning,
    );

    final newStability = result['stability'] as double;
    final newDifficulty = result['difficulty'] as double;
    final nextIntervalDays = result['interval'] as double;
    final currentRetrievability = result['retrievability'] as double;

    // Update lapse count
    int newLapses = lapses;
    if (!isGood) {
      newLapses++;
    }

    // Store due in days for database
    final newDue = now + nextIntervalDays.round();

    debugPrint('Review processed for entry $entSeq:');
    debugPrint('1. Rating: $rating');
    debugPrint('2. Stability: $stability → $newStability');
    debugPrint('3. Difficulty: $difficulty → $newDifficulty');
    debugPrint('4. Retrievability: $currentRetrievability');
    debugPrint('5. Reps: $reps → ${reps + 1}');
    debugPrint('6. Lapses: $lapses → $newLapses');
    debugPrint('7. Next interval: $nextIntervalDays days');
    debugPrint('8. New due time: $newDue');

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
        where: 'ent_seq = ?',
        whereArgs: [entSeq]);

    // Log the review
    await db.insert('reviews', {
      'ent_seq': entSeq,
      'timestamp': now,
      'rating': isGood ? 3 : 1, // 1 = Again, 3 = Good
      'elapsed_days': elapsedDays,
      'scheduled_days': nextIntervalDays,
      'review_duration': reviewDuration
    });

    return {
      'due': newDue,
      'stability': newStability,
      'difficulty': newDifficulty,
      'interval_days': nextIntervalDays,
      'formatted_interval': FSRSAlgorithm.formatInterval(nextIntervalDays)
    };
  }

  static Future<Map<String, String>> getPredictedIntervals(int entSeq) async {
    final db = await FSRSDatabase.getDatabase();

    final cards =
        await db.query('cards', where: 'ent_seq = ?', whereArgs: [entSeq]);
    if (cards.isEmpty) return {'again': '1 day', 'good': '1 day'};

    final card = cards.first;
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();
    final reps = (card['reps'] as int);
    final lastReview = card['last_review'] as int?;
    final now = DateTime.now().millisecondsSinceEpoch ~/
        (1000 * 60 * 60 * 24); // Convert to days
    final elapsedDays = lastReview != null
        ? (now - lastReview) // Calculate actual days since last review
        : 0.0;
    final isNewCard = lastReview == null;
    final isLearning = reps < 3;

    final FSRSAlgorithm fsrs = FSRSAlgorithm(requestRetention: targetRetention);
    return fsrs.previewIntervals(
        entSeq: entSeq,
        currentStability: stability,
        currentDifficulty: difficulty,
        elapsedDays: elapsedDays.toDouble(),
        isNewCard: isNewCard,
        isLearningCard: isLearning);
  }
}
