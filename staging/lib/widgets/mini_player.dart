import 'package:flutter/material.dart';
import '../screens/player_screen.dart';
import '../services/player_controller.dart';
import 'glass_panel.dart';
import 'track_tile.dart';

/// Floating mini-player card (Namida pattern): a detached rounded card
/// with frosted-glass blur, artwork thumb, title/artist, transport
/// buttons, and a thin progress line along its bottom edge.
/// Tap or swipe up opens the full Now Playing screen.
class MiniPlayer extends StatelessWidget {
  final PlayerController pc;
  const MiniPlayer({super.key, required this.pc});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(pc: pc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = pc.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final pos = pc.position.inMilliseconds.toDouble();
    final dur = pc.duration?.inMilliseconds.toDouble() ?? 0;
    final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () => _open(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -300) _open(context);
      },
      child: GlassPanel(
        radius: 20,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 76,
          child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TrackArt(track, size: 56, radius: 12),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous, size: 28),
                        color: Colors.white70,
                        onPressed: pc.previous,
                      ),
                      // Spinner only while genuinely loading (never while
                      // audio is playing — see the controller invariant).
                      if (pc.isLoading && !pc.isPlaying)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            pc.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            size: 40,
                            color: Colors.white,
                          ),
                          onPressed: pc.togglePlayPause,
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                // Thin progress line along the card's bottom edge
                // (Auxio + Namida consensus pattern).
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF1DB954)),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
