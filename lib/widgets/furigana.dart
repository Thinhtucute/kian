import 'package:flutter/material.dart';

class FuriganaText extends StatelessWidget {
  final String kanji;
  final String reading;

  const FuriganaText({super.key, required this.kanji, required this.reading});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          reading,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          kanji,
          style: TextStyle(fontSize: 24, color: Colors.white),
        ),
      ],
    );
  }
}
