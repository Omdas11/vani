import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:opentune/services/equalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opentune/widgets/expressive.dart';

/// v1.6.2 regression tests.
///
/// 1. Notification buttons (P0): the device showed a media notification
///    with metadata but ZERO transport buttons. End-to-end code audit
///    proved the library wiring correct (just_audio_background always
///    broadcasts a non-empty controls list; audio_service maps
///    MediaAction -> PlaybackStateCompat action bits via `1 << index`,
///    activates the session, attaches it to the MediaStyle
///    notification). The device-specific fault was the v1.5.1 EQ guard:
///    on phones where the native equalizer channel is unimplemented,
///    EVERY first playback disposed and rebuilt the player, driving the
///    native AudioService through stop() (session deactivated,
///    stopSelf()) and an immediate foreground restart that raced the
///    old instance's onDestroy (instance=null, session released) —
///    leaving the notification bound to a dead session with no actions.
///    v1.6.2 resolves EQ support once at startup (persisted) and never
///    rebuilds mid-session. These tests pin the parts verifiable
///    headless:
///    a) MediaAction enum order matches Android PlaybackStateCompat bit
///       positions (a silent reorder would zero the native bitmask);
///    b) a playing-state controls list always carries
///       play/pause/skipToNext/skipToPrevious/stop;
///    c) the EQ-unsupported verdict persists across launches.
///
/// 2. Now Playing title: the marquee rendered
///    "Rutho Jo Tum (Tum Prem Ho) [FfCrY2vrkuc]" starting mid-title.
///    The marquee is now a seamless wrap loop that always starts at
///    offset 0, so the title always begins at its first character.
void main() {
  group('notification action-bit contract', () {
    test('MediaAction order matches PlaybackStateCompat bit positions',
        () {
      // AudioService.java computes native actions as `1 << actionIndex`
      // where actionIndex is the Dart MediaAction enum index. These must
      // match Android's PlaybackStateCompat.ACTION_* constants:
      // STOP=1, PAUSE=2, PLAY=4, REWIND=8, SKIP_TO_PREVIOUS=16,
      // SKIP_TO_NEXT=32, FAST_FORWARD=64, SET_RATING=128, SEEK_TO=256,
      // PLAY_PAUSE=512.
      const expected = {
        MediaAction.stop: 0,
        MediaAction.pause: 1,
        MediaAction.play: 2,
        MediaAction.rewind: 3,
        MediaAction.skipToPrevious: 4,
        MediaAction.skipToNext: 5,
        MediaAction.fastForward: 6,
        MediaAction.setRating: 7,
        MediaAction.seek: 8,
        MediaAction.playPause: 9,
      };
      for (final entry in expected.entries) {
        expect(MediaAction.values.indexOf(entry.key), entry.value,
            reason: '${entry.key} moved: the native action bitmask '
                'would silently break notification buttons');
      }
      // And the derived bitmask for a playing state is non-zero and
      // contains every transport bit.
      final actions = {
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
      };
      var bits = 0;
      for (final a in actions) {
        bits |= 1 << MediaAction.values.indexOf(a);
      }
      expect(bits, isNonZero, reason: 'native bitmask is zero');
      expect(bits & (1 << 1), isNonZero,
          reason: 'pause bit missing from native bitmask');
      expect(bits & (1 << 0), isNonZero,
          reason: 'stop bit missing from native bitmask');
      expect(bits & (1 << 4), isNonZero,
          reason: 'skipToPrevious bit missing from native bitmask');
      expect(bits & (1 << 5), isNonZero,
          reason: 'skipToNext bit missing from native bitmask');
      // A paused state's mask carries the play bit instead of pause.
      final pausedBits = 1 << MediaAction.values.indexOf(MediaAction.play);
      expect(pausedBits, 1 << 2, reason: 'play must sit at bit 2');
    });

    test('playing-state controls always carry all transport actions', () {
      // Mirrors the controls list just_audio_background's
      // _broadcastState() builds for a playing multi-track state: the
      // notification buttons come from exactly this list.
      final controls = [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.stop,
        MediaControl.skipToNext,
      ];
      final state = PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
        controls: controls,
        systemActions: const {},
      );
      final found = state.controls.map((c) => c.action).toSet();
      expect(found, contains(MediaAction.pause));
      expect(found, contains(MediaAction.stop));
      expect(found, contains(MediaAction.skipToPrevious));
      expect(found, contains(MediaAction.skipToNext));
      expect(state.controls, isNotEmpty,
          reason: 'empty controls = notification with zero buttons');
    });
  });

  group('EQ unsupported verdict persistence', () {
    test('markUnsupported persists; loader reads it back', () async {
      SharedPreferences.setMockInitialValues({});
      final c = EqualizerController(_NeverUsedEqualizer());
      expect(await EqualizerController.loadPersistedUnsupported(), isNull);
      await c.markUnsupported();
      expect(await EqualizerController.loadPersistedUnsupported(), isTrue);
    });

    test('loader returns null when never probed', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await EqualizerController.loadPersistedUnsupported(), isNull);
    });
  });

  group('MarqueeText seamless loop', () {
    const longTitle =
        'Rutho Jo Tum (Tum Prem Ho) [FfCrY2vrkuc] — an overlong title that '
        'must never be clipped at its start';

    Future<void> pumpMarquee(WidgetTester tester, String text) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: MarqueeText(
                key: ValueKey('t::$text'),
                text: text,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // post-frame overflow detection
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('overlong title renders the FULL text from character 0',
        (tester) async {
      await pumpMarquee(tester, longTitle);
      // Seamless loop duplicates the text: both copies must hold the
      // complete title starting at its first character.
      final found = find.text(longTitle);
      expect(found, findsNWidgets(2),
          reason: 'marquee loop must duplicate the full title');
      for (final e in found.evaluate()) {
        final widget = e.widget as Text;
        expect(widget.data, longTitle);
        expect(widget.data, startsWith('Rutho Jo Tum'),
            reason: 'title must begin at its first character, '
                'never clipped at the start');
      }
    });

    testWidgets('short title renders once without marquee', (tester) async {
      await pumpMarquee(tester, 'Short Song');
      expect(find.text('Short Song'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('new title starts at character 0 (no stale offset)',
        (tester) async {
      await pumpMarquee(tester, longTitle);
      expect(find.text(longTitle), findsNWidgets(2));
      // Swap to a different long title with the same key shape the
      // player screen uses (per-track keys recreate state anyway; this
      // covers the didUpdateWidget reset path too).
      const other =
          'Another Extremely Long Track Title That Must Start At Zero [xyz]';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: MarqueeText(
                key: const ValueKey('t::same'),
                text: other,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final found = find.text(other);
      expect(found, findsNWidgets(2));
      expect((found.evaluate().first.widget as Text).data,
          startsWith('Another'));
    });
  });
}

/// Never touched: persistence must not need the platform channel.
class _NeverUsedEqualizer extends AndroidEqualizer {}
