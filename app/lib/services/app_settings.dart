import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide user settings, persisted in SharedPreferences.
///
/// - [iaEnabled]: show Internet Archive shelves/search. Default true.
///   When false the app is Drive + local only.
/// - [autoLoadLyrics]: fetch lyrics when Now Playing opens. Default true.
class AppSettings extends ChangeNotifier {
  static const _kIaEnabled = 'set_ia_enabled';
  static const _kAutoLyrics = 'set_auto_lyrics';

  bool iaEnabled = true;
  bool autoLoadLyrics = true;
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    iaEnabled = prefs.getBool(_kIaEnabled) ?? true;
    autoLoadLyrics = prefs.getBool(_kAutoLyrics) ?? true;
    _loaded = true;
    notifyListeners();
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
}
