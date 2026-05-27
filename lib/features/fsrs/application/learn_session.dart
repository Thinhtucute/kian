import 'package:kian/models/session_model.dart';
import 'package:kian/features/fsrs/domain/fsrs_helper.dart';
import 'package:kian/features/dictionary/data/repositories/dictionary_repository.dart';
import 'dart:async';
import 'package:kian/core/logger.dart';

class LearnSessionService {

  // Load meanings and examples for the current card.
  static Future<void> loadMeaningsAndExamples(
    LearnSessionModel session, {
    String languageTag = 'jp',
  }) async {
    if (session.cards.isEmpty) return;

    final entryId = session.cards[session.currentCardIndex]['entry_id'] as int;

    final meanings = await DictionaryRepository.getMeanings(
      entryId,
      languageTag: languageTag,
    );
    final examples = await DictionaryRepository.getExamples(
      entryId,
      languageTag: languageTag,
    );

    session.setMeanings(meanings);
    session.setExamples(examples);
  }

  // Load due cards and initialize session.
  static Future<void> loadCards(
    LearnSessionModel session, {
    bool forceReload = false,
    String languageTag = 'jp',
  }) async {
    if (session.cards.isNotEmpty && !forceReload) return;
    if (forceReload) session.loadCards([]);

    session.setLoading(true);

    try {
      final cards = await FSRSHelper.getDueCards();

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
      await loadMeaningsAndExamples(session, languageTag: languageTag);
    } catch (e) {
      kLog('Error loading cards: $e');
      session.setLoading(false);
    }
  }

  // Show answer and load predicted intervals.
  static Future<void> showAnswer(
    LearnSessionModel session, {
    String languageTag = 'jp',
  }) async {
    final card = session.cards[session.currentCardIndex];
    final entryId = card['entry_id'] as int;

    try {
      final intervals = await FSRSHelper.getPredictedIntervals(entryId);
      session.setPredictedIntervals(intervals);
      kLog('Predicted intervals for card $entryId: ${session.predictedIntervals}');
    } catch (e) {
      kLog('Error getting intervals: $e');
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
    }

    session.setShowingAnswer(true);
  }

  // Process rating and move to next card.
  // [onSessionComplete] is called by the screen to show the completion dialog 

  static Future<void> processRating(
    LearnSessionModel session,
    bool isGood,
    Timer? sessionTimer, {
    void Function()? onSessionComplete,
    String languageTag = 'jp',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final duration = now - session.startTime;

    session.recordAnswer(isGood, duration);

    try {
      final card = session.cards[session.currentCardIndex];
      final entryId = card['entry_id'] as int;
      kLog('Processing review for card $entryId: ${isGood ? "Good" : "Again"}');

      await FSRSHelper.processReview(entryId, isGood, reviewDuration: duration);

      session.cardsReviewed++;
      await _nextCard(
        session,
        sessionTimer,
        onSessionComplete: onSessionComplete,
        languageTag: languageTag,
      );
    } catch (e) {
      kLog('Error processing review: $e');
    }
  }

  static Future<void> _nextCard(
    LearnSessionModel session,
    Timer? sessionTimer, {
    void Function()? onSessionComplete,
    String languageTag = 'jp',
  }) async {
    if (session.currentCardIndex < session.cards.length - 1) {
      kLog('Moving to next card: ${session.currentCardIndex + 1} -> ${session.currentCardIndex + 2}');
      session.setCurrentCardIndex(session.currentCardIndex + 1);
      session.setShowingAnswer(false);
      session.startTime = DateTime.now().millisecondsSinceEpoch;
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
      await loadMeaningsAndExamples(session, languageTag: languageTag);
    } else {
      kLog('Finished current card set, checking for more cards');
      await _finishReview(
        session,
        sessionTimer,
        onSessionComplete: onSessionComplete,
        languageTag: languageTag,
      );
    }
  }

  static Future<void> _finishReview(
    LearnSessionModel session,
    Timer? sessionTimer, {
    void Function()? onSessionComplete,
    String languageTag = 'jp',
  }) async {
    session.setLoading(true);

    try {
      final cards = await FSRSHelper.getDueCards();

      if (cards.isEmpty) {
        sessionTimer?.cancel();
        session.loadCards([]);
        session.setLoading(false);
        onSessionComplete?.call();
      } else {
        session.loadCards(cards);
        session.setCurrentCardIndex(0);
        session.setLoading(false);
        session.setShowingAnswer(false);
        session.startTime = DateTime.now().millisecondsSinceEpoch;
        await loadMeaningsAndExamples(session, languageTag: languageTag);
      }
    } catch (e) {
      kLog('Error checking for more cards: $e');
      session.setLoading(false);
      session.loadCards([]);
      sessionTimer?.cancel();
      onSessionComplete?.call();
    }
  }
}
