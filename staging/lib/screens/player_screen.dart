import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/artwork_colors.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import '../widgets/expressive.dart';
import '../widgets/lyrics_sheet.dart';
import '../widgets/track_art.dart';
import '../widgets/track_tile.dart';
import '../widgets/vinyl_record.dart';
import '../widgets/wavy_slider.dart';

/// Full-screen now-playing view (M3 Expressive restyle, v1.6.0).
///
/// Kept signature pieces, restyled: the spinning vinyl record with its
/// holographic shimmer sweep, the cover-art ambient glow, and the
/// frosted-glass control panels. New expressive elements:
/// - tonal circular collapse button + a pill tonal group (lyrics, queue)
///   in the top bar (PixelPlayer pattern);
/// - the wavy progress slider (played portion is a sine wave that
///   flattens while dragging);
/// - a large filled play/pause hero flanked by circular tonal prev/next;
/// - shuffle / repeat / like grouped in one dark pill container;
/// - a reorderable queue sheet behind the queue icon.
class PlayerScreen extends StatefulWidget {
  final PlayerController pc;
  const PlayerScreen({super.key, required this.pc});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  double? _dragMs; // non-null while the user is dragging the seek bar
  late final AnimationController _spin;
  late final AnimationController _shimmer;

  // Lyrics preview state (auto-fetch when enabled in Settings).
  Track? _lyricsTrack;
  String? _lyricsPreview; // null = not fetched yet, '' = none found
  bool _lyricsLoading = false;

