# PixelPlayer UI Study — Look-and-Feel Research for Vani

> Research-only document. No code or assets copied. All observations come from
> **public-facing materials**: the PixelPlayerHQ/PixelPlayer GitHub README
> (4 README screenshots, `assets/screenshot1–4.jpg`, fetched 2026-10-08),
> the repo's public feature list and tagline, public release/commit summaries,
> third-party writeups (magiskzip.com, appteka.store), and a Flutter port's
> public README (chiraitori/pixel-player-flutter) used only as corroboration.
> Screenshots were inspected visually, not scraped for code.
>
> PixelPlayerHQ/PixelPlayer's license is proprietary (portions pre-2026-05-12
> MIT per its LICENSE/THIRD_PARTY_NOTICES) — this study covers
> look-and-feel only.

Sources:
- https://github.com/PixelPlayerHQ/PixelPlayer (README, screenshots, tagline: "privacy-first Android music player built with Material 3 Expressive")
- https://github.com/PixelPlayerHQ/PixelPlayer/blob/master/README.md
- https://magiskzip.com/pixelplayer-privacy-first-android-music-player/
- https://appteka.store/app/066r262719

---

## 1. PixelPlayer — element inventory (from the 4 public README screenshots)

### Screenshot 1 — Home ("Your Mix")

**Visible M3 / M3-Expressive components**
- **Large display header**: oversized "Your Mix" display text + smaller subtitle "Today's Mix for you". Pure M3-Expressive editorial scale (roughly Display Large, possibly larger).
- **Tonal IconButtons**: two circular tonal icon buttons top-right (a "newspaper/list" icon — likely Recently Played/Stats — and a gear for Settings) sitting on `surfaceContainer`-tone circles.
- **Giant circular play button**: a very large filled circle (periwinkle/light-blue `primaryContainer` tone) with a dark play triangle — functions as the hero CTA ("play my mix"). Not a standard FAB shape; closer to an oversized filled IconButton.
- **Expressive artwork collage**: album art shown inside playful morphing shapes — one large rounded form (squircle-ish circle) plus smaller circles, one rotated pill. Signature M3-Expressive shape language rather than plain rounded squares.
- **Mini-player (docked card)**: a wide rounded container (~28dp radius) in a mauve `secondaryContainer` tone holding: circular artwork (left), two-line title/artist in `onSecondaryContainer`, and **two circular tonal IconButtons** (play, skip-next) on the right.
- **NavigationBar in a floating rounded container**: bottom nav sits inside a dark rounded-rectangle container (~32dp radius). Three destinations (Home, Search, Library). The active destination gets a **pill-shaped indicator** (secondary-container tone) wrapping a filled icon + label; inactive destinations show outline icons + labels. Compact, centered, clearly the M3 `NavigationBar` with expressive container treatment.

**Shapes**: circles (icon buttons, play hero, artwork), full pills (nav indicator), large-radius rounded containers (nav dock, mini-player). Nothing sharp anywhere.

**Color**: near-black background with a subtle navy tint; dynamic accent pops (blue hero button, mauve mini-player). The mauve mini-player vs. blue hero button suggests per-context dynamic coloring.

### Screenshot 2 — Now Playing

**Layout, top to bottom**
1. **Top bar**: circular tonal "collapse" (down-chevron) button left; centered "Now Playing" title (rounded-sans, `titleLarge`-ish); right side has **two pill-shaped tonal buttons** (a darker rounded container holding a lyrics icon and a queue-list icon side by side).
2. **Dynamic-color background**: the entire screen background is a deep plum/mauve **extracted from the album artwork** — the README's "Album Art Colors — Dynamic color extraction from album artwork" in action. No scrim needed; text is light-on-plum.
3. **Hero artwork**: large rounded-square (squircle, ~56–64dp radius), centered, ~80% of screen width.
4. **Title block**: track title in large rounded geometric sans (headline scale, near-white), artist below in a muted mauve tone (title scale).
5. **Wavy progress slider** — the signature M3-Expressive element: the *played* portion renders as a **sine wave** in light pink, flattening into a straight line at the round thumb knob; the *remaining* portion is a translucent straight track. Time labels (`01:21` / `03:10`) flank it in a small rounded font. (Public commit summaries name this component `WavySliderExpressive` and note the wave "flattens during interaction" with a "pill-to-line thumb morph".)
6. **Transport controls**: three large circular tonal buttons — previous (darker container), **play/pause as the hero** (big light-pink circle/squircle ~96dp with dark pause glyph), next (darker container).
7. **Secondary controls pill**: shuffle, repeat, and a filled heart (like) grouped inside a **dark pill-shaped container** — three icon buttons in one expressive pill.

