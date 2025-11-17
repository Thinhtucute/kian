import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class FSRSAlgorithm {
  // Weights 
  // Initial stability for Again
  static const double w0 = 0.212;    // 0.1747
  // Initial stability for Hard
  static const double w1 = 1.2931;   // 0.4583
  // Initial stability for Good
  static const double w2 = 2.3065;   // 0.4583
  // Initial stability for Easy
  static const double w3 = 8.2956;   // 7.0958
  // Initial difficulty base
  static const double w4 = 6.4133;   // 6.6473
  // Initial difficulty modifier
  static const double w5 = 0.8334;   // 0.2448
  // Difficulty decay
  static const double w6 = 3.0194;   // 2.3396
  // Difficulty change per grade
  static const double w7 = 0.001;    // 0.0033
  // Stability increase base
  static const double w8 = 1.8722;   // 1.2529
  // Grade effect on stability
  static const double w9 = 0.1666;   // 0.0000
  // Difficulty effect on stability
  static const double w10 = 0.796;   // 0.4226
  // Stability effect on stability
  static const double w11 = 1.4835;  // 1.3872
  // Retrievability effect on stability
  static const double w12 = 0.0614;  // 0.1288
  // Post-lapse stability base
  static const double w13 = 0.2629;  // 0.5220
  // Post-lapse difficulty exponent
  static const double w14 = 1.6483;  // 1.0061
  // Post-lapse stability exponent
  static const double w15 = 0.6014;  // 0.8484
  // Post-lapse retrievability effect
  static const double w16 = 1.8729;  // 1.1826
  // Short-term stability base
  static const double w17 = 0.5425;  // 0.2438
  // Short-term stability modifier
  static const double w18 = 0.0912;  // 0.0000
  // Short-term stability decay
  static const double w19 = 0.0658;  // 0.0910
  // Forgetting curve decay
  static const double w20 = 0.1542;  // 0.4217


  static const double defaultRetention = 0.9;
  static double get factor => pow(0.9, 1 / -w20) - 1;

  // Forgetting curve formula
  static double forgettingCurve(double elapsedDays, double stability) {
    return pow(1 + factor * elapsedDays / stability, -w20).toDouble();
  }

  // Next interval formula
  double calculateNextInterval(double stability) {
    return stability / factor * (pow(defaultRetention, 1 / -w20) - 1);
  }

  // Apply fuzzing to the interval
  static double applyFuzz(double interval, bool enableFuzz, int entSeq) {
    if (!enableFuzz || interval < 2.5) return interval;

    interval = interval.roundToDouble();
    final bytes = sha256.convert(utf8.encode(entSeq.toString())).bytes;
    final v = bytes[0] % 11;
    final multiplier = 0.95 + v * 0.01;
    return interval * multiplier;
  }

  // Constrain difficulty to 1-10 range
  static double constrainDifficulty(double difficulty) {
    return difficulty.clamp(1.0, 10.0);
  }

  // Initialize difficulty
  static double initDifficulty(String rating) {
    int ratingValue = _getRatingValue(rating);
    double difficulty = w4 - exp(w5 * (ratingValue - 1)) + 1;
    return constrainDifficulty(difficulty);
  }

  // Initialize stability
  static double initStability(String rating) {
    int ratingValue = _getRatingValue(rating);
    double stability = _getWeightForRating(ratingValue);
    return max(stability, 0.1);
  }

  // Get weight for rating
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
        return w2;
    }
  }

  // Convert rating string to integer value
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
        return 3;
    }
  }

  // Calculate next difficulty
  static double nextDifficulty(double currentDifficulty, String rating) {
    int ratingValue = _getRatingValue(rating);
    double deltaD = -w6 * (ratingValue - 3);
    double nextD = currentDifficulty + _linearDamping(deltaD, currentDifficulty);
    return constrainDifficulty(_meanReversion(initDifficulty("easy"), nextD));
  }

  // Linear damping for difficulty changes
  static double _linearDamping(double deltaD, double oldD) {
    return deltaD * (10 - oldD) / 9;
  }

  // Mean reversion for difficulty
  static double _meanReversion(double init, double current) {
    return w7 * init + (1 - w7) * current;
  }

  // Good recall next stability
  double nextRecallStability(double difficulty, double stability, double retrievability, String rating) {
    double hardPenalty = rating.toLowerCase() == 'hard' ? w15 : 1;
    double easyBonus = rating.toLowerCase() == 'easy' ? w16 : 1;
    double stabilityInc = exp(w8) *
        (11 - difficulty) *
        pow(stability, -w9) *
        (exp((1 - retrievability) * w10) - 1) *
        hardPenalty *
        easyBonus;
    double newStability = stability * (1 + stabilityInc);
    return newStability.clamp(0.1, double.infinity);
  }

  // Again recall next stability
  static double nextForgetStability(double difficulty, double stability, double retrievability) {
    double sMin = stability / exp(w17 * w18);
    double newStability = w11 *
        pow(difficulty, -w12) *
        (pow(stability + 1, w13) - 1) *
        exp((1 - retrievability) * w14);
    return min(newStability, sMin).clamp(0.1, double.infinity);
  }

  // Learning to review card stability
  static double nextShortTermStability(double stability, String rating) {
    int ratingValue = _getRatingValue(rating);

    double ratingOffset = (ratingValue - 3).toDouble();
    double exponent = w17 * (ratingOffset + w18);
    double baseMultiplier = exp(exponent);

    double stabilityDecay = pow(stability, -w19).toDouble();
    double sinc = baseMultiplier * stabilityDecay;

    if (ratingValue >= 3) {
      sinc = max(sinc, 1.0);
      if (ratingValue == 4) {
        sinc *= 1.05;
      }
    }
    else {
      sinc = max(sinc, 0.6);
    }
    double newStability = stability * sinc;
    double maxGrowthFactor = 2.5;
    double minStabilityFactor = 0.7;
    newStability = min(newStability, stability * maxGrowthFactor);
    newStability = max(newStability, stability * minStabilityFactor);
    return newStability.clamp(0.1, double.infinity);
  }

  /// Process a review and return updated card
  Map<String, dynamic> processReview({
    required int entSeq,
    required int type,
    required int queue,
    required int left,
    required String rating,
    required double currentStability,
    required double currentDifficulty,
    required double elapsedDays,
  }) {
    bool isNewCard = (type == 0 && queue == 0);
    bool isLearningCard = (type == 1 || type == 3 || queue == 1 || queue == 3);
    bool isReviewCard = (type == 2 && queue == 2);
    bool isGraduating = isLearningCard && left <= 1 && rating.toLowerCase() != 'again';
    double newStability = currentStability;
    double newDifficulty = currentDifficulty;

    if (isNewCard) {
      // Initialize stability and difficulty
      newStability = initStability(rating);
      newDifficulty = initDifficulty(rating);
    } else if (isLearningCard && rating.toLowerCase() == 'again') {
      newStability = w0;
    }else if (isGraduating) {
      newDifficulty = nextDifficulty(currentDifficulty, rating);
      newStability = nextShortTermStability(currentStability, rating);
      // Simulate reviews so that Good interval is always > 1 day
      if (rating.toLowerCase() == 'good') {
        double interval = calculateNextInterval(newStability);
        if (interval < 1.0) {
          double tempStability = newStability;
          double tempDifficulty = newDifficulty;
          double simulatedElapsed = interval;
          while (interval < 1.0) {
            double retrievability = forgettingCurve(simulatedElapsed, tempStability);
            tempDifficulty = nextDifficulty(tempDifficulty, "good");
            tempStability = nextRecallStability(tempDifficulty, tempStability, retrievability, "good");
            interval = calculateNextInterval(tempStability);
            simulatedElapsed = interval;
            debugPrint('Simulated review:'
              ' retrievability=${retrievability.toStringAsFixed(2)},'
              ' stability=${tempStability.toStringAsFixed(2)}'
            );
          }
          newStability = tempStability;
          newDifficulty = tempDifficulty;
        }
      }
    }
    else if (isReviewCard) {
      double retrievability = forgettingCurve(elapsedDays, currentStability);
      newDifficulty = nextDifficulty(currentDifficulty, rating);
      if (rating.toLowerCase() == 'again') {
        newStability = nextForgetStability(
            currentDifficulty, currentStability, retrievability);
      }
      else {
        newStability = nextRecallStability(
            currentDifficulty, currentStability, retrievability, rating);
      }
    }

    // Calculate next review interval
    double nextInterval;
    // Learning cards use fixed intervals
    if ((isLearningCard || isNewCard) && !isGraduating) {
      if (rating.toLowerCase() == 'again') {
        nextInterval = 10.0 / (60 * 24); // 10 minutes
      }
      else {
        nextInterval = 30.0 / (60 * 24); // 30 minutes
      }
    }
    // "Again" responses use relearning interval
    else if (rating.toLowerCase() == 'again') {
      nextInterval = 10.0 / (60 * 24); // 10 minutes
    }
    // Graduating cards use calculated interval
    else if (isGraduating) {
      nextInterval = calculateNextInterval(newStability);
    }
    // Default
    else {
      nextInterval = calculateNextInterval(newStability);
    }

    // Calculate retrievability for reference
    double currentRetrievability = isNewCard || isLearningCard
        ? 1.0
        : forgettingCurve(elapsedDays, currentStability);

    return {
      'stability': newStability,
      'difficulty': newDifficulty,
      'interval': nextInterval,
      'retrievability': currentRetrievability,
    };
  }

  // Preview intervals
  Map<String, String> previewIntervals({
    required int entSeq,
    required int type,
    required int queue,
    required int left,
    required double currentStability,
    required double currentDifficulty,
    required double elapsedDays,
  }) {
    final Map<String, String> previews = {};
    final ratings = ['again', 'hard', 'good', 'easy'];

    for (String rating in ratings) {
      final result = processReview(
        entSeq: entSeq,
        type: type,
        queue: queue,
        left: left,
        rating: rating,
        currentStability: currentStability,
        currentDifficulty: currentDifficulty,
        elapsedDays: elapsedDays,
      );

      double interval = result['interval'];
      previews[rating] = formatInterval(interval);
    }

    return previews;
  }

  // Format intervals
  static String formatInterval(double days) {
    if (days < 1) {
      return '${(days * 24 * 60).toStringAsFixed(0)} mins';
    } else if (days < 30) {
      return '${days.toStringAsFixed(0)} days';
    } else if (days < 365) {
      double months = days / 30;
      return '${months.toStringAsFixed(0)} months';
    } else {
      double years = days / 365;
      return '${years.toStringAsFixed(0)} years';
    }
  }
}
