# CTM V7 test files

Made by us, byte by byte from the V7 layout in `docs/charpad.md`; `tests/tctm.nim`
checks that they read back as described here. V7 is what CharPad Free 2.86
saves.

All four share the chars, tiles and maps of the V9 files (see
`tests/files/ctm9/README.md`): 6 chars, each with its char number as material;
4 tiles of 2 x 2 named empty, solid, box, bands with tags 0 to 3 and a 6 x 3
map; or, with the tile system off, a 6 x 2 map of chars.

V7 has no bitmap modes, so every char, tile or project has one colour (colour
RAM). The char colour shares the attribute byte with the material; in the files
not coloured per char it is 0. The header's project colour is only used when
colouring is per project.

| File | Display mode | Colouring | $d021-$d024 (just $d021 if one) | Project colour | Per tile / per char |
| --- | --- | --- | --- | --- | --- |
| `mctext_pertile.ctm` | multicolour text | per tile | blue, dark grey, grey, black | light blue | Tile 0: 9, 1: 10, 2: 13, 3: 15. 8-15 make the cells multicolour, and pixel pair 11 then shows the colour & 7: white, red, green, yellow. |
| `hirestext_perchar_notiles.ctm` | hires text | per char | black | white | Char 0 white (1), 1 red (2), 2 green (5), 3 yellow (7), 4 light green (13), 5 light blue (14). |
| `hirestext_perproject.ctm` | hires text | per project | blue | yellow (7), all chars | - |
| `ecm_perproject_notiles.ctm` | ECM text | per project | black, red, green, blue | white (1), all chars | -. CharPad Free 2.86 has no ECM and opens it as hires text with a warning; check it in CharPad Pro. |

## Checked in CharPad

Opened in CharPad and found to look as described above:

- `mctext_pertile.ctm` (2026-10-18), in CharPad Free 2.86 (which does not
  show tags) and in Pro 3.88, apart from tile 1's tag (see below)
- `hirestext_perchar_notiles.ctm` (2026-10-19), in CharPad Free 2.86
- `hirestext_perproject.ctm` (2026-10-19), in CharPad Free 2.86
- `ecm_perproject_notiles.ctm` (2026-10-18), in CharPad C64 Pro 3.88

CharPad Pro 3.88 shows tile 1's tag as 0 in the files with tiles, because of a
CharPad bug (see `docs/charpad.md`, "What has been checked in CharPad itself").
The files hold tag 1.
