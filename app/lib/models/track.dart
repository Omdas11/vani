/// A single playable track. Stream URLs are resolved lazily from the
/// Internet Archive; downloads carry a [localPath] for offline playback.
/// Tracks the user adds from Google Drive use [source] == 'drive' and
/// carry their stream URL directly. Tracks imported from phone storage
/// use [source] == 'local' and always carry a [localPath].
class Track {
  final String id; // IA identifier, or 'drive:<fileId>' / 'driveurl:<hash>'
  final String title;
  final String artist;
  final String license; // 'CC0', 'CC BY 4.0', 'CC BY 3.0', or 'Drive'
  final String licenseUrl;
  final String artworkUrl;
  final String source; // 'archive', 'drive', or 'local'
  String? streamUrl; // resolved at play time (preset for Drive tracks)
  String? localPath; // set when downloaded

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.license,
    required this.licenseUrl,
    required this.artworkUrl,
    this.source = 'archive',
    this.streamUrl,
    this.localPath,
  });

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;
  bool get needsAttribution => license != 'CC0' && source == 'archive';
  bool get isDriveTrack => source == 'drive';
  bool get isLocalTrack => source == 'local';

  /// Audio format derived from the file extension (local path first,
  /// then stream URL), e.g. "FLAC", "OPUS", "MP3". Null when unknown.
  String? get audioFormat {
    final path =
        (localPath?.isNotEmpty == true ? localPath! : streamUrl) ?? '';
    final clean = path.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return null;
    final ext = clean.substring(dot).toLowerCase();
    const known = {
      '.flac',
      '.opus',
      '.ogg',
      '.oga',
      '.mp3',
      '.m4a',
      '.aac',
      '.wav',
      '.wma',
    };
    return known.contains(ext) ? ext.substring(1).toUpperCase() : null;
  }

  /// Formats whose playback support is still in early testing (beta).
  /// ExoPlayer handles FLAC and Opus on Android, but seeking and gapless
  /// behavior vary by device and container.
  bool get isBetaFormat {
    final f = audioFormat;
    return f == 'FLAC' || f == 'OPUS';
  }

  Track copyWith({String? title, String? artist, String? artworkUrl}) =>
      Track(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        license: license,
        licenseUrl: licenseUrl,
        artworkUrl: artworkUrl ?? this.artworkUrl,
        source: source,
        streamUrl: streamUrl,
        localPath: localPath,
      );

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Unknown title',
        artist: j['artist'] as String? ?? 'Unknown artist',
        license: j['license'] as String? ?? 'CC0',
        licenseUrl: j['licenseUrl'] as String? ?? '',
        artworkUrl: j['artworkUrl'] as String? ?? '',
        source: j['source'] as String? ?? 'archive',
        streamUrl: j['streamUrl'] as String?,
        localPath: j['localPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'license': license,
        'licenseUrl': licenseUrl,
        'artworkUrl': artworkUrl,
        'source': source,
        'streamUrl': streamUrl,
        'localPath': localPath,
      };

  @override
  bool operator ==(Object other) =>
      other is Track && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
