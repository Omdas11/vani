# Vani v1.6.7 — notification transport buttons fixed

**The headline:** the notification/shade media controls finally work. Root cause, found via
`aapt2 dump resources` on the v1.6.6 APK: the `audio_service` notification icon drawables
(`audio_service_pause`, `audio_service_play_arrow`, `audio_service_stop`,
`audio_service_skip_previous`, `audio_service_skip_next`, rewind, fast-forward) were missing
from the APK entirely — the plugin resolves them at runtime with
`Resources.getIdentifier()`, which is invisible to AGP's resource shrinker, so
`optimizeReleaseResources` stripped all 7 icons (42 resource entries: present after link,
gone after optimize). At runtime `getResourceId()` returned 0, notification actions got
null icons, and Android 11+'s media carousel — which renders its buttons from the
notification's actions — showed zero buttons, while metadata and the seek bar worked fine.

**The fix:**
- The 35 icon PNGs (7 icons × 5 densities) are now bundled in
  `app/android/app/src/main/res/drawable-*/`.
- New `app/android/app/src/main/res/xml/keep.xml` with
  `tools:keep="@drawable/audio_service_*"` so the shrinker can never strip them again.
- Verified headless: `aapt2 dump resources` on the final arm64 APK lists all 7 drawables.

Also: version bumped to 1.6.7+16 (versionCode 2016); dev-log version constant synced.

**Still needs the phone:** play a track and check the notification shade / Quick Settings
media card — play/pause, previous, next should now appear. This is the final judge.
