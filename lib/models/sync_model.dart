import '../services/cloud/sync_manager.dart';
import 'package:flutter/material.dart';

class SyncModel extends ChangeNotifier {
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  String _phase = '';
  String get phase => _phase;

  int _current = 0;
  int get current => _current;

  int _total = 0;
  int get total => _total;

  SyncResult? _lastResult;
  SyncResult? get lastResult => _lastResult;

  bool _cancelled = false;
  void cancelSync() {
    _cancelled = true;
  }

  @override
  void dispose() {
    cancelSync();
    super.dispose();
  }

  Future<void> performSync({
    VoidCallback? onComplete,
  }) async {
    if (_isSyncing) return;

    _isSyncing = true;
    _cancelled = false;
    _lastResult = null;
    _phase = 'Starting...';
    _current = 0;
    _total = 36;
    notifyListeners();

    try {
      _lastResult = await FSRSSyncManager.performSync(
        onProgress: (phase, current, total) {
          _phase = phase;
          _current = current;
          _total = total;
          notifyListeners();
        },
        shouldCancel: () => _cancelled,
      ).timeout(
        const Duration(minutes: 5),
        onTimeout: () => SyncResult(
          success: false,
          uploaded: 0,
          downloaded: 0,
          error: 'Sync timed out — check your connection',
        ),
      );
      if (_lastResult?.success == true && onComplete != null) {
        onComplete();
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}