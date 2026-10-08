import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/lyrics_api.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import 'wavy_slider.dart';

/// Bottom-sheet lyrics view, opened from the Now Playing screen
/// (M3 Expressive restyle, v1.6.0).
///
/// Lookup is explicit: one lrclib.net request per sheet open (cache
/// first), never a prefetch loop. Synced lyrics auto-scroll and
/// highlight the current line as the track plays. Expressive elements:
/// large pill Synced/Static segmented buttons, a floating squircle
/// play/pause over the text, and a slim wavy-transport pill pinned at
/// the bottom.
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

  /// 0 = synced, 1 = static. When only one kind exists the other is
  /// disabled.
  int _mode = 0;

  /// Human label for where the current lyrics came from.
  String _sourceLabel(LyricsResult? r) {
    final artistBit =
        _track != null ? '${_track!.artist} · ' : '';
    switch (r?.source) {
      case 'kugou':
        return '${artistBit}via KuGou';
      case 'web':
        return '${artistBit}via web search (fallback)';
      default:
        return '${artistBit}via lrclib.net';
    }
  }

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
      _mode = 0;
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
        // Default to whichever kind actually exists.
        if (r.synced.isEmpty && r.plain.isNotEmpty) _mode = 1;
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
        if (r.synced.isEmpty && r.plain.isNotEmpty) _mode = 1;
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = _track;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = _result;
    final hasSynced = r != null && r.synced.isNotEmpty;
    final hasPlain = r != null && r.plain.isNotEmpty;
    final showBody = !_loading &&
        _error == null &&
        r != null &&
        r.found &&
        !(r.instrumental && !hasSynced && !hasPlain);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                t?.title ?? 'Lyrics',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.w700),
                              ),
                              Text(
                                _sourceLabel(_result),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(
                                        color: scheme
                                            .onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _editing
                                ? Icons.check
                                : Icons.edit_outlined,
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
                  if (_editing) _overrideEditor(),
                  // Expressive segmented pill: Synced / Static.
                  if (showBody && (hasSynced || hasPlain))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          24, 4, 24, 8),
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment<int>(
                            value: 0,
                            enabled: hasSynced,
                            label: const Text('Synced'),
                            icon: const Icon(
                                Icons.music_note_outlined,
                                size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 1,
                            enabled: hasPlain,
                            label: const Text('Static'),
                            icon: const Icon(
                                Icons.notes_outlined,
                                size: 16),
                          ),
                        ],
                        selected: {_mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _mode = s.first),
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                        ),
                      ),
                    ),
                  Expanded(child: _body()),
                  // Slim wavy-transport pill pinned at the bottom.
                  if (showBody) _transportPill(),
                ],
              ),
              // Floating squircle play/pause over the lyrics.
              if (showBody)
                Positioned(
                  right: 24,
                  bottom: 96,
                  child: FloatingActionButton.large(
                    heroTag: 'lyrics_play',
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor:
                        scheme.onSecondaryContainer,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            VaniTheme.radiiOf(context))),
                    tooltip:
                        pc.isPlaying ? 'Pause' : 'Play',
                    onPressed: pc.togglePlayPause,
                    child: Icon(
                        pc.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        size: 36),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mini transport: time labels + small wavy slider in a dark pill.
  Widget _transportPill() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pos = pc.position;
    final dur = pc.duration ?? Duration.zero;
    final maxMs =
        dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Text(_fmt(pos),
                style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant)),
            Expanded(
              child: WavySlider(
                value:
                    pos.inMilliseconds.toDouble().clamp(0.0, maxMs),
                max: maxMs,
                height: 36,
                animate: pc.isPlaying,
                onChangeEnd: (v) =>
                    pc.seek(Duration(milliseconds: v.round())),
              ),
            ),
            Text(_fmt(dur),
                style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _empty(Icons.error_outline, _error!);
    }
    final r = _result;
    if (r == null || !r.found) {
      return _empty(Icons.lyrics_outlined,
          'No lyrics found for this track.\nSearched lrclib, KuGou and the web — not every song is listed anywhere.');
    }
    if (r.instrumental && r.synced.isEmpty && r.plain.isEmpty) {
      return _empty(Icons.music_note, 'This track is instrumental.');
    }
    if (_mode == 0 && r.synced.isNotEmpty) return _syncedView(r);
    if (r.plain.isNotEmpty) return _plainView(r.plain);
    if (r.synced.isNotEmpty) return _syncedView(r);
    return _empty(Icons.lyrics_outlined, 'No lyrics found.');
  }

  Widget _overrideEditor() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wrong song details? Fix them and search again.',
              style: TextStyle(
                  color: scheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _artistCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Artist',
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
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searchOverride,
                child: const Text('Go'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _syncedView(LyricsResult r) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportH = constraints.maxHeight;
        return ValueListenableBuilder<int>(
          valueListenable: _activeIndex,
          builder: (_, active, __) {
            return ListView.builder(
              controller: _scroll,
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
              itemCount: r.synced.length,
              itemBuilder: (_, i) {
                final line = r.synced[i];
                final isActive = i == active;
                return SizedBox(
                  height: _lineH,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedDefaultTextStyle(
                      duration:
                          const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: isActive ? 19 : 15,
                        height: 1.35,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isActive
                            ? scheme.primary
                            : scheme.onSurface
                                .withValues(alpha: 0.42),
                      ),
                      child: Text(
                        line.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('UNSYNCED',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: scheme.onTertiaryContainer)),
          ),
          const SizedBox(height: 12),
          Text(plain,
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 15.5,
                  height: 1.7)),
        ],
      ),
    );
  }
}
