import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../widgets/track_tile.dart';
import 'drive_screen.dart';
import 'stats_screen.dart';

/// Library: recently played, liked songs, playlists, offline downloads.
class LibraryScreen extends StatelessWidget {
  final PlayerController pc;
  const LibraryScreen({super.key, required this.pc});

  Future<void> _importFromPhone(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Import from phone'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'files'),
            child: const ListTile(
              leading: Icon(Icons.audiotrack_outlined),
              title: Text('Pick files'),
              subtitle: Text('Choose one or more audio files'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'folder'),
            child: const ListTile(
              leading: Icon(Icons.folder_open_outlined),
              title: Text('Pick a folder'),
              subtitle: Text('Import a whole folder, including subfolders'),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'folder') {
        await _importFolder(context, messenger);
      } else {
        final added = await pc.importLocalFiles();
        messenger.showSnackBar(SnackBar(
          content: Text(added > 0
              ? 'Imported $added track${added == 1 ? '' : 's'} from your phone.'
              : 'No new tracks imported.'),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  /// Folder import with a progress dialog showing file counts.
  Future<void> _importFolder(
      BuildContext context, ScaffoldMessengerState messenger) async {
    final progress = ValueNotifier<(int, int)>((0, 0));
    var dialogOpen = true;
    // Non-dismissible progress dialog driven by the notifier.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (_, v, __) => AlertDialog(
          title: const Text('Importing folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: v.$2 > 0 ? v.$1 / v.$2 : null,
              ),
              const SizedBox(height: 12),
              Text(v.$2 > 0 ? '${v.$1} of ${v.$2} files' : 'Scanning…'),
            ],
          ),
        ),
      ),
    ).then((_) => dialogOpen = false);
    int added = 0;
    try {
      added = await pc.importLocalFolder(
          onProgress: (d, t) => progress.value = (d, t));
    } catch (e) {
      if (dialogOpen && context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      progress.dispose();
      return;
    }
    progress.dispose();
    if (dialogOpen && context.mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(added > 0
          ? 'Imported $added track${added == 1 ? '' : 's'} from the folder.'
          : 'No new tracks imported.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Library')),
      body: AnimatedBuilder(
        animation: pc,
        builder: (_, __) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final liked = pc.likedSongs;
    final names = pc.playlists.keys.toList();
    final dls = pc.downloads;
    final recent = pc.recent;
    return ListView(
        children: [
          if (recent.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Recently played',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 172,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: recent.length,
                itemBuilder: (_, i) {
                  final t = recent[i];
                  return GestureDetector(
                    onTap: () => pc.playTracks(recent, i),
                    child: Container(
                      width: 112,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              TrackArt(t, size: 112, radius: 8),
                              if (t.isDownloaded)
                                const Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Icon(Icons.download_done,
                                      size: 18, color: Colors.white70),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text(t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          _headerTile(
            context,
            icon: Icons.favorite,
            color: const Color(0xFF1DB954),
            title: 'Liked Songs',
            subtitle: '${liked.length} tracks',
            onTap: liked.isEmpty
                ? null
                : () => _openTrackList(context, 'Liked Songs', liked,
                    allowRemove: (t) => pc.toggleLike(t)),
          ),
          _headerTile(
            context,
            icon: Icons.download_done,
            color: Colors.blue,
            title: 'Downloads',
            subtitle: dls.isEmpty
                ? 'Music for offline listening'
                : '${dls.length} tracks · offline ready',
            onTap: dls.isEmpty
                ? null
                : () => _openTrackList(context, 'Downloads', dls,
                    allowRemove: (t) => pc.deleteDownload(t),
                    removeLabel: 'Remove download',
                    showOfflineBadge: true),
          ),
          _headerTile(
            context,
            icon: Icons.cloud_outlined,
            color: const Color(0xFF0F9D58),
            title: 'My Drive',
            subtitle: pc.driveTracks.isEmpty
                ? 'Your songs from Google Drive'
                : '${pc.driveTracks.length} tracks · Google Drive',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DriveScreen(pc: pc),
            )),
          ),
          _headerTile(
            context,
            icon: Icons.smartphone_outlined,
            color: Colors.teal,
            title: 'On this phone',
            subtitle: pc.localTracks.isEmpty
                ? 'Import MP3s from your phone storage'
                : '${pc.localTracks.length} tracks · stored in the app',
            onTap: () => _importFromPhone(context),
          ),
          if (pc.localTracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: TextButton.icon(
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('View imported tracks'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: Colors.grey[300],
                ),
                onPressed: () => _openTrackList(
                  context,
                  'On this phone',
                  pc.localTracks,
                  allowRemove: (t) => pc.removeLocalTrack(t),
                  removeLabel: 'Delete import',
                  showOfflineBadge: true,
                ),
              ),
            ),
          _headerTile(
            context,
            icon: Icons.bar_chart_outlined,
            color: Colors.purple,
            title: 'Your Stats',
            subtitle: 'Listening time, top tracks & artists',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StatsScreen(pc: pc),
            )),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Playlists',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...names.map((n) {
            final tracks = pc.playlists[n]!;
            return ListTile(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.queue_music,
                    color: Colors.white70),
              ),
              title: Text(n,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${tracks.length} tracks'),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'rename') {
                    _renamePlaylistDialog(context, n);
                  } else if (v == 'delete') {
                    pc.deletePlaylist(n);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'rename', child: Text('Rename')),
                  PopupMenuItem(
                      value: 'delete', child: Text('Delete playlist')),
                ],
              ),
              onTap: tracks.isEmpty
                  ? null
                  : () => _openTrackList(context, n, tracks,
                      allowRemove: (t) =>
                          pc.removeFromPlaylist(n, t)),
            );
          }),
          ListTile(
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.add, color: Colors.white70),
            ),
            title: const Text('New playlist'),
            onTap: () => _nameDialog(context, 'New playlist',
                (name) => pc.createPlaylist(name)),
          ),
          const SizedBox(height: 24),
        ],
      );
  }

  Widget _headerTile(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withValues(alpha: 0.9),
            color.withValues(alpha: 0.5)
          ]),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  void _openTrackList(BuildContext context, String title,
      List<Track> tracks,
      {required Future<void> Function(Track) allowRemove,
      String removeLabel = 'Remove',
      bool showOfflineBadge = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play all'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => pc.playTracks(tracks, 0),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  return Dismissible(
                    key: ValueKey('${t.id}::${t.title}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red[900],
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Text(removeLabel,
                          style: const TextStyle(color: Colors.white)),
                    ),
                    onDismissed: (_) => allowRemove(t),
                    child: TrackTile(
                      track: t,
                      contextQueue: tracks,
                      indexInQueue: i,
                      pc: pc,
                      showOfflineBadge: showOfflineBadge,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ));
  }

  void _nameDialog(BuildContext context, String title,
      Future<void> Function(String) onSave,
      {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await onSave(ctrl.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _renamePlaylistDialog(BuildContext context, String oldName) {
    _nameDialog(context, 'Rename playlist',
        (name) => pc.renamePlaylist(oldName, name),
        initial: oldName);
  }
}
