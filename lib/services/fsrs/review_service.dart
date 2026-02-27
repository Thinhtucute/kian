import 'package:flutter/foundation.dart';
import '../../helpers/fsrs/fsrs_database.dart';
import '../../helpers/fsrs/fsrs_algorithm.dart';
import 'package:kian/services/dictionary/dict_entry.dart';
import '../../services/cloud/sync_service.dart';
import '../../helpers/logger.dart';

class FSRSReviewService {
  static const List<String> names = ['New', 'Learning', 'Review', 'Relearning'];
  // Get vocab by entSeq
  static Future<String> getVocabForEntry(int entSeq) async {
    try {
      final entry = await DictionaryEntryService.getEntryById(entSeq);
      if (entry == null) {
        return "Unknown Vocab";
      }
      final keb = entry['keb'] as String?;
      final reb = entry['reb'] as String?;
      if (keb != null && keb.isNotEmpty) {
        return "$keb${reb != null ? ' [$reb]' : ''}";
      }
      else if (reb != null) {
        return reb;
      }
      return "Vocab #$entSeq";
    } catch (e) {
      kLog('Error in getVocabForEntry: $e');
      return "Error: $entSeq";
    }
  }

  static Future<Map<String, dynamic>> processReview(int entSeq, bool isGood,
      {int? reviewDuration}) async {
    final db = await FSRSDatabase.getDatabase();
    // Convert to days
    final now = DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24);

    // Get current card state
    final cards =
        await db.query('cards', where: 'ent_seq = ?', whereArgs: [entSeq]);
    if (cards.isEmpty) throw Exception('Card not found');

    final card = cards.first;

    // Default values
    final stability = (card['stability'] as num?)?.toDouble() ?? 0.0;
    final difficulty = (card['difficulty'] as num?)?.toDouble() ?? 6.4133;
    final reps = (card['reps'] as num?)?.toInt() ?? 0;
    final lapses = (card['lapses'] as num?)?.toInt() ?? 0;
    final lastReview = card['last_review'] != null
        ? (card['last_review'] as num).toDouble()
        : null;
    final int currentType = (card['type'] as num?)?.toInt() ?? 0;
    final int currentQueue = (card['queue'] as num?)?.toInt() ?? currentType;
    final int currentLeft = (card['left'] as num?)?.toInt() ?? 0;
    double elapsedDays;
    if ((lastReview != null) || currentType == 2) {
      // Review
      elapsedDays = now - (lastReview ?? now).toDouble();
    }
    else {
      // Learning / Relearning
      elapsedDays = 30.0 / (60 * 24); // 30 mins
    }
    final String rating = isGood ? 'good' : 'again';

    // Initialize variables for new cards
    double newStability = stability;
    double newDifficulty = difficulty;
    double nextIntervalDays;
    double currentRetrievability = 0.95;
    int newType = currentType;
    int newQueue = currentQueue;
    int newLeft = currentLeft;
    int newLapses = lapses;
    bool usedFSRS = false;

    if (currentType == 0) {
      newStability = FSRSAlgorithm.initStability(rating);
      newDifficulty = FSRSAlgorithm.initDifficulty(rating);
      newType = 1;
      newQueue = 1;
      newLeft = 2;

      if (isGood) {
        newLeft--;
        nextIntervalDays = 30.0 / (60 * 24);
      }else {
        nextIntervalDays = 10.0 / (60 * 24);
        newLapses++;
      }
      kLog('New card: Initializing stability to ${newStability.toStringAsFixed(2)} and difficulty to ${newDifficulty.toStringAsFixed(2)}');
    }

    // Learning card (Again)
    else if ((currentType == 1 || currentType == 3) && !isGood) {
      newType = currentType;
      newQueue = currentType;
      newLeft = 2;
      nextIntervalDays = 10.0 / (60 * 24);
      newDifficulty += 0.1;
      if (newDifficulty > 10) newDifficulty = 10;
      newLapses++;
    }

    // Learning card (Good)
    else if ((currentType == 1 || currentType == 3) &&
        currentLeft > 1 &&
        isGood) {
      newType = currentType;
      newQueue = currentType;
      newLeft = currentLeft - 1;
      nextIntervalDays = 30.0 / (60 * 24); // 30 minutes
      newDifficulty -= 0.05;
      if (newDifficulty < 1) newDifficulty = 1;
    }

    // Learning -> Review
    else if ((currentType == 1 || currentType == 3) &&
        currentLeft <= 1 &&
        isGood) {
      newType = 2;
      newQueue = 2;
      newLeft = 0;

      final FSRSAlgorithm fsrs = FSRSAlgorithm();
      final result = fsrs.processReview(
        entSeq: entSeq,
        type: currentType,
        queue: currentQueue,
        left: currentLeft,
        rating: rating,
        currentStability: stability,
        currentDifficulty: difficulty,
        elapsedDays: elapsedDays,
      );

      newStability = result['stability'] as double;
      newDifficulty = result['difficulty'] as double;
      nextIntervalDays = result['interval'] as double;
      currentRetrievability = result['retrievability'] as double;
      usedFSRS = true;

      kLog('Card graduating: Using standard FSRS - stability: ${newStability.toStringAsFixed(2)}');
      kLog('Card graduating: Using FSRS interval of ${nextIntervalDays.toStringAsFixed(1)} days');
    }

