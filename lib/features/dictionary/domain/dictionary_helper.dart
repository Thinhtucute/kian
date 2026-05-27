import 'package:sqflite/sqflite.dart';
import 'package:kian/features/dictionary/data/local/dictionary_database.dart';
import 'package:kian/features/dictionary/data/repositories/dictionary_repository.dart';

class DictionaryHelper {
    static final DictionaryHelper _instance = DictionaryHelper._internal();
    factory DictionaryHelper() => _instance;
    DictionaryHelper._internal();

    static Future<void> initialize() => DictionaryDatabase.initialize();
    static Future<Database> getDatabase() => DictionaryDatabase.getDatabase();

    static Future<Map<String, dynamic>?> getEntryById(
        int entryId, {
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.getEntryById(
                entryId,
                languageTag: languageTag,
            );

    static Future<List<Map<String, dynamic>>> searchByKanji(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchByKanji(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<List<Map<String, dynamic>>> searchByReading(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchByReading(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<List<Map<String, dynamic>>> searchByMeaning(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchByMeaning(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<List<Map<String, dynamic>>> searchAll(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchAll(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<void> debugTableStructure() =>
            DictionaryDatabase.debugTableStructure();
    static Future<bool> testFTS5Functionality() =>
            DictionaryDatabase.testFTS5Functionality();
}
