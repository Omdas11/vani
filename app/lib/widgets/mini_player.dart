import 'package:flutter/material.dart';
import '../screens/player_screen.dart';
import '../services/player_controller.dart';
import 'track_tile.dart';

/// Slim now-playing bar pinned above the bottom navigation.
class MiniPlayer extends StatelessWidget {
  final PlayerController pc;
  const MiniPlayer({super.key, required this.pc});

  @override
  Widget build(BuildContext context) {
    final track = pc.currentTrack;
    if (track == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerScreen(pc: pc)),
      ),
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: TrackArt(track, size: 52, radius: 4),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            if (pc.isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  pc.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  size: 36,
                  color: Colors.white,
                ),
                onPressed: pc.togglePlayPause,
              ),
          ],
        ),
      ),
    );
  }
}
