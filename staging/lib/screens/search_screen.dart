import 'dart:async';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../widgets/expressive.dart';
import '../widgets/nav.dart';
import '../widgets/track_tile.dart';

/// Search the Internet Archive's CC0/CC-BY audio catalog, with
/// debounced live results as the user types. M3 Expressive restyle:
/// display header + a real M3 SearchBar pill.
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
    if (widget.pc.settings.iaEnabled) {
      setState(() {
        _searched = true;
        _results = widget.pc.api.search(q, rows: 30);
      });
    } else {
      // IA collections off: search the user's own music instead.
      final query = q.toLowerCase();
      final mine = [
        ...widget.pc.driveTracks,
        ...widget.pc.localTracks
      ].where((t) =>
          t.title.toLowerCase().contains(query) ||
          t.artist.toLowerCase().contains(query));
      setState(() {
        _searched = true;
        _results = Future.value(mine.toList());
      });
    }
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Column(
        children: [
          DisplayHeader(
            title: 'Search',
            subtitle: 'Open-licensed music, artists and moods',
            actions: const [SettingsGearButton()],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _ctrl,
              hintText: 'Artists, tracks, moods…',
              leading: const Icon(Icons.search),
              trailing: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(
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
              ],
              onChanged: (text) {
                setState(() {}); // refresh the clear button
                _onChanged(text);
              },
              onSubmitted: (q) {
                _debounce?.cancel();
                _runQuery(q.trim());
                FocusScope.of(context).unfocus();
              },
            ),
          ),
          Expanded(
            child: !_searched
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search,
                              size: 56,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.6)),
                          const SizedBox(height: 12),
                          Text(
                            widget.pc.settings.iaEnabled
                                ? 'Search 60,000+ open-licensed tracks\nfrom the Internet Archive.'
                                : 'Internet Archive search is off.\nSearching your Drive songs and phone imports.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 14,
                                height: 1.5),
                          ),
                        ],
                      ),
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
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              widget.pc.settings.iaEnabled
                                  ? 'Not found on Internet Archive — add it via My Drive.'
                                  : 'No matches in your music.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color:
                                      scheme.onSurfaceVariant),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
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
