import 'package:kian/core/logger.dart';
import 'package:kian/core/db_factory.dart';
import 'debugger.dart';
import 'download_progress.dart';
import 'installer.dart';

import 'package:sqflite_common/sqlite_api.dart';

class DictionaryDatabase {
  static final DictionaryInstaller _installer = DictionaryInstaller();

  static Database? _database;
  static Future<Database>? _openingFuture;

  static Future<void> initialize({
    DictionaryDownloadProgress? onProgress,
  }) async {
    await _installer.ensureInstalled(onProgress: onProgress);
    await getDatabase();
  }

  static Future<String> getDatabasePath() => _installer.getDatabasePath();

  static Future<Database> getDatabase() {
    final database = _database;

    if (database != null) {
      return Future.value(database);
    }

    return _openingFuture ??= _openDatabase();
  }

  static Future<Database> _openDatabase() async {
    try {
      final databasePath = await _installer.ensureInstalled();

      final database = await DatabaseFactories.dictionary.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          readOnly: true,
          singleInstance: true,
          onOpen: (_) {
            kLog('Dictionary database opened using FFI');
            kLog('DB path: $databasePath');
          },
        ),
      );

      _database = database;
      return database;
    } catch (_) {
      _openingFuture = null;
      rethrow;
    }
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
    _openingFuture = null;
  }

  static Future<void> deleteInstalledDictionary() async {
    await close();
    await _installer.deleteInstallation();
  }

  static Future<void> debugTableStructure() async {
    final database = await getDatabase();
    await DictionaryDatabaseDebugger(database).debugTableStructure();
  }

  static Future<bool> testFTS5Functionality() async {
    final database = await getDatabase();
    return DictionaryDatabaseDebugger(database).testFts5Functionality();
  }
}
