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

  void setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void setShowingAnswer(bool value) {
    showingAnswer = value;
    notifyListeners();
  }

  void setCards(List<Map<String, dynamic>> newCards) {
    cards = newCards;
    notifyListeners();
  }

  void setCurrentCardIndex(int index) {
    currentCardIndex = index;
    notifyListeners();
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
}