  @override
  void initState() {
    super.initState();
    // ~14s per revolution: a graceful vinyl feel rather than literal 33rpm.
    _spin = AnimationController(
        vsync: this, duration: const Duration(seconds: 14));
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(seconds: 9));
    widget.pc.addListener(_syncVinyl);
    widget.pc.addListener(_maybeAutoLyrics);
    _syncVinyl();
    _maybeAutoLyrics();
  }

  void _syncVinyl() {
    if (widget.pc.isPlaying) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _spin.stop();
      _shimmer.stop();
    }
  }

  void _maybeAutoLyrics() {
    final track = widget.pc.currentTrack;
    if (track == null || track == _lyricsTrack) return;
    _lyricsTrack = track;
    _lyricsPreview = null;
    _lyricsLoading = false;
    if (widget.pc.settings.autoLoadLyrics) {
      _fetchLyricsPreview(track);
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchLyricsPreview(Track track) async {
    _lyricsLoading = true;
    try {
      final r = await widget.pc.fetchLyrics(track);
      if (!mounted || widget.pc.currentTrack != track) return;
      setState(() {
        _lyricsLoading = false;
        if (!r.found) {
          _lyricsPreview = '';
        } else if (r.synced.isNotEmpty) {
          _lyricsPreview =
              r.synced.take(2).map((l) => l.text).join('\n');
        } else {
          _lyricsPreview = r.plain.split('\n').take(2).join('\n').trim();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _lyricsLoading = false);
    }
  }

  @override
  void dispose() {
    widget.pc.removeListener(_syncVinyl);
    widget.pc.removeListener(_maybeAutoLyrics);
    _spin.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _openLyrics(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LyricsSheet(pc: widget.pc),
    );
  }

  void _openQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QueueSheet(pc: widget.pc),
    );
  }

  String _attribution(Track track) {
    if (track.isLocalTrack) {
      return '"${track.title}" · from this phone';
    }
    if (track.isDriveTrack) {
      return '"${track.title}" · from your Google Drive';
    }
    return track.needsAttribution
        ? '"${track.title}" by ${track.artist} · ${track.license} · via Internet Archive'
        : '"${track.title}" · ${track.license} · via Internet Archive';
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.pc;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screenW = MediaQuery.of(context).size.width;
    // Complete circle, large and centered (v1.4.0: edge-crop reverted).
    final vinylSize = (screenW * 0.86).clamp(280.0, 420.0);
    return AnimatedBuilder(
      animation: pc,
      builder: (_, __) {
        final track = pc.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final pos = pc.position;
        final dur = pc.duration ?? Duration.zero;
        final maxMs =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final sliderValue =
            (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
        final dlProgress = pc.downloadProgressOf(track);

        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: TonalIconButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Close player',
                size: 44,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: Text('Now Playing',
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
            centerTitle: true,
            actions: [
              // Pill tonal group: lyrics + queue shortcuts.
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.lyrics_outlined, size: 20),
                      tooltip: 'Lyrics',
                      color: scheme.onSecondaryContainer,
                      onPressed: () => _openLyrics(context),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.queue_music_outlined, size: 20),
                      tooltip: 'Queue',
                      color: scheme.onSecondaryContainer,
                      onPressed: () => _openQueue(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // ---- Vinyl stage: ambient glow + full centered disc ----
              SizedBox(
                height: vinylSize * 1.04,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _AmbientGlow(
                          pc: pc, artworkUrl: track.artworkUrl),
                    ),
                    Center(
                      child: VinylRecord(
                        artworkUrl: track.artworkUrl,
                        rotation: _spin,
                        shimmer: _shimmer,
                        size: vinylSize,
                      ),
                    ),
                  ],
                ),
              ),
              // ---- Everything else scrolls ----
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            MarqueeText(
                              key: ValueKey(
                                  'np-title::${track.id}'),
                              text: track.title,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                        color:
                                            scheme.onSurfaceVariant)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                LicenseBadge(track),
                                if (track.isDownloaded) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3),
                                    decoration: BoxDecoration(
                                      color: scheme.tertiaryContainer,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: Text('OFFLINE',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: scheme
                                                .onTertiaryContainer)),
                                  ),
                                ],
                              ],
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 8),
                              child: Text(
                                _attribution(track),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(
                                        color:
                                            scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ---- Tappable lyrics preview ----
                    _lyricsPreviewCard(context, track),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                        child: Column(
                          children: [
                            if (pc.error != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 8, left: 12, right: 12),
                                child: Text(pc.error!,
                                    style: TextStyle(
                                        color: scheme.error)),
                              ),
                            // Wavy expressive seek bar.
                            WavySlider(
                              value: sliderValue,
                              max: maxMs,
                              animate: pc.isPlaying,
                              onChangeStart: (v) =>
                                  setState(() => _dragMs = v),
                              onChanged: (v) =>
                                  setState(() => _dragMs = v),
                              onChangeEnd: (v) {
                                pc.seek(Duration(
                                    milliseconds: v.round()));
                                setState(() => _dragMs = null);
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      _fmt(_dragMs != null
                                          ? Duration(
                                              milliseconds: _dragMs!
                                                  .round())
                                          : pos),
                                      style: theme
                                          .textTheme.labelMedium
                                          ?.copyWith(
                                              color: scheme
                                                  .onSurfaceVariant)),
                                  Text(_fmt(dur),
                                      style: theme
                                          .textTheme.labelMedium
                                          ?.copyWith(
                                              color: scheme
                                                  .onSurfaceVariant)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                TonalIconButton(
                                  icon: Icons.skip_previous,
                                  iconSize: 30,
                                  size: 60,
                                  tooltip: 'Previous',
                                  onPressed: pc.previous,
                                ),
                                const SizedBox(width: 12),
                                // Loading spinner only when NOT playing: the
                                // controller guarantees isLoading is cleared
                                // the moment audio plays, so a stuck spinner
                                // can never cover the play/pause button.
                                pc.isLoading && !pc.isPlaying
                                    ? SizedBox(
                                        width: 84,
                                        height: 84,
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.all(24),
                                          child:
                                              CircularProgressIndicator(
                                                  color: scheme
                                                      .primary),
                                        ),
                                      )
                                    : Stack(
                                        alignment:
                                            Alignment.center,
                                        children: [
                                          // Holographic ring rotating behind the play button.
                                          // v1.5.0 perf: repaint-isolated.
                                          RepaintBoundary(
                                            child: AnimatedBuilder(
                                              animation: _shimmer,
                                              builder: (_, __) =>
                                                  Container(
                                                width: 96,
                                                height: 96,
                                                decoration:
                                                    BoxDecoration(
                                                  shape:
                                                      BoxShape.circle,
                                                  gradient:
                                                      SweepGradient(
                                                    transform:
                                                        GradientRotation(
                                                            _shimmer.value *
                                                                6.28318),
                                                    colors: const [
                                                      Color(0x001DB954),
                                                      Color(0x551DB954),
                                                      Color(0x55A47FE8),
                                                      Color(0x555EC8E8),
                                                      Color(0x001DB954),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Hero play/pause: large filled circle.
                                          Material(
                                            color: scheme.primary,
                                            shape:
                                                const CircleBorder(),
                                            child: InkWell(
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap:
                                                  pc.togglePlayPause,
                                              child: SizedBox(
                                                width: 76,
                                                height: 76,
                                                child: Icon(
                                                  pc.isPlaying
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                  size: 40,
                                                  color: scheme
                                                      .onPrimary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                const SizedBox(width: 12),
                                TonalIconButton(
                                  icon: Icons.skip_next,
                                  iconSize: 30,
                                  size: 60,
                                  tooltip: 'Next',
                                  onPressed: () => pc.next(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Secondary controls pill: shuffle / repeat /
                            // like grouped in one dark container.
                            Container(
                              decoration: BoxDecoration(
                                color:
                                    scheme.surfaceContainerHighest,
                                borderRadius:
                                    BorderRadius.circular(999),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.shuffle,
                                        color: pc.shuffle
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant),
                                    tooltip:
                                        'Shuffle ${pc.shuffle ? 'on' : 'off'}',
                                    onPressed: pc.toggleShuffle,
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      pc.loopMode == 2
                                          ? Icons.repeat_one
                                          : Icons.repeat,
                                      color: pc.loopMode == 0
                                          ? scheme.onSurfaceVariant
                                          : scheme.primary,
                                    ),
                                    tooltip: 'Repeat',
                                    onPressed: pc.cycleLoop,
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      pc.isLiked(track)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: pc.isLiked(track)
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    tooltip: pc.isLiked(track)
                                        ? 'Unlike'
                                        : 'Like',
                                    onPressed: () =>
                                        pc.toggleLike(track),
                                  ),
                                  _downloadPillButton(
                                      context, pc, track, dlProgress),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (pc.upNext.isNotEmpty) ...[
                      Row(
                        children: [
                          Text('Up next',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.w700)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _openQueue(context),
                            child: const Text('Open queue'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...pc.upNext.map((t) {
                        final qi = pc.queue.indexOf(t);
                        return TrackTile(
                          track: t,
                          contextQueue: pc.queue,
                          indexInQueue: qi,
                          pc: pc,
                          onTapOverride: () =>
                              pc.jumpToQueueIndex(qi),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _downloadPillButton(BuildContext context, PlayerController pc,
      Track track, double? dlProgress) {
    final scheme = Theme.of(context).colorScheme;
    if (track.isDownloaded) {
      return IconButton(
        icon: Icon(Icons.download_done, color: scheme.primary),
        tooltip: 'Downloaded',
        onPressed: null,
      );
    }
    if (pc.isDownloading(track)) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: dlProgress,
            strokeWidth: 2.5,
            color: scheme.primary,
          ),
        ),
      );
    }
    return IconButton(
      icon: Icon(Icons.download_outlined,
          color: scheme.onSurfaceVariant),
      tooltip: 'Download for offline',
      onPressed: () => pc.downloadTrack(track),
    );
  }

  /// Tappable lyrics preview under the track info. Opens the full sheet.
  Widget _lyricsPreviewCard(BuildContext context, Track track) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String label;
    IconData icon;
    if (_lyricsLoading) {
      label = 'Looking up lyrics…';
      icon = Icons.hourglass_empty;
    } else if (_lyricsPreview == null) {
      label = 'Tap to look up lyrics';
      icon = Icons.lyrics_outlined;
    } else if (_lyricsPreview!.isEmpty) {
      label = 'No lyrics found — tap to search manually';
      icon = Icons.lyrics_outlined;
    } else {
      label = _lyricsPreview!;
      icon = Icons.lyrics;
    }
    return Card(
      child: InkWell(
        borderRadius:
            BorderRadius.circular(VaniTheme.radiiOf(context)),
        onTap: () => _openLyrics(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _lyricsPreview != null &&
                            _lyricsPreview!.isNotEmpty
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: scheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reorderable queue sheet: the current track pinned at top, up-next
/// items draggable (drag handle), tap to jump, swipe to remove.
class _QueueSheet extends StatelessWidget {
  final PlayerController pc;
  const _QueueSheet({required this.pc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: pc,
      builder: (_, __) {
        final upNext = pc.upNext;
        final base = pc.currentPlayPos + 1;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Up next',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.w700)),
                            Text(
                                '${upNext.length} track${upNext.length == 1 ? '' : 's'} · drag to reorder',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(
                                        color: theme.colorScheme
                                            .onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close queue',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: upNext.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing queued after this track.',
                            style: TextStyle(
                                color: theme.colorScheme
                                    .onSurfaceVariant),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          itemCount: upNext.length,
                          onReorderItem:
                              (oldI, newI) => pc.moveUpNextItem(
                                  base + oldI, base + newI),
                          itemBuilder: (_, i) {
                            final t = upNext[i];
                            final qi = pc.queue.indexOf(t);
                            return Dismissible(
                              key: ValueKey(
                                  'q::${t.id}::${t.title}::$i'),
                              direction:
                                  DismissDirection.endToStart,
                              background: Container(
                                color: theme.colorScheme.errorContainer,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(
                                    right: 24),
                                child: Icon(Icons.delete_outline,
                                    color: theme.colorScheme
                                        .onErrorContainer),
                              ),
                              onDismissed: (_) =>
                                  pc.removeUpNextItem(base + i),
                              child: ListTile(
                                leading: TrackArt(t,
                                    size: 48, radius: 12),
                                title: Text(t.title,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis),
                                subtitle: Text(t.artist,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis),
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(
                                      Icons.drag_handle),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  pc.jumpToQueueIndex(qi);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Soft ambient glow behind the vinyl, tinted by the cover art's
/// dominant color. Cross-fades between tracks over ~1.2s.
class _AmbientGlow extends StatefulWidget {
  final PlayerController pc;
  final String artworkUrl;
  const _AmbientGlow({required this.pc, required this.artworkUrl});

  @override
  State<_AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<_AmbientGlow> {
  Color _from = ArtworkColors.fallback;
  Color _to = ArtworkColors.fallback;
  String _url = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _AmbientGlow old) {
    super.didUpdateWidget(old);
    if (widget.artworkUrl != old.artworkUrl) _refresh();
  }

  Future<void> _refresh() async {
    final url = widget.artworkUrl;
    if (url == _url) return;
    _url = url;
    final c = await ArtworkColors.dominant(url);
    if (!mounted || _url != widget.artworkUrl) return;
    setState(() {
      _from = _to;
      _to = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      key: ValueKey(_to),
      tween: ColorTween(begin: _from, end: _to),
      duration: const Duration(milliseconds: 1200),
      builder: (_, color, __) {
        final c = color ?? _to;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.25, 0.4),
              radius: 0.9,
              colors: [
                c.withValues(alpha: 0.38),
                c.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        );
      },
    );
  }
}
