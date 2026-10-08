import 'dart:io';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/ai_fixer.dart';
import '../services/player_controller.dart';
import '../widgets/ai_provider_card.dart';

/// "AI Fixer (BETA)" — cleans up local/Drive track filenames and metadata
/// with the user's own AI provider key (called directly from the phone),
/// re-checks lyrics with the corrected metadata, and fetches cover art
/// from free keyless sources (iTunes, then MusicBrainz + Cover Art
/// Archive).
///
/// Every suggestion is previewed first (before → after per track, with a
/// per-track checkbox); nothing changes until "Apply selected" is tapped.
/// Provider + key management lives in [AiProviderCard], which is also
/// embedded in Settings.
class AiFixerScreen extends StatefulWidget {
  final PlayerController pc;
  const AiFixerScreen({super.key, required this.pc});

  @override
  State<AiFixerScreen> createState() => _AiFixerScreenState();
}

/// One track's proposed changes, built during analysis.
class _FixProposal {
  final Track track;
  String? newFilename; // basename only, local tracks
  String? newTitle;
  String? newArtist;
  bool? lyricsFound; // null when the lyrics task was off
  bool? coverFound; // null when the cover task was off
  String? coverPath; // downloaded preview image (docs dir)
  bool driveRenameSkipped = false;
  String? error; // per-row failure message
  bool include; // user checkbox for Apply
  _FixProposal(this.track, {this.include = true});

  bool get hasChanges =>
      newFilename != null ||
      newTitle != null ||
      newArtist != null ||
      coverPath != null;
}

class _AiFixerScreenState extends State<AiFixerScreen> {
  late final AiFixer _fixer;

  // Track source selection: 0 = single, 1 = batch.
  int _mode = 0;
  Track? _single;
  final Set<String> _batchIds = {};

  // Tasks.
  bool _taskFilenames = true;
  bool _taskMetadata = true;
  bool _taskLyrics = false;
  bool _taskCover = false;

