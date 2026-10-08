import 'package:flutter/material.dart';
import '../services/player_controller.dart';
import '../services/stats_service.dart';

/// "Your Stats": listening time, top tracks/artists, per-source split.
/// Aggregated client-side from the device's Supabase listening events.
/// M3 Expressive restyle: large pill segmented control, tonal stat cards.
class StatsScreen extends StatefulWidget {
  final PlayerController pc;
  const StatsScreen({super.key, required this.pc});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _range = 2; // 0 = 7d, 1 = 30d, 2 = all time
  late Future<_Loaded> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Loaded> _load() async {
    final events = await widget.pc.stats.fetchEvents(limit: 2000);
    final now = DateTime.now();
    return _Loaded(
      week: StatsSummary.summarize(events,
          since: now.subtract(const Duration(days: 7))),
      month: StatsSummary.summarize(events,
          since: now.subtract(const Duration(days: 30))),
      all: StatsSummary.summarize(events),
    );
  }

  String _fmtDur(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your Stats')),
      body: FutureBuilder<_Loaded>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!widget.pc.stats.ready) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 56,
                        color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text(
                      'Stats backend is not connected.\nListening stats will appear here once the connection is up.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey, height: 1.5),
                    ),
                  ],
                ),
              ),
            );
          }
          final loaded = snap.data;
          if (loaded == null) {
            return const Center(
                child: Text('Could not load stats.',
                    style: TextStyle(color: Colors.grey)));
          }
          final s = [
            _loadedWeek(loaded),
            _loadedMonth(loaded),
            loaded.all
          ][_range];
          if (s.playCount == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_outlined,
                        size: 56,
                        color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text(
                      'No listening stats yet.\nPlay something for 30+ seconds and it will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey, height: 1.5),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Expressive large-pill segmented control.
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        label: Text('7 days'),
                        icon: Icon(Icons.calendar_view_week_outlined,
                            size: 16)),
                    ButtonSegment(
                        value: 1,
                        label: Text('30 days'),
                        icon: Icon(Icons.calendar_month_outlined,
                            size: 16)),
                    ButtonSegment(
                        value: 2,
                        label: Text('All time'),
                        icon:
                            Icon(Icons.all_inclusive, size: 16)),
                  ],
                  selected: {_range},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => _range = v.first),
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _statCard(
                            context,
                            'Listening time',
                            _fmtDur(s.totalSeconds),
                            Icons.timer_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _statCard(context, 'Plays',
                            '${s.playCount}', Icons.play_arrow)),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Top tracks',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(
                            fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...s.topTracks.asMap().entries.map((e) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              scheme.primaryContainer,
                          child: Text('${e.key + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: scheme
                                      .onPrimaryContainer)),
                        ),
                        title: Text(e.value.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(e.value.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Text(_fmtDur(e.value.seconds),
                              style: TextStyle(
                                  color: scheme
                                      .onSecondaryContainer,
                                  fontWeight:
                                      FontWeight.w600,
                                  fontSize: 12)),
                        ),
                      ),
                    )),
                const SizedBox(height: 12),
                Text('Top artists',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(
                            fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...s.topArtists.asMap().entries.map((e) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              scheme.tertiaryContainer,
                          child: Text('${e.key + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: scheme
                                      .onTertiaryContainer)),
                        ),
                        title: Text(e.value.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        trailing: Text(_fmtDur(e.value.seconds),
                            style: TextStyle(
                                color: scheme.onSurfaceVariant)),
                      ),
                    )),
                const SizedBox(height: 12),
                Text('By source',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(
                            fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: s.playsBySource.entries
                      .map((e) => Chip(
                            avatar: Icon(
                                _sourceIcon(e.key),
                                size: 16),
                            label: Text(
                                '${_sourceLabel(e.key)} · ${e.value}',
                                style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w600)),
                          ))
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  StatsSummary _loadedWeek(_Loaded l) => l.week;
  StatsSummary _loadedMonth(_Loaded l) => l.month;

  String _sourceLabel(String s) => switch (s) {
        'archive' => 'Archive',
        'drive' => 'Drive',
        'local' => 'Phone',
        _ => s,
      };

  IconData _sourceIcon(String s) => switch (s) {
        'archive' => Icons.public_outlined,
        'drive' => Icons.cloud_outlined,
        'local' => Icons.smartphone_outlined,
        _ => Icons.music_note,
      };

  Widget _statCard(
      BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(icon,
                  color: scheme.onPrimaryContainer,
                  size: 22),
            ),
            const SizedBox(height: 12),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Loaded {
  final StatsSummary week;
  final StatsSummary month;
  final StatsSummary all;
  _Loaded({required this.week, required this.month, required this.all});
}
