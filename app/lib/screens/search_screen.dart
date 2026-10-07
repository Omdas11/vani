import 'dart:async';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../widgets/track_tile.dart';

/// Search the Internet Archive's CC0/CC-BY audio catalog, with
/// debounced live results as the user types.
class SearchScreen extends StatefulWidget {
  final PlayerController pc;
  const SearchScreen({super.key, required this.pc});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Future<List<Track>>? _results;
  bool _searched = false;
  Timer? _debounce;

  void _runQuery(String q) {
    if (q.isEmpty) {
      setState(() {
        _searched = false;
        _results = null;
      });
      return;
    }
    setState(() {
      _searched = true;
      _results = widget.pc.api.search(q, rows: 30);
    });
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _runQuery(text.trim()),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (q) {
                _debounce?.cancel();
                _runQuery(q.trim());
                FocusScope.of(context).unfocus();
              },
              decoration: InputDecoration(
                hintText: 'Artists, tracks, moods…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _debounce?.cancel();
                    _ctrl.clear();
                    setState(() {
                      _searched = false;
                      _results = null;
                    });
                  },
                ),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: !_searched
                ? Center(
                    child: Text(
                      'Search 60,000+ open-licensed tracks\nfrom the Internet Archive.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  )
                : FutureBuilder<List<Track>>(
                    future: _results,
                    builder: (context, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final tracks = snap.data ?? [];
                      if (tracks.isEmpty) {
                        return const Center(
                            child: Text('No results. Try another search.'));
                      }
                      return ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (_, i) => TrackTile(
                          track: tracks[i],
                          contextQueue: tracks,
                          indexInQueue: i,
                          pc: widget.pc,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
