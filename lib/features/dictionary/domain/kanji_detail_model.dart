class KanjiDetail {
  final String character;
  final int codePoint;
  final String codePointLabel;
  final Map<String, List<String>> properties;

  const KanjiDetail({
    required this.character,
    required this.codePoint,
    required this.codePointLabel,
    required this.properties,
  });

  factory KanjiDetail.fromRows(
    String character,
    Map<String, Object?> characterRow,
    List<Map<String, Object?>> propertyRows,
  ) {
    final properties = <String, List<String>>{};

    for (final row in propertyRows) {
      final key = row['key']?.toString();
      final value = row['value']?.toString();
      if (key == null || key.isEmpty || value == null || value.isEmpty) {
        continue;
      }
      properties.putIfAbsent(key, () => []).add(value);
    }

    return KanjiDetail(
      character: character,
      codePoint: _asInt(characterRow['id']),
      codePointLabel: characterRow['codepoint']?.toString() ?? '',
      properties: properties,
    );
  }

  String? firstProperty(String key) {
    final values = properties[key];
    return values == null || values.isEmpty ? null : values.first;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
