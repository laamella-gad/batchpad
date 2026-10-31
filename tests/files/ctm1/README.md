# CTM V1 test files

Made by us with a throwaway script that wrote them in the V1 layout of
`docs/charpad.md`: 20-byte header, chars of 8 bytes, 4 x 4 tiles with a byte
per cell, a colour byte per tile cell or per tile when the colouring says so,
and a byte map. All hold 4 chars, 2 tiles and a 3 x 2 map `0 1 1 / 1 0 0`.
Chars: blank, `$55 $aa` rows, a frame, `$1b` rows. Tile 0 is chars 0 1 2 3
repeated on every row, tile 1 is 3 2 1 0.

| File | Holds |
| --- | --- |
| `mctext_project.ctm` | multicolour, `$d021`-`$d023` 6 11 12, one colour 14 for the project |
| `hires_pertile.ctm` | hires, colouring per tile: tile colours 5 and 10 |
| `mctext_pertilecell.ctm` | multicolour, colour per tile cell: tile 0 colours 1 2 9 1 per row, tile 1 colours 1 7 9 1. Chars 1 and 2 are used in two colours each, so we read 6 chars |

Checked against the three samples of CharPad 1.0 (not in the repo): the one
that comes with it and two the user saved (per tile, per tile cell). All read
and write back byte for byte. Not checked in CharPad itself.