**Not visible**: inline lyrics (lyrics live behind the top-bar icon), overflow menu, sleep timer. Queue is behind the top-right queue icon.

### Screenshot 3 — Library (Songs tab)

**Visible components**
- **Display header**: huge italic-leaning rounded "Library" in periwinkle; settings gear in a filled blue circle top-right (primary-filled circular IconButton).
- **Filter chips (horizontally scrollable)**: large pill chips (~56dp tall), fully rounded. Selected chip = filled light-blue `primaryContainer` with dark uppercase label ("SONGS"); unselected = near-black pills with light uppercase labels ("ALBUMS", "ARTIST", …). Uppercase small-cap labels are a distinctive choice.
- **Content container**: the song list sits inside a dark `surfaceContainer` card with a **large top corner radius (~32dp)** — an expressive bottom-sheet-like container for the list itself.
- **"Shuffle" pill button** (tonal, purple-gray) + a **circular sort icon button** at the top of the list — a nice list-header pattern.
- **Song rows as individual cards**: each row is its own rounded card (~24dp radius, `surfaceContainerLow`), containing: ~56dp rounded-square artwork (radius ~16dp), title (`titleMedium`, white), artist (`bodyMedium`, gray, truncated with ellipsis), and a **circular tonal IconButton with a 3-dot overflow menu** as the trailing control.
- Mini-player + bottom nav identical to Home.

**List-row anatomy**: ~88dp tall card rows, 12–16dp gaps between cards, 16dp horizontal margins. Artwork left, two metadata lines, circular overflow right. No dividers — cards do the separation.

### Screenshot 4 — Lyrics

**Visible components**
- **Top bar**: black circular back button; centered "Lyrics" title in rounded sans.
- **Segmented buttons, expressive style**: two large fully-rounded pills — "Synced" selected (light-pink fill, dark text) / "Static" unselected (translucent dark pill, light text). Much larger and more pill-like than stock M3 segmented buttons.
- **Lyrics lines**: large rounded-sans lines with generous line spacing. Active line = bright near-white, larger; inactive lines dimmed to ~40% alpha. Karaoke-style focus hierarchy.
- **Floating squircle play/pause**: a large soft-square (squircle) button in pale mint-green with a dark pause glyph, floating centered over the lyrics — a signature touch.
- **Bottom progress pill**: a black pill container holding time labels (`01:48` / `03:10`) and a smaller **wavy slider** (pink wave) — the mini transport, always visible while reading lyrics.

### Components NOT confirmed from public materials (thin spots)
- **Settings screen**: no public screenshot. README claims "Adjustable corner radius and navigation bar settings"; a public changelog notes Settings was "modernized" with "category sub-screens" in M3-Expressive style (v0.5.0-beta). Exact layout unverified.
- **Equalizer**: the repo tagline advertises "fine-tune with equalizer presets"; the official README feature list I fetched does not detail an EQ screen, and no screenshot shows one. A third-party fork changelog mentions a 10-band EQ. Treat EQ UI as **unverified**.
- **Queue screen/sheet**: public release notes (v0.7.0-beta) mention a "redesigned queue sheet" with drag-and-drop reordering and "animated queue scrolling"; no public screenshot. Pattern confirmed as *existing*, visuals unverified.

## 2. Shapes & corner radii language

- **Fully rounded pills** for chips, segmented controls, buttons (Shuffle, Synced/Static), and the secondary-controls container.
- **Circles** for icon buttons (top bars, overflow menus, transport prev/next, mini-player buttons).
- **Squircle / large-radius rounded squares** for artwork: ~16dp on list thumbnails, ~56–64dp on the now-playing hero art.
- **Expressive morphing shapes** for decorative artwork (rotated pill, circles of varying sizes on Home).
- **Large container radii (~28–32dp)** for the mini-player, bottom-nav dock, and list container — cards-within-cards, never edge-to-edge rectangles.
- Corner radius is **user-adjustable** in Settings (per README) — the shape language is a feature, not an accident.

## 3. Color strategy

