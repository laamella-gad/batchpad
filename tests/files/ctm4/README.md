# CTM V4 test files

Made by us from the V7 files in `tests/files/ctm7/` (read by a throwaway script
and written out in the V4 layout of `docs/charpad.md`). V4 colours and gives
materials per tile cell, not per char, and always has tiles. `tests/tctm.nim`
checks that they read back as described.

| File | Holds |
| --- | --- |
| `mctext_pertile.ctm` | as `ctm7/mctext_pertile.ctm`: multicolour text, per tile, 4 tiles of 2 x 2, 6 x 3 map (one byte per cell); the cell attribute bytes hold the material only |
| `hires_pertilecell.ctm` | hires text, colouring method 2 (per tile cell): every cell of tile n has colour n + 1, except the first cell of tile 3 (char 5), which has 5; tile 3's last cell is char 5 with colour 4, so the reader makes a copy of char 5 |
| `mctext_expanded.ctm` | CHAREX flag set, so no tile data: 8 chars, 2 tiles of 2 x 2 holding chars 0-3 and 4-7, per project, 3 x 2 map `0 1 1 / 1 0 0` |

Not checked in CharPad itself. 112 V4 samples of CharPad 1.8 and 2.0 (not in the
repo) read, and write back to files that read as the same projects.
