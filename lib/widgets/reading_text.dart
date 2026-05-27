import 'package:flutter/material.dart';

class FuriganaText extends StatelessWidget {
  final String kanji;
  final String reading;
  final TextStyle? kanjiStyle;
  final TextStyle? readingStyle;
  final String languageTag;
  final String? readingLabel;
  final bool showReadingLabel;
  final double verticalSpacing;

  const FuriganaText({
    super.key,
    required this.kanji,
    required this.reading,
    required this.languageTag,
    this.kanjiStyle,
    this.readingStyle,
    this.readingLabel,
    this.showReadingLabel = false,
    this.verticalSpacing = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    final isCn = languageTag.startsWith('cn');
    final isJp = languageTag.startsWith('jp');
    final resolvedReadingStyle = readingStyle ?? TextStyle(
      fontSize: (isCn || isJp) ? 16 : 14,
      color: Colors.lightBlueAccent,
      height: 1.0,
      letterSpacing: (isCn || isJp) ? 0.4 : 0.0,
    );

    final String displayReading = reading;

    // Simple column with reading above kanji
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showReadingLabel && (readingLabel?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Text(
              readingLabel!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
                letterSpacing: 0.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        // Reading (kana/pinyin)
        Text(
          displayReading,
          style: resolvedReadingStyle,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: verticalSpacing),
        // Kanji text
        Text(
          kanji,
          style: kanjiStyle ?? TextStyle(
            fontSize: 25,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