  // Analyze / apply state.
  bool _analyzing = false;
  int _progressDone = 0;
  int _progressTotal = 0;
  List<_FixProposal> _proposals = [];
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _fixer = AiFixer();
    _single = _defaultSingle();
  }

  /// All tracks this screen can work on: local + drive only.
  List<Track> get _eligible =>
      [...widget.pc.localTracks, ...widget.pc.driveTracks];

  Track? _defaultSingle() {
    final cur = widget.pc.currentTrack;
    if (cur != null && (cur.isLocalTrack || cur.isDriveTrack)) return cur;
    return _eligible.isNotEmpty ? _eligible.first : null;
  }

  List<Track> _selectedTracks() {
    if (_mode == 0) {
      return _single == null ? const [] : [_single!];
    }
    return _eligible.where((t) => _batchIds.contains(t.id)).toList();
  }

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _sibling(String path, String newName) {
    final i = path.lastIndexOf('/');
    return i < 0 ? newName : '${path.substring(0, i + 1)}$newName';
  }

  static String _errorText(Object e) =>
      e is AiFixerException ? e.message : 'Failed: ${e.toString()}';

  bool get _canAnalyze =>
      !_analyzing &&
      (_taskFilenames || _taskMetadata || _taskLyrics || _taskCover) &&
      _selectedTracks().isNotEmpty;

  Future<void> _analyze() async {
    if (!await _fixer.hasKey()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Save an API key in the AI provider card first.')));
      return;
    }
    final tracks = _selectedTracks();
    final doFilenames = _taskFilenames;
    final doMetadata = _taskMetadata;
    final doLyrics = _taskLyrics;
    final doCover = _taskCover;
    setState(() {
      _analyzing = true;
      _progressDone = 0;
      _progressTotal = tracks.length;
      _proposals = tracks.map(_FixProposal.new).toList();
    });

    for (var i = 0; i < _proposals.length; i++) {
      final p = _proposals[i];
      try {
        if (doFilenames) {
          if (p.track.isLocalTrack && p.track.localPath != null) {
            final name = _basename(p.track.localPath!);
            final fix = await _fixer.fixFilename(name);
            final cleaned = fix['filename'];
            if (cleaned != null && cleaned != name) {
              p.newFilename = cleaned;
            }
          } else if (p.track.isDriveTrack) {
            // Drive files live on Google's servers; the app only holds
            // stream URLs, so there is nothing on-device to rename.
            p.driveRenameSkipped = true;
          }
        }
        if (doMetadata) {
          final fix = await _fixer.fixMetadata(
              title: p.track.title, artist: p.track.artist);
          final t = fix['title'];
          final a = fix['artist'];
          if (t != null && t != p.track.title) p.newTitle = t;
          if (a != null && a != p.track.artist) p.newArtist = a;
        }
        final effArtist = p.newArtist ?? p.track.artist;
        final effTitle = p.newTitle ?? p.track.title;
        if (doLyrics) {
          final res = await widget.pc.fetchLyricsOverride(
            p.track,
            effArtist,
            effTitle,
          );
          p.lyricsFound = res.found;
          if (res.found) {
            // Also cache under the player-sheet identity so the lyrics
            // show up in the player without another lookup.
            await widget.pc.lyricsCache
                .put(widget.pc.lyricsIdentity(p.track), res);
          }
        }
        if (doCover) {
          final url = await CoverArt.findArtworkUrl(
            artist: effArtist,
            title: effTitle,
          );
          if (url != null) {
            final dir = await CoverArt.artworkDir();
            final dest = '${dir.path}/${CoverArt.fileNameForId(p.track.id)}';
            if (await CoverArt.download(url, dest)) {
              p.coverPath = dest;
              p.coverFound = true;
            } else {
              p.coverFound = false;
            }
          } else {
            p.coverFound = false;
          }
        }
        // Nothing proposed and no lyrics/cover result → deselect.
        if (!p.hasChanges && p.lyricsFound != true && p.coverFound != true) {
          p.include = false;
        }
      } catch (e) {
        p.error = _errorText(e);
        p.include = false;
      }
      if (!mounted) return;
      setState(() => _progressDone = i + 1);
    }
    if (mounted) setState(() => _analyzing = false);
  }

  bool get _canApply =>
      !_applying &&
      !_analyzing &&
      _proposals.any((p) => p.include && p.error == null);

  Future<void> _apply() async {
    setState(() => _applying = true);
    var renamed = 0;
    var metadata = 0;
    var lyricsOk = 0;
    var covers = 0;
    for (final p in _proposals) {
      if (!p.include || p.error != null) continue;
      try {
        final t = p.newTitle;
        final a = p.newArtist;
        if (p.newFilename != null &&
            p.track.isLocalTrack &&
            p.track.localPath != null) {
          final oldPath = p.track.localPath!;
          final newPath = _sibling(oldPath, p.newFilename!);
          if (await File(newPath).exists()) {
            throw 'A file named "${p.newFilename}" already exists.';
          }
          await File(oldPath).rename(newPath);
          // One call updates both the renamed path and any metadata fix.
          await widget.pc.updateLocalTrack(p.track,
              localPath: newPath, title: t, artist: a);
          renamed++;
          if (t != null || a != null) metadata++;
        } else if (t != null || a != null) {
          if (p.track.isDriveTrack) {
            await widget.pc.updateDriveTrack(
                p.track, t ?? p.track.title, a ?? p.track.artist);
          } else if (p.track.isLocalTrack) {
            await widget.pc.updateLocalTrack(p.track, title: t, artist: a);
          }
          metadata++;
        }
        if (p.lyricsFound == true) lyricsOk++;
        if (p.coverPath != null && File(p.coverPath!).existsSync()) {
          await _attachArtwork(p);
          covers++;
        }
        p.include = false; // applied
      } catch (e) {
        p.error = e is String ? e : _errorText(e);
      }
      if (!mounted) return;
      setState(() {});
    }
    if (!mounted) return;
    setState(() => _applying = false);
    final bits = <String>[];
    if (renamed > 0) bits.add('$renamed renamed');
    if (metadata > 0) bits.add('$metadata metadata fixed');
    if (lyricsOk > 0) bits.add('lyrics found for $lyricsOk');
    if (covers > 0) bits.add('cover art attached to $covers');
    final summary =
        bits.isEmpty ? 'Nothing applied.' : 'Done: ${bits.join(', ')}.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(summary)));
  }

  /// Attaches the downloaded cover image to the track using only the
  /// controller's public API (this screen may not edit the controller).
  ///
  /// WORKAROUND, documented for the parent: PlayerController has no
  /// artworkUrl parameter on updateLocalTrack/updateDriveTrack, so this
  /// swaps the track list entry for one carrying the new artworkUrl and
  /// then calls the existing update method — which rebuilds the track
  /// from the swapped entry (preserving artworkUrl) and persists it.
  /// The recommended permanent fix is to add `{String? artworkUrl}` to
  /// both update methods (and to Track.copyWith in models/track.dart);
  /// then this can pass the path directly instead of swapping.
  ///
  /// NOTE: the artwork widgets (TrackArt, VinylRecord) currently render
  /// via Image.network, so a local file path only displays after they
  /// learn to use FileImage for paths starting with '/'.
  Future<void> _attachArtwork(_FixProposal p) async {
    final path = p.coverPath!;
    final pc = widget.pc;
    if (p.track.isLocalTrack) {
      await pc.updateLocalTrack(p.track, artworkUrl: path);
    } else if (p.track.isDriveTrack) {
      await pc.updateDriveTrack(
          p.track, p.track.title, p.track.artist,
          artworkUrl: path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pc,
      builder: (_, __) {
        // Keep the single-track pick valid if the library changed.
        final eligible = _eligible;
        if (_mode == 0 &&
            (_single == null || !eligible.any((t) => t.id == _single!.id))) {
          _single = _defaultSingle();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('AI Fixer (BETA)')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildExplainer(),
              const SizedBox(height: 12),
              const AiProviderCard(),
              const SizedBox(height: 12),
              _buildSourceCard(eligible),
              const SizedBox(height: 12),
              _buildTasksCard(),
              const SizedBox(height: 16),
              _buildAnalyzeButton(),
              if (_analyzing) _buildProgress(),
              if (_proposals.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildPreviewHeader(),
                const SizedBox(height: 8),
                ..._proposals.map(_buildProposalCard),
                const SizedBox(height: 16),
                _buildApplyButton(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExplainer() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Uses your own AI provider key, called directly from your '
          'phone — pick Gemini, OpenRouter, or a custom OpenAI-compatible '
          'endpoint below. Cover art comes from the iTunes Search API '
          'and MusicBrainz (no scraping). AI suggestions are previewed '
          'first — nothing changes until you tap "Apply selected".',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
        ),
      ),
    );
  }

  Widget _buildSourceCard(List<Track> eligible) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tracks',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Single track')),
                ButtonSegment(value: 1, label: Text('Batch')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            if (_mode == 0)
              _buildSingleDropdown(eligible)
            else
              _buildBatchList(eligible),
          ],
        ),
      ),
    );
  }

  String _trackLabel(Track t) =>
      '${t.title} — ${t.artist} (${t.isLocalTrack ? 'phone' : 'Drive'})';

  Widget _buildSingleDropdown(List<Track> eligible) {
    if (eligible.isEmpty) {
      return const Text('No local or Drive tracks yet. Import some first.');
    }
    return DropdownButtonFormField<Track>(
      initialValue: _single != null && eligible.any((t) => t.id == _single!.id)
          ? eligible.firstWhere((t) => t.id == _single!.id)
          : null,
      items: eligible
          .map((t) => DropdownMenuItem(
              value: t,
              child: Text(_trackLabel(t), overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (t) => setState(() => _single = t),
      decoration:
          const InputDecoration(border: OutlineInputBorder(), isDense: true),
      isExpanded: true,
    );
  }

  Widget _buildBatchList(List<Track> eligible) {
    final scheme = Theme.of(context).colorScheme;
    if (eligible.isEmpty) {
      return const Text('No local or Drive tracks yet. Import some first.');
    }
    return Column(
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _batchIds.addAll(eligible.map((t) => t.id))),
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () => setState(() => _batchIds.clear()),
              child: const Text('None'),
            ),
            const Spacer(),
            Text('${_batchIds.length}/${eligible.length} selected',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
        ...eligible.map(
          (t) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(t.title, overflow: TextOverflow.ellipsis),
            subtitle:
                Text('${t.isLocalTrack ? 'phone' : 'Drive'} · ${t.artist}'),
            value: _batchIds.contains(t.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _batchIds.add(t.id);
              } else {
                _batchIds.remove(t.id);
              }
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTasksCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tasks',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Clean filenames'),
              subtitle: const Text(
                  'Local tracks only — renames the actual file on your phone.'),
              value: _taskFilenames,
              onChanged: (v) => setState(() => _taskFilenames = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Fix metadata'),
              subtitle:
                  const Text('Cleans up title and artist for local + Drive.'),
              value: _taskMetadata,
              onChanged: (v) => setState(() => _taskMetadata = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Find lyrics'),
              subtitle: const Text(
                  'Re-checks lyrics with the corrected metadata (local + Drive).'),
              value: _taskLyrics,
              onChanged: (v) => setState(() => _taskLyrics = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Fetch cover art'),
              subtitle: const Text(
                  'iTunes, then MusicBrainz — saved on-device (local + Drive).'),
              value: _taskCover,
              onChanged: (v) => setState(() => _taskCover = v ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _canAnalyze ? _analyze : null,
          child: Text(_analyzing ? 'Analyzing…' : 'Analyze'),
        ),
        if (_selectedTracks().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Pick at least one track above.',
              style: TextStyle(color: scheme.tertiary, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _buildProgress() {
    final scheme = Theme.of(context).colorScheme;
    final total = _progressTotal == 0 ? 1 : _progressTotal;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: _progressDone / total),
          const SizedBox(height: 6),
          Text('$_progressDone/$_progressTotal…',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildPreviewHeader() {
    final count = _proposals.where((p) => p.hasChanges).length;
    return Text(
      'Proposed changes ($count of ${_proposals.length} tracks)',
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    );
  }

  Widget _buildProposalCard(_FixProposal p) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(p.track.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.track.artist,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
            const SizedBox(height: 6),
            if (p.newFilename != null)
              _changeRow('Filename', _basename(p.track.localPath ?? ''),
                  p.newFilename!),
            if (p.driveRenameSkipped)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Filename: Drive files can’t be renamed on-device.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              ),
            if (p.newTitle != null)
              _changeRow('Title', p.track.title, p.newTitle!),
            if (p.newArtist != null)
              _changeRow('Artist', p.track.artist, p.newArtist!),
            if (p.coverPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(p.coverPath!),
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Cover art → saved on-device',
                          style: TextStyle(
                              color: scheme.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            if (!p.hasChanges && p.error == null)
              Text(
                'No changes suggested.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (p.lyricsFound != null)
                  Chip(
                    label: Text(p.lyricsFound! ? 'Lyrics found' : 'No lyrics',
                        style: const TextStyle(fontSize: 11.5)),
                    backgroundColor: p.lyricsFound!
                        ? scheme.primary.withValues(alpha: 0.25)
                        : Colors.grey.withValues(alpha: 0.25),
                    visualDensity: VisualDensity.compact,
                  ),
                if (p.coverFound != null && p.coverPath == null)
                  Chip(
                    label: const Text('No cover found',
                        style: TextStyle(fontSize: 11.5)),
                    backgroundColor: Colors.grey.withValues(alpha: 0.25),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (p.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(p.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ),
          ],
        ),
        value: p.include,
        onChanged: p.error == null
            ? (v) => setState(() => p.include = v ?? false)
            : null,
      ),
    );
  }

  Widget _changeRow(String field, String oldV, String newV) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          children: [
            TextSpan(
                text: '$field: ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(
                text: oldV,
                style: const TextStyle(decoration: TextDecoration.lineThrough)),
            const TextSpan(text: '  →  '),
            TextSpan(
                text: newV,
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyButton() {
    return ElevatedButton(
      onPressed: _canApply ? _apply : null,
      child: Text(_applying ? 'Applying…' : 'Apply selected'),
    );
  }
}
