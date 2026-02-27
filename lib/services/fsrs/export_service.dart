import 'package:flutter/material.dart';
import 'dart:io';

class ExportService {
  
  /// Export database to Downloads folder
  static Future<void> exportDatabase(BuildContext context) async {
    const dbPath = '/data/data/com.example.kian/app_flutter/fsrs.db';
    final exportDir = Directory('/storage/emulated/0/Download/');
    final exportPath = '${exportDir.path}/cards.db';

    try {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.copy(exportPath);
        
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database exported to $exportPath'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database file not found'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
