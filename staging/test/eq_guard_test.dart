import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:opentune/services/equalizer.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simulates a platform that declines the equalizer method channel,
/// reproducing the exact on-device failure:
/// "UnimplementedError: androidEqualizerGetParameters() has not been
/// implemented." (thrown from just_audio's effect _activate during the
/// player's platform connect, i.e. inside setAudioSource on devices
/// where the background player's channel doesn't implement it).
class _ThrowingEqualizer extends AndroidEqualizer {
  @override
  Future<AndroidEqualizerParameters> get parameters => throw UnimplementedError(
      'androidEqualizerGetParameters() has not been implemented.');
}

void main() {
  group('isEqPlatformFailure', () {
    test('detects the equalizer UnimplementedError', () {
      expect(
        isEqPlatformFailure(UnimplementedError(
            'androidEqualizerGetParameters() has not been implemented.')),
        isTrue,
      );
    });

    test('ignores unrelated errors', () {
      expect(
        isEqPlatformFailure(
            UnimplementedError('load() has not been implemented.')),
        isFalse,
      );
      expect(isEqPlatformFailure(StateError('boom')), isFalse);
      expect(
        isEqPlatformFailure(
            Exception('androidEqualizerBandSetGain failed')),
        isFalse,
      );
    });
  });

  group('buildAudioPipeline', () {
    test('attaches the equalizer when the platform supports it', () {
      final eq = AndroidEqualizer();
      final pipeline =
          buildAudioPipeline(eqSupported: true, equalizer: eq);
      expect(pipeline.androidAudioEffects, contains(eq));
    });

    test('never touches the equalizer when unsupported', () {
      // The throwing fake stands in for the real effect: even so, the
      // unsupported pipeline must not reference it at all, so playback
      // can never trigger the platform call.
      final eq = _ThrowingEqualizer();
      final pipeline =
          buildAudioPipeline(eqSupported: false, equalizer: eq);
      expect(pipeline.androidAudioEffects, isEmpty);
    });
  });

  group('EqualizerController unsupported path', () {
    test('markUnsupported flips flags; init() returns immediately',
        () async {
      final c = EqualizerController(_ThrowingEqualizer());
      await c.markUnsupported();
      expect(c.supported, isFalse);
      expect(c.ready, isFalse);
      // Must not throw, hang, or retry: the platform already declined.
      await c.init().timeout(const Duration(seconds: 5));
      expect(c.ready, isFalse);
      expect(c.supported, isFalse);
    });

    test('mutators never touch the platform when unsupported', () async {
      SharedPreferences.setMockInitialValues({});
      final c = EqualizerController(_ThrowingEqualizer());
      await c.markUnsupported();
      await c.setEnabled(true);
      await c.applyPreset('Bass Boost');
      await c.setBandGain(0, 5.0);
      expect(c.ready, isFalse);
      expect(c.supported, isFalse);
    });

    test('init() marks unsupported on UnimplementedError, no retry storm',
        () async {
      // init() with a throwing channel must give up and mark the
      // platform unsupported instead of retrying 15 times.
      final c = EqualizerController(_ThrowingEqualizer());
      final sw = Stopwatch()..start();
      await c.init();
      sw.stop();
      expect(c.supported, isFalse);
      expect(c.ready, isFalse);
      // A single fast failure, not 15 attempts x (2s timeout + 1s delay).
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}
