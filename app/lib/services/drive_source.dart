import 'dart:convert';

/// Google Drive helpers: parse share links into streamable URLs and
/// import track lists from a user-hosted index JSON file.
///
/// Pure functions (no network) so they are unit-testable. Everything here
/// works with files the user has shared as "Anyone with the link".
class DriveSource {
  /// Extracts a Drive file ID from the common share-link formats:
  /// - https://drive.google.com/file/d/<id>/view?...
  /// - https://drive.google.com/file/d/<id>
  /// - https://drive.google.com/open?id=<id>
  /// - https://drive.google.com/uc?id=<id>&export=download
  /// - the same with /u/0/ (or /u/1/...) account segments
  /// - a bare file ID pasted on its own
  /// Returns null when no ID can be found.
  static String? parseDriveFileId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;

    // /file/d/<id>[/...]
    final fileD = RegExp(r'drive\.google\.com(?:/u/\d+)?/file/d/([^/?#&]+)');
    final m1 = fileD.firstMatch(s);
    if (m1 != null) return m1.group(1);

    // ?id=<id> or &id=<id>  (covers /open?id= and /uc?id=)
    final idParam = RegExp(r'[?&]id=([^&#]+)');
    final m2 = idParam.firstMatch(s);
    if (m2 != null) return Uri.decodeComponent(m2.group(1)!);

    // Bare file ID: Drive IDs are long URL-safe base64-ish strings.
    final bare = RegExp(r'^[A-Za-z0-9_-]{20,}$');
    if (bare.hasMatch(s)) return s;

    return null;
  }

  /// Direct stream/download URL for a Drive file ID.
  static String driveStreamUrl(String fileId) =>
      'https://drive.google.com/uc?export=download&id=$fileId';

  /// True when [url] points at drive.google.com.
  static bool isDriveUrl(String url) => url.contains('drive.google.com');

  /// Converts a user-supplied link into a streamable URL:
  /// Drive share links become uc?export=download URLs, anything else
  /// is returned unchanged (trimmed).
  static String toStreamUrl(String url) {
    final t = url.trim();
    final id = parseDriveFileId(t);
    if (id != null && isDriveUrl(t)) return driveStreamUrl(id);
    return t;
  }

  /// Stable short id for a non-Drive URL (FNV-1a hex), so index-imported
  /// tracks keep a deterministic identity across restarts.
  static String stableUrlId(String url) {
    var h = 0x811c9dc5;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Derives a display title from a URL when no metadata is available:
  /// last path segment, URL-decoded, extension stripped. Falls back to
  /// 'Drive track'.
  static String deriveTitle(String url) {
    try {
      final uri = Uri.parse(url.trim());
      var seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      seg = Uri.decodeComponent(seg).trim();
      final dot = seg.lastIndexOf('.');
      if (dot > 0) seg = seg.substring(0, dot);
      if (seg.isNotEmpty && seg != 'view' && seg != 'open' && seg != 'uc') {
        return seg.replaceAll(RegExp(r'[_+]+'), ' ');
      }
    } catch (_) {}
    return 'Drive track';
  }
}

/// One entry parsed from a user-hosted index JSON file.
class DriveIndexEntry {
  final String title;
  final String artist;
  final String url; // streamable URL (Drive links already converted)

  DriveIndexEntry({
    required this.title,
    required this.artist,
    required this.url,
  });
}

/// Parses an index JSON document into track entries.
///
/// Accepted shapes:
///   [ {"title": "...", "artist": "...", "url": "..."}, ... ]
///   { "tracks": [ ... ] }        (also accepts "songs" as the key)
///
/// - "url" is required; entries without one are skipped.
/// - "title" is optional → derived from the URL.
/// - "artist" is optional → 'Unknown artist'.
/// - Drive share links in "url" are converted to stream URLs.
class DriveIndex {
  static List<DriveIndexEntry> parse(String body) {
    dynamic decoded;
    try {
      // Tolerate a UTF-8 BOM, which some editors add to hosted JSON files.
      final s = body.startsWith('﻿') ? body.substring(1) : body;
      decoded = jsonDecode(s);
    } catch (_) {
      return [];
    }
    final List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      final inner = decoded['tracks'] ?? decoded['songs'];
      if (inner is! List) return [];
      list = inner;
    } else {
      return [];
    }
    final out = <DriveIndexEntry>[];
    for (final e in list) {
      if (e is! Map) continue;
      final url = (e['url'] as String?)?.trim();
      if (url == null || url.isEmpty) continue;
      final title = (e['title'] as String?)?.trim();
      final artist = (e['artist'] as String?)?.trim();
      out.add(DriveIndexEntry(
        title: (title == null || title.isEmpty)
            ? DriveSource.deriveTitle(url)
            : title,
        artist: (artist == null || artist.isEmpty) ? 'Unknown artist' : artist,
        url: DriveSource.toStreamUrl(url),
      ));
    }
    return out;
  }
}
