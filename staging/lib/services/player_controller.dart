import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'app_settings.dart';
import 'archive_api.dart';
import 'drive_source.dart';
import 'equalizer.dart';
import 'local_library.dart';
import 'lyrics_api.dart';
import 'stats_service.dart';

/// Builds the [AudioPipeline] for the player. The equalizer is only
/// attached when the platform has proven it implements the equalizer
/// method channel — on devices where it throws UnimplementedError
/// (e.g. androidEqualizerGetParameters not implemented behind the
/// background player), the pipeline is built WITHOUT the effect so
/// playback can never touch it. Pure function: unit-testable.
AudioPipeline buildAudioPipeline(
    {required bool eqSupported, required AndroidEqualizer equalizer}) {
  return eqSupported
      ? AudioPipeline(androidAudioEffects: [equalizer])
      : AudioPipeline();
}

/// Detects the platform declining the equalizer: just_audio surfaces
/// this as UnimplementedError mentioning the equalizer method.
/// Pure function: unit-testable.
bool isEqPlatformFailure(Object e) =>
    e is UnimplementedError && e.toString().contains('Equalizer');

/// Loop modes: 0 = off, 1 = repeat all, 2 = repeat one.
class PlayerController extends ChangeNotifier {
  final ArchiveApi api = ArchiveApi();

  /// System equalizer (Android native AudioEffect, via just_audio's
  /// built-in AndroidEqualizer which forwards through the background
  /// player's platform channel). Disabled by default; driven by
  /// EqualizerController once the platform connects. Only attached to
  /// the player's AudioPipeline while [_eqSupported] — on devices where
  /// the platform throws UnimplementedError for the equalizer, the
  /// player is rebuilt WITHOUT it (see [_disableEqAndRebuildPlayer]),
  /// so playback can never touch the effect.
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late AudioPlayer _player;

  /// False once the platform has proven it does not implement the
  /// equalizer method channel. The player is then rebuilt with an
  /// effect-free pipeline and the EQ UI is hidden.
  bool _eqSupported = true;

  /// 5-band system equalizer (beta). Initialized fire-and-forget in
  /// [init]; check [EqualizerController.ready] before showing controls.
  late final EqualizerController eqc = EqualizerController(equalizer);

  List<Track> _queue = [];
  List<int> _order = []; // playback order (shuffled or straight)
  int _orderPos = 0;

  /// Background-player sequence bookkeeping. The system notification only
  /// shows next/previous buttons when the background player actually holds
  /// a multi-item queue, so the app's queue is mirrored into a
  /// [ConcatenatingAudioSource]: `_seqPlayPos[s]` is the play-order
  /// position sitting at player sequence index `s`.
  List<int> _seqPlayPos = [];
  ConcatenatingAudioSource? _concat;

  /// Load generation: guards against overlapping _playCurrent calls and
  /// stuck futures. Only the latest generation may mutate loading state
  /// or replace the player's audio source.
  int _loadGen = 0;

  bool isLoading = false;
  String? error;

  final Set<String> _likedIds = {};
  final Map<String, Track> _likedTracks = {};
  final Map<String, List<Track>> playlists = {};
  final List<Track> downloads = [];
  final List<Track> recent = [];

  /// Tracks the user added from Google Drive ("My Drive").
  final List<Track> driveTracks = [];

  /// Tracks imported from the phone's own storage ("On this phone").
  /// Always carry a localPath; offline by nature.
  final List<Track> localTracks = [];

  final LyricsApi lyricsApi = LyricsApi();
  final LyricsCache lyricsCache = LyricsCache();

  /// User settings (IA collections on/off, auto-load lyrics).
  final AppSettings settings = AppSettings();

  /// Listening-stats backend (Supabase, anonymous sign-in). Best-effort:
  /// never blocks or breaks playback.
  final StatsService stats = StatsService();

  bool shuffle = false;
  int loopMode = 0; // 0 off, 1 all, 2 one

  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _indexSub;
  StreamSubscription? _playingSub;
  Duration position = Duration.zero;
  Duration? duration;

  final Set<String> _activeDownloads = {};
  final Map<String, double> downloadProgress = {};

  PlayerController() {
    // Optimistic: most devices implement the equalizer channel. If the
    // platform proves otherwise on first playback, the player is rebuilt
    // without the effect (see _playCurrent's retry path).
    _buildPlayer(withEq: true);
  }

