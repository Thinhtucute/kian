import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import 'auth_service.dart';
import '../../helpers/fsrs/fsrs_algorithm.dart';
import '../fsrs/card_fetcher.dart';

class FSRSSyncService {
  static SupabaseClient get _client => SupabaseService.client;

  static Future<int> getCardCount() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    
    final response = await _client
        .from('cards')
        .select()
        .eq('user_id', userId)
        .count(CountOption.exact);
    return response.count;
  }

  static Future<Map<String, dynamic>?> getCard(int entSeq) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    
    try {
      final response = await _client
          .from('cards')
          .select()
          .eq('user_id', userId)
          .eq('ent_seq', entSeq)
          .single();
      return response;
    } catch (e) {
      return null;
    }
  }

  static Future<void> upsertCard(Map<String, dynamic> card) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await _client.from('cards').upsert({
      'user_id': userId,
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
    List<Map<String, dynamic>> localCards, {
    Future<bool> Function(
            Map<String, dynamic> localCard, Map<String, dynamic>? cloudCard)?
        shouldUploadCallback,
    Function(int current, int total)? onProgress,
  }) async {
    int uploaded = 0;
    int skipped = 0;
    int errors = 0;
    List<String> errorDetails = [];
    final total = localCards.length;

    const int batchSize = 100;
    for (int i = 0; i < localCards.length; i += batchSize) {
      final batch = localCards.skip(i).take(batchSize).toList();

      try {
        final userId = AuthService.currentUserId;
        if (userId == null) {
          throw Exception('User not authenticated');
        }
        
        final entSeqs = batch.map((card) => card['ent_seq'] as int).toList();
        final response = await _client
            .from('cards')
            .select()
            .eq('user_id', userId)
            .inFilter('ent_seq', entSeqs);

        final cloudCards = List<Map<String, dynamic>>.from(response);
        final cloudCardsMap = {
          for (var card in cloudCards) card['ent_seq'] as int: card
        };

        List<Map<String, dynamic>> cardsToUpload = [];

        for (final localCard in batch) {
          final entSeq = localCard['ent_seq'] as int;
          final cloudCard = cloudCardsMap[entSeq];

          bool shouldUpload = false;

          if (shouldUploadCallback != null) {
            shouldUpload = await shouldUploadCallback(localCard, cloudCard);
          }

          if (shouldUpload) {
            cardsToUpload.add(localCard);
          } else {
            skipped++;
          }
        }

        if (cardsToUpload.isNotEmpty) {
          final userId = AuthService.currentUserId;
          if (userId == null) {
            throw Exception('User not authenticated');
          }

          final supabaseCards = cardsToUpload
              .map((card) => {
                    'user_id': userId,
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
                  })
              .toList();

          await _client
              .from('cards')
              .upsert(supabaseCards);
          uploaded += cardsToUpload.length;
          debugPrint('↑ Batch uploaded ${cardsToUpload.length} cards');
        }

        onProgress?.call(i + batch.length, total);
      } catch (e) {
        errors += batch.length;
        errorDetails.add('Batch ${i ~/ batchSize}: $e');
        debugPrint('❌ Error uploading batch: $e');
      }

      // Small delay between batches
      if (i + batchSize < localCards.length) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }

    return {
      'success': errors == 0,
      'uploaded': uploaded,
      'skipped': skipped,
      'errors': errors,
      'errorDetails': errorDetails,
    };
  }

  static Future<Map<String, dynamic>> syncCloudToLocal(
    Future<bool> Function(Map<String, dynamic>) shouldDownloadCallback, {
    Function(int current, int total)? onProgress,
  }) async {
    int downloaded = 0;
    int skipped = 0;
    int errors = 0;
    int processedCount = 0;
    List<String> errorDetails = [];

    final totalCount = await getCardCount();
    const int batchSize = 1000;
    int offset = 0;

    try {
      while (true) {
        final userId = AuthService.currentUserId;
        if (userId == null) {
          throw Exception('User not authenticated');
        }
        
        final response = await _client
            .from('cards')
            .select()
            .eq('user_id', userId)
            .order('ent_seq', ascending: true)
            .range(offset, offset + batchSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);

        if (batch.isEmpty) break;

        for (final cloudCard in batch) {
          try {
            final entSeq = cloudCard['ent_seq'] as int;

            final shouldDownload = await shouldDownloadCallback(cloudCard);

            if (shouldDownload) {
              await _saveCloudCardToLocal(cloudCard);
              downloaded++;
              debugPrint('⬇ Downloaded card $entSeq (newer cloud version)');
            } else {
              skipped++;
              debugPrint('→ Skipped card $entSeq (local same/newer)');
            }
          } catch (e) {
            errors++;
            errorDetails.add('Card ${cloudCard['ent_seq']}: $e');
            debugPrint('❌ Error downloading card ${cloudCard['ent_seq']}: $e');
          }

          processedCount++;
          onProgress?.call(processedCount, totalCount);
        }

        if (batch.length < batchSize) break;
        offset += batchSize;
      }

      debugPrint('✅ Sync complete: $processedCount cards processed.');
    } catch (e) {
      errors++;
      errorDetails.add('Failed to fetch cloud cards: $e');
      debugPrint('❌ Error fetching cloud cards: $e');
    }

    return {
      'success': errors == 0,
      'downloaded': downloaded,
      'skipped': skipped,
      'errors': errors,
      'errorDetails': errorDetails,
    };
  }

  static Future<void> _saveCloudCardToLocal(
      Map<String, dynamic> cloudCard) async {
    final localFormatCard = {
      'ent_seq': cloudCard['ent_seq'],
      'type': cloudCard['type'],
      'queue': cloudCard['queue'],
      'due': cloudCard['due'],
      'last_review': cloudCard['last_review'],
      'reps': cloudCard['reps'],
      'lapses': cloudCard['lapses'],
      'left': cloudCard['left_steps'], // Convert left_steps -> left
      'stability': cloudCard['stability'],
      'difficulty': cloudCard['difficulty'],
    };
    // Save to local DB
    await FSRSCardService.upsertCard(localFormatCard);
  }

  // Check if cloud has newer version
  static Future<bool> isCloudNewer(int entSeq, double? localLastReview) async {
    final cloudCard = await getCard(entSeq);

    if (cloudCard == null) return false;

    final cloudLastReview = cloudCard['last_review'] as double?;

    if (localLastReview == null && cloudLastReview == null) return false;
    if (localLastReview == null && cloudLastReview != null) return true;
    if (localLastReview != null && cloudLastReview == null) return false;

    return cloudLastReview! > localLastReview!;
  }

  static Future<List<Map<String, dynamic>>> getDueCards(
      {int limit = 999999}) async {
    // Convert to days
    final now = (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24));

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
      return reviews;
    } catch (e) {
      debugPrint('Error getting due cards from Supabase: $e');
      return [];
    }
  }

  static Future<void> addCard(int entSeq) async {
    // Convert to days
    final now = (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24));

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
      final now =
          (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24));

      final double elapsedDays;
      if (card['last_review'] == null) {
        // Use default elapsed time for first review
        elapsedDays = 2;
      } else {
        elapsedDays = (now - (card['last_review'] as double));
      }

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
      final newDue = now + (result['interval'] as double);

      await _client.from('cards').update({
        'type': newType,
        'queue': newQueue,
        'due': newDue,
        'last_review': now,
        'reps': (card['reps'] ?? 0) + 1,
        'lapses': ((card['lapses'] as int?) ?? 0) + (isGood ? 0 : 1),
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
      final now =
          (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24));

      // Handle first review case
      final double elapsedDays;
      if (card['last_review'] == null) {
        elapsedDays = 2;
      } else {
        elapsedDays = (now - (card['last_review'] as double));
      }

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
}
