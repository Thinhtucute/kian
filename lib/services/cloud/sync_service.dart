import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'auth_service.dart';
import 'package:kian/features/fsrs/domain/fsrs_algorithm.dart';
import 'package:kian/features/fsrs/data/repositories/fsrs_repository.dart';
import 'package:kian/core/logger.dart';

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

  static Future<Map<String, dynamic>?> getCard(int entryId) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final response = await _client
          .from('cards')
          .select()
          .eq('user_id', userId)
          .eq('entry_id', entryId)
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
      'entry_id': card['entry_id'],
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
    bool Function()? shouldCancel,
  }) async {
    int uploaded = 0;
    int skipped = 0;
    int errors = 0;
    List<String> errorDetails = [];
    final total = localCards.length;

    const int batchSize = 100;
    for (int i = 0; i < localCards.length; i += batchSize) {
      if (shouldCancel != null && shouldCancel()) {
        throw Exception('Sync cancelled');
      }
      final batch = localCards.skip(i).take(batchSize).toList();

      try {
        final userId = AuthService.currentUserId;
        if (userId == null) {
          throw Exception('User not authenticated');
        }

        final entryIds = batch.map((card) => card['entry_id'] as int).toList();
        final response = await _client
            .from('cards')
            .select()
            .eq('user_id', userId)
            .inFilter('entry_id', entryIds);

        final cloudCards = List<Map<String, dynamic>>.from(response);
        final cloudCardsMap = {
          for (var card in cloudCards) card['entry_id'] as int: card
        };

        List<Map<String, dynamic>> cardsToUpload = [];

        for (final localCard in batch) {
          final entryId = localCard['entry_id'] as int;
          final cloudCard = cloudCardsMap[entryId];

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
                    'entry_id': card['entry_id'],
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

          await _client.from('cards').upsert(supabaseCards);
          uploaded += cardsToUpload.length;
          kLog('↑ Batch uploaded ${cardsToUpload.length} cards');
        }

        onProgress?.call(i + batch.length, total);
      } catch (e) {
        errors += batch.length;
        errorDetails.add('Batch ${i ~/ batchSize}: $e');
        kLog('❌ Error uploading batch: $e');
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
    bool Function()? shouldCancel,
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
        if (shouldCancel != null && shouldCancel()) {
          throw Exception('Sync cancelled');
        }
        final userId = AuthService.currentUserId;
        if (userId == null) {
          throw Exception('User not authenticated');
        }

        final response = await _client
            .from('cards')
            .select()
            .eq('user_id', userId)
            .order('entry_id', ascending: true)
            .range(offset, offset + batchSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);

        if (batch.isEmpty) break;

        for (final cloudCard in batch) {
          if (shouldCancel != null && shouldCancel()) {
            throw Exception('Sync cancelled');
          }
          try {
            final entryId = cloudCard['entry_id'] as int;

            final shouldDownload = await shouldDownloadCallback(cloudCard);

            if (shouldDownload) {
              await _saveCloudCardToLocal(cloudCard);
              downloaded++;
              kLog('⬇ Downloaded card $entryId (newer cloud version)');
            } else {
              skipped++;
              kLog('→ Skipped card $entryId (local same/newer)');
            }
          } catch (e) {
            errors++;
            errorDetails.add('Card ${cloudCard['entry_id']}: $e');
            kLog('❌ Error downloading card ${cloudCard['entry_id']}: $e');
          }

          processedCount++;
          onProgress?.call(processedCount, totalCount);
        }

        if (batch.length < batchSize) break;
        offset += batchSize;
      }

      kLog('✅ Sync complete: $processedCount cards processed.');
    } catch (e) {
      errors++;
      errorDetails.add('Failed to fetch cloud cards: $e');
      kLog('❌ Error fetching cloud cards: $e');
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
      'entry_id': cloudCard['entry_id'],
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
    await FSRSRepository.upsertCard(localFormatCard);
  }

  static Future<bool> isCloudNewer(int entryId, double? localLastReview) async {
    final cloudCard = await getCard(entryId);

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
      kLog('Error getting due cards from Supabase: $e');
      return [];
    }
  }

  static Future<void> addCard(int entryId) async {
    // Convert to days
    final now = (DateTime.now().millisecondsSinceEpoch / (1000 * 60 * 60 * 24));

    try {
      await _client.from('cards').insert({
        'entry_id': entryId,
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
      kLog('Card $entryId added to Supabase');
    } catch (e) {
      kLog('Error adding card to Supabase: $e');
      rethrow;
    }
  }

  static Future<void> processReview(
    int entryId,
    bool isGood, {
    int? reviewDuration,
  }) async {
    try {
      final cardResponse =
          await _client.from('cards').select().eq('entry_id', entryId).single();

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
        entryId: entryId,
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
      }).eq('entry_id', entryId);

      kLog('Card $entryId review processed in Supabase');
    } catch (e) {
      kLog('Error processing review in Supabase: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getPredictedIntervals(int entryId) async {
    try {
      final cardResponse =
          await _client.from('cards').select().eq('entry_id', entryId).single();

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
        entryId: entryId,
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
      kLog('Error getting predicted intervals from Supabase: $e');
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
