# Vani v1.6.4 — release notes

## Persistent mini player with gestures
- The mini player now **floats above every screen** — Home, Search,
  Library, playlist pages ("On this phone", …), Settings sub-pages.
  Each tab got its own navigator, so pushed pages can no longer cover
  the player or the dock.
- **Gestures on the mini player:**
  - Tap / swipe up → open Now Playing
  - Swipe left → next track · swipe right → previous track
    (with a tactile nudge animation)
  - Deliberate swipe down (fast fling + distance) → **stop playback
    entirely and dismiss** — releases the player and clears the
    notification. A short accidental drag never triggers it
    (the card springs back).
- Bottom sheets and dialogs now render above the mini player.

## Developer options (your idea)
Diagnose device issues without adb:
1. **Settings → tap "Version" 7 times** → "Developer options" unlocks
   (toast counts down the taps; the entry persists).
2. Open **Developer options → enable "Capture debug logs"**.
3. Reproduce the issue.
4. Back here → **"Share log file"** (or "Copy logs") → send the text
   to the developer.

Captured: app start + version, audio-service init, EQ probe verdict,
every playback-state broadcast with the **exact native notification
controls list** (mirrors just_audio_background's formula), track
loads, load failures, and uncaught errors with stack traces.
Capture off = near-zero overhead (no string building on hot paths).

## Notes
- 204/204 tests pass. `flutter analyze` clean.
- Phone QA still needed: gesture feel, mini player over every screen,
  swipe-down-to-stop behavior, log share sheet on-device.
- The notification-buttons issue is **not** touched in this release —
  that's what the new log capture is for.
