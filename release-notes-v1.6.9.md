# Vani v1.6.9 — release notes

Fix release for the three v1.6.8 issues you reported.

## Light theme actually applies
- Look & Feel → Light now renders a proper light app: white background,
  light cards, dark text. Status-bar icons flip to dark so they stay
  visible.
- System and AMOLED modes verified in the theme path too (System follows
  the phone, AMOLED stays pure black).

## Developer options buttons
- The five action buttons (Copy logs, Share log file, Simulate crash,
  Share crash log, Clear) are now proper horizontal pill buttons that
  flow onto multiple lines — no more tall narrow pills with vertical
  unreadable text.

## Mini-player swipe, Spotify-style
- Swiping left/right no longer moves the whole card. Only the track
  identity (artwork + title/artist) slides with your finger; the card
  background, transport buttons and progress line stay fixed.
- Fling to skip: the old content slides out and the next/previous
  track's content slides in. Release without a fling and the content
  springs back.
- Tap / swipe up (open Now Playing) and swipe down (stop + dismiss) are
  unchanged.

**Needs your phone to verify:** Light/System/AMOLED themes rendering on
device, the dev-options button layout, and the new swipe content-slide
feel.
