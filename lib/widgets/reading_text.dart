  import 'package:flutter/material.dart';

class FuriganaText extends StatelessWidget {
  final String reading;
  final TextStyle? readingStyle;
  final String languageTag;
  final String? readingLabel;
  final bool showReadingLabel;
  final double verticalSpacing;

  const FuriganaText({
    super.key,
    required this.reading,
    required this.languageTag,
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

    if (reading.isEmpty) {
      return const SizedBox.shrink();
    }

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
        Text(
          reading,
          style: resolvedReadingStyle,
          textAlign: TextAlign.center,
        ),
        if (verticalSpacing > 0) SizedBox(height: verticalSpacing),
      ],
    );
  }
}
