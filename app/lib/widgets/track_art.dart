import 'dart:io';

import 'package:flutter/material.dart';
import '../models/track.dart';

/// Shared artwork image with a music-note fallback.
/// Supports remote URLs (Image.network) and on-device file paths
/// (Image.file, e.g. cover art downloaded by AI Fixer).
class TrackArt extends StatelessWidget {
  final Track track;
  final double size;
  final double radius;

  /// When true the artwork is a full circle (PixelPlayer mini-player
  /// pattern); otherwise a squircle-ish rounded rect.
  final bool circular;

  const TrackArt(this.track,
      {super.key, this.size = 56, this.radius = 6, this.circular = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = circular
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius));
    Widget fallback() => Container(
          width: size,
          height: size,
          decoration: ShapeDecoration(
            shape: shape,
            color: scheme.surfaceContainerHighest,
          ),
          child: Icon(Icons.music_note,
              color: scheme.onSurfaceVariant, size: size * 0.45),
        );
    if (track.artworkUrl.isEmpty) return fallback();
    final url = track.artworkUrl;
    final Widget image = url.startsWith('/')
        ? Image.file(
            File(url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback(),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback(),
          );
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(shape: shape),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

/// License badge shown on cards and in the player (CC-BY needs attribution).
class LicenseBadge extends StatelessWidget {
  final Track track;
  const LicenseBadge(this.track, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    if (track.license == 'CC0') {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else if (track.isDriveTrack) {
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
    } else {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        track.license,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
