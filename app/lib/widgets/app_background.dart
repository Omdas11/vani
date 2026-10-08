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

  /// Test seam: which gradient stages render for a given brightness /
  /// AMOLED combination (v1.6.9 light-mode regression guard).
  @visibleForTesting
  static List<List<Color>> stagesFor(
          {required Brightness brightness, required bool amoled}) =>
      _AppBackgroundState.stagesFor(
          brightness: brightness, amoled: amoled);

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Four dark gradient stops the background cycles through. All very
  // dark so text stays readable; tints echo the Obsidian Sonic theme
  // (mint, violet, deep teal, charcoal).
  static const _darkStages = [
    [Color(0xFF0B0E0C), Color(0xFF101512)],
    [Color(0xFF0C0F14), Color(0xFF12141C)],
    [Color(0xFF0D0C10), Color(0xFF151218)],
    [Color(0xFF0B0E0C), Color(0xFF101512)],
  ];

  // Near-black variant for AMOLED theme mode (pure black saves pixels).
  static const _amoledStages = [
    [Color(0xFF000000), Color(0xFF050505)],
    [Color(0xFF020202), Color(0xFF070707)],
    [Color(0xFF000000), Color(0xFF050505)],
    [Color(0xFF020202), Color(0xFF070707)],
  ];

  // Light gradient stops for the Light theme mode: near-white with a
  // whisper of warmth so dark text stays readable. The animated cycle
  // is kept (subtle), mirroring the dark behavior.
  // v1.6.9: the old code hardcoded near-black stages, which is why the
  // Light theme rendered white cards on a black background.
  static const _lightStages = [
    [Color(0xFFF7F8FA), Color(0xFFE9EBF0)],
    [Color(0xFFF4F6FA), Color(0xFFE7EAF0)],
    [Color(0xFFF8F7F5), Color(0xFFEBE9E4)],
    [Color(0xFFF7F8FA), Color(0xFFE9EBF0)],
  ];

  /// Gradient stages for the given brightness. Pure logic so the
  /// theme-mode path is unit-testable: Light must never return a dark
  /// stage (v1.6.9 regression: Light rendered on a black background).
  @visibleForTesting
  static List<List<Color>> stagesFor({
    required Brightness brightness,
    required bool amoled,
  }) {
    if (brightness == Brightness.light) return _lightStages;
    if (amoled) return _amoledStages;
    return _darkStages;
  }

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
    final scheme = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light;
    // AMOLED pins its surfaces to pure black (see VaniTheme); detect it
    // from the scheme so the background matches the theme mode.
    final amoled =
        !light && scheme.surface == const Color(0xFF000000);
    final stages = stagesFor(
        brightness: scheme.brightness, amoled: amoled);
    if (!widget.animated) {
      return Container(color: scheme.surface);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value * (stages.length - 1);
          final i = t.floor().clamp(0, stages.length - 2);
          final f = t - i;
          final top = Color.lerp(stages[i][0], stages[i + 1][0], f)!;
          final bottom = Color.lerp(stages[i][1], stages[i + 1][1], f)!;
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
                // Veena watermark: scaled down and fully on-screen
                // (bug report v1.6.0 — the old 340px art bled off the
                // right edge and looked cropped). Subtle by design.
                // In light mode the mint art would vanish on white, so
                // it is dimmed slightly darker instead of glowing.
                Align(
                  alignment: const Alignment(0.45, -0.1),
                  child: Opacity(
                    opacity: light ? 0.10 : 0.06,
                    child: ColorFiltered(
                      colorFilter: light
                          ? const ColorFilter.mode(
                              Color(0xFF9AA5B1), BlendMode.srcIn)
                          : const ColorFilter.mode(
                              Colors.transparent, BlendMode.dst),
                      child: Image.asset(
                        'assets/veena_watermark.webp',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
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
