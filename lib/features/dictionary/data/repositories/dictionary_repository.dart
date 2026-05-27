import 'package:kian/features/dictionary/data/local/dictionary_database.dart';
import 'package:kian/core/logger.dart';

class DictionaryRepository {
  static const String _defaultLanguageTag = 'jp';
  static const String _definitionLanguageTag = 'eng';
  static const String _translationLanguageTag = 'eng';

  static String _resolveLanguageTag(String? languageTag) {
    final normalized = languageTag?.trim();
    return (normalized == null || normalized.isEmpty)
        ? _defaultLanguageTag
        : normalized;
  }

  static String? _firstString(List<Map<String, Object?>> rows, String key) {
    for (final row in rows) {
      final value = row[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }

  static String? _firstHeadwordByScript(
    List<Map<String, Object?>> headwords,
    String script,
  ) {
    for (final row in headwords) {
      if (row['script']?.toString() == script) {
        final text = row['text']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  static String? _firstHeadwordByScripts(
    List<Map<String, Object?>> headwords,
    List<String> scripts,
  ) {
    for (final script in scripts) {
      final value = _firstHeadwordByScript(headwords, script);
      if (value != null) return value;
    }
    return null;
  }

  static String? _firstReadingByLanguage(
    List<Map<String, Object?>> headwords,
    String languageTag,
  ) {
    for (final row in headwords) {
      final script = row['script']?.toString();
      final romanizationType = row['romanization_type']?.toString();
      final text = row['text']?.toString().trim();
      if (text == null || text.isEmpty) continue;

      if (languageTag == 'jp' && script == 'kana') {
        return text;
      }

      if (languageTag == 'cn' &&
          script == 'romanization' &&
          romanizationType == 'pinyin-numeric') {
        return text;
      }
    }

    return _firstString(headwords, 'text');
  }

  static String _readingHeadwordWhereClause(String languageTag) {
    if (languageTag == 'jp') {
      return "h.script = 'kana'";
    }

    if (languageTag == 'cn') {
      return "h.script = 'romanization' AND h.romanization_type = 'pinyin-numeric'";
    }

    return "h.script = 'kana' OR (h.script = 'romanization' AND h.romanization_type = 'pinyin-numeric')";
  }

  static List<String> _collectStrings(
    List<Map<String, Object?>> rows,
    String key,
  ) {
    final values = <String>[];
    for (final row in rows) {
      final value = row[key];
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty && !values.contains(text)) {
          values.add(text);
        }
      }
    }
    return values;
  }

  static bool _isCjkQuery(String query) {
    for (final rune in query.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
      if (rune >= 0x3400 && rune <= 0x4DBF) return true;
      if (rune >= 0xF900 && rune <= 0xFAFF) return true;
    }
    return false;
  }

  static String _buildFtsQuery(String query) {
    if (_isCjkQuery(query) && query.length > 1) {
      return '"$query"';
    }
    return '${query}*';
  }

  static Map<String, dynamic> _buildEntryResult({
    required int entryId,
    required List<Map<String, Object?>> headwords,
    required List<Map<String, Object?>> senses,
    required String lang,
  }) {
    final headword = _firstHeadwordByScript(headwords, 'cjk') ??
      _firstString(headwords, 'text');
    final reading = _firstReadingByLanguage(headwords, lang);
    final glosses = _collectStrings(senses, 'definitions');

    return {
      'entry_id': entryId,
      'headword': headword,
      'reading': reading,
      'gloss': glosses.isNotEmpty ? glosses.join('； ') : null,
      'is_reading_only': headword == null,
      'lang': lang,
    };
  }

  static Future<Map<String, dynamic>?> getEntryById(
    int entryId, {
    String languageTag = _defaultLanguageTag,
  }) async {
    try {
      final db = await DictionaryDatabase.getDatabase();
      final resolvedLanguageTag = _resolveLanguageTag(languageTag);

      kLog('Looking up dictionary entry: $entryId ($resolvedLanguageTag)');

      final entryRows = await db.rawQuery('''
        SELECT e.id AS entry_id, e.lang AS lang
        FROM entry e
        WHERE e.id = ? AND e.lang = ?
        LIMIT 1
      ''', [entryId, resolvedLanguageTag]);

      if (entryRows.isEmpty) {
        kLog('No entry found with ID $entryId');
        return null;
      }

      final headwords = await db.rawQuery('''
        SELECT id, text, script, romanization_type, position, is_primary
        FROM headword
        WHERE entry_id = ?
        ORDER BY is_primary DESC, position ASC, id ASC
      ''', [entryId]);

      final senses = await db.rawQuery('''
        SELECT
          s.id,
          s.position,
          GROUP_CONCAT(DISTINCT d.text) AS definitions,
          GROUP_CONCAT(DISTINCT st.value) AS part_of_speech
        FROM sense s
        LEFT JOIN definition d ON d.sense_id = s.id
        LEFT JOIN sense_tag st ON st.sense_id = s.id AND st.tag_type = 'pos'
        WHERE s.entry_id = ? AND s.def_lang = ?
        GROUP BY s.id, s.position
        ORDER BY s.position ASC, s.id ASC
      ''', [entryId, _definitionLanguageTag]);

      final result = _buildEntryResult(
        entryId: entryId,
        headwords: headwords,
        senses: senses,
        lang: (entryRows.first['lang'] ?? resolvedLanguageTag).toString(),
      );

      kLog('Found entry: $result');
      return result;
    } catch (e) {
      kLog('Error in getEntryById: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getMultipleEntries(
    List<int> entryIds, {
    String languageTag = _defaultLanguageTag,
  }) async {
    if (entryIds.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    for (final id in entryIds) {
      final entry = await getEntryById(id, languageTag: languageTag);
      if (entry != null) {
        results.add(entry);
      }
    }
    return results;
  }

  static Future<List<Map<String, dynamic>>> _searchHeadwordFts({
    required String query,
    required String languageTag,
    required String scriptClause,
    required int limit,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final ftsQuery = _buildFtsQuery(query);
    final readingClause = _readingHeadwordWhereClause(languageTag);

    return db.rawQuery('''
      SELECT DISTINCT
        e.id AS entry_id,
        e.lang AS lang,
        (
          SELECT h.text
          FROM headword h
          WHERE h.entry_id = e.id AND h.script = 'cjk'
          ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
          LIMIT 1
        ) AS headword,
        (
          SELECT h.text
          FROM headword h
          WHERE h.entry_id = e.id AND ($readingClause)
          ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
          LIMIT 1
        ) AS reading,
        (
          SELECT GROUP_CONCAT(d.text, '； ')
          FROM sense s
          JOIN definition d ON d.sense_id = s.id
          WHERE s.entry_id = e.id AND s.def_lang = ?
        ) AS gloss
      FROM headword_fts hf
      JOIN headword h ON h.id = hf.rowid AND $scriptClause
      JOIN entry e ON e.id = h.entry_id
      WHERE hf.text MATCH ? AND e.lang = ?
      ORDER BY e.id ASC
      LIMIT ?
    ''', [_definitionLanguageTag, ftsQuery, languageTag, limit]);
  }

  static Future<List<Map<String, dynamic>>> _searchHeadwordLike({
    required String query,
    required String languageTag,
    required String scriptClause,
    required int limit,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final readingClause = _readingHeadwordWhereClause(languageTag);
    return db.rawQuery('''
      SELECT DISTINCT
        e.id AS entry_id,
        e.lang AS lang,
        (
          SELECT h.text
          FROM headword h
          WHERE h.entry_id = e.id AND h.script = 'cjk'
          ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
          LIMIT 1
        ) AS headword,
        (
          SELECT h.text
          FROM headword h
          WHERE h.entry_id = e.id AND ($readingClause)
          ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
          LIMIT 1
        ) AS reading,
        (
          SELECT GROUP_CONCAT(d.text, '； ')
          FROM sense s
          JOIN definition d ON d.sense_id = s.id
          WHERE s.entry_id = e.id AND s.def_lang = ?
        ) AS gloss
      FROM headword h
      JOIN entry e ON e.id = h.entry_id
      WHERE $scriptClause AND h.text LIKE ? AND e.lang = ?
      ORDER BY e.id ASC
      LIMIT ?
    ''', [_definitionLanguageTag, '${query}%', languageTag, limit]);
  }

  static Future<List<Map<String, dynamic>>> searchByKanji(
    String query, {
    int limit = 20,
    String languageTag = _defaultLanguageTag,
  }) async {
    final resolvedLanguageTag = _resolveLanguageTag(languageTag);
    try {
      final scriptClause = "h.script = 'cjk'";
      final results = await _searchHeadwordFts(
        query: query,
        languageTag: resolvedLanguageTag,
        scriptClause: scriptClause,
        limit: limit,
      );

      if (results.isNotEmpty || !_isCjkQuery(query)) {
        return results;
      }

      return _searchHeadwordLike(
        query: query,
        languageTag: resolvedLanguageTag,
        scriptClause: scriptClause,
        limit: limit,
      );
    } catch (e) {
      kLog('Error searching kanji: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchByReading(
    String query, {
    int limit = 20,
    String languageTag = _defaultLanguageTag,
  }) async {
    final resolvedLanguageTag = _resolveLanguageTag(languageTag);
    try {
      final scriptClause = "h.script IN ('kana', 'romaji')";
      final results = await _searchHeadwordFts(
        query: query,
        languageTag: resolvedLanguageTag,
        scriptClause: scriptClause,
        limit: limit,
      );

      if (results.isNotEmpty || !_isCjkQuery(query)) {
        return results;
      }

      return _searchHeadwordLike(
        query: query,
        languageTag: resolvedLanguageTag,
        scriptClause: scriptClause,
        limit: limit,
      );
    } catch (e) {
      kLog('Error searching reading: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchByMeaning(
    String query, {
    int limit = 20,
    String languageTag = _defaultLanguageTag,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final resolvedLanguageTag = _resolveLanguageTag(languageTag);

    try {
      final results = await db.rawQuery('''
        SELECT DISTINCT
          e.id AS entry_id,
          e.lang AS lang,
          (
            SELECT h.text
            FROM headword h
            WHERE h.entry_id = e.id AND h.script = 'cjk'
            ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
            LIMIT 1
          ) AS headword,
          (
            SELECT h.text
            FROM headword h
            WHERE h.entry_id = e.id AND (${_readingHeadwordWhereClause(resolvedLanguageTag)})
            ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
            LIMIT 1
          ) AS reading,
          (
            SELECT GROUP_CONCAT(d2.text, '； ')
            FROM sense s2
            JOIN definition d2 ON d2.sense_id = s2.id
            WHERE s2.entry_id = e.id AND s2.def_lang = ?
          ) AS gloss
        FROM definition_fts df
        JOIN definition d ON d.id = df.rowid
        JOIN sense s ON s.id = d.sense_id
        JOIN entry e ON e.id = s.entry_id
        WHERE df.text MATCH ? AND e.lang = ?
        ORDER BY e.id ASC
        LIMIT ?
      ''', [_definitionLanguageTag, '${query}*', resolvedLanguageTag, limit]);

      return results;
    } catch (e) {
      kLog('Error searching meaning: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchAll(
    String query, {
    int limit = 20,
    String languageTag = _defaultLanguageTag,
  }) async {
    final perSearchLimit = limit ~/ 3;
    final searchLimit = perSearchLimit > 0 ? perSearchLimit : limit;
    final kanjiResults = await searchByKanji(
      query,
      limit: searchLimit,
      languageTag: languageTag,
    );
    final readingResults = await searchByReading(
      query,
      limit: searchLimit,
      languageTag: languageTag,
    );
    final meaningResults = await searchByMeaning(
      query,
      limit: searchLimit,
      languageTag: languageTag,
    );

    final seenEntries = <int>{};
    final combined = <Map<String, dynamic>>[];

    for (final resultList in [kanjiResults, readingResults, meaningResults]) {
      for (final result in resultList) {
        final resolved = (result['entry_id']) as int;
        if (!seenEntries.contains(resolved)) {
          seenEntries.add(resolved);
          combined.add(result);
          if (combined.length >= limit) break;
        }
      }
      if (combined.length >= limit) break;
    }

    return combined;
  }

  static Future<List<Map<String, dynamic>>> getMeanings(
    int entryId, {
    String languageTag = _defaultLanguageTag,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    return db.rawQuery("""
      SELECT
        s.id,
        s.position,
        GROUP_CONCAT(DISTINCT d.text) AS definitions,
        GROUP_CONCAT(DISTINCT st.value) AS part_of_speech
      FROM sense s
      LEFT JOIN definition d ON d.sense_id = s.id
      LEFT JOIN sense_tag st ON st.sense_id = s.id AND st.tag_type = 'pos'
      WHERE s.entry_id = ? AND s.def_lang = ?
      GROUP BY s.id, s.position
      ORDER BY s.position ASC, s.id ASC
    """, [entryId, _definitionLanguageTag]);
  }

  static Future<List<Map<String, dynamic>>> getExamples(
    int entryId, {
    String languageTag = _defaultLanguageTag,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    return db.rawQuery("""
      SELECT
        s.id as sense_id,
        ex.id as example_id,
        ex.text as japanese_text,
        ex.translation as english_translation,
        ex.translation_lang as translation_lang,
        ex.source as source
      FROM sense s
      JOIN example ex ON s.id = ex.sense_id
      WHERE s.entry_id = ?
        AND s.def_lang = ?
        AND (ex.translation_lang = ? OR ex.translation_lang IS NULL)
      ORDER BY s.position ASC, s.id ASC, ex.id ASC
    """, [entryId, _definitionLanguageTag, _translationLanguageTag]);
  }
}
