import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/card_widget.dart';
import '../widgets/session_stats.dart';
import '../services/cloud/sync_manager.dart';
import '../services/fsrs/export_service.dart';
import '../services/fsrs/learn_session.dart';
import 'package:provider/provider.dart';
import '../../models/session_model.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  LearnScreenState createState() => LearnScreenState();
}

class LearnScreenState extends State<LearnScreen> {
  Timer? _sessionTimer;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadCards();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
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

  Future<void> _performSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      await FSRSSyncManager.performSync(
        context: context,
        onComplete: () async {
          await _loadCards();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _exportData() async {
    await ExportService.exportDatabase(context);
  }

  Future<void> _onRatingPressed(bool isGood) async {
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
                icon: _isSyncing
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
                onPressed: _isSyncing ? null : _performSync,
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
    
    return Column(
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
                () => _onRatingPressed(false),
                session.predictedIntervals['again'] ?? '10 mins',
              ),
              _buildRatingButton(
                'Good',
                Colors.green[700]!,
                () => _onRatingPressed(true),
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