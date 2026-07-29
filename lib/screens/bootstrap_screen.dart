import 'package:flutter/material.dart';
import 'package:kian/app/app_init.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<BootstrapScreen> createState() =>
      _BootstrapScreenState();
}

class _BootstrapScreenState
    extends State<BootstrapScreen> {
  String _stage = 'Starting...';
  int _downloadedBytes = 0;
  int? _totalBytes;
  Object? _error;
  bool _ready = false;
  bool _initializing = false;

  double? get _downloadProgress {
    final total = _totalBytes;
    if (total == null || total <= 0 || _downloadedBytes <= 0) {
      return null;
    }

    return (_downloadedBytes / total).clamp(0.0, 1.0);
  }

  bool get _isDownloading => _downloadedBytes > 0 && !_ready;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    if (_initializing) return;

    setState(() {
      _initializing = true;
      _error = null;
      _ready = false;
      _stage = 'Starting...';
      _downloadedBytes = 0;
      _totalBytes = null;
    });

    try {
      await initialize(
        onStageChanged: (stage) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
          });
        },
        onDictionaryProgress: (downloadedBytes, totalBytes) {
          if (!mounted) return;
          setState(() {
            _stage = downloadedBytes == totalBytes && totalBytes != null
                ? 'Installing offline dictionary...'
                : 'Downloading offline dictionary...';
            _downloadedBytes = downloadedBytes;
            _totalBytes = totalBytes;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _ready = true;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF090C2B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _error == null ? _buildProgress() : _buildError(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final progress = _downloadProgress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Preparing Kian',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _stage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFB8C0E0),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 28),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 12),
        if (_isDownloading)
          Text(
            _formatDownloadProgress(),
            style: const TextStyle(
              color: Color(0xFFB8C0E0),
              fontSize: 14,
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Keep the app open.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF8992B8),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_off_rounded,
          size: 68,
          color: Color(0xFFFFB4AB),
        ),
        const SizedBox(height: 24),
        const Text(
          'Dictionary setup failed',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Check your internet connection and available storage, then retry.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFB8C0E0),
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _error.toString(),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8992B8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _initializing ? null : _startInitialization,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry setup'),
        ),
      ],
    );
  }

  String _formatDownloadProgress() {
    final downloaded = _formatBytes(_downloadedBytes);
    final total = _totalBytes;

    if (total == null || total <= 0) {
      return downloaded;
    }

    final percentage = ((_downloadedBytes / total) * 100).clamp(0, 100);
    return '$downloaded of ${_formatBytes(total)} '
        '(${percentage.toStringAsFixed(0)}%)';
  }

  String _formatBytes(int bytes) {
    const megabyte = 1024 * 1024;
    if (bytes >= megabyte) {
      return '${(bytes / megabyte).toStringAsFixed(1)} MB';
    }

    const kilobyte = 1024;
    if (bytes >= kilobyte) {
      return '${(bytes / kilobyte).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }
}
