// lib/screens/learn_screen.dart
import 'package:flutter/material.dart';
import '../widgets/flashcard.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  _LearnScreenState createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  int _currentIndex = 0;
  bool _showAnswer = false;

  void _toggleAnswer() {
    setState(() {
      _showAnswer = !_showAnswer;
    });
  }

  void _nextCard() {
    setState(() {
      if (_currentIndex + 1 < mockFlashcards.length) {
        _currentIndex++;
      } else {
        _currentIndex = 0; // Restart from the beginning
      }
      _showAnswer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flashcard = mockFlashcards[_currentIndex];

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: AppBar(
        title: Text("Japanese Kanji N5"),
        backgroundColor: const Color.fromARGB(255, 9, 12, 43),
      ),
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85, // 85% screen width
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 3, 10, 88),
            border: Border.all(color: const Color.fromARGB(255, 9, 12, 43), width: 2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _showAnswer ? flashcard.answer : flashcard.question,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40),
              if (!_showAnswer)
                ElevatedButton(
                  onPressed: _toggleAnswer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 40),
                  ),
                  child: Text(
                    "Show Andwer",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _reviewButton("Again", "1 Min", Colors.redAccent),
                    _reviewButton("Good", "10 Min", const Color.fromARGB(255, 73, 176, 126)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewButton(String label, String subText, Color color) {
    return ElevatedButton(
      onPressed: _nextCard,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(subText, style: TextStyle(fontSize: 15, color: Colors.white)),
        ],
      ),
    );
  }
}
