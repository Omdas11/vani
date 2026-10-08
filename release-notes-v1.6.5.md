# Vani v1.6.5 — navigation regression fixes

Fixes four regressions introduced by v1.6.4's per-tab nested navigators:

- **Settings no longer appears "inside" Home.** The Home header's gear
  button pushed a Settings page onto the Home tab's own navigator, so
  Settings content showed while the dock still had Home selected. The
  gear now jumps to the Settings tab instead.
- **System back works again.** Back now pops the active tab's sub-page
  first, then returns to the Home tab, and only exits the app on a
  double-press (with a "Press back again to exit" toast). Previously
  back always closed the app.
- **Folder import no longer breaks the Library tab.** The "Importing
  folder" dialog was shown on the root navigator but dismissed with a
  tab-context pop, which removed the tab's own page (black/empty tab,
  import option "disappeared") and left the progress dialog stuck open
  at "98 of 98", freezing the app. All root-shown dialogs (import,
  Drive add/index/edit, rename playlist, new playlist) now dismiss via
  the root navigator.
- Nothing else changed: notification code, mini player, and Developer
  Mode are untouched.

**Get it:** `Vani-v1.6.5-arm64.apk` (most phones) from this release's assets.
