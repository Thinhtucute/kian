import 'package:flutter/material.dart';
import 'package:kian/features/fsrs/domain/fsrs_helper.dart';
import 'package:kian/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:kian/features/dictionary/domain/entry_model.dart';
import 'package:kian/features/dictionary/domain/example_model.dart';
import 'package:kian/features/dictionary/domain/sense_model.dart';
import 'package:kian/widgets/card_widget.dart';
import 'dart:async';
import 'package:kian/core/logger.dart';

class WordDetailsScreen extends StatefulWidget {
  final Entry entry;
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
  List<Sense> _meanings = [];
  List<Example> _examples = [];

  List<Map<String, dynamic>> _meaningsAsMaps() =>
      _meanings.map((meaning) => meaning.toMap()).toList();

  List<Map<String, dynamic>> _examplesAsMaps() =>
      _examples.map((example) => example.toMap()).toList();

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails() async {
    setState(() => _isLoading = true);

    try {
      final entryId = widget.entry.entryId;
      final meanings = await _getMeanings(entryId);
      final examples = await _getExampleSentences(entryId);

      setState(() {
        _meanings = meanings;
        _examples = examples;
        _isLoading = false;
      });
    } catch (e) {
      kLog('Error loading details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Sense>> _getMeanings(int entryId) async {
    return DictionaryRepository.getMeaningsModels(
      entryId,
      languageTag: widget.entry.lang.isNotEmpty
          ? widget.entry.lang
          : widget.languageTag,
    );
  }

  Future<List<Example>> _getExampleSentences(int entryId) async {
    return DictionaryRepository.getExamplesModels(
      entryId,
      languageTag: widget.entry.lang.isNotEmpty
          ? widget.entry.lang
          : widget.languageTag,
    );
  }

  Future<void> _addToFlashcards() async {
    try {
      final entryId = widget.entry.entryId;
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
          widget.entry.displayHeadword.isNotEmpty
              ? widget.entry.displayHeadword
              : widget.entry.displayReading,
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
              languageTag: widget.entry.lang.isNotEmpty ? widget.entry.lang : widget.languageTag,
            ),
    );
  }
}
