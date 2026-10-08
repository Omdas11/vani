import 'dart:async';

import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import 'track_art.dart';

/// Circular tonal icon button (PixelPlayer top-bar / transport pattern).
class TonalIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const TonalIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconSize = 22,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.secondaryContainer;
    final fg = foregroundColor ?? scheme.onSecondaryContainer;
    final btn = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );
    return tooltip == null
        ? btn
        : Tooltip(message: tooltip, child: btn);
  }
}

/// Oversized display-scale screen header (PixelPlayer "Your Mix" pattern):
/// big rounded-sans title + small subtitle, with tonal circular utility
/// buttons on the right instead of a dense app bar.
class DisplayHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const DisplayHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Respect the status bar / notch: without this the header underlaps
    // the system padding on phones with a notch (bug report v1.6.0).
    final topInset = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16 + topInset, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    )),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          ...actions.map((a) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: a,
              )),
        ],
      ),
    );
  }
}

/// List header pattern (PixelPlayer Library): a tonal "Shuffle" pill on
/// the left, a circular sort/filter icon button on the right.
class SongListHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onShuffle;
  final VoidCallback? onSort;
  final String? sortTooltip;

  const SongListHeader({
    super.key,
    required this.title,
    required this.count,
    required this.onShuffle,
    this.onSort,
    this.sortTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('$count track${count == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: count == 0 ? null : onShuffle,
            icon: const Icon(Icons.shuffle, size: 18),
            label: const Text('Shuffle'),
          ),
          if (onSort != null) ...[
            const SizedBox(width: 8),
            TonalIconButton(
              icon: Icons.sort,
              tooltip: sortTooltip ?? 'Sort',
              onPressed: onSort,
              size: 44,
            ),
          ],
        ],
      ),
    );
  }
}

/// Scrolls (rather than truncates) long single-line titles.
/// Seamless wrap loop: the text is duplicated with a gap and scrolls
/// forward continuously, wrapping back to offset 0 — so the title
/// ALWAYS begins at its first character at every loop restart, and the
/// full text is shown in every cycle. Falls back to ellipsis when the
/// text fits.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration pause;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.pause = const Duration(milliseconds: 1500),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _ctrl = ScrollController();

  /// Gap between the two copies in the seamless loop.
  static const _gap = 48.0;

  /// Pixels per second of the scroll, for a constant reading speed.
  static const _pxPerSec = 60.0;

  bool _overflows = false;

  /// Width of one text copy + gap: the loop scrolls exactly this far
  /// then wraps to 0 (visually seamless because the content repeats).
  double _loopWidth = 0;

  /// Single-shot loop timer, cancelled in dispose so no Timer outlives
  /// the widget (flutter_test fails on pending timers).
  Timer? _timer;
  bool _dead = false;

  @override
  void initState() {
    super.initState();
    // Wait a beat so layout settles, then loop the scroll.
    _arm(const Duration(milliseconds: 800));
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Belt and braces (keys already recreate state per track): a new
    // title must always begin at its first character, never at a stale
    // scroll offset.
    if (oldWidget.text != widget.text) {
      if (_ctrl.hasClients) _ctrl.jumpTo(0);
      _arm(widget.pause);
    }
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  void _tick() {
    if (_dead || !mounted) return;
    if (!_overflows || !_ctrl.hasClients || _loopWidth <= 0) {
      _arm(widget.pause); // not ready yet; re-check later
      return;
    }
    final w = _loopWidth;
    // Constant-speed forward scroll of exactly one copy, then a
    // seamless wrap back to the start (full title visible from char 0).
    _ctrl
        .animateTo(w,
            duration: Duration(
                milliseconds:
                    (w / _pxPerSec * 1000).round().clamp(1200, 12000)),
            curve: Curves.linear)
        .then((_) {
      if (_dead || !mounted) return;
      if (_ctrl.hasClients) _ctrl.jumpTo(0);
      _arm(widget.pause);
    });
  }

  @override
  void dispose() {
    _dead = true;
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);
        final overflows = tp.width > constraints.maxWidth;
        if (overflows != _overflows) {
          // Defer the flag flip past this build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _overflows = overflows);
          });
        }
        if (!overflows) {
          return Text(widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style);
        }
        _loopWidth = tp.width + _gap;
        // Duplicated text: scrolling one copy+gap and wrapping to 0 is
        // invisible, giving an infinite loop of the FULL title.
        return SingleChildScrollView(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              Text(widget.text, maxLines: 1, style: widget.style),
              const SizedBox(width: _gap),
              Text(widget.text, maxLines: 1, style: widget.style),
            ],
          ),
        );
      },
    );
  }
}

