import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../services/cloud/supabase_service.dart';
import '../helpers/fsrs/fsrs_database.dart';
import '../helpers/dictionary_helper.dart';
import '../helpers/fsrs_helper.dart';
import '../helpers/logger.dart';

Future<void> initialize() async {
    
    try {
    // Initialize Supabase
    kLog("Initializing Supabase...");
    await SupabaseService.initialize();
    kLog("Success!");
    
    kLog("Starting FFI support initialization...");
    await DictionaryHelper.initialize();

    if (kDebugMode) {
      await DictionaryHelper.debugTableStructure();
      final fts5Works = await DictionaryHelper.testFTS5Functionality();
      kLog('FTS5 functionality is ${fts5Works ? 'available' : 'not available'}.');
    }

    kLog("Initializing FSRS database...");
    await FSRSDatabase.initialize();
    
    
    kLog("Initializing FSRS Helper...");
    await FSRSHelper.initialize();
    kLog("Success!");

    kLog("Database paths: ");
    final docDir = await getApplicationDocumentsDirectory();
    kLog("Documents directory: ${docDir.path}");
    final fsrsPath = join(docDir.path, "fsrs.db");
    final dictPath = join(docDir.path, "jmdict_fts5.db");
    kLog("FSRS database path: $fsrsPath (exists: ${await File(fsrsPath).exists()})");
    kLog("Dictionary path: $dictPath (exists: ${await File(dictPath).exists()})");
        
    kLog("✅ All initialization completed");
    
  } catch (e) {
    kLog("❌ Error during initialization: $e");
    rethrow;
  }
}