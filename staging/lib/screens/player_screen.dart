import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/artwork_colors.dart';
import '../services/player_controller.dart';
import '../widgets/glass_panel.dart';
import '../widgets/lyrics_sheet.dart';
import '../widgets/track_tile.dart';
import '../widgets/vinyl_record.dart';

/// Full-screen now-playing view.
///
/// v1.4.0 layout: the vinyl is a complete circle again, large and centered
/// (the v1.3.0 edge-crop read as broken on-device). Behind it, an ambient
/// glow derived from the cover art's dominant color fades between tracks.
/// Controls and track info sit in frosted-glass panels. The vinyl spins
/// only while audio is playing; the holographic shimmer sweep is kept.
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
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LyricsSheet(pc: widget.pc),
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

  /// Frosted-glass panel (shared widget — see glass_panel.dart).
  Widget _glass({required Widget child, double radius = 20}) {
    return GlassPanel(radius: radius, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.pc;
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
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Now Playing',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.lyrics_outlined),
                tooltip: 'Lyrics',
                onPressed: () => _openLyrics(context),
              ),
              IconButton(
                icon: Icon(
                  pc.isLiked(track)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: pc.isLiked(track)
                      ? const Color(0xFF1DB954)
                      : null,
                ),
                onPressed: () => pc.toggleLike(track),
              ),
              _downloadButton(pc, track, dlProgress),
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
                    _glass(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2),
                          const SizedBox(height: 4),
                          Text(track.artist,
                              style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 15)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              LicenseBadge(track),
                              if (track.isDownloaded) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[900],
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: const Text('OFFLINE',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 6),
                            child: Text(
                              _attribution(track),
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ---- Tappable lyrics preview ----
                    _lyricsPreviewCard(context, track),
                    const SizedBox(height: 12),
                    _glass(
                      child: Column(
                        children: [
                          if (pc.error != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8),
                              child: Text(pc.error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent)),
                            ),
                          Slider(
                            value: sliderValue,
                            max: maxMs,
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
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  _fmt(_dragMs != null
                                      ? Duration(
                                          milliseconds:
                                              _dragMs!.round())
                                      : pos),
                                  style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12)),
                              Text(_fmt(dur),
                                  style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle,
                                    color: pc.shuffle
                                        ? const Color(0xFF1DB954)
                                        : Colors.grey),
                                iconSize: 26,
                                onPressed: pc.toggleShuffle,
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.skip_previous),
                                iconSize: 40,
                                onPressed: pc.previous,
                              ),
                              // Loading spinner only when NOT playing: the
                              // controller guarantees isLoading is cleared
                              // the moment audio plays, so a stuck spinner
                              // can never cover the play/pause button.
                              pc.isLoading && !pc.isPlaying
                                  ? const SizedBox(
                                      width: 64,
                                      height: 64,
                                      child: Padding(
                                        padding:
                                            EdgeInsets.all(16),
                                        child:
                                            CircularProgressIndicator(
                                                color: Color(
                                                    0xFF1DB954)),
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
                                              width: 78,
                                              height: 78,
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
                                        IconButton(
                                          icon: Icon(pc.isPlaying
                                              ? Icons
                                                  .pause_circle_filled
                                              : Icons
                                                  .play_circle_filled),
                                          iconSize: 64,
                                          color: Colors.white,
                                          onPressed:
                                              pc.togglePlayPause,
                                        ),
                                      ],
                                    ),
                              IconButton(
                                icon:
                                    const Icon(Icons.skip_next),
                                iconSize: 40,
                                onPressed: () => pc.next(),
                              ),
                              IconButton(
                                icon: Icon(
                                  pc.loopMode == 2
                                      ? Icons.repeat_one
                                      : Icons.repeat,
                                  color: pc.loopMode == 0
                                      ? Colors.grey
                                      : const Color(0xFF1DB954),
                                ),
                                iconSize: 26,
                                onPressed: pc.cycleLoop,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (pc.upNext.isNotEmpty) ...[
                      const Text('Up next',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
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

  /// Tappable lyrics preview under the track info. Opens the full sheet.
  Widget _lyricsPreviewCard(BuildContext context, Track track) {
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
    return GestureDetector(
      onTap: () => _openLyrics(context),
      child: _glass(
        radius: 14,
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1DB954), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _lyricsPreview != null &&
                          _lyricsPreview!.isNotEmpty
                      ? Colors.grey[200]
                      : Colors.grey[500],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _downloadButton(
      PlayerController pc, Track track, double? dlProgress) {
    if (track.isDownloaded) {
      return const IconButton(
        icon: Icon(Icons.download_done),
        color: Color(0xFF1DB954),
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
            color: const Color(0xFF1DB954),
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.download_outlined),
      onPressed: () => pc.downloadTrack(track),
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
