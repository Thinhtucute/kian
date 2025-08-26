import 'package:flutter/material.dart';
import 'dart:async';
import '../helpers/fsrs_helper.dart';
import '../helpers/dictionary_helper.dart';
import '../widgets/furigana.dart';
import 'settings_screen.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  LearnScreenState createState() => LearnScreenState();
}

class LearnScreenState extends State<LearnScreen> {
  List<Map<String, dynamic>> _cards = [];
  List<Map<String, dynamic>> _meanings = [];
  List<Map<String, dynamic>> _examples = [];
  bool _isLoading = true;
  bool _showingAnswer = false;
  int _currentCardIndex = 0;
  int _startTime = 0;
  Timer? _sessionTimer;
  int _sessionDuration = 0;
  int _cardsReviewed = 0;
  Map<String, String> _predictedIntervals = {
    'again': '10 mins',
    'good': 'unknown'
  };

  // New session statistics
  int _correctAnswers = 0;
  int _incorrectAnswers = 0;
  double _averageResponseTime = 0.0;
  final List<int> _responseTimes = [];

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
      setState(() {
        _sessionDuration++;
      });
    });
  }

  Future<void> _loadCards() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cards = await FSRSHelper.getDueCards();

      // Load meanings and examples for the first card (if any)
      List<Map<String, dynamic>> meanings = [];
      List<Map<String, dynamic>> examples = [];
      if (cards.isNotEmpty) {
        final entSeq = cards[0]['ent_seq'];
        final db = await DictionaryHelper.getDatabase();
        meanings = await db.rawQuery("""
          SELECT s.id, GROUP_CONCAT(g.gloss, '; ') as definitions, GROUP_CONCAT(pos.pos, ', ') as part_of_speech
          FROM sense s
          JOIN gloss g ON s.id = g.sense_id
          LEFT JOIN part_of_speech pos ON s.id = pos.sense_id
          WHERE s.ent_seq = ?
          GROUP BY s.id
        """, [entSeq]);
        examples = await db.rawQuery("""
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
      }

      setState(() {
        _cards = cards;
        _meanings = meanings;
        _examples = examples;
        _isLoading = false;
        _currentCardIndex = 0;
        _showingAnswer = false;
        _startTime = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (e) {
      debugPrint('Error loading cards: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showAnswer() async {
    final card = _cards[_currentCardIndex];

    // Default predicted intervals
    try {
      _predictedIntervals =
          await FSRSHelper.getPredictedIntervals(card['ent_seq']);
      debugPrint(
          'Predicted intervals for card ${card['ent_seq']}: $_predictedIntervals');
    } catch (e) {
      debugPrint('Error getting intervals: $e');
      _predictedIntervals = {'again': '10 mins', 'good': 'unknown'};
    }

    setState(() {
      _showingAnswer = true;
    });
  }

  Future<void> _processRating(bool isGood) async {
    // Calculate time spent on this card
    final now = DateTime.now().millisecondsSinceEpoch;
    final duration = now - _startTime;

    // Update session statistics
    _responseTimes.add(duration);
    if (isGood) {
      _correctAnswers++;
    } else {
      _incorrectAnswers++;
    }
    _averageResponseTime =
        _responseTimes.reduce((a, b) => a + b) / _responseTimes.length;

    try {
      final card = _cards[_currentCardIndex];
      debugPrint(
          'Processing review for card ${card['ent_seq']}: ${isGood ? "Good" : "Again"}');
      debugPrint('Current predicted intervals: $_predictedIntervals');

      await FSRSHelper.processReview(card['ent_seq'], isGood,
          reviewDuration: duration);

      setState(() {
        _cardsReviewed++;
      });

      _nextCard();
    } catch (e) {
      debugPrint('Error processing review: $e');
    }
  }

  void _nextCard() {
    if (_currentCardIndex < _cards.length - 1) {
      debugPrint(
          'Moving to next card: ${_currentCardIndex + 1} -> ${_currentCardIndex + 2}');
      setState(() {
        _currentCardIndex++;
        _showingAnswer = false;
        _startTime = DateTime.now().millisecondsSinceEpoch;
        // Reset predicted intervals for the new card
        _predictedIntervals = {'again': '10 mins', 'good': 'unknown'};
      });
    } else {
      debugPrint('Finished current card set, checking for more cards');
      _finishReview();
    }
  }

  Future<void> _finishReview() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cards = await FSRSHelper.getDueCards();

      if (!mounted) return;
      if (cards.isEmpty) {
        // No more 24h due cards
        _sessionTimer?.cancel();
        setState(() {
          _cards = [];
          _isLoading = false;
        });
      } else {
        // 24 hours due cards available
        setState(() {
          _cards = cards;
          _isLoading = false;
          _currentCardIndex = 0;
          _showingAnswer = false;
          _startTime = DateTime.now().millisecondsSinceEpoch;
        });
      }
    } catch (e) {
      debugPrint('Error checking for more cards: $e');
      setState(() {
        _isLoading = false;
        _cards = [];
      });

      // Show error completion dialog
      _sessionTimer?.cancel();
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Review Session Complete'),
            content: Text(
                'You reviewed $_cardsReviewed cards in ${_formatDuration(_sessionDuration)}'),
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
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: AppBar(
        title: Text('Review', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 9, 12, 43),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          // Session statistics
          if (_cardsReviewed > 0)
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
                      Text('Correct: $_correctAnswers'),
                      Text('Incorrect: $_incorrectAnswers'),
                      Text('Accuracy: ${_calculateAccuracy()}%'),
                      Text(
                          'Avg Time: ${_formatDuration((_averageResponseTime / 1000).round())}'),
                    ],
                  ),
                ),
              ],
            ),
          // Timer display
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Text(
                _formatDuration(_sessionDuration),
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          // Settings icon
          IconButton(
            icon: Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? _buildNoCardsView()
              : _buildReviewArea(),
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

  Widget _buildReviewArea() {
    final card = _cards[_currentCardIndex];
    final hasKanji = card['keb'] != null;

    return Column(
      children: [
        // Progress indicator
        LinearProgressIndicator(
          value: (_currentCardIndex + 1) / _cards.length,
          backgroundColor: Colors.grey[800],
          valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
        ),

        // Card count
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '${_currentCardIndex + 1} / ${_cards.length}',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ),

        // Card content
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
                    // Vocab
                    Expanded(
                      flex: _showingAnswer ? 1 : 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Center(
                            child: hasKanji
                                ? FuriganaText(
                                    kanji: card['keb'],
                                    reading: _showingAnswer ? card['reb'] ?? '' : '',
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

                    // Divider between question and answer
                    Divider(color: Colors.grey[700]),

                    // Answer
                    Expanded(
                      flex: _showingAnswer ? 3 : 2,
                      child: Center(
                        child: _showingAnswer
                            ? SingleChildScrollView(
                                child: _buildMeaningsAndExamples(),
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

        // Rating buttons
        _showingAnswer
            ? Column(
                children: [
                  // Buttons row
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRatingButton(
                          'Again',
                          Colors.red[700]!,
                          () => _processRating(false),
                          _predictedIntervals['again'] ?? '10 mins',
                        ),
                        _buildRatingButton(
                          'Good',
                          Colors.green[700]!,
                          () => _processRating(true),
                          _predictedIntervals['good'] ?? 'unknown',
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

  Widget _buildMeaningsAndExamples() {
    Map<int, Map<String, dynamic>> examplesBySense = {};

    for (var example in _examples) {
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
      children: _meanings.asMap().entries.map((entry) {
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

  double _calculateAccuracy() {
    final total = _correctAnswers + _incorrectAnswers;
    if (total == 0) return 0.0;
    return ((_correctAnswers / total) * 100).roundToDouble();
  }
}
