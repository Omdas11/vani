# Bottom Nav + Mini-Player Patterns — Open-Source Android Players Research
Research date: 2026-10-07. Sources: GitHub READMEs (raw), README screenshots (visually inspected), and source layouts/code. Screenshots saved in `./screenshots/`.

Key surprise: **none of the six ships a floating bottom navigation dock.** All use either a flat edge-to-edge M3 nav bar or no bottom nav at all. The floating card pattern lives in their **mini-players** (Namida, Retro Music).

---

## Per-app findings

### 1. Retro Music Player (5.3k stars, active)
- **Bottom nav:** Full-width FLAT Material 3 `BottomNavigationView` pinned to the bottom edge — not floating, not detached. 5 destinations (Home/Songs/Albums/Artists/Playlists); active item gets the M3 pill-shaped tonal indicator + label below it; inactive items icon-only. Evidence: fastlane screenshots 2.jpg & 5.jpg (visually confirmed); `app/src/main/res/layout/sliding_music_panel_layout.xml` (`TintedBottomNavigationView`, style `Widget.Material3.BottomNavigationView`, `layout_gravity="bottom"`).
- **Mini-player:** Material3 bottom sheet (`BottomSheetStyle`, parent `Widget.Material3.BottomSheet`, medium rounded corners → rounded top corners) layered ABOVE the nav bar. Collapsed bar: rounded artwork thumb, marquee title, prev/play/next. Swipe-up/tap expands to full player. 10+ player themes including a "Blur" theme. Evidence: `sliding_music_panel_layout.xml` (BottomSheetBehavior + miniPlayerFragment); styles.xml; screenshots.
- **M3 notes:** README headline "🆕 Material You Design Music Player"; "Material You support on Android 12+".

### 2. Phonograph (archived)
- **Bottom nav:** NONE. Top TabLayout (SONGS/ALBUMS/ARTISTS/PLAYLISTS) under the toolbar + navigation drawer. Evidence: `art/art.jpg`.
- **Mini-player:** Edge-to-edge bottom bar docked above system nav — artwork thumb, title/artist, expand chevron, play/pause; expands to player. Evidence: `art/art.jpg`.
- **M3 notes:** none (2017-era Material 1 design).

### 3. Auxio (4.3k stars)
- **Bottom nav:** NONE. Top TabRow tabs (Artists/Albums/Songs/Playlists/Genres) under the app bar. Evidence: `shot1.png`, `shot2.png` (promo "Form and function with Material You").
- **Mini-player:** Bottom-docked compact bar — artwork thumb, title/artist, play/pause + next buttons, **thin linear progress bar along the bar's bottom edge**. Drag-up expands to a playback-panel bottom sheet (`colorSurfaceContainerLow` background, rounded top corners when roundMode on). Evidence: `shot3.png` (queue + mini bar); `PlaybackBottomSheetBehavior.kt`; `PlaybackBarFragment.kt`.
- **M3 notes:** README "Snappy UI derived from the latest Material Design guidelines"; dynamic Material You theming (purple/green/orange accents across promo shots).

### 4. Namida (6.6k stars — most-starred; **built in Flutter**)
- **Bottom nav:** Flat edge-to-edge Flutter M3 `NavigationBar` — not floating. 6–7 destinations with icon+label (Home, Tracks, Artists, Albums, Playlists, Genres, Folders); custom pill-ish active indicator. Evidence: `screens/collection_light_1.jpg` (3 phones, visually confirmed); `lib/ui/pages/main_page.dart` (`_CustomNavBar` using `NavigationBar`, indicator borderRadius 16/24).
- **Mini-player:** **Floating rounded card ABOVE the nav bar** — inset side margins, large corner radius, soft shadow. Contains rounded artwork thumb, title/artist, prev/play/next + circular play button, **thin progress line at the card's bottom edge**. Drag-up with springy physics expands to full player (`MiniPlayerController`; README credits @cameralis for the miniplayer physics). "Miniplayer Party Mode": edge breathing glow effect with static or artwork-derived dynamic colors. Evidence: `collection_light_1.jpg`, `collection_light_2.jpg`; `lib/main_page_wrapper.dart` (MiniPlayerParent stacked bottom-center); README feature list ("Dynamic Theming, Player Colors are picked from the current album artwork").
- **M3 notes:** README "Material3-like Theme"; dynamic artwork-derived theming.

### 5. Metro (1.6k stars)
- Fork of Retro Music Player. README: "Minor differences in UI" vs Retro — same pattern: flat full-width M3 bottom nav + rounded-corner bottom-sheet mini-player above it. Evidence: README "Differences between Metro and RetroMusicPlayer" section; screenshot section mirrors Retro's layout.
- **M3 notes:** "Material You support on Android 12+"; "Monet themed icon support on Android 13+".

### 6. Vinyl Music Player (994 stars)
- Fork of Phonograph — same architecture: `DrawerLayout` + top tabs, **no bottom nav**. Edge-to-edge bottom mini-player bar with expand chevron. Evidence: `app/src/main/res/layout/activity_main_drawer_layout.xml`; README "Forked from Phonograph; makes all Pro features free, as they used to be".
- **M3 notes:** none.

---

## Ranked recommendation: 6 patterns for the M3 Expressive floating dock (Flutter)

1. **Floating mini-player card above the dock (Namida pattern)** — rounded card (~20–24dp radius), 12–16dp side margins, soft shadow, rounded artwork thumb + title/artist + prev/play/next, thin linear progress line at the card's bottom edge. This is the single most distinctive floating pattern in the research and comes from the most-starred app (6.6k). Bonus: Namida is Flutter — `lib/packages/miniplayer.dart` and `MiniPlayerController` are directly crib-able for the drag physics.
2. **Floating dock: detached tonal pill bar (M3 Expressive)** — no app in the survey floats its nav bar, but all six converge on rounded-corner tonal M3 containers, so the Expressive dock is: `colorSurfaceContainer`, 24–28dp corner radius, ~12dp side margins + 12dp bottom inset, tonal elevation/shadow. (Retro/Auxio prove the tonal-surface look; Namida proves users love floating cards.)
3. **Active-indicator pill in the dock (Retro Music M3 pattern)** — M3 pill indicator (`secondaryContainer`) on the active destination, label under the active item only, icon-only inactives. Proven by Retro (5.3k stars).
4. **Swipe-up-to-expand from mini bar → full player (unanimous)** — Retro, Auxio, and Namida all expand the mini-player via upward drag into a rounded-corner bottom sheet. In Flutter: `DraggableScrollableSheet` or Namida's MiniPlayerController approach.
5. **Thin linear progress on the mini-player (Auxio + Namida consensus)** — progress as a slim line along the card's bottom edge rather than a circular ring; cleaner and trivial in Flutter (`LinearProgressIndicator` with custom track).
6. **Artwork-derived dynamic color on mini-player/dock (Namida + Retro)** — Namida tints the player from album artwork; Retro uses Material You dynamic color. For Expressive: `palette_generator` → tint dock container/accent. Optional flourish: Namida's "Party Mode" edge-breathing glow on the mini-player for the now-playing accent.

### Honest caveats
- **Blur/glass:** none of the six uses real glassmorphism on the mini-player or bottom nav (Retro's "Blur" is a now-playing theme only). If glass is wanted in OpenTune, it would be an addition beyond what these apps ship — use `BackdropFilter` sparingly.
- Phonograph is archived (read from `kabouzeid/Phonograph` master README + art).
- Metro's README claims only "minor differences in UI" vs Retro; screenshots mirror Retro's, so its patterns are treated as identical.
- Method: READMEs, screenshots (visually inspected, saved here), and source layouts/code (Retro's `sliding_music_panel_layout.xml` + styles, Auxio's `PlaybackBottomSheetBehavior.kt`, Namida's `main_page.dart` + `main_page_wrapper.dart`). No features were inferred beyond what these show.
