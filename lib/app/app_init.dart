import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:kian/services/cloud/supabase_service.dart';
import 'package:kian/features/fsrs/data/local/fsrs_database.dart';
import 'package:kian/features/dictionary/domain/dictionary_helper.dart';
import 'package:kian/features/fsrs/domain/fsrs_helper.dart';
import 'package:kian/core/logger.dart';

Future<void> initialize() async {
  try {
    kLog('Initializing Supabase...');
    await SupabaseService.initialize();
    kLog('Supabase ready.');

    kLog('Initializing dictionary database...');
    await DictionaryHelper.initialize();

    if (kDebugMode) {
      await DictionaryHelper.debugTableStructure();
      final fts5Works = await DictionaryHelper.testFTS5Functionality();
      kLog('FTS5 functionality is ${fts5Works ? 'available' : 'not available'}.');
    }

    kLog('Initializing FSRS database...');
    await FSRSDatabase.initialize();

    kLog('Initializing FSRS helper...');
    await FSRSHelper.initialize();
    kLog('FSRS ready.');

    kLog('Database paths:');
    final docDir = await getApplicationDocumentsDirectory();
    kLog('Documents directory: ${docDir.path}');
    final fsrsPath = join(docDir.path, 'fsrs.db');
    final dictPath = join(docDir.path, 'dictionary.db');
    kLog('FSRS database path: $fsrsPath (exists: ${await File(fsrsPath).exists()})');
    kLog('Dictionary path: $dictPath (exists: ${await File(dictPath).exists()})');

    kLog('All initialization completed.');
  } catch (e) {
    kLog('Error during initialization: $e');
    rethrow;
  }
}