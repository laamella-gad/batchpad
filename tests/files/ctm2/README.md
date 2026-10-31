# CTM V2 test files

Made by us from the V4 files in `tests/files/ctm4/` (a throwaway script wrote
them out in the V2 layout of `docs/charpad.md`: 20-byte header, chars of 9 bytes
with the material as the 9th, tiles with a word per cell, a colour per tile only
when colouring is per tile, a byte map). V2 has no CHAREX flag, so the expanded
file holds its tile data in full.

| File | Holds |
| --- | --- |
| `mctext_pertile.ctm` | as `ctm4/mctext_pertile.ctm` |
| `mctext_expanded.ctm` | as `ctm4/mctext_expanded.ctm`, colouring per project |

The layout is checked against the 25 distinct V2 samples of the CharPad 1.7
download (not in the repo): all read, and 23 write back byte for byte. The
other two (SEUCK examples) have bit 4 set in some tile colour bytes, which we
mask as CharPad Pro does. Not checked in CharPad itself.
