import 'package:flutter/material.dart';
import '../helpers/dictionary_helper.dart';
import '../helpers/fsrs_helper.dart';
import '../widgets/card_widget.dart';
import 'dart:async';

class WordDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> entry;

  const WordDetailsScreen({super.key, required this.entry});

  @override
  State<WordDetailsScreen> createState() => _WordDetailsScreenState();
}

class _WordDetailsScreenState extends State<WordDetailsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _meanings = [];
  List<Map<String, dynamic>> _examples = [];

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _getMeanings(widget.entry['ent_seq']),
        _getExampleSentences(widget.entry['ent_seq']),
      ]);

      setState(() {
        _meanings = results[0];
        _examples = results[1];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getMeanings(int entSeq) async {
    final db = await DictionaryHelper.getDatabase();
    return await db.rawQuery("""
      SELECT s.id,
        GROUP_CONCAT(DISTINCT g.gloss) as definitions,
        GROUP_CONCAT(DISTINCT pos.pos) as part_of_speech
      FROM sense s
      JOIN gloss g ON s.id = g.sense_id
      LEFT JOIN part_of_speech pos ON s.id = pos.sense_id
      WHERE s.ent_seq = ?
      GROUP BY s.id
    """, [entSeq]);
  }

  Future<List<Map<String, dynamic>>> _getExampleSentences(int entSeq) async {
    final db = await DictionaryHelper.getDatabase();

    return await db.rawQuery("""
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

  Future<void> _addToFlashcards() async {
    try {
      final entSeq = widget.entry['ent_seq'] as int;
      final added = await FSRSHelper.addToFSRS(entSeq);

      if (!mounted) return;

      if (added) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Word added to review'),
          backgroundColor: Colors.green,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Word is already added to review'),
          backgroundColor: Colors.amber,
        ));
      }
    } catch (e) {
      debugPrint('Error adding to flashcards: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bi loi cc j do r'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: AppBar(
        title: Text(
          widget.entry['keb'] ?? widget.entry['reb'],
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 9, 12, 43),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.add_card, color: Colors.amber),
            onPressed: _addToFlashcards,
            tooltip: 'Add to flashcards',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ReviewCardWidget(
              card: widget.entry,
              meanings: _meanings,
              examples: _examples,
              showAnswer: true,
            ),
    );
  }
}