import 'package:flutter/material.dart';
import '../helpers/dictionary_helper.dart';
import '../helpers/fsrs_helper.dart';
import '../widgets/furigana.dart';
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
      SELECT s.id, GROUP_CONCAT(DISTINCT g.gloss, '; ') as definitions, GROUP_CONCAT(DISTINCT pos.pos, ', ') as part_of_speech
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
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWordHeader(),
                  SizedBox(height: 24),
                  _buildMeaningsAndExamples(),
                ],
              ),
            ),
    );
  }

  Widget _buildWordHeader() {
    return Card(
      color: const Color.fromARGB(255, 33, 36, 97),
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          children: [
            Center(
              child: widget.entry['keb'] != null
                  ? FuriganaText(
                      kanji: widget.entry['keb'],
                      reading: widget.entry['reb'] ?? '',
                      kanjiStyle: TextStyle(
                        fontSize: 36,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      readingStyle: TextStyle(
                        fontSize: 16,
                        color: Colors.lightBlueAccent,
                        letterSpacing: 1.0,
                      ),
                    )
                  : Text(
                      widget.entry['reb'] ?? '',
                      style: TextStyle(
                        fontSize: 36,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
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
                // Meaning number and part of speech
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(0xFFF3BB06),
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
                              color: Color(0xFFF3BB06),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 12),

                // Definition text
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

                // Example if it exists
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
}
