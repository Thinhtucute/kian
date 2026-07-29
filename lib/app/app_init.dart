import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kian/core/logger.dart';
import 'package:kian/features/dictionary/data/local/download_progress.dart';
import 'package:kian/features/dictionary/domain/dictionary_helper.dart';
import 'package:kian/features/fsrs/data/local/fsrs_database.dart';
import 'package:kian/features/fsrs/domain/fsrs_helper.dart';
import 'package:kian/services/cloud/supabase_service.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initialize({
  void Function(String stage)? onStageChanged,
  DictionaryDownloadProgress? onDictionaryProgress,
}) async {
  try {
    onStageChanged?.call('Connecting to services...');
    kLog('Initializing Supabase...');
    await SupabaseService.initialize();
    kLog('Supabase ready.');

    onStageChanged?.call('Checking offline dictionary...');
    kLog('Initializing dictionary database...');
    await DictionaryHelper.initialize(
      onProgress: onDictionaryProgress,
    );

    onStageChanged?.call('Verifying offline dictionary...');
    if (kDebugMode) {
      await DictionaryHelper.debugTableStructure();
      final fts5Works = await DictionaryHelper.testFTS5Functionality();
      kLog(
        'FTS5 functionality is '
        '${fts5Works ? 'available' : 'not available'}.',
      );
    }

    onStageChanged?.call('Preparing review database...');
    kLog('Initializing FSRS database...');
    await FSRSDatabase.initialize();

    onStageChanged?.call('Preparing review system...');
    kLog('Initializing FSRS helper...');
    await FSRSHelper.initialize();
    kLog('FSRS ready.');

    if (kDebugMode) {
      kLog('Database paths:');
      final docDir = await getApplicationDocumentsDirectory();
      kLog('Documents directory: ${docDir.path}');
      final fsrsPath = join(docDir.path, 'fsrs.db');
      kLog(
        'FSRS database path: $fsrsPath '
        '(exists: ${await File(fsrsPath).exists()})',
      );

      final dictionaryPath = await DictionaryHelper.getDatabasePath();
      kLog(
        'Dictionary path: $dictionaryPath '
        '(exists: ${await File(dictionaryPath).exists()})',
      );
    }

    onStageChanged?.call('Ready');
    kLog('All initialization completed.');
  } catch (error, stackTrace) {
    kLog('Error during initialization: $error');
    kLog('$stackTrace');
    rethrow;
  }
}
