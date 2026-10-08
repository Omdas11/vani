# Vani v1.6.8 — release notes

## Notification polish
- Action icons redrawn smaller with generous padding (less chunky in the shade).
- New button set: **previous · play/pause · next · shuffle** — the stop square
  is gone. Previous/next are always visible; at the ends of the queue they
  show dimmed, and tapping previous with no previous track restarts the
  current track. The shuffle button toggles shuffle from the notification.

## Mini-player gestures
- Swipe left/right is now a **peek**: drag to reveal the next/previous track
  sliding in with rubber-band resistance; release to spring back, fling to
  skip. No more accidental skips.
- Swipe up opens Now Playing with a smooth expand transition (no abrupt cut).

## Now Playing background
- The hard black band is gone: the vinyl area blends into a gradient derived
  from your theme color, flowing through the now-transparent control panel.

## Settings gear on every page
- Home, Search, Library and Stats headers all have the settings gear now
  (jumps to the Settings tab).

## Theme modes
- New Look & Feel option: **System / Dark / Light / AMOLED (pure black)**.
  Light is a proper white Material 3 theme; AMOLED pins surfaces to pure
  black; System follows the phone. Presets and dynamic color keep working
  inside every mode.

## Developer options
- New **Simulate crash** button: throws a test exception through the real
  error pipeline — captured in the debug log and saved as a persistent
  crash-report file you can share with **Share crash log**.

## Fixes
- A local/offline track that fails to load no longer blames your connection
  ("Couldn't load this file" instead of "Timed out — check your connection").

**Needs your phone to verify:** gesture feel, gradient look, light/AMOLED
themes, notification icons + the new button set (prev-dim/shuffle behavior).
