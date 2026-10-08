import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_log.dart';
import 'vani_theme.dart';

/// App-wide user settings, persisted in SharedPreferences.
///
/// - [iaEnabled]: show Internet Archive shelves/search. Default true.
///   When false the app is Drive + local only.
/// - [autoLoadLyrics]: fetch lyrics when Now Playing opens. Default true.
/// - [animatedBackground]: slowly-shifting gradient + veena watermark
///   behind every screen. Default true; turn off to save battery.
/// - [dockOrder]: navigation destinations shown in the floating dock, in
///   order. Any subset of [NavDestination.ids], in any order.
/// - [themePresetId]: fixed accent preset (see [ThemePreset]); default
///   Neon Mint (the legacy Obsidian Sonic look).
/// - [themeModeId]: theme brightness mode (see [ThemeModeOption]);
///   default System (follow the phone).
/// - [matchSystemColor]: follow the wallpaper-derived Material You
///   palette on Android 12+. Default true; falls back to the preset when
///   the platform has no dynamic color.
/// - [cornerRadius]: user-adjustable card/button radius (8..32 dp),
///   exposed to widgets via the [VaniRadii] theme extension.
class AppSettings extends ChangeNotifier {
  static const _kIaEnabled = 'set_ia_enabled';
  static const _kAutoLyrics = 'set_auto_lyrics';
  static const _kAnimBg = 'set_animated_bg';
  static const _kDockOrder = 'set_dock_order';
  static const _kThemePreset = 'set_theme_preset';
  static const _kThemeMode = 'set_theme_mode';
  static const _kMatchSystem = 'set_match_system_color';
  static const _kCornerRadius = 'set_corner_radius';
  static const _kDevUnlocked = 'set_dev_unlocked';
  static const _kLogCapture = 'set_log_capture';

  bool iaEnabled = true;
  bool autoLoadLyrics = true;
  bool animatedBackground = true;
  List<String> dockOrder = List.of(NavDestination.defaultOrder);

  String themePresetId = ThemePreset.neonMint.id;
  String themeModeId = ThemeModeOption.system.id;
  bool matchSystemColor = true;
  double cornerRadius = 24;

  /// Developer mode: unlocked by tapping the Settings version row 7×.
  /// Persisted; gates the Developer options screen.
  bool devUnlocked = false;

  /// In-app debug-log capture (Developer options). Default off; when on,
  /// diagnostic lines go to DebugLog's in-memory ring buffer.
  bool logCapture = false;

  /// Last wallpaper-derived dark scheme from the platform, or null when
  /// the platform has no dynamic color (pre-Android 12) / hasn't
  /// responded yet.
  ColorScheme? dynamicDarkScheme;

  /// Light-mode counterpart, for the Light theme mode (or System mode
  /// when the phone is in light mode).
  ColorScheme? dynamicLightScheme;

  /// The phone's current platform brightness, synced from main.dart
  /// (init + platform-brightness observer). Defaults to dark so unit
  /// tests and pre-first-frame builds resolve the legacy dark theme.
  Brightness platformBrightness = Brightness.dark;

  /// True once the platform has actually supplied a dynamic palette.
  /// Drives the "Match system theme color" toggle's availability: on
  /// older Android the toggle shows as unavailable.
  bool dynamicColorSupported = false;

  bool _loaded = false;

  bool get loaded => _loaded;

  ThemePreset get themePreset => ThemePreset.byId(themePresetId);

  ThemeModeOption get themeMode => ThemeModeOption.byId(themeModeId);

  /// The effective scheme for the whole app, resolved for the
  /// current [themeMode]:
  /// - System: follows [platformBrightness]; Dark: always dark;
  ///   Light: always light; AMOLED: pure-black dark.
  /// - When "Match system theme color" is on and the platform supplied
  ///   a dynamic palette for the effective brightness, it wins;
  ///   otherwise the fixed accent preset (Light = proper white M3,
  ///   AMOLED = pure-black variant, Dark = Obsidian family).
  /// Pure logic: unit-testable.
  ColorScheme resolveColorScheme() {
    final mode = themeMode;
    final brightness = mode.effectiveBrightness(platformBrightness);
    if (matchSystemColor) {
      final dynamicScheme = brightness == Brightness.light
          ? dynamicLightScheme
          : dynamicDarkScheme;
      if (dynamicScheme != null) return dynamicScheme;
    }
    return VaniTheme.schemeForPreset(
      themePreset,
      brightness: brightness,
      amoled: mode == ThemeModeOption.amoled,
    );
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    iaEnabled = prefs.getBool(_kIaEnabled) ?? true;
    autoLoadLyrics = prefs.getBool(_kAutoLyrics) ?? true;
    animatedBackground = prefs.getBool(_kAnimBg) ?? true;
    dockOrder = sanitizeDockOrder(prefs.getStringList(_kDockOrder));
    themePresetId =
        prefs.getString(_kThemePreset) ?? ThemePreset.neonMint.id;
    // Unknown ids (e.g. from a newer preset list) fall back cleanly.
    themePresetId = ThemePreset.byId(themePresetId).id;
    themeModeId = prefs.getString(_kThemeMode) ?? ThemeModeOption.system.id;
    themeModeId = ThemeModeOption.byId(themeModeId).id;
    matchSystemColor = prefs.getBool(_kMatchSystem) ?? true;
    cornerRadius =
        (prefs.getDouble(_kCornerRadius) ?? 24).clamp(8.0, 32.0);
    devUnlocked = prefs.getBool(_kDevUnlocked) ?? false;
    logCapture = prefs.getBool(_kLogCapture) ?? false;
    // Sync the logger's master switch as early as possible so startup
    // lines are captured when the user left capture on.
    DebugLog.captureEnabled = logCapture;
    _loaded = true;
    notifyListeners();
  }

