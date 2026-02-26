import '../../helpers/fsrs_helper.dart';

class SyncResult {
  final bool success;
  final int uploaded;
  final int downloaded;
  final String? error;

  SyncResult({
    required this.success,
    required this.uploaded,
    required this.downloaded,
    this.error,
  });
}

class FSRSSyncManager {
  static Future<SyncResult> performSync({
    Function(String phase, int current, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    void updateProgress(String phase, int current, int total) {
      onProgress?.call(phase, current, total);
    }

    try {
      // Upload
      updateProgress('⬆️ Uploading', 0, 36);
      final uploadResult = await FSRSHelper.syncToSupabase(
        onProgress: (current, total) {
          updateProgress('⬆️ Uploading', current, total);
        },
        shouldCancel: shouldCancel,
      );
      if (shouldCancel != null && shouldCancel()) {
        throw Exception('Sync cancelled');
      }

      // Download
      updateProgress('⬇️ Downloading', 0, 36);
      final downloadResult = await FSRSHelper.syncFromSupabase(
        onProgress: (current, total) {
          updateProgress('⬇️ Downloading', current, total);
        },
        shouldCancel: shouldCancel,
      );
      if (shouldCancel != null && shouldCancel()) {
        throw Exception('Sync cancelled');
      }
      return SyncResult(
        success: uploadResult['success'] && downloadResult['success'],
        uploaded: uploadResult['synced'] ?? 0,
        downloaded: downloadResult['synced'] ?? 0,
        error: uploadResult['error'] ?? downloadResult['error'],
      );
    } catch (e) {
      return SyncResult(
        success: false,
        uploaded: 0,
        downloaded: 0,
        error: e.toString(),
      );
    }
  }
}