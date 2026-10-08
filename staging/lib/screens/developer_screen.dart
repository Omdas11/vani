import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/crash_log.dart';
import '../services/debug_log.dart';
import '../services/player_controller.dart';

/// Developer options: in-app debug-log capture for diagnosing
/// device-specific issues (e.g. notification controls) without adb.
///
/// Entry: Settings → tap the "Version" row 7 times (Android convention).
/// Flow: enable "Capture debug logs" → reproduce the issue → back here →
/// "Share log file" (or "Copy logs") → send the text to the developer.
class DeveloperScreen extends StatefulWidget {
  final PlayerController pc;
  const DeveloperScreen({super.key, required this.pc});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;
  bool _sharing = false;

  static const _shareChannel = MethodChannel('vani/share_log');

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Jump to the newest entries after a frame, when auto-scroll is on.
  void _maybeAutoScroll() {
    if (!_autoScroll || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _copyLogs() async {
    final text = DebugLog.instance.export();
    await Clipboard.setData(ClipboardData(
        text: text.isEmpty ? '(log is empty)' : text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(text.isEmpty
              ? 'Log is empty — enable capture and reproduce first.'
              : 'Copied ${DebugLog.instance.length} log lines.')),
    );
  }

  Future<void> _shareFile(File file) async {
    try {
      await _shareChannel
          .invokeMethod('shareFile', {'path': file.path});
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  Future<void> _shareLogFile() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file = File('${dir.path}/vani-log-$ts.txt');
      await file.writeAsString(
          'Vani $kAppVersion debug log — ${DateTime.now().toIso8601String()}\n'
          '${'=' * 60}\n'
          '${DebugLog.instance.export()}\n');
      await _shareFile(file);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareCrashLog() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final latest = await CrashLog.latestReport();
      if (!mounted) return;
      if (latest == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No crash reports yet — tap "Simulate crash" first.')),
        );
        return;
      }
      await _shareFile(latest);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Throws a test exception through the real framework error path
  /// (FlutterError.onError), where it is captured into the debug log
  /// and persisted as a crash report — the same pipeline a genuine
  /// crash travels. The app itself survives: only the test throw is
  /// "crashing".
  void _simulateCrash() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      throw StateError(
          'Simulated test crash from Developer options (no real crash)');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Test crash thrown — check the log and share the crash report.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.pc.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([s, DebugLog.instance]),
      builder: (_, __) {
        _maybeAutoScroll();
        final entries = DebugLog.instance.entries;
        return Scaffold(
          appBar: AppBar(title: const Text('Developer options')),
          body: Column(
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SwitchListTile(
                  title: const Text('Capture debug logs',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'In-memory ring buffer (last 3000 lines). '
                      'Near-zero cost when off. Enable, reproduce the '
                      'issue, then share the log.'),
                  value: s.logCapture,
                  onChanged: (v) => s.setLogCapture(v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy logs'),
                        onPressed: _copyLogs,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _sharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.share, size: 18),
                        label: const Text('Share log file'),
                        onPressed: _sharing ? null : _shareLogFile,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bug_report_outlined,
                            size: 18),
                        label: const Text('Simulate crash'),
                        onPressed: _simulateCrash,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _sharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(
                                Icons.warning_amber_outlined,
                                size: 18),
                        label: const Text('Share crash log'),
                        onPressed:
                            _sharing ? null : _shareCrashLog,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear'),
                        onPressed: () => DebugLog.instance.clear(),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(
                  children: [
                    Text('${entries.length} lines',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    const Text('Auto-scroll'),
                    Switch(
                      value: _autoScroll,
                      onChanged: (v) =>
                          setState(() => _autoScroll = v),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            s.logCapture
                                ? 'Capture is on — interact with the app and lines will appear here.'
                                : 'Capture is off. Turn it on above, then reproduce the issue.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                            12, 8, 12, 200),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            entries[i],
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: _tagColor(
                                  entries[i], scheme),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Tag-based tint so error/audio lines stand out in the viewer.
  Color _tagColor(String line, ColorScheme scheme) {
    if (line.contains('[error]')) return scheme.error;
    if (line.contains('[audio]')) return scheme.primary;
    if (line.contains('[eq]')) return scheme.tertiary;
    return scheme.onSurfaceVariant;
  }
}
