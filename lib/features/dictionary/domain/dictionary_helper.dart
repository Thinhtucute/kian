import 'package:sqflite/sqflite.dart';
import 'package:kian/features/dictionary/data/local/dictionary_database.dart';
import 'package:kian/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:kian/features/dictionary/domain/example_model.dart';
import 'package:kian/features/dictionary/domain/headword_model.dart';
import 'package:kian/features/dictionary/domain/entry_model.dart';
import 'package:kian/features/dictionary/domain/sense_model.dart';

class DictionaryHelper {
    static final DictionaryHelper _instance = DictionaryHelper._internal();
    factory DictionaryHelper() => _instance;
    DictionaryHelper._internal();

    static Future<void> initialize() => DictionaryDatabase.initialize();
    static Future<Database> getDatabase() => DictionaryDatabase.getDatabase();

    static Future<Entry?> getEntryById(
        int entryId, {
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.getEntryModelById(
                entryId,
                languageTag: languageTag,
            );

    static Future<List<Headword>> getHeadwordsByEntryId(
        int entryId,
    ) => DictionaryRepository.getHeadwordsModels(entryId);

    static Future<List<Sense>> getMeaningsByEntryId(
        int entryId, {
        String languageTag = 'jp',
    }) => DictionaryRepository.getMeaningsModels(
        entryId,
        languageTag: languageTag,
    );

    static Future<List<Example>> getExamplesByEntryId(
        int entryId, {
        String languageTag = 'jp',
    }) => DictionaryRepository.getExamplesModels(
        entryId,
        languageTag: languageTag,
    );

    static Future<List<Entry>> searchByKanji(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchByKanjiModels(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<List<Entry>> searchByReading(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchByReadingModels(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<List<Entry>> searchByMeaning(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchByMeaningModels(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<List<Entry>> searchAll(
        String query, {
        int limit = 20,
        String languageTag = 'jp',
    }) =>
            DictionaryRepository.searchAllModels(
                query,
                limit: limit,
                languageTag: languageTag,
            );

    static Future<void> debugTableStructure() =>
            DictionaryDatabase.debugTableStructure();
    static Future<bool> testFTS5Functionality() =>
            DictionaryDatabase.testFTS5Functionality();
}
