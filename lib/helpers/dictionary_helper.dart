import 'package:sqflite/sqflite.dart';
import 'dictionary/dict_database.dart';
import 'dictionary/dict_entry.dart';
import 'dictionary/dict_search.dart';

class DictionaryHelper {
  static final DictionaryHelper _instance = DictionaryHelper._internal();
  factory DictionaryHelper() => _instance;
  DictionaryHelper._internal();

  // Initialization
  static Future<void> initialize() => DictionaryDatabase.initialize();
  static Future<Database> getDatabase() => DictionaryDatabase.getDatabase();

  // Entry lookup
  static Future<Map<String, dynamic>?> getEntryById(int entryId) => 
      DictionaryEntryService.getEntryById(entryId);

  // Search functions
  static Future<List<Map<String, dynamic>>> searchByKanji(String query, {int limit = 20}) =>
      DictionarySearchService.searchByKanji(query, limit: limit);
  
  static Future<List<Map<String, dynamic>>> searchByReading(String query, {int limit = 20}) =>
      DictionarySearchService.searchByReading(query, limit: limit);
  
  static Future<List<Map<String, dynamic>>> searchByMeaning(String query, {int limit = 20}) =>
      DictionarySearchService.searchByMeaning(query, limit: limit);
  
  static Future<List<Map<String, dynamic>>> searchAll(String query, {int limit = 20}) =>
      DictionarySearchService.searchAll(query, limit: limit);

  // Debug functions
  static Future<void> debugTableStructure() => DictionaryDatabase.debugTableStructure();
  static Future<bool> testFTS5Functionality() => DictionaryDatabase.testFTS5Functionality();
}