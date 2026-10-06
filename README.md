# Darktide mods

An automatically synchronized collection of [LucLeto's](https://github.com/LucLeto) Warhammer 40,000: Darktide mods, primarily intended as a source and reference library for other modders. Cloning this repository provides the actual mod files, ready for code search and IDE indexing.

| Display name | Directory | Source repository |
| --- | --- | --- |
| Radar | [`Radar/`](Radar/) | [LucLeto/darktide-mods-radar](https://github.com/LucLeto/darktide-mods-radar) |
| Icon Browser | [`IconBrowser/`](IconBrowser/) | [LucLeto/darktide-mods-icon-browser](https://github.com/LucLeto/darktide-mods-icon-browser) |
| Overflow Meter | [`OverflowMeter/`](OverflowMeter/) | [LucLeto/darktide-mods-overflow-meter](https://github.com/LucLeto/darktide-mods-overflow-meter) |
| Show CJK Glyphs Plus | [`ShowCnJaKoGlyphsPlus/`](ShowCnJaKoGlyphsPlus/) | [LucLeto/darktide-mods-show-cjk-glyphs-plus](https://github.com/LucLeto/darktide-mods-show-cjk-glyphs-plus) |
| Perfect Thrust | [`PerfectThrust/`](PerfectThrust/) | [LucLeto/darktide-mods-perfect-thrust](https://github.com/LucLeto/darktide-mods-perfect-thrust) |

The individual source repositories remain the canonical development repositories. Please send issues and pull requests for a specific mod to its source repository. Treat the mirrored mod directories here as read-only: direct edits will be overwritten by synchronization.

GitHub Actions checks the sources' current default branches once per hour, at minute 17 UTC, and also supports manual synchronization. Only the mapped mod directories and their upstream licenses are copied. Changes flow exclusively from the individual repositories into this collection; nothing is synchronized back. [SOURCES.md](SOURCES.md) records the exact upstream revisions currently mirrored. When those revisions and files are unchanged, synchronization creates no commit.

Each mirrored mod retains the license of its original source repository. The separate, unmodified license texts are preserved under [LICENSES/](LICENSES/), named after each mod directory. There is no blanket root license covering the collection.
