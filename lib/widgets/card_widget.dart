import 'package:flutter/material.dart';
import 'furigana.dart';

class ReviewCardWidget extends StatelessWidget {
  final Map<String, dynamic> card;
  final List<Map<String, dynamic>> meanings;
  final List<Map<String, dynamic>> examples;
  final bool showAnswer;
  final VoidCallback? onShowAnswer;

  const ReviewCardWidget({
    super.key,
    required this.card,
    required this.meanings,
    required this.examples,
    this.showAnswer = false,
    this.onShowAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final hasKanji = card['keb'] != null;

    return Padding(
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
              // Kanji/Reading display
              Expanded(
                flex: showAnswer ? 1 : 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: hasKanji
                          ? FuriganaText(
                              kanji: card['keb'],
                              reading: showAnswer ? card['reb'] ?? '' : '',
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
                          : SelectableText(
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
              // Answer area
              Expanded(
                flex: showAnswer ? 3 : 2,
                child: Center(
                  child: showAnswer
                      ? SingleChildScrollView(
                          child: _buildMeaningsAndExamples(),
                        )
                      : TextButton(
                          onPressed: onShowAnswer,
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
    );
  }

  Widget _buildMeaningsAndExamples() {
    Map<int, Map<String, dynamic>> examplesBySense = {};

    for (var example in examples) {
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
      children: meanings.asMap().entries.map((entry) {
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
                SelectableText(
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
                  SelectableText(
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
                        SelectableText(
                          examplesBySense[senseId]!['japanese_text'] ?? '',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        SelectableText(
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