    // Review card
    else if (currentType == 2 && isGood) {
      // Good
      final FSRSAlgorithm fsrs = FSRSAlgorithm();
      final result = fsrs.processReview(
        entSeq: entSeq,
        type: currentType,
        queue: currentQueue,
        left: currentLeft,
        rating: rating,
        currentStability: stability,
        currentDifficulty: difficulty,
        elapsedDays: elapsedDays,
      );
      newStability = result['stability'] as double;
      newDifficulty = result['difficulty'] as double;
      nextIntervalDays = result['interval'] as double;
      currentRetrievability = result['retrievability'] as double;
      usedFSRS = true;
    }

    // Again
    else if (currentType == 2 && !isGood) {
      // Relearn
      newType = 3;
      newQueue = 3;
      newLeft = 1;
      final FSRSAlgorithm fsrs = FSRSAlgorithm();
      final result = fsrs.processReview(
        entSeq: entSeq,
        type: currentType,
        queue: currentQueue,
        left: currentLeft,
        rating: rating,
        currentStability: stability,
        currentDifficulty: difficulty,
        elapsedDays: elapsedDays,
      );
      newStability = result['stability'] as double;
      newDifficulty = result['difficulty'] as double;
      nextIntervalDays = 10.0 / (60 * 24);
      currentRetrievability = result['retrievability'] as double;
      newLapses++;
      usedFSRS = true;
    } else {
      kLog('Something wrong in Review Service bro');
      nextIntervalDays = 1.0;
    }
    final newDue = now + nextIntervalDays;

    // Debug
    kLog('Processing review for entry $entSeq: ${await getVocabForEntry(entSeq)}');
    kLog('1. Rating: $rating');
    kLog('2. Type: ${names[currentType]} ($currentType) -> ${names[newType]} ($newType)');
    kLog('3. Queue: ${names[currentQueue]} ($currentQueue) -> ${names[newQueue]} ($newQueue)');
    kLog('4. Left: $currentLeft -> $newLeft');
    kLog('5. Stability: $stability -> $newStability');
    kLog('6. Difficulty: $difficulty -> $newDifficulty');
    kLog('7. Retrievability: $currentRetrievability');
    kLog('8. Elapsed Days: $elapsedDays');
    kLog('9. Reps: $reps -> ${reps + 1}');
    kLog('10. Lapses: $lapses -> $newLapses');
    kLog('11. Next interval: $nextIntervalDays days (${usedFSRS ? "FSRS" : "fixed schedule"})');
    kLog('12. New due time: $newDue');

    // Update card in database
    await db.update(
        'cards',
        {
          'stability': newStability,
          'difficulty': newDifficulty,
          'due': newDue,
          'last_review': now,
          'reps': reps + 1,
          'lapses': newLapses,
          'type': newType,
          'queue': newQueue,
          'left': newLeft,
        },
        where: 'ent_seq = ?',
        whereArgs: [entSeq]);
    
    try {
      await FSRSSyncService.upsertCard({
        'ent_seq': entSeq,
        'stability': newStability,
        'difficulty': newDifficulty,
        'due': newDue,
        'last_review': now,
        'reps': reps + 1,
        'lapses': newLapses,
        'type': newType,
        'queue': newQueue,
        'left': newLeft,
      });
    } catch (e) {
      kLog('❌ Auto-upload failed (card saved locally): $e');
    }
    
    return {
      'due': newDue,
      'stability': newStability,
      'difficulty': newDifficulty,
      'interval_days': nextIntervalDays,
      'formatted_interval': FSRSAlgorithm.formatInterval(nextIntervalDays),
      'type': newType,
      'type_name': names[newType],
      'queue': newQueue,
      'queue_name': names[newQueue],
      'left': newLeft
    };
  }

  static Future<Map<String, String>> getPredictedIntervals(int entSeq) async {
    final db = await FSRSDatabase.getDatabase();

    final cards =
        await db.query('cards', where: 'ent_seq = ?', whereArgs: [entSeq]);
    if (cards.isEmpty) throw Exception('Card not found');

    final card = cards.first;
    final stability = (card['stability'] as num?)?.toDouble() ?? 2.3065;
    final difficulty = (card['difficulty'] as num?)?.toDouble() ?? 6.4133;
    final lastReview = card['last_review'] != null
        ? (card['last_review'] as num).toDouble()
        : null;
    final now = DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24);
    double elapsedDays;
    if (lastReview != null) {
      elapsedDays = now - lastReview;
    }
    else {
      elapsedDays = 1.0;
    }
    final int currentType = (card['type'] as num?)?.toInt() ?? 0;
    final int currentQueue = (card['queue'] as num?)?.toInt() ?? currentType;
    final int left = (card['left'] as num?)?.toInt() ?? 0;

    kLog('Previewing intervals for ${names[currentType]} card (type=$currentType, queue=$currentQueue/${names[currentQueue]}, left=$left)');

    return FSRSAlgorithm().previewIntervals(
      entSeq: entSeq,
      type: currentType,
      queue: currentQueue,
      left: left,
      currentStability: stability,
      currentDifficulty: difficulty,
      elapsedDays: elapsedDays,
    );
  }
}
