# Vinyl Now-Playing UI — design notes (v1.2.0)

## Stitch source

- Stitch project: **"OpenTune"** — `projects/449571797836617136`
- Generation session: `5821873937739520377`
- Auto-generated design system: **"Obsidian Sonic"**
  (`assets/e56ea26d0c704a5db84e4cebf6219be3`) — true-black surfaces,
  neon-mint accents, holographic refraction lines, glassmorphism.
- Prompt used: now-playing screen, large rotating vinyl with album art at
  its center, holographic iridescent rainbow shimmer, track title/artist,
  seek bar, shuffle/prev/play/next/repeat, lyrics button, dark premium
  aesthetic, `#0A0A0A` background, `#1DB954` green accent, portrait phone.

## Flutter implementation

`staging/lib/widgets/vinyl_record.dart` (+ wiring in
`staging/lib/screens/player_screen.dart`):

- **Vinyl disc**: black radial-gradient circle; grooves drawn by
  `_GroovePainter` (42 concentric rings, alpha-modulated); diagonal light
  streak rotating with the disc; cover art as the center label inside a
  green ring; spindle hole dot.
- **Rotation**: an `AnimationController` (~14 s/rev — a graceful feel,
  not literal 33⅓ RPM) driven from `PlayerController.isPlaying` via a
  listener — spins only while audio plays, freezes on pause. One
  controller, `RotationTransition`, no extra packages.
- **Holographic effects**: a slow (9 s) `SweepGradient` rainbow sweep
  rotating over the disc at low opacity; an ambient glow behind the disc
  whose hue drifts mint → violet; a rotating iridescent ring behind the
  play/pause button.
- The v1.1.0 live-rebuild fix is preserved: the screen still rebuilds on
  every `PlayerController` tick via `AnimatedBuilder` (seek bar, transport
  state, queue, and the vinyl spin state all stay in sync).
- All existing controls (seek, shuffle/repeat, like, download, lyrics,
  up-next queue, attribution line) are unchanged functionally.
