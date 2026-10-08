import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';

/// Persistent crash log: every uncaught error (framework + async gaps)
/// is saved to a timestamped file in the app documents directory, so a
/// crash report survives app restarts and can be shared from Developer
/// options alongside the debug log.
///
/// Wired into the existing error handlers in main.dart
/// ([FlutterError.onError] and [PlatformDispatcher.onError]); the
/// Developer options "Simulate crash" button exercises the same path.
class CrashLog {
  CrashLog._();

  static const _dirName = 'crash-logs';
  static const _keepFiles = 10;

  /// Test hook: when set, crash reports go here instead of the app
  /// documents directory (path_provider has no implementation in unit
  /// tests).
  @visibleForTesting
  static Directory? testDir;

  /// The crash-log directory, created on demand.
  static Future<Directory> _dir() async {
    if (testDir != null) {
      if (!await testDir!.exists()) {
        await testDir!.create(recursive: true);
      }
      return testDir!;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves one crash report. Never throws: a failing crash reporter
  /// must not take down the error path that called it.
  static Future<void> saveCrash(Object error, StackTrace? stack) async {
    try {
      final dir = await _dir();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file = File('${dir.path}/vani-crash-$ts.txt');
      await file.writeAsString(
        'Vani $kAppVersion crash report — ${DateTime.now().toIso8601String()}\n'
        '${'=' * 60}\n'
        'Error: $error\n'
        '${'-' * 60}\n'
        'Stack trace:\n'
        '${stack ?? StackTrace.current}\n',
      );
      // Keep only the newest reports; prune the rest.
      final files = (await dir
              .list()
              .where((e) => e is File && e.path.endsWith('.txt'))
              .toList())
          .cast<File>()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(_keepFiles)) {
        try {
          await f.delete();
        } catch (_) {}
      }
      DebugLog.logNow('crash', 'saved crash report: ${file.path}');
    } catch (e) {
      DebugLog.logNow('crash', 'failed to save crash report: $e');
    }
  }

  /// Newest-first list of saved crash reports. Empty when none exist.
  static Future<List<File>> listReports() async {
    try {
      final dir = await _dir();
      final files = (await dir
              .list()
              .where((e) => e is File && e.path.endsWith('.txt'))
              .toList())
          .cast<File>()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// The newest crash report, or null when none exist.
  static Future<File?> latestReport() async {
    final files = await listReports();
    return files.isEmpty ? null : files.first;
  }
}