/// Rich per-track action sheet (Namida pattern): Play Next / Play Last as
/// prominent split buttons, then icon-led rows for playlist, like and
/// download actions.
Future<void> showTrackActions(
    BuildContext context, PlayerController pc, Track track) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHeader(ctx, pc, track),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      pc.insertIntoQueue(track, playNext: true);
                    },
                    icon: const Icon(Icons.playlist_play),
                    label: const Text('Play next'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      pc.insertIntoQueue(track, playNext: false);
                    },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add to queue'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: pc.isLiked(track)
                  ? Icons.favorite
                  : Icons.favorite_border,
              label: pc.isLiked(track)
                  ? 'Unlike'
                  : 'Like',
              onTap: () {
                Navigator.pop(ctx);
                pc.toggleLike(track);
              },
            ),
            _ActionRow(
              icon: Icons.playlist_add_outlined,
              label: 'Add to playlist',
              onTap: () {
                Navigator.pop(ctx);
                showPlaylistPicker(context, pc, track);
              },
            ),
            if (!track.isDownloaded)
              _ActionRow(
                icon: Icons.download_outlined,
                label: pc.isDownloading(track)
                    ? 'Downloading…'
                    : 'Download for offline',
                onTap: pc.isDownloading(track)
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await pc.downloadTrack(track);
                        if (context.mounted &&
                            pc.error != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                                  content:
                                      Text(pc.error!)));
                        }
                      },
              )
            else
              _ActionRow(
                icon: Icons.delete_outline,
                label: 'Remove download',
                onTap: () {
                  Navigator.pop(ctx);
                  pc.deleteDownload(track);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _sheetHeader(
    BuildContext context, PlayerController pc, Track track) {
  final theme = Theme.of(context);
  return Row(
    children: [
      TrackArt(track,
          size: 56, radius: VaniTheme.radiiOf(context) * 0.7),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      const SizedBox(width: 8),
      TonalIconButton(
        icon: pc.isLiked(track)
            ? Icons.favorite
            : Icons.favorite_border,
        tooltip: pc.isLiked(track) ? 'Unlike' : 'Like',
        backgroundColor: pc.isLiked(track)
            ? theme.colorScheme.primaryContainer
            : null,
        foregroundColor: pc.isLiked(track)
            ? theme.colorScheme.onPrimaryContainer
            : null,
        onPressed: () => pc.toggleLike(track),
      ),
    ],
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ActionRow(
      {required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: TonalIconButton(
        icon: icon,
        onPressed: onTap,
        size: 44,
        iconSize: 20,
      ),
      title: Text(label,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

/// Playlist picker sheet (shared by TrackTile and the action sheet).
Future<void> showPlaylistPicker(
    BuildContext context, PlayerController pc, Track track) {
  final theme = Theme.of(context);
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      final names = pc.playlists.keys.toList();
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('Add to playlist',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: TonalIconButton(
                      icon: Icons.add,
                      onPressed: () {
                        Navigator.pop(ctx);
                        showNewPlaylistDialog(context, (name) async {
                          await pc.createPlaylist(name);
                          if (name.trim().isNotEmpty) {
                            await pc.addToPlaylist(
                                name.trim(), track);
                          }
                        });
                      },
                    ),
                    title: const Text('New playlist'),
                    onTap: () {
                      Navigator.pop(ctx);
                      showNewPlaylistDialog(context, (name) async {
                        await pc.createPlaylist(name);
                        if (name.trim().isNotEmpty) {
                          await pc.addToPlaylist(name.trim(), track);
                        }
                      });
                    },
                  ),
                  ...names.map(
                    (n) => ListTile(
                      leading: const Icon(Icons.playlist_add_outlined),
                      title: Text(n),
                      subtitle: Text(
                          '${pc.playlists[n]?.length ?? 0} tracks'),
                      onTap: () async {
                        await pc.addToPlaylist(n, track);
                        if (context.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Expressive new-playlist dialog.
Future<void> showNewPlaylistDialog(BuildContext context,
    Future<void> Function(String) onSave) {
  final ctrl = TextEditingController();
  return showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration:
            const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (_) async {
          await onSave(ctrl.text);
          if (context.mounted) Navigator.pop(context);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await onSave(ctrl.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
