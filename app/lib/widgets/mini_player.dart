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
/// Gestures:
/// - tap / swipe up → Now Playing, via a smooth slide-up/fade/scale
///   route transition (no abrupt cut);
/// - horizontal drag → **peek**: the card follows the finger with
///   rubber-band resistance while the previous/next track slides in from
///   the drag side; release without fling velocity springs back, a fling
///   commits the track change with a settle animation;
/// - deliberate swipe down (fast fling AND real distance) → stop playback
///   entirely and dismiss the player.
class MiniPlayer extends StatefulWidget {
  final PlayerController pc;

  /// Explicit track to render. When set (e.g. by the shell's exit
  /// animation after the queue was cleared), the card keeps showing this
  /// track even though [PlayerController.currentTrack] is already null —
  /// but all interactions are disabled then.
  final Track? displayTrack;

  const MiniPlayer({super.key, required this.pc, this.displayTrack});

  /// Peek physics constants (shared with [_MiniPlayerState]).
  static const double peekFullReveal = 120; // px of drag for full reveal
  static const double peekMaxDx = 150; // hard clamp after rubber-banding
  static const double commitFlingVelocity = 600; // px/s to commit a peek

  /// Rubber-banded horizontal displacement: linear-ish for small drags,
  /// progressively resisting past [peekFullReveal], hard-clamped at
  /// [peekMaxDx]. Pure function — unit-tested directly.
  @visibleForTesting
  static double rubberBand(double raw) {
    final sign = raw.sign;
    final a = raw.abs();
    double out;
    if (a <= peekFullReveal) {
      out = a * 0.62;
    } else {
      out = peekFullReveal * 0.62 + (a - peekFullReveal) * 0.18;
    }
    return (sign * out).clamp(-peekMaxDx, peekMaxDx);
  }

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

  /// Gesture animation plumbing. [_dragOffset]/[_dragOpacity] track the
  /// finger live; [_offsetTween]/[_opacityTween] animate spring-back,
  /// commit animations and the swipe-down dismiss. [_visualOffset] is
  /// their sum, so a release mid-drag animates from exactly where the
  /// finger left the card.
  late final AnimationController _anim;
  Tween<Offset> _offsetTween = Tween(begin: Offset.zero, end: Offset.zero);
  Tween<double> _opacityTween = Tween(begin: 1.0, end: 1.0);
  Curve _animCurve = Curves.easeOutCubic;
  Offset _dragOffset = Offset.zero;
  double _dragOpacity = 1.0;
  double _dragDy = 0.0; // accumulated vertical drag (stop threshold)

  /// Peek state: which neighbor is being revealed (-1 next, +1 previous,
  /// 0 none) and how far (0..1). Derived from the horizontal drag.
  int _peekDir = 0;
  double _peekT = 0.0;

  /// Set while the dismiss animation runs so the card resets its
  /// transforms when it reappears for the next track.
  bool _dismissed = false;

  /// Deliberate-fling thresholds for swipe-down-to-stop: BOTH must hold,
  /// so an accidental short drag never kills playback.
  static const double _stopFlingVelocity = 500; // px/s, downward
  static const double _stopDragDistance = 48; // px, downward

  /// Peek physics (canonical values live on [MiniPlayer]).
  static const double _peekFullReveal = MiniPlayer.peekFullReveal;
  static const double _commitFlingVelocity = MiniPlayer.commitFlingVelocity;

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

  Offset get _visualOffset =>
      _dragOffset +
      _offsetTween.chain(CurveTween(curve: _animCurve)).evaluate(_anim);
  double get _visualOpacity => (_dragOpacity *
          _opacityTween.chain(CurveTween(curve: _animCurve)).evaluate(_anim))
      .clamp(0.0, 1.0);

  void _resetTransforms() {
    _offsetTween = Tween(begin: Offset.zero, end: Offset.zero);
    _opacityTween = Tween(begin: 1.0, end: 1.0);
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _dragDy = 0.0;
    _peekDir = 0;
    _peekT = 0.0;
    _anim.reset();
  }

