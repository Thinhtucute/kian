class Headword {
  final int id;
  final int entryId;
  final String text;
  final String script;
  final String? romanizationType;
  final int position;
  final bool isPrimary;

  Headword({
    required this.id,
    required this.entryId,
    required this.text,
    required this.script,
    this.romanizationType,
    required this.position,
    required this.isPrimary,
  });

  factory Headword.fromMap(Map<String, dynamic> map) {
    return Headword(
      id: _asInt(map['id']),
      entryId: _asInt(map['entry_id']),
      text: (map['text'] ?? '').toString(),
      script: (map['script'] ?? '').toString(),
      romanizationType: map['romanization_type']?.toString(),
      position: _asInt(map['position']),
      isPrimary: map['is_primary'] == true || map['is_primary'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entry_id': entryId,
      'text': text,
      'script': script,
      'romanization_type': romanizationType,
      'position': position,
      'is_primary': isPrimary,
    };
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
