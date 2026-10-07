# Vani v1.5.0

## Notification controls — fixed (P0)
The system notification lost its transport buttons because the foreground
service detached every time you paused. It now stays in the foreground
across pause/resume, with an explicit icon and brand color. Next/previous
buttons appear once the queue is mirrored to the background player
(as before).

## New: Equalizer (beta)
Settings → Equalizer. Your phone's native 5-band system EQ with
Normal / Bass Boost / Treble / Vocal presets + full custom sliders.
Settings persist across launches. If your device doesn't expose the
effect, the screen says so instead of pretending.

## New: FLAC & Opus playback (beta)
Phone imports now accept `.flac` and `.opus` (decoded by ExoPlayer).
Tracks show a small `FLAC β` / `OPUS β` badge. Seeking can vary by
device — tell us if anything misbehaves.

## Lyrics: many more hits
New lookup order: lrclib exact → lrclib free-text search → KuGou
(synced) → **web-search fallback** (plain text, clearly labeled — the
same approach the Namida player uses). The sheet now shows which source
each result came from.

## AI Fixer v2 (beta) — now worth trying
- **3 providers:** Gemini, OpenRouter, or any OpenAI-compatible endpoint
  (custom base URL). Each key lives in secure storage, never logged.
- **Preview-then-apply** for everything: `Artist - Title` filename
  renames (sanitized), metadata fixes, missing-lyrics fetch, and cover
  art from iTunes / MusicBrainz (no scraping).
- **Batch mode** for a whole folder/playlist with per-track checkboxes.
- Test button in Settings → AI Fixer to verify your key.

## Smoother UI + Material 3
- De-janked: cheaper glass blur, repaint-isolated background, vinyl and
  animations (the always-on gradient + stacked blurs were the main
  choppiness driver).
- M3 Expressive segmented-button preset picker; bigger "Vani" wordmark
  on Home.

## Fixes
- Mini-player: added the missing **next** button (prev / play-pause /
  next are now symmetric).
- Playback-state forwarding is now unit-tested, so the notification
  wiring can't silently regress.

---
**Upgrade note:** uninstalling is not needed — install over v1.4.x.
Delete old `app-arm64-v8a-release.apk` files from Downloads first so you
don't reinstall a stale download.
