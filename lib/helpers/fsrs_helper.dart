import 'fsrs/fsrs_database.dart';
import 'fsrs/card_fetcher.dart';
import 'fsrs/review_process.dart';
import 'dictionary_helper.dart';

class FSRSHelper {
  static final FSRSHelper _instance = FSRSHelper._internal();
  factory FSRSHelper() => _instance;
  FSRSHelper._internal();

  static Future<void> initialize() async {
    await DictionaryHelper.initialize();
    await FSRSDatabase.initialize();
  }

  // Delegate methods
  static Future<bool> addToFSRS(int entryId) => FSRSCardService.addCard(entryId);
  static Future<List<Map<String, dynamic>>> getDueCards({int limit = 20}) => 
      FSRSCardService.getDueCards(limit: limit);
  static Future<Map<String, dynamic>> processReview(int entryId, bool isGood, {int? reviewDuration}) => 
      FSRSReviewService.processReview(entryId, isGood, reviewDuration: reviewDuration);
  static Future<Map<String, dynamic>> getCardStats(int entryId) => 
      FSRSCardService.getCardStats(entryId);
  static Future<Map<String, String>> getPredictedIntervals(int entryId) => 
      FSRSReviewService.getPredictedIntervals(entryId);
}