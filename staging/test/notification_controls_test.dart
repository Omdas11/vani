import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the notification-controls plumbing that v1.5.0 investigated.
///
/// Background: the device symptom was a notification with track metadata
/// but no transport buttons. The buttons come from
/// `PlaybackState.controls`, which just_audio_background's player handler
/// broadcasts on every state change; audio_service's
/// `SwitchAudioHandler` forwards the inner handler's playbackState to the
/// platform as `setState` calls.
///
/// These tests validate the pure-Dart forwarding (runnable on any
/// platform). NOTE: on Linux/Windows, `AudioServicePlatform.instance`
/// defaults to `NoOpAudioService`, so no `setState` method-channel traffic
/// can be observed in unit tests — that is expected and is NOT the app
/// bug. On Android the real `MethodChannelAudioService` is used.
///
/// The production fix for the missing buttons (v1.5.0) is config-level:
/// `androidStopForegroundOnPause: false` (the pause/resume
/// detach/re-attach cycle was the prime suspect for the degraded media
/// session) plus an explicit notification icon and brand color.
class _PlayerLikeHandler extends BaseAudioHandler {
  _PlayerLikeHandler() {
    playbackState.add(_state(false));
  }

  static PlaybackState _state(bool playing) => PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: playing,
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {},
      );

  void setPlaying(bool playing) =>
      playbackState.add(_state(playing));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SwitchAudioHandler forwards inner playbackState with controls',
      () async {
    final switcher = SwitchAudioHandler(BaseAudioHandler());
    final player = _PlayerLikeHandler();
    switcher.inner = player;

    final received = <PlaybackState>[];
    final sub = switcher.playbackState.listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    player.setPlaying(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    player.setPlaying(false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();

    expect(received, isNotEmpty,
        reason: 'inner playbackState was not forwarded at all');
    for (final s in received) {
      expect(s.controls, isNotEmpty,
          reason: 'a forwarded state carried no controls — '
              'the notification would show no buttons');
    }
    final playing =
        received.firstWhere((s) => s.playing, orElse: () => received.last);
    final actions = playing.controls.map((c) => c.action).toSet();
    expect(actions, contains(MediaAction.pause));
    expect(actions, contains(MediaAction.skipToNext));
    expect(actions, contains(MediaAction.skipToPrevious));
  });

  test('player-like handler always broadcasts a non-empty controls list',
      () async {
    final player = _PlayerLikeHandler();
    final states = <PlaybackState>[];
    final sub = player.playbackState.listen(states.add);
    player.setPlaying(true);
    player.setPlaying(false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();

    expect(states, isNotEmpty);
    expect(states.every((s) => s.controls.isNotEmpty), isTrue,
        reason: 'every broadcast state must carry transport controls');
  });
}
