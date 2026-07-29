import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart';

class DictionaryArchiveExtractor {
  Future<void> extractSingleDatabase({
    required String archivePath,
    required String outputPath,
  }) async {
    final input = InputFileStream(archivePath);

    try {
      final archive = ZipDecoder().decodeStream(input);
      final databaseEntries = archive.files.where((entry) {
        return entry.isFile &&
            extension(entry.name).toLowerCase() == '.db';
      }).toList(growable: false);

      if (databaseEntries.isEmpty) {
        throw const FormatException(
          'Dictionary archive does not contain a .db file.',
        );
      }

      if (databaseEntries.length > 1) {
        final names = databaseEntries.map((entry) => entry.name).join(', ');
        throw FormatException(
          'Dictionary archive must contain exactly one .db file. '
          'Found ${databaseEntries.length}: $names',
        );
      }

      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);

      final output = OutputFileStream(outputPath);
      try {
        databaseEntries.single.writeContent(output);
      } finally {
        output.close();
      }
    } finally {
      input.close();
    }

    final extractedFile = File(outputPath);
    if (!await extractedFile.exists() || await extractedFile.length() == 0) {
      throw FileSystemException(
        'Extracted dictionary database is empty.',
        outputPath,
      );
    }
  }
}
