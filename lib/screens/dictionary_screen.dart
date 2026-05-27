import 'package:flutter/material.dart';
import 'dart:async';
import 'package:kian/features/dictionary/domain/dictionary_helper.dart';
import 'word_details_screen.dart';
import 'package:kian/widgets/reading_text.dart';
import 'package:kian/core/logger.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  DictionaryScreenState createState() => DictionaryScreenState();
}

class DictionaryScreenState extends State<DictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Timer? _debounceTimer;
  bool _isLoading = false;
  String _selectedLanguageTag = 'jp';

  static const List<_LanguageOption> _languageOptions = [
    _LanguageOption(label: 'Japanese', value: 'jp'),
    _LanguageOption(label: 'Chinese', value: 'cn'),
  ];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchDictionary(String query) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() {
          _results = [];
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        kLog('Searching for: "$query"');
        final results = await DictionaryHelper.searchAll(
          query.trim(),
          languageTag: _selectedLanguageTag,
        );

        kLog('Found ${results.length} results');

        if (mounted) {
          setState(() {
            _results = results;
            _isLoading = false;
          });
        }
      } catch (e) {
        kLog('FTS search error: $e');
        // Let the user know something went wrong
        setState(() {
          _isLoading = false;
          _results = [];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildResultsList(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        "Dictionary",
        style: TextStyle(color: Colors.white),
      ),
      backgroundColor: const Color.fromARGB(255, 9, 12, 43),
      elevation: 0,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 15.0, left: 25.0, right: 25.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: _buildBorder(Colors.grey),
                focusedBorder: _buildBorder(Colors.white),
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
              ),
              style: TextStyle(color: Colors.white),
              onChanged: _searchDictionary,
            ),
          ),
          const SizedBox(width: 12),
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey, width: 2),
              ),
              child: DropdownButton<String>(
                value: _selectedLanguageTag,
                dropdownColor: const Color.fromARGB(255, 9, 12, 43),
                iconEnabledColor: Colors.white,
                style: const TextStyle(color: Colors.white),
                items: _languageOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == _selectedLanguageTag) return;
                  setState(() {
                    _selectedLanguageTag = value;
                  });
                  _searchDictionary(_searchController.text);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _buildBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(15.0),
      borderSide: BorderSide(
        color: color,
        width: 2.0,
      ),
    );
  }

  Widget _buildResultsList() {
    return Expanded(
      child: _isLoading
          ? _buildLoadingIndicator()
          : _results.isEmpty
              ? _buildEmptyState()
              : _buildSearchResults(),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No results found',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildResultCard(_results[index]),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> entry) {
    final bool isReadingOnly = entry['headword'] == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 10.0),
      child: Card(
        color: const Color.fromARGB(43, 68, 186, 255),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0),
        ),
        child: InkWell(
          onTap: () {
            kLog('Selected entry: $entry');
            _showEntryDetails(context, entry);
          },
          borderRadius: BorderRadius.circular(25.0),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // For kana-only words, use a simpler display
                isReadingOnly
                    ? Text(
                        entry['reading'] ?? '',
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : FuriganaText(
                        kanji: entry['headword'] ?? '',
                        reading: entry['reading'] ?? '',
                        languageTag: entry['lang']?.toString() ?? '',
                        kanjiStyle: TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        readingStyle: TextStyle(
                          fontSize: 14,
                          color: Colors.lightBlueAccent,
                        ),
                      ),

                // Spacer between word and meaning
                const SizedBox(height: 10.0),

                // Meaning text
                Text(
                  entry['gloss'] ?? '',
                  style: TextStyle(color: Colors.grey[350]),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEntryDetails(BuildContext context, Map<String, dynamic> entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WordDetailsScreen(
          entry: entry,
          languageTag: entry['lang']?.toString() ?? _selectedLanguageTag,
        ),
      ),
    );
  }
}

class _LanguageOption {
  final String label;
  final String value;

  const _LanguageOption({required this.label, required this.value});
}
