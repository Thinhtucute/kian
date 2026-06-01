class Sense {
  final int id;
  final int entryId;
  final int position;
  final List<String> definitions;
  final List<String> partOfSpeech;

  Sense({
    required this.id,
    required this.entryId,
    required this.position,
    required this.definitions,
    required this.partOfSpeech,
  });

  factory Sense.fromMap(Map<String, dynamic> map) {
    return Sense(
      id: _asInt(map['id']),
      entryId: _asInt(map['entry_id']),
      position: _asInt(map['position']),
      definitions: _splitValues(map['definitions']),
      partOfSpeech: _splitValues(map['part_of_speech']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entry_id': entryId,
      'position': position,
      'definitions': definitions.join('; '),
      'part_of_speech': partOfSpeech.join(', '),
    };
  }

  static List<String> _splitValues(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return const [];
    return text
        .split(RegExp(r'[;,；]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
