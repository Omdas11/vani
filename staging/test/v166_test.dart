import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/main.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:opentune/widgets/mini_player.dart';

/// v1.6.6 tests.
///
/// PART A — guardedActivate: the equalizer UnimplementedError escapes
/// just_audio as *uncaught async* (the `_activate` loop sits outside
/// just_audio's try/catch, so the awaited setAudioSource hangs instead
/// of throwing). These tests pin the zone-net that catches the refusal
/// however it surfaces — the exact failure from the v1.6.4 device log.
///
/// PART B — dynamic mini player: zero reserved space when hidden,
/// animated in/out, content padding follows.
void main() {
  group('guardedActivate: EQ refusal escape routes', () {
    UnimplementedError eqError() => UnimplementedError(
        'androidEqualizerGetParameters() has not been implemented.');

    test('direct UnimplementedError -> eqRefused', () async {
      final outcome = await guardedActivate(
        () => Future<void>.error(eqError()),
        watchdog: const Duration(seconds: 2),
      );
      expect(outcome, ActivationOutcome.eqRefused);
    });

    test('uncaught-async escape (the just_audio route) -> eqRefused',
        () async {
      // Mirrors the real failure: the error escapes via an orphaned
      // future (never reaches the awaited load future, which hangs).
      final outcome = await guardedActivate(
        () async {
          // ignore: unawaited_futures
          Future<void>.error(eqError());
          await Future<void>.delayed(const Duration(seconds: 30));
        },
        watchdog: const Duration(seconds: 2),
      );
      expect(outcome, ActivationOutcome.eqRefused);
    });

    test('successful load -> ok', () async {
      final outcome = await guardedActivate(
        () async {},
        watchdog: const Duration(seconds: 2),
      );
      expect(outcome, ActivationOutcome.ok);
    });

    test('non-EQ direct error is rethrown, not swallowed', () async {
      final boom = StateError('boom');
      Object? caught;
      try {
        await guardedActivate(
          () => Future<void>.error(boom),
          watchdog: const Duration(seconds: 2),
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, same(boom));
    });

    test('hang without EQ signal -> failed (watchdog)', () async {
      final outcome = await guardedActivate(
        () => Future<void>.delayed(const Duration(seconds: 30)),
        watchdog: const Duration(milliseconds: 300),
      );
      expect(outcome, ActivationOutcome.failed);
    });

    test('non-EQ uncaught async error is forwarded, not swallowed',
        () async {
      // A foreign uncaught error during the window must keep its old
      // behavior (reported to the enclosing zone), not vanish.
      Object? forwarded;
      StackTrace? forwardedStack;
      await runZonedGuarded(() async {
        await guardedActivate(
          () async {
            // ignore: unawaited_futures
            Future<void>.error(StateError('foreign'));
            await Future<void>.delayed(const Duration(seconds: 30));
          },
          watchdog: const Duration(milliseconds: 300),
        );
      }, (Object e, StackTrace s) {
        forwarded = e;
        forwardedStack = s;
      });
      // Let the forwarded uncaught error land in the outer zone.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(forwarded, isStateError);
      expect(forwardedStack, isNotNull);
    });
  });

  group('dynamic mini player layout', () {
    // NOTE: no pumpAndSettle anywhere here — the animated app background
    // never settles, so tests advance the clock with explicit pumps
    // (same pattern as v164_test).
    testWidgets('hidden -> zero-height slot; shown -> animates in',
        (tester) async {
      final pc = _FakePc();
      await tester.pumpWidget(MaterialApp(home: MainShell(pc: pc)));
      await tester.pump();

      // No track: no MiniPlayer in the tree at all (zero reserved space).
      expect(find.byType(MiniPlayer), findsNothing);

      // Start playback: the card animates in.
      pc.fakeTrack = _track('t1', 'Dynamic Song');
      pc.poke();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Dynamic Song'),
        ),
        findsWidgets,
      );
    });

    testWidgets('stop -> exit animation keeps stale track, then collapses',
        (tester) async {
      final pc = _FakePc()..fakeTrack = _track('t1', 'Fading Song');
      await tester.pumpWidget(MaterialApp(home: MainShell(pc: pc)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MiniPlayer), findsOneWidget);

      // Stop: the exiting card keeps rendering the stale track (inert)
      // while it collapses — no pop.
      pc.fakeTrack = null;
      pc.poke();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Fading Song'),
        ),
        findsWidgets,
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('content bottom padding follows mini player visibility',
        (tester) async {
      final pc = _FakePc();
      await tester.pumpWidget(MaterialApp(home: MainShell(pc: pc)));
      await tester.pump();

      AnimatedPadding paddingOf() => tester.widget(
            find.ancestor(
              of: find.byType(IndexedStack),
              matching: find.byType(AnimatedPadding),
            ),
          );

      // Hidden: compact padding (dock only).
      expect(
        (paddingOf().padding as EdgeInsets).bottom,
        lessThan(120),
      );

      pc.fakeTrack = _track('t1', 'Padding Song');
      pc.poke();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Shown: room for dock + mini player.
      expect(
        (paddingOf().padding as EdgeInsets).bottom,
        greaterThan(150),
      );
    });
  });
}

Track _track(String id, String title) => Track(
      id: id,
      title: title,
      artist: 'Unknown artist',
      license: 'CC0',
      licenseUrl: '',
      artworkUrl: '',
    );

/// Minimal fake: the PlayerController.test() seam has no platform
/// player, so playback state is driven manually.
class _FakePc extends PlayerController {
  _FakePc() : super.test();

  Track? fakeTrack;

  @override
  Track? get currentTrack => fakeTrack;

  @override
  bool get isPlaying => true;

  void poke() => notifyListeners();
}
