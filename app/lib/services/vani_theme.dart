import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    as mcu;

/// The four fixed accent presets (per the PixelPlayer study's palette
/// recommendation). Neon Mint is the legacy Obsidian Sonic look and the
/// default; the other three move the app off the all-green monochrome.
/// All are dark schemes on near-black tinted surfaces.
enum ThemePreset {
  neonMint(
    'neon_mint',
    'Neon Mint',
    'The classic Vani green',
    Color(0xFF00E59B),
    Color(0xFF0A0F0D),
  ),
  plumWave(
    'plum_wave',
    'Plum Wave',
    'PixelPlayer now-playing plum',
    Color(0xFFD9A7C0),
    Color(0xFF141014),
  ),
  periwinkle(
    'periwinkle',
    'Periwinkle',
    'PixelPlayer home blue',
    Color(0xFFB4C5FF),
    Color(0xFF0E1116),
  ),
  amberDusk(
    'amber_dusk',
    'Amber Dusk',
    'Warm Auxio-style amber',
    Color(0xFFFFB86B),
    Color(0xFF14100B),
  );

  final String id;
  final String label;
  final String subtitle;
  final Color seed;
  final Color surfaceTint;

  const ThemePreset(
      this.id, this.label, this.subtitle, this.seed, this.surfaceTint);

  /// Unknown ids (e.g. from a future preset list) fall back to the
  /// default instead of crashing.
  static ThemePreset byId(String? id) => ThemePreset.values
      .firstWhere((p) => p.id == id, orElse: () => ThemePreset.neonMint);
}

/// User-adjustable corner-radius token, exposed through the Theme so any
/// widget can read it via [VaniTheme.radiiOf]. Drives card / sheet /
/// dialog radii app-wide (PixelPlayer pattern 15).
@immutable
class VaniRadii extends ThemeExtension<VaniRadii> {
  /// Base radius in dp, from the Look & Feel slider (8..32).
  final double card;

  const VaniRadii({required this.card});

  double get sheet => (card + 8).clamp(16.0, 36.0);
  double get dialog => (card + 4).clamp(16.0, 32.0);

  @override
  VaniRadii copyWith({double? card}) => VaniRadii(card: card ?? this.card);

  @override
  VaniRadii lerp(ThemeExtension<VaniRadii>? other, double t) {
    if (other is! VaniRadii) return this;
    return VaniRadii(card: card + (other.card - card) * t);
  }
}

/// Vani's Material 3 Expressive theme factory.
///
/// - Fixed presets: full dark [ColorScheme]s generated from the preset
///   seed via [ColorScheme.fromSeed], with the surface pinned to the
///   preset's near-black "Obsidian" tint. Tonal container roles stay
///   seed-derived so any preset keeps M3 tonal layering.
/// - Dynamic color: when the user enables "Match system theme color" and
///   the platform (Android 12+) supplies a palette, the OS-provided dark
///   scheme is used unmodified.
class VaniTheme {
  VaniTheme._();

