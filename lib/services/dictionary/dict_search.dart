import 'package:flutter/foundation.dart';
import '../../helpers/dictionary/dict_database.dart';

class DictionarySearchService {
  static Future<List<Map<String, dynamic>>> searchByKanji(String query, {int limit = 20}) async {
    final db = await DictionaryDatabase.getDatabase();
    
    try {
      final results = await db.rawQuery('''
        SELECT kf.ent_seq, kf.keb
        FROM kanji_fts kf
        WHERE kf.keb MATCH ?
        LIMIT ?
      ''', ['$query*', limit]);
      
      return results;
    } catch (e) {
      debugPrint('Error searching kanji: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchByReading(String query, {int limit = 20}) async {
    final db = await DictionaryDatabase.getDatabase();
    
    try {
      final results = await db.rawQuery('''
        SELECT rf.ent_seq, rf.reb
        FROM reading_fts rf
        WHERE rf.reb MATCH ?
        LIMIT ?
      ''', ['$query*', limit]);
      
      return results;
    } catch (e) {
      debugPrint('Error searching reading: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchByMeaning(String query, {int limit = 20}) async {
    final db = await DictionaryDatabase.getDatabase();
    
    try {
      final results = await db.rawQuery('''
        SELECT DISTINCT gf.ent_seq, gf.gloss
        FROM gloss_fts gf
        WHERE gf.gloss MATCH ?
        LIMIT ?
      ''', ['$query*', limit]);
      
      return results;
    } catch (e) {
      debugPrint('Error searching meaning: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchAll(String query, {int limit = 20}) async {
    // Search across all types and combine results
    final kanjiResults = await searchByKanji(query, limit: limit ~/ 3);
    final readingResults = await searchByReading(query, limit: limit ~/ 3);
    final meaningResults = await searchByMeaning(query, limit: limit ~/ 3);

    // Combine and deduplicate by ent_seq
    final seenEntries = <int>{};
    final combined = <Map<String, dynamic>>[];

    for (final resultList in [kanjiResults, readingResults, meaningResults]) {
      for (final result in resultList) {
        final entSeq = result['ent_seq'] as int;
        if (!seenEntries.contains(entSeq)) {
          seenEntries.add(entSeq);
          combined.add(result);
          if (combined.length >= limit) break;
        }
      }
      if (combined.length >= limit) break;
    }

    return combined;
  }
}