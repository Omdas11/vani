import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One timestamped lyric line parsed from LRC.
class LyricLine {
  final Duration time;
  final String text;
  LyricLine(this.time, this.text);
}

/// Result of a lyrics lookup.
class LyricsResult {
  /// False when nothing was found (or the lookup failed).
  final bool found;

  /// True when the track is instrumental (no lyrics exist).
  final bool instrumental;

  /// Synced lines, empty when only plain lyrics (or nothing) exist.
  final List<LyricLine> synced;

  /// Plain unsynced lyrics text, may be empty.
  final String plain;

  const LyricsResult({
    required this.found,
    this.instrumental = false,
    this.synced = const [],
    this.plain = '',
  });

  static const notFound = LyricsResult(found: false);
}

/// Free keyless lyrics lookup: lrclib.net first, then KuGou as a fallback
/// (the same two sources the open-source Namida player uses, in the same
/// order). Plus LRC parsing and a local cache. Lookups are explicit
/// (one per user tap, or one auto-load per track) — no prefetching.
class LyricsApi {
  static const _base = 'https://lrclib.net/api/get';

  /// Builds the lookup URL, omitting empty params.
  /// Public for testing.
  static String buildUrl({
    String? artist,
    String? title,
    int? durationSeconds,
  }) {
    final params = <String, String>{};
    final a = artist?.trim() ?? '';
    final t = title?.trim() ?? '';
    if (a.isNotEmpty && a != 'Unknown artist') params['artist_name'] = a;
    if (t.isNotEmpty && t != 'Unknown title') params['track_name'] = t;
    if (durationSeconds != null && durationSeconds > 0) {
      params['duration'] = durationSeconds.toString();
    }
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return qs.isEmpty ? _base : '$_base?$qs';
  }

  /// Parses an LRC document into timestamped lines.
  /// - Supports [mm:ss.xx] / [mm:ss:xx] / [mm:ss] and multiple
  ///   timestamps on one line.
  /// - Skips metadata tags ([ti:], [ar:], [al:], [by:], [offset:], ...).
  /// - Skips empty lyric text. Output is sorted by time.
  /// Public for testing.
  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    final tagRe =
        RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final metaRe = RegExp(r'^\[(ti|ar|al|by|offset|length):', caseSensitive: false);
    for (final rawLine in lrc.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || metaRe.hasMatch(line)) continue;
      final matches = tagRe.allMatches(line).toList();
      if (matches.isEmpty) continue;
      var text = line;
      for (final m in matches) {
        text = text.replaceFirst(m.group(0)!, '');
      }
      text = text.trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final fracStr = m.group(3);
        var ms = 0;
        if (fracStr != null) {
          // 1-2 digits = centiseconds, 3 digits = milliseconds.
          ms = fracStr.length <= 2
              ? int.parse(fracStr.padRight(2, '0')) * 10
              : int.parse(fracStr.substring(0, 3));
        }
        out.add(LyricLine(
          Duration(minutes: min, seconds: sec, milliseconds: ms),
          text,
        ));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// Interprets an lrclib HTTP response. Not-found is reported inside a
  /// 200 body ({"statusCode":404,"name":"TrackNotFound",...}); anything
  /// else non-200 is also treated as not found.
  /// Public for testing.
  static LyricsResult parseResponse(int statusCode, String body) {
    if (statusCode != 200) return LyricsResult.notFound;
    Map<String, dynamic> json;
    try {
      final d = jsonDecode(body);
      if (d is! Map<String, dynamic>) return LyricsResult.notFound;
      json = d;
    } catch (_) {
      return LyricsResult.notFound;
    }
    if (json['statusCode'] == 404 || json['name'] == 'TrackNotFound') {
      return LyricsResult.notFound;
    }
    final syncedRaw = (json['syncedLyrics'] as String?) ?? '';
    final plain = (json['plainLyrics'] as String?) ?? '';
    final synced = parseLrc(syncedRaw);
    if (synced.isEmpty && plain.trim().isEmpty) {
      return LyricsResult.notFound;
    }
    return LyricsResult(
      found: true,
      instrumental: json['instrumental'] == true,
      synced: synced,
      plain: plain.trim(),
    );
  }

