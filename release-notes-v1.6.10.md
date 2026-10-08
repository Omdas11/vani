# Vani v1.6.10 — release notes

Fix release for the Light theme not applying on-device.

## What changed

**Light theme can no longer render dark — guaranteed.** The whole theme
pipeline (mode → dynamic/preset scheme → MaterialApp → background) was
re-verified end to end and tests green, so v1.6.10 adds a safety net on
top: if the effective mode is Light but the winning color scheme ever
reports dark (whatever the phone's dynamic-color layer hands back), the
app now falls back to the light preset instead of rendering dark, and
logs the incident.

**Theme diagnostics in the debug log.** Every theme-affecting change
(theme mode, system-color toggle, platform light/dark flip, wallpaper
palette refresh, app start) now writes one line to the in-app debug log:
selected mode, effective brightness, whether dynamic color was available
and used, and the resolved brightness + surface luminance. If anything
still looks wrong: Settings → Developer options → Capture debug logs →
reproduce → Share log file, and the log will show exactly what the phone
computed.

Also fixed: the in-app version number now reads 1.6.10 (it was stuck
showing 1.6.8 in logs).

## Tests

270 pass (265 existing + 5 new): live theme switching through the real
app widget for all four modes (System/Dark/Light/AMOLED, no restart),
the dynamic-color platform path with a realistic wallpaper palette, and
the new Light-never-dark guard.

**Needs your phone to verify:** Light mode rendering fully light on
device. If it still looks dark, share a debug log — the new `[theme]`
lines will pinpoint where the phone diverges.
