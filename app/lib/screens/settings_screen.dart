import 'package:flutter/material.dart';
import '../services/player_controller.dart';

/// App settings: Internet Archive collections on/off, auto-load lyrics,
/// stats-backend status, and about info.
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Music sources',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
              SwitchListTile(
                title: const Text('Internet Archive collections'),
                subtitle: const Text(
                    'Genre shelves on Home and Archive search. '
                    'Turn off to use only your Drive songs and phone imports.'),
                value: s.iaEnabled,
                activeThumbColor: const Color(0xFF1DB954),
                onChanged: (v) => s.setIaEnabled(v),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Lyrics',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
              SwitchListTile(
                title: const Text('Auto-load lyrics'),
                subtitle: const Text(
                    'Look up synced lyrics when the Now Playing screen opens. '
                    'Lookups use the free lrclib.net database, once per song, '
                    'and are cached on your device.'),
                value: s.autoLoadLyrics,
                activeThumbColor: const Color(0xFF1DB954),
                onChanged: (v) => s.setAutoLoadLyrics(v),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Listening stats',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('About',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
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
