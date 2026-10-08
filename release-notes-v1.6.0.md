# Vani v1.6.0 — Material 3 Expressive redesign + Material You

The UI got its biggest overhaul yet: real Material 3 Expressive
components everywhere, wallpaper-matched dynamic colors, and three new
accent presets to finally kill the all-green monochrome.

## What's new

**Material You dynamic color**
- New "Match system theme color" toggle (Settings → Look & Feel, on by
  default): on Android 12+ the whole app follows your wallpaper colors.
  Change your wallpaper and the app re-themes when you come back.
- On older Android the toggle shows as unavailable and the app uses the
  classic Obsidian Sonic theme.

**4 accent presets** (Settings → Look & Feel)
- Neon Mint (the classic green, still the default), Plum Wave, Periwinkle,
  Amber Dusk. One tap switches the whole app's accent.

**Your radius, your rules**
- New "Corner radius" slider in Look & Feel — cards, sheets and dialogs
  follow it, with a live preview.

**Expressive player**
- New wavy seek bar: the played part is an animated sine wave that
  flattens while you drag.
- Tonal top bar (collapse button + lyrics/queue pill), big filled
  play/pause hero, shuffle/repeat/like grouped in one pill.
- Long titles marquee-scroll instead of cutting off.
- New queue sheet: drag to reorder up-next, swipe to remove, tap to jump.
- The mini-player now re-tints itself from the current album art.

**Expressive everywhere else**
- Home/Search/Library get big display headers and pill chips; song rows
  are now individual cards with a circular options button that opens a
  rich action sheet (Play next, Add to queue, Like, Add to playlist,
  Download).
- Lyrics: big Synced/Static pill switch, floating play button, mini wavy
  transport at the bottom.
- Settings is now icon-tile categories with a dedicated Look & Feel page.

**Kept and restyled:** the spinning vinyl with holographic shimmer,
ambient cover-art glow, veena watermark, floating dock.

## Notes
- Nothing about playback changed: Drive/local/Archive sources, lyrics
  (lrclib + KuGou + web fallback), stats, AI Fixer, downloads,
  playlists all work as before. The v1.5.1 equalizer safety guard is
  intact — on devices without a system equalizer the EQ screen hides
  itself and playback never touches it.

## Get it
- `Vani-v1.6.0-arm64.apk` — most modern phones (recommended)
- `Vani-v1.6.0-armeabi-v7a.apk` — older 32-bit phones
- `Vani-v1.6.0-x86_64.apk` — emulators / x86 devices

Sideload: allow "Install unknown apps" for your browser/file manager,
then open the APK. Delete old `Vani-v*.apk` downloads first so you
don't reinstall a stale one.
