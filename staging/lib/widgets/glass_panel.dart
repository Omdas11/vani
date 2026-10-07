import 'dart:ui';
import 'package:flutter/material.dart';

/// Frosted-glass panel shared by the Now Playing screen, the floating
/// mini-player card and the bottom dock.
///
/// Why it reads as "glass" on-device (v1.4.0 fixes for the flat look):
/// - a stronger blur (sigma 22) over a *tinted* base, so the panel is
///   legible even where there is little behind it to blur;
/// - a bright top-edge highlight plus a full 1px border, which is what
///   sells the glass edge to the eye;
/// - a soft drop shadow for separation from the background.
/// The base tint doubles as a graceful fallback on GPUs where the blur
/// is weak: the panel never becomes unreadable.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double tintAlpha;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.tintAlpha = 0.10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.02),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.10),
              ],
              stops: const [0.0, 0.12, 0.5, 1.0],
            ),
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: tintAlpha),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
