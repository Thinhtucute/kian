import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class FSRSAlgorithm {
  // v6.1.1 weights
  static const double w0 = 0.212; // Initial stability for Again
  static const double w1 = 1.2931; // Initial stability for Hard
  static const double w2 = 2.3065; // Initial stability for Good
  static const double w3 = 8.2956; // Initial stability for Easy
  static const double w4 = 6.4133; // Initial difficulty base
  static const double w5 = 0.8334; // Initial difficulty modifier
  static const double w6 = 3.0194; // Difficulty decay
  static const double w7 = 0.001; // Difficulty change per grade
  static const double w8 = 1.8722; // Stability increase base
  static const double w9 = 0.1666; // Grade effect on stability
  static const double w10 = 0.796; // Difficulty effect on stability
  static const double w11 = 1.4835; // Stability effect on stability
  static const double w12 = 0.0614; // Retrievability effect on stability
  static const double w13 = 0.2629; // Post-lapse stability base
  static const double w14 = 1.6483; // Post-lapse difficulty exponent
  static const double w15 = 0.6014; // Post-lapse stability exponent
  static const double w16 = 1.8729; // Post-lapse retrievability effect
  static const double w17 = 0.5425; // Short-term stability base
  static const double w18 = 0.0912; // Short-term stability modifier
  static const double w19 = 0.0658; // Short-term stability decay
  static const double w20 = 0.1542; // Forgetting curve decay

  static const double defaultRetention = 0.9;
  static const int defaultMaxInterval = 365;
  static double get factor => pow(0.9, 1 / -w20) - 1;

  // Instance variables
  final double requestRetention;
  final int maximumInterval;
  final bool enableFuzz;

  // Constructor
  FSRSAlgorithm({
    this.requestRetention = defaultRetention,
    this.maximumInterval = defaultMaxInterval,
    this.enableFuzz = true,
  }) {
    assert(requestRetention > 0 && requestRetention < 1);
  }

  /// Forgetting curve formula
  static double forgettingCurve(double elapsedDays, double stability) {
    return pow(1 + factor * elapsedDays / stability, -w20).toDouble();
  }

  /// Calculate next interval using official FSRS formula
  static double calculateNextInterval(
      double stability, double requestRetention) {
    double newInterval =
        stability / factor * (pow(requestRetention, 1 / -w20) - 1);
    return newInterval.clamp(1.0, defaultMaxInterval.toDouble());
  }

  /// Apply fuzz to interval (official FSRS implementation)
  static double applyFuzz(double interval, bool enableFuzz, int entryId) {
    if (!enableFuzz || interval < 2.5) return interval;

    interval = interval.roundToDouble();
    final bytes = sha256.convert(utf8.encode(entryId.toString())).bytes;
    final v = bytes[0] % 11;
    final multiplier = 0.95 + v * 0.01;
    return interval * multiplier;
  }

  /// Constrain difficulty to 1-10 range (official FSRS)
  static double constrainDifficulty(double difficulty) {
    return difficulty.clamp(1.0, 10.0);
  }

  /// Initialize difficulty for a rating (official FSRS)
  static double initDifficulty(String rating) {
    int ratingValue = _getRatingValue(rating);
    double difficulty = w4 - exp(w5 * (ratingValue - 1)) + 1;
    return constrainDifficulty(difficulty);
  }

  /// Initialize stability for a rating (official FSRS)
  static double initStability(String rating) {
    int ratingValue = _getRatingValue(rating);
    double stability = _getWeightForRating(ratingValue);
    return max(stability, 0.1);
  }

  /// Get weight for rating (w0 for Again, w1 for Hard, etc.)
  static double _getWeightForRating(int rating) {
    switch (rating) {
      case 1:
        return w0; // Again
      case 2:
        return w1; // Hard
      case 3:
        return w2; // Good
      case 4:
        return w3; // Easy
      default:
        return w2; // Default to Good
    }
  }

  /// Convert rating string to integer value
  static int _getRatingValue(String rating) {
    switch (rating.toLowerCase()) {
      case 'again':
        return 1;
      case 'hard':
        return 2;
      case 'good':
        return 3;
      case 'easy':
        return 4;
      default:
        return 3; // Default to Good
    }
  }

  /// Calculate next difficulty (official FSRS)
  static double nextDifficulty(double currentDifficulty, String rating) {
    int ratingValue = _getRatingValue(rating);
    double deltaD = -w6 * (ratingValue - 3);
    double nextD =
        currentDifficulty + _linearDamping(deltaD, currentDifficulty);
    return constrainDifficulty(_meanReversion(initDifficulty("easy"), nextD));
  }

  /// Linear damping for difficulty changes (official FSRS)
  static double _linearDamping(double deltaD, double oldD) {
    return deltaD * (10 - oldD) / 9;
  }

  /// Mean reversion for difficulty (official FSRS)
  static double _meanReversion(double init, double current) {
    return w7 * init + (1 - w7) * current;
  }

  /// Calculate next recall stability for successful reviews (official FSRS)
  static double nextRecallStability(double difficulty, double stability,
      double retrievability, String rating) {
    double hardPenalty = rating.toLowerCase() == 'hard' ? w15 : 1;
    double easyBonus = rating.toLowerCase() == 'easy' ? w16 : 1;

    double stabilityInc = exp(w8) *
        (11 - difficulty) *
        pow(stability, -w9) *
        (exp((1 - retrievability) * w10) - 1) *
        hardPenalty *
        easyBonus;

    return (stability * (1 + stabilityInc)).clamp(0.1, double.infinity);
  }

  /// Calculate next forget stability for failed reviews (official FSRS)
  static double nextForgetStability(
      double difficulty, double stability, double retrievability) {
    double sMin = stability / exp(w17 * w18);

    double newStability = w11 *
        pow(difficulty, -w12) *
        (pow(stability + 1, w13) - 1) *
        exp((1 - retrievability) * w14);

    return min(newStability, sMin).clamp(0.1, double.infinity);
  }

  /// Calculate next short-term stability for learning cards (official FSRS)
  static double nextShortTermStability(double stability, String rating) {
    int ratingValue = _getRatingValue(rating);
    double sinc = exp(w17 * (ratingValue - 3 + w18)) * pow(stability, -w19);

    if (ratingValue >= 3) {
      sinc = max(sinc, 1);
    }

    return (stability * sinc).clamp(0.1, double.infinity);
  }

  /// Process a review and return updated card state
  Map<String, dynamic> processReview({
    required int entryId,
    required String rating, // 'again', 'hard', 'good', 'easy'
    required double currentStability,
    required double currentDifficulty,
    required double elapsedDays,
    required bool isNewCard,
    required bool isLearningCard,
  }) {
    double newStability, newDifficulty;

    if (isNewCard) {
      // First review - use initial formulas
      newStability = initStability(rating);
      newDifficulty = initDifficulty(rating);
    } else if (isLearningCard) {
      // Learning card - use short-term stability
      newStability = nextShortTermStability(currentStability, rating);
      newDifficulty = nextDifficulty(currentDifficulty, rating);
    } else {
      // Review card - calculate retrievability and update
      double retrievability = forgettingCurve(elapsedDays, currentStability);
      newDifficulty = nextDifficulty(currentDifficulty, rating);

      if (rating.toLowerCase() == 'again') {
        // Failed review
        newStability = nextForgetStability(
            currentDifficulty, currentStability, retrievability);
      } else {
        // Successful review
        newStability = nextRecallStability(
            currentDifficulty, currentStability, retrievability, rating);
      }
    }

    // Calculate next review interval
    double nextInterval = calculateNextInterval(newStability, requestRetention);
    nextInterval = applyFuzz(nextInterval, enableFuzz, entryId);

    // For "Again" responses, always use 10 minutes
    if (rating.toLowerCase() == 'again') {
      nextInterval = 10.0 / (60 * 24); // 10 minutes in days
    }

    // Calculate current retrievability for reference
    double currentRetrievability = isNewCard || isLearningCard
        ? 1.0
        : forgettingCurve(elapsedDays, currentStability);

    debugPrint(
        'FSRS Review: Rating=$rating, S=${newStability.toStringAsFixed(2)}, '
        'D=${newDifficulty.toStringAsFixed(2)}, R=${currentRetrievability.toStringAsFixed(3)}, '
        'Interval=${formatInterval(nextInterval)}');

    return {
      'stability': newStability,
      'difficulty': newDifficulty,
      'interval': nextInterval,
      'retrievability': currentRetrievability,
    };
  }

  /// Preview what intervals would result from each choice
  Map<String, String> previewIntervals({
    required int entryId,
    required double currentStability,
    required double currentDifficulty,
    required double elapsedDays,
    required bool isNewCard,
    required bool isLearningCard,
  }) {
    final Map<String, String> previews = {};

    // For each rating, simulate the review
    final ratings = ['again', 'hard', 'good', 'easy'];

    for (String rating in ratings) {
      final result = processReview(
        entryId: entryId,
        rating: rating,
        currentStability: currentStability,
        currentDifficulty: currentDifficulty,
        elapsedDays: elapsedDays,
        isNewCard: isNewCard,
        isLearningCard: isLearningCard,
      );

      double interval = result['interval'];
      previews[rating] = formatInterval(interval);
    }

    return previews;
  }

  /// Format interval into human-readable string
  static String formatInterval(double days) {
    if (days < 1) {
      return '${(days * 24 * 60).toStringAsFixed(0)} mins';
    } else if (days < 30) {
      return '${days.toStringAsFixed(1)} days';
    } else if (days < 365) {
      double months = days / 30;
      return '${months.toStringAsFixed(1)} months';
    } else {
      double years = days / 365;
      return '${years.toStringAsFixed(1)} years';
    }
  }
}
