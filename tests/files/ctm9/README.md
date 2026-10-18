# CTM V9 test files

Made by us, byte by byte from the V9 layout in `docs/charpad.md`; `tests/tctm.nim`
checks that they read back as described here.

All five share the same 6 chars, each with its char number as material:

| Char | Pattern |
| --- | --- |
| 0 | empty |
| 1 | solid |
| 2 | checkerboard (`$aa`, `$55`) |
| 3 | box outline |
| 4 | diagonal, top left to bottom right |
| 5 | four bands of two rows: bit pairs 00, 01, 10, 11 (in multicolour: background, $d022, $d023, cell colour) |

The files with the tile system on share 4 tiles of 2 x 2 and a 6 x 3 map:

| Tile | Name | Tag | Cells |
| --- | --- | --- | --- |
| 0 | empty | 0 | 0 0 / 0 0 |
| 1 | solid | 1 | 1 1 / 1 1 |
| 2 | box | 2 | 3 3 / 3 3 |
| 3 | bands | 3 | 5 2 / 2 5 |

Map rows: `1 2 3 1 2 3`, `2 3 1 2 3 1`, `0 1 0 1 0 1`.

The files with the tile system off have a 6 x 2 map of chars: `1 2 3 4 5 0`,
`5 4 3 2 1 0`.

Unless listed, the flexi-grid is CharPad's default (10 x 10, off, thick line)
and there is no key map.

Colours are C64 palette names, with the number in brackets where it helps.
The header always holds the project colours: the char colour (colour RAM),
then screen low and high for bitmap modes. CharPad only uses them when
colouring is per project. In the other files they can't be seen in CharPad at
all (its Colours box shows the selected tile's or char's colours instead), so
only `tests/tctm.nim` checks them.

| File | Display mode | Colouring | $d021-$d024 (just $d021 if one) | Project colours | Per tile / per char |
| --- | --- | --- | --- | --- | --- |
| `mctext_pertile.ctm` | multicolour text | per tile | blue, dark grey, grey, black | light blue | Tile 0: 9, 1: 10, 2: 13, 3: 15. 8-15 make the cells multicolour, and pixel pair 11 then shows the colour & 7: white, red, green, yellow. |
| `hirestext_perchar_notiles.ctm` | hires text | per char | black | white | Char 0 white (1), 1 red (2), 2 green (5), 3 yellow (7), 4 light green (13), 5 light blue (14). |
| `mcbitmap_pertile.ctm` | multicolour bitmap | per tile | black | white, red, cyan | Tiles as colour RAM / screen low / screen high: 0 white / red / cyan (1, 2, 3), 1 purple / green / blue (4, 5, 6), 2 yellow / orange / brown (7, 8, 9), 3 light red / dark grey / grey (10, 11, 12). |
| `hiresbitmap_perchar.ctm` | hires bitmap | per char | black | screen white / black | Chars as screen low / screen high: 0 white / black (1, 0), 1 red / yellow (2, 7), 2 blue / light blue (6, 14), 3 brown / orange (9, 8), 4 dark grey / light grey (11, 15), 5 black / white (0, 1). Flexi-grid on, 3 x 2, thin green line. |
| `ecm_perproject_notiles.ctm` | ECM text | per project | black, red, green, blue | white (1), all chars | -. Key map 9 (C64 ROM upper case). |

## Checked in CharPad

Opened in CharPad C64 Pro 3.88 and found to look as described above:

- `hirestext_perchar_notiles.ctm` (2026-10-18)
- `mctext_pertile.ctm` (2026-10-18), apart from tile 1's tag (see below)
- `mcbitmap_pertile.ctm` (2026-10-18), apart from tile 1's tag
- `hiresbitmap_perchar.ctm` (2026-10-18), flexi-grid included
- `ecm_perproject_notiles.ctm` (2026-10-18), key map included (the Char Set
  window marks screen code 32 as the space char, which comes from the key map)

CharPad shows tile 1's tag as 0 in the files with tiles, because of a CharPad
bug (see `docs/charpad.md`, "What has been checked in CharPad itself"). The
files hold tag 1.
