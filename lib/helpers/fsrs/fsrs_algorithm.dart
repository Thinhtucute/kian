import 'dart:math';
import 'package:flutter/foundation.dart';

class FSRSAlgorithm {
  // Official FSRS weights
  static const double w0 = 0.5546; // Initial difficulty
  static const double w1 = -0.0235;
  static const double w2 = 1.4444;
  static const double w3 = 0.1963;
  static const double w4 = 2.1451; // Stability reset on lapse
  static const double w5 = -0.3772; // Again stability update
  static const double w12 = 0.1056; // Recall-based stability update
  static const double w13 = 0.1044; // Good stability update

  // Sigmoid helper
  static double sigmoid(double x) => 1 / (1 + exp(-x));

  // Initial Difficulty (d)
  static double initialDifficulty({
    required int rating, // 1=Again, 3=Good
    double? logDaysSinceLastReview,
    double? lastDifficulty,
  }) {
    final logDays = logDaysSinceLastReview ?? 0.0;
    final lastDiff = lastDifficulty ?? 0.0;
    final x = w0 + w1 * rating + w2 * logDays + w3 * lastDiff;
    return (1 + 9 * sigmoid(x)).clamp(1.0, 10.0);
  }

  // Initial Stability (s)
  static double initialStability(int rating) {
    return exp(w2 + w3 * rating);
  }

  // Retrievability: R = exp(-(t/θ)^d)
  static double calculateRetrievability(
      double elapsedMinutes, double stabilityMinutes, double difficulty) {
    return exp(-pow(elapsedMinutes / stabilityMinutes, difficulty));
  }

  // Again stability update
  static double updateStabilityAgain(
    double difficulty, {
    int reps = 0,
    int lapses = 0,
  }) {
    // More reps = higher stability, more lapses = lower stability
    double historyFactor = 1.0 - 0.03 * lapses + 0.01 * reps;
    historyFactor = historyFactor.clamp(0.7, 1.2); // Prevent extreme values
    return w4 * exp(w5 * (difficulty - 1)) * historyFactor;
  }

  // Good tability update
  static double updateStabilityGood(
    double stability,
    double retrievability, {
    int reps = 0,
    int lapses = 0,
  }) {
    final factor = w12 * (exp((1 - retrievability) * w13) - 1);
    // More reps = higher stability, more lapses = lower stability
    double historyFactor = 1.0 + 0.01 * reps - 0.02 * lapses;
    historyFactor = historyFactor.clamp(0.7, 1.3); // Prevent extreme values
    return stability * (1 + factor) * historyFactor;
  }

  // Difficulty update
  static double updateDifficulty(
    double difficulty,
    bool recalled, // "Good": true, "Again": false
    int rating, // 1=Again, 3=Good
    double retrievability,
    int reps,
    int lapses,
  ) {
    double dNext = difficulty;
    if (recalled) {
      dNext =
          difficulty + 0.1 * (difficulty - 1); // Increase slightly on success
    } else {
      dNext = difficulty - 0.2; // Decrease on lapse
    }
    dNext += 0.05 * (1 - retrievability); // Penalty if hard
    dNext -= 0.01 * lapses; // More lapses = slightly easier
    dNext += 0.01 * reps; // More reps = slightly harder
    return dNext.clamp(1.0, 10.0);
  }

  // Calculate next review interval in minutes
  static double calculateInterval(
      double stabilityMinutes, double targetRetention) {
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

  // Predicted intervals helper
  static Map<String, String> getPredictedIntervals(
    double stability,
    double difficulty,
    double retrievability,
    double targetRetention, {
    int reps = 0,
    int lapses = 0,
  }) {
    // "Again"
    double againStability =
        updateStabilityAgain(difficulty, reps: reps, lapses: lapses);
    double againInterval = calculateInterval(againStability, targetRetention);
    final againFormatted = formatInterval(againInterval);

    // "Good"
    double goodStability = updateStabilityGood(
      max(stability, 2880.0),
      retrievability,
      reps: reps,
      lapses: lapses,
    );
    double goodInterval = calculateInterval(goodStability, targetRetention);
    final actualGoodInterval =
        max(goodInterval, max(againInterval * 2, 2880.0));
    final goodFormatted = formatInterval(actualGoodInterval);

    debugPrint(
        'Intervals - again: $againInterval min, good: $actualGoodInterval min');
    return {'again': againFormatted, 'good': goodFormatted};
  }
}
