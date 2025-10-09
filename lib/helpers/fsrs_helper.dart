import 'fsrs/fsrs_database.dart';
import 'fsrs/card_fetcher.dart';
import 'fsrs/review_service.dart';
import 'dictionary_helper.dart';
import '../services/progress_service.dart';
import 'package:flutter/foundation.dart';

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
  static Future<Map<String, dynamic>> syncToSupabase() async {
    try {
      final localCards = await FSRSCardService.getAllCards();
      final result = await FSRSBackendService.syncLocalToCloud(localCards);

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

  static Future<Map<String, dynamic>> syncFromSupabase() async {
    try {
      final cloudCards = await FSRSBackendService.getAllCards();

      // Handle empty cloud database
      if (cloudCards.isEmpty) {
        debugPrint('☁️ No cloud cards to download');
        return {
          'success': true,
          'synced': 0,
          'errors': 0,
          'error': null,
        };
      }

      // Get all local cards once (efficient!)
      final localCards = await FSRSCardService.getAllCards();

      // Create lookup map for O(1) access
      final Map<int, Map<String, dynamic>> localCardMap = {
        for (var card in localCards) card['ent_seq'] as int: card
      };

      final result = await FSRSBackendService.syncCloudToLocal(
        cloudCards,
        (cloudCard) async {
          // Use map lookup instead of database query
          final localCard = localCardMap[cloudCard['ent_seq']];

          bool shouldDownload = false;

          if (localCard == null) {
            // Card doesn't exist locally - download it
            shouldDownload = true;
          } else {
            // Compare timestamps (same logic as upload sync)
            final localLastReview = localCard['last_review'] as int?;
            final cloudLastReview = cloudCard['last_review'] as int?;

            if (localLastReview == null && cloudLastReview == null) {
              shouldDownload = false;
            } else if (localLastReview != null && cloudLastReview == null) {
              shouldDownload = false; // Local is newer
            } else if (localLastReview == null && cloudLastReview != null) {
              shouldDownload = true; // Cloud is newer
            } else {
              // Both have timestamps - download if cloud is newer
              shouldDownload = cloudLastReview! > localLastReview!;
            }
          }

          if (shouldDownload) {
            // FILTER OUT CLOUD-ONLY FIELDS before local insert
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
              // NOTE: Deliberately exclude 'id' field - it doesn't exist in local table
            };
            await FSRSCardService.upsertCard(localFormatCard);
          }

          return shouldDownload;
        },
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
      final supabaseCount = await FSRSBackendService.getCardCount();

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
