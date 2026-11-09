import 'package:flutter/material.dart';
import 'package:kian/features/dictionary/domain/dictionary_helper.dart';
import 'package:kian/features/dictionary/domain/kanji_detail_model.dart';

class KanjiDetailScreen extends StatefulWidget {
  final String character;

  const KanjiDetailScreen({
    super.key,
    required this.character,
  });

  @override
  State<KanjiDetailScreen> createState() => _KanjiDetailScreenState();
}

class _KanjiDetailScreenState extends State<KanjiDetailScreen> {
  late Future<KanjiDetail?> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = DictionaryHelper.getKanjiDetail(widget.character);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: AppBar(
        title: Text(widget.character, style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 9, 12, 43),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<KanjiDetail?>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildMessage('Unable to load character details.');
          }

          final detail = snapshot.data;
          if (detail == null) {
            return _buildMessage('No character details found.');
          }

          return _buildDetails(detail);
        },
      ),
    );
  }

  Widget _buildDetails(KanjiDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildHeader(detail),
        _buildBadges(detail),
        _buildSection(detail, 'Meaning', ['kDefinition']),
        _buildSection(detail, 'Readings', [
          if (detail.properties.containsKey('kMandarin'))
            'kMandarin'
          else
            'kHanyuPinyin',
          'kCantonese',
          'kJapaneseOn',
          'kJapaneseKun',
        ]),
        _buildAdvanced(detail),
      ],
    );
  }

  Widget _buildHeader(KanjiDetail detail) {
    return Column(
      children: [
        Text(
          detail.codePointLabel,
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              detail.character,
              style: const TextStyle(
                fontSize: 96,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Center(
          child: Text(
            detail.firstProperty('kVietnamese') ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[300], fontSize: 18),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSection(KanjiDetail detail, String title, List<String> keys) {
    final rows = keys
        .map((key) => (key: key, values: detail.properties[key]))
        .where((row) => row.values != null && row.values!.isNotEmpty)
        .toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      color: const Color.fromARGB(255, 33, 36, 97),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            for (final row in rows) ...[
              Text(
                _labelFor(row.key),
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
              const SizedBox(height: 2),
              SelectableText(
                _displayValues(row.key, row.values!),
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
              if (row.key != rows.last.key) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadges(KanjiDetail detail) {
    final badges = <String>[
      if (detail.properties['kTotalStrokes']?.isNotEmpty == true)
        'Strokes: ${detail.properties['kTotalStrokes']!.join(' / ')}',
      if (detail.properties.containsKey('kGradeLevel'))
        'Grade ${detail.firstProperty('kGradeLevel')}',
      if (detail.properties.containsKey('kJoyoKanji')) 'Joyo kanji',
      if (detail.properties.containsKey('kJinmeiyoKanji')) 'Jinmeiyo kanji',
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final badge in badges)
            Chip(
              label: Text(badge),
              labelStyle: const TextStyle(color: Colors.white),
              backgroundColor: const Color.fromARGB(255, 65, 68, 130),
            ),
        ],
      ),
    );
  }

  Widget _buildVariants(KanjiDetail detail) {
    const keys = [
      'kSimplifiedVariant',
      'kTraditionalVariant',
      'kSemanticVariant',
    ];
    final rows = keys
        .map((key) => (key: key, values: detail.properties[key]))
        .where((row) => row.values != null && row.values!.isNotEmpty)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      color: const Color.fromARGB(255, 33, 36, 97),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Variants',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            for (final row in rows) ...[
              const SizedBox(height: 10),
              _buildVariantGrid(
                _labelFor(row.key),
                _variantCharacters(row.values!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantGrid(
    String label,
    List<({String character, String unicode})> variants,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final variant in variants)
              SizedBox(
                width: tileWidth,
                height: tileWidth / 0.82,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          KanjiDetailScreen(character: variant.character),
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 65, 68, 130),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          variant.unicode,
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          variant.character,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAdvanced(KanjiDetail detail) {
    final cangjie = detail.firstProperty('kCangjie');
    final fourCorner = detail.firstProperty('kFourCornerCode');
    final hanyu = detail.properties['kHanyuPinyin'];
    if (cangjie == null && fourCorner == null && hanyu == null) {
      return const SizedBox.shrink();
    }
    return Card(
      color: const Color.fromARGB(255, 33, 36, 97),
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        title: const Text('Advanced',
            style: TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (cangjie != null) _propertyValue('Cangjie', cangjie),
          if (fourCorner != null)
            _propertyValue('Four-corner code', fourCorner),
          if (hanyu != null)
            _propertyValue('Hanyu Pinyin', _parseHanyuPinyin(hanyu)),
        ],
      ),
    );
  }

  Widget _propertyValue(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title:
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      subtitle: SelectableText(value,
          style: const TextStyle(color: Colors.white, fontSize: 17)),
    );
  }

  String _parseHanyuPinyin(List<String> values) {
    return values
        .expand((value) => value.split(RegExp(r'\s+')))
        .map((value) => value.contains(':')
            ? value.substring(value.indexOf(':') + 1)
            : value)
        .join(' / ');
  }

  String _displayValues(String key, List<String> values) {
    return key == 'kHanyuPinyin'
        ? _parseHanyuPinyin(values)
        : values.join(' / ');
  }

  List<({String character, String unicode})> _variantCharacters(
    List<String> values,
  ) {
    final characters = <({String character, String unicode})>[];
    for (final value in values) {
      for (final match in RegExp(r'U\+([0-9A-Fa-f]+)').allMatches(value)) {
        final codePoint = int.tryParse(match.group(1)!, radix: 16);
        if (codePoint != null) {
          characters.add((
            character: String.fromCharCodes([codePoint]),
            unicode: 'U+${match.group(1)!.toUpperCase()}',
          ));
        }
      }
    }
    return characters;
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[300], fontSize: 18),
        ),
      ),
    );
  }

  String _labelFor(String key) {
    const labels = {
      'kDefinition': 'Definition',
      'kJapaneseOn': 'On readings',
      'kJapaneseKun': 'Kun readings',
      'kMandarin': 'Mandarin',
      'kCantonese': 'Cantonese',
      'kHanyuPinyin': 'Hanyu Pinyin',
      'kTotalStrokes': 'Total strokes',
      'kRSUnicode': 'Radical and stroke',
      'kGradeLevel': 'Grade level',
      'kJoyoKanji': 'Joyo kanji',
      'kJinmeiyoKanji': 'Jinmeiyo kanji',
      'kSimplifiedVariant': 'Simplified variant',
      'kTraditionalVariant': 'Traditional variant',
      'kSemanticVariant': 'Semantic variant',
      'kCangjie': 'Cangjie',
      'kFourCornerCode': 'Four-corner code',
    };
    return labels[key] ?? key;
  }
}
