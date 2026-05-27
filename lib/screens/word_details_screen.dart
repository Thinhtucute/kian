import 'package:flutter/material.dart';
import 'package:kian/features/fsrs/domain/fsrs_helper.dart';
import 'package:kian/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:kian/widgets/card_widget.dart';
import 'dart:async';
import 'package:kian/core/logger.dart';

class WordDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String languageTag;

  const WordDetailsScreen({
    super.key,
    required this.entry,
    String? languageTag,
  }) : languageTag = languageTag ?? 'jp';

  @override
  State<WordDetailsScreen> createState() => _WordDetailsScreenState();
}

class _WordDetailsScreenState extends State<WordDetailsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _meanings = [];
  List<Map<String, dynamic>> _examples = [];

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails() async {
    setState(() => _isLoading = true);

    try {
      final entryId = widget.entry['entry_id'] as int;
      final results = await Future.wait([
        _getMeanings(entryId),
        _getExampleSentences(entryId),
      ]);

      setState(() {
        _meanings = results[0];
        _examples = results[1];
        _isLoading = false;
      });
    } catch (e) {
      kLog('Error loading details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getMeanings(int entryId) async {
    return DictionaryRepository.getMeanings(
      entryId,
      languageTag: (widget.entry['lang']?.toString().isNotEmpty ?? false)
          ? widget.entry['lang'].toString()
          : widget.languageTag,
    );
  }

  Future<List<Map<String, dynamic>>> _getExampleSentences(int entryId) async {
    return DictionaryRepository.getExamples(
      entryId,
      languageTag: (widget.entry['lang']?.toString().isNotEmpty ?? false)
          ? widget.entry['lang'].toString()
          : widget.languageTag,
    );
  }

  Future<void> _addToFlashcards() async {
    try {
      final entryId = widget.entry['entry_id'] as int;
      final added = await FSRSHelper.addToFSRS(entryId);

      if (!mounted) return;

      if (added) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Word added to review'),
          backgroundColor: Colors.green,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Word is already added to review'),
          backgroundColor: Colors.amber,
        ));
      }
    } catch (e) {
      kLog('Error adding to flashcards: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to add word. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: AppBar(
        title: Text(
          widget.entry['headword'] ?? widget.entry['reading'],
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 9, 12, 43),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.add_card, color: Colors.amber),
            onPressed: _addToFlashcards,
            tooltip: 'Add to flashcards',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ReviewCardWidget(
              card: widget.entry,
              meanings: _meanings,
              examples: _examples,
              showAnswer: true,
              languageTag: widget.entry['lang']?.toString() ?? widget.languageTag,
            ),
    );
  }
}
