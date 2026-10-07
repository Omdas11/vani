# Music sources for Vani (verified 2026-10-07)

Primary: **Internet Archive advancedsearch API** — keyless. Free Music Archive and Jamendo both require API keys → deprioritized. Jamendo remains an optional secondary source if the user registers a free client_id later.

## License filter (CC0 + CC-BY 4.0/3.0 only)

```
licenseurl:("https://creativecommons.org/publicdomain/zero/1.0/" OR "https://creativecommons.org/licenses/by/4.0/" OR "https://creativecommons.org/licenses/by/3.0/")
```

CC-BY tracks require attribution shown in-app (artist/title/license).

## Genre queries (all verified live; counts = numFound)

- General/trending (CC0): ~62,805 results
  https://archive.org/advancedsearch.php?q=mediatype%3Aaudio+AND+licenseurl%3A%22https%3A%2F%2Fcreativecommons.org%2Fpublicdomain%2Fzero%2F1.0%2F%22&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=licenseurl&rows=50&output=json
- Electronic: ~1,581
  https://archive.org/advancedsearch.php?q=mediatype%3Aaudio+AND+licenseurl%3A%28%22https%3A%2F%2Fcreativecommons.org%2Fpublicdomain%2Fzero%2F1.0%2F%22+OR+%22https%3A%2F%2Fcreativecommons.org%2Flicenses%2Fby%2F4.0%2F%22+OR+%22https%3A%2F%2Fcreativecommons.org%2Flicenses%2Fby%2F3.0%2F%22%29+AND+subject%3Aelectronic&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=licenseurl&rows=50&output=json
- Ambient/chill: ~1,142 — same base + `AND+subject%3Aambient`
- Rock: ~1,468 — same base + `AND+subject%3Arock`
- Jazz: ~39,904 — same base + `AND+subject%3Ajazz` (likely loose tagging/old dumps; curate)
- Classical: ~307 — same base + `AND+subject%3Aclassical`
- Hip-hop: ~670 — same base + `AND+subject%3Ahip-hop`
- Folk/world: ~406 — same base + `AND+subject%3Afolk`

## Verified playable tracks (HTTP 206 + audio/mpeg on range request)

1. "Enchanted Valley" — Ondrosik — CC0
   https://archive.org/download/Ondrosik-Free-music-catalog/Enchanted%20Valley.mp3
2. "A Long Path" — Frank Schlimbach — CC-BY 4.0 (needs attribution)
   https://archive.org/download/monster-in-the-closet-main/A%20Long%20Path.mp3
3. "Amalgam" — Koraii (Birth of Paul, 2023) — CC-BY 4.0 (needs attribution)
   https://archive.org/download/koraii-full-discography/Koraii%20-%20Full%20Discography%20(2016-2023)/Birth%20of%20Paul%20(2023)/1%20-%20Amalgam.mp3

## Artwork

`https://archive.org/services/img/<identifier>` returns 200 + image/jpeg for tested items (item-level cover, not per-track). Keep a local placeholder fallback when no image/* content-type.

## Gotchas

- `collection:netlabels` is unusable under the license constraint (NC/ND dominates) — always apply the license filter.
- Mislabeled uploads exist (e.g. bogus "CC0" claims on commercial albums) — add a curation/blocklist layer, don't blindly play top downloads.
- `/download/<id>/<file>` 302-redirects to `ia*.us.archive.org`; follow redirects.
- `archive.org/metadata/<id>` can transiently return empty JSON — retry in-app.
- CC-BY tracks: show attribution (title/artist/license) in the app UI.
