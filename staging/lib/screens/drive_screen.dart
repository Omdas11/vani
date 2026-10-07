import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../widgets/track_tile.dart';

/// "My Drive" — the user's own music hosted on Google Drive.
/// Tracks are added by pasting share links or importing an index JSON
/// file; they behave like any other track (play, queue, like,
/// download-for-offline).
class DriveScreen extends StatelessWidget {
  final PlayerController pc;
  const DriveScreen({super.key, required this.pc});

  @override
  Widget build(BuildContext context) {
    final tracks = pc.driveTracks;
    return Scaffold(
      appBar: AppBar(title: const Text('My Drive')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[900]!.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Add your own songs from Google Drive.\n'
              '• In Drive, share each file (or folder) as "Anyone with the link" → Viewer.\n'
              '• Paste the share link below, or host an index.json listing your songs.\n'
              '• Drive\'s free 15 GB is shared with Gmail/Photos, and Google may '
              'throttle heavy streaming ("quota exceeded") — for big libraries a '
              'dedicated music server works better.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add song from link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => _addLinkDialog(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Import index.json'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => _importIndexDialog(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'No Drive songs yet.\nAdd your first link above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...tracks.asMap().entries.map((e) {
              final i = e.key;
              final t = e.value;
              return Dismissible(
                key: ValueKey('drive::${t.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red[900],
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Text('Remove',
                      style: TextStyle(color: Colors.white)),
                ),
                onDismissed: (_) => pc.removeDriveTrack(t),
                child: TrackTile(
                  track: t,
                  contextQueue: tracks,
                  indexInQueue: i,
                  pc: pc,
                  showOfflineBadge: true,
                  onEdit: (track) => _editDialog(context, track),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _addLinkDialog(BuildContext context) {
    final linkCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add song from Google Drive'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: linkCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Paste Drive share link',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    hintText: 'Title (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: artistCtrl,
                decoration: const InputDecoration(
                    hintText: 'Artist (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final t = pc.driveTrackFromLink(
                linkCtrl.text,
                title: titleCtrl.text,
                artist: artistCtrl.text,
              );
              if (t == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Could not read a Drive file from that link.')),
                  );
                }
                return;
              }
              final added = await pc.addDriveTrack(t);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(added
                          ? 'Added "${t.title}"'
                          : 'That song is already in My Drive')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _importIndexDialog(BuildContext context) {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import index.json'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Host a JSON file listing your songs (a Drive file shared '
                'with "Anyone with the link" works), then paste its link:',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://…/index.json',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Format: [{"title":"…","artist":"…","url":"…"}, …]\n'
                '"url" may be a Drive share link or a direct audio URL.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final n = await pc.importDriveIndex(urlCtrl.text);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(n > 0
                          ? 'Imported $n song${n == 1 ? '' : 's'}'
                          : (pc.error ?? 'Nothing imported'))),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _editDialog(BuildContext context, Track track) {
    final titleCtrl = TextEditingController(text: track.title);
    final artistCtrl = TextEditingController(
        text: track.artist == 'Unknown artist' ? '' : track.artist);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit song'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: artistCtrl,
              decoration:
                  const InputDecoration(hintText: 'Artist'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await pc.updateDriveTrack(
                  track, titleCtrl.text, artistCtrl.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
