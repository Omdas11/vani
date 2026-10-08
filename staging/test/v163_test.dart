import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/services/player_controller.dart';
import 'package:opentune/widgets/mini_player.dart';
import 'package:opentune/widgets/track_tile.dart';

/// v1.6.3 regression tests.
///
/// 1. Tap-a-song bug (P0, user-reported on v1.6.2): tapping a song row
///    did nothing — no mini player, no playback UI. The tap path is
///    TrackTile (InkWell) -> PlayerController.playTracks ->
///    notifyListeners -> AnimatedBuilder rebuild -> MiniPlayer appears
///    (currentTrack != null). This test pumps the real TrackTile +
///    MiniPlayer pair (as MainShell lays them out) with a scripted
///    PlayerController double and asserts the tap reaches playTracks
///    AND surfaces the mini player with the tapped track's title.
///    The double uses the PlayerController.test() seam: the real
///    constructor builds a just_audio AudioPlayer, which needs a
///    device's platform channels.
class _FakePlayerController extends PlayerController {
  _FakePlayerController() : super.test();

  Track? fakeTrack;
  int playTracksCalls = 0;
  bool fakePlaying = false;

  @override
  Track? get currentTrack => fakeTrack;

  @override
  bool get isPlaying => fakePlaying;

  @override
  Future<void> playTracks(List<Track> tracks, int startIndex) async {
    playTracksCalls++;
    if (tracks.isEmpty) return;
    fakeTrack = tracks[startIndex.clamp(0, tracks.length - 1)];
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
  group('tap-a-song surfaces the mini player', () {
    testWidgets('tapping a song row plays it and shows the mini player',
        (tester) async {
      final pc = _FakePlayerController();
      final tracks = [
        _track('t1', 'Rutho Jo Tum (Tum Prem Ho)'),
        _track('t2', 'Another Song'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: pc,
              builder: (_, __) => ListView(
                shrinkWrap: true,
                children: [
                  TrackTile(
                    track: tracks[0],
                    contextQueue: tracks,
                    indexInQueue: 0,
                    pc: pc,
                  ),
                  MiniPlayer(pc: pc),
                ],
              ),
            ),
          ),
        ),
      );

      // Before the tap the mini player renders nothing (no current track).
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Rutho Jo Tum (Tum Prem Ho)'),
        ),
        findsNothing,
      );

      // Tap the song row itself: tap the tile's title text, which sits
      // inside the tile's own InkWell (not the trailing overflow
      // button's).
      await tester.tap(find.text('Rutho Jo Tum (Tum Prem Ho)'));
      await tester.pump();

      // The tap reached the controller...
      expect(pc.playTracksCalls, 1);
      expect(pc.fakeTrack?.id, 't1');
      // ...and the mini player surfaced with the tapped track's title.
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Rutho Jo Tum (Tum Prem Ho)'),
        ),
        findsWidgets,
      );
    });

    testWidgets('mini player stays hidden with no current track',
        (tester) async {
      final pc = _FakePlayerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniPlayer(pc: pc)),
        ),
      );
      expect(find.byType(SizedBox), findsWidgets);
      // No title text anywhere inside the mini player.
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });
  });
}
