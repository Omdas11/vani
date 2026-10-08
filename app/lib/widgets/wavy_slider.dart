import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The M3-Expressive wavy progress slider (PixelPlayer / Auxio signature):
/// the played portion renders as an animated sine wave that flattens
/// while dragging; the remaining portion is a straight translucent track
/// with a round thumb knob at the boundary.
///
/// Tap-to-seek and horizontal-drag both work. Set [animate] to whether
/// audio is playing to freeze the wave when paused.
class WavySlider extends StatefulWidget {
  final double value;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final bool animate;
  final double height;

  const WavySlider({
    super.key,
    required this.value,
    required this.max,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.animate = true,
    this.height = 44,
  });

  @override
  State<WavySlider> createState() => _WavySliderState();
}

class _WavySliderState extends State<WavySlider>
    with TickerProviderStateMixin {
  late final AnimationController _phase;
  late final AnimationController _amp;

  @override
  void initState() {
    super.initState();
    // ~1.6s per wave cycle: lively but calm.
    _phase = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    // Wave amplitude: 1 at rest, eases to 0 while dragging (the
    // "flattens during interaction" behavior).
    _amp = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
        value: 1);
    if (!widget.animate) _phase.stop();
  }

  @override
  void didUpdateWidget(covariant WavySlider old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!widget.animate && _phase.isAnimating) {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  double _valueForDx(double dx, double width) =>
      (dx / width * widget.max).clamp(0.0, widget.max);

  void _beginDrag(double dx, double width) {
    _amp.animateTo(0, curve: Curves.easeOut);
    final v = _valueForDx(dx, width);
    widget.onChangeStart?.call(v);
    widget.onChanged?.call(v);
  }

  void _updateDrag(double dx, double width) {
    widget.onChanged?.call(_valueForDx(dx, width));
  }

  void _endDrag(double dx, double width) {
    _amp.animateTo(1, curve: Curves.easeOut);
    widget.onChangeEnd?.call(_valueForDx(dx, width));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final dx = box.globalToLocal(d.globalPosition).dx;
          final v = _valueForDx(dx, box.size.width);
          widget.onChangeStart?.call(v);
          widget.onChanged?.call(v);
          widget.onChangeEnd?.call(v);
        },
        onHorizontalDragStart: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          _beginDrag(
              box.globalToLocal(d.globalPosition).dx, box.size.width);
        },
        onHorizontalDragUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          _updateDrag(
              box.globalToLocal(d.globalPosition).dx, box.size.width);
        },
        onHorizontalDragEnd: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) {
            _amp.animateTo(1, curve: Curves.easeOut);
            return;
          }
          _endDrag(box.size.width * (widget.value / widget.max),
              box.size.width);
        },
        onHorizontalDragCancel: () {
          _amp.animateTo(1, curve: Curves.easeOut);
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_phase, _amp]),
          builder: (_, __) => Semantics(
            label: 'Seek',
            slider: true,
            child: CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: _WavyPainter(
                fraction: widget.max > 0
                    ? (widget.value / widget.max).clamp(0.0, 1.0)
                    : 0.0,
                phase: _phase.value * 2 * math.pi,
                ampFactor: _amp.value,
                active: scheme.primary,
                inactive:
                    scheme.onSurface.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  final double fraction;
  final double phase;
  final double ampFactor;
  final Color active;
  final Color inactive;

  static const double _amp = 5.0;
  static const double _wavelength = 30.0;
  static const double _stroke = 4.0;
  static const double _thumbR = 7.0;

  _WavyPainter({
    required this.fraction,
    required this.phase,
    required this.ampFactor,
    required this.active,
    required this.inactive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final endX = size.width - _thumbR;
    const startX = _thumbR;
    final thumbX =
        startX + (endX - startX) * fraction.clamp(0.0, 1.0);

    // Remaining (unplayed) track: straight translucent line.
    final trackPaint = Paint()
      ..color = inactive
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(thumbX, cy), Offset(endX, cy), trackPaint);

    // Played portion: sine wave, flattening while dragging.
    final amp = _amp * ampFactor;
    final wavePaint = Paint()
      ..color = active
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    final steps = ((thumbX - startX) / 4).ceil().clamp(2, 400);
    for (var i = 0; i <= steps; i++) {
      final x = startX + (thumbX - startX) * i / steps;
      final y = cy +
          math.sin(x / _wavelength * 2 * math.pi + phase) * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    // Round the very start so the wave reads as one stroke.
    if (thumbX > startX + 1) canvas.drawPath(path, wavePaint);

    // Round thumb knob at the boundary.
    canvas.drawCircle(
        Offset(thumbX, cy), _thumbR, Paint()..color = active);
  }

  @override
  bool shouldRepaint(covariant _WavyPainter old) =>
      old.fraction != fraction ||
      old.phase != phase ||
      old.ampFactor != ampFactor ||
      old.active != active ||
      old.inactive != inactive;
}
