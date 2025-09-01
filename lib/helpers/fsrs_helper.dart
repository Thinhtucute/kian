import 'fsrs/fsrs_database.dart';
import 'fsrs/card_fetcher.dart';
import 'fsrs/review_service.dart';
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
  static Future<bool> addToFSRS(int entSeq) => FSRSCardService.addCard(entSeq);
  static Future<List<Map<String, dynamic>>> getDueCards({int limit = 999999}) => 
      FSRSCardService.getDueCards(limit: limit);
  static Future<Map<String, dynamic>> processReview(int entSeq, bool isGood, {int? reviewDuration}) => 
      FSRSReviewService.processReview(entSeq, isGood, reviewDuration: reviewDuration);
  static Future<Map<String, dynamic>> getCardStats(int entSeq) => 
      FSRSCardService.getCardStats(entSeq);
  static Future<Map<String, String>> getPredictedIntervals(int entSeq) => 
      FSRSReviewService.getPredictedIntervals(entSeq);
}