import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/archive_api.dart';
import '../services/player_controller.dart';
import '../widgets/expressive.dart';
import '../widgets/track_art.dart';
import '../widgets/track_tile.dart';
import 'drive_screen.dart';
import 'settings_screen.dart';

/// Home: genre chips + horizontal shelves of open-licensed tracks.
/// When "Internet Archive collections" is off in Settings, Home shows
/// the user's own music (Drive + phone imports) instead.
///
/// M3 Expressive restyle: display-scale header with tonal circular
/// utility buttons, large pill genre chips, squircle artwork cards.
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
      body: Column(
        children: [
          DisplayHeader(
            title: 'Your Mix',
            subtitle:
                'Open-licensed picks for today · CC0 / CC-BY',
            actions: [
              TonalIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SettingsScreen(pc: widget.pc),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: widget.pc.settings.iaEnabled
                ? _archiveBody()
                : _ownMusicBody(),
          ),
        ],
      ),
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
                  Icon(Icons.library_music_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text(
                    'Internet Archive collections are off.\nAdd your own music to get started.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('Open My Drive'),
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
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
          children: [
            SongListHeader(
              title: 'Your music',
              count: mine.length,
              onShuffle: () {
                final shuffled = List<Track>.of(mine)..shuffle();
                pc.playTracks(shuffled, 0);
              },
            ),
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
                const SizedBox(height: 12),
                FilledButton(
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'All music is Creative Commons (CC0 / CC-BY) from the Internet Archive. '
                  'CC-BY tracks credit their artists in the player.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// Large expressive pill chips (PixelPlayer Library pattern).
  Widget _genreChips() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: ArchiveApi.genres.keys.map((g) {
          final selected = g == _genre;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(g.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              selected: selected,
              selectedColor: scheme.primaryContainer,
              labelStyle: TextStyle(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant),
              shape: const StadiumBorder(),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              onSelected: (_) => setState(() => _genre = g),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Big horizontal cards for the selected genre, with squircle art.
  Widget _featuredShelf(Map<String, List<Track>> data) {
    final tracks = data[_genre] ?? [];
    final theme = Theme.of(context);
    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No tracks found for this genre yet.',
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return SizedBox(
      height: 218,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        itemBuilder: (_, i) {
          final t = tracks[i];
          return GestureDetector(
            onTap: () => widget.pc.playTracks(tracks, i),
            child: Container(
              width: 148,
              margin: const EdgeInsets.only(right: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      TrackArt(t, size: 148, radius: 28),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: LicenseBadge(t),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600)),
                  Text(t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(genre,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 184,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return GestureDetector(
                onTap: () => widget.pc.playTracks(tracks, i),
                child: Container(
                  width: 118,
                  margin: const EdgeInsets.only(right: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrackArt(t, size: 118, radius: 24),
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
                                  color: theme.colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 11)),
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