- **Material You dynamic color, two sources**: (a) wallpaper-based app theme (README: "Dynamic color theming that adapts to your wallpaper"), and (b) **per-album-art extraction that re-themes the Now Playing screen and mini-player** (plum/mauve in the screenshots, derived from the Linkin Park artwork). This is the core anti-monochrome mechanism: the app is never one flat color because the *currently playing art* repaints the player.
- **Tonal palettes everywhere**: primary/secondary/tertiary *containers* (light blue hero button, mauve mini-player, periwinkle headers) over near-black `surface` with `surfaceContainer` layering. Contrast comes from container tones, not from a single accent.
- **Accent usage is functional**: filled/high-emphasis = primary actions (play hero, selected chip, selected segmented button); tonal/dark circles = secondary actions (prev/next, overflow, top-bar icons).
- **Dark theme is the showcase**, light theme supported (README: "Dark/Light Theme — Automatic or manual").
- **How dynamic color is applied**: tonal roles (`primaryContainer`, `secondaryContainer`, `surfaceContainer*`) rather than raw hues — so any extracted palette stays legible. The Flutter port's public README corroborates the mechanism ("dynamic theme extraction from album artwork" via Material Utilities-style quantization).

## 4. Typography

- A **rounded geometric sans** throughout (soft, circular letterforms — visible in "Your Mix", "Library", "The Emptiness Machine", button labels). The exact font is unconfirmed from official materials; the third-party Flutter port's README claims the original uses **Google Sans Flex** — plausible given the look, but treat as corroborating-not-official.
- **Hierarchy**: Display (screen headers "Your Mix"/"Library", oversized), Headline (now-playing track title), Title (song-row titles, "Now Playing" bar), Body (artists, subtitles in `onSurfaceVariant` gray), Label (uppercase chip/segment labels, time readouts in a slightly mono/rounded cut).
- Long titles **marquee-scroll** instead of truncating in the player (per v0.7.0-beta release notes).
- Detail screens (Album/Artist) use a "bold, horizontally scaled font effect" for headers per public commit summaries — condensed-bold display type as a branding device.

## 5. Spacing rhythm, density, list-row anatomy

- **Generous whitespace**: the Home screen is mostly empty dark space around the display title and art collage — confident, low-density.
- **Card-based lists**: song rows are separated cards with ~12dp gaps, not divider-separated flat rows. Airy, touch-friendly (~88dp rows).
- **Row anatomy**: 56dp rounded artwork → 12dp gap → two-line metadata (title `titleMedium` / artist `bodyMedium`, artist truncated) → circular tonal overflow button. No duration shown on rows (duration lives in the player).
- **Grouping**: list headers combine a tonal pill CTA (Shuffle) + circular utility button (sort) above the list — actions live *with* the list, not in the app bar.

## 6. Motion & signature interactions

(From public release notes and commit summaries — not directly visible in static screenshots.)
- **Wavy slider**: the played portion is an animated sine wave that **flattens while dragging**, thumb morphs pill-to-line.
- **Mini-player ↔ full-player morph**: "smoother alpha and scaling transitions between the mini-player and full-player views based on expansion fraction" — the mini-player expands into the now-playing sheet.
- **Marquee** for long titles; **animated queue scrolling**; fluid screen transitions and micro-interactions (README claim).
- **Expressive dialogs**: e.g. the lyrics-fetch dialog was "completely redesigned with a custom, expressive Material 3 layout" (Oct 2025 commit summary).
- Bottom sheets use contextual corner rounding that adapts to list position (`expressiveListShape` per commit summaries).

## 7. Bottom navigation & mini-player pattern (detail)

- **Bottom nav**: M3 `NavigationBar` with **3 destinations** (Home, Search, Library), housed in a **floating rounded container** (~32dp radius, `surfaceContainer` tone) with side margins — it is a dock, not an edge-to-edge bar. Active destination: pill indicator + filled icon + label; inactive: outline icon + label. A "compact mode for the navigation bar" exists per release notes.
- **Mini-player**: sits **directly above the nav dock** as its own rounded card (~28dp radius) in a **dynamic `secondaryContainer` tone** (re-colored from album art). Contents: circular artwork, title/artist (2 lines, `onSecondaryContainer`), **play/pause + skip-next as circular tonal IconButtons**. Tapping expands to full Now Playing with an alpha/scale morph.
- The two elements read as one stacked "dock unit" — mini-player card floating over the nav dock.

## 8. Now-playing screen anatomy (detail)

Summarized from Screenshot 2 + Lyrics screen:
- Collapse button (circular tonal) + centered "Now Playing" title + lyrics & queue shortcuts (pill tonal group) in the top bar.
- Full-bleed **album-art-derived background** (plum in screenshots).
- Hero artwork ~80% width, squircle ~60dp radius.
- Track title (headline, rounded sans, near-white) + artist (muted).
- **Wavy expressive slider** + time labels.
- Three big circular transport buttons; play/pause is the largest, filled light.
- Shuffle / repeat / like grouped in a **dark pill container**.
- Lyrics and queue are one tap away in the top bar; the lyrics screen keeps a **mini wavy transport pill** pinned at the bottom and floats a **squircle play/pause** over the text.

