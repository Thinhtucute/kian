import 'package:flutter/material.dart';
import 'dart:async';
import '../helpers/fsrs_helper.dart';
import '../helpers/dictionary_helper.dart';
import '../widgets/furigana.dart';
import 'package:provider/provider.dart';
import '../models/learn_session_model.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  LearnScreenState createState() => LearnScreenState();
}

class LearnScreenState extends State<LearnScreen> {
  Timer? _sessionTimer;

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

  Future<void> _loadMeaningsAndExamples() async {
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

  Future<void> _loadCards() async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    if (session.cards.isNotEmpty) return; // Don't reload if already loaded

    session.setLoading(true);

    try {
      final cards = await FSRSHelper.getDueCards();
      session.setCards(cards);
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
      await _loadMeaningsAndExamples();
    } catch (e) {
      debugPrint('Error loading cards: $e');
      session.setLoading(false);
    }
  }

  Future<void> _exportData() async {
    final dbPath = '/data/data/com.example.anki2/app_flutter/fsrs.db';
    final exportDir = await getApplicationDocumentsDirectory();
    final exportPath = '${exportDir.path}/cards.db';

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.copy(exportPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Database exported to $exportPath'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Database file not found'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showAnswer() async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    final card = session.cards[session.currentCardIndex];

    try {
      final intervals = await FSRSHelper.getPredictedIntervals(card['ent_seq']);
      session.setPredictedIntervals(intervals);
      debugPrint(
          'Predicted intervals for card ${card['ent_seq']}: ${session.predictedIntervals}');
    } catch (e) {
      debugPrint('Error getting intervals: $e');
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
    }

    session.setShowingAnswer(true);
  }

  Future<void> _processRating(bool isGood) async {
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
      debugPrint(
          'Processing review for card ${card['ent_seq']}: ${isGood ? "Good" : "Again"}');
      debugPrint('Current predicted intervals: ${session.predictedIntervals}');

      await FSRSHelper.processReview(card['ent_seq'], isGood,
          reviewDuration: duration);

      session.cardsReviewed++;
      await _nextCard();
    } catch (e) {
      debugPrint('Error processing review: $e');
    }
  }

