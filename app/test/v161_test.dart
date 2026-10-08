import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/equalizer.dart';
import 'package:opentune/widgets/expressive.dart';
import 'package:opentune/widgets/floating_dock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A platform that NEVER answers the parameters probe — reproduces the
/// v1.6.0 bug where the EQ screen spun on "Waiting for the audio
/// engine..." forever because init() had no total deadline.
class _HangingEqualizer extends AndroidEqualizer {
  @override
  Future<AndroidEqualizerParameters> get parameters =>
      Completer<AndroidEqualizerParameters>().future;
}

void main() {
  group('v1.6.1: notch safe-area', () {
    testWidgets('DisplayHeader text sits below the top system padding',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
                padding: EdgeInsets.only(top: 47)), // notched phone
            child: Scaffold(body: DisplayHeader(title: 'Your Mix')),
          ),
        ),
      );
      // The visible title text must start below the notch/status bar:
      // base 16dp design padding + 47dp system inset.
      final textTop = tester.getTopLeft(find.text('Your Mix')).dy;
      expect(textTop, greaterThanOrEqualTo(47 + 16),
          reason: 'header must not underlap the notch/status bar');
    });

    testWidgets('DisplayHeader has no extra inset without a notch',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.zero),
            child: Scaffold(body: DisplayHeader(title: 'Your Mix')),
          ),
        ),
      );
      final textTop = tester.getTopLeft(find.text('Your Mix')).dy;
      // Base 16dp design padding only — no phantom inset.
      expect(textTop, 16);
    });
  });

  group('v1.6.1: equalizer bounded probe', () {
    test('hanging platform probe marks EQ unsupported (no infinite wait)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final c = EqualizerController(_HangingEqualizer());
      final sw = Stopwatch()..start();
      await c.init(probeBudget: const Duration(milliseconds: 400));
      sw.stop();
      expect(c.supported, isFalse);
      expect(c.ready, isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'probe must be bounded');
    });

    test('retry() re-runs the probe after a timeout', () async {
      SharedPreferences.setMockInitialValues({});
      final c = EqualizerController(_HangingEqualizer());
      await c.init(probeBudget: const Duration(milliseconds: 200));
      expect(c.supported, isFalse);
      // Retry re-arms and probes again (still hanging -> unsupported).
      await c.retry(probeBudget: const Duration(milliseconds: 200));
      expect(c.supported, isFalse);
      expect(c.ready, isFalse);
    });

    test('concurrent init() calls do not stack probes', () async {
      SharedPreferences.setMockInitialValues({});
      final c = EqualizerController(_HangingEqualizer());
      await Future.wait([
        c.init(probeBudget: const Duration(milliseconds: 300)),
        c.init(probeBudget: const Duration(milliseconds: 300)),
      ]);
      expect(c.supported, isFalse);
    });
  });

  group('v1.6.1: floating dock', () {
    Future<void> pumpDock(WidgetTester tester,
        {required List<NavDestination> dests,
        required String current,
        required ValueChanged<String> onSelect}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingDock(
              destinations: dests,
              currentId: current,
              onSelect: onSelect,
            ),
          ),
        ),
      );
    }

    testWidgets('renders all destinations with labels', (tester) async {
      await pumpDock(tester,
          dests: NavDestination.all.sublist(0, 3),
          current: 'home',
          onSelect: (_) {});
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      // Sliding active-indicator pill exists.
      expect(find.byType(AnimatedPositioned), findsOneWidget);
    });

    testWidgets('tapping a destination selects it', (tester) async {
      String? selected;
      await pumpDock(tester,
          dests: NavDestination.all.sublist(0, 3),
          current: 'home',
          onSelect: (id) => selected = id);
      await tester.tap(find.text('Search'));
      expect(selected, 'search');
    });

    testWidgets('respects a custom order', (tester) async {
      await pumpDock(tester,
          dests: [
            NavDestination.byId('settings'),
            NavDestination.byId('home'),
          ],
          current: 'settings',
          onSelect: (_) {});
      final settingsX =
          tester.getCenter(find.text('Settings')).dx;
      final homeX = tester.getCenter(find.text('Home')).dx;
      expect(settingsX, lessThan(homeX));
    });

    testWidgets('empty destination list renders nothing', (tester) async {
      await pumpDock(tester,
          dests: const [], current: 'home', onSelect: (_) {});
      expect(find.byType(FloatingDock), findsOneWidget);
      expect(find.byType(AnimatedPositioned), findsNothing);
    });
  });
}
