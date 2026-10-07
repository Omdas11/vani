import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Extracts a dominant color from a track's cover art for ambient-light
/// effects. Dependency-free: downloads the bytes with `http`, decodes
/// with dart:ui, and averages a downsampled pixel grid.
///
/// Results are cached per artwork URL for the session. Returns
/// [fallback] when the artwork is missing or undecodable.
class ArtworkColors {
  ArtworkColors._();
  static final Map<String, Color> _cache = {};

  static const Color fallback = Color(0xFF1DB954);

  static Future<Color> dominant(String artworkUrl,
      {Color fallback = fallback}) async {
    if (artworkUrl.isEmpty) return fallback;
    final hit = _cache[artworkUrl];
    if (hit != null) return hit;
    try {
      final res = await http
          .get(Uri.parse(artworkUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        return fallback;
      }
      final color = await _average(res.bodyBytes);
      _cache[artworkUrl] = color;
      return color;
    } catch (_) {
      return fallback;
    }
  }

  /// Decodes and averages pixels on a coarse grid. Pure-Dart math over
  /// the raw RGBA bytes; runs off the critical path via async decode.
  static Future<Color> _average(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 24,
      targetHeight: 24,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;
    try {
      final data =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return fallback;
      final px = data.buffer.asUint8List();
      var r = 0, g = 0, b = 0, n = 0;
      // Sample every pixel of the 24x24 thumbnail, skipping near-black
      // (letterboxing) and near-transparent pixels.
      for (var i = 0; i + 3 < px.length; i += 4) {
        final pr = px[i], pg = px[i + 1], pb = px[i + 2], pa = px[i + 3];
        if (pa < 128) continue;
        if (pr < 12 && pg < 12 && pb < 12) continue;
        r += pr;
        g += pg;
        b += pb;
        n++;
      }
      if (n == 0) return fallback;
      var col = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
      // Boost saturation a little so the glow reads as "ambient light"
      // rather than muddy grey.
      final hsv = HSVColor.fromColor(col);
      col = hsv.withSaturation((hsv.saturation * 1.25).clamp(0.0, 1.0)).toColor();
      return col;
    } finally {
      img.dispose();
    }
  }

  /// Test seam: average raw RGBA bytes without network/decode.
  @visibleForTesting
  static Color averageRgba(Uint8List rgba) {
    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final pr = rgba[i], pg = rgba[i + 1], pb = rgba[i + 2], pa = rgba[i + 3];
      if (pa < 128) continue;
      if (pr < 12 && pg < 12 && pb < 12) continue;
      r += pr;
      g += pg;
      b += pb;
      n++;
    }
    if (n == 0) return fallback;
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }
}
