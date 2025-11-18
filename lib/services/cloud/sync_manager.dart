import 'package:flutter/material.dart';
import '../../helpers/fsrs_helper.dart';

class FSRSSyncManager {
  
  static Future<void> performSync({
    required BuildContext context,
    VoidCallback? onComplete,
  }) async {
    await performSyncWithProgress(
      context: context,
      onComplete: onComplete,
    );
  }

  static Future<void> performSyncWithProgress({
    required BuildContext context,
    Function(int synced, int total)? onProgress,
    VoidCallback? onComplete,
  }) async {
    ScaffoldMessengerState? scaffoldMessenger;
    if (context.mounted) {
      scaffoldMessenger = ScaffoldMessenger.of(context);
    }

    final progressNotifier = ValueNotifier<Map<String, dynamic>>({
      'phase': '🔄 Preparing',
      'current': 0,
      'total': 1,
      'percentage': 0,
    });

    if (context.mounted && scaffoldMessenger != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: progressNotifier,
            builder: (context, progress, child) {
              return Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress['total'] > 0 ? progress['current'] / progress['total'] : null,
                      backgroundColor: Colors.white30,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('${progress['phase']}: ${progress['current']}/${progress['total']} (${progress['percentage']}%)'),
                  ),
                ],
              );
            },
          ),
          duration: Duration(hours: 999),
          backgroundColor: Colors.blue[700],
        ),
      );
    }

    void updateProgress(String phase, int current, int total) {
      if (!context.mounted) return;
      
      final percentage = total > 0 ? (current * 100 / total).toInt() : 0;
      progressNotifier.value = {
        'phase': phase,
        'current': current,
        'total': total,
        'percentage': percentage,
      };
      
      onProgress?.call(current, total);
    }

    try {
      // Upload with progress tracking
      updateProgress('⬆️ Uploading', 0, 1);
      final uploadResult = await FSRSHelper.syncToSupabase(
        onProgress: (current, total) {
          updateProgress('⬆️ Uploading', current, total);
        },
      );

      // Download with progress tracking
      updateProgress('⬇️ Downloading', 0, 1);
      final downloadResult = await FSRSHelper.syncFromSupabase(
        onProgress: (current, total) {
          updateProgress('⬇️ Downloading', current, total);
        },
      );

      if (!context.mounted) {
        progressNotifier.dispose();
        return;
      }
      
      // Hide snackbar and wait for animation to complete
      scaffoldMessenger?.hideCurrentSnackBar();
      await Future.delayed(Duration(milliseconds: 500));
      progressNotifier.dispose();

      if (!context.mounted) return;

      if (uploadResult['success'] && downloadResult['success']) {
        final uploaded = uploadResult['synced'] ?? 0;
        final downloaded = downloadResult['synced'] ?? 0;

        String message = '✅ Sync complete';
        if (uploaded > 0 || downloaded > 0) {
          message += ' (↑$uploaded ↓$downloaded)';
        }

        scaffoldMessenger?.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        if (downloaded > 0 && onComplete != null) {
          onComplete();
        }
      } else {
        final error = uploadResult['error'] ?? downloadResult['error'] ?? 'Unknown error';
                
        scaffoldMessenger?.showSnackBar(
          SnackBar(
            content: Text('❌ Sync failed: $error'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) {
        progressNotifier.dispose();
        return;
      }
      
      // Hide snackbar and wait for animation to complete
      scaffoldMessenger?.hideCurrentSnackBar();
      await Future.delayed(Duration(milliseconds: 500));
      progressNotifier.dispose();

      if (!context.mounted) return;
      
      scaffoldMessenger?.showSnackBar(
        SnackBar(
          content: Text('❌ Sync error: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
}