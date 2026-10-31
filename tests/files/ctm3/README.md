# CTM V3 test files

Made by us from the V4 files in `tests/files/ctm4/` (a throwaway script cut
the V4 header down to V3's 20 bytes, with the map size first and one square
tile size, and left out the attribute byte per char). They hold the same
projects as the V4 files; see `tests/files/ctm4/README.md`. V3 has colour and
material per tile cell, like V4, and always has tiles.

| File | Holds |
| --- | --- |
| `mctext_pertile.ctm` | as `ctm4/mctext_pertile.ctm` |
| `hires_pertilecell.ctm` | as `ctm4/hires_pertilecell.ctm` |
| `mctext_expanded.ctm` | as `ctm4/mctext_expanded.ctm` |

Not checked in CharPad itself: no release writes V3, so only the layout from
`docs/charpad.md` backs them.
