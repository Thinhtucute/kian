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
        final db = await DatabaseHelper.getDatabase();
        final results = await db.rawQuery("""
        SELECT DISTINCT k.ent_seq, k.keb, r.reb, g.gloss
        FROM kanji_element k
        LEFT JOIN reading_element r ON k.ent_seq = r.ent_seq
        LEFT JOIN sense s ON k.ent_seq = s.ent_seq
        LEFT JOIN gloss g ON s.id = g.sense_id
        WHERE k.keb LIKE ? 
        OR r.reb LIKE ? 
        OR g.gloss LIKE ?
        GROUP BY k.ent_seq
        LIMIT 50
      """, ['%$query%', '%$query%', '%$query%']);

        if (mounted) {
          setState(() {
            _results = results;
            _isLoading = false;
          });
        }
      } catch (e) {
        print('Search error: $e');
        setState(() {
          _isLoading = false;
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
      padding: const EdgeInsets.all(8.0),
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
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Card(
        color: const Color.fromARGB(43, 68, 186, 255),
        child: ListTile(
          title: FuriganaText(
            kanji: entry['keb'] ?? entry['reb'],
            reading: entry['reb'] ?? '',
          ),
          subtitle: Center(
            child: Text(
              entry['gloss'] ?? '',
              style: TextStyle(color: Colors.grey),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          onTap: () => _showEntryDetails(context, entry),
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