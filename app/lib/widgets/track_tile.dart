import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';

/// Shared artwork image with a music-note fallback.
class TrackArt extends StatelessWidget {
  final Track track;
  final double size;
  final double radius;
  const TrackArt(this.track,
      {super.key, this.size = 56, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    if (track.artworkUrl.isEmpty) return _fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          track.artworkUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.music_note, color: Colors.white54),
    );
  }
}

/// License badge shown on cards and in the player (CC-BY needs attribution).
class LicenseBadge extends StatelessWidget {
  final Track track;
  const LicenseBadge(this.track, {super.key});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (track.license == 'CC0') {
      bg = Colors.green[900]!;
    } else if (track.isDriveTrack) {
      bg = Colors.blue[900]!;
    } else {
      bg = Colors.amber[900]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        track.license,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// A tappable track row with an overflow menu (like / playlist / download).
class TrackTile extends StatelessWidget {
  final Track track;
  final List<Track> contextQueue;
  final int indexInQueue;
  final PlayerController pc;
  final VoidCallback? onTapOverride;
  final bool showOfflineBadge;

  /// When non-null, shows an edit (pencil) button in the trailing row —
  /// used by the My Drive screen to rename user-added tracks.
  final void Function(Track track)? onEdit;

  const TrackTile({
    super.key,
    required this.track,
    required this.contextQueue,
    required this.indexInQueue,
    required this.pc,
    this.onTapOverride,
    this.showOfflineBadge = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = pc.currentTrack == track;
    return ListTile(
      leading: TrackArt(track),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? const Color(0xFF1DB954) : null,
        ),
      ),
      subtitle: Text(
        '${track.artist} · ${track.license}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showOfflineBadge && track.isDownloaded)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.download_done,
                  size: 18, color: Colors.white54),
            ),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => onEdit!(track),
            ),
          _menu(context),
        ],
      ),
      onTap: onTapOverride ?? () => pc.playTracks(contextQueue, indexInQueue),
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) => _onMenu(context, v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'like',
          child: Text(pc.isLiked(track) ? 'Unlike' : 'Like'),
        ),
        const PopupMenuItem(
          value: 'playlist',
          child: Text('Add to playlist'),
        ),
        if (!track.isDownloaded)
          PopupMenuItem(
            value: 'download',
            enabled: !pc.isDownloading(track),
            child: Text(
                pc.isDownloading(track) ? 'Downloading…' : 'Download'),
          )
        else
          const PopupMenuItem(
            value: 'undownload',
            child: Text('Remove download'),
          ),
      ],
    );
  }

  Future<void> _onMenu(BuildContext context, String v) async {
    switch (v) {
      case 'like':
        await pc.toggleLike(track);
        break;
      case 'playlist':
        _showAddToPlaylist(context);
        break;
      case 'download':
        await pc.downloadTrack(track);
        if (context.mounted && pc.error != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(pc.error!)));
        }
        break;
      case 'undownload':
        await pc.deleteDownload(track);
        break;
    }
  }

  void _showAddToPlaylist(BuildContext context) {
    final names = pc.playlists.keys.toList();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () {
                Navigator.pop(context);
                _showNewPlaylistDialog(context);
              },
            ),
            ...names.map(
              (n) => ListTile(
                leading: const Icon(Icons.playlist_add),
                title: Text(n),
                onTap: () async {
                  await pc.addToPlaylist(n, track);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewPlaylistDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await pc.createPlaylist(ctrl.text);
              if (ctrl.text.trim().isNotEmpty) {
                await pc.addToPlaylist(ctrl.text.trim(), track);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
