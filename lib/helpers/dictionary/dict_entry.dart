import 'package:flutter/foundation.dart';
import 'dict_database.dart';

class DictionaryEntryService {
  static Future<Map<String, dynamic>?> getEntryById(int entryId) async {
    try {
      final db = await DictionaryDatabase.getDatabase();

      debugPrint('Looking up dictionary entry: $entryId');

      // First verify the entry exists in the reading table (all entries should have readings)
      final entryCheck = await db.rawQuery(
          'SELECT ent_seq FROM reading_element WHERE ent_seq = ? LIMIT 1',
          [entryId]);

      if (entryCheck.isEmpty) {
        debugPrint('No entry found with ID $entryId');
        return null;
      }

      // Get reading (should always exist)
      final reading = await db.rawQuery(
          'SELECT reb FROM reading_element WHERE ent_seq = ? LIMIT 1',
          [entryId]);

      // Get kanji (might not exist for kana-only words)
      final kanji = await db.rawQuery(
          'SELECT keb FROM kanji_element WHERE ent_seq = ? LIMIT 1', [entryId]);

      // Determine if this is a kana-only word
      final isKanaOnly = kanji.isEmpty && reading.isNotEmpty;

      // Get gloss/meaning using a simple join
      final gloss = await db.rawQuery('''
        SELECT g.gloss 
        FROM gloss g
        JOIN sense s ON g.sense_id = s.id
        WHERE s.ent_seq = ?
        LIMIT 1
      ''', [entryId]);

      // Build response
      final result = {
        'ent_seq': entryId,
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

  static Future<List<Map<String, dynamic>>> getMultipleEntries(List<int> entryIds) async {
    if (entryIds.isEmpty) return [];
    
    final results = <Map<String, dynamic>>[];
    for (final id in entryIds) {
      final entry = await getEntryById(id);
      if (entry != null) {
        results.add(entry);
      }
    }
    return results;
  }
}