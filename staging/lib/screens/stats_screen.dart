import 'package:flutter/material.dart';
import '../services/player_controller.dart';
import '../services/stats_service.dart';

/// "Your Stats": listening time, top tracks/artists, per-source split.
/// Aggregated client-side from the device's Supabase listening events.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Your Stats')),
      body: FutureBuilder<_Loaded>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!widget.pc.stats.ready) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Stats backend is not connected.\nListening stats will appear here once the connection is up.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
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
          final s = [_loadedWeek(loaded), _loadedMonth(loaded), loaded.all][_range];
          if (s.playCount == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No listening stats yet.\nPlay something for 30+ seconds and it will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
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
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('7 days')),
                    ButtonSegment(value: 1, label: Text('30 days')),
                    ButtonSegment(value: 2, label: Text('All time')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (v) =>
                      setState(() => _range = v.first),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _statCard('Listening time',
                            _fmtDur(s.totalSeconds), Icons.timer)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _statCard('Plays',
                            '${s.playCount}', Icons.play_arrow)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Top tracks',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...s.topTracks.asMap().entries.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[850],
                        child: Text('${e.key + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(e.value.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(e.value.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Text(_fmtDur(e.value.seconds),
                          style: TextStyle(color: Colors.grey[400])),
                    )),
                const SizedBox(height: 12),
                const Text('Top artists',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...s.topArtists.asMap().entries.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[850],
                        child: Text('${e.key + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(e.value.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Text(_fmtDur(e.value.seconds),
                          style: TextStyle(color: Colors.grey[400])),
                    )),
                const SizedBox(height: 12),
                const Text('By source',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: s.playsBySource.entries
                      .map((e) => Chip(
                            label: Text(
                                '${_sourceLabel(e.key)}: ${e.value}'),
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

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF1DB954)),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: Colors.grey[400])),
        ],
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
