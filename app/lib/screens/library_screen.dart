import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import '../widgets/expressive.dart';
import '../widgets/track_art.dart';
import '../widgets/track_tile.dart';
import 'drive_screen.dart';
import 'stats_screen.dart';

/// Library: recently played, liked songs, playlists, offline downloads.
/// M3 Expressive restyle: display header, icon-tile destinations, and
/// track lists with the Shuffle-pill + sort-button header.
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
      body: Column(
        children: [
          const DisplayHeader(
            title: 'Library',
            subtitle: 'Your music, your way',
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: pc,
              builder: (_, __) => _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final liked = pc.likedSongs;
    final names = pc.playlists.keys.toList();
    final dls = pc.downloads;
    final recent = pc.recent;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text('Recently played',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 182,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recent.length,
              itemBuilder: (_, i) {
                final t = recent[i];
                return GestureDetector(
                  onTap: () => pc.playTracks(recent, i),
                  child: Container(
                    width: 118,
                    margin: const EdgeInsets.only(right: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            TrackArt(t, size: 118, radius: 24),
                            if (t.isDownloaded)
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  padding:
                                      const EdgeInsets.all(4),
                                  child: Icon(
                                      Icons.download_done,
                                      size: 14,
                                      color: scheme
                                          .onSecondaryContainer),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                        Text(t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(
                                    color:
                                        scheme.onSurfaceVariant,
                                    fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        _destinationTile(
          context,
          icon: Icons.favorite,
          tileColor: scheme.primaryContainer,
          iconColor: scheme.onPrimaryContainer,
          title: 'Liked Songs',
          subtitle: '${liked.length} tracks',
          onTap: liked.isEmpty
              ? null
              : () => _openTrackList(context, 'Liked Songs', liked,
                  allowRemove: (t) => pc.toggleLike(t)),
        ),
        _destinationTile(
          context,
          icon: Icons.download_done,
          tileColor: scheme.secondaryContainer,
          iconColor: scheme.onSecondaryContainer,
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
        _destinationTile(
          context,
          icon: Icons.cloud_outlined,
          tileColor: scheme.tertiaryContainer,
          iconColor: scheme.onTertiaryContainer,
          title: 'My Drive',
          subtitle: pc.driveTracks.isEmpty
              ? 'Your songs from Google Drive'
              : '${pc.driveTracks.length} tracks · Google Drive',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DriveScreen(pc: pc),
          )),
        ),
        _destinationTile(
          context,
          icon: Icons.smartphone_outlined,
          tileColor: scheme.primaryContainer,
          iconColor: scheme.onPrimaryContainer,
          title: 'On this phone',
          subtitle: pc.localTracks.isEmpty
              ? 'Import MP3s from your phone storage'
              : '${pc.localTracks.length} tracks · stored in the app',
          onTap: () => _importFromPhone(context),
        ),
        if (pc.localTracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 76, right: 16),
            child: TextButton.icon(
              icon:
                  const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('View imported tracks'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
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
        _destinationTile(
          context,
          icon: Icons.bar_chart_outlined,
          tileColor: scheme.secondaryContainer,
          iconColor: scheme.onSecondaryContainer,
          title: 'Your Stats',
          subtitle: 'Listening time, top tracks & artists',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StatsScreen(pc: pc),
          )),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Text('Playlists',
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                onPressed: () => showNewPlaylistDialog(
                    context, (name) => pc.createPlaylist(name)),
              ),
            ],
          ),
        ),
        ...names.map((n) {
          final tracks = pc.playlists[n]!;
          return _destinationTile(
            context,
            icon: Icons.queue_music,
            tileColor: scheme.surfaceContainerHighest,
            iconColor: scheme.onSurfaceVariant,
            title: n,
            subtitle: '${tracks.length} tracks',
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
      ],
    );
  }

  Widget _destinationTile(
    BuildContext context, {
    required IconData icon,
    required Color tileColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Card(
        child: InkWell(
          borderRadius:
              BorderRadius.circular(VaniTheme.radiiOf(context)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tileColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon,
                      color: iconColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(
                                  fontWeight:
                                      FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                  color: theme.colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ),
                ),
                trailing ??
                    (onTap != null
                        ? Icon(Icons.chevron_right,
                            color: theme
                                .colorScheme.onSurfaceVariant)
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openTrackList(BuildContext context, String title,
      List<Track> tracks,
      {required Future<void> Function(Track) allowRemove,
      String removeLabel = 'Remove',
      bool showOfflineBadge = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _TrackListScreen(
        pc: pc,
        title: title,
        tracks: tracks,
        allowRemove: allowRemove,
        removeLabel: removeLabel,
        showOfflineBadge: showOfflineBadge,
      ),
    ));
  }

  void _renamePlaylistDialog(BuildContext context, String oldName) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename playlist'),
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
          FilledButton(
            onPressed: () async {
              await pc.renamePlaylist(oldName, ctrl.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// A named track list with the expressive Shuffle-pill + sort header,
/// swipe-to-remove rows, and a Play-all pill.
class _TrackListScreen extends StatefulWidget {
  final PlayerController pc;
  final String title;
  final List<Track> tracks;
  final Future<void> Function(Track) allowRemove;
  final String removeLabel;
  final bool showOfflineBadge;

  const _TrackListScreen({
    required this.pc,
    required this.title,
    required this.tracks,
    required this.allowRemove,
    required this.removeLabel,
    required this.showOfflineBadge,
  });

  @override
  State<_TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<_TrackListScreen> {
  int _sort = 0; // 0 = as added, 1 = title A–Z, 2 = artist A–Z

  List<Track> get _sorted {
    final list = List<Track>.of(widget.tracks);
    if (_sort == 1) {
      list.sort((a, b) => a.title
          .toLowerCase()
          .compareTo(b.title.toLowerCase()));
    } else if (_sort == 2) {
      list.sort((a, b) => a.artist
          .toLowerCase()
          .compareTo(b.artist.toLowerCase()));
    }
    return list;
  }

  String get _sortName =>
      ['As added', 'Title A–Z', 'Artist A–Z'][_sort];

  @override
  Widget build(BuildContext context) {
    final tracks = _sorted;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AnimatedBuilder(
        animation: widget.pc,
        builder: (_, __) => Column(
          children: [
            SongListHeader(
              title: widget.title,
              count: tracks.length,
              onShuffle: () {
                final shuffled = List<Track>.of(tracks)
                  ..shuffle();
                widget.pc.playTracks(shuffled, 0);
              },
              onSort: () =>
                  setState(() => _sort = (_sort + 1) % 3),
              sortTooltip: 'Sort: $_sortName',
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play all'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: tracks.isEmpty
                    ? null
                    : () =>
                        widget.pc.playTracks(tracks, 0),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(vertical: 8),
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  return Dismissible(
                    key: ValueKey('${t.id}::${t.title}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer,
                      alignment: Alignment.centerRight,
                      padding:
                          const EdgeInsets.only(right: 24),
                      child: Text(widget.removeLabel,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                    ),
                    onDismissed: (_) =>
                        widget.allowRemove(t),
                    child: TrackTile(
                      track: t,
                      contextQueue: tracks,
                      indexInQueue: i,
                      pc: widget.pc,
                      showOfflineBadge:
                          widget.showOfflineBadge,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