  /// One explicit lookup: lrclib first, KuGou fallback.
  /// Returns [LyricsResult.notFound] on any failure.
  Future<LyricsResult> fetch({
    String? artist,
    String? title,
    int? durationSeconds,
  }) async {
    final r = await _fetchLrclib(
        artist: artist, title: title, durationSeconds: durationSeconds);
    if (r.found) return r;
    return _fetchKugou(
        artist: artist, title: title, durationSeconds: durationSeconds);
  }

  Future<LyricsResult> _fetchLrclib({
    String? artist,
    String? title,
    int? durationSeconds,
  }) async {
    final url = buildUrl(
        artist: artist, title: title, durationSeconds: durationSeconds);
    if (url == _base) return LyricsResult.notFound; // nothing to query
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'Vani/1.4'})
          .timeout(const Duration(seconds: 15));
      return parseResponse(res.statusCode, res.body);
    } catch (_) {
      return LyricsResult.notFound;
    }
  }

  // ---------- KuGou fallback (no key, public JSON endpoints) ----------

  /// Noise tokens stripped before fuzzy-matching titles, mirroring
  /// Namida's approach.
  static const _noiseTokens = {
    'official',
    'video',
    'audio',
    'lyrics',
    'lyric',
    'music',
    'hd',
    'hq',
    '4k',
    'visualizer',
    'mv',
    'lyrical',
  };

  /// Public for testing: normalizes a string for fuzzy comparison.
  static String normalizeForMatch(String s) {
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final tokens =
        t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return tokens.where((w) => !_noiseTokens.contains(w)).join(' ');
  }

  /// Public for testing: scores a KuGou candidate 0..1.
  /// 0.7 * title token overlap + 0.3 * artist token overlap, minus a
  /// duration-mismatch penalty. Mirrors Namida's 0.7 accept threshold.
  static double scoreKugouCandidate({
    required String candTitle,
    required String candArtist,
    required int candDurationMs,
    required String wantTitle,
    required String wantArtist,
    int? wantDurationSeconds,
  }) {
    double overlap(String a, String b) {
      final ta = normalizeForMatch(a).split(' ').where((w) => w.isNotEmpty).toSet();
      final tb = normalizeForMatch(b).split(' ').where((w) => w.isNotEmpty).toSet();
      if (ta.isEmpty || tb.isEmpty) return 0;
      return ta.intersection(tb).length / ta.union(tb).length;
    }

    var score =
        0.7 * overlap(candTitle, wantTitle) + 0.3 * overlap(candArtist, wantArtist);
    if (wantDurationSeconds != null && wantDurationSeconds > 0) {
      final wantMs = wantDurationSeconds * 1000;
      final rel = (candDurationMs - wantMs).abs() / wantMs;
      score -= rel.clamp(0.0, 1.0) * 0.4;
    }
    return score.clamp(0.0, 1.0);
  }

  /// Public for testing: builds the KuGou search URL.
  static String kugouSearchUrl({
    String? artist,
    String? title,
    int? durationSeconds,
  }) {
    final a = (artist ?? '').trim();
    final t = (title ?? '').trim();
    final keyword = a.isNotEmpty ? '$a - $t' : t;
    final durMs = durationSeconds != null && durationSeconds > 0
        ? (durationSeconds * 1000).toString()
        : '';
    return 'https://lyrics.kugou.com/search?ver=1&man=yes&client=pc'
        '&keyword=${Uri.encodeComponent(keyword)}'
        '&duration=$durMs&hash=';
  }

  /// Public for testing: picks the best candidate from a KuGou search
  /// response, or null when nothing scores above the accept threshold.
  /// Returns {'id','accesskey'} of the winner.
  static Map<String, String>? pickKugouCandidate(
    Map<String, dynamic> json, {
    required String wantTitle,
    required String wantArtist,
    int? wantDurationSeconds,
  }) {
    final cands = json['candidates'];
    if (cands is! List) return null;
    var bestScore = 0.7; // Namida's accept threshold
    Map<String, String>? best;
    final seen = <String>{};
    for (final c in cands.whereType<Map<String, dynamic>>()) {
      final id = '${c['id']}';
      final accesskey = '${c['accesskey']}';
      if (id.isEmpty || accesskey.isEmpty) continue;
      final dedupe =
          '${c['song']}|${c['singer']}|${c['duration']}';
      if (!seen.add(dedupe)) continue; // KuGou repeats ids
      final score = scoreKugouCandidate(
        candTitle: '${c['song']}',
        candArtist: '${c['singer']}',
        candDurationMs: (c['duration'] as num?)?.toInt() ?? 0,
        wantTitle: wantTitle,
        wantArtist: wantArtist,
        wantDurationSeconds: wantDurationSeconds,
      );
      if (score > bestScore) {
        bestScore = score;
        best = {'id': id, 'accesskey': accesskey};
      }
    }
    return best;
  }

  /// Public for testing: decodes a KuGou download response
  /// ({"content": "<base64 LRC>"}) into an LRC string, or null.
  static String? decodeKugouContent(Map<String, dynamic> json) {
    final b64 = json['content'];
    if (b64 is! String || b64.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  Future<LyricsResult> _fetchKugou({
    String? artist,
    String? title,
    int? durationSeconds,
  }) async {
    final t = (title ?? '').trim();
    if (t.isEmpty || t == 'Unknown title') return LyricsResult.notFound;
    try {
      final searchRes = await http
          .get(
            Uri.parse(kugouSearchUrl(
                artist: artist,
                title: title,
                durationSeconds: durationSeconds)),
            headers: {'User-Agent': 'Vani/1.4'},
          )
          .timeout(const Duration(seconds: 15));
      if (searchRes.statusCode != 200) return LyricsResult.notFound;
      final searchJson = jsonDecode(searchRes.body);
      if (searchJson is! Map<String, dynamic>) {
        return LyricsResult.notFound;
      }
      final pick = pickKugouCandidate(
        searchJson,
        wantTitle: t,
        wantArtist: (artist ?? '').trim(),
        wantDurationSeconds: durationSeconds,
      );
      if (pick == null) return LyricsResult.notFound;
      final dlRes = await http
          .get(
            Uri.parse('https://lyrics.kugou.com/download?ver=1&client=pc'
                '&id=${Uri.encodeComponent(pick['id']!)}'
                '&accesskey=${Uri.encodeComponent(pick['accesskey']!)}'
                '&fmt=lrc&charset=utf8'),
            headers: {'User-Agent': 'Vani/1.4'},
          )
          .timeout(const Duration(seconds: 15));
      if (dlRes.statusCode != 200) return LyricsResult.notFound;
      final dlJson = jsonDecode(dlRes.body);
      if (dlJson is! Map<String, dynamic>) return LyricsResult.notFound;
      final lrc = decodeKugouContent(dlJson);
      if (lrc == null) return LyricsResult.notFound;
      final synced = parseLrc(lrc);
      if (synced.isEmpty) return LyricsResult.notFound;
      return LyricsResult(
        found: true,
        synced: synced,
        plain: synced.map((l) => l.text).join('\n'),
      );
    } catch (_) {
      return LyricsResult.notFound;
    }
  }
}

/// Persists fetched lyrics per track so repeat views don't re-hit the API.
/// Keyed by a caller-supplied track identity string.
class LyricsCache {
  static const _prefsKey = 'lyrics_cache';
  final Map<String, LyricsResult> _mem = {};

  String keyFor(String trackIdentity) =>
      'lyr::${trackIdentity.toLowerCase().trim()}';

  Future<LyricsResult?> get(String trackIdentity) async {
    final k = keyFor(trackIdentity);
    if (_mem.containsKey(k)) return _mem[k];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[k];
      if (entry is! Map<String, dynamic>) return null;
      final r = LyricsResult(
        found: true,
        instrumental: entry['instrumental'] == true,
        synced: LyricsApi.parseLrc(entry['synced'] as String? ?? ''),
        plain: entry['plain'] as String? ?? '',
      );
      _mem[k] = r;
      return r;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String trackIdentity, LyricsResult result) async {
    if (!result.found) return;
    final k = keyFor(trackIdentity);
    // Re-serialize synced lines to canonical LRC for compact storage.
    final lrc = result.synced
        .map((l) =>
            '[${_fmtTs(l.time)}] ${l.text}')
        .join('\n');
    _mem[k] = result;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      final map = (raw == null || raw.isEmpty)
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(raw) as Map<String, dynamic>);
      // Bound the cache so it can't grow without limit.
      if (map.length > 200) {
        final keys = map.keys.toList();
        for (var i = 0; i < keys.length - 200; i++) {
          map.remove(keys[i]);
        }
      }
      map[k] = {
        'synced': lrc,
        'plain': result.plain,
        'instrumental': result.instrumental,
      };
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  static String _fmtTs(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$m:$s.$cs';
  }
}
