import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/vani_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // google_fonts fetches font files at runtime; disable that in tests
    // so no network is hit and the base text theme is used instead.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ThemePreset', () {
    test('byId resolves every known id', () {
      for (final p in ThemePreset.values) {
        expect(ThemePreset.byId(p.id), p);
      }
    });

    test('byId falls back to neonMint for unknown/null ids', () {
      expect(ThemePreset.byId('nope'), ThemePreset.neonMint);
      expect(ThemePreset.byId(null), ThemePreset.neonMint);
    });

    test('four presets exist, neonMint is the default', () {
      expect(ThemePreset.values.length, 4);
      expect(ThemePreset.values.first, ThemePreset.neonMint);
    });
  });

  group('VaniTheme.schemeForPreset', () {
    test('generates a dark scheme per preset', () {
      for (final p in ThemePreset.values) {
        final s = VaniTheme.schemeForPreset(p);
        expect(s.brightness, Brightness.dark);
      }
    });

    test('pins surface to the preset Obsidian tint', () {
      for (final p in ThemePreset.values) {
        expect(VaniTheme.schemeForPreset(p).surface, p.surfaceTint);
      }
    });

    test('presets produce distinct primaries (no monochrome)', () {
      final primaries = ThemePreset.values
          .map((p) => VaniTheme.schemeForPreset(p).primary)
          .toSet();
      expect(primaries.length, ThemePreset.values.length);
    });
  });

  group('VaniTheme.buildTheme', () {
    // google_fonts raises its "font not bundled" error asynchronously
    // even with runtime fetching disabled; absorb it — these tests
    // verify theme structure, not font loading.
    Future<void> withoutFontErrors(Future<void> Function() body) async {
      await runZonedGuarded(
        body,
        (Object e, StackTrace s) {
          if (e.toString().contains('GoogleFonts')) return;
          Error.throwWithStackTrace(e, s);
        },
      );
    }

    test('builds an M3 theme carrying the scheme and radii', () {
      return withoutFontErrors(() async {
        final scheme =
            VaniTheme.schemeForPreset(ThemePreset.plumWave);
        final theme = VaniTheme.buildTheme(
            scheme: scheme, cornerRadius: 20);
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme, scheme);
        expect(theme.extension<VaniRadii>()!.card, 20);
        // Expressive component theming is present.
        expect(
            theme.filledButtonTheme.style?.shape
                ?.resolve({WidgetState.selected}),
            isA<StadiumBorder>());
        expect(theme.dialogTheme.shape, isNotNull);
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
      });
    });

    test('clamps corner radius to 8..32', () {
      return withoutFontErrors(() async {
        final scheme =
            VaniTheme.schemeForPreset(ThemePreset.neonMint);
        expect(
            VaniTheme.buildTheme(scheme: scheme, cornerRadius: 4)
                .extension<VaniRadii>()!
                .card,
            8);
        expect(
            VaniTheme.buildTheme(scheme: scheme, cornerRadius: 99)
                .extension<VaniRadii>()!
                .card,
            32);
      });
    });

    test('VaniRadii lerp/copyWith behave', () {
      const a = VaniRadii(card: 8);
      const b = VaniRadii(card: 32);
      expect(a.lerp(b, 0.5).card, 20);
      expect(a.copyWith(card: 16).card, 16);
      expect(a.sheet, greaterThan(a.card));
    });
  });

  group('AppSettings theme persistence', () {
    test('defaults: neonMint preset, match-system on, radius 24',
        () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      expect(s.themePresetId, ThemePreset.neonMint.id);
      expect(s.matchSystemColor, isTrue);
      expect(s.cornerRadius, 24);
    });

    test('preset / match-system / radius round-trip through prefs',
        () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      await s.setThemePreset(ThemePreset.amberDusk);
      await s.setMatchSystemColor(false);
      await s.setCornerRadius(12);

      final reloaded = AppSettings();
      await reloaded.load();
      expect(reloaded.themePresetId, ThemePreset.amberDusk.id);
      expect(reloaded.matchSystemColor, isFalse);
      expect(reloaded.cornerRadius, 12);
    });

    test('unknown persisted preset id falls back to neonMint', () async {
      SharedPreferences.setMockInitialValues(
          {'set_theme_preset': 'future_preset'});
      final s = AppSettings();
      await s.load();
      expect(s.themePreset, ThemePreset.neonMint);
    });

    test('corner radius is clamped on load and set', () async {
      SharedPreferences.setMockInitialValues(
          {'set_corner_radius': 99.0});
      final s = AppSettings();
      await s.load();
      expect(s.cornerRadius, 32);
      await s.setCornerRadius(1);
      expect(s.cornerRadius, 8);
    });
  });

  group('AppSettings.resolveColorScheme', () {
    Future<AppSettings> fresh() async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      return s;
    }

    test('uses the fixed preset when match-system is off', () async {
      final s = await fresh();
      await s.setThemePreset(ThemePreset.periwinkle);
      await s.setMatchSystemColor(false);
      // Even with a dynamic scheme available, off means preset.
      s.dynamicDarkScheme = const ColorScheme.dark(
          primary: Color(0xFF123456));
      expect(s.resolveColorScheme().surface,
          ThemePreset.periwinkle.surfaceTint);
    });

    test('uses the dynamic scheme when on and available', () async {
      final s = await fresh();
      await s.setMatchSystemColor(true);
      const dynamicScheme =
          ColorScheme.dark(primary: Color(0xFF123456));
      s.dynamicDarkScheme = dynamicScheme;
      expect(s.resolveColorScheme(), dynamicScheme);
    });

    test('falls back to preset when dynamic unavailable', () async {
      final s = await fresh();
      await s.setMatchSystemColor(true);
      s.dynamicDarkScheme = null;
      await s.setThemePreset(ThemePreset.plumWave);
      expect(s.resolveColorScheme().surface,
          ThemePreset.plumWave.surfaceTint);
    });
  });

  group('dynamic color platform resolution', () {
    test('resolveDynamicDarkScheme returns null without a platform',
        () async {
      // No Android method channel in unit tests: must degrade
      // gracefully, never throw.
      expect(await resolveDynamicDarkScheme(), isNull);
    });

    test('refreshDynamicColor marks unsupported without a platform',
        () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      await s.refreshDynamicColor();
      expect(s.dynamicColorSupported, isFalse);
      expect(s.dynamicDarkScheme, isNull);
      // …and the app falls back to the preset scheme.
      expect(s.resolveColorScheme().surface,
          ThemePreset.neonMint.surfaceTint);
    });
  });
}
