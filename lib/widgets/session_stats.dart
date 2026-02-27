import 'package:flutter/material.dart';
import '../../models/session_model.dart';

class SessionStatsPopup extends StatelessWidget {
  final LearnSessionModel session;
  final String Function(int) formatDuration;
  final double Function(LearnSessionModel) calculateAccuracy;

  const SessionStatsPopup({
    super.key,
    required this.session,
    required this.formatDuration,
    required this.calculateAccuracy,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.analytics, color: Colors.white),
      onSelected: (value) {},
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session Stats',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Correct: ${session.correctAnswers}'),
              Text('Incorrect: ${session.incorrectAnswers}'),
              Text('Accuracy: ${calculateAccuracy(session)}%'),
              Text('Avg Time: ${formatDuration((session.averageResponseTime / 1000).round())}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
