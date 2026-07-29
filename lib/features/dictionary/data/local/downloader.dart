import 'dart:io';

import 'download_progress.dart';

class DictionaryDownloader {
  DictionaryDownloader({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<void> download({
    required Uri uri,
    required File destination,
    DictionaryDownloadProgress? onProgress,
  }) async {
    await destination.parent.create(recursive: true);

    final request = await _client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Kian-Dictionary-Installer',
    );

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Dictionary download failed with HTTP '
        '${response.statusCode}'
        '${response.reasonPhrase.isEmpty ? '' : ' ${response.reasonPhrase}'}',
        uri: uri,
      );
    }

    final totalBytes =
        response.contentLength >= 0 ? response.contentLength : null;
    var downloadedBytes = 0;
    final sink = destination.openWrite();

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        onProgress?.call(downloadedBytes, totalBytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (totalBytes != null && downloadedBytes != totalBytes) {
      throw FileSystemException(
        'Incomplete dictionary download. Expected $totalBytes bytes, '
        'received $downloadedBytes bytes.',
        destination.path,
      );
    }

    if (!await destination.exists() || await destination.length() == 0) {
      throw FileSystemException(
        'Downloaded dictionary archive is empty.',
        destination.path,
      );
    }
  }

  void close() {
    _client.close(force: true);
  }
}
