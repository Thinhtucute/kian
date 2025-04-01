import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/database_helper.dart';
import 'word_details.dart';
import '../widgets/furigana.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  _DictionaryScreenState createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Timer? _debounceTimer;
  bool _isLoading = false;

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
        print('Searching for: "${query}"');
        final db = await DatabaseHelper.getDatabase();
        String searchTerm = "${query.trim()}*";

        // Enhanced search with better ranking and deduplication
        final results = await db.rawQuery("""
      WITH combined_results AS (
        SELECT DISTINCT k.ent_seq, k.keb, r.reb, g.gloss,
               1 as rank,
               k.keb || r.reb as dedup_key
        FROM kanji_fts 
        JOIN kanji_element k ON kanji_fts.rowid = k.id
        LEFT JOIN reading_element r ON k.ent_seq = r.ent_seq
        LEFT JOIN sense s ON k.ent_seq = s.ent_seq
        LEFT JOIN gloss g ON s.id = g.sense_id
        WHERE kanji_fts.keb MATCH ?
        
        UNION
        
        SELECT DISTINCT k.ent_seq, k.keb, r.reb, g.gloss,
               2 as rank,
               k.keb || r.reb as dedup_key
        FROM reading_fts 
        JOIN reading_element r ON reading_fts.rowid = r.id
        LEFT JOIN kanji_element k ON r.ent_seq = k.ent_seq
        LEFT JOIN sense s ON r.ent_seq = s.ent_seq
        LEFT JOIN gloss g ON s.id = g.sense_id
        WHERE reading_fts.reb MATCH ?
        
        UNION
        
        SELECT DISTINCT k.ent_seq, k.keb, r.reb, g.gloss,
               CASE 
                 WHEN g.gloss LIKE ? THEN 3
                 WHEN g.gloss LIKE ? THEN 4
                 ELSE 5
               END as rank,
               k.keb || r.reb as dedup_key
        FROM gloss_fts 
        JOIN gloss g ON gloss_fts.rowid = g.id
        LEFT JOIN sense s ON g.sense_id = s.id
        LEFT JOIN kanji_element k ON s.ent_seq = k.ent_seq
        LEFT JOIN reading_element r ON s.ent_seq = r.ent_seq
        WHERE gloss_fts.gloss MATCH ?
      )

      SELECT ent_seq, keb, reb, gloss
      FROM (
        SELECT *, 
               ROW_NUMBER() OVER (PARTITION BY dedup_key ORDER BY rank ASC) as row_num
        FROM combined_results
      )
      WHERE row_num = 1
      ORDER BY rank ASC, LENGTH(gloss) ASC
      LIMIT 50
      """, [
          searchTerm,
          searchTerm,
          query.trim(),
          'to ${query.trim()}%',
          searchTerm
        ]);

        print('Found ${results.length} results');

        if (mounted) {
          setState(() {
            _results = results;
            _isLoading = false;
          });
        }
      } catch (e) {
        print('FTS search error: $e');
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 10.0),
      child: Card(
        color: const Color.fromARGB(43, 68, 186, 255),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0),
        ),
        child: InkWell(
          onTap: () => _showEntryDetails(context, entry),
          borderRadius: BorderRadius.circular(25.0),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Furigana text (kanji + reading)
                FuriganaText(
                  kanji: entry['keb'] ?? entry['reb'],
                  reading: entry['reb'] ?? '',
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
        builder: (context) => WordDetailsScreen(entry: entry),
      ),
    );
  }
}
