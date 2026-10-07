import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Listening-stats backend on Supabase (project "opentune").
///
/// Uses Supabase Auth *anonymous* sign-in: one throwaway user per install,
/// no login UI. The anon key below is the publishable key (standard to
/// embed); row-level security on `listening_events` restricts every
/// device to its own rows (`device_id = auth.uid()`).
///
/// All network failures are swallowed — stats must never break playback.
class StatsService {
  static const _base = 'https://uwmzlamkhivopjewipbm.supabase.co';
  static const _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3bXpsYW1raGl2b3BqZXdpcGJtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzODMzMjcsImV4cCI6MjEwNjk1OTMyN30.57z7owfui3Q_caYaHhPcjprYvX1zubOdq5F3iAQhYgU';

  static const _kUserId = 'stats_user_id';
  static const _kAccessToken = 'stats_access_token';
  static const _kRefreshToken = 'stats_refresh_token';
  static const _kExpiresAt = 'stats_expires_at_ms';

  String? _userId;
  String? _accessToken;
  bool _ready = false;

  bool get ready => _ready;
  String? get deviceId => _userId;

  Map<String, String> _headers({bool authed = false}) => {
        'apikey': _anonKey,
        'Content-Type': 'application/json',
        if (authed && _accessToken != null)
          'Authorization': 'Bearer $_accessToken',
      };

  /// Restore a saved anonymous session, or sign in fresh.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final exp = prefs.getInt(_kExpiresAt) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (exp - now > 60000) {
        _userId = prefs.getString(_kUserId);
        _accessToken = prefs.getString(_kAccessToken);
        if (_userId != null && _accessToken != null) {
          _ready = true;
          return;
        }
      }
      await _signUpFresh(prefs);
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> _signUpFresh(SharedPreferences prefs) async {
    final res = await http
        .post(Uri.parse('$_base/auth/v1/signup'),
            headers: _headers(), body: '{}')
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>?;
    final token = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    if (user == null || token == null) return;
    _userId = user['id'] as String?;
    _accessToken = token;
    if (_userId == null) return;
    await prefs.setString(_kUserId, _userId!);
    await prefs.setString(_kAccessToken, token);
    if (refresh != null) await prefs.setString(_kRefreshToken, refresh);
    await prefs.setInt(_kExpiresAt,
        DateTime.now().millisecondsSinceEpoch + expiresIn * 1000);
    _ready = true;
  }

  /// Record one listening event. Fire-and-forget safe.
  Future<void> logEvent({
    required String trackTitle,
    required String trackArtist,
    required String source, // 'archive' | 'drive' | 'local'
    required int durationListenedS,
    required bool completed,
  }) async {
    if (!_ready || _userId == null) return;
    try {
      final res = await http
          .post(Uri.parse('$_base/rest/v1/listening_events'),
              headers: _headers(authed: true),
              body: jsonEncode({
                'device_id': _userId,
                'track_title': trackTitle,
                'track_artist': trackArtist,
                'source': source,
                'duration_listened_s': durationListenedS,
                'completed': completed,
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) {
        // Token died (e.g. project rotated keys): sign in fresh once.
        _ready = false;
        final prefs = await SharedPreferences.getInstance();
        await _signUpFresh(prefs);
      }
    } catch (_) {}
  }

  /// Fetch this device's events (newest first). Returns [] on any failure.
  Future<List<ListeningEvent>> fetchEvents({int limit = 1000}) async {
    if (!_ready) return [];
    try {
      final uri = Uri.parse(
          '$_base/rest/v1/listening_events?select=track_title,track_artist,source,played_at,duration_listened_s,completed&order=played_at.desc&limit=$limit');
      final res = await http
          .get(uri, headers: _headers(authed: true))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ListeningEvent.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// One row from `listening_events`.
class ListeningEvent {
  final String trackTitle;
  final String trackArtist;
  final String source;
  final DateTime playedAt;
  final int durationListenedS;
  final bool completed;

  ListeningEvent({
    required this.trackTitle,
    required this.trackArtist,
    required this.source,
    required this.playedAt,
    required this.durationListenedS,
    required this.completed,
  });

  factory ListeningEvent.fromJson(Map<String, dynamic> j) => ListeningEvent(
        trackTitle: j['track_title'] as String? ?? 'Unknown title',
        trackArtist: j['track_artist'] as String? ?? 'Unknown artist',
        source: j['source'] as String? ?? 'archive',
        playedAt: DateTime.tryParse(j['played_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        durationListenedS:
            (j['duration_listened_s'] as num?)?.toInt() ?? 0,
        completed: j['completed'] == true,
      );
}

/// Aggregated stats, computed client-side (pure — unit-testable).
class StatsSummary {
  final int totalSeconds;
  final int playCount;
  final List<RankedTrack> topTracks;
  final List<RankedArtist> topArtists;
  final Map<String, int> playsBySource;

  StatsSummary({
    required this.totalSeconds,
    required this.playCount,
    required this.topTracks,
    required this.topArtists,
    required this.playsBySource,
  });

  /// Aggregate [events], optionally restricted to plays on/after [since].
  static StatsSummary summarize(List<ListeningEvent> events,
      {DateTime? since}) {
    final sel = since == null
        ? events
        : events.where((e) => !e.playedAt.isBefore(since)).toList();
    var total = 0;
    final trackSecs = <String, int>{};
    final trackPlays = <String, int>{};
    final trackMeta = <String, List<String>>{};
    final artistSecs = <String, int>{};
    final bySource = <String, int>{};
    for (final e in sel) {
      total += e.durationListenedS;
      final tk = '${e.trackTitle}::${e.trackArtist}';
      trackSecs[tk] = (trackSecs[tk] ?? 0) + e.durationListenedS;
      trackPlays[tk] = (trackPlays[tk] ?? 0) + 1;
      trackMeta[tk] = [e.trackTitle, e.trackArtist];
      artistSecs[e.trackArtist] =
          (artistSecs[e.trackArtist] ?? 0) + e.durationListenedS;
      bySource[e.source] = (bySource[e.source] ?? 0) + 1;
    }
    List<RankedTrack> topT = trackSecs.entries
        .map((e) => RankedTrack(
            title: trackMeta[e.key]![0],
            artist: trackMeta[e.key]![1],
            seconds: e.value,
            plays: trackPlays[e.key]!))
        .toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    List<RankedArtist> topA = artistSecs.entries
        .map((e) => RankedArtist(artist: e.key, seconds: e.value))
        .toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    if (topT.length > 10) topT = topT.sublist(0, 10);
    if (topA.length > 10) topA = topA.sublist(0, 10);
    return StatsSummary(
      totalSeconds: total,
      playCount: sel.length,
      topTracks: topT,
      topArtists: topA,
      playsBySource: bySource,
    );
  }
}

class RankedTrack {
  final String title;
  final String artist;
  final int seconds;
  final int plays;
  RankedTrack(
      {required this.title,
      required this.artist,
      required this.seconds,
      required this.plays});
}

class RankedArtist {
  final String artist;
  final int seconds;
  RankedArtist({required this.artist, required this.seconds});
}
