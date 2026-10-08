import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    as mcu;
import 'package:opentune/main.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:opentune/services/vani_theme.dart';
import 'package:opentune/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.6.10 fix-release tests.
///
/// The Light theme still didn't render on the user's phone in v1.6.9
/// even though every unit in the chain tested green in isolation.
/// These tests close the gaps:
///
/// 1. End-to-end reactivity: pump the REAL VaniApp, flip the theme
///    mode via the same AppSettings the UI writes, and assert the
///    MaterialApp's ThemeData follows WITHOUT a restart — for all
///    four modes (System/Dark/Light/AMOLED).
/// 2. The on-device dynamic-color path: mock the platform channel
///    with a realistic wallpaper palette (Int32List, exactly what
///    StandardMethodCodec delivers for the Kotlin int[]) and run the
///    REAL resolveDynamicScheme/refreshDynamicColor, asserting the
///    user's exact combo (Light + match-system-color) resolves light.
/// 3. The v1.6.10 brightness guard: even a pathological dark dynamic
///    scheme can never win in Light mode — the preset takes over.
class _FakePlayerController extends PlayerController {
  _FakePlayerController() : super.test();
}

Brightness _appBrightness(WidgetTester tester) {
  final app =
      tester.widget<MaterialApp>(find.byType(MaterialApp));
  return app.theme!.brightness;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('VaniApp end-to-end theme reactivity (no restart)', () {
    // No dynamic color in these widget tests: the platform channel
    // returns null, so refreshDynamicColor()'s 3s timeout timers never
    // go pending and teardown stays clean.
    setUp(() {
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DynamicColorPlugin.channel,
              (MethodCall call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DynamicColorPlugin.channel, null);
    });

    Future<_FakePlayerController> pumpApp(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final pc = _FakePlayerController();
      await pc.settings.load();
      await pc.settings.setMatchSystemColor(false);
      await tester.pumpWidget(VaniApp(pc: pc));
      await tester.pump();
      return pc;
    }

    testWidgets('Light mode renders a light MaterialApp theme live',
        (tester) async {
      final pc = await pumpApp(tester);

      await pc.settings.setThemeMode(ThemeModeOption.dark);
      await tester.pump();
      expect(_appBrightness(tester), Brightness.dark);

      // The exact user action: pick Light in Look & Feel.
      await pc.settings.setThemeMode(ThemeModeOption.light);
      await tester.pump();

      expect(_appBrightness(tester), Brightness.light,
          reason: 'switching to Light must flip the app theme '
              'without a restart');
      // …and the background reads the live theme (not a stale one).
      final bgElement = tester.element(find.byType(AppBackground));
      expect(Theme.of(bgElement).colorScheme.brightness,
          Brightness.light);
    });

    testWidgets('all four modes resolve correctly through VaniApp',
        (tester) async {
      final pc = await pumpApp(tester);

      await pc.settings.setThemeMode(ThemeModeOption.system);
      pc.settings.setPlatformBrightness(Brightness.light);
      await tester.pump();
      expect(_appBrightness(tester), Brightness.light);

      pc.settings.setPlatformBrightness(Brightness.dark);
      await tester.pump();
      expect(_appBrightness(tester), Brightness.dark);

      await pc.settings.setThemeMode(ThemeModeOption.amoled);
      await tester.pump();
      expect(_appBrightness(tester), Brightness.dark);
      final amoledTheme =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
      expect(amoledTheme.colorScheme.surface, const Color(0xFF000000),
          reason: 'AMOLED must pin surfaces to pure black');
    });
  });

  group('on-device dynamic-color path (mocked platform channel)', () {
    // Realistic wallpaper palette in the exact wire format: the
    // Kotlin plugin returns int[], StandardMethodCodec decodes to
    // Int32List on the Dart side.
    final channelPayload =
        // ignore: deprecated_member_use
        Int32List.fromList(mcu.CorePalette.of(0xFF3B6EA5).asList());

    setUp(() {
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DynamicColorPlugin.channel,
              (MethodCall call) async {
        if (call.method == DynamicColorPlugin.methodName) {
          return channelPayload;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DynamicColorPlugin.channel, null);
    });

    test(
        'user combo (Light + match-system-color) resolves a light '
        'scheme from a real palette', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      await s.refreshDynamicColor();

      expect(s.dynamicColorSupported, isTrue);
      expect(s.dynamicLightScheme, isNotNull);
      expect(s.dynamicLightScheme!.brightness, Brightness.light);

      await s.setThemeMode(ThemeModeOption.light);
      await s.setMatchSystemColor(true);
      final resolved = s.resolveColorScheme();
      expect(resolved.brightness, Brightness.light,
          reason: 'the dynamic light scheme must stay light '
              'end-to-end');
      expect(resolved.surface.computeLuminance(), greaterThan(0.6));
    });

    test('dynamic dark scheme stays dark from a real palette',
        () async {
      final scheme = await resolveDynamicScheme(Brightness.dark);
      expect(scheme, isNotNull);
      expect(scheme!.brightness, Brightness.dark);
    });

    test('v1.6.10 guard: a dark dynamic scheme can never win in '
        'light mode', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      await s.setThemeMode(ThemeModeOption.light);
      await s.setMatchSystemColor(true);
      // Pathological device behavior: the platform hands back a DARK
      // scheme for the light request. The guard must fall back to the
      // preset instead of rendering dark.
      s.dynamicLightScheme =
          const ColorScheme.dark(primary: Color(0xFF123456));
      final resolved = s.resolveColorScheme();
      expect(resolved.brightness, Brightness.light,
          reason: 'light mode must never resolve a dark scheme');
      expect(resolved.surface.computeLuminance(), greaterThan(0.5));
    });
  });
}
