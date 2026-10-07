import 'package:flutter/material.dart';
import '../services/player_controller.dart';
import '../widgets/track_tile.dart';

/// Full-screen now-playing view: artwork, seek bar, transport controls,
/// shuffle/repeat, like/download actions, attribution, and the up-next queue.
class PlayerScreen extends StatefulWidget {
  final PlayerController pc;
  const PlayerScreen({super.key, required this.pc});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragMs; // non-null while the user is dragging the seek bar

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.pc;
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
            icon: Icon(
              pc.isLiked(track) ? Icons.favorite : Icons.favorite_border,
              color: pc.isLiked(track) ? const Color(0xFF1DB954) : null,
            ),
            onPressed: () => pc.toggleLike(track),
          ),
          _downloadButton(pc, track, dlProgress),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 8),
          Center(child: TrackArt(track, size: 300, radius: 12)),
          const SizedBox(height: 24),
          Text(track.title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              maxLines: 2),
          const SizedBox(height: 4),
          Text(track.artist,
              style: TextStyle(color: Colors.grey[400], fontSize: 15)),
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
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('OFFLINE',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          // CC-BY attribution, as required by the license.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              track.needsAttribution
                  ? '"${track.title}" by ${track.artist} · ${track.license} · via Internet Archive'
                  : '"${track.title}" · ${track.license} · via Internet Archive',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          if (pc.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(pc.error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Slider(
            value: sliderValue,
            max: maxMs,
            onChangeStart: (v) => setState(() => _dragMs = v),
            onChanged: (v) => setState(() => _dragMs = v),
            onChangeEnd: (v) {
              pc.seek(Duration(milliseconds: v.round()));
              setState(() => _dragMs = null);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_dragMs != null
                      ? Duration(milliseconds: _dragMs!.round())
                      : pos),
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 12)),
              Text(_fmt(dur),
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                icon: const Icon(Icons.skip_previous),
                iconSize: 40,
                onPressed: pc.previous,
              ),
              pc.isLoading
                  ? const SizedBox(
                      width: 64,
                      height: 64,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                            color: Color(0xFF1DB954)),
                      ),
                    )
                  : IconButton(
                      icon: Icon(pc.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled),
                      iconSize: 64,
                      color: Colors.white,
                      onPressed: pc.togglePlayPause,
                    ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 40,
                onPressed: () => pc.next(),
              ),
              IconButton(
                icon: Icon(
                  pc.loopMode == 2 ? Icons.repeat_one : Icons.repeat,
                  color: pc.loopMode == 0
                      ? Colors.grey
                      : const Color(0xFF1DB954),
                ),
                iconSize: 26,
                onPressed: pc.cycleLoop,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pc.upNext.isNotEmpty) ...[
            const Text('Up next',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...pc.upNext.map((t) {
              final qi = pc.queue.indexOf(t);
              return TrackTile(
                track: t,
                contextQueue: pc.queue,
                indexInQueue: qi,
                pc: pc,
                onTapOverride: () => pc.jumpToQueueIndex(qi),
              );
            }),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _downloadButton(
      PlayerController pc, track, double? dlProgress) {
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
