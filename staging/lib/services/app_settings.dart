import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide user settings, persisted in SharedPreferences.
///
/// - [iaEnabled]: show Internet Archive shelves/search. Default true.
///   When false the app is Drive + local only.
/// - [autoLoadLyrics]: fetch lyrics when Now Playing opens. Default true.
/// - [animatedBackground]: slowly-shifting gradient + veena watermark
///   behind every screen. Default true; turn off to save battery.
/// - [dockOrder]: navigation destinations shown in the floating dock, in
///   order. Any subset of [NavDestination.ids], in any order.
class AppSettings extends ChangeNotifier {
  static const _kIaEnabled = 'set_ia_enabled';
  static const _kAutoLyrics = 'set_auto_lyrics';
  static const _kAnimBg = 'set_animated_bg';
  static const _kDockOrder = 'set_dock_order';

  bool iaEnabled = true;
  bool autoLoadLyrics = true;
  bool animatedBackground = true;
  List<String> dockOrder = List.of(NavDestination.defaultOrder);
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    iaEnabled = prefs.getBool(_kIaEnabled) ?? true;
    autoLoadLyrics = prefs.getBool(_kAutoLyrics) ?? true;
    animatedBackground = prefs.getBool(_kAnimBg) ?? true;
    dockOrder = sanitizeDockOrder(prefs.getStringList(_kDockOrder));
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
