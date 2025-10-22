import 'fsrs/fsrs_database.dart';
import '../services/fsrs/card_fetcher.dart';
import '../services/fsrs/review_service.dart';
import 'dictionary_helper.dart';
import '../services/cloud/sync_service.dart';

class FSRSHelper {
  static final FSRSHelper _instance = FSRSHelper._internal();
  factory FSRSHelper() => _instance;
  FSRSHelper._internal();

  static Future<void> initialize() async {
    await DictionaryHelper.initialize();
    await FSRSDatabase.initialize();
  }

  static Future<bool> addToFSRS(int entSeq) => FSRSCardService.addCard(entSeq);

  static Future<List<Map<String, dynamic>>> getDueCards({int limit = 999999}) =>
      FSRSCardService.getDueCards(limit: limit);

  static Future<Map<String, dynamic>> processReview(int entSeq, bool isGood,
          {int? reviewDuration}) =>
      FSRSReviewService.processReview(entSeq, isGood,
          reviewDuration: reviewDuration);

  static Future<Map<String, dynamic>> getCardStats(int entSeq) =>
      FSRSCardService.getCardStats(entSeq);

  static Future<Map<String, String>> getPredictedIntervals(int entSeq) =>
      FSRSReviewService.getPredictedIntervals(entSeq);

  // Sync methods
// Sync methods
  static Future<Map<String, dynamic>> syncToSupabase({
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final localCards = await FSRSCardService.getAllCards();

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
  }) async {
    try {
      final localCards = await FSRSCardService.getAllCards();

      final Map<int, Map<String, dynamic>> localCardMap = {
        for (var card in localCards) card['ent_seq'] as int: card
      };

      final result = await FSRSSyncService.syncCloudToLocal(
        (cloudCard) async {
          final localCard = localCardMap[cloudCard['ent_seq']];

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
              'ent_seq': cloudCard['ent_seq'],
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
            await FSRSCardService.upsertCard(localFormatCard);
          }

          return shouldDownload;
        },
        onProgress: onProgress,
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
      final localCount = await FSRSCardService.getCardCount();
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