  void _animateTo({
    required Offset offset,
    required double opacity,
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    _offsetTween = Tween(begin: _visualOffset, end: offset);
    _opacityTween = Tween(begin: _visualOpacity, end: opacity);
    _animCurve = curve;
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _anim.duration = duration;
    _anim.forward(from: 0);
  }

  void _springBack() {
    _peekDir = 0;
    _peekT = 0.0;
    _animateTo(
      offset: Offset.zero,
      opacity: 1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.elasticOut,
    );
  }


  /// Swipe-down: slide the card off the bottom and fade it, then stop
  /// playback entirely (not pause) and clear the queue. The background
  /// service deactivates the media session, clearing the notification;
  /// currentTrack → null hides the mini player.
  Future<void> _dismissAndStop() async {
    _dismissed = true;
    _peekDir = 0;
    _peekT = 0.0;
    _animateTo(
        offset: const Offset(0, 170),
        opacity: 0.0,
        duration: const Duration(milliseconds: 220));
    await Future.delayed(const Duration(milliseconds: 190));
    await pc.stopAndClear();
    if (mounted) _resetTransforms();
  }

  /// Smooth expand transition into the full player: the route slides up
  /// from the bottom with fade + subtle scale, eased — the mini player
  /// feels like it grows into Now Playing instead of cutting to it.
  void _open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => PlayerScreen(pc: pc),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Commit a peeked track change: settle the peek card to center while
  /// the old card exits, swap the track, then reset transforms invisibly
  /// (the settled peek card and the fresh current card render the same
  /// track, so the reset is seamless).
  Future<void> _commitPeek(int dir, double cardWidth) async {
    final target = dir < 0 ? pc.peekNextTrack : pc.peekPreviousTrack;
    if (target == null) {
      _springBack();
      return;
    }
    // Settle: old card exits in the fling direction, peek card centers.
    _animateTo(
      offset: Offset(dir < 0 ? -cardWidth : cardWidth, 0),
      opacity: 0.35,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
    );
    await Future.delayed(const Duration(milliseconds: 170));
    if (dir < 0) {
      await pc.next();
    } else {
      await pc.previous();
    }
    if (mounted) _resetTransforms();
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
        final scheme = Theme.of(context).colorScheme;
        final pos = pc.position.inMilliseconds.toDouble();
        final dur = pc.duration?.inMilliseconds.toDouble() ?? 0;
        final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

        final peekTrack =
            _peekDir < 0 ? pc.peekNextTrack : pc.peekPreviousTrack;

        return LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth;
            return GestureDetector(
              onTap: live ? () => _open(context) : null,
              // Vertical: swipe up opens Now Playing (smooth expand);
              // a deliberate swipe down (fast fling AND real distance)
              // stops everything. The card follows the finger so the
              // dismiss feels physical.
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
              // Horizontal peek: drag reveals the neighbor track sliding
              // in from the drag side with rubber-band resistance; fling
              // commits the change, otherwise it springs back.
              onHorizontalDragUpdate: live
                  ? (d) {
                      final rawDx = _dragOffset.dx + d.delta.dx;
                      final dx = MiniPlayer.rubberBand(rawDx);
                      final dir = dx == 0 ? 0 : (dx < 0 ? -1 : 1);
                      final neighbor = dir < 0
                          ? pc.peekNextTrack
                          : pc.peekPreviousTrack;
                      setState(() {
                        _dragOffset = Offset(dx, _dragOffset.dy);
                        // No neighbor: extra resistance, never reveal.
                        if (neighbor == null) {
                          _peekDir = 0;
                          _peekT = 0.0;
                          _dragOffset = Offset(dx * 0.45, _dragOffset.dy);
                        } else {
                          _peekDir = dir;
                          _peekT = (dx.abs() / (_peekFullReveal * 0.62))
                              .clamp(0.0, 1.0);
                        }
                      });
                    }
                  : null,
              onHorizontalDragEnd: live
                  ? (d) {
                      final v = d.primaryVelocity ?? 0;
                      final dir = _peekDir;
                      if (dir != 0 && v < -_commitFlingVelocity && dir < 0) {
                        _commitPeek(-1, cardWidth);
                      } else if (dir != 0 &&
                          v > _commitFlingVelocity &&
                          dir > 0) {
                        _commitPeek(1, cardWidth);
                      } else {
                        _springBack();
                      }
                    }
                  : null,
              onHorizontalDragCancel: live ? _springBack : null,
              child: SizedBox(
                height: 78,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Peek layer: the neighbor track slides in from the
                    // drag side as the finger moves.
                    if (_peekDir != 0 && peekTrack != null)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Transform.translate(
                            offset: Offset(
                              // Starts off-screen on the drag side, settles
                              // toward center as the peek progresses.
                              _peekDir *
                                      cardWidth *
                                      (1.0 -
                                          Curves.easeOutCubic
                                              .transform(_peekT)) +
                                  _dragOffset.dx * 0.25,
                              0,
                            ),
                            child: Opacity(
                              opacity:
                                  Curves.easeOutCubic.transform(_peekT),
                              child: _PeekCard(
                                track: peekTrack,
                                tint: tint,
                                onTint: onTint,
                                direction: _peekDir,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Current card.
                    Transform.translate(
                      offset: _visualOffset,
                      child: Opacity(
                        opacity: _visualOpacity,
                        child: _MiniCard(
                          track: track,
                          tint: tint,
                          onTint: onTint,
                          scheme: scheme,
                          progress: progress,
                          live: live,
                          pc: pc,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The neighbor-track preview revealed during a peek drag.
class _PeekCard extends StatelessWidget {
  final Track track;
  final Color tint;
  final Color onTint;
  final int direction; // -1: next (from right), +1: previous (from left)

  const _PeekCard({
    required this.track,
    required this.tint,
    required this.onTint,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: onTint.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(9),
            child: TrackArt(track, size: 56, circular: true),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  direction < 0 ? 'Next' : 'Previous',
                  style: TextStyle(
                    color: onTint.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                MarqueeText(
                  key: ValueKey('peek-title::${track.id}'),
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
                      color: onTint.withValues(alpha: 0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            direction < 0 ? Icons.skip_next : Icons.skip_previous,
            color: onTint.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// The main mini-player card (extracted so the peek layer can sit under it).
class _MiniCard extends StatelessWidget {
  final Track track;
  final Color tint;
  final Color onTint;
  final ColorScheme scheme;
  final double progress;
  final bool live;
  final PlayerController pc;

  const _MiniCard({
    required this.track,
    required this.tint,
    required this.onTint,
    required this.scheme,
    required this.progress,
    required this.live,
    required this.pc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  child: TrackArt(track, size: 56, circular: true),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        key: ValueKey('mini-title::${track.id}'),
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
                    icon: pc.isPlaying ? Icons.pause : Icons.play_arrow,
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
              backgroundColor: onTint.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
