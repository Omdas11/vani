import 'package:flutter/material.dart';

/// App-wide animated background: a slowly-shifting dark gradient with the
/// Vani veena icon enlarged at very low opacity as a watermark.
///
/// GPU-cheap by design: a single 24s [AnimationController] drives one
/// [AnimatedBuilder] that lerps between four pre-built gradients. No
/// per-frame blur, no shader. When the user turns "Animated background"
/// off in Settings (battery saver), this renders a plain static dark
/// container instead.
///
/// v1.5.0 perf: the whole background sits in a RepaintBoundary so its
/// per-frame gradient ticks never force the UI above to repaint (this
/// was the main "choppy" driver together with the glass blur). The
/// watermark no longer drifts per-frame — it was imperceptible and
/// forced the image to repaint.
class AppBackground extends StatefulWidget {
  final bool animated;
  const AppBackground({super.key, this.animated = true});

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Four dark gradient stops the background cycles through. All very
  // dark so text stays readable; tints echo the Obsidian Sonic theme
  // (mint, violet, deep teal, charcoal).
  static const _stages = [
    [Color(0xFF0B0E0C), Color(0xFF101512)],
    [Color(0xFF0C0F14), Color(0xFF12141C)],
    [Color(0xFF0D0C10), Color(0xFF151218)],
    [Color(0xFF0B0E0C), Color(0xFF101512)],
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    if (widget.animated) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant AppBackground old) {
    super.didUpdateWidget(old);
    if (widget.animated && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animated && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animated) {
      return Container(color: const Color(0xFF121212));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value * (_stages.length - 1);
          final i = t.floor().clamp(0, _stages.length - 2);
          final f = t - i;
          final top = Color.lerp(_stages[i][0], _stages[i + 1][0], f)!;
          final bottom = Color.lerp(_stages[i][1], _stages[i + 1][1], f)!;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [top, bottom],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -90,
                  top: 120,
                  child: Opacity(
                    opacity: 0.055,
                    child: Image.asset(
                      'assets/veena_watermark.webp',
                      width: 340,
                      height: 340,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
