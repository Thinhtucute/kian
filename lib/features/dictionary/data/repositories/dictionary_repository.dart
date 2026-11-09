import 'package:kian/core/logger.dart';
import 'package:kian/features/dictionary/data/local/dictionary_database.dart';
import 'package:kian/features/dictionary/domain/entry_model.dart';
import 'package:kian/features/dictionary/domain/entry_presentation_mapper.dart';
import 'package:kian/features/dictionary/domain/example_model.dart';
import 'package:kian/features/dictionary/domain/headword_model.dart';
import 'package:kian/features/dictionary/domain/kanji_detail_model.dart';
import 'package:kian/features/dictionary/domain/sense_model.dart';

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

  static Map<String, Object?>? _firstHeadwordRowByScript(
    List<Map<String, Object?>> headwords,
    String script,
  ) {
    for (final row in headwords) {
      if (row['script']?.toString() == script) {
        final text = row['text']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          return row;
        }
      }
    }
    return null;
  }

  static Map<String, Object?>? _firstHeadwordRow(
    List<Map<String, Object?>> headwords,
  ) {
    return _firstHeadwordRowByScript(headwords, 'cjk') ??
        (() {
          for (final row in headwords) {
            final text = row['text']?.toString().trim();
            if (text != null && text.isNotEmpty) {
              return row;
            }
          }
          return null;
        })();
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

  static String _readingScriptClause(String languageTag) {
    if (languageTag == 'jp') {
      return "h.script = 'kana'";
    }

    if (languageTag == 'cn') {
      return "h.script = 'romanization' AND h.romanization_type = 'pinyin-numeric'";
    }

    return "h.script IN ('kana', 'romaji', 'romanization')";
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

  static bool _isKanaQuery(String query) {
    return query.runes.any(
      (rune) =>
          (rune >= 0x3040 && rune <= 0x309F) ||
          (rune >= 0x30A0 && rune <= 0x30FF) ||
          (rune >= 0xFF66 && rune <= 0xFF9F),
    );
  }

  static String _buildFtsQuery(String query) {
    if (_isCjkQuery(query) && query.length > 1) {
      return '"$query"';
    }
    return '$query*';
  }

  static Future<List<Map<String, Object?>>> _searchHeadwordFts({
    required String query,
    required String languageTag,
    required String scriptClause,
    required int limit,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final ftsQuery = _buildFtsQuery(query);
    final readingClause = _readingHeadwordWhereClause(languageTag);

    final results = await db.rawQuery('''
      SELECT DISTINCT
        e.id AS entry_id,
        e.lang AS lang,
        (
          SELECT COALESCE(
            (
              SELECT h.script
              FROM headword h
              WHERE h.entry_id = e.id AND h.script = 'cjk'
              ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
              LIMIT 1
            ),
            (
              SELECT h.script
              FROM headword h
              WHERE h.entry_id = e.id
              ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
              LIMIT 1
            )
          )
        ) AS script,
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

    return results;
  }

  static Future<List<Map<String, Object?>>> _searchHeadwordLike({
    required String query,
    required String languageTag,
    required String scriptClause,
    required int limit,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final readingClause = _readingHeadwordWhereClause(languageTag);
    final useGlob = _isCjkQuery(query) || _isKanaQuery(query);
    final prefixOperator = useGlob ? 'GLOB' : 'LIKE';
    final prefixPattern = useGlob ? '$query*' : '$query%';

    final results = await db.rawQuery('''
      SELECT DISTINCT
        e.id AS entry_id,
        e.lang AS lang,
        (
          SELECT COALESCE(
            (
              SELECT h.script
              FROM headword h
              WHERE h.entry_id = e.id AND h.script = 'cjk'
              ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
              LIMIT 1
            ),
            (
              SELECT h.script
              FROM headword h
              WHERE h.entry_id = e.id
              ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
              LIMIT 1
            )
          )
        ) AS script,
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
      WHERE $scriptClause AND h.text $prefixOperator ? AND e.lang = ?
      ORDER BY e.id ASC
      LIMIT ?
    ''', [_definitionLanguageTag, prefixPattern, languageTag, limit]);

    return results;
  }

  static Entry _buildEntryModelFromRow(
    Map<String, Object?> row, {
    required String languageTag,
  }) {
    return EntryPresentationMapper.buildEntryFromSource(row,
        languageTag: languageTag);
  }

  static Future<Entry?> getEntryModelById(
    int entryId, {
    String languageTag = _defaultLanguageTag,
  }) async {
    try {
      final db = await DictionaryDatabase.getDatabase();
      final resolvedLanguageTag = _resolveLanguageTag(languageTag);

      final entryRows = await db.rawQuery('''
        SELECT e.id AS entry_id, e.lang AS lang
        FROM entry e
        WHERE e.id = ? AND e.lang = ?
        LIMIT 1
      ''', [entryId, resolvedLanguageTag]);

      if (entryRows.isEmpty) {
        return null;
      }

      final headwords = await db.rawQuery('''
        SELECT id, entry_id, text, script, romanization_type, position, is_primary
        FROM headword
        WHERE entry_id = ?
        ORDER BY is_primary DESC, position ASC, id ASC
      ''', [entryId]);

      final senses = await db.rawQuery('''
        SELECT
          s.id,
          s.entry_id,
          s.position,
          GROUP_CONCAT(DISTINCT d.text) AS definitions,
          GROUP_CONCAT(DISTINCT st.value) AS part_of_speech
        FROM sense s
        LEFT JOIN definition d ON d.sense_id = s.id
        LEFT JOIN sense_tag st ON st.sense_id = s.id AND st.tag_type = 'pos'
        WHERE s.entry_id = ? AND s.def_lang = ?
        GROUP BY s.id, s.entry_id, s.position
        ORDER BY s.position ASC, s.id ASC
      ''', [entryId, _definitionLanguageTag]);

      final examples = await db.rawQuery('''
        SELECT
          s.id as sense_id,
          ex.id as id,
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
      ''', [entryId, _definitionLanguageTag, _translationLanguageTag]);

      final headwordRow = _firstHeadwordRow(headwords);
      final headword = headwordRow?['text']?.toString().trim();
      final headwordScript = headwordRow?['script']?.toString();
      final reading = _firstReadingByLanguage(headwords, resolvedLanguageTag);
      final glosses = _collectStrings(senses, 'definitions');

      final base = _buildEntryModelFromRow(
        {
          'entry_id': entryId,
          'lang': (entryRows.first['lang'] ?? resolvedLanguageTag).toString(),
          'headword': headword,
          'headword_script': headwordScript,
          'reading': reading,
          'gloss': glosses.isNotEmpty ? glosses.join('； ') : null,
          'is_reading_only': headword == null,
        },
        languageTag: resolvedLanguageTag,
      );

      return Entry(
        entryId: base.entryId,
        lang: base.lang,
        headword: base.headword,
        headwordScript: base.headwordScript,
        reading: base.reading,
        gloss: base.gloss,
        isReadingOnly: base.isReadingOnly,
        showReadingAbove: base.showReadingAbove,
        displayHeadword: base.displayHeadword,
        displayReading: base.displayReading,
        headwords:
            EntryPresentationMapper.buildHeadwordListFromSource(headwords),
        senses: EntryPresentationMapper.buildSenseListFromSource(senses),
        examples: EntryPresentationMapper.buildExampleListFromSource(examples),
      );
    } catch (e) {
      kLog('Error in getEntryModelById: $e');
      return null;
    }
  }

  static Future<List<Entry>> getMultipleEntryModels(
    List<int> entryIds, {
    String languageTag = _defaultLanguageTag,
  }) async {
    if (entryIds.isEmpty) return [];

    final results = <Entry>[];
    for (final id in entryIds) {
      final entry = await getEntryModelById(id, languageTag: languageTag);
      if (entry != null) {
        results.add(entry);
      }
    }
    return results;
  }

  static Future<List<Headword>> getHeadwordsModels(int entryId) async {
    final db = await DictionaryDatabase.getDatabase();
    final rows = await db.rawQuery('''
      SELECT id, entry_id, text, script, romanization_type, position, is_primary
      FROM headword
      WHERE entry_id = ?
      ORDER BY is_primary DESC, position ASC, id ASC
    ''', [entryId]);
    return EntryPresentationMapper.buildHeadwordListFromSource(rows);
  }

  static Future<KanjiDetail?> getKanjiDetailModel(String character) async {
    final db = await DictionaryDatabase.getDatabase();
    final characterRows = await db.rawQuery('''
      SELECT id, character, codepoint
      FROM cjk_char
      WHERE character = ?
      LIMIT 1
    ''', [character]);

    if (characterRows.isEmpty) return null;

    final characterRow = characterRows.first;
    final propertyRows = await db.rawQuery('''
      SELECT key, value
      FROM cjk_char_property
      WHERE char_id = ?
      ORDER BY key ASC, id ASC
    ''', [characterRow['id']]);

    return KanjiDetail.fromRows(character, characterRow, propertyRows);
  }

  static Future<List<Sense>> getMeaningsModels(
    int entryId, {
    String languageTag = _defaultLanguageTag,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final rows = await db.rawQuery('''
      SELECT
        s.id,
        s.entry_id,
        s.position,
        GROUP_CONCAT(DISTINCT d.text) AS definitions,
        GROUP_CONCAT(DISTINCT st.value) AS part_of_speech
      FROM sense s
      LEFT JOIN definition d ON d.sense_id = s.id
      LEFT JOIN sense_tag st ON st.sense_id = s.id AND st.tag_type = 'pos'
      WHERE s.entry_id = ? AND s.def_lang = ?
      GROUP BY s.id, s.entry_id, s.position
      ORDER BY s.position ASC, s.id ASC
    ''', [entryId, _definitionLanguageTag]);
    return EntryPresentationMapper.buildSenseListFromSource(rows);
  }

  static Future<List<Example>> getExamplesModels(
    int entryId, {
    String languageTag = _defaultLanguageTag,
  }) async {
    final db = await DictionaryDatabase.getDatabase();
    final rows = await db.rawQuery('''
      SELECT
        s.id as sense_id,
        ex.id as id,
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
    ''', [entryId, _definitionLanguageTag, _translationLanguageTag]);
    return EntryPresentationMapper.buildExampleListFromSource(rows);
  }

  static Future<List<Entry>> searchByKanjiModels(
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

      final mapResults =
          results.isNotEmpty || (!_isCjkQuery(query) && !_isKanaQuery(query))
              ? results
              : await _searchHeadwordLike(
                  query: query,
                  languageTag: resolvedLanguageTag,
                  scriptClause: scriptClause,
                  limit: limit,
                );

      return EntryPresentationMapper.buildEntryListFromSource(
        mapResults,
        languageTag: resolvedLanguageTag,
      );
    } catch (e) {
      kLog('Error searching kanji: $e');
      return [];
    }
  }

  static Future<List<Entry>> searchByReadingModels(
    String query, {
    int limit = 20,
    String languageTag = _defaultLanguageTag,
  }) async {
    final resolvedLanguageTag = _resolveLanguageTag(languageTag);
    try {
      final scriptClause = _readingScriptClause(resolvedLanguageTag);
      final results = await _searchHeadwordFts(
        query: query,
        languageTag: resolvedLanguageTag,
        scriptClause: scriptClause,
        limit: limit,
      );

      final mapResults =
          results.isNotEmpty || (!_isCjkQuery(query) && !_isKanaQuery(query))
              ? results
              : await _searchHeadwordLike(
                  query: query,
                  languageTag: resolvedLanguageTag,
                  scriptClause: scriptClause,
                  limit: limit,
                );

      return EntryPresentationMapper.buildEntryListFromSource(
        mapResults,
        languageTag: resolvedLanguageTag,
      );
    } catch (e) {
      kLog('Error searching reading: $e');
      return [];
    }
  }

  static Future<List<Entry>> searchByMeaningModels(
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
            SELECT COALESCE(
              (
                SELECT h.script
                FROM headword h
                WHERE h.entry_id = e.id AND h.script = 'cjk'
                ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
                LIMIT 1
              ),
              (
                SELECT h.script
                FROM headword h
                WHERE h.entry_id = e.id
                ORDER BY h.is_primary DESC, h.position ASC, h.id ASC
                LIMIT 1
              )
            )
          ) AS script,
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
      ''', [_definitionLanguageTag, '$query*', resolvedLanguageTag, limit]);

      return EntryPresentationMapper.buildEntryListFromSource(
        results,
        languageTag: resolvedLanguageTag,
      );
    } catch (e) {
      kLog('Error searching meaning: $e');
      return [];
    }
  }

  static Future<List<Entry>> searchAllModels(
    String query, {
    int limit = 20,
    String languageTag = _defaultLanguageTag,
  }) async {
    final perSearchLimit = limit ~/ 3;
    final searchLimit = perSearchLimit > 0 ? perSearchLimit : limit;

    final kanjiResults = await searchByKanjiModels(
      query,
      limit: searchLimit,
      languageTag: languageTag,
    );
    final readingResults = await searchByReadingModels(
      query,
      limit: searchLimit,
      languageTag: languageTag,
    );
    final meaningResults = await searchByMeaningModels(
      query,
      limit: searchLimit,
      languageTag: languageTag,
    );

    final seenEntries = <int>{};
    final combined = <Entry>[];

    for (final resultList in [kanjiResults, readingResults, meaningResults]) {
      for (final result in resultList) {
        if (seenEntries.add(result.entryId)) {
          combined.add(result);
          if (combined.length >= limit) break;
        }
      }
      if (combined.length >= limit) break;
    }

    return combined;
  }
}
