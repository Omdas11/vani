# Vani v1.6.6 — equalizer refusal fixed for real + dynamic mini player

Two items — one deep bug, one UI refinement:

## Equalizer: the real root cause (evidence from the on-device dev log)

The v1.6.4 developer log proved the `UnimplementedError:
androidEqualizerGetParameters()` was **still** thrown on every first
playback, escaping as *uncaught async*. Source-level forensics on the
vendored plugins found why every previous guard failed:

- just_audio's effect `_activate` loop sits **outside** its try/catch
  (`AudioPlayer._setPlatformActive.setPlatform`), so the refusal
  escapes via an orphaned `_platform` future — it never reaches a
  try/catch around the awaited `setAudioSource`, which instead hangs
  (the "load timeout" lines in the log are this hang, not a network
  issue).
- The old startup probe awaited `equalizer.parameters`, but that
  future can **only** complete inside `_activate` itself — so the probe
  always timed out ("ambiguous") and never protected anything.

The fix: EQ support is now resolved with a **genuine activation probe**
at startup — a sacrificial player runs a real `setAudioSource` on a
silent asset inside a zone net (`guardedActivate`) that catches the
refusal however it surfaces. The verdict is persisted (awaited, so it
can't be lost) and the main player is built exactly once with the
right pipeline. First playback on affected devices no longer throws,
hangs, or tears down the audio service.

The same zone net now guards `setAudioSource` in normal playback as a
last resort (replacing the try/catch branch that could never fire).

## Mini player: dynamically appears, zero reserved space

When nothing is playing, the layout no longer reserves a blank slot
above the dock — content flows down to the dock. When playback starts,
the card slides + fades in; on stop/dismiss it collapses away (the
exiting card keeps its last track, inert, so the collapse animates
smoothly instead of popping). The content's bottom padding animates
along with it.

## Notification buttons

The Dart→native broadcast chain was diffed line-by-line against the
vendored plugin sources and is correct (non-empty controls, right
bitmask mapping, live session). The prime suspect for the missing
buttons is now gone: the EQ-throw chaos (uncaught error + hung loads
+ idle→stop→session-release cycles visible in the log) that could
leave SystemUI bound to a dead session. Please re-test the shade
after updating — if buttons are still missing, the next step is the
Developer Mode log (Settings → tap Version 7×), which now also
records the EQ verdict.

**Get it:** `Vani-v1.6.6-arm64.apk` (most phones) from this release's assets.
