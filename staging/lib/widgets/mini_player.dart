import 'package:flutter/material.dart';
import '../screens/player_screen.dart';
import '../services/artwork_colors.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import 'expressive.dart';
import 'track_art.dart';

/// Floating mini-player as a dynamic tonal card (PixelPlayer pattern):
/// a detached ~28dp card docked above the nav dock whose container color
/// is re-tinted from the current album art. Circular artwork, marquee
/// title/artist, circular tonal play + skip buttons, and a thin progress
/// line along the bottom edge. Tap or swipe up opens Now Playing.
class MiniPlayer extends StatefulWidget {
  final PlayerController pc;
  const MiniPlayer({super.key, required this.pc});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  /// Memoized per artwork URL: rebuilding on every position tick must
  /// NOT restart the tint future (it would flicker through the
  /// fallback color each second).
  Future<Color>? _tintFuture;
  String _tintUrl = '';

  PlayerController get pc => widget.pc;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(pc: pc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = pc.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    if (track.artworkUrl != _tintUrl) {
      _tintUrl = track.artworkUrl;
      _tintFuture = ArtworkColors.dominant(_tintUrl);
    }

    return FutureBuilder<Color>(
      future: _tintFuture,
      builder: (_, snap) {
        // Dynamic tint: the mini-player repaints itself in the current
        // artwork's tonal palette — the core anti-monochrome mechanism.
        final art = snap.data ?? ArtworkColors.fallback;
        final artScheme = VaniTheme.schemeForArtwork(art);
        final tint = artScheme.secondaryContainer;
        final onTint = artScheme.onSecondaryContainer;
        final pos = pc.position.inMilliseconds.toDouble();
        final dur = pc.duration?.inMilliseconds.toDouble() ?? 0;
        final progress =
            dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

        return GestureDetector(
          onTap: () => _open(context),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -300) _open(context);
          },
          child: Container(
            height: 78,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(9),
                        child: TrackArt(track,
                            size: 56, circular: true),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            MarqueeText(
                              key: ValueKey(
                                  'mini-title::${track.id}'),
                              text: track.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: onTint,
                                  fontSize: 14),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: onTint.withValues(alpha: 0.75),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // Prev/play/next: the full transport set lives here as
                      // well as on the Now Playing screen (v1.6.2
                      // regression guard).
                      TonalIconButton(
                        icon: Icons.skip_previous,
                        iconSize: 24,
                        size: 46,
                        backgroundColor: onTint.withValues(alpha: 0.16),
                        foregroundColor: onTint,
                        tooltip: 'Previous',
                        onPressed: pc.previous,
                      ),
                      const SizedBox(width: 4),
                      // Spinner only while genuinely loading (never while
                      // audio is playing — see the controller invariant).
                      if (pc.isLoading && !pc.isPlaying)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: onTint),
                          ),
                        )
                      else
                        TonalIconButton(
                          icon: pc.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          iconSize: 26,
                          size: 46,
                          backgroundColor: onTint.withValues(alpha: 0.16),
                          foregroundColor: onTint,
                          tooltip: pc.isPlaying ? 'Pause' : 'Play',
                          onPressed: pc.togglePlayPause,
                        ),
                      const SizedBox(width: 4),
                      TonalIconButton(
                        icon: Icons.skip_next,
                        iconSize: 24,
                        size: 46,
                        backgroundColor: onTint.withValues(alpha: 0.16),
                        foregroundColor: onTint,
                        tooltip: 'Next',
                        onPressed: pc.next,
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
                // Thin progress line along the card's bottom edge.
                SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor:
                        onTint.withValues(alpha: 0.15),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(scheme.primary),
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
