# CTM V5 test files

Made by us from the V7 files of the same name in `tests/files/ctm7/` (read by a
throwaway script and written out in the V5 layout of `docs/charpad.md`), apart
from `mctext_expanded.ctm`. `tests/tctm.nim` checks that they read back as the V7
projects, without tile tags and names and without $d024. See
`tests/files/ctm7/README.md` for what they hold.

| File | Holds |
| --- | --- |
| `mctext_pertile.ctm` | multicolour text, per tile, 4 tiles of 2 x 2, 6 x 3 map |
| `hirestext_perchar_notiles.ctm` | hires text, per char, tile system off (tile fields 0, as CharPad 2.x writes them), 6 x 2 map of chars |
| `mctext_expanded.ctm` | CHAREX flag set, so no tile data: 8 chars (the 6 of the others, a stripe and a ball), 2 tiles of 2 x 2 holding chars 0-3 and 4-7, material = char number, per project, colour 7, 3 x 2 map `0 1 1 / 1 0 0` |

Not checked in CharPad itself. 640 of the 708 V5 files in the CharPad 2.x downloads (not in
the repo) read and write back to the same bytes; the others differ only in the
tile size fields of projects without tiles.
