import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/player_controller.dart';
import 'ai_fixer_screen.dart';

/// App settings: music sources, lyrics, navigation dock, appearance,
/// listening stats, AI Fixer (beta), and about info.
class SettingsScreen extends StatelessWidget {
  final PlayerController pc;
  const SettingsScreen({super.key, required this.pc});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pc.settings,
      builder: (_, __) {
        final s = pc.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              const _SectionHeader('Music sources'),
              SwitchListTile(
                title: const Text('Internet Archive collections'),
                subtitle: const Text(
                    'Genre shelves on Home and Archive search. '
                    'Turn off to use only your Drive songs and phone imports.'),
                value: s.iaEnabled,
                activeThumbColor: const Color(0xFF1DB954),
                onChanged: (v) => s.setIaEnabled(v),
              ),
              const _SectionHeader('Lyrics'),
              SwitchListTile(
                title: const Text('Auto-load lyrics'),
                subtitle: const Text(
                    'Look up synced lyrics when the Now Playing screen opens. '
                    'Lookups use free lyrics databases (lrclib.net, KuGou), '
                    'once per song, and are cached on your device.'),
                value: s.autoLoadLyrics,
                activeThumbColor: const Color(0xFF1DB954),
                onChanged: (v) => s.setAutoLoadLyrics(v),
              ),
              const _SectionHeader('Navigation'),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('Customize dock'),
                subtitle: Text(
                    '${s.dockOrder.length} of ${NavDestination.ids.length} destinations shown'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => _DockEditor(settings: s)),
                ),
              ),
              const _SectionHeader('Appearance'),
              SwitchListTile(
                title: const Text('Animated background'),
                subtitle: const Text(
                    'Slowly-shifting gradient with the Vani watermark. '
                    'Turn off to save battery.'),
                value: s.animatedBackground,
                activeThumbColor: const Color(0xFF1DB954),
                onChanged: (v) => s.setAnimatedBackground(v),
              ),
              const _SectionHeader('Tools'),
              ListTile(
                leading: const Icon(Icons.auto_fix_high_outlined,
                    color: Color(0xFF1DB954)),
                title: const Row(
                  children: [
                    Text('AI Fixer'),
                    SizedBox(width: 8),
                    _BetaChip(),
                  ],
                ),
                subtitle: const Text(
                    'Clean up filenames, fix metadata and find lyrics '
                    'with AI. Uses your own free Gemini API key.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AiFixerScreen(pc: pc)),
                ),
              ),
              const _SectionHeader('Listening stats'),
              ListTile(
                leading: const Icon(Icons.cloud_done_outlined,
                    color: Color(0xFF1DB954)),
                title: const Text('Stats backend'),
                subtitle: Text(
                  pc.stats.ready
                      ? 'Connected — anonymous device stats are being recorded.'
                      : 'Not connected — stats stay on this device only.',
                ),
              ),
              const _SectionHeader('About'),
              const ListTile(
                leading: Icon(Icons.album_outlined),
                title: Text('Vani'),
                subtitle: Text(
                    'A music player for open-licensed music.\n'
                    'Archive tracks: CC0 / CC-BY via the Internet Archive.\n'
                    'Your Drive and phone songs are yours — the app only streams them.'),
              ),
              const ListTile(
                leading: Icon(Icons.privacy_tip_outlined),
                title: Text('Privacy'),
                subtitle: Text(
                    'No accounts, no ads, no tracking SDKs. '
                    'Listening stats use an anonymous device id — '
                    'no email, no name, nothing identifiable.'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey)),
    );
  }
}

class _BetaChip extends StatelessWidget {
  const _BetaChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1DB954).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: const Color(0xFF1DB954).withValues(alpha: 0.4)),
      ),
      child: const Text('BETA',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1DB954))),
    );
  }
}

/// Reorderable + toggleable dock destinations. The last visible
/// destination cannot be removed (the dock must show something).
class _DockEditor extends StatefulWidget {
  final AppSettings settings;
  const _DockEditor({required this.settings});

  @override
  State<_DockEditor> createState() => _DockEditorState();
}

class _DockEditorState extends State<_DockEditor> {
  /// All destinations in display order; [_visible] decides dock membership.
  late List<String> _all;
  late Set<String> _visible;

  @override
  void initState() {
    super.initState();
    final order = widget.settings.dockOrder;
    _visible = order.toSet();
    _all = [
      ...order,
      for (final d in NavDestination.all)
        if (!order.contains(d.id)) d.id,
    ];
  }

  Future<void> _save() async {
    await widget.settings
        .setDockOrder([for (final id in _all) if (_visible.contains(id)) id]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize dock'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Done')),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Choose which destinations appear in the floating dock. '
              'Drag the handle to reorder.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _all.length,
              onReorderItem: (oldI, newI) {
                setState(() {
                  // onReorderItem already adjusts newI for the removal.
                  final moved = _all.removeAt(oldI);
                  _all.insert(newI.clamp(0, _all.length), moved);
                });
              },
              itemBuilder: (_, i) {
                final d = NavDestination.byId(_all[i]);
                final visible = _visible.contains(d.id);
                return CheckboxListTile(
                  key: ValueKey(d.id),
                  value: visible,
                  activeColor: const Color(0xFF1DB954),
                  onChanged: (_visible.length == 1 && visible)
                      ? null // can't remove the last one
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _visible.add(d.id);
                            } else {
                              _visible.remove(d.id);
                            }
                          });
                        },
                  title: Text(d.label),
                  secondary: Icon(d.icon),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
