import 'package:kian/core/logger.dart';
import 'package:sqflite/sqflite.dart';

class DictionaryDatabaseDebugger {
  DictionaryDatabaseDebugger(this._database);

  final Database _database;

  Future<void> debugTableStructure() async {
    kLog('\nChecking dictionary structure...');
    const mainTables = ['entry', 'headword', 'sense', 'definition', 'example'];

    for (final table in mainTables) {
      try {
        final columns = await _database.rawQuery('PRAGMA table_info($table)');
        kLog('\n$table columns:');
        for (final column in columns) {
          kLog('  ${column['name']} (${column['type']})');
        }

        final sample = await _database.rawQuery('SELECT * FROM $table LIMIT 1');
        kLog(sample.isNotEmpty ? '- Sample row: ${sample.first}' : '- No data');
      } catch (error) {
        kLog('Error checking $table: $error');
      }
    }

    kLog('\nChecking FTS5 tables...');
    const ftsTables = ['headword_fts', 'definition_fts', 'example_fts'];

    for (final table in ftsTables) {
      try {
        final sample = await _database.rawQuery('SELECT * FROM $table LIMIT 1');
        if (sample.isNotEmpty) {
          kLog('\n$table columns: ${sample.first.keys.join(', ')}');
          kLog('- Sample: ${sample.first}');
        } else {
          kLog('\n$table exists but is empty');
        }
      } catch (error) {
        kLog('Error checking $table: $error');
      }
    }
  }

  Future<bool> testFts5Functionality() async {
    kLog('\nTesting FTS5 functionality...');

    try {
      for (final query in const ['食べ*', '人*']) {
        final results = await _database.rawQuery(
          '''
          SELECT *
          FROM headword_fts
          WHERE text MATCH ?
          LIMIT 5
          ''',
          [query],
        );

        if (results.isNotEmpty) {
          kLog('FTS5 found ${results.length} results for "$query"');
          kLog('First result: ${results.first}');
          return true;
        }
      }

      kLog('FTS5 queries worked but returned no common words');
      return false;
    } catch (error) {
      kLog('FTS5 query failed: $error');
      return false;
    }
  }
}