  Future<void> _nextCard() async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    if (session.currentCardIndex < session.cards.length - 1) {
      debugPrint(
          'Moving to next card: ${session.currentCardIndex + 1} -> ${session.currentCardIndex + 2}');
      session.setCurrentCardIndex(session.currentCardIndex + 1);
      session.setShowingAnswer(false);
      session.startTime = DateTime.now().millisecondsSinceEpoch;
      session.setPredictedIntervals({'again': '10 mins', 'good': 'unknown'});
      await _loadMeaningsAndExamples();
    } else {
      debugPrint('Finished current card set, checking for more cards');
      await _finishReview();
    }
  }

  Future<void> _finishReview() async {
    final session = Provider.of<LearnSessionModel>(context, listen: false);
    session.setLoading(true);

    try {
      final cards = await FSRSHelper.getDueCards();

      if (!mounted) return;
      if (cards.isEmpty) {
        _sessionTimer?.cancel();
        session.setCards([]);
        session.setLoading(false);
      } else {
        session.setCards(cards);
        session.setCurrentCardIndex(0);
        session.setLoading(false);
        session.setShowingAnswer(false);
        session.startTime = DateTime.now().millisecondsSinceEpoch;
      }
    } catch (e) {
      debugPrint('Error checking for more cards: $e');
      session.setLoading(false);
      session.setCards([]);

      _sessionTimer?.cancel();
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Review Session Complete'),
            content: Text(
                'You reviewed ${session.cardsReviewed} cards in ${_formatDuration(session.sessionDuration)}'),
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
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
              if (session.cardsReviewed > 0)
                PopupMenuButton<String>(
                  icon: Icon(Icons.analytics, color: Colors.white),
                  onSelected: (value) {},
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Session Stats',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text('Correct: ${session.correctAnswers}'),
                          Text('Incorrect: ${session.incorrectAnswers}'),
                          Text('Accuracy: ${_calculateAccuracy(session)}%'),
                          Text(
                              'Avg Time: ${_formatDuration((session.averageResponseTime / 1000).round())}'),
                        ],
                      ),
                    ),
                  ],
                ),
              Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Text(
                    _formatDuration(session.sessionDuration),
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
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
    final card = session.cards[session.currentCardIndex];
    final hasKanji = card['keb'] != null;

    return Column(
      children: [
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
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Card(
              color: Color.fromARGB(255, 33, 36, 97),
              elevation: 4.0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: session.showingAnswer ? 1 : 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Center(
                            child: hasKanji
                                ? FuriganaText(
                                    kanji: card['keb'],
                                    reading: session.showingAnswer
                                        ? card['reb'] ?? ''
                                        : '',
                                    kanjiStyle: TextStyle(
                                      fontSize: 48,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    readingStyle: TextStyle(
                                      fontSize: 20,
                                      color: Colors.lightBlueAccent,
                                      letterSpacing: 1.0,
                                    ),
                                  )
                                : Text(
                                    card['reb'] ?? '',
                                    style: TextStyle(
                                      fontSize: 48,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.grey[700]),
                    Expanded(
                      flex: session.showingAnswer ? 3 : 2,
                      child: Center(
                        child: session.showingAnswer
                            ? SingleChildScrollView(
                                child: _buildMeaningsAndExamples(session),
                              )
                            : TextButton(
                                onPressed: _showAnswer,
                                child: Text(
                                  'Show Answer',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        session.showingAnswer
            ? Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRatingButton(
                          'Again',
                          Colors.red[700]!,
                          () => _processRating(false),
                          session.predictedIntervals['again'] ?? '10 mins',
                        ),
                        _buildRatingButton(
                          'Good',
                          Colors.green[700]!,
                          () => _processRating(true),
                          session.predictedIntervals['good'] ?? 'unknown',
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : SizedBox(height: 100),
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

  Widget _buildMeaningsAndExamples(LearnSessionModel session) {
    Map<int, Map<String, dynamic>> examplesBySense = {};

    for (var example in session.examples) {
      String japaneseText = example['japanese_text'] ?? '';
      String englishText = example['english_translation'] ?? '';
      if (japaneseText.isEmpty || englishText.isEmpty) continue;
      int senseId = example['sense_id'];
      if (!examplesBySense.containsKey(senseId)) {
        examplesBySense[senseId] = example;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: session.meanings.asMap().entries.map((entry) {
        int index = entry.key;
        Map<String, dynamic> meaning = entry.value;
        int senseId = meaning['id'];

        return Card(
          color: const Color.fromARGB(255, 2, 75, 127),
          margin: EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    if (meaning['part_of_speech'] != null &&
                        meaning['part_of_speech'].toString().isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            (meaning['part_of_speech'] as String)
                                .replaceAll(',', ', ')
                                .split(',')
                                .map((pos) => pos.trim())
                                .toSet()
                                .join(', '),
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  meaning['definitions'] != null
                      ? (meaning['definitions'] as String)
                          .replaceAll(',', '; ')
                          .split(';')
                          .map((d) => d.trim())
                          .toSet()
                          .join('; ')
                      : '',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                if (examplesBySense.containsKey(senseId)) ...[
                  SizedBox(height: 16),
                  Text(
                    'Example',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          examplesBySense[senseId]!['japanese_text'] ?? '',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          examplesBySense[senseId]!['english_translation'] ??
                              '',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  double _calculateAccuracy(LearnSessionModel session) {
    final total = session.correctAnswers + session.incorrectAnswers;
    if (total == 0) return 0.0;
    return ((session.correctAnswers / total) * 100).roundToDouble();
  }
}
