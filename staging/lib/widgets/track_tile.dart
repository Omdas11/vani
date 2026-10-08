import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import 'expressive.dart';
import 'track_art.dart';

/// A tappable track row as an individual expressive card (PixelPlayer
/// Library pattern): rounded container, 56dp squircle artwork, two
/// metadata lines, and a circular tonal overflow button — no dividers.
///
/// The overflow button opens the rich track action sheet
/// ([showTrackActions]): Play Next / Add to queue / Like / Add to
/// playlist / Download.
class TrackTile extends StatelessWidget {
  final Track track;
  final List<Track> contextQueue;
  final int indexInQueue;
  final PlayerController pc;
  final VoidCallback? onTapOverride;
  final bool showOfflineBadge;

  /// When non-null, shows an edit (pencil) button in the trailing row —
  /// used by the My Drive screen to rename user-added tracks.
  final void Function(Track track)? onEdit;

  const TrackTile({
    super.key,
    required this.track,
    required this.contextQueue,
    required this.indexInQueue,
    required this.pc,
    this.onTapOverride,
    this.showOfflineBadge = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = VaniTheme.radiiOf(context);
    final isCurrent = pc.currentTrack == track;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap:
              onTapOverride ?? () => pc.playTracks(contextQueue, indexInQueue),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                TrackArt(track, size: 56, radius: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isCurrent ? scheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${track.artist} · ${track.license}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (track.isBetaFormat)
                  Tooltip(
                    message:
                        '${track.audioFormat} playback is in early testing — '
                        'tell us if seeking or playback misbehaves.',
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${track.audioFormat} β',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                if (showOfflineBadge && track.isDownloaded)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.download_done,
                        size: 18, color: scheme.onSurfaceVariant),
                  ),
                if (onEdit != null)
                  TonalIconButton(
                    icon: Icons.edit_outlined,
                    iconSize: 18,
                    size: 40,
                    tooltip: 'Rename',
                    onPressed: () => onEdit!(track),
                  ),
                TonalIconButton(
                  icon: Icons.more_vert,
                  iconSize: 20,
                  size: 40,
                  tooltip: 'Track options',
                  onPressed: () => showTrackActions(context, pc, track),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
