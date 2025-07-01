import 'dart:math';
import 'package:flutter/foundation.dart';

class FSRSAlgorithm {
  // Calculate memory retrievability
  static double calculateRetrievability(double elapsedMinutes, double stabilityMinutes) {
    return exp(-elapsedMinutes / stabilityMinutes);
  }

  // Update difficulty based on recall success
  static double updateDifficulty(double difficulty, bool recalled, double w) {
    final delta = recalled ? (1.0 - difficulty) : -difficulty;
    final newDifficulty = difficulty + w * delta;
    return newDifficulty.clamp(0.1, 1.0);
  }

  // Update stability based on performance
  static double updateStability(double stabilityMinutes, double difficulty, double retrievability) {
    final a = 0.5 / difficulty;
    return stabilityMinutes * (1.0 + a * (1.0 - retrievability));
  }

  // Calculate next review interval
  static double calculateInterval(double stabilityMinutes, double targetRetention) {
    final exactInterval = -stabilityMinutes * log(targetRetention);
    final randomFactor = 0.95 + (0.1 * DateTime.now().millisecond / 1000);
    return max(10.0, exactInterval * randomFactor);
  }

  // Format interval for display
  static String formatInterval(double minutes) {
    if (minutes < 60) {
      return '${minutes.round()} min';
    } else if (minutes < 1440) {
      return '${(minutes / 60).round()} hr';
    } else if (minutes < 43200) {
      return '${(minutes / 1440).round()} days';
    } else {
      return '${(minutes / 43200).round()} months';
    }
  }

  // Calculate predicted intervals for UI
  static Future<Map<String, String>> getPredictedIntervals(Map<String, dynamic> card, Map<String, dynamic> config) async {
    final stability = (card['stability'] as num).toDouble();
    final difficulty = (card['difficulty'] as num).toDouble();
    final targetRetention = (config['target_retention'] as num).toDouble();

    // Predict "Again" interval
    final againInterval = difficulty * 30.0;
    final againFormatted = formatInterval(againInterval);

    // Predict "Good" interval
    final retrievability = 0.9;
    final w = (config['w'] as num).toDouble();
    final newStability = updateStability(max(stability, 2880.0), difficulty, retrievability);
    double goodInterval = calculateInterval(newStability, targetRetention);
    
    final actualGoodInterval = max(goodInterval, max(againInterval * 2, 2880.0));
    final goodFormatted = formatInterval(actualGoodInterval);

    debugPrint('Intervals - again: $againInterval min, good: $actualGoodInterval min');
    return {'again': againFormatted, 'good': goodFormatted};
  }
}