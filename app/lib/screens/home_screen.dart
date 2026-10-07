import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/track.dart';
import '../services/archive_api.dart';
import '../services/player_controller.dart';
import '../widgets/track_tile.dart';
import 'drive_screen.dart';
import 'settings_screen.dart';

/// Home: genre chips + horizontal shelves of open-licensed tracks.
/// When "Internet Archive collections" is off in Settings, Home shows
/// the user's own music (Drive + phone imports) instead.
class HomeScreen extends StatefulWidget {
  final PlayerController pc;
  const HomeScreen({super.key, required this.pc});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _genre = 'Trending';
  late Future<Map<String, List<Track>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    widget.pc.settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    widget.pc.settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() => setState(() {});

  Future<Map<String, List<Track>>> _loadAll() async {
    if (!widget.pc.settings.iaEnabled) return {};
    final out = <String, List<Track>>{};
    for (final g in ArchiveApi.genres.keys) {
      try {
        out[g] = await widget.pc.api.browse(g, rows: 20);
      } catch (_) {
        out[g] = [];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vani',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            )),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(pc: widget.pc),
            )),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: LicenseBadge(Track(
              id: '',
              title: '',
              artist: '',
              license: 'CC0',
              licenseUrl: '',
              artworkUrl: '',
            )),
          ),
        ],
      ),
      body: widget.pc.settings.iaEnabled ? _archiveBody() : _ownMusicBody(),
    );
  }

  /// Shown when the IA toggle is off: the user's own music only.
  Widget _ownMusicBody() {
    final pc = widget.pc;
    final mine = [...pc.driveTracks, ...pc.localTracks];
    return AnimatedBuilder(
      animation: pc,
      builder: (_, __) {
        if (mine.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_music_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Internet Archive collections are off.\nAdd your own music to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('Open My Drive'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => DriveScreen(pc: pc)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Text('Your music',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${mine.length} tracks · Drive + this phone',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 8),
            ...mine.asMap().entries.map((e) => TrackTile(
                  track: e.value,
                  contextQueue: mine,
                  indexInQueue: e.key,
                  pc: pc,
                )),
          ],
        );
      },
    );
  }

  Widget _archiveBody() {
    return FutureBuilder<Map<String, List<Track>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not reach the Internet Archive.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _future = _loadAll()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = _loadAll()),
            child: ListView(
              children: [
                _genreChips(),
                const SizedBox(height: 4),
                _featuredShelf(data),
                for (final g in ArchiveApi.genres.keys)
                  if (g != 'Trending') _shelf(g, data[g] ?? []),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'All music is Creative Commons (CC0 / CC-BY) from the Internet Archive. '
                    'CC-BY tracks credit their artists in the player.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      );
  }

  Widget _genreChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: ArchiveApi.genres.keys.map((g) {
          final selected = g == _genre;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(g),
              selected: selected,
              selectedColor: const Color(0xFF1DB954),
              onSelected: (_) => setState(() => _genre = g),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Big horizontal cards for the selected genre.
  Widget _featuredShelf(Map<String, List<Track>> data) {
    final tracks = data[_genre] ?? [];
    if (tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No tracks found for this genre yet.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tracks.length,
        itemBuilder: (_, i) {
          final t = tracks[i];
          return GestureDetector(
            onTap: () => widget.pc.playTracks(tracks, i),
            child: Container(
              width: 140,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      TrackArt(t, size: 140, radius: 8),
                      Positioned(
                        left: 6,
                        top: 6,
                        child: LicenseBadge(t),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  Text(t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shelf(String genre, List<Track> tracks) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(genre,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 176,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return GestureDetector(
                onTap: () => widget.pc.playTracks(tracks, i),
                child: Container(
                  width: 112,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrackArt(t, size: 112, radius: 8),
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
    );
  }
}
