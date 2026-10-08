import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/crash_log.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:opentune/services/vani_theme.dart';
import 'package:opentune/widgets/mini_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _track(String id, String title, {String source = 'archive'}) =>
    Track(
      id: id,
      title: title,
      artist: 'Unknown artist',
      license: 'CC0',
      licenseUrl: '',
      artworkUrl: '',
      source: source,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('peek physics (MiniPlayer.rubberBand)', () {
    test('small drags are near-linear (0.62 factor)', () {
      expect(MiniPlayer.rubberBand(0), 0);
      expect(MiniPlayer.rubberBand(100), closeTo(62, 0.001));
      expect(MiniPlayer.rubberBand(120), closeTo(74.4, 0.001));
    });

    test('past full reveal the resistance stiffens (0.18 factor)', () {
      // 120px -> 74.4; every extra px adds only 0.18.
      expect(MiniPlayer.rubberBand(220), closeTo(74.4 + 100 * 0.18, 0.001));
      // Diminishing returns: doubling the over-drag adds little.
      final at220 = MiniPlayer.rubberBand(220);
      final at420 = MiniPlayer.rubberBand(420);
      expect(at420 - at220, lessThan(220 - 120));
    });

    test('hard-clamped at +/-150px (no runaway card)', () {
      expect(MiniPlayer.rubberBand(10000), 150);
      expect(MiniPlayer.rubberBand(-10000), -150);
    });

    test('symmetric for both drag directions', () {
      expect(MiniPlayer.rubberBand(-80), closeTo(-MiniPlayer.rubberBand(80), 0.001));
      expect(MiniPlayer.rubberBand(-500), closeTo(-MiniPlayer.rubberBand(500), 0.001));
    });

    test('monotonic: more finger travel never moves the card less', () {
      double prev = 0;
      for (var raw = 10.0; raw <= 2000; raw += 10) {
        final cur = MiniPlayer.rubberBand(raw);
        expect(cur, greaterThanOrEqualTo(prev));
        prev = cur;
      }
    });
  });

  group('ThemeModeOption', () {
    test('byId resolves every known id, falls back to system', () {
      for (final m in ThemeModeOption.values) {
        expect(ThemeModeOption.byId(m.id), m);
      }
      expect(ThemeModeOption.byId('nope'), ThemeModeOption.system);
      expect(ThemeModeOption.byId(null), ThemeModeOption.system);
    });

    test('effectiveBrightness: system follows phone, others are fixed',
        () {
      expect(ThemeModeOption.system.effectiveBrightness(Brightness.light),
          Brightness.light);
      expect(ThemeModeOption.system.effectiveBrightness(Brightness.dark),
          Brightness.dark);
      expect(ThemeModeOption.light.effectiveBrightness(Brightness.dark),
          Brightness.light);
      expect(ThemeModeOption.dark.effectiveBrightness(Brightness.light),
          Brightness.dark);
      expect(ThemeModeOption.amoled.effectiveBrightness(Brightness.light),
          Brightness.dark);
    });

    test('four modes exist in UI order', () {
      expect(ThemeModeOption.values.map((m) => m.id),
          ['system', 'dark', 'light', 'amoled']);
    });
  });

  group('AppSettings theme mode resolution', () {
    Future<AppSettings> fresh() async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      return s;
    }

    test('default mode is system', () async {
      final s = await fresh();
      expect(s.themeModeId, ThemeModeOption.system.id);
      expect(s.themeMode, ThemeModeOption.system);
    });

    test('theme mode round-trips through prefs', () async {
      final s = await fresh();
      await s.setThemeMode(ThemeModeOption.amoled);
      final reloaded = AppSettings();
      await reloaded.load();
      expect(reloaded.themeMode, ThemeModeOption.amoled);
    });

    test('unknown persisted mode id falls back to system', () async {
      SharedPreferences.setMockInitialValues(
          {'set_theme_mode': 'future_mode'});
      final s = AppSettings();
      await s.load();
      expect(s.themeMode, ThemeModeOption.system);
    });

    test('dark mode: preset Obsidian surface', () async {
      final s = await fresh();
      await s.setThemeMode(ThemeModeOption.dark);
      await s.setMatchSystemColor(false);
      await s.setThemePreset(ThemePreset.plumWave);
      final scheme = s.resolveColorScheme();
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, ThemePreset.plumWave.surfaceTint);
    });

    test('amoled mode: pure black surfaces', () async {
      final s = await fresh();
      await s.setThemeMode(ThemeModeOption.amoled);
      await s.setMatchSystemColor(false);
      final scheme = s.resolveColorScheme();
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, const Color(0xFF000000));
      expect(scheme.surfaceContainerLow, const Color(0xFF000000));
    });

    test('light mode: proper light M3 scheme', () async {
      final s = await fresh();
      await s.setThemeMode(ThemeModeOption.light);
      await s.setMatchSystemColor(false);
      final scheme = s.resolveColorScheme();
      expect(scheme.brightness, Brightness.light);
      // White-ish surface, dark on-surface text — a real light theme,
      // not an inverted dark one.
      expect(scheme.surface.computeLuminance(), greaterThan(0.8));
      expect(scheme.onSurface.computeLuminance(), lessThan(0.2));
    });

    test('system mode follows the platform brightness', () async {
      final s = await fresh();
      await s.setThemeMode(ThemeModeOption.system);
      await s.setMatchSystemColor(false);
      s.setPlatformBrightness(Brightness.light);
      expect(s.resolveColorScheme().brightness, Brightness.light);
      s.setPlatformBrightness(Brightness.dark);
      expect(s.resolveColorScheme().brightness, Brightness.dark);
    });

    test('dynamic color still wins when on and available', () async {
      final s = await fresh();
      await s.setThemeMode(ThemeModeOption.light);
      await s.setMatchSystemColor(true);
      const dyn = ColorScheme.light(primary: Color(0xFF123456));
      s.dynamicLightScheme = dyn;
      expect(s.resolveColorScheme(), dyn);
    });

    test('presets keep working inside every mode', () async {
      final s = await fresh();
      await s.setMatchSystemColor(false);
      await s.setThemePreset(ThemePreset.amberDusk);
      await s.setThemeMode(ThemeModeOption.light);
      final light = s.resolveColorScheme();
      await s.setThemeMode(ThemeModeOption.dark);
      final dark = s.resolveColorScheme();
      // Same seed family (primary hue close), different brightness.
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });
  });

  group('VaniTheme preset schemes per brightness', () {
    test('light preset scheme is a proper white M3 scheme', () {
      final s = VaniTheme.schemeForPreset(ThemePreset.neonMint,
          brightness: Brightness.light);
      expect(s.brightness, Brightness.light);
      expect(s.surface.computeLuminance(), greaterThan(0.8));
    });

    test('amoled pins base surfaces to pure black', () {
      final s = VaniTheme.schemeForPreset(ThemePreset.neonMint,
          brightness: Brightness.dark, amoled: true);
      expect(s.surface, const Color(0xFF000000));
      expect(s.surfaceContainerLowest, const Color(0xFF000000));
    });

    test('default args preserve the legacy dark Obsidian behavior', () {
      final s = VaniTheme.schemeForPreset(ThemePreset.neonMint);
      expect(s.brightness, Brightness.dark);
      expect(s.surface, ThemePreset.neonMint.surfaceTint);
    });
  });

  group('notification controls formula (patched mirror)', () {
    test('always four controls: prev, play/pause, next, shuffle', () {
      final controls = buildVaniNotificationControls(
        hasPrevious: true,
        hasNext: true,
        playing: true,
        shuffleOn: false,
      );
      expect(controls.length, 4);
      expect(controls[0].action, MediaAction.skipToPrevious);
      expect(controls[1].action, MediaAction.pause);
      expect(controls[2].action, MediaAction.skipToNext);
      expect(controls[3].action, MediaAction.rewind);
      // No stop square anywhere.
      expect(
          controls.where((c) => c.action == MediaAction.stop), isEmpty);
    });

    test('paused state shows play', () {
      final controls = buildVaniNotificationControls(
        hasPrevious: false,
        hasNext: false,
        playing: false,
        shuffleOn: false,
      );
      expect(controls[1].action, MediaAction.play);
    });

    test('dimmed icons at the queue ends, full icons mid-queue', () {
      final atStart = buildVaniNotificationControls(
        hasPrevious: false,
        hasNext: true,
        playing: true,
        shuffleOn: false,
      );
      expect(atStart[0].androidIcon,
          'drawable/audio_service_skip_previous_dim');
      expect(atStart[2].androidIcon, 'drawable/audio_service_skip_next');

      final atEnd = buildVaniNotificationControls(
        hasPrevious: true,
        hasNext: false,
        playing: true,
        shuffleOn: false,
      );
      expect(
          atEnd[0].androidIcon, 'drawable/audio_service_skip_previous');
      expect(atEnd[2].androidIcon,
          'drawable/audio_service_skip_next_dim');
    });

    test('shuffle icon reflects shuffle state', () {
      final off = buildVaniNotificationControls(
        hasPrevious: true,
        hasNext: true,
        playing: true,
        shuffleOn: false,
      );
      final on = buildVaniNotificationControls(
        hasPrevious: true,
        hasNext: true,
        playing: true,
        shuffleOn: true,
      );
      expect(off[3].androidIcon, 'drawable/audio_service_shuffle');
      expect(on[3].androidIcon, 'drawable/audio_service_shuffle_on');
      expect(off[3].label, 'Shuffle');
    });

    test('compact indices are prev/play/next (shuffle expanded-only)',
        () {
      expect(vaniCompactActionIndices, [0, 1, 2]);
    });
  });

  group('CrashLog', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp
          .createTemp('vani-crash-test-');
      CrashLog.testDir = tmp;
    });

    tearDown(() async {
      CrashLog.testDir = null;
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('saveCrash writes a timestamped report file', () async {
      await CrashLog.saveCrash(
          StateError('Simulated test crash'), StackTrace.current);
      final reports = await CrashLog.listReports();
      expect(reports.length, 1);
      expect(reports.first.path, contains('vani-crash-'));
      final text = await reports.first.readAsString();
      expect(text, contains('Simulated test crash'));
      expect(text, contains('Stack trace:'));
      expect(text, contains('Vani '));
    });

    test('latestReport returns the newest, null when empty', () async {
      expect(await CrashLog.latestReport(), isNull);
      await CrashLog.saveCrash('first', StackTrace.empty);
      // Ensure distinct timestamps in the filename (1s resolution).
      await Future.delayed(const Duration(milliseconds: 1100));
      await CrashLog.saveCrash('second', StackTrace.empty);
      final latest = await CrashLog.latestReport();
      expect(latest, isNotNull);
      expect(await latest!.readAsString(), contains('second'));
      final reports = await CrashLog.listReports();
      expect(reports.first.path, latest.path);
    });

    test('prunes to the 10 newest reports', () async {
      for (var i = 0; i < 12; i++) {
        await CrashLog.saveCrash('crash $i', StackTrace.empty);
        await Future.delayed(const Duration(milliseconds: 1100));
      }
      final reports = await CrashLog.listReports();
      expect(reports.length, 10);
    });

    test('saveCrash never throws (even on a bad directory)', () async {
      CrashLog.testDir = Directory('/proc/vani-nope-crash-test');
      await CrashLog.saveCrash('boom', StackTrace.empty);
      // No exception — the error path must not crash the crash reporter.
    });
  });

  group('load-timeout message (drive-by fix)', () {
    test('local tracks never mention the connection', () {
      final msg = PlayerController.timeoutMessage(
          _track('t1', 'Local Song', source: 'local'));
      expect(msg, isNot(contains('connection')));
      expect(msg, contains("Couldn't load"));
    });

    test('streamed tracks keep the connection hint', () {
      final archive = PlayerController.timeoutMessage(
          _track('t2', 'Archive Song', source: 'archive'));
      expect(archive, contains('check your connection'));
      final drive = PlayerController.timeoutMessage(
          _track('t3', 'Drive Song', source: 'drive'));
      expect(drive, contains('check your connection'));
    });
  });
}
