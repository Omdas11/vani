import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/lyrics_api.dart';
import '../services/player_controller.dart';

/// Bottom-sheet lyrics view, opened from the Now Playing screen.
///
/// Lookup is explicit: one lrclib.net request per sheet open (cache
/// first), never a prefetch loop. Synced lyrics auto-scroll and
/// highlight the current line as the track plays.
class LyricsSheet extends StatefulWidget {
  final PlayerController pc;
  const LyricsSheet({super.key, required this.pc});

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  Track? _track;
  LyricsResult? _result;
  bool _loading = true;
  String? _error;

  // Manual search override (for bad metadata).
  bool _editing = false;
  late TextEditingController _artistCtrl;
  late TextEditingController _titleCtrl;

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<int> _activeIndex = ValueNotifier(-1);
  double _viewportH = 400;
  static const double _lineH = 54;

  PlayerController get pc => widget.pc;

  @override
  void initState() {
    super.initState();
    _track = pc.currentTrack;
    _artistCtrl = TextEditingController(text: _track?.artist ?? '');
    _titleCtrl = TextEditingController(text: _track?.title ?? '');
    pc.addListener(_onPcTick);
    _load();
  }

  @override
  void dispose() {
    pc.removeListener(_onPcTick);
    _scroll.dispose();
    _activeIndex.dispose();
    _artistCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  /// If the track changed while the sheet is open, look up the new one.
  void _onPcTick() {
    final cur = pc.currentTrack;
    if (cur != _track) {
      _track = cur;
      _activeIndex.value = -1;
      _editing = false;
      _artistCtrl.text = cur?.artist ?? '';
      _titleCtrl.text = cur?.title ?? '';
      _load();
      return;
    }
    // Update the highlighted line from the playback position.
    final lines = _result?.synced;
    if (lines == null || lines.isEmpty) return;
    final pos = pc.position;
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != _activeIndex.value) {
      _activeIndex.value = idx;
      _scrollTo(idx);
    }
  }

  void _scrollTo(int idx) {
    if (!_scroll.hasClients || idx < 0) return;
    final target =
        (idx * _lineH - _viewportH / 2 + _lineH / 2).clamp(0.0, 1e9);
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(target.clamp(0.0, max));
  }

  Future<void> _load() async {
    final t = _track;
    if (t == null) {
      setState(() {
        _loading = false;
        _result = LyricsResult.notFound;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await pc.fetchLyrics(t);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
      // Jump to the current line once lyrics arrive.
      _onPcTick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Lyrics lookup failed';
      });
    }
  }

  /// Manual override: search again with user-corrected artist/title.
  Future<void> _searchOverride() async {
    final t = _track;
    if (t == null) return;
    final artist = _artistCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    if (artist.isEmpty || title.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _editing = false;
    });
    try {
      final r = await pc.fetchLyricsOverride(t, artist, title);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
      _onPcTick();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Lyrics lookup failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _track;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.lyrics_outlined,
                        color: Color(0xFF1DB954)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            t?.title ?? 'Lyrics',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          Text(
                            t != null
                                ? '${t.artist} · via lrclib.net'
                                : 'via lrclib.net',
                            style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _editing ? Icons.check : Icons.edit_outlined,
                        size: 20,
                      ),
                      tooltip: _editing
                          ? 'Search with these details'
                          : 'Fix artist/title and search again',
                      onPressed: () {
                        if (_editing) {
                          _searchOverride();
                        } else {
                          setState(() => _editing = true);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_editing) _overrideEditor(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1DB954)),
      );
    }
    if (_error != null) {
      return _empty(Icons.error_outline, _error!);
    }
    final r = _result;
    if (r == null || !r.found) {
      return _empty(Icons.lyrics_outlined,
          'No lyrics found for this track.\nLyrics come from the free lrclib.net database — not every song is listed.');
    }
    if (r.instrumental && r.synced.isEmpty && r.plain.isEmpty) {
      return _empty(Icons.music_note, 'This track is instrumental.');
    }
    if (r.synced.isNotEmpty) return _syncedView(r);
    return _plainView(r.plain);
  }

  Widget _overrideEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wrong song details? Fix them and search again.',
              style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _artistCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Artist',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchOverride(),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searchOverride,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Go'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _syncedView(LyricsResult r) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportH = constraints.maxHeight;
        return ValueListenableBuilder<int>(
          valueListenable: _activeIndex,
          builder: (_, active, __) {
            return ListView.builder(
              controller: _scroll,
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
              itemCount: r.synced.length,
              itemBuilder: (_, i) {
                final line = r.synced[i];
                final isActive = i == active;
                return SizedBox(
                  height: _lineH,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      line.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isActive ? 17 : 14.5,
                        height: 1.35,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive
                            ? const Color(0xFF1DB954)
                            : Colors.grey[400],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _plainView(String plain) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber[900],
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('UNSYNCED',
                style:
                    TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Text(plain,
              style: TextStyle(
                  color: Colors.grey[300], fontSize: 14.5, height: 1.7)),
        ],
      ),
    );
  }
}
