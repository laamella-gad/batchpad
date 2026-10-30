# CTM V8 test files

Made by us from the V9 files of the same name in `tests/files/ctm9/`: the 19 byte
V9 header is cut to the 14 byte V8 header (the flexi-grid and the key map are
gone, the rest is the same), the blocks are kept as they are. `tests/tctm.nim`
checks that they read back as the V9 projects, without flexi-grid and key map. See
`tests/files/ctm9/README.md` for what they hold.

| File | Version byte |
| --- | --- |
| `mcbitmap_pertile.ctm` | 8 |
| `hirestext_perchar_notiles.ctm` | 82, as in the dropped prototype |
| `mctext_perchar_big.ctm` | 8 |

Not checked in CharPad: no release found reads V8 except CharPad C64 3.0, which
we don't have. Pro 3.88's own V8 loader and saver gave the layout (see
`docs/charpad.md`).
