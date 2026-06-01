import 'package:kian/features/dictionary/domain/example_model.dart';
import 'package:kian/features/dictionary/domain/headword_model.dart';
import 'package:kian/features/dictionary/domain/sense_model.dart';

class Entry {
  final int entryId;
  final String lang;
  final String? headword;
  final String? headwordScript;
  final String? reading;
  final String? gloss;
  final bool isReadingOnly;
  final bool showReadingAbove;
  final String displayHeadword;
  final String displayReading;
  final List<Headword> headwords;
  final List<Sense> senses;
  final List<Example> examples;

  Entry({
    required this.entryId,
    required this.lang,
    this.headword,
    this.headwordScript,
    this.reading,
    this.gloss,
    required this.isReadingOnly,
    required this.showReadingAbove,
    required this.displayHeadword,
    required this.displayReading,
    this.headwords = const [],
    this.senses = const [],
    this.examples = const [],
  });

  factory Entry.fromMap(Map<String, dynamic> map) {
    final headwordMaps = _asMapList(map['headwords']);
    final senseMaps = _asMapList(map['senses']);
    final exampleMaps = _asMapList(map['examples']);

    return Entry(
      entryId: _asInt(map['entry_id']),
      lang: (map['lang'] ?? '').toString(),
      headword: map['headword']?.toString(),
      headwordScript: map['headword_script']?.toString(),
      reading: map['reading']?.toString(),
      gloss: map['gloss']?.toString(),
      isReadingOnly: map['is_reading_only'] == true,
      showReadingAbove: map['show_reading_above'] == true,
      displayHeadword: (map['display_headword'] ?? map['headword'] ?? '').toString(),
      displayReading: (map['display_reading'] ?? map['reading'] ?? '').toString(),
      headwords: headwordMaps.map(Headword.fromMap).toList(),
      senses: senseMaps.map(Sense.fromMap).toList(),
      examples: exampleMaps.map(Example.fromMap).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'entry_id': entryId,
      'lang': lang,
      'headword': headword,
      'headword_script': headwordScript,
      'reading': reading,
      'gloss': gloss,
      'is_reading_only': isReadingOnly,
      'show_reading_above': showReadingAbove,
      'display_headword': displayHeadword,
      'display_reading': displayReading,
      'headwords': headwords.map((item) => item.toMap()).toList(),
      'senses': senses.map((item) => item.toMap()).toList(),
      'examples': examples.map((item) => item.toMap()).toList(),
    };
  }

  static List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
