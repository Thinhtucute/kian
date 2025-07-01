import 'package:flutter/material.dart';
import 'dart:async';
import '../helpers/fsrs_helper.dart';
import '../widgets/furigana.dart';
import 'settings_screen.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  LearnScreenState createState() => LearnScreenState();
}

class LearnScreenState extends State<LearnScreen> {
  List<Map<String, dynamic>> _cards = [];
  bool _isLoading = true;
  bool _showingAnswer = false;
  int _currentCardIndex = 0;
  int _startTime = 0;
  Timer? _sessionTimer;
  int _sessionDuration = 0;
  int _cardsReviewed = 0;
  Map<String, String> _predictedIntervals = {
    'again': '< 10 min',
    'good': '~1 day'
  };

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

      setState(() {
        _cards = cards;
        _isLoading = false;
        _currentCardIndex = 0;
        _showingAnswer = false;

        // Start timing this card
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

    // Get predicted intervals for this card
    try {
      _predictedIntervals =
          await FSRSHelper.getPredictedIntervals(card['entry_id']);
      debugPrint('Predicted intervals: $_predictedIntervals');
    } catch (e) {
      debugPrint('Error getting intervals: $e');
      _predictedIntervals = {'again': '< 10 min', 'good': '~1 day'};
    }

    setState(() {
      _showingAnswer = true;
    });
  }

  Future<void> _processRating(bool isGood) async {
    // Calculate time spent on this card
    final now = DateTime.now().millisecondsSinceEpoch;
    final duration = now - _startTime;

    try {
      final card = _cards[_currentCardIndex];
      await FSRSHelper.processReview(card['entry_id'], isGood,
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
      setState(() {
        _currentCardIndex++;
        _showingAnswer = false;
        _startTime = DateTime.now().millisecondsSinceEpoch;
      });
    } else {
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
        // No more cards - truly finished
        _sessionTimer?.cancel();

        setState(() {
          _cards = [];
          _isLoading = false;
        });

        // Show completion dialog since we're really done
        showDialog(
          context: context,
          barrierDismissible: false,
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
                    setState(() {
                      _cards = [];
                    });
                  },
                ),
              ],
            );
          },
        );
      } else {
        // More cards available - continue reviewing
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
                    // Question (always visible)
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: hasKanji
                            ? FuriganaText(
                                kanji: card['keb'],
                                reading:
                                    _showingAnswer ? card['reb'] ?? '' : '',
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
                    ),

                    // Divider between question and answer
                    Divider(color: Colors.grey[700]),

                    // Answer (visible only after tap)
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: _showingAnswer
                            ? Text(
                                card['gloss'] ?? '',
                                style: TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
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
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRatingButton(
                          'Again',
                          Colors.red[700]!,
                          () => _processRating(false),
                          _predictedIntervals['again'] ?? '< 10 min',
                        ),
                        _buildRatingButton(
                          'Good',
                          Colors.green[700]!,
                          () => _processRating(true),
                          _predictedIntervals['good'] ?? '~1 day',
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : SizedBox(height: 100), // Placeholder when buttons aren't visible
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

  Widget _buildNextReviewText(String text, bool isGood) {
    return Container(
      width: 120, // Match button width
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isGood ? Colors.green[400] : Colors.red[400],
          fontSize: 14,
        ),
      ),
    );
  }
}
