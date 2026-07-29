import 'dart:io';

import 'package:kian/core/logger.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'extractor.dart';
import 'download_progress.dart';
import 'downloader.dart';
import 'validator.dart';

class DictionaryInstaller {
  DictionaryInstaller({
    DictionaryDownloader? downloader,
    DictionaryArchiveExtractor? extractor,
    DictionaryValidator? validator,
  })  : _downloader = downloader ?? DictionaryDownloader(),
        _extractor = extractor ?? DictionaryArchiveExtractor(),
        _validator = validator ?? DictionaryValidator();

  static const String databaseFileName = 'dictionary.db';
  static const String archiveFileName = 'dict_jp_cn.zip';
  static final Uri downloadUri = Uri.parse(
    'https://github.com/Thinhtucute/kian/releases/'
    'download/dict-v1/dict_jp_cn.zip',
  );

  final DictionaryDownloader _downloader;
  final DictionaryArchiveExtractor _extractor;
  final DictionaryValidator _validator;

  Future<String>? _installationFuture;

  Future<String> ensureInstalled({
    DictionaryDownloadProgress? onProgress,
  }) {
    return _installationFuture ??= _ensureInstalledInternal(
      onProgress: onProgress,
    ).whenComplete(() {
      _installationFuture = null;
    });
  }

  Future<String> _ensureInstalledInternal({
    DictionaryDownloadProgress? onProgress,
  }) async {
    final databasePath = await getDatabasePath();
    final databaseFile = File(databasePath);

    if (await _validator.isValid(databaseFile)) {
      return databasePath;
    }

    await _install(onProgress: onProgress);
    await _validator.validateOrThrow(databaseFile);
    return databasePath;
  }

  Future<void> _install({
    DictionaryDownloadProgress? onProgress,
  }) async {
    final databasePath = await getDatabasePath();
    final directory = dirname(databasePath);
    final archivePath = join(directory, archiveFileName);
    final partialArchivePath = '$archivePath.download';
    final temporaryDatabasePath = '$databasePath.installing';

    final databaseFile = File(databasePath);
    final archiveFile = File(archivePath);
    final partialArchiveFile = File(partialArchivePath);
    final temporaryDatabaseFile = File(temporaryDatabasePath);

    await Directory(directory).create(recursive: true);
    await _deleteIfExists(partialArchiveFile);
    await _deleteIfExists(archiveFile);
    await _deleteIfExists(temporaryDatabaseFile);

    try {
      kLog('Downloading dictionary from $downloadUri');
      await _downloader.download(
        uri: downloadUri,
        destination: partialArchiveFile,
        onProgress: onProgress,
      );

      await partialArchiveFile.rename(archivePath);

      kLog('Extracting dictionary archive');
      await _extractor.extractSingleDatabase(
        archivePath: archivePath,
        outputPath: temporaryDatabasePath,
      );

      await _validator.validateOrThrow(temporaryDatabaseFile);

      await _deleteIfExists(databaseFile);
      await temporaryDatabaseFile.rename(databasePath);

      kLog('Dictionary installed at $databasePath');
    } catch (error) {
      kLog('Dictionary installation failed: $error');
      await _deleteIfExists(partialArchiveFile);
      await _deleteIfExists(temporaryDatabaseFile);
      rethrow;
    } finally {
      await _deleteIfExists(archiveFile);
    }
  }

  Future<String> getDatabasePath() async {
    return join(await getDatabasesPath(), databaseFileName);
  }

  Future<void> deleteInstallation() async {
    final databasePath = await getDatabasePath();
    final archivePath = join(dirname(databasePath), archiveFileName);

    await _deleteIfExists(File(databasePath));
    await _deleteIfExists(File('$databasePath.installing'));
    await _deleteIfExists(File(archivePath));
    await _deleteIfExists(File('$archivePath.download'));
  }

  void close() {
    _downloader.close();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