  /// Full M3 dark ColorScheme for [preset].
  static ColorScheme schemeForPreset(ThemePreset preset) {
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: Brightness.dark,
    );
    // Obsidian feel: near-black tinted surface; the seed-tinted
    // container roles are kept for tonal layering.
    return scheme.copyWith(surface: preset.surfaceTint);
  }

  /// Dark ColorScheme derived from album artwork, for tinting the
  /// mini-player card (PixelPlayer/Namida dynamic-tint pattern).
  static ColorScheme schemeForArtwork(Color artColor) =>
      ColorScheme.fromSeed(
          seedColor: artColor, brightness: Brightness.dark);

  static double radiiOf(BuildContext context) =>
      Theme.of(context).extension<VaniRadii>()?.card ?? 24;

  /// Obsidian Sonic typography: Sora for display/titles, Inter for body
  /// (google_fonts fetches the files on first use; offline it falls back
  /// to platform fonts). The PixelPlayer study could not confirm a better
  /// pick (Google Sans Flex is unlicensed), so Sora+Inter stay.
  static TextTheme textTheme() {
    final base = ThemeData.dark().textTheme;
    try {
      final display = GoogleFonts.soraTextTheme(base);
      final body = GoogleFonts.interTextTheme(base);
      return body.copyWith(
        displayLarge: display.displayLarge,
        displayMedium: display.displayMedium,
        displaySmall: display.displaySmall,
        headlineLarge: display.headlineLarge,
        headlineMedium: display.headlineMedium,
        headlineSmall: display.headlineSmall,
        titleLarge: display.titleLarge,
        titleMedium: display.titleMedium,
        titleSmall: display.titleSmall,
      );
    } catch (_) {
      // google_fonts throws synchronously when runtime fetching is
      // disabled and the font isn't bundled (unit tests). Fall back to
      // the platform text theme rather than crashing theme creation.
      return base;
    }
  }

  /// Builds the full M3 Expressive ThemeData for [scheme].
  ///
  /// Signature pieces are kept but restyled: the floating dock, vinyl
  /// player, holographic effects and veena watermark all read their
  /// colors from the scheme instead of a hardcoded green.
  static ThemeData buildTheme({
    required ColorScheme scheme,
    double cornerRadius = 24,
  }) {
    final r = cornerRadius.clamp(8.0, 32.0);
    final radii = VaniRadii(card: r);
    const pill = StadiumBorder();
    final cardShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.card));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme(),
      extensions: [radii],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      // ---- Expressive buttons: pills everywhere ----
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: pill,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: pill),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pill),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
      ),
      // ---- Chips & segmented controls: large expressive pills ----
      chipTheme: ChipThemeData.fromDefaults(
        primaryColor: scheme.primary,
        secondaryColor: scheme.surfaceContainerHighest,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ).copyWith(
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: pill,
          selectedForegroundColor: scheme.onSecondaryContainer,
          selectedBackgroundColor: scheme.secondaryContainer,
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ).copyWith(
          // The outer container is a single large pill.
          shape: WidgetStateProperty.all(pill),
        ),
      ),
      // ---- Cards, dialogs, sheets ----
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radii.dialog)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radii.sheet)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
      // ---- Inputs ----
      searchBarTheme: SearchBarThemeData(
        backgroundColor:
            WidgetStateProperty.all(scheme.surfaceContainerHigh),
        shape: WidgetStateProperty.all(pill),
        hintStyle: WidgetStateProperty.all(
            TextStyle(color: scheme.onSurfaceVariant)),
        padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      // ---- Toggles & sliders ----
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      // ---- Navigation ----
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: states.contains(WidgetState.selected)
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant)),
      ),
      tabBarTheme: TabBarThemeData(
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: scheme.secondaryContainer,
        ),
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

/// Resolves the wallpaper-derived dark ColorScheme via the
/// `dynamic_color` platform channel (Android 12+). Returns null when the
/// platform has no dynamic color (older Android, or the channel missing).
///
/// NOTE: dynamic_color 2.1.0's own `toColorScheme()` extension targets the
/// new `material_ui` package's forked `ColorScheme` type, which is not
/// Flutter's `ColorScheme`. So this replicates its conversion logic
/// (fromSeed + exact OS role overrides) with Flutter types, using the
/// pure-Dart `material_color_utilities` Scheme directly.
Future<ColorScheme?> resolveDynamicDarkScheme() async {
  try {
    final palette = await DynamicColorPlugin.getCorePalette()
        .timeout(const Duration(seconds: 3));
    if (palette == null) return null;
    // Scheme.darkFromCorePalette remains the supported CorePalette→roles
    // conversion; migrating to DynamicScheme would mean hand-mapping ~30
    // roles with no behavior change.
    // ignore: deprecated_member_use
    final s = mcu.Scheme.darkFromCorePalette(palette);
    Color c(int argb) => Color(argb);
    // Seed from the OS primary so the newer roles (surfaceContainer*,
    // *Fixed*) that Scheme doesn't define still get sensible
    // seed-derived values; then override every role the OS defines.
    return ColorScheme.fromSeed(
      seedColor: c(s.primary),
      brightness: Brightness.dark,
    ).copyWith(
      primary: c(s.primary),
      onPrimary: c(s.onPrimary),
      primaryContainer: c(s.primaryContainer),
      onPrimaryContainer: c(s.onPrimaryContainer),
      secondary: c(s.secondary),
      onSecondary: c(s.onSecondary),
      secondaryContainer: c(s.secondaryContainer),
      onSecondaryContainer: c(s.onSecondaryContainer),
      tertiary: c(s.tertiary),
      onTertiary: c(s.onTertiary),
      tertiaryContainer: c(s.tertiaryContainer),
      onTertiaryContainer: c(s.onTertiaryContainer),
      error: c(s.error),
      onError: c(s.onError),
      errorContainer: c(s.errorContainer),
      onErrorContainer: c(s.onErrorContainer),
      outline: c(s.outline),
      outlineVariant: c(s.outlineVariant),
      surface: c(s.surface),
      onSurface: c(s.onSurface),
      // surfaceVariant was renamed surfaceContainerHighest (same tone).
      surfaceContainerHighest: c(s.surfaceVariant),
      onSurfaceVariant: c(s.onSurfaceVariant),
      inverseSurface: c(s.inverseSurface),
      onInverseSurface: c(s.inverseOnSurface),
      inversePrimary: c(s.inversePrimary),
      shadow: c(s.shadow),
      surfaceTint: c(s.primary),
      scrim: c(s.scrim),
    );
  } catch (_) {
    return null;
  }
}
