import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

/// Internet Archive advancedsearch + metadata API.
/// Only CC0 / CC-BY 4.0 / CC-BY 3.0 items are ever surfaced, and a
/// hardcoded blocklist filters out mislabeled commercial uploads
/// (bogus "CC0" claims on mainstream albums do exist on the Archive).
class ArchiveApi {
  static const _licenseFilter =
      'licenseurl:("https://creativecommons.org/publicdomain/zero/1.0/"'
      ' OR "https://creativecommons.org/licenses/by/4.0/"'
      ' OR "https://creativecommons.org/licenses/by/3.0/")';

  static const Map<String, String> genres = {
    'Trending': '',
    'Electronic': 'electronic',
    'Ambient': 'ambient',
    'Rock': 'rock',
    'Jazz': 'jazz',
    'Classical': 'classical',
    'Hip-Hop': 'hip-hop',
    'Folk': 'folk',
  };

  /// Substrings matched (case-insensitive) against identifier + title.
  /// These are known-mislabeled commercial uploads, not open music.
  static const List<String> _blocklist = [
    'childish gambino',
    'fantasia 2000',
    'deluxe soundtrack',
    'official soundtrack',
    'motion picture soundtrack',
    'taylor swift',
    'billie eilish',
    'kendrick lamar',
    'the beatles',
    'pink floyd',
    'michael jackson',
    'star wars',
    'harry potter',
    'avengers',
    'frozen 2',
    'hamilton musical',
    'spider-man',
    'jurassic park',
  ];

  final Map<String, String> _streamCache = {};
  final Map<String, List<Track>> _browseCache = {};

  /// Public for testing: true when an item matches the blocklist.
  bool isBlocked(String id, String title) {
    // Normalize separators so 'fantasia-2000' matches 'fantasia 2000'.
    final hay = '$id $title'
        .toLowerCase()
        .replaceAll(RegExp(r'[-_]+'), ' ');
    return _blocklist.any(hay.contains);
  }

  String _licenseLabel(String url) {
    if (url.contains('publicdomain/zero/1.0')) return 'CC0';
    if (url.contains('licenses/by/4.0')) return 'CC BY 4.0';
    if (url.contains('licenses/by/3.0')) return 'CC BY 3.0';
    return 'CC';
  }

  /// Public for testing: converts one advancedsearch doc into a [Track].
  Track? docToTrack(Map<String, dynamic> d) {
    final id = d['identifier'] as String?;
    if (id == null || id.isEmpty) return null;
    final licenseUrl = (d['licenseurl'] as String?) ?? '';
    final title = (d['title'] as String?)?.trim();
    final creator = (d['creator'] as String?)?.trim();
    final safeTitle =
        (title == null || title.isEmpty) ? id : title;
    if (isBlocked(id, safeTitle)) return null;
    return Track(
      id: id,
      title: safeTitle,
      artist:
          (creator == null || creator.isEmpty) ? 'Unknown artist' : creator,
      license: _licenseLabel(licenseUrl),
      licenseUrl: licenseUrl,
      artworkUrl: 'https://archive.org/services/img/$id',
    );
  }

  Future<List<Track>> _query(String q, {int rows = 20}) async {
    final uri = Uri.parse(
      'https://archive.org/advancedsearch.php'
      '?q=${Uri.encodeComponent(q)}'
      '&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=licenseurl'
      '&rows=$rows&page=1&output=json',
    );
    try {
      final res =
          await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final docs = (body['response']?['docs'] as List?) ?? [];
      return docs
          .whereType<Map<String, dynamic>>()
          .map(docToTrack)
          .whereType<Track>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Browse one genre shelf. Results are cached per genre for the session.
  Future<List<Track>> browse(String genre, {int rows = 20}) async {
    if (_browseCache.containsKey(genre)) return _browseCache[genre]!;
    final subject = genres[genre] ?? '';
    final q = subject.isEmpty
        ? 'mediatype:audio AND $_licenseFilter'
        : 'mediatype:audio AND $_licenseFilter AND subject:$subject';
    final tracks = await _query(q, rows: rows);
    _browseCache[genre] = tracks;
    return tracks;
  }

  /// Free-text search across CC0/CC-BY audio (title or creator match).
  Future<List<Track>> search(String text, {int rows = 25}) async {
    final t = _escape(text);
    final q =
        'mediatype:audio AND $_licenseFilter AND (title:($t) OR creator:($t))';
    return _query(q, rows: rows);
  }

  String _escape(String s) =>
      s.replaceAll('"', '').replaceAll('(', '').replaceAll(')', '');

  /// Fetch item metadata with retries — archive.org/metadata can
  /// transiently return empty JSON or fail outright.
  Future<Map<String, dynamic>?> _fetchMetadata(String id) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await http
            .get(Uri.parse('https://archive.org/metadata/$id'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode == 200 && res.body.length > 100) {
          final meta = jsonDecode(res.body);
          if (meta is Map<String, dynamic> &&
              (meta['files'] as List?)?.isNotEmpty == true) {
            return meta;
          }
        }
      } catch (_) {
        // retry
      }
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
    return null;
  }

  /// Public for testing: picks the best playable file from a metadata
  /// `files` list. Tiered: original lossy → Archive-generated derivative
  /// lossy (much smaller than original lossless) → lossless.
  static Map<String, dynamic>? pickPlayableFile(List<dynamic> files) {
    const tiers = [
      ['original', '.mp3'],
      ['original', '.ogg'],
      ['original', '.oga'],
      ['derivative', '.mp3'],
      ['derivative', '.ogg'],
      ['derivative', '.oga'],
      ['original', '.m4a'],
      ['original', '.aac'],
      ['derivative', '.m4a'],
      ['derivative', '.aac'],
      ['original', '.wav'],
      ['original', '.flac'],
      ['derivative', '.wav'],
      ['derivative', '.flac'],
    ];
    for (final tier in tiers) {
      for (final f in files.whereType<Map<String, dynamic>>()) {
        final name = (f['name'] as String?) ?? '';
        final source = (f['source'] as String?) ?? 'original';
        if (source != tier[0]) continue;
        if (name.toLowerCase().endsWith(tier[1])) return f;
      }
    }
    return null;
  }

  /// Public for testing: builds the /download/ URL for an in-item path.
  /// The metadata `name` already holds the full in-item path, so `dir`
  /// must NOT be prepended.
  static String downloadUrl(String id, String name) {
    final encoded = name.split('/').map(Uri.encodeComponent).join('/');
    return 'https://archive.org/download/$id/$encoded';
  }
  /// Resolve a directly-playable audio URL for [track], caching per id.
  /// Returns null when the item exposes no playable file.
  Future<String?> resolveStreamUrl(Track track) async {
    if (track.isDownloaded) return track.localPath;
    if (track.streamUrl != null) return track.streamUrl;
    if (_streamCache.containsKey(track.id)) {
      track.streamUrl = _streamCache[track.id];
      return track.streamUrl;
    }
    final meta = await _fetchMetadata(track.id);
    if (meta == null) return null;
    final files = (meta['files'] as List?) ?? [];
    final pick = pickPlayableFile(files);
    if (pick == null) return null;
    final url = downloadUrl(track.id, pick['name'] as String);
    _streamCache[track.id] = url;
    track.streamUrl = url;
    return url;
  }
}
