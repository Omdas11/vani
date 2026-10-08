import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/screens/developer_screen.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/vani_theme.dart';
import 'package:opentune/widgets/app_background.dart';
import 'package:opentune/widgets/mini_player.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.6.9 fix-release tests.
///
/// Bug 1 (P0): the Light theme mode never rendered — the app background
/// was hard-coded to near-black gradients. Regression guards assert the
/// built ThemeData brightness matches the selected mode AND the
/// background gradient stages match that brightness.
///
/// Bug 2: the developer-options action buttons collapsed into tall
/// narrow pills with vertical unreadable text. Guards assert proper
/// horizontal pills.
///
/// Bug 3: mini-player swipe was whole-card; v1.6.9 is Spotify-style —
/// only the identity block slides, chrome stays fixed, fling commits a
/// content swap, release-without-fling springs back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // google_fonts raises its "font not bundled" error asynchronously even
  // with runtime fetching disabled; absorb it — these tests verify
  // theme structure, not font loading.
  Future<void> withoutFontErrors(Future<void> Function() body) async {
    await runZonedGuarded(
      body,
      (Object e, StackTrace s) {
        if (e.toString().contains('GoogleFonts')) return;
        Error.throwWithStackTrace(e, s);
      },
    );
  }

  group('Bug 1: theme mode actually renders', () {
    test('Light mode resolves to a light scheme and light stages',
        () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      await settings.setThemeMode(ThemeModeOption.light);
      await settings.setMatchSystemColor(false);

      final scheme = settings.resolveColorScheme();
      expect(scheme.brightness, Brightness.light,
          reason: 'Light mode must resolve a light ColorScheme');

      await withoutFontErrors(() async {
        final theme =
            VaniTheme.buildTheme(scheme: scheme, cornerRadius: 20);
        expect(theme.brightness, Brightness.light,
            reason: 'built ThemeData must carry the light brightness');
        // Status-bar icons must stay visible on the light background.
        expect(theme.appBarTheme.systemOverlayStyle,
            SystemUiOverlayStyle.dark);
      });

      // The background gradient stages must be light too — this was
      // the actual P0: hard-coded black stages under white cards.
      final stages = AppBackground.stagesFor(
          brightness: scheme.brightness, amoled: false);
      expect(stages.length, 4);
      for (final stage in stages) {
        for (final c in stage) {
          expect(c.computeLuminance(), greaterThan(0.5),
              reason: 'light-mode background stages must be bright');
        }
      }
    });

    test('System mode follows the platform brightness', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      await settings.setThemeMode(ThemeModeOption.system);
      await settings.setMatchSystemColor(false);

      settings.setPlatformBrightness(Brightness.light);
      expect(settings.resolveColorScheme().brightness, Brightness.light);
      expect(
          AppBackground.stagesFor(
              brightness: Brightness.light, amoled: false)
              .first
              .first
              .computeLuminance(),
          greaterThan(0.5));

      settings.setPlatformBrightness(Brightness.dark);
      expect(settings.resolveColorScheme().brightness, Brightness.dark);
      expect(
          AppBackground.stagesFor(
              brightness: Brightness.dark, amoled: false)
              .first
              .first
              .computeLuminance(),
          lessThan(0.2));
    });

    test('AMOLED mode pins surfaces to pure black with dark stages',
        () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      await settings.setThemeMode(ThemeModeOption.amoled);
      await settings.setMatchSystemColor(false);

      final scheme = settings.resolveColorScheme();
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, const Color(0xFF000000));

      final stages = AppBackground.stagesFor(
          brightness: scheme.brightness, amoled: true);
      for (final stage in stages) {
        for (final c in stage) {
          expect(c.computeLuminance(), lessThan(0.05),
              reason: 'AMOLED stages must be near-black');
        }
      }
    });

    test('dark scheme stages stay dark (no regression)', () {
      final stages = AppBackground.stagesFor(
          brightness: Brightness.dark, amoled: false);
      for (final stage in stages) {
        for (final c in stage) {
          expect(c.computeLuminance(), lessThan(0.2));
        }
      }
    });

    test('dark theme keeps light status-bar icons', () async {
      await withoutFontErrors(() async {
        final scheme = VaniTheme.schemeForPreset(ThemePreset.neonMint);
        final theme =
            VaniTheme.buildTheme(scheme: scheme, cornerRadius: 20);
        expect(theme.brightness, Brightness.dark);
        expect(theme.appBarTheme.systemOverlayStyle,
            SystemUiOverlayStyle.light);
      });
    });
  });

  group('Bug 2: developer options buttons are horizontal pills', () {
    testWidgets('all five action buttons render wide and readable',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeveloperScreen(pc: _FakePc()),
          ),
        ),
      );
      await tester.pump();

      const labels = [
        'Copy logs',
        'Share log file',
        'Simulate crash',
        'Share crash log',
        'Clear',
      ];
      for (final label in labels) {
        final btn = find.widgetWithText(OutlinedButton, label);
        expect(btn, findsOneWidget, reason: 'button "$label" exists');
        final size = tester.getSize(btn);
        // The v1.6.8 bug: ~65px-wide Expanded buttons in a Row forced
        // labels into single-character-wide wrapped lines. A proper
        // horizontal pill is wider than it is tall.
        expect(size.width, greaterThan(size.height),
            reason: '"$label" must be a horizontal pill, not vertical');
        expect(size.width, greaterThan(90),
            reason: '"$label" must be wide enough for readable text');
      }
    });
  });

  group('Bug 3: Spotify-style content slide', () {
    Future<_FakePc> pumpMini(WidgetTester tester) async {
      final pc = _FakePc()
        ..fakeTrack = _track('t1', 'Content Slide Song');
      pc.fakeNext = _track('t2', 'Next Content Song');
      pc.fakePrev = _track('t0', 'Prev Content Song');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniPlayer(pc: pc)),
        ),
      );
      await tester.pump();
      return pc;
    }

    testWidgets(
        'held horizontal drag moves the identity block, not the chrome',
        (tester) async {
      final pc = await pumpMini(tester);
      expect(pc.fakeTrack?.id, 't1');

      final titleFinder =
          find.byKey(const ValueKey('mini-title::t1'));
      final pauseFinder = find.byTooltip('Pause');
      expect(titleFinder, findsOneWidget);
      expect(pauseFinder, findsOneWidget);

      final titleBefore = tester.getCenter(titleFinder);
      final pauseBefore = tester.getCenter(pauseFinder);

      final center = tester.getCenter(find.byType(MiniPlayer));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();

      final titleAfter = tester.getCenter(titleFinder);
      final pauseAfter = tester.getCenter(pauseFinder);

      // The identity block (artwork + title/artist) follows the finger.
      expect(titleAfter.dx, lessThan(titleBefore.dx - 10),
          reason: 'title must slide with the finger');
      // The transport chrome stays fixed in place.
      expect((pauseAfter - pauseBefore).distance, lessThan(1.0),
          reason: 'transport buttons must not move');

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(pc.nextCalls, 0, reason: 'no fling → no skip');
    });

    testWidgets('fling left commits a content swap to the next track',
        (tester) async {
      final pc = await pumpMini(tester);
      await tester.fling(
          find.byType(MiniPlayer), const Offset(-400, 0), 1500);
      // Phase 1 (180ms) slides the old content out, then next() fires,
      // then phase 2 (220ms) slides the new content in.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(pc.nextCalls, 1);
      expect(pc.prevCalls, 0);
      // The identity block now renders the NEW track.
      expect(find.byKey(const ValueKey('mini-title::t2')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('mini-title::t1')), findsNothing);
    });

    testWidgets('fling right commits a content swap to the previous track',
        (tester) async {
      final pc = await pumpMini(tester);
      await tester.fling(
          find.byType(MiniPlayer), const Offset(400, 0), 1500);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(pc.prevCalls, 1);
      expect(pc.nextCalls, 0);
      expect(find.byKey(const ValueKey('mini-title::t0')),
          findsOneWidget);
    });

    testWidgets('fling with no neighbor springs back, no skip',
        (tester) async {
      final pc = _FakePc()
        ..fakeTrack = _track('t1', 'Content Slide Song');
      // No fakeNext: end of queue.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniPlayer(pc: pc)),
        ),
      );
      await tester.pump();
      await tester.fling(
          find.byType(MiniPlayer), const Offset(-400, 0), 1500);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(pc.nextCalls, 0);
      expect(pc.prevCalls, 0);
      expect(find.byKey(const ValueKey('mini-title::t1')),
          findsOneWidget);
    });

    testWidgets('slow drag without fling springs the content back',
        (tester) async {
      final pc = await pumpMini(tester);
      final center = tester.getCenter(find.byType(MiniPlayer));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(pc.nextCalls, 0);
      expect(pc.prevCalls, 0);
      // Original content restored.
      expect(find.byKey(const ValueKey('mini-title::t1')),
          findsOneWidget);
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

/// Minimal PlayerController.test() fake: next()/previous() actually
/// advance the track (mirrors the real controller's behavior).
class _FakePc extends PlayerController {
  _FakePc() : super.test();

  Track? fakeTrack;
  Track? fakeNext;
  Track? fakePrev;
  bool fakePlaying = true;
  int nextCalls = 0;
  int prevCalls = 0;

  @override
  Track? get currentTrack => fakeTrack;

  @override
  Track? get peekNextTrack => fakeNext;

  @override
  Track? get peekPreviousTrack => fakePrev;

  @override
  bool get isPlaying => fakePlaying;

  @override
  Future<void> next() async {
    nextCalls++;
    if (fakeNext != null) {
      fakeTrack = fakeNext;
      notifyListeners();
    }
  }

  @override
  Future<void> previous() async {
    prevCalls++;
    if (fakePrev != null) {
      fakeTrack = fakePrev;
      notifyListeners();
    }
  }
}
