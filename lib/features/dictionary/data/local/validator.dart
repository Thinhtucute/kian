import 'dart:io';

import 'package:kian/core/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DictionaryValidator {
  static bool _ffiInitialized = false;

  static const Set<String> expectedTables = {
    'entry',
    'headword',
    'sense',
    'definition',
    'example',
    'headword_fts',
    'definition_fts',
  };
// Initialize FFI for FTS5 DO NOT REMOVE DO NOT REMOVE DO NOT REMOVE
  static void _initializeFfi() {
    if (_ffiInitialized) return;

    sqfliteFfiInit();
    _ffiInitialized = true;
  }

  Future<bool> isValid(File file) async {
    if (!await file.exists() || await file.length() == 0) {
      return false;
    }

    Database? database;

    try {
      _initializeFfi();

      database = await databaseFactoryFfi.openDatabase(
        file.path,
        options: OpenDatabaseOptions(
          readOnly: true,
          singleInstance: false,
        ),
      );

      final rows = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type IN ('table', 'view')
      ''');

      final actualTables = rows
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      final missingTables = expectedTables.difference(actualTables);

      if (missingTables.isNotEmpty) {
        kLog(
          'Dictionary database is missing tables: '
          '${missingTables.join(', ')}',
        );
        return false;
      }

      await database.rawQuery('''
        SELECT rowid
        FROM headword_fts
        LIMIT 1
      ''');

      return true;
    } catch (error) {
      kLog('Dictionary database validation failed: $error');
      return false;
    } finally {
      await database?.close();
    }
  }

  Future<void> validateOrThrow(File file) async {
    if (!await isValid(file)) {
      throw StateError('Invalid dictionary database: ${file.path}');
    }
  }
}