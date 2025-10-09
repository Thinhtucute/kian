import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../helpers/fsrs/fsrs_algorithm.dart';
import '../helpers/dictionary_helper.dart';

class FSRSBackendService {
  static SupabaseClient get _client => SupabaseService.client;

  static Future<List<Map<String, dynamic>>> getAllCards() async {
    final response = await _client.from('cards').select();
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<int> getCardCount() async {
    final response = await _client.from('cards').select('ent_seq');
    return (response as List).length;
  }

  // Get single card by ent_seq
  static Future<Map<String, dynamic>?> getCard(int entSeq) async {
    try {
      final response =
          await _client.from('cards').select().eq('ent_seq', entSeq).single();
      return response;
    } catch (e) {
      return null;
    }
  }

  // Update existing card in Supabase
  static Future<void> updateCard(Map<String, dynamic> card) async {
    await _client.from('cards').update({
      'type': card['type'],
      'queue': card['queue'],
      'due': card['due'],
      'last_review': card['last_review'],
      'reps': card['reps'],
      'lapses': card['lapses'],
      'left_steps': card['left_steps'] ?? card['left'],
      'stability': card['stability'],
      'difficulty': card['difficulty'],
    }).eq('ent_seq', card['ent_seq']);
  }

  // Upsert card
  static Future<void> upsertCard(Map<String, dynamic> card) async {
    await _client.from('cards').upsert({
      'ent_seq': card['ent_seq'],
      'type': card['type'],
      'queue': card['queue'],
      'due': card['due'],
      'last_review': card['last_review'],
      'reps': card['reps'],
      'lapses': card['lapses'],
      'left_steps': card['left_steps'] ?? card['left'],
      'stability': card['stability'],
      'difficulty': card['difficulty'],
    });
  }

  static Future<Map<String, dynamic>> syncLocalToCloud(
      List<Map<String, dynamic>> localCards) async {
    int uploaded = 0;
    int skipped = 0;
    int errors = 0;
    List<String> errorDetails = [];

    for (var localCard in localCards) {
      try {
        final entSeq = localCard['ent_seq'] as int;

        final cloudCard = await getCard(entSeq);

        bool shouldUpload = false;

        if (cloudCard == null) {
          shouldUpload = true;
        } else {
          // Both are int days - direct comparison
          final localLastReview = localCard['last_review'] as int?;
          final cloudLastReview = cloudCard['last_review'] as int?;

          if (localLastReview == null && cloudLastReview == null) {
            shouldUpload = false;
          } else if (localLastReview != null && cloudLastReview == null) {
            shouldUpload = true;
          } else if (localLastReview == null && cloudLastReview != null) {
            shouldUpload = false;
          } else {
            // Simple int comparison - both are days since epoch
            shouldUpload = localLastReview! > cloudLastReview!;
          }
        }

        if (shouldUpload) {
          await upsertCard(localCard);
          uploaded++;
          debugPrint('↑ Uploaded card $entSeq (newer local version)');
        } else {
          skipped++;
          debugPrint('→ Skipped card $entSeq (cloud same/newer)');
        }
      } catch (e) {
        errors++;
        errorDetails.add('Card ${localCard['ent_seq']}: $e');
        debugPrint('❌ Error uploading card ${localCard['ent_seq']}: $e');
      }
    }

    return {
      'success': errors < localCards.length,
      'uploaded': uploaded,
      'skipped': skipped,
      'errors': errors,
      'errorDetails': errorDetails,
    };
  }

  // Download only newer cloud cards to local
  static Future<Map<String, dynamic>> syncCloudToLocal(
      List<Map<String, dynamic>> cloudCards,
      Future<bool> Function(Map<String, dynamic>)
          shouldDownloadCallback) async {
    int downloaded = 0;
    int skipped = 0;
    int errors = 0;
    List<String> errorDetails = [];

    for (var cloudCard in cloudCards) {
      try {
        final entSeq = cloudCard['ent_seq'] as int;
        final shouldDownload = await shouldDownloadCallback(cloudCard);

        if (shouldDownload) {
          downloaded++;
          debugPrint('Downloaded card $entSeq (newer cloud version)');
        } else {
          skipped++;
          debugPrint('Skipped card $entSeq (local same/newer)');
        }
      } catch (e) {
        errors++;
        errorDetails.add('Card ${cloudCard['ent_seq']}: $e');
        debugPrint('❌ Error downloading card ${cloudCard['ent_seq']}: $e');
      }
    }

    return {
      'success': errors < cloudCards.length,
      'downloaded': downloaded,
      'skipped': skipped,
      'errors': errors,
      'errorDetails': errorDetails,
    };
  }

  // Get cards modified after a specific timestamp (int days)
  static Future<List<Map<String, dynamic>>> getCardsModifiedAfter(
      int timestamp) async {
    final response = await _client
        .from('cards')
        .select()
        .gt('last_review', timestamp)
        .order('last_review', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Check if cloud has newer version
  static Future<bool> isCloudNewer(int entSeq, int? localLastReview) async {
    final cloudCard = await getCard(entSeq);

    if (cloudCard == null) return false; // Cloud doesn't have card

    final cloudLastReview = cloudCard['last_review'] as int?;

    if (localLastReview == null && cloudLastReview == null) return false;
    if (localLastReview == null && cloudLastReview != null) return true;
    if (localLastReview != null && cloudLastReview == null) return false;

    return cloudLastReview! > localLastReview!;
  }

  static Future<List<Map<String, dynamic>>> getDueCards(
      {int limit = 999999}) async {
    // Convert to int days
    final now =
        (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24)).round();

    try {
      List<Map<String, dynamic>> reviews = [];

      var response = await _client
          .from('cards')
          .select()
          .lt('due', now)
          .eq('type', 2)
          .order('due', ascending: true)
          .limit(limit);

      reviews = List<Map<String, dynamic>>.from(response);

      if (reviews.isEmpty) {
        response = await _client
            .from('cards')
            .select()
            .lt('due', now)
            .eq('left_steps', 1)
            .order('due', ascending: true)
            .limit(limit);

        reviews = List<Map<String, dynamic>>.from(response);
      }

      if (reviews.isEmpty) {
        response = await _client
            .from('cards')
            .select()
            .lt('due', now)
            .order('due', ascending: true)
            .limit(limit);

        reviews = List<Map<String, dynamic>>.from(response);
      }

      if (reviews.isEmpty) return [];

      return await _enrichCards(reviews);
    } catch (e) {
      debugPrint('Error getting due cards from Supabase: $e');
      return [];
    }
  }

  static Future<void> addCard(int entSeq) async {
    // Convert to int days
    final now =
        (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24)).round();

    try {
      await _client.from('cards').insert({
        'ent_seq': entSeq,
        'type': 0,
        'queue': 0,
        'due': now,
        'last_review': null,
        'reps': 0,
        'lapses': 0,
        'left_steps': 2,
        'stability': 2.3065,
        'difficulty': 6.4133,
      });
      debugPrint('Card $entSeq added to Supabase');
    } catch (e) {
      debugPrint('Error adding card to Supabase: $e');
      rethrow;
    }
  }

  static Future<void> processReview(
    int entSeq,
    bool isGood, {
    int? reviewDuration,
  }) async {
    try {
      final cardResponse =
          await _client.from('cards').select().eq('ent_seq', entSeq).single();

      final card = cardResponse;
      // Convert to int days
      final now =
          (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24))
              .round();
      final elapsedDays = card['last_review'] != null
          ? (now - (card['last_review'] as int)).toDouble()
          : 1.0;

      final result = FSRSAlgorithm().processReview(
        entSeq: entSeq,
        type: card['type'],
        queue: card['queue'],
        left: card['left_steps'],
        rating: isGood ? 'good' : 'again',
        currentStability: (card['stability'] as num).toDouble(),
        currentDifficulty: (card['difficulty'] as num).toDouble(),
        elapsedDays: elapsedDays,
      );

      final newType = _calculateNewType(card, isGood);
      final newQueue = newType;
      final newLeft = _calculateNewLeft(card, isGood);
      // Convert interval to int days
      final newDue = now + (result['interval'] as double).round();

      await _client.from('cards').update({
        'type': newType,
        'queue': newQueue,
        'due': newDue,
        'last_review': now,
        'reps': (card['reps'] ?? 0) + 1,
        'lapses': isGood ? card['lapses'] : (card['lapses'] ?? 0) + 1,
        'left_steps': newLeft,
        'stability': result['stability'],
        'difficulty': result['difficulty'],
      }).eq('ent_seq', entSeq);

      debugPrint('Card $entSeq review processed in Supabase');
    } catch (e) {
      debugPrint('Error processing review in Supabase: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getPredictedIntervals(int entSeq) async {
    try {
      final cardResponse =
          await _client.from('cards').select().eq('ent_seq', entSeq).single();

      final card = cardResponse;
      // Convert to int days
      final now =
          (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24))
              .round();
      final elapsedDays = card['last_review'] != null
          ? (now - (card['last_review'] as int)).toDouble()
          : 1.0;

      final intervals = FSRSAlgorithm().previewIntervals(
        entSeq: entSeq,
        type: card['type'],
        queue: card['queue'],
        left: card['left_steps'],
        currentStability: (card['stability'] as num).toDouble(),
        currentDifficulty: (card['difficulty'] as num).toDouble(),
        elapsedDays: elapsedDays,
      );

      return {
        'interval': intervals['good'] ?? 'unknown',
        'type': card['type'],
        'stability': card['stability'],
        'difficulty': card['difficulty'],
        'last_review': card['last_review'],
      };
    } catch (e) {
      debugPrint('Error getting predicted intervals from Supabase: $e');
      return {
        'interval': 'unknown',
        'type': 0,
        'stability': 2.3065,
        'difficulty': 6.4133,
        'last_review': null,
      };
    }
  }

  static int _calculateNewType(Map<String, dynamic> card, bool isGood) {
    if (card['type'] == 0) return isGood ? 1 : 0;
    if (card['type'] == 1 || card['type'] == 3) {
      if (isGood && card['left_steps'] <= 1) return 2;
      if (!isGood) return 3;
      return card['type'];
    }
    if (card['type'] == 2) return isGood ? 2 : 3;
    return card['type'];
  }

  static int _calculateNewLeft(Map<String, dynamic> card, bool isGood) {
    if (card['type'] == 0) return isGood ? 1 : 2;
    if (card['type'] == 1 || card['type'] == 3) {
      if (isGood) return (card['left_steps'] - 1).clamp(0, 2);
      return 2;
    }
    return 0;
  }

  static Future<List<Map<String, dynamic>>> _enrichCards(
      List<Map<String, dynamic>> allCards) async {
    List<Map<String, dynamic>> enrichedCards = [];

    for (var card in allCards) {
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
        debugPrint('Error enriching card $entSeq: $e');
      }
    }

    return enrichedCards;
  }
}
