import 'package:kian/features/fsrs/data/local/fsrs_database.dart';
import 'package:kian/features/fsrs/data/repositories/fsrs_repository.dart';
import 'package:kian/features/fsrs/application/review_service.dart';
import 'package:kian/features/dictionary/domain/dictionary_helper.dart';
import 'package:kian/services/cloud/sync_service.dart';

class FSRSHelper {
  static final FSRSHelper _instance = FSRSHelper._internal();
  factory FSRSHelper() => _instance;
  FSRSHelper._internal();

  static Future<void> initialize() async {
    await DictionaryHelper.initialize();
    await FSRSDatabase.initialize();
  }

  static Future<bool> addToFSRS(int entryId) => FSRSRepository.addCard(entryId);

  static Future<List<Map<String, dynamic>>> getDueCards({int limit = 999999}) =>
      FSRSRepository.getDueCards(limit: limit);

    static Future<Map<String, dynamic>> processReview(int entryId, bool isGood,
        {int? reviewDuration}) =>
      FSRSReviewService.processReview(entryId, isGood,
        reviewDuration: reviewDuration);

    static Future<Map<String, dynamic>> getCardStats(int entryId) =>
      FSRSRepository.getCardStats(entryId);

    static Future<Map<String, String>> getPredictedIntervals(int entryId) =>
      FSRSReviewService.getPredictedIntervals(entryId);

  // Sync methods
// Sync methods
  static Future<Map<String, dynamic>> syncToSupabase({
    Function(int current, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    try {
      final localCards = await FSRSRepository.getAllCards();

      final result = await FSRSSyncService.syncLocalToCloud(
        localCards
            .map((card) => {
                  ...card,
                  'due': (card['due'] as num).toDouble(),
                  'last_review': card['last_review'] != null
                      ? (card['last_review'] as num).toDouble()
                      : null,
                })
            .toList(),
        shouldUploadCallback: (localCard, cloudCard) async {
          bool shouldUpload = false;

          if (cloudCard == null) {
            shouldUpload = true;
          } else {
            final localLastReview = localCard['last_review'] as double?;
            final cloudLastReview = cloudCard['last_review'] as double?;

            if (localLastReview == null && cloudLastReview == null) {
              shouldUpload = false;
            } else if (localLastReview != null && cloudLastReview == null) {
              shouldUpload = true;
            } else if (localLastReview == null && cloudLastReview != null) {
              shouldUpload = false;
            } else {
              shouldUpload = localLastReview! > cloudLastReview!;
            }
          }

          return shouldUpload;
        },
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );

      return {
        'success': result['success'],
        'synced': result['uploaded'],
        'errors': result['errors'],
        'error': result['success'] ? null : 'Upload failed',
      };
    } catch (e) {
      return {
        'success': false,
        'synced': 0,
        'error': e.toString(),
      };
    }
  }



  static Future<Map<String, dynamic>> syncFromSupabase({
    Function(int current, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    try {
      final localCards = await FSRSRepository.getAllCards();

      final Map<int, Map<String, dynamic>> localCardMap = {
        for (var card in localCards) card['entry_id'] as int: card
      };

      final result = await FSRSSyncService.syncCloudToLocal(
        (cloudCard) async {
          final localCard = localCardMap[cloudCard['entry_id']];

          bool shouldDownload = false;

          if (localCard == null) {
            shouldDownload = true;
          } else {
            final localLastReview = localCard['last_review'] != null
                ? (localCard['last_review'] as num).toDouble()
                : null;
            final cloudLastReview = cloudCard['last_review'] != null
                ? (cloudCard['last_review'] as num).toDouble()
                : null;

            if (localLastReview == null && cloudLastReview == null) {
              shouldDownload = false;
            } else if (localLastReview != null && cloudLastReview == null) {
              shouldDownload = false;
            } else if (localLastReview == null && cloudLastReview != null) {
              shouldDownload = true;
            } else {
              shouldDownload = cloudLastReview! > localLastReview!;
            }
          }

          if (shouldDownload) {
            final localFormatCard = {
              'entry_id': cloudCard['entry_id'],
              'type': cloudCard['type'],
              'queue': cloudCard['queue'],
              'due': (cloudCard['due'] as num).toDouble(),
              'last_review': cloudCard['last_review'] != null
                  ? (cloudCard['last_review'] as num).toDouble()
                  : null,
              'reps': cloudCard['reps'],
              'lapses': cloudCard['lapses'],
              'left': cloudCard['left_steps'],
              'stability': cloudCard['stability'],
              'difficulty': cloudCard['difficulty'],
            };
            await FSRSRepository.upsertCard(localFormatCard);
          }

          return shouldDownload;
        },
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );

      return {
        'success': result['success'],
        'synced': result['downloaded'],
        'errors': result['errors'],
        'error': result['success'] ? null : 'Download failed',
      };
    } catch (e) {
      return {
        'success': false,
        'synced': 0,
        'error': e.toString(),
      };
    }
  }

  // Get sync status
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final localCount = await FSRSRepository.getCardCount();
      final supabaseCount = await FSRSSyncService.getCardCount();

      return {
        'local': localCount,
        'supabase': supabaseCount,
        'needsSync': localCount != supabaseCount,
      };
    } catch (e) {
      return {
        'local': 0,
        'supabase': 0,
        'needsSync': false,
        'error': e.toString(),
      };
    }
  }
}
