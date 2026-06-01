class Example {
  final int id;
  final int senseId;
  final String japaneseText;
  final String englishTranslation;
  final String? translationLang;
  final String? source;

  Example({
    required this.id,
    required this.senseId,
    required this.japaneseText,
    required this.englishTranslation,
    this.translationLang,
    this.source,
  });

  factory Example.fromMap(Map<String, dynamic> map) {
    return Example(
      id: _asInt(map['id'] ?? map['example_id']),
      senseId: _asInt(map['sense_id']),
      japaneseText: (map['japanese_text'] ?? '').toString(),
      englishTranslation: (map['english_translation'] ?? '').toString(),
      translationLang: map['translation_lang']?.toString(),
      source: map['source']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sense_id': senseId,
      'japanese_text': japaneseText,
      'english_translation': englishTranslation,
      'translation_lang': translationLang,
      'source': source,
    };
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
