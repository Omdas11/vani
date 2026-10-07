import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A vinyl record with the track's cover art as the center label.
///
/// [rotation] drives the spin (0.0–1.0 = one full turn). The parent screen
/// advances it only while audio is playing, so the disc freezes on pause.
/// [shimmer] drives a slow holographic rainbow sweep across the disc.
///
/// Both animations are cheap: one [RotationTransition] each plus a
/// [CustomPainter] for the grooves. No extra packages.
class VinylRecord extends StatelessWidget {
  final String artworkUrl;
  final Animation<double> rotation;
  final Animation<double> shimmer;
  final double size;

  const VinylRecord({
    super.key,
    required this.artworkUrl,
    required this.rotation,
    required this.shimmer,
    this.size = 300,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient holographic glow behind the disc.
          AnimatedBuilder(
            animation: shimmer,
            builder: (_, __) {
              final t = shimmer.value;
              return Container(
                width: size * 1.12,
                height: size * 1.12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _holoColor(t, 0.22),
                      _holoColor(t + 0.33, 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.55, 0.8, 1.0],
                  ),
                ),
              );
            },
          ),
          // The spinning disc.
          RotationTransition(
            turns: rotation,
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  radius: 1.1,
                  colors: [Color(0xFF2A2A2A), Color(0xFF0B0B0B)],
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 24,
                      offset: Offset(0, 10)),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Grooves.
                  CustomPaint(
                    size: Size(size, size),
                    painter: _GroovePainter(),
                  ),
                  // Holographic iridescent sweep rotating slowly over the disc.
                  RotationTransition(
                    turns: shimmer,
                    child: ClipOval(
                      child: Container(
                        width: size,
                        height: size,
                        decoration: const BoxDecoration(
                          gradient: SweepGradient(
                            colors: [
                              Colors.transparent,
                              Color(0x66FF5E5E),
                              Color(0x66FFB84D),
                              Color(0x66F9F871),
                              Color(0x665EE87A),
                              Color(0x665EC8E8),
                              Color(0x66A47FE8),
                              Colors.transparent,
                            ],
                            stops: [
                              0.0,
                              0.15,
                              0.30,
                              0.45,
                              0.60,
                              0.75,
                              0.90,
                              1.0
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Diagonal light streak (rotates with the disc).
                  ClipOval(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x22FFFFFF),
                            Colors.transparent,
                            Colors.transparent,
                            Color(0x11FFFFFF),
                          ],
                          stops: [0.0, 0.35, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Center label: the cover art.
                  Container(
                    width: size * 0.38,
                    height: size * 0.38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1DB954), width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 8)
                      ],
                    ),
                    child: ClipOval(child: _labelArt()),
                  ),
                  // Spindle hole.
                  Container(
                    width: size * 0.045,
                    height: size * 0.045,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE8E8E8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cycles through hues as the shimmer value moves, for the ambient glow.
  Color _holoColor(double t, double opacity) {
    final hue = ((t % 1.0) * 360 + 140) % 360; // mint → violet range drift
    return HSVColor.fromAHSV(opacity, hue, 0.7, 1.0).toColor();
  }

  Widget _labelArt() {
    if (artworkUrl.isEmpty) return _labelFallback();
    return Image.network(
      artworkUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _labelFallback(),
    );
  }

  Widget _labelFallback() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Icon(Icons.music_note,
          color: Color(0xFF1DB954), size: 40),
    );
  }
}

/// Thin concentric groove rings, alpha modulated for a machined look.
class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    // Leave the center-label area clear.
    final minR = maxR * 0.21;
    const rings = 42;
    for (var i = 0; i < rings; i++) {
      final r = minR + (maxR - minR - 6) * (i / (rings - 1));
      final alpha = 14 + (10 * math.sin(i * 1.7)).round();
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Color.fromARGB(alpha.clamp(4, 28), 255, 255, 255),
      );
    }
    // Dead-wax ring near the label.
    canvas.drawCircle(
      center,
      minR + 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = const Color.fromARGB(40, 255, 255, 255),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
