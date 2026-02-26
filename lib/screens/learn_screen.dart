import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../widgets/card_widget.dart';
import '../widgets/session_stats.dart';
import '../services/cloud/auth_service.dart';
import '../services/fsrs/export_service.dart';
import '../services/fsrs/learn_session.dart';
import 'package:provider/provider.dart';
import '../models/session_model.dart';
import '../models/sync_model.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  LearnScreenState createState() => LearnScreenState();
}

class LearnScreenState extends State<LearnScreen> {
  Timer? _sessionTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadCards();
    _startTimer();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _sessionTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      final session = Provider.of<LearnSessionModel>(context, listen: false);
      session.incrementSessionDuration();
    });
  }

  Future<void> _loadCards() async {
    await LearnSessionService.loadCards(context);
  }

  Future<void> _exportData() async {
    await ExportService.exportDatabase(context);
  }

  Future<void> _performSync() async {
    final syncModel = context.read<SyncModel>();
    await syncModel.performSync(onComplete: _loadCards);

    if (!mounted) return;
    final result = syncModel.lastResult;
    if (result?.success == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync successful'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (result != null && result.error != null && !result.error!.contains('cancelled')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AuthService.signOut();
        // Navigation will be handled by auth state listener
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logout failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _onGoodPressed(bool isGood) async {
    await LearnSessionService.processRating(context, isGood, _sessionTimer);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  double _calculateAccuracy(LearnSessionModel session) {
    final total = session.correctAnswers + session.incorrectAnswers;
    if (total == 0) return 0.0;
    return ((session.correctAnswers / total) * 100).roundToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LearnSessionModel>(
      builder: (context, session, child) {
        return Scaffold(
          backgroundColor: const Color.fromARGB(255, 16, 20, 63),
          appBar: AppBar(
            title: Text('Review', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color.fromARGB(255, 9, 12, 43),
            iconTheme: IconThemeData(color: Colors.white),
            actions: [
              // Statistics button
              if (session.cardsReviewed > 0)
                SessionStatsPopup(
                  session: session,
                  formatDuration: _formatDuration,
                  calculateAccuracy: _calculateAccuracy,
                ),

              // Sync button
              IconButton(
                icon: context.watch<SyncModel>().isSyncing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.sync, color: Colors.white),
                tooltip: 'Sync',
                onPressed: _performSync,
              ),

              // Session timer
              Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Text(
                    _formatDuration(session.sessionDuration),
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),

              // Export button
              IconButton(
                icon: Icon(Icons.upload_file),
                tooltip: 'Export',
                onPressed: _exportData,
              ),

              // Profile/Logout button
              PopupMenuButton<String>(
                icon: Icon(Icons.account_circle, color: Colors.white),
                onSelected: (value) {
                  if (value == 'logout') {
                    _handleLogout();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      AuthService.currentUser?.email ?? 'User',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 20),
                        SizedBox(width: 8),
                        Text('Logout'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: session.isLoading
              ? Center(child: CircularProgressIndicator())
              : session.cards.isEmpty
                  ? _buildNoCardsView()
                  : _buildReviewArea(session),
        );
      },
    );
  }

  Widget _buildNoCardsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green,
          ),
          SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'No cards due for review right now',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewArea(LearnSessionModel session) {
    final currentCard = session.cards[session.currentCardIndex];

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (!session.showingAnswer && (
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter
          )) {
            LearnSessionService.showAnswer(context);
          }
          else if (session.showingAnswer && (
              event.logicalKey == LogicalKeyboardKey.digit2 ||
              event.logicalKey == LogicalKeyboardKey.numpad2 ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter
          )) {
            _onGoodPressed(true);
          }
          else if (session.showingAnswer && (
              event.logicalKey == LogicalKeyboardKey.digit1 ||
              event.logicalKey == LogicalKeyboardKey.numpad1
          )) {
            _onGoodPressed(false);
          }
        }
      },
      child: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (session.currentCardIndex + 1) / session.cards.length,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '${session.currentCardIndex + 1} / ${session.cards.length}',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),

          // Review card
          Expanded(
            child: ReviewCardWidget(
              card: currentCard,
              meanings: session.meanings,
              examples: session.examples,
              showAnswer: session.showingAnswer,
              onShowAnswer: () => LearnSessionService.showAnswer(context),
            ),
          ),

          // Rating buttons
          if (session.showingAnswer) _buildRatingButtons(session),
          if (!session.showingAnswer) SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildRatingButtons(LearnSessionModel session) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildRatingButton(
                'Again',
                Colors.red[700]!,
                () => _onGoodPressed(false),
                session.predictedIntervals['again'] ?? '10 mins',
              ),
              _buildRatingButton(
                'Good',
                Colors.green[700]!,
                () => _onGoodPressed(true),
                session.predictedIntervals['good'] ?? 'unknown',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingButton(
      String label, Color color, VoidCallback onPressed, String timeInterval) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        minimumSize: Size(120, 72),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          SizedBox(height: 4),
          Text(
            timeInterval,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}