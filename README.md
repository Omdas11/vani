# OpenTune

A Spotify-style music player for **open-licensed music** — real Android app
(Flutter), dark Material 3 UI, background playback with notification controls.

No accounts, no API keys, no ads, no tracking. All music streams from the
**Internet Archive** under Creative Commons licenses.

## Music source & license notes

- **Source:** Internet Archive `advancedsearch.php` (keyless) with a strict
  license filter — only items tagged **CC0**, **CC BY 4.0**, or **CC BY 3.0**
  are ever shown or played. Query pipeline:
  `advancedsearch` → `identifier/title/creator/licenseurl` →
  `archive.org/metadata/<id>` → pick a playable file (original MP3/OGG first,
  then Archive-generated derivative MP3/OGG, then lossless) →
  stream `https://archive.org/download/<id>/<file>`.
- **Curation:** the Archive has mislabeled uploads (commercial albums falsely
  tagged CC0). A hardcoded blocklist of known-bad identifier/title keywords
  (e.g. "childish gambino", "fantasia 2000", "deluxe soundtrack") filters
  them out in `ArchiveApi`.
- **Artwork:** per-item cover via `https://archive.org/services/img/<id>`,
  with a local gradient/note placeholder when none exists.
- **Attribution:** CC-BY tracks show `"Title" by Artist · CC BY 4.0 · via
  Internet Archive` in the now-playing screen, as the license requires. CC0
  tracks need no attribution.
- Nothing in this app rips from Spotify, YouTube, or any paid service.

Full source notes: [`docs/MUSIC_SOURCES.md`](docs/MUSIC_SOURCES.md).

## Features

- **Home** — genre shelves (Trending, Electronic, Ambient, Rock, Jazz,
  Classical, Hip-Hop, Folk) + a featured shelf for the selected genre;
  horizontal track cards, tap to play; pull-to-refresh.
- **Search** — debounced live search over the IA CC0/CC-BY catalog
  (title/creator match); tap a result to play.
- **Library** — Liked Songs, Playlists (create / rename / delete, add &
  remove tracks), Downloads (offline tracks with offline badge),
  Recently Played (last 50), **My Drive** (your own songs from
  Google Drive — see below).
- **Now Playing** — full-screen sheet: artwork, title/artist, like button,
  play/pause, draggable seek bar, next/previous, shuffle, repeat
  (off → all → one), up-next queue (tap to jump), download-for-offline
  button with progress, license/attribution line, **lyrics button**.
- **Lyrics** — tap the lyrics icon on Now Playing to look up the song on
  the free lrclib.net database. Synced (karaoke-style) lyrics
  auto-scroll and highlight the current line as the song plays; plain
  unsynced lyrics are shown when no timing data exists. Lookups happen
  only when you tap (never automatically) and results are cached on
  your device, so repeat views don't hit the network. Works for both
  Archive tracks and your Drive songs (it matches on artist/title).
  "No lyrics found" simply means lrclib doesn't list that song.
- **Mini player** pinned above the bottom nav while something plays.
- **Background playback** — `just_audio` + `audio_service` (via
  `just_audio_background`): notification/lock-screen controls, headset
  media-button handling, playback continues when the app is backgrounded.
- **Offline** — downloads stream to the app documents dir (`path_provider`);
  the registry persists in `shared_preferences`; downloaded tracks play
  from the local file.
- **Persistence** — likes, playlists, downloads, Drive tracks, and
  recently-played all survive restarts via `shared_preferences` (JSON).

## My Drive — your own music from Google Drive

OpenTune has no server of its own. To play your personal collection,
host the MP3s on **Google Drive** and add them in
Library → **My Drive**:

1. In the Google Drive app/site, upload your MP3s.
2. Share each file (or the whole folder) as **"Anyone with the link"**
   → **Viewer**. Without this the app can't stream them.
3. In OpenTune: Library → My Drive → **"Add song from link"** → paste
   the share link (title/artist optional — you can edit them later).
4. Your songs now play like any other track: queue, shuffle, repeat,
   like, add to playlists, and download for offline.

