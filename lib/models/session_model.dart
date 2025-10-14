import 'package:flutter/material.dart';

class LearnSessionModel extends ChangeNotifier {
  List<Map<String, dynamic>> cards = [];
  int currentCardIndex = 0;
  int correctAnswers = 0;
  int incorrectAnswers = 0;
  double averageResponseTime = 0.0;
  final List<int> responseTimes = [];

  bool isLoading = false;
  bool showingAnswer = false;
  int startTime = 0;
  int sessionDuration = 0;
  int cardsReviewed = 0;
  Map<String, String> predictedIntervals = {
    'again': '10 mins',
    'good': 'unknown'
  };

  List<Map<String, dynamic>> meanings = [];
  List<Map<String, dynamic>> examples = [];

  void reset() {
    cards = [];
    currentCardIndex = 0;
    correctAnswers = 0;
    incorrectAnswers = 0;
    averageResponseTime = 0.0;
    responseTimes.clear();
    isLoading = false;
    showingAnswer = false;
    startTime = 0;
    sessionDuration = 0;
    cardsReviewed = 0;
    predictedIntervals = {
      'again': '10 mins',
      'good': 'unknown'
    };
    meanings = [];
    examples = [];
    notifyListeners();
  }

  void incrementSessionDuration() {
    sessionDuration++;
    notifyListeners();
  }

  // Delay notification until after build completes
  void setLoading(bool value) {
    if (isLoading != value) {
      isLoading = value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void setShowingAnswer(bool value) {
    if (showingAnswer != value) {
      showingAnswer = value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void loadCards(List<Map<String, dynamic>> newCards) {
    cards = newCards;
    currentCardIndex = 0;
    isLoading = false;
    notifyListeners();
  }

  void setCurrentCardIndex(int index) {
    if (currentCardIndex != index) {
      currentCardIndex = index;
      notifyListeners();
    }
  }

  void setMeanings(List<Map<String, dynamic>> newMeanings) {
    meanings = newMeanings;
    notifyListeners();
  }

  void setExamples(List<Map<String, dynamic>> newExamples) {
    examples = newExamples;
    notifyListeners();
  }

  void setPredictedIntervals(Map<String, String> intervals) {
    predictedIntervals = intervals;
    notifyListeners();
  }

  // Helper methods
  // Get current card
  Map<String, dynamic>? get currentCard {
    if (cards.isEmpty || currentCardIndex >= cards.length) return null;
    return cards[currentCardIndex];
  }

  // Check if there are more cards
  bool get hasMoreCards => currentCardIndex < cards.length - 1;

  // Move to next card
  void nextCard() {
    if (hasMoreCards) {
      setCurrentCardIndex(currentCardIndex + 1);
      setShowingAnswer(false);
    }
  }

  // Record answer
  void recordAnswer(bool isCorrect, int responseTimeMs) {
    if (isCorrect) {
      correctAnswers++;
    } else {
      incorrectAnswers++;
    }
    
    responseTimes.add(responseTimeMs);
    cardsReviewed++;
    
    // Calculate average response time
    if (responseTimes.isNotEmpty) {
      averageResponseTime = responseTimes.reduce((a, b) => a + b) / responseTimes.length;
    }
    
    notifyListeners();
  }
}