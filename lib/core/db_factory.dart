import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseFactories {
  DatabaseFactories._();

  static bool _ffiInitialized = false;

// Initialize FFI for FTS5 DO NOT REMOVE DO NOT REMOVE DO NOT REMOVE
  static void initialize() {
    if (_ffiInitialized) return;

    sqfliteFfiInit();
    _ffiInitialized = true;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      databaseFactory = databaseFactoryFfi;
    }
  }

  static DatabaseFactory get dictionary => databaseFactoryFfi;
  static DatabaseFactory get application => databaseFactory;
}