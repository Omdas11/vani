import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import '../models/track.dart';

/// "Import from phone": lets the user pick audio files from device
/// storage and adds them as local tracks.
///
/// DESIGN DECISION (documented): picked files are **copied** into the
/// app's documents directory (`opentune/local/`), not referenced in
/// place. Rationale:
/// - `file_picker` on Android uses the Storage Access Framework, so no
///   storage permission is needed at all (no READ_MEDIA_AUDIO dance,
///   works on Android 13+ scoped storage).
/// - Referenced `content://` URIs would need persistable URI permissions
///   via a platform channel and can break if the user moves/deletes the
///   original file.
/// - Copied files play offline by nature and survive app restarts.
/// Trade-off: importing duplicates the bytes on disk. The Library's
/// local-tracks list lets the user remove imports (deletes the copy).
class LocalLibrary {
  /// Opens the system file picker for audio files. Returns the picked
  /// platform files (with read streams), or null when cancelled.
  static Future<List<PlatformFile>?> pickAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      withReadStream: true,
    );
    return result?.files;
  }

  /// Copies picked files into the app's local library dir and builds
  /// [Track]s for them. Title/artist are derived from the filename
  /// ("Artist - Title.mp3" supported); the user can rename later.
  /// Returns the created tracks.
  static Future<List<Track>> importPicked(
      List<PlatformFile> picked) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/opentune/local');
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = <Track>[];
    for (final f in picked) {
      try {
        final name = f.name;
        final dest = File('${dir.path}/${_safe(name)}');
        if (f.readStream != null) {
          final sink = dest.openWrite();
          await for (final chunk in f.readStream!) {
            sink.add(chunk);
          }
          await sink.close();
        } else if (f.path != null) {
          await File(f.path!).copy(dest.path);
        } else {
          continue;
        }
        final id = 'local:${stableId(dest.path)}';
        final meta = _splitArtistTitle(name);
        out.add(Track(
          id: id,
          title: meta[0],
          artist: meta[1],
          license: 'Local',
          licenseUrl: '',
          artworkUrl: '',
          source: 'local',
          localPath: dest.path,
        ));
      } catch (_) {
        // Skip files that fail; keep the rest.
      }
    }
    return out;
  }

  /// Deletes the copied file for [track]. Best-effort.
  static Future<void> deleteLocal(Track track) async {
    try {
      if (track.localPath != null) {
        final f = File(track.localPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  /// Audio extensions recognized during folder import.
  /// Public for testing.
  static const audioExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.ogg',
    '.oga',
    '.opus',
    '.wav',
    '.flac',
    '.wma',
  };

  /// Picks a whole folder via the Storage Access Framework and imports
  /// every audio file inside it, recursing into subfolders. Files are
  /// copied into the app's library dir (same decision as [importPicked]).
  /// Returns the created tracks. [onProgress] receives (done, total).
  /// Returns [] when the user cancels or the platform isn't Android.
  static Future<List<Track>> importFolder(
      {void Function(int done, int total)? onProgress}) async {
    if (!Platform.isAndroid) return [];
    final saf = Saf();
    final dir = await saf.pickDirectory();
    if (dir == null) return [];
    final docs = await getApplicationDocumentsDirectory();
    final destRoot = Directory('${docs.path}/opentune/local');
    if (!await destRoot.exists()) {
      await destRoot.create(recursive: true);
    }
    // Collect audio files recursively first, so progress has a total.
    final entries = <SafWalkEntry>[];
    await for (final e in saf.walk(dir.uri)) {
      if (e.file.isDir) continue;
      final lower = e.file.name.toLowerCase();
      if (audioExtensions.any(lower.endsWith)) entries.add(e);
    }
    final out = <Track>[];
    var done = 0;
    for (final e in entries) {
      try {
        // Preserve subfolder structure (each segment sanitized) to avoid
        // name clashes between same-named files in different folders.
        final safeRel = e.relativePath
            .split('/')
            .map(_safe)
            .where((s) => s.isNotEmpty && s != '.' && s != '..')
            .join('/');
        if (safeRel.isEmpty) continue;
        final dest = File('${destRoot.path}/$safeRel');
        await dest.parent.create(recursive: true);
        await saf.copyToLocalFile(e.file.uri, dest.path);
        final id = 'local:${stableId(dest.path)}';
        final meta = _splitArtistTitle(e.file.name);
        out.add(Track(
          id: id,
          title: meta[0],
          artist: meta[1],
          license: 'Local',
          licenseUrl: '',
          artworkUrl: '',
          source: 'local',
          localPath: dest.path,
        ));
      } catch (_) {
        // Skip files that fail; keep the rest.
      }
      done++;
      onProgress?.call(done, entries.length);
    }
    return out;
  }

  /// Stable id for a file path (FNV-1a hex) — deterministic across
  /// restarts so re-imports dedupe. Public for testing.
  static String stableId(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Splits "Artist - Title.ext" into [title, artist]; falls back to
  /// (basename-without-ext, 'Unknown artist'). Public for testing.
  static List<String> _splitArtistTitle(String filename) {
    var base = filename;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final dash = base.indexOf(' - ');
    if (dash > 0) {
      final artist = base.substring(0, dash).trim();
      final title = base.substring(dash + 3).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return [title, artist];
      }
    }
    final clean = base.replaceAll(RegExp(r'[_+]+'), ' ').trim();
    return [clean.isEmpty ? 'Local track' : clean, 'Unknown artist'];
  }

  static String _safe(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
