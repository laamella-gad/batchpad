# BMP test files

Made by us: `batchpad png` previews of our own test projects, saved as BMP by
ImageMagick 6.9.12 (`convert`), so the reader is checked against a writer that
isn't ours. `tests/tpicture.nim` checks each reads back as the preview.

| File | From | BMP kind |
| --- | --- | --- |
| `mc24.bmp` | `ctm9/mctext_pertile.ctm` map (96 x 48) | 24 bit, 40 byte header (`BMP3:`, `-type TrueColor`) |
| `mc4.bmp` | same | 4 bit with a colour table (`BMP3:`, `-type Palette`) |
| `mc32.bmp` | same | 32 bit, bit fields, 124 byte V5 header (`BMP:`, `-type TrueColorAlpha`) |
| `mcos2.bmp` | same | 24 bit, 12 byte OS/2 header (`BMP2:`) |
| `hires1.bmp` | `ctm9/hirestext_perchar_notiles.ctm` map (48 x 16), all colours but black made white | 1 bit (`-type Bilevel`) |
| `sprites.bmp` | `spd5/sprites.spd` sprites, 3 per row (72 x 42) | 24 bit |

8 and 16 bit, top-down and refused files are built in the test itself.
