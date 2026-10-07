/// A single playable track. Stream URLs are resolved lazily from the
/// Internet Archive; downloads carry a [localPath] for offline playback.
class Track {
  final String id; // Internet Archive identifier
  final String title;
  final String artist;
  final String license; // 'CC0', 'CC BY 4.0', 'CC BY 3.0'
  final String licenseUrl;
  final String artworkUrl;
  String? streamUrl; // resolved at play time
  String? localPath; // set when downloaded

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.license,
    required this.licenseUrl,
    required this.artworkUrl,
    this.streamUrl,
    this.localPath,
  });

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;
  bool get needsAttribution => license != 'CC0';

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Unknown title',
        artist: j['artist'] as String? ?? 'Unknown artist',
        license: j['license'] as String? ?? 'CC0',
        licenseUrl: j['licenseUrl'] as String? ?? '',
        artworkUrl: j['artworkUrl'] as String? ?? '',
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
        'streamUrl': streamUrl,
        'localPath': localPath,
      };

  @override
  bool operator ==(Object other) =>
      other is Track && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
