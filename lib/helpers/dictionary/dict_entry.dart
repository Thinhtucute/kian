import 'package:flutter/foundation.dart';
import 'dict_database.dart';

class DictionaryEntryService {
  static Future<Map<String, dynamic>?> getEntryById(int entSeq) async {
    try {
      final db = await DictionaryDatabase.getDatabase();

      debugPrint('Looking up dictionary entry: $entSeq');

      // First verify the entry exists in the reading table (all entries should have readings)
      final entryCheck = await db.rawQuery(
          'SELECT ent_seq FROM reading_element WHERE ent_seq = ? LIMIT 1',
          [entSeq]);

      if (entryCheck.isEmpty) {
        debugPrint('No entry found with ID $entSeq');
        return null;
      }

      // Get reading (should always exist)
      final reading = await db.rawQuery(
          'SELECT reb FROM reading_element WHERE ent_seq = ? LIMIT 1',
          [entSeq]);

      // Get kanji (might not exist for kana-only words)
      final kanji = await db.rawQuery(
          'SELECT keb FROM kanji_element WHERE ent_seq = ? LIMIT 1', [entSeq]);

      // Determine if this is a kana-only word
      final isKanaOnly = kanji.isEmpty && reading.isNotEmpty;

      // Get gloss/meaning using a simple join
      final gloss = await db.rawQuery('''
        SELECT g.gloss 
        FROM gloss g
        JOIN sense s ON g.sense_id = s.id
        WHERE s.ent_seq = ?
        LIMIT 1
      ''', [entSeq]);

      // Build response
      final result = {
        'ent_seq': entSeq,
        'keb': kanji.isNotEmpty ? kanji.first['keb'] : null,
        'reb': reading.isNotEmpty ? reading.first['reb'] : null,
        'gloss': gloss.isNotEmpty ? gloss.first['gloss'] : null,
        'is_kana_only': isKanaOnly,
      };

      debugPrint('Found entry: $result');
      return result;
    } catch (e) {
      debugPrint('Error in getEntryById: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getMultipleEntries(List<int> entSeqs) async {
    if (entSeqs.isEmpty) return [];
    
    final results = <Map<String, dynamic>>[];
    for (final id in entSeqs) {
      final entry = await getEntryById(id);
      if (entry != null) {
        results.add(entry);
      }
    }
    return results;
  }
}