---

## Supplement A — Metro (open source, github.com/zillowez/metro — fork of RetroMusicPlayer)

Classic (non-expressive) M3 done cleanly. From README screenshots:
- **Songs screen**: top bar with search + overflow icons; big display "Songs"; **flat divider-free list** — 56dp rounded artwork, title/artist, trailing 3-dot; a **rounded-square tonal FAB** (shuffle icon) floating bottom-right; mini-player as a slim strip (artwork + "Title • Artist" + circular play button); standard edge-to-edge 5-destination `NavigationBar` (active = pill indicator + label).
- **Settings**: the pattern worth stealing — **categorized list with circular pastel icon tiles** (blue "Look and feel", pink "Now playing", purple "Audio", mint "Personalize", pink "Images", yellow "Notification", blue "Other"/"Backup & Restore", green "About"), each row = icon tile + title + descriptive subtitle, big "Settings" display header + back arrow.
- Color: conventional M3 dynamic/static palettes, light theme showcased; less adventurous than PixelPlayer but a good reference for a clean settings taxonomy.

## Supplement B — Auxio (open source, github.com/OxygenCobalt/Auxio)

Opinionated, snappy M3. From README screenshots:
- **Now Playing**: the **wavy progress slider** appears here too (Auxio popularized it); artwork in a large rounded rect; **squircle play button** in primary container flanked by circular tonal prev/next; shuffle/repeat as **outlined circular icon buttons**; a "Queue" bottom-sheet handle at the bottom edge.
- **Search**: filter chips row (Songs, Albums, Artists, Genres, Playlists) + **grouped result sections** with small headers (Artists / Albums / Genres / Songs), artwork-led rows, trailing 3-dot menus; mini-player strip at bottom with play + shuffle buttons.
- **Principles** (README): edge-to-edge, "no rounded album covers (if you want them)", opinionated UX over edge cases. A good reference for tasteful restraint — fewer decorative shapes than PixelPlayer, same M3 bones.

## Supplement C — Namida (open source, Flutter, github.com/namidaco/namida)

The most customization-obsessed of the four; highly relevant since **Vani is also Flutter**. From README + screenshots:
- **Navigation**: left **drawer** with rounded-card destinations (Home, Albums, Tracks [active pill], Artists, Genres, Playlists, Folders, Search, Queues, Youtube); drawer footer has a **theme quick-switcher** (auto/light/dark segmented control) and sleep timer shortcut. Alternative to bottom nav worth considering.
- **Player**: "Player Colors are picked from the current album artwork" (README) — same dynamic-color idea as PixelPlayer; **waveform seekbar** (real audio waveform, signature element); circular play button; bottom toolbar (audio source, shuffle, repeat, queue); lyrics shown as a rounded card overlay; "Animating Thumbnail" (artwork pulses with audio peak) and "Miniplayer Party Mode" (edge breathing glow, static or artwork-derived colors).
- **Track overflow sheet** (excellent pattern): rows with leading icons — Go to Album, Go to Artist, Go to Folder, Share, Stop after this track, Add to Playlist, Edit Tags, Advanced, Open in Youtube view, "Repeat for N times" (−/+ steppers) — plus **"Play Next" / "Play Last"** split buttons at the bottom. The richest per-track action sheet of the four apps.
- **Settings/dialogs**: chip-based multi-select dialogs (Artist Separators, Blacklist with removable chips + Add field); search screen with Local/Youtube tabs; queues saved as cards with artwork, duration, overflow.
- **Look & Feel** (README): "Material3-like Theme", dynamic theming, waveform seekbar, deep customization section.

---

## Patterns to adopt in Vani (concrete, actionable)

