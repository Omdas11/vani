# Vani v1.6.2 — notification buttons root-cause fix + marquee fix

## Notification transport buttons: the actual root cause, fixed

Three releases chased this with config tweaks. This time the whole
audio path was audited end to end — Dart playback-state construction,
the `MediaAction` → native action-bit mapping, session activation, the
`MediaStyle` notification, manifest, channel — and the library wiring
is **correct**. The fault was in our own code, and it was
device-specific:

On phones where Android's native equalizer channel is unimplemented
(like the reporter's Moto G40 Fusion), v1.5.1's EQ guard discovered
the failure *inside* `setAudioSource` — so **every first playback**
disposed the player and rebuilt it. That dispose drives the native
`AudioService` through `stop()`: media session deactivated,
notification cancelled, `stopSelf()` — and the rebuild immediately
restarts the foreground service, racing the old instance's `onDestroy`
(`instance = null`, session released). Win the race wrong and the
notification ends up bound to a dead session: artwork and title
visible, **zero buttons**. This teardown/restart cycle did not exist
before v1.5.1, which matches when the symptom escalated to no buttons
at all.

**The fix:** equalizer support is now resolved **once at startup**,
before any playback can exist (bounded probe, verdict persisted to
`eq_unsupported`). The player is built exactly once with the right
pipeline — no more per-playback native service teardown. On the
affected phone the second launch skips the probe entirely.

Headless verification added (the OEM shade still needs a real phone
to confirm): a test pins the `MediaAction` enum order against
Android's `PlaybackStateCompat` bit positions (a silent reorder would
zero the native bitmask), plus a controls-contract test asserting a
playing state always carries play/pause/skip/stop.

> **Acceptance test for the reporter:** play any track, pull down the
> notification shade — play/pause, previous and next buttons must now
> be present on the media notification.

## Now Playing title no longer clipped

Long titles ("Rutho Jo Tum (Tum Prem Ho) [FfCrY2vrkuc]") could render
starting mid-title. The marquee is now a **seamless wrap loop** —
text duplicated with a gap, constant-speed forward scroll, invisible
wrap back to offset 0 — so the title **always begins at its first
character** at every loop restart and the full text scrolls every
cycle. Track changes also reset to offset 0. Widget tests cover an
overlong title (full text from character 0, both loop copies), a
short title (no marquee), and title swaps.

## Mini-player: full transport set

The mini-player now has **previous / play-pause / next** (previous
was missing), matching the Now Playing screen. Queue behavior
unchanged — verified by the existing suite.

## Technical notes

- Version 1.6.2+11 (versionCode 11). `flutter analyze` clean,
  **183/183 tests pass** (7 new).
- The EQ screen's "not available on this device" state and Try Again
  behavior are unchanged; the persisted verdict only skips the probe.
- If the platform ever regresses after proving supported, the old
  playback-path guard remains as a last resort (and now persists the
  verdict too, so it can only fire once per install).
