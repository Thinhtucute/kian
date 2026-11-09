import 'package:flutter/material.dart';
import 'package:kian/features/dictionary/domain/entry_model.dart';
import 'package:kian/features/dictionary/domain/example_model.dart';
import 'package:kian/features/dictionary/domain/sense_model.dart';
import 'package:kian/screens/kanji_detail_screen.dart';
import 'reading_text.dart';

bool _isJapaneseCard(String languageTag) => languageTag.toLowerCase().startsWith('jp');

bool _isKanji(String char) {
  if (char.isEmpty) return false;

  final rune = char.runes.first;
  return rune >= 0x4E00 && rune <= 0x9FFF;
}

Widget _buildJapaneseHeadword(BuildContext context, String text) {
  final chars = text.runes.map((r) => String.fromCharCode(r)).toList();

  return Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final char in chars)
        _isKanji(char)
            ? InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KanjiDetailScreen(character: char),
                    ),
                  );
                },
                child: Text(
                  char,
                  style: TextStyle(
                    fontSize: 48,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : Text(
                char,
                style: TextStyle(
                  fontSize: 48,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
    ],
  );
}

Widget _buildHeadwordWidget(BuildContext context, String headwordText, String displayReading, String languageTag) {
  final baseText = (headwordText.isNotEmpty ? headwordText : displayReading).trim();

  if (_isJapaneseCard(languageTag) && baseText.isNotEmpty) {
    return _buildJapaneseHeadword(context, baseText);
  }

  return SelectableText(
    baseText.isNotEmpty ? baseText : displayReading,
    style: TextStyle(
      fontSize: 48,
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  );
}

class ReviewCardWidget extends StatelessWidget {
  final Entry card;
  final List<Sense> meanings;
  final List<Example> examples;
  final bool showAnswer;
  final VoidCallback? onShowAnswer;
  final String languageTag;

  const ReviewCardWidget({
    super.key,
    required this.card,
    required this.meanings,
    required this.examples,
    required this.languageTag,
    this.showAnswer = false,
    this.onShowAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final headwordText = card.displayHeadword;
    final usesReadingAbove = card.showReadingAbove;
    final displayReading = card.displayReading;

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
              // Headword + reading (reading on top, smaller)
              Expanded(
                flex: showAnswer ? 1 : 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showAnswer && !usesReadingAbove && displayReading.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Text(
                          displayReading,
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.lightBlueAccent,
                          ),
                        ),
                      ),
                    Center(
                      child: usesReadingAbove
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FuriganaText(
                                  reading: showAnswer ? displayReading : '',
                                  languageTag: languageTag,
                                  readingStyle: TextStyle(
                                    fontSize: 20,
                                    color: Colors.lightBlueAccent,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                _buildHeadwordWidget(context, headwordText, displayReading, languageTag),
                              ],
                            )
                          : _buildHeadwordWidget(context, headwordText, displayReading, languageTag),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.grey[700]),
              if (languageTag.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      languageTag,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
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
    final Map<int, Example> examplesBySense = {};

    for (var example in examples) {
      if (example.japaneseText.isEmpty || example.englishTranslation.isEmpty) {
        continue;
      }
      final senseId = example.senseId;
      if (!examplesBySense.containsKey(senseId)) {
        examplesBySense[senseId] = example;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: meanings.asMap().entries.map((entry) {
        final index = entry.key;
        final meaning = entry.value;
        final senseId = meaning.id;

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
                    if (meaning.partOfSpeech.isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            meaning.partOfSpeech.join(', '),
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
                  meaning.definitions.join('; '),
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
                          examplesBySense[senseId]!.japaneseText,
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        SelectableText(
                          examplesBySense[senseId]!.englishTranslation,
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