  /// Drops unknown ids and re-adds any missing known ids at the end, so
  /// the dock can never end up empty or reference a removed destination.
  /// Public for testing.
  static List<String> sanitizeDockOrder(List<String>? raw) {
    if (raw == null || raw.isEmpty) {
      return List.of(NavDestination.defaultOrder);
    }
    final known = NavDestination.ids.toSet();
    final seen = <String>[];
    for (final id in raw) {
      if (known.contains(id) && !seen.contains(id)) seen.add(id);
    }
    for (final id in NavDestination.ids) {
      if (!seen.contains(id)) seen.add(id);
    }
    return seen.isEmpty ? List.of(NavDestination.defaultOrder) : seen;
  }

  Future<void> setIaEnabled(bool v) async {
    iaEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIaEnabled, v);
  }

  Future<void> setAutoLoadLyrics(bool v) async {
    autoLoadLyrics = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoLyrics, v);
  }

  Future<void> setAnimatedBackground(bool v) async {
    animatedBackground = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnimBg, v);
  }

  /// Visible dock destinations in order. The last one cannot be removed.
  Future<void> setDockOrder(List<String> v) async {
    final clean = sanitizeDockOrder(v);
    if (clean.isEmpty) return;
    dockOrder = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDockOrder, clean);
  }

  Future<void> setThemePreset(ThemePreset preset) async {
    themePresetId = preset.id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePreset, preset.id);
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    themeModeId = mode.id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.id);
  }

  /// Synced from the platform brightness observer in main.dart; rebuilds
  /// the theme when the phone flips between light and dark (System mode).
  void setPlatformBrightness(Brightness b) {
    if (platformBrightness == b) return;
    platformBrightness = b;
    notifyListeners();
  }

  Future<void> setMatchSystemColor(bool v) async {
    matchSystemColor = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMatchSystem, v);
  }

  Future<void> setCornerRadius(double v) async {
    cornerRadius = v.clamp(8.0, 32.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCornerRadius, cornerRadius);
  }

  /// Unlocks Developer options (hidden 7-tap entry on the version row).
  Future<void> setDevUnlocked(bool v) async {
    devUnlocked = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDevUnlocked, v);
  }

  /// Toggles in-app debug-log capture. Syncs DebugLog's master switch
  /// immediately so the toggle takes effect without a restart.
  Future<void> setLogCapture(bool v) async {
    logCapture = v;
    DebugLog.captureEnabled = v;
    if (v) DebugLog.logNow('app', 'log capture enabled by user');
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLogCapture, v);
  }

  /// (Re-)resolves the wallpaper-derived dynamic palette from the
  /// platform. Safe to call any time: on pre-Android 12 (or any
  /// failure) it clears the dynamic scheme and marks dynamic color
  /// unsupported, so the app falls back to the fixed preset.
  /// Called once at startup and again on every app resume, so a
  /// wallpaper change re-themes the app.
  Future<void> refreshDynamicColor() async {
    final results = await Future.wait([
      resolveDynamicDarkScheme(),
      resolveDynamicLightScheme(),
    ]);
    dynamicDarkScheme = results[0];
    dynamicLightScheme = results[1];
    dynamicColorSupported =
        dynamicDarkScheme != null || dynamicLightScheme != null;
    notifyListeners();
  }
}

/// Navigation destinations available for the floating dock.
class NavDestination {
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const NavDestination(this.id, this.label, this.icon, this.selectedIcon);

  static const List<NavDestination> all = [
    NavDestination(
        'home', 'Home', Icons.home_outlined, Icons.home),
    NavDestination(
        'search', 'Search', Icons.search_outlined, Icons.search),
    NavDestination('library', 'Library', Icons.library_music_outlined,
        Icons.library_music),
    NavDestination(
        'stats', 'Stats', Icons.bar_chart_outlined, Icons.bar_chart),
    NavDestination('settings', 'Settings', Icons.settings_outlined,
        Icons.settings),
  ];

  static List<String> get ids => all.map((d) => d.id).toList();
  static const List<String> defaultOrder = ['home', 'search', 'library'];

  static NavDestination byId(String id) =>
      all.firstWhere((d) => d.id == id, orElse: () => all[0]);
}
