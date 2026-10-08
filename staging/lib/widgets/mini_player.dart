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
/// Gestures (v1.6.9 Spotify-style rework):
/// - tap / swipe up → Now Playing, via a smooth slide-up/fade/scale
///   route transition (no abrupt cut);
/// - horizontal drag → only the track identity block (artwork +
///   title/artist) follows the finger; the card chrome (background,
///   transport buttons, progress line) stays fixed. Release without a
///   fling springs the content back; a fling slides the old content out
///   and the neighbor's content in with a clean content-swap animation;
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

  /// Content-slide physics constants (shared with [_MiniPlayerState]).
  static const double peekFullReveal = 120; // px of drag for full slide
  static const double peekMaxDx = 150; // hard clamp after rubber-banding
  static const double commitFlingVelocity = 600; // px/s to commit a slide

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
  /// finger live for VERTICAL gestures (the whole card follows); the
  /// horizontal content slide has its own controller below so the two
  /// axes never fight. [_offsetTween]/[_opacityTween] animate spring-back,
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

  /// Content-slide state (v1.6.9 Spotify rework): horizontal drags move
  /// ONLY the track identity block (artwork + title/artist) inside the
  /// fixed card chrome. [_contentDragDx] tracks the finger live;
  /// [_contentTween]/[_contentOpacityTween] drive the spring-back and the
  /// two-phase commit animation on [_contentAnim]. [_shownTrack] is the
  /// track rendered in the identity block — it lags [pc.currentTrack]
  /// by half a commit animation so the swap looks seamless.
  late final AnimationController _contentAnim;
  Tween<double> _contentTween = Tween(begin: 0.0, end: 0.0);
  Tween<double> _contentOpacityTween = Tween(begin: 1.0, end: 1.0);
  double _contentDragDx = 0.0;
  double _contentDragOpacity = 1.0;
  Track? _shownTrack;
  bool _committing = false;

  /// Set while the dismiss animation runs so the card resets its
  /// transforms when it reappears for the next track.
  bool _dismissed = false;

  /// Deliberate-fling thresholds for swipe-down-to-stop: BOTH must hold,
  /// so an accidental short drag never kills playback.
  static const double _stopFlingVelocity = 500; // px/s, downward
  static const double _stopDragDistance = 48; // px, downward

  /// Content-slide physics (canonical values live on [MiniPlayer]).
  static const double _commitFlingVelocity = MiniPlayer.commitFlingVelocity;

  PlayerController get pc => widget.pc;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _anim.addListener(() {
      if (mounted) setState(() {});
    });
    _contentAnim = AnimationController(vsync: this);
    _contentAnim.addListener(() {
      if (mounted) setState(() {});
    });
    _shownTrack = pc.currentTrack;
    pc.addListener(_syncShownTrack);
  }

  /// Keeps the identity block in sync when the track changes outside a
  /// content-slide commit (natural track end, queue jump, etc.): the
  /// content just swaps, no slide animation.
  void _syncShownTrack() {
    if (_committing || !mounted) return;
    final cur = pc.currentTrack;
    if (cur?.id != _shownTrack?.id) {
      setState(() => _shownTrack = cur);
    }
  }

  @override
  void dispose() {
    pc.removeListener(_syncShownTrack);
    _anim.dispose();
    _contentAnim.dispose();
    super.dispose();
  }

  Offset get _visualOffset =>
      _dragOffset +
      _offsetTween.chain(CurveTween(curve: _animCurve)).evaluate(_anim);
  double get _visualOpacity => (_dragOpacity *
          _opacityTween.chain(CurveTween(curve: _animCurve)).evaluate(_anim))
      .clamp(0.0, 1.0);

  /// Live content offset: finger position plus the commit/spring
  /// animation. Pure getter so release mid-drag animates from exactly
  /// where the finger left the content.
  double get _contentVisualDx =>
      _contentDragDx + _contentTween.evaluate(_contentAnim);
  double get _contentVisualOpacity => (_contentDragOpacity *
          _contentOpacityTween.evaluate(_contentAnim))
      .clamp(0.0, 1.0);

  void _resetTransforms() {
    _offsetTween = Tween(begin: Offset.zero, end: Offset.zero);
    _opacityTween = Tween(begin: 1.0, end: 1.0);
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _dragDy = 0.0;
    _anim.reset();
    _resetContentTransforms();
  }

  void _resetContentTransforms() {
    _contentTween = Tween(begin: 0.0, end: 0.0);
    _contentOpacityTween = Tween(begin: 1.0, end: 1.0);
    _contentDragDx = 0.0;
    _contentDragOpacity = 1.0;
    _contentAnim.reset();
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

  /// Whole-card spring-back (vertical gestures only — horizontal drags
  /// move just the content block, never the card).
  void _springBack() {
    _animateTo(
      offset: Offset.zero,
      opacity: 1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.elasticOut,
    );
  }

  /// Content spring-back: release without a fling returns the identity
  /// block to center with a soft elastic settle.
  void _springContentBack() {
    _contentTween =
        Tween(begin: _contentVisualDx, end: 0.0);
    _contentOpacityTween =
        Tween(begin: _contentVisualOpacity, end: 1.0);
    _contentDragDx = 0.0;
    _contentDragOpacity = 1.0;
    _contentAnim.duration = const Duration(milliseconds: 280);
    _contentAnim.forward(from: 0);
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

  /// Commit a content slide: the old identity block exits in the fling
  /// direction while fading, the track actually changes at the midpoint,
  /// then the new identity block enters from the opposite side — a clean
  /// Spotify-style content swap with the card chrome never moving.
  /// [dir] is -1 for next (fling left) and +1 for previous (fling right).
  Future<void> _commitContentSlide(int dir, double cardWidth) async {
    final neighbor =
        dir < 0 ? pc.peekNextTrack : pc.peekPreviousTrack;
    if (neighbor == null) {
      _springContentBack();
      return;
    }
    _committing = true;
    // Phase 1: old content exits in the fling direction, fading out.
    _contentTween =
        Tween(begin: _contentVisualDx, end: dir * cardWidth);
    _contentOpacityTween =
        Tween(begin: _contentVisualOpacity, end: 0.0);
    _contentDragDx = 0.0;
    _contentDragOpacity = 1.0;
    _contentAnim.duration = const Duration(milliseconds: 180);
    _contentAnim.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 160));
    if (dir < 0) {
      await pc.next();
    } else {
      await pc.previous();
    }
    // Phase 2: the new track's content enters from the opposite side.
    // _shownTrack is set explicitly here (not via _syncShownTrack) so
    // the entering block renders the NEW track from the first frame.
    if (mounted) {
      setState(() {
        _shownTrack = pc.currentTrack;
        _contentTween = Tween(begin: -dir * cardWidth, end: 0.0);
        _contentOpacityTween = Tween(begin: 0.0, end: 1.0);
      });
    }
    _contentAnim.duration = const Duration(milliseconds: 220);
    _contentAnim.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 200));
    _committing = false;
    if (mounted) _resetContentTransforms();
  }

  @override
  Widget build(BuildContext context) {
    // The identity block renders _shownTrack, which lags pc.currentTrack
    // by half a commit animation during a content-slide swap (seamless),
    // and follows it immediately for external changes (auto-advance).
    final track = widget.displayTrack ?? _shownTrack;
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
                        _dragOffset = Offset(0, dy);
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
              // Horizontal content slide (v1.6.9 Spotify rework): ONLY the
              // track identity block (artwork + title/artist) follows the
              // finger with rubber-band resistance — the card chrome
              // (background, transport buttons, progress line) never
              // moves. Release without a fling springs the content back;
              // a fling swaps the content to the neighbor track.
              onHorizontalDragUpdate: live
                  ? (d) {
                      final rawDx = _contentDragDx + d.delta.dx;
                      var dx = MiniPlayer.rubberBand(rawDx);
                      final dir = dx == 0 ? 0 : (dx < 0 ? -1 : 1);
                      final neighbor = dir < 0
                          ? pc.peekNextTrack
                          : pc.peekPreviousTrack;
                      // No neighbor at this end of the queue: extra
                      // resistance, never commit.
                      if (dir != 0 && neighbor == null) dx *= 0.45;
                      setState(() => _contentDragDx = dx);
                    }
                  : null,
              onHorizontalDragEnd: live
                  ? (d) {
                      final v = d.primaryVelocity ?? 0;
                      final dx = _contentDragDx;
                      final dir = dx == 0 ? 0 : (dx < 0 ? -1 : 1);
                      final neighbor = dir < 0
                          ? pc.peekNextTrack
                          : dir > 0
                              ? pc.peekPreviousTrack
                              : null;
                      if (dir != 0 &&
                          neighbor != null &&
                          ((dir < 0 && v < -_commitFlingVelocity) ||
                              (dir > 0 && v > _commitFlingVelocity))) {
                        _commitContentSlide(dir, cardWidth);
                      } else {
                        _springContentBack();
                      }
                    }
                  : null,
              onHorizontalDragCancel: live ? _springContentBack : null,
              child: SizedBox(
                height: 78,
                // The whole card still moves for vertical gestures
                // (swipe up/down); horizontal drags only ever move the
                // identity content inside _MiniCard.
                child: Transform.translate(
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
                      contentDx: _contentVisualDx,
                      contentOpacity: _contentVisualOpacity,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}


/// The main mini-player card (extracted so the peek layer can sit under it).
/// The main mini-player card. The card chrome (tinted background,
/// transport buttons, progress line) never moves horizontally; only the
/// track identity block (artwork + title/artist) translates via
/// [contentDx]/[contentOpacity] — the v1.6.9 Spotify-style rework.
class _MiniCard extends StatelessWidget {
  final Track track;
  final Color tint;
  final Color onTint;
  final ColorScheme scheme;
  final double progress;
  final bool live;
  final PlayerController pc;

  /// Horizontal offset of the identity block (finger drag / commit
  /// animation). The chrome stays fixed.
  final double contentDx;

  /// Opacity of the identity block during the commit animation.
  final double contentOpacity;

  const _MiniCard({
    required this.track,
    required this.tint,
    required this.onTint,
    required this.scheme,
    required this.progress,
    required this.live,
    required this.pc,
    this.contentDx = 0.0,
    this.contentOpacity = 1.0,
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
                // Identity block: the ONLY part that slides horizontally.
                // Clipped to the strip so mid-animation frames never
                // overflow the card's rounded corners.
                Expanded(
                  child: ClipRect(
                    child: Transform.translate(
                      offset: Offset(contentDx, 0),
                      child: Opacity(
                        opacity: contentOpacity,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(9),
                              child: TrackArt(track,
                                  size: 56, circular: true),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
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
                                        color: onTint.withValues(
                                            alpha: 0.75),
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
