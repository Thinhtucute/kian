import 'package:flutter/material.dart';

class FuriganaText extends StatelessWidget {
  final String kanji;
  final String reading;
  final TextStyle? kanjiStyle;
  final TextStyle? readingStyle;
  final double verticalSpacing;

  const FuriganaText({
    super.key,
    required this.kanji,
    required this.reading,
    this.kanjiStyle,
    this.readingStyle,
    this.verticalSpacing = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    // If no kanji or reading, just show the text
    if (kanji.isEmpty || reading.isEmpty) {
      return Text(
        kanji.isEmpty ? reading : kanji,
        style: kanjiStyle ?? TextStyle(
          fontSize: 32,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // Simple column with reading above kanji
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Furigana reading
        Text(
          reading,
          style: readingStyle ?? TextStyle(
            fontSize: 14,
            color: Colors.lightBlueAccent,
            height: 1.0,
          ),
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
