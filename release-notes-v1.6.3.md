# Vani v1.6.3 — release notes

## Notification buttons — evidence-grounded hardening (P0)

The v1.6.2 root-cause theory (EQ-rebuild race) was disproven by device
testing — buttons were still missing. A full re-audit of the chain
(Dart controls → `1 << actionIndex` bitmask → native
`PlaybackStateCompat` actions → MediaStyle notification) verified every
layer correct headless, so the failure is device/OEM-specific (Moto G40
Fusion, near-stock Android 12).

Two changes, both grounded in a documented fix for the same plugin
version (senkjm/webdav_media_manager's vendored audio_service 0.18.19
PATCHES.md — "OEM builds that hide LOW media channels"):

1. **Notification channel importance** (app-side,
   `MainActivity.ensureAudioChannel()`): audio_service creates its
   channel at IMPORTANCE_LOW; the app now pre-creates
   `com.opentune.app.channel.audio` at IMPORTANCE_DEFAULT (audio_service
   only creates the channel when absent) and deletes the stale LOW
   channel left by earlier installs so it is recreated properly.
2. **Transport category** (mirror patch, documented in README):
   audio_service's `getNotificationBuilder()` now sets
   `CATEGORY_TRANSPORT` so OEM skins treat the notification as media
   transport instead of degrading it to a metadata-only shade entry.

Honest status: no headless test can prove SystemUI renders the buttons
on this OEM skin — the acceptance test is the user's shade. If they are
still missing, the next step is logcat from the device.

## Tap-a-song regression test

User reported tapping a song does nothing (no mini player). The tap
path (TrackTile InkWell → `PlayerController.playTracks` →
`notifyListeners` → mini-player visibility) is now pinned by widget
tests (`v163_test.dart`, incl. a `PlayerController.test()` seam that
skips building the device-bound AudioPlayer). Both pass headless — the
Dart wiring is verified; a device-side failure would need logcat.

## minSdk 29 (Android 10+)

`minSdk` is now explicitly 29 (was Flutter's default 24). Audited for
10/11 compatibility: the app's own Kotlin (MainActivity) and Dart use
no API-30+ calls; `dynamic_color` degrades gracefully below Android 12
(returns null schemes → Obsidian fallback); all audio plugins declare
minSdk ≤ 29. Note: this drops Android 6–9 (incl. the spare Zenfone 2
Laser / Lava A97 on Android 6).

## Verified

- `flutter analyze`: clean
- 185/185 tests pass (183 existing + 2 new v163 tap tests)
- Release APKs built per ABI with versioned names