  /// (Re)builds the underlying player and (re)attaches all stream
  /// listeners. Used at startup and when shedding the equalizer after
  /// the platform proves it unimplemented.
  void _buildPlayer({required bool withEq}) {
    _player = AudioPlayer(
      audioPipeline:
          buildAudioPipeline(eqSupported: withEq, equalizer: equalizer),
    );
    _attachPlayerListeners();
  }

  void _attachPlayerListeners() {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    _posSub = _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
    _durSub = _player.durationStream.listen((d) {
      duration = d;
      notifyListeners();
    });
    // The player — not the app — is the source of truth for track
    // position inside the background sequence (notification buttons,
    // auto-advance, loop modes all move it).
    _indexSub = _player.currentIndexStream.listen(_onSequenceIndex);
    // Invariant: "loading" can never be true while audio is playing.
    // This guarantees the play/pause slot never shows a stuck spinner
    // even if a load future hangs.
    _playingSub = _player.playingStream.listen((playing) {
      if (playing && isLoading) {
        isLoading = false;
        notifyListeners();
      }
    });
  }

  void _detachPlayerListeners() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _indexSub?.cancel();
    _playingSub?.cancel();
    _stateSub = _posSub = _durSub = _indexSub = _playingSub = null;
  }

  /// Permanently disables the equalizer for this session: marks the
  /// controller unsupported (hides EQ UI, stops init retries) and
  /// rebuilds the player with an effect-free pipeline so the throwing
  /// platform method is never called again.
  Future<void> _disableEqAndRebuildPlayer() async {
    _eqSupported = false;
    eqc.markUnsupported();
    _detachPlayerListeners();
    try {
      await _player.dispose();
    } catch (_) {}
    _buildPlayer(withEq: false);
  }

  Future<void> init() async {
    await settings.load();
    await _loadPersisted();
    stats.init(); // fire-and-forget: stats must never delay startup
    eqc.init(); // fire-and-forget: retries until the platform connects
  }

  @override
  void dispose() {
    _detachPlayerListeners();
    _player.dispose();
    super.dispose();
  }

  // ---------- queue / playback ----------

  Track? get currentTrack =>
      _queue.isEmpty || _order.isEmpty ? null : _queue[_order[_orderPos]];

  List<Track> get queue => List.unmodifiable(_queue);

  /// Tracks coming up after the current one, in play order.
  List<Track> get upNext {
    if (_order.isEmpty) return [];
    final out = <Track>[];
    for (var i = _orderPos + 1; i < _order.length; i++) {
      out.add(_queue[_order[i]]);
    }
    return out;
  }

  bool get isPlaying => _player.playing;

  void _rebuildOrder({bool reshuffle = false}) {
    _order = List.generate(_queue.length, (i) => i);
    if (shuffle) {
      _order.shuffle();
      if (reshuffle && _queue.isNotEmpty && currentTrack != null) {
        // Keep the current track first when toggling shuffle mid-queue.
        final cur = _queue.indexOf(currentTrack!);
        _order.remove(cur);
        _order.insert(0, cur);
        _orderPos = 0;
      }
    }
  }

  /// Maps a track to its stats source bucket.
  String _statsSource(Track t) {
    if (t.isLocalTrack) return 'local';
    if (t.isDriveTrack) return 'drive';
    return 'archive';
  }

  /// Logs the outgoing track as a skip when it played >= 30s.
  /// Called before the queue moves away from the current track via a
  /// path that does NOT go through the player's sequence index stream
  /// (which logs for itself).
  void _logSkip() {
    final track = currentTrack;
    if (track == null) return;
    final secs = position.inSeconds;
    if (secs < 30) return;
    stats.logEvent(
      trackTitle: track.title,
      trackArtist: track.artist,
      source: _statsSource(track),
      durationListenedS: secs,
      completed: false,
    );
  }

  /// Logs the current track as fully played (natural completion).
  void _logCompleted() {
    final track = currentTrack;
    if (track == null) return;
    stats.logEvent(
      trackTitle: track.title,
      trackArtist: track.artist,
      source: _statsSource(track),
      durationListenedS: duration?.inSeconds ?? position.inSeconds,
      completed: true,
    );
  }

  Future<void> playTracks(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    _logSkip();
    error = null;
    _queue = List.of(tracks);
    _rebuildOrder();
    _orderPos = shuffle ? _order.indexOf(startIndex) : startIndex;
    if (_orderPos < 0) _orderPos = 0;
    await _playCurrent();
  }

  Future<void> playTrack(Track track) => playTracks([track], 0);

  AudioSource _taggedSource(Track track, String url) {
    final uri = track.isDownloaded
        ? Uri.file(url)
        : Uri.parse(url);
    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: '${track.id}::${track.title}',
        album: track.isDriveTrack ? 'Vani · My Drive' : 'Vani · Internet Archive',
        title: track.title,
        artist: track.artist,
        artUri: track.artworkUrl.isEmpty
            ? null
            : Uri.parse(track.artworkUrl),
      ),
    );
  }

  /// Maps the app's loop mode onto just_audio's: repeat-all is handled by
  /// the player itself so auto-advance stays in sync with the notification.
  void _applyLoopMode() {
    _player.setLoopMode(switch (loopMode) {
      2 => LoopMode.one,
      1 => LoopMode.all,
      _ => LoopMode.off,
    });
  }

  Future<void> _playCurrent() async {
    final gen = ++_loadGen;
    final track = currentTrack;
    if (track == null) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      var attempt = 0;
      while (true) {
        attempt++;
        try {
          final url = await api
              .resolveStreamUrl(track)
              .timeout(const Duration(seconds: 45));
          // A newer load superseded us: bail without touching shared state.
          if (gen != _loadGen) return;
          if (url == null) {
            error = 'Could not load "${track.title}"';
            return;
          }
          // Fresh single-track sequence around the current track; the rest of
          // the queue is appended in the background by _fillSequence so the
          // notification gains working next/previous buttons.
          _seqPlayPos = [_orderPos];
          _concat =
              ConcatenatingAudioSource(children: [_taggedSource(track, url)]);
          await _player
              .setAudioSource(_concat!, initialIndex: 0)
              .timeout(const Duration(seconds: 30));
          if (gen != _loadGen) return;
          _applyLoopMode();
          _recordRecent(track);
          await _player.play().timeout(const Duration(seconds: 15));
          break; // success
        } catch (e) {
          // The platform declining the equalizer kills setAudioSource via
          // just_audio's effect _activate. Shed the effect and retry once
          // with an EQ-free player instead of failing playback entirely.
          if (attempt == 1 && _eqSupported && isEqPlatformFailure(e)) {
            await _disableEqAndRebuildPlayer();
            continue;
          }
          rethrow;
        }
      }
    } on TimeoutException {
      error = 'Timed out loading "${track.title}" — check your connection';
    } catch (e) {
      error = 'Playback failed: $e';
    } finally {
      // Only the latest generation clears the flag: a stale call can
      // never leave the spinner stuck on.
      if (gen == _loadGen) {
        isLoading = false;
        notifyListeners();
      }
    }
    if (gen == _loadGen) _fillSequence(gen);
  }

  /// Appends the rest of the queue (in play order) into the background
  /// player's sequence so hasNext/hasPrevious become true and the system
  /// notification / lock-screen controls show prev/play/next buttons.
  /// Fire-and-forget; fully guarded by the load generation.
  Future<void> _fillSequence(int gen) async {
    for (var p = 0; p < _order.length; p++) {
      if (gen != _loadGen) return;
      if (p == _orderPos || _seqPlayPos.contains(p)) continue;
      final t = _queue[_order[p]];
      String? url;
      try {
        url =
            await api.resolveStreamUrl(t).timeout(const Duration(seconds: 20));
      } catch (_) {
        continue; // skip unresolvable tracks, keep the rest
      }
      if (gen != _loadGen) return;
      if (url == null) continue;
      final concat = _concat;
      if (concat == null) return;
      // Sequence position = how many already-sequenced play-positions
      // sit before p. (Check-then-act is atomic: no await between the
      // generation check and the insert call below.)
      final s = _seqPlayPos.where((x) => x < p).length;
      try {
        await concat.insert(s, _taggedSource(t, url));
      } catch (_) {
        return; // sequence was replaced/detached; the new gen refills
      }
      if (gen != _loadGen || !identical(_concat, concat)) return;
      _seqPlayPos.insert(s, p);
      // just_audio shifts its currentIndex itself on insert; _orderPos is
      // play-order based so it stays valid without adjustment.
    }
  }

  /// Fires when the background player's sequence index changes — i.e. the
  /// user pressed notification/lock-screen next/previous, or the player
  /// auto-advanced (or looped). Syncs the app's position and logs stats.
  void _onSequenceIndex(int? s) {
    if (s == null || _seqPlayPos.isEmpty) return;
    if (s < 0 || s >= _seqPlayPos.length) return;
    final p = _seqPlayPos[s];
    if (p == _orderPos) return;
    final prev = currentTrack;
    final secs = position.inSeconds;
    final durSecs = duration?.inSeconds ?? 0;
    _orderPos = p;
    final track = currentTrack;
    if (track != null) _recordRecent(track);
    if (prev != null) {
      if (durSecs > 0 && secs >= durSecs - 3) {
        stats.logEvent(
          trackTitle: prev.title,
          trackArtist: prev.artist,
          source: _statsSource(prev),
          durationListenedS: durSecs,
          completed: true,
        );
      } else if (secs >= 30) {
        stats.logEvent(
          trackTitle: prev.title,
          trackArtist: prev.artist,
          source: _statsSource(prev),
          durationListenedS: secs,
          completed: false,
        );
      }
    }
    notifyListeners();
  }

  void _onPlayerState(PlayerState state) {
    notifyListeners();
    if (state.processingState == ProcessingState.completed) {
      // With a concatenating source this only fires at the true end of
      // the sequence under LoopMode.off (LoopMode.all/one loop internally
      // without surfacing completed). Per-track completion is logged by
      // _onSequenceIndex.
      _logCompleted();
      _player.stop(); // back to idle so replay starts clean
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle &&
          currentTrack != null) {
        await _playCurrent();
      } else {
        await _player.play();
      }
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    int target;
    if (_orderPos + 1 < _order.length) {
      target = _orderPos + 1;
    } else if (loopMode == 1) {
      target = 0; // repeat-all wraps (player also loops, this is a fallback)
    } else {
      await _player.stop();
      notifyListeners();
      return;
    }
    final s = _seqPlayPos.indexOf(target);
    if (s >= 0) {
      // Target is already in the background sequence: let the player
      // move; _onSequenceIndex syncs _orderPos and logs stats.
      await _player.seek(Duration.zero, index: s);
      await _player.play();
      return;
    }
    // Not sequenced yet (URL still resolving): rebuild around the target.
    _logSkip();
    _orderPos = target;
    await _playCurrent();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    final target = _orderPos - 1;
    if (target < 0) {
      await _player.seek(Duration.zero);
      return;
    }
    final s = _seqPlayPos.indexOf(target);
    if (s >= 0) {
      await _player.seek(Duration.zero, index: s);
      await _player.play();
      return;
    }
    _logSkip();
    _orderPos = target;
    await _playCurrent();
  }

  Future<void> jumpToQueueIndex(int queueIndex) async {
    final pos = _order.indexOf(queueIndex);
    if (pos < 0) return;
    final s = _seqPlayPos.indexOf(pos);
    if (s >= 0) {
      await _player.seek(Duration.zero, index: s);
      await _player.play();
      return;
    }
    _logSkip();
    _orderPos = pos;
    await _playCurrent();
  }

  Future<void> seek(Duration d) => _player.seek(d);

  void toggleShuffle() {
    shuffle = !shuffle;
    final cur = currentTrack;
    final pos = position;
    final wasPlaying = _player.playing;
    _rebuildOrder(reshuffle: true);
    notifyListeners();
    // The background sequence is in old play order: rebuild it around the
    // current track so notification next/previous follow the new order.
    if (cur != null) {
      _rebuildSequenceAroundCurrent(pos, wasPlaying);
    }
  }

  /// Rebuilds the background sequence in the (possibly reshuffled) play
  /// order, keeping the current track and its position.
  Future<void> _rebuildSequenceAroundCurrent(
      Duration keepPos, bool wasPlaying) async {
    final gen = ++_loadGen;
    final track = currentTrack;
    if (track == null) return;
    try {
      final url = await api
          .resolveStreamUrl(track)
          .timeout(const Duration(seconds: 30));
      if (gen != _loadGen || url == null) return;
      _seqPlayPos = [_orderPos];
      _concat = ConcatenatingAudioSource(children: [_taggedSource(track, url)]);
      await _player.setAudioSource(_concat!, initialIndex: 0);
      if (gen != _loadGen) return;
      _applyLoopMode();
      await _player.seek(keepPos);
      if (wasPlaying) await _player.play();
      _fillSequence(gen);
    } catch (_) {
      // Keep the old sequence on failure; playback continues.
    }
  }

  void cycleLoop() {
    loopMode = (loopMode + 1) % 3;
    _applyLoopMode();
    notifyListeners();
  }

  // ---------- likes ----------

  bool isLiked(Track t) => _likedIds.contains(_trackKey(t));

  String _trackKey(Track t) => '${t.id}::${t.title}';

  List<Track> get likedSongs => _likedIds
      .map((k) => _likedTracks[k])
      .whereType<Track>()
      .toList();

  Future<void> toggleLike(Track t) async {
    final k = _trackKey(t);
    if (_likedIds.contains(k)) {
      _likedIds.remove(k);
      _likedTracks.remove(k);
    } else {
      _likedIds.add(k);
      _likedTracks[k] = t;
    }
    notifyListeners();
    await _persist();
  }

  // ---------- playlists ----------

  Future<void> createPlaylist(String name) async {
    final n = name.trim();
    if (n.isEmpty || playlists.containsKey(n)) return;
    playlists[n] = [];
    notifyListeners();
    await _persist();
  }

  Future<void> renamePlaylist(String oldName, String newName) async {
    final n = newName.trim();
    if (n.isEmpty || !playlists.containsKey(oldName)) return;
    if (oldName == n) return;
    if (playlists.containsKey(n)) return; // don't clobber an existing one
    final tracks = playlists.remove(oldName)!;
    playlists[n] = tracks;
    notifyListeners();
    await _persist();
  }

  Future<void> addToPlaylist(String name, Track t) async {
    final list = playlists[name];
    if (list == null || list.any((e) => e == t)) return;
    list.add(t);
    notifyListeners();
    await _persist();
  }

  Future<void> removeFromPlaylist(String name, Track t) async {
    playlists[name]?.removeWhere((e) => e == t);
    notifyListeners();
    await _persist();
  }

  Future<void> deletePlaylist(String name) async {
    playlists.remove(name);
    notifyListeners();
    await _persist();
  }

  // ---------- recently played ----------

  void _recordRecent(Track t) {
    recent.removeWhere((e) => e == t);
    recent.insert(0, t);
    if (recent.length > 50) recent.removeRange(50, recent.length);
    _persist(); // fire-and-forget
  }

  // ---------- downloads ----------

  Future<Directory> _dlDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/opentune');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  bool isDownloading(Track t) => _activeDownloads.contains(_trackKey(t));

  double? downloadProgressOf(Track t) =>
      downloadProgress[_trackKey(t)];

  Future<void> downloadTrack(Track t) async {
    final key = _trackKey(t);
    if (t.isDownloaded || _activeDownloads.contains(key)) return;
    _activeDownloads.add(key);
    downloadProgress[key] = 0;
    error = null;
    notifyListeners();
    try {
      final url = await api.resolveStreamUrl(t);
      if (url == null) {
        error = 'Could not download "${t.title}"';
        return;
      }
      final req = http.Request('GET', Uri.parse(url));
      final streamed = await http.Client().send(req);
      if (streamed.statusCode != 200) {
        error = 'Download failed (${streamed.statusCode})';
        return;
      }
      final total = streamed.contentLength ?? 0;
      final dir = await _dlDir();
      final safe = t.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeId = t.id.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/${safeId}_$safe.mp3');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          downloadProgress[key] = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      t.localPath = file.path;
      if (!downloads.any((e) => e == t)) downloads.add(t);
      await _persist();
    } catch (e) {
      error = 'Download failed: $e';
    } finally {
      _activeDownloads.remove(key);
      downloadProgress.remove(key);
      notifyListeners();
    }
  }

  Future<void> deleteDownload(Track t) async {
    try {
      if (t.localPath != null) {
        final f = File(t.localPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    t.localPath = null;
    downloads.removeWhere((e) => e == t);
    notifyListeners();
    await _persist();
  }

  // ---------- google drive ("my drive") ----------

  /// Builds a Drive [Track] from a user-supplied share link (or a bare
  /// file ID). Returns null when no Drive file ID can be parsed.
  Track? driveTrackFromLink(String link,
      {String? title, String? artist}) {
    final id = DriveSource.parseDriveFileId(link);
    if (id == null) return null;
    final t = (title == null || title.trim().isEmpty)
        ? DriveSource.deriveTitle(link)
        : title.trim();
    final a = (artist == null || artist.trim().isEmpty)
        ? 'Unknown artist'
        : artist.trim();
    return Track(
      id: 'drive:$id',
      title: t,
      artist: a,
      license: 'Drive',
      licenseUrl: '',
      artworkUrl: '',
      source: 'drive',
      streamUrl: DriveSource.driveStreamUrl(id),
    );
  }

  /// Adds a Drive track if an identical one isn't already saved.
  Future<bool> addDriveTrack(Track t) async {
    if (driveTracks.any((e) => e.id == t.id)) return false;
    driveTracks.add(t);
    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> removeDriveTrack(Track t) async {
    driveTracks.removeWhere((e) => e.id == t.id);
    notifyListeners();
    await _persist();
  }

  /// Replaces a Drive track's title/artist (Track is immutable).
  Future<void> updateDriveTrack(Track old, String title, String artist,
      {String? artworkUrl}) async {
    final i = driveTracks.indexWhere((e) => e.id == old.id);
    if (i < 0) return;
    final t = (title.trim().isEmpty ? old.title : title.trim());
    final a = (artist.trim().isEmpty ? old.artist : artist.trim());
    driveTracks[i] = old.copyWith(title: t, artist: a, artworkUrl: artworkUrl);
    notifyListeners();
    await _persist();
  }

  /// Fetches an index JSON file from [indexUrl] and imports every entry
  /// as a Drive track. Entry URLs may be Drive share links (converted)
  /// or direct audio URLs. Returns the number of tracks added.
  Future<int> importDriveIndex(String indexUrl) async {
    final url = indexUrl.trim();
    if (url.isEmpty) return 0;
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      error = 'Could not fetch index (${res.statusCode})';
      notifyListeners();
      return 0;
    }
    final entries = DriveIndex.parse(res.body);
    var added = 0;
    for (final e in entries) {
      final fileId = DriveSource.parseDriveFileId(e.url);
      final Track t;
      if (fileId != null && DriveSource.isDriveUrl(e.url)) {
        t = Track(
          id: 'drive:$fileId',
          title: e.title,
          artist: e.artist,
          license: 'Drive',
          licenseUrl: '',
          artworkUrl: '',
          source: 'drive',
          streamUrl: DriveSource.driveStreamUrl(fileId),
        );
      } else {
        t = Track(
          id: 'driveurl:${DriveSource.stableUrlId(e.url)}',
          title: e.title,
          artist: e.artist,
          license: 'Drive',
          licenseUrl: '',
          artworkUrl: '',
          source: 'drive',
          streamUrl: e.url,
        );
      }
      if (await addDriveTrack(t)) added++;
    }
    if (added == 0 && entries.isEmpty) {
      error = 'No tracks found in that index file';
      notifyListeners();
    }
    return added;
  }

  // ---------- local tracks ("on this phone") ----------

  /// Imports audio files picked from device storage: copies them into
  /// the app's library dir and registers them as local tracks.
  /// Returns the number of tracks added.
  Future<int> importLocalFiles() async {
    final picked = await LocalLibrary.pickAudioFiles();
    if (picked == null || picked.isEmpty) return 0;
    final tracks = await LocalLibrary.importPicked(picked);
    var added = 0;
    for (final t in tracks) {
      if (localTracks.any((e) => e.id == t.id)) continue;
      localTracks.add(t);
      added++;
    }
    if (added > 0) {
      notifyListeners();
      await _persist();
    }
    return added;
  }

  Future<void> removeLocalTrack(Track t) async {
    localTracks.removeWhere((e) => e.id == t.id);
    await LocalLibrary.deleteLocal(t);
    notifyListeners();
    await _persist();
  }

  /// Replaces a local track's metadata (and/or its file path after a
  /// rename). Used by the AI Fixer. Track is immutable so we swap it.
  Future<void> updateLocalTrack(Track old,
      {String? title, String? artist, String? localPath, String? artworkUrl}) async {
    final i = localTracks.indexWhere((e) => e.id == old.id);
    if (i < 0) return;
    final t = Track(
      id: old.id,
      title: (title == null || title.trim().isEmpty) ? old.title : title.trim(),
      artist:
          (artist == null || artist.trim().isEmpty) ? old.artist : artist.trim(),
      license: old.license,
      licenseUrl: old.licenseUrl,
      artworkUrl: artworkUrl ?? old.artworkUrl,
      source: old.source,
      streamUrl: old.streamUrl,
      localPath: localPath ?? old.localPath,
    );
    localTracks[i] = t;
    notifyListeners();
    await _persist();
  }

  /// Imports a whole folder (recursively) picked via the Storage Access
  /// Framework. Returns the number of tracks added. Progress callback
  /// receives (done, total).
  Future<int> importLocalFolder(
      {void Function(int done, int total)? onProgress}) async {
    final tracks =
        await LocalLibrary.importFolder(onProgress: onProgress);
    var added = 0;
    for (final t in tracks) {
      if (localTracks.any((e) => e.id == t.id)) continue;
      localTracks.add(t);
      added++;
    }
    if (added > 0) {
      notifyListeners();
      await _persist();
    }
    return added;
  }

  // ---------- lyrics ----------

  /// Identity string used to key the lyrics cache for [t].
  String lyricsIdentity(Track t) =>
      '${t.source}::${t.id}::${t.title}::${t.artist}';

  /// Explicit lyrics lookup: cache first, then one lrclib.net request.
  /// Call only from a user tap — never in a loop.
  Future<LyricsResult> fetchLyrics(Track t) async {
    final key = lyricsIdentity(t);
    final cached = await lyricsCache.get(key);
    if (cached != null) return cached;
    final result = await lyricsApi.fetch(
      artist: t.artist,
      title: t.title,
      durationSeconds: duration?.inSeconds,
    );
    await lyricsCache.put(key, result);
    return result;
  }

  /// Manual override: look up lyrics with user-corrected artist/title
  /// (for bad metadata). One request; result is cached under the
  /// override identity so repeat views don't re-hit the API.
  Future<LyricsResult> fetchLyricsOverride(
      Track t, String artist, String title) async {
    final key = 'override::${artist.toLowerCase().trim()}::'
        '${title.toLowerCase().trim()}';
    final cached = await lyricsCache.get(key);
    if (cached != null) return cached;
    final result = await lyricsApi.fetch(
      artist: artist,
      title: title,
      durationSeconds: duration?.inSeconds,
    );
    await lyricsCache.put(key, result);
    return result;
  }

  // ---------- persistence ----------

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'liked',
        jsonEncode(
            _likedTracks.values.map((t) => t.toJson()).toList()));
    await prefs.setString(
        'playlists',
        jsonEncode(playlists.map(
            (k, v) => MapEntry(k, v.map((t) => t.toJson()).toList()))));
    await prefs.setString(
        'downloads', jsonEncode(downloads.map((t) => t.toJson()).toList()));
    await prefs.setString(
        'drive', jsonEncode(driveTracks.map((t) => t.toJson()).toList()));
    await prefs.setString(
        'local', jsonEncode(localTracks.map((t) => t.toJson()).toList()));
    await prefs.setString(
        'recent', jsonEncode(recent.map((t) => t.toJson()).toList()));
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final liked = jsonDecode(prefs.getString('liked') ?? '[]') as List;
      for (final j in liked.whereType<Map<String, dynamic>>()) {
        final t = Track.fromJson(j);
        final k = _trackKey(t);
        _likedIds.add(k);
        _likedTracks[k] = t;
      }
      final pls = jsonDecode(prefs.getString('playlists') ?? '{}') as Map;
      pls.forEach((k, v) {
        playlists[k as String] = (v as List)
            .whereType<Map<String, dynamic>>()
            .map(Track.fromJson)
            .toList();
      });
      final dls = jsonDecode(prefs.getString('downloads') ?? '[]') as List;
      for (final j in dls.whereType<Map<String, dynamic>>()) {
        final t = Track.fromJson(j);
        // Keep only files that still exist.
        if (t.localPath != null && await File(t.localPath!).exists()) {
          downloads.add(t);
        }
      }
      final dr = jsonDecode(prefs.getString('drive') ?? '[]') as List;
      for (final j in dr.whereType<Map<String, dynamic>>()) {
        driveTracks.add(Track.fromJson(j));
      }
      final loc = jsonDecode(prefs.getString('local') ?? '[]') as List;
      for (final j in loc.whereType<Map<String, dynamic>>()) {
        final t = Track.fromJson(j);
        // Keep only files that still exist.
        if (t.localPath != null && await File(t.localPath!).exists()) {
          localTracks.add(t);
        }
      }
      final rec = jsonDecode(prefs.getString('recent') ?? '[]') as List;
      for (final j in rec.whereType<Map<String, dynamic>>()) {
        recent.add(Track.fromJson(j));
        if (recent.length >= 50) break;
      }
    } catch (_) {}
    notifyListeners();
  }
}
