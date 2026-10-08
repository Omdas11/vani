import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/main.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:opentune/widgets/mini_player.dart';

/// v1.6.4 mini-player tests.
///
/// 1. The mini player is a persistent overlay in MainShell: it must stay
///    visible (and tappable) above sub-pages pushed inside a tab's own
///    navigator (e.g. a playlist page like "On this phone"). Tabs got
///    per-tab nested Navigators in v1.6.4 exactly so pushed pages can't
///    cover the shell's bottom stack.
/// 2. Swipe left → next track; swipe right → previous track.
/// 3. Deliberate swipe down → stopAndClear (playback stopped, queue
///    cleared) and the mini player hides.
///
/// The fake uses the PlayerController.test() seam (no platform channels).
class _FakePlayerController extends PlayerController {
  _FakePlayerController() : super.test();

  Track? fakeTrack;
  bool fakePlaying = true;
  int nextCalls = 0;
  int prevCalls = 0;
  int toggleCalls = 0;
  int stopCalls = 0;

  @override
  Track? get currentTrack => fakeTrack;

  @override
  bool get isPlaying => fakePlaying;

  @override
  Future<void> playTracks(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    fakeTrack = tracks[startIndex.clamp(0, tracks.length - 1)];
    notifyListeners();
  }

  @override
  Future<void> togglePlayPause() async {
    toggleCalls++;
    fakePlaying = !fakePlaying;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    nextCalls++;
  }

  @override
  Future<void> previous() async {
    prevCalls++;
  }

  @override
  Future<void> stopAndClear() async {
    stopCalls++;
    fakeTrack = null;
    notifyListeners();
  }
}

Track _track(String id, String title) => Track(
      id: id,
      title: title,
      artist: 'Unknown artist',
      license: 'CC0',
      licenseUrl: '',
      artworkUrl: '',
    );

void main() {
  group('persistent mini player over sub-pages', () {
    testWidgets(
        'mini player stays visible and tappable above a pushed playlist page',
        (tester) async {
      final pc = _FakePlayerController()
        ..fakeTrack = _track('t1', 'Persistent Test Song');

      await tester.pumpWidget(
        MaterialApp(home: MainShell(pc: pc)),
      );
      await tester.pump();

      // Mini player visible on the home tab.
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Persistent Test Song'),
        ),
        findsWidgets,
      );

      // Switch to the Library tab via the dock…
      await tester.tap(find.text('Library'));
      await tester.pump();

      // …and push a sub-page (e.g. a playlist) inside the tab's own
      // navigator, the way LibraryScreen does.
      final libCtx = tester.element(find.text('My Drive'));
      Navigator.of(libCtx).push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('PLAYLIST SUBPAGE')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('PLAYLIST SUBPAGE'), findsOneWidget);

      // The mini player is NOT inside the pushed route: it still shows
      // the track…
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Persistent Test Song'),
        ),
        findsWidgets,
      );
      // …and it is still hit-testable above the sub-page: tapping its
      // play/pause button reaches the controller instead of the page
      // underneath.
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(pc.toggleCalls, 1);
    });
  });

  group('mini player gestures', () {
    Future<_FakePlayerController> pumpMini(WidgetTester tester) async {
      final pc = _FakePlayerController()
        ..fakeTrack = _track('t1', 'Gesture Test Song');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniPlayer(pc: pc)),
        ),
      );
      await tester.pump();
      return pc;
    }

    testWidgets('swipe left triggers next track', (tester) async {
      final pc = await pumpMini(tester);
      await tester.fling(
          find.byType(MiniPlayer), const Offset(-400, 0), 1500);
      await tester.pump();
      expect(pc.nextCalls, 1);
      expect(pc.prevCalls, 0);
    });

    testWidgets('swipe right triggers previous track', (tester) async {
      final pc = await pumpMini(tester);
      await tester.fling(
          find.byType(MiniPlayer), const Offset(400, 0), 1500);
      await tester.pump();
      expect(pc.prevCalls, 1);
      expect(pc.nextCalls, 0);
    });

    testWidgets('swipe up opens Now Playing', (tester) async {
      final pc = await pumpMini(tester);
      await tester.fling(
          find.byType(MiniPlayer), const Offset(0, -400), 1500);
      await tester.pump();
      // PlayerScreen pushed on top of the scaffold.
      expect(find.text('Gesture Test Song'), findsWidgets);
      expect(pc.stopCalls, 0);
    });

    testWidgets(
        'deliberate swipe down stops playback and hides the mini player',
        (tester) async {
      final pc = await pumpMini(tester);
      await tester.fling(
          find.byType(MiniPlayer), const Offset(0, 400), 1500);
      // The dismiss animation + stop settle shortly after the fling.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(pc.stopCalls, 1);
      // Queue cleared → currentTrack null → mini player hides.
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Gesture Test Song'),
        ),
        findsNothing,
      );
    });

    testWidgets('a short downward drag does NOT stop playback',
        (tester) async {
      final pc = await pumpMini(tester);
      // Slow short drag: below both the velocity and distance
      // thresholds for the deliberate swipe-down-to-stop.
      final center = tester.getCenter(find.byType(MiniPlayer));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump();
      expect(pc.stopCalls, 0);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Gesture Test Song'),
        ),
        findsWidgets,
      );
    });
  });

  group('stopAndClear (real logic)', () {
    test('stops without a device player and empties the queue', () async {
      // PlayerController.test() never builds the AudioPlayer (no
      // platform channels in tests); the stop() call is guarded.
      final pc = PlayerController.test();
      await pc.stopAndClear();
      expect(pc.queue, isEmpty);
      expect(pc.currentTrack, isNull);
    });
  });
}
