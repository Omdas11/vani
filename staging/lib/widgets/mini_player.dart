import 'package:flutter/material.dart';
import '../models/track.dart';
import '../screens/player_screen.dart';
import '../services/artwork_colors.dart';
import '../services/player_controller.dart';
import '../services/vani_theme.dart';
import 'expressive.dart';
import 'track_art.dart';

/// Floating mini-player as a dynamic tonal card (PixelPlayer pattern):
/// a detached ~28dp card docked above the nav dock whose container color
/// is re-tinted from the current album art. Circular artwork, marquee
/// title/artist, circular tonal play + skip buttons, and a thin progress
/// line along the bottom edge.
///
/// Gestures: tap / swipe up → Now Playing; swipe left → next track;
/// swipe right → previous track; deliberate swipe down (fling distance)
/// → stop playback entirely and dismiss the player.
class MiniPlayer extends StatefulWidget {
  final PlayerController pc;

  /// Explicit track to render. When set (e.g. by the shell's exit
  /// animation after the queue was cleared), the card keeps showing this
  /// track even though [PlayerController.currentTrack] is already null —
  /// but all interactions are disabled then.
  final Track? displayTrack;

  const MiniPlayer({super.key, required this.pc, this.displayTrack});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with TickerProviderStateMixin {
  /// Memoized per artwork URL: rebuilding on every position tick must
  /// NOT restart the tint future (it would flicker through the
  /// fallback color each second).
  Future<Color>? _tintFuture;
  String _tintUrl = '';

  /// Gesture animation plumbing: [_dragOffset]/[_dragOpacity] track the
  /// finger live; [_offsetTween]/[_opacityTween] animate spring-back,
  /// swipe nudges and the swipe-down dismiss. [_visualOffset] is their
  /// sum, so a release mid-drag animates from exactly where the finger
  /// left the card.
  late final AnimationController _anim;
  Tween<Offset> _offsetTween =
      Tween(begin: Offset.zero, end: Offset.zero);
  Tween<double> _opacityTween =
      Tween(begin: 1.0, end: 1.0);
  Offset _dragOffset = Offset.zero;
  double _dragOpacity = 1.0;
  double _dragDy = 0.0; // accumulated vertical drag (stop threshold)

  /// Set while the dismiss animation runs so the card resets its
  /// transforms when it reappears for the next track.
  bool _dismissed = false;

  /// Deliberate-fling thresholds for swipe-down-to-stop: BOTH must hold,
  /// so an accidental short drag never kills playback.
  static const double _stopFlingVelocity = 500; // px/s, downward
  static const double _stopDragDistance = 48; // px, downward

  PlayerController get pc => widget.pc;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _anim.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Offset get _visualOffset => _dragOffset + _offsetTween.evaluate(_anim);
  double get _visualOpacity =>
      (_dragOpacity * _opacityTween.evaluate(_anim)).clamp(0.0, 1.0);

  void _resetTransforms() {
    _offsetTween = Tween(begin: Offset.zero, end: Offset.zero);
    _opacityTween = Tween(begin: 1.0, end: 1.0);
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _dragDy = 0.0;
    _anim.reset();
  }

  void _animateTo(
      {required Offset offset,
      required double opacity,
      Duration duration = const Duration(milliseconds: 200)}) {
    _offsetTween = Tween(begin: _visualOffset, end: offset);
    _opacityTween = Tween(begin: _visualOpacity, end: opacity);
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _anim.duration = duration;
    _anim.forward(from: 0);
  }

  void _springBack() => _animateTo(offset: Offset.zero, opacity: 1.0);

  /// Quick kick in the fling direction, then spring back — the tactile
  /// answer to a swipe track-change.
  void _nudge(Offset direction) {
    _dragOffset = direction;
    _springBack();
  }

  /// Swipe-down: slide the card off the bottom and fade it, then stop
  /// playback entirely (not pause) and clear the queue. The background
  /// service deactivates the media session, clearing the notification;
  /// currentTrack → null hides the mini player.
  Future<void> _dismissAndStop() async {
    _dismissed = true;
    _animateTo(
        offset: const Offset(0, 170),
        opacity: 0.0,
        duration: const Duration(milliseconds: 220));
    await Future.delayed(const Duration(milliseconds: 190));
    await pc.stopAndClear();
    if (mounted) _resetTransforms();
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(pc: pc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.displayTrack ?? pc.currentTrack;
    if (track == null) return const SizedBox.shrink();
    // Interactions only make sense while the track is actually loaded.
    // During the shell's exit animation displayTrack holds a stale track
    // with an empty queue: the card is visible but inert.
    final live = pc.currentTrack != null;
    // After a swipe-down dismiss the state object survives (same widget
    // slot); reset the dismiss transforms for the next appearance.
    if (_dismissed) {
      _dismissed = false;
      _resetTransforms();
    }
    final scheme = Theme.of(context).colorScheme;
    if (track.artworkUrl != _tintUrl) {
      _tintUrl = track.artworkUrl;
      _tintFuture = ArtworkColors.dominant(_tintUrl);
    }

    return FutureBuilder<Color>(
      future: _tintFuture,
      builder: (_, snap) {
        // Dynamic tint: the mini-player repaints itself in the current
        // artwork's tonal palette — the core anti-monochrome mechanism.
        final art = snap.data ?? ArtworkColors.fallback;
        final artScheme = VaniTheme.schemeForArtwork(art);
        final tint = artScheme.secondaryContainer;
        final onTint = artScheme.onSecondaryContainer;
        final pos = pc.position.inMilliseconds.toDouble();
        final dur = pc.duration?.inMilliseconds.toDouble() ?? 0;
        final progress =
            dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

        return GestureDetector(
          onTap: live ? () => _open(context) : null,
          // Vertical: swipe up opens Now Playing; a deliberate swipe
          // down (fast fling AND real distance) stops everything.
          // The card follows the finger so the dismiss feels physical.
          onVerticalDragUpdate: live
              ? (d) {
                  _dragDy += d.delta.dy;
                  final dy =
                      (_dragOffset.dy + d.delta.dy).clamp(-72.0, 150.0);
                  setState(() {
                    _dragOffset = Offset(_dragOffset.dx, dy);
                    _dragOpacity =
                        1.0 - (dy.clamp(0.0, 150.0) / 150.0) * 0.45;
                  });
                }
              : null,
          onVerticalDragEnd: live
              ? (d) {
                  final v = d.primaryVelocity ?? 0;
                  final dy = _dragDy;
                  _dragDy = 0.0;
                  if (v < -350) {
                    _springBack();
                    _open(context);
                  } else if (v > _stopFlingVelocity &&
                      dy > _stopDragDistance) {
                    _dismissAndStop();
                  } else {
                    _springBack();
                  }
                }
              : null,
          onVerticalDragCancel: live
              ? () {
                  _dragDy = 0.0;
                  _springBack();
                }
              : null,
          // Horizontal: fling left → next, fling right → previous,
          // with a tactile nudge in the fling direction.
          onHorizontalDragUpdate: live
              ? (d) {
                  final dx =
                      (_dragOffset.dx + d.delta.dx).clamp(-72.0, 72.0);
                  setState(
                      () => _dragOffset = Offset(dx, _dragOffset.dy));
                }
              : null,
          onHorizontalDragEnd: live
              ? (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -600) {
                    _nudge(const Offset(-36, 0));
                    pc.next();
                  } else if (v > 600) {
                    _nudge(const Offset(36, 0));
                    pc.previous();
                  } else {
                    _springBack();
                  }
                }
              : null,
          onHorizontalDragCancel: live ? _springBack : null,
          child: Transform.translate(
            offset: _visualOffset,
            child: Opacity(
              opacity: _visualOpacity,
              child: Container(
            height: 78,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(9),
                        child: TrackArt(track,
                            size: 56, circular: true),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            MarqueeText(
                              key: ValueKey(
                                  'mini-title::${track.id}'),
                              text: track.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: onTint,
                                  fontSize: 14),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: onTint.withValues(alpha: 0.75),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // Prev/play/next: the full transport set lives here as
                      // well as on the Now Playing screen (v1.6.2
                      // regression guard).
                      TonalIconButton(
                        icon: Icons.skip_previous,
                        iconSize: 24,
                        size: 46,
                        backgroundColor: onTint.withValues(alpha: 0.16),
                        foregroundColor: onTint,
                        tooltip: 'Previous',
                        onPressed: live ? pc.previous : null,
                      ),
                      const SizedBox(width: 4),
                      // Spinner only while genuinely loading (never while
                      // audio is playing — see the controller invariant).
                      if (pc.isLoading && !pc.isPlaying)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: onTint),
                          ),
                        )
                      else
                        TonalIconButton(
                          icon: pc.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          iconSize: 26,
                          size: 46,
                          backgroundColor: onTint.withValues(alpha: 0.16),
                          foregroundColor: onTint,
                          tooltip: pc.isPlaying ? 'Pause' : 'Play',
                          onPressed: live ? pc.togglePlayPause : null,
                        ),
                      const SizedBox(width: 4),
                      TonalIconButton(
                        icon: Icons.skip_next,
                        iconSize: 24,
                        size: 46,
                        backgroundColor: onTint.withValues(alpha: 0.16),
                        foregroundColor: onTint,
                        tooltip: 'Next',
                        onPressed: live ? pc.next : null,
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
                // Thin progress line along the card's bottom edge.
                SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor:
                        onTint.withValues(alpha: 0.15),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
              ],
            ),
              ),
            ),
          ),
        );
      },
    );
  }
}
