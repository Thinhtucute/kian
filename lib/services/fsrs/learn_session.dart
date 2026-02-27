import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/session_model.dart';
import '../../helpers/fsrs_helper.dart';
import '../../helpers/dictionary_helper.dart';
import 'dart:async';
import '../../helpers/logger.dart';

class LearnSessionService {
  
  // Load meanings and examples for the current card
  static Future<void> loadMeaningsAndExamples(BuildContext context) async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    if (session.cards.isEmpty) return;
    
    final entSeq = session.cards[session.currentCardIndex]['ent_seq'];
    final db = await DictionaryHelper.getDatabase();
    
    final meanings = await db.rawQuery("""
      SELECT s.id,
        GROUP_CONCAT(DISTINCT g.gloss) as definitions,
        GROUP_CONCAT(DISTINCT pos.pos) as part_of_speech
      FROM sense s
      JOIN gloss g ON s.id = g.sense_id
      LEFT JOIN part_of_speech pos ON s.id = pos.sense_id
      WHERE s.ent_seq = ?
      GROUP BY s.id
    """, [entSeq]);
    
    final examples = await db.rawQuery("""
      SELECT 
        s.id as sense_id,
        jpn.example_id as example_id,
        jpn.sentence as japanese_text,
        eng.sentence as english_translation
      FROM sense s
      JOIN example ex ON s.id = ex.sense_id
      JOIN example_sentence jpn ON ex.id = jpn.example_id AND jpn.lang = 'jpn'
      JOIN example_sentence eng ON eng.id = jpn.id + 1 AND eng.lang = 'eng'
      WHERE s.ent_seq = ?
      ORDER BY s.id
    """, [entSeq]);
    
    session.setMeanings(meanings);
    session.setExamples(examples);
  }

  // Load due cards and initialize session
  static Future<void> loadCards(BuildContext context, {bool forceReload = false}) async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    if (session.cards.isNotEmpty && !forceReload) return; // Don't reload if already loaded
    if (forceReload) session.loadCards([]);

    session.setLoading(true);

    try {
      final cards = await FSRSHelper.getDueCards();
      
      // Check if context is still mounted
      if (!context.mounted) return;
      
      session.loadCards(cards);
      session.setCurrentCardIndex(0);
      session.setLoading(false);
      session.setShowingAnswer(false);
      session.startTime = DateTime.now().millisecondsSinceEpoch;
      session.correctAnswers = 0;
      session.incorrectAnswers = 0;
      session.averageResponseTime = 0.0;
      session.responseTimes.clear();
      session.cardsReviewed = 0;
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
      await loadMeaningsAndExamples(context);
    } catch (e) {
      kLog('Error loading cards: $e');
      session.setLoading(false);
    }
  }

  // Show answer and load predicted intervals
  static Future<void> showAnswer(BuildContext context) async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    final card = session.cards[session.currentCardIndex];

    try {
      final intervals = await FSRSHelper.getPredictedIntervals(card['ent_seq']);
      
      // Check if context is still mounted
      if (!context.mounted) return;
      
      session.setPredictedIntervals(intervals);
      kLog('Predicted intervals for card ${card['ent_seq']}: ${session.predictedIntervals}');
    } catch (e) {
      kLog('Error getting intervals: $e');
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
    }

    session.setShowingAnswer(true);
  }

  // Process rating and move to next card
  static Future<void> processRating(
    BuildContext context, 
    bool isGood, 
    Timer? sessionTimer,
  ) async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    final now = DateTime.now().millisecondsSinceEpoch;
    final duration = now - session.startTime;

    session.responseTimes.add(duration);
    if (isGood) {
      session.correctAnswers++;
    } else {
      session.incorrectAnswers++;
    }
    session.averageResponseTime =
        session.responseTimes.reduce((a, b) => a + b) /
            session.responseTimes.length;

    try {
      final card = session.cards[session.currentCardIndex];
      kLog('Processing review for card ${card['ent_seq']}: ${isGood ? "Good" : "Again"}');
      kLog('Current predicted intervals: ${session.predictedIntervals}');

      await FSRSHelper.processReview(card['ent_seq'], isGood,
          reviewDuration: duration);

      // Check if context is still mounted
      if (!context.mounted) return;

      session.cardsReviewed++;
      await _nextCard(context, sessionTimer);
    } catch (e) {
      kLog('Error processing review: $e');
    }
  }

  // Move to next card or finish review
  static Future<void> _nextCard(BuildContext context, Timer? sessionTimer) async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    if (session.currentCardIndex < session.cards.length - 1) {
      kLog('Moving to next card: ${session.currentCardIndex + 1} -> ${session.currentCardIndex + 2}');
      session.setCurrentCardIndex(session.currentCardIndex + 1);
      session.setShowingAnswer(false);
      session.startTime = DateTime.now().millisecondsSinceEpoch;
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
      
      // Check if context is still mounted
      if (context.mounted) {
        await loadMeaningsAndExamples(context);
      }
    } else {
      kLog('Finished current card set, checking for more cards');
      await _finishReview(context, sessionTimer);
    }
  }

  // Finish review session and check for more cards
  static Future<void> _finishReview(BuildContext context, Timer? sessionTimer) async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    session.setLoading(true);

    try {
      final cards = await FSRSHelper.getDueCards();

      if (!context.mounted) return;
      
      if (cards.isEmpty) {
        sessionTimer?.cancel();
        session.loadCards([]);
        session.setLoading(false);
      } else {
        session.loadCards(cards);
        session.setCurrentCardIndex(0);
        session.setLoading(false);
        session.setShowingAnswer(false);
        session.startTime = DateTime.now().millisecondsSinceEpoch;
      }
    } catch (e) {
      kLog('Error checking for more cards: $e');
      session.setLoading(false);
      session.loadCards([]);

      sessionTimer?.cancel();
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Review Session Complete'),
              content: Text('You reviewed ${session.cardsReviewed} cards in ${_formatDuration(session.sessionDuration)}'),
              actions: <Widget>[
                TextButton(
                  child: Text('Close'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    }
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