1. **Floating nav dock** — Put Vani's `NavigationBar` inside a rounded (~28dp) `surfaceContainer` dock with side/bottom margins instead of an edge-to-edge bar; keep the M3 pill active indicator. (PixelPlayer Home/Library)
2. **Mini-player as a dynamic tonal card** — Rounded ~28dp card docked above the nav dock: circular artwork, 2-line title/artist, circular tonal play + next buttons; **re-tint its container color from the current album art** like PixelPlayer does. (PixelPlayer Home/Library)
3. **Mini-player → full-player morph** — Expand the mini-player into Now Playing with a shared-element alpha/scale transition driven by drag fraction. (PixelPlayer, per public commit notes)
4. **Wavy progress slider** — Adopt the M3-Expressive wavy slider for the seek bar: sine-wave played portion that flattens on drag, round thumb, translucent remaining track. It's the single most distinctive "expressive" signature across PixelPlayer *and* Auxio.
5. **Segmented pill control for lyrics modes** — Large fully-rounded Synced/Static segmented buttons at the top of the lyrics view. (PixelPlayer Lyrics)
6. **Secondary-controls pill** — Group shuffle / repeat / like inside one dark pill container beneath the transport buttons instead of scattering them. (PixelPlayer Now Playing)
7. **Floating squircle play/pause on lyrics** — A large soft-square tonal play/pause floating over the lyrics view + a slim wavy-transport pill pinned at the bottom. (PixelPlayer Lyrics)
8. **Card-based song rows** — Each song row as its own rounded card (~20–24dp radius, `surfaceContainerLow`) with 56dp rounded artwork and a **circular tonal overflow button**; no dividers. (PixelPlayer Library)
9. **List header: Shuffle pill + sort button** — Above every song list, a tonal "Shuffle" pill on the left and a circular sort/filter icon button on the right. (PixelPlayer Library)
10. **Rich track action sheet** — Bottom sheet per track: Go to Album, Go to Artist, Play Next, Play Last, Add to Playlist, Share, Sleep timer, Edit tags — with leading icons and Play Next/Play Last as prominent split buttons. (Namida)
11. **Settings as icon-tile categories** — Settings index with circular pastel icon tiles + title + subtitle per category (Look & Feel, Now Playing, Audio & EQ, Personalize, Backup & Restore, About). (Metro)
12. **Display-scale headers** — Oversized rounded-sans screen titles ("Your Mix"-style) with a small subtitle, and tonal circular utility buttons (settings, sort) in the top bar instead of a dense app bar. (PixelPlayer)
13. **Marquee long titles** — Scroll (don't truncate) long track titles in the player and mini-player. (PixelPlayer, per release notes)
14. **Waveform seekbar option** — Offer Namida-style real-waveform seekbar as a Now-Playing alternative to the wavy slider for local files (Vani already computes audio data; cache the waveform).
15. **User-adjustable corner radius** — Expose a "Corner radius" slider in Look & Feel settings driving card/button radii app-wide; it's a PixelPlayer headline feature and cheap to implement in Flutter via a single radius token.

### Color-palette recommendation (moving off all-green monochrome)

Keep the neon-mint as **one of four presets**, all as M3 dark schemes on near-black surfaces, with the Now-Playing screen + mini-player re-tinted from album artwork (PixelPlayer/Namida pattern). All values are dark-scheme roles (surface ≈ #0B0E0C–#141114 family):

| Preset | Seed vibe | primary | primaryContainer | secondary | tertiary | surface tint |
|---|---|---|---|---|---|---|
| **Neon Mint** (current, keep as default) | #00E59B | #00E59B | #00513D | #B0CCC0 | #7DD3FC | green-black #0A0F0D |
| **Plum Wave** (PixelPlayer NP) | #D9A7C0 | #F2B8D3 | #5B2A3E | #D8BFD0 | #B4C5FF | plum-black #141014 |
| **Periwinkle** (PixelPlayer home) | #B4C5FF | #B4C5FF | #2B3A67 | #C0CAD6 | #F2B8D3 | navy-black #0E1116 |
| **Amber Dusk** (Auxio warmth) | #FFB86B | #FFB86B | #5A3410 | #D8C2A8 | #7DD3A8 | umber-black #14100B |

Implementation notes:
- Store presets as `ColorScheme` seeds; generate full M3 dark schemes at runtime (Flutter `ColorScheme.fromSeed(seed, brightness: dark)`), then override `surface` with the tinted near-black for the "Obsidian" feel.
- **Dynamic per-track tint**: on track change, extract the artwork's dominant color (palette_generator, already in Vani's deps per prior work) and lerp the Now-Playing background + mini-player `secondaryContainer` toward it — exactly the PixelPlayer mechanism that kills the flat-monochrome look without abandoning the preset.
- Keep neon-mint as the default preset so existing users see continuity; the other three are one tap away in Look & Feel.

### What this study could NOT verify (gaps)
- PixelPlayer Settings screen layout and Equalizer UI — no public screenshots; only feature-list/changelog claims.
- Queue sheet visuals — confirmed to exist with drag-reorder (release notes), visuals unverified.
- Exact display font name — visually a rounded geometric sans; a third-party port claims Google Sans Flex (unconfirmed officially).
- No public design writeup or review dissecting PixelPlayer's design system was found; the inventory above is reconstructed from screenshots + public release/commit text.
