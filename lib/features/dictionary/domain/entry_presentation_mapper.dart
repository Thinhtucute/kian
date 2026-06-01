import 'package:kian/features/dictionary/domain/entry_model.dart';
import 'package:kian/features/dictionary/domain/example_model.dart';
import 'package:kian/features/dictionary/domain/headword_model.dart';
import 'package:kian/features/dictionary/domain/sense_model.dart';

class EntryPresentationMapper {
  static bool shouldShowReadingAbove({
    required String? headwordScript,
    required String? headword,
    required String languageTag,
  }) {
    final resolvedLanguageTag = languageTag.trim();
    final hasHeadword = headword != null && headword.trim().isNotEmpty;

    if (!hasHeadword) return false;
    if (headwordScript == 'kana') return false;

    return resolvedLanguageTag == 'jp' || resolvedLanguageTag == 'cn';
  }

  static Map<String, dynamic> buildCardViewData(
    Map<String, Object?> source, {
    required String languageTag,
  }) {
    final headword = _textOrNull(source['headword']);
    final reading = _textOrNull(source['reading']);
    final headwordScript = _textOrNull(source['headword_script']) ??
        _textOrNull(source['script']);
    final showReadingAbove = shouldShowReadingAbove(
      headwordScript: headwordScript,
      headword: headword,
      languageTag: languageTag,
    );
    final isReadingOnly = headword == null;
    final displayHeadword = headword ?? reading;
    final displayReading = showReadingAbove ? reading : '';

    return <String, dynamic>{
      ...source,
      'headword': headword,
      'reading': reading,
      'headword_script': headwordScript,
      'show_reading_above': showReadingAbove,
      'is_reading_only': isReadingOnly,
      'display_headword': displayHeadword,
      'display_reading': displayReading,
    };
  }

  static List<Map<String, dynamic>> buildCardViewDataList(
    List<Map<String, Object?>> source, {
    required String languageTag,
  }) {
    return source
        .map((entry) => buildCardViewData(entry, languageTag: languageTag))
        .toList();
  }

  static Entry buildEntryFromSource(
    Map<String, Object?> source, {
    required String languageTag,
  }) {
    final mapped = buildCardViewData(source, languageTag: languageTag);
    return Entry.fromMap(mapped);
  }

  static Headword buildHeadwordFromSource(Map<String, Object?> source) {
    return Headword.fromMap(
      source.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static List<Headword> buildHeadwordListFromSource(
    List<Map<String, Object?>> source,
  ) {
    return source.map(buildHeadwordFromSource).toList();
  }

  static Sense buildSenseFromSource(Map<String, Object?> source) {
    return Sense.fromMap(
      source.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static List<Sense> buildSenseListFromSource(
    List<Map<String, Object?>> source,
  ) {
    return source.map(buildSenseFromSource).toList();
  }

  static Example buildExampleFromSource(Map<String, Object?> source) {
    return Example.fromMap(
      source.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static List<Example> buildExampleListFromSource(
    List<Map<String, Object?>> source,
  ) {
    return source.map(buildExampleFromSource).toList();
  }

  static List<Entry> buildEntryListFromSource(
    List<Map<String, Object?>> source, {
    required String languageTag,
  }) {
    return source
        .map((entry) => buildEntryFromSource(entry, languageTag: languageTag))
        .toList();
  }

  static String? _textOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}