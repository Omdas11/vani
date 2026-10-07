import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:opentune/services/equalizer.dart';

/// Unit tests for the pure helpers of the beta equalizer.
/// No platform interaction: the controller's init() (which talks to the
/// native AudioEffect) is not exercised here.
void main() {
  group('bandLabel', () {
    test('formats Hz and kHz', () {
      expect(EqualizerController.bandLabel(60), '60 Hz');
      expect(EqualizerController.bandLabel(230), '230 Hz');
      expect(EqualizerController.bandLabel(3600), '3.6 kHz');
      expect(EqualizerController.bandLabel(14000), '14 kHz');
    });
  });

  group('preset curve interpolation', () {
    test('single-point curve is flat', () {
      expect(
          EqualizerController.interpForTest(
              const [(60.0, 0.0)], 10000),
          0);
    });

    test('exact points return exact gains', () {
      const curve = <(double, double)>[(60, 8.0), (1000, 0.0), (10000, -2.0)];
      expect(
          EqualizerController.interpForTest(curve, 60), 8.0);
      expect(
          EqualizerController.interpForTest(curve, 1000), 0.0);
    });

    test('clamps outside the curve range', () {
      const curve = <(double, double)>[(100, 5.0), (1000, -5.0)];
      expect(
          EqualizerController.interpForTest(curve, 10), 5.0);
      expect(
          EqualizerController.interpForTest(curve, 20000), -5.0);
    });

    test('interpolates logarithmically between points', () {
      const curve = <(double, double)>[(100, 0.0), (10000, 10.0)];
      // Geometric midpoint of 100..10000 is 1000 -> gain 5.
      final mid =
          EqualizerController.interpForTest(curve, 1000);
      expect(mid, closeTo(5.0, 0.01));
    });
  });

  group('presets list', () {
    test('contains the required five presets', () {
      expect(EqualizerController.presets,
          containsAll(['Normal', 'Bass Boost', 'Treble', 'Vocal', 'Custom']));
    });

    test('controller constructs without platform', () {
      final c = EqualizerController(AndroidEqualizer());
      expect(c.ready, isFalse);
      expect(c.enabled, isFalse);
      expect(c.preset, 'Normal');
    });
  });
}