**Bulk import with index.json** — instead of pasting links one by one,
host a JSON file listing your songs (a Drive file shared as "Anyone
with the link" works), then My Drive → **"Import index.json"** and
paste the file's link. Schema:

```json
[
  {"title": "Eto J Nithur Bondhu", "artist": "Aditi Chakraborty",
   "url": "https://drive.google.com/file/d/1AbC.../view?usp=sharing"},
  {"title": "Amar Shonar Bangla", "artist": "Various Artists",
   "url": "https://example.com/songs/amar-shonar-bangla.mp3"}
]
```

- Also accepted: `{"tracks": [...]}` or `{"songs": [...]}` wrappers.
- `"url"` is required — a Drive share link (converted automatically)
  or any direct audio URL. `"title"` falls back to the filename;
  `"artist"` falls back to "Unknown artist".
- Example file: [`docs/index-example.json`](docs/index-example.json).

**Honest limits:** Drive's free 15 GB is shared with Gmail/Photos;
Google may throttle heavy streaming (you'll see a "quota exceeded"
error — waiting a while fixes it); shared links must stay
"Anyone with the link". For a large library, a dedicated music
server (e.g. Navidrome/Subsonic) beats Drive — the app is ready for
that whenever you are.

## Rebuild

Every shell command must source the environment first:

```bash
source ~/workspace/opentune/ENV.sh
cd ~/workspace/opentune/app
flutter build apk --release --split-per-abi
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Notes:
- `flutter pub get` resolves against a local package mirror
  (`../.pub_pkgs/` + `pubspec_overrides.yaml`) because this sandbox's
  proxy breaks pub.dev access for the Dart tool (curl works — see
  `../mirror_pub.py`, which built the mirror). Adding a dependency means
  re-running `mirror_pub.py` (and hand-fixing prerelease version picks —
  its version comparator mishandles `0.0.1-beta.N` ordering; we hand-pinned
  `just_audio_background-0.0.1-beta.17`).
- Two build-environment patches live in the `.pub_pkgs` mirror (NOT in
  upstream packages — re-apply if you re-mirror from scratch):
  `audio_service` `compileSdk = 35 → 36` (android-35 platform isn't
  installed) and `just_audio`/`audio_session` `compileSdk 34 → 36`.
- **Proxy CA rotation:** if Gradle/Java HTTPS suddenly fails with
  `PKIX ... signature check failed` while curl works, the egress proxy's
  MITM CA has rotated again — re-import the current CA into
  `~/jdk-17/lib/security/cacerts` (see `~/AGENTS.md` → "Egress proxy CA
  rotation"). This happened once during this build (2026-10-07).
- Do **not** run `flutter upgrade` — a local `flutter_tools` patch would
  be lost.
- `lib/` in `app/` is generated from `../staging/lib/` (plus `test/`);
  treat `staging/` as the source of truth.
- `minSdk 23`, `compileSdk/targetSdk 36`, `applicationId com.opentune.app`.

## What's untested / known gaps

- **On-device runtime is untested** — this was built and unit-tested in a
  headless Linux sandbox with no Android device/emulator attached. Needs
  the user's phone to verify: audio playback & streaming, background
  service + notification controls, media-button handling, downloads and
  offline playback, artwork loading, and the IA API behaving the same
  from a mobile network.
- **Mobile layout** was not visually QA'd (no device); desktop-width
  assumptions may show on small screens.
- Genre shelves depend on Archive `subject` tagging quality (Jazz in
  particular is loosely tagged — ~40k loose results upstream).
- New in v1.1.0 and likewise phone-untested: Google Drive streaming
  (share-link parsing, index.json import, Drive downloads), the lyrics
  sheet (synced auto-scroll, caching), and the Now Playing live-rebuild.
- Some IA items expose no playable audio file; the app shows an error
  toast/line and stays on the current track in that case.
- Release APK is signed with the debug key (`signingConfigs.debug`) —
  fine for sideloading, not for Play Store release.
