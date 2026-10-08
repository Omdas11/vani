import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/screens/settings_screen.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/debug_log.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.6.4 developer-mode tests: ring buffer, 7-tap unlock, broadcast-line
/// format, and the log-capture settings sync.
void main() {
  group('DebugLog ring buffer', () {
    test('keeps only the last 3000 entries', () {
      DebugLog.captureEnabled = true;
      try {
        DebugLog.instance.clear();
        for (var i = 0; i < 3100; i++) {
          DebugLog.logNow('t', 'line $i');
        }
        expect(DebugLog.instance.length, DebugLog.maxEntries);
        expect(DebugLog.instance.entries.first, contains('line 100'));
        expect(DebugLog.instance.entries.last, contains('line 3099'));
      } finally {
        DebugLog.instance.clear();
        DebugLog.captureEnabled = false;
      }
    });

    test('zero cost when capture is off: no strings built, no entries',
        () {
      DebugLog.captureEnabled = false;
      DebugLog.instance.clear();
      var built = false;
      DebugLog.log('audio', () {
        built = true;
        return 'expensive ${List.filled(1000, 'x').join()}';
      });
      expect(built, false);
      expect(DebugLog.instance.length, 0);
    });

    test('entries carry timestamp and tag', () {
      DebugLog.captureEnabled = true;
      try {
        DebugLog.instance.clear();
        DebugLog.logNow('audio', 'hello');
        final line = DebugLog.instance.entries.single;
        expect(line, contains('[audio]'));
        expect(line, contains('hello'));
        // [HH:MM:SS.mmm] timestamp prefix.
        expect(line, matches(RegExp(r'^\[\d{2}:\d{2}:\d{2}\.\d{3}\]')));
      } finally {
        DebugLog.instance.clear();
        DebugLog.captureEnabled = false;
      }
    });
  });

  group('DevUnlockCounter', () {
    test('needs exactly 7 taps', () {
      final c = DevUnlockCounter();
      for (var i = 1; i <= 6; i++) {
        expect(c.tap(), 7 - i, reason: 'tap $i');
      }
      expect(c.tap(), 0, reason: '7th tap unlocks');
    });
  });

  group('playback-state broadcast line', () {
    test('includes the exact native controls list', () {
      final line = PlayerController.formatBroadcastLine(
        processingState: 'ready',
        playing: true,
        seqIndex: 1,
        seqLength: 3,
      );
      expect(
          line,
          contains(
              'processingState=ready playing=true controls=[skipToPrevious,pause,stop,skipToNext]'));
    });

    test('single-track sequence has no skip buttons', () {
      final line = PlayerController.formatBroadcastLine(
        processingState: 'ready',
        playing: false,
        seqIndex: 0,
        seqLength: 1,
      );
      expect(line, contains('controls=[play,stop]'));
    });

    test('empty sequence degrades to play/stop', () {
      final line = PlayerController.formatBroadcastLine(
        processingState: 'idle',
        playing: false,
        seqIndex: -1,
        seqLength: 0,
      );
      expect(line, contains('controls=[play,stop]'));
    });
  });

  group('log capture setting', () {
    test('setLogCapture syncs the logger master switch', () async {
      SharedPreferences.setMockInitialValues({});
      DebugLog.captureEnabled = false;
      final s = AppSettings();
      await s.setLogCapture(true);
      expect(DebugLog.captureEnabled, isTrue);
      expect(s.logCapture, isTrue);
      await s.setLogCapture(false);
      expect(DebugLog.captureEnabled, isFalse);
    });

    test('logCapture persists across loads', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.setLogCapture(true);
      final s2 = AppSettings();
      await s2.load();
      expect(s2.logCapture, isTrue);
      expect(DebugLog.captureEnabled, isTrue);
      // Clean up static state for other tests.
      await s2.setLogCapture(false);
    });

    test('devUnlocked persists across loads', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.setDevUnlocked(true);
      final s2 = AppSettings();
      await s2.load();
      expect(s2.devUnlocked, isTrue);
    });
  });

  group('VersionRow 7-tap unlock', () {
    testWidgets('7 taps unlock developer options', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pc = _DevFake();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: VersionRow(pc: pc))),
      );
      expect(pc.settings.devUnlocked, isFalse);
      expect(find.text('Vani $kAppVersion'), findsOneWidget);

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byType(VersionRow));
        await tester.pump();
        expect(pc.settings.devUnlocked, isFalse,
            reason: 'tap ${i + 1} must not unlock yet');
      }
      // 7th tap unlocks (Android's developer-mode convention).
      await tester.tap(find.byType(VersionRow));
      await tester.pump();
      expect(pc.settings.devUnlocked, isTrue);
    });

    testWidgets('tapping the row when unlocked opens Developer options',
        (tester) async {
      SharedPreferences.setMockInitialValues({'set_dev_unlocked': true});
      final pc = _DevFake();
      await pc.settings.load();
      expect(pc.settings.devUnlocked, isTrue);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: VersionRow(pc: pc))),
      );

      await tester.tap(find.byType(VersionRow));
      await tester.pumpAndSettle();
      expect(find.text('Developer options'), findsWidgets);
      expect(find.text('Capture debug logs'), findsOneWidget);
    });
  });
}

class _DevFake extends PlayerController {
  _DevFake() : super.test();
}
