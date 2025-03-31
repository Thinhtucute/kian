import 'package:flutter/material.dart';
import '../widgets/database_helper.dart';
import '../widgets/furigana.dart';

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
  List<Map<String, dynamic>> _partsOfSpeech = [];

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails() async {
    setState(() => _isLoading = true);

    try {
      // Load all data concurrently for better performance
      final results = await Future.wait([
        _getMeanings(widget.entry['ent_seq']),
        _getExampleSentences(widget.entry['ent_seq']),
        _getPartOfSpeech(widget.entry['ent_seq']),
      ]);

      setState(() {
        _meanings = results[0];
        _examples = results[1];
        _partsOfSpeech = results[2];
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getMeanings(int entSeq) async {
    final db = await DatabaseHelper.getDatabase();
    return await db.rawQuery("""
      SELECT s.id, GROUP_CONCAT(g.gloss, '; ') as definitions
      FROM sense s
      JOIN gloss g ON s.id = g.sense_id
      WHERE s.ent_seq = ?
      GROUP BY s.id
    """, [entSeq]);
  }

  Future<List<Map<String, dynamic>>> _getExampleSentences(int entSeq) async {
    final db = await DatabaseHelper.getDatabase();

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

  Future<List<Map<String, dynamic>>> _getPartOfSpeech(int entSeq) async {
    final db = await DatabaseHelper.getDatabase();
    return await db.rawQuery("""
    SELECT DISTINCT pos.pos
    FROM sense s
    JOIN part_of_speech pos ON s.id = pos.sense_id
    WHERE s.ent_seq = ?
    ORDER BY pos.pos
  """, [entSeq]);
  }

  void _addToFlashcards() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Word added to flashcards'),
      backgroundColor: Colors.green,
    ));
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
            // Centered word container
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
            SizedBox(height: 24),
            // Parts of speech remain in wrap format
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _partsOfSpeech
                  .map((pos) => _buildPosChip(pos['pos']))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosChip(String pos) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 40, 116, 247).withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        pos,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMeaningsAndExamples() {
    // Group examples by sense_id and take only the first example for each meaning
    Map<int, Map<String, dynamic>> examplesBySense = {};

    for (var example in _examples) {
      // Only filter out completely empty examples
      String japaneseText = example['japanese_text'] ?? '';
      String englishText = example['english_translation'] ?? '';

      if (japaneseText.isEmpty || englishText.isEmpty) {
        continue;
      }

      int senseId = example['sense_id'];
      // Only add the example if we don't already have one for this sense
      if (!examplesBySense.containsKey(senseId)) {
        examplesBySense[senseId] = example;
      }
    }

    // Create a list of meanings with their associated examples
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
                // Meaning number
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
                    Expanded(
                      child: Text(
                        'Definition',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),

                // Definition text
                Text(
                  meaning['definitions'] ?? '',
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
                    'Example', // Changed from 'Examples' to singular
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  Container(
                    width: double.infinity, // Take full width
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.center, // Center children
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
