import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../services/cloud/supabase_service.dart';
import '../helpers/fsrs/fsrs_database.dart';
import '../helpers/dictionary_helper.dart';
import '../helpers/fsrs_helper.dart';

Future<void> initialize() async {
    
    try {
    // Initialize Supabase
    debugPrint("Initializing Supabase...");
    await SupabaseService.initialize();
    debugPrint("Success!");
    
    debugPrint("Starting FFI support initialization...");
    await DictionaryHelper.initialize();

    if (kDebugMode) {
      await DictionaryHelper.debugTableStructure();
      final fts5Works = await DictionaryHelper.testFTS5Functionality();
      debugPrint('FTS5 functionality is ${fts5Works ? 'available' : 'not available'}.');
    }

    debugPrint("Initializing FSRS database...");
    await FSRSDatabase.initialize();
    
    // Check for bundled database and import
    // debugPrint("Checking for bundled FSRS database...");
    // await FSRSDatabase.importBundledDatabase();
    
    debugPrint("Initializing FSRS Helper...");
    await FSRSHelper.initialize();
    debugPrint("Success!");

    debugPrint("Database paths: ");
    final docDir = await getApplicationDocumentsDirectory();
    debugPrint("Documents directory: ${docDir.path}");
    final fsrsPath = join(docDir.path, "fsrs.db");
    final dictPath = join(docDir.path, "jmdict_fts5.db");
    debugPrint("FSRS database path: $fsrsPath (exists: ${await File(fsrsPath).exists()})");
    debugPrint("Dictionary path: $dictPath (exists: ${await File(dictPath).exists()})");
        
    debugPrint("✅ All initialization completed");
    
  } catch (e) {
    debugPrint("❌ Error during initialization: $e");
    rethrow;
  }
}