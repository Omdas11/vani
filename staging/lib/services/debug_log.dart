import 'dart:collection';

import 'package:flutter/foundation.dart';

/// App version — single source of truth for the Settings version row
/// and the log header. Bump with the release.
const String kAppVersion = '1.6.10';

/// In-app debug log: an in-memory ring buffer feeding the Developer
/// options log viewer (Settings → tap Version 7× → Developer options).
///
/// Near-zero cost when capture is off: [log] takes a lazy message
/// builder, so call sites on hot paths build no strings and allocate
/// only a closure when disabled. Use [logNow] for cold paths
/// (startup, errors) where the string is built anyway.
///
/// NOTE: this lives in the UI isolate. The background audio isolate
/// cannot reach it; playback-state entries are logged from the UI
/// isolate's state observer, which mirrors the native controls list
/// exactly (see PlayerController.formatBroadcastLine).
class DebugLog extends ChangeNotifier {
  /// Ring capacity. 3000 timestamped lines ≈ a long listening session.
  static const int maxEntries = 3000;

  /// Master switch, synced from AppSettings.logCapture (persisted).
  static bool captureEnabled = false;

  static final DebugLog instance = DebugLog._();
  DebugLog._();

  final ListQueue<String> _entries = ListQueue<String>();

  List<String> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;

  /// Logs a line. The [message] closure is ONLY evaluated when capture
  /// is enabled.
  static void log(String tag, String Function() message) {
    if (!captureEnabled) return;
    instance._add(tag, message());
  }

  /// Eager variant for cold paths.
  static void logNow(String tag, String message) {
    if (!captureEnabled) return;
    instance._add(tag, message);
  }

  void _add(String tag, String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _entries.add('[$ts][$tag] $message');
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Whole buffer as one string, for copy/share/export.
  String export() => _entries.join('\n');

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

/// Counts taps toward the hidden developer-mode unlock (Android's
/// 7-tap convention). Extracted for unit testing.
class DevUnlockCounter {
  static const int tapsNeeded = 7;
  int _taps = 0;
  int get taps => _taps;

  /// Registers one tap. Returns the taps remaining AFTER this tap;
  /// 0 means "just unlocked".
  int tap() {
    _taps++;
    return tapsNeeded - _taps;
  }

  void reset() => _taps = 0;
}
