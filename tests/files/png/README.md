# PNG test files

Made by us: `tests/files/bmp/mc24.bmp` and `hires1.bmp` (previews of our own
test projects) saved as PNG by ImageMagick 6.9.12 (`convert`), so the reader is
checked against a writer that isn't ours. `tests/tpicture.nim` checks each reads
back as the preview.

| File | PNG kind | Made with |
| --- | --- | --- |
| `mc4.png` | 4 bit palette | `-define png:bit-depth=4 -define png:color-type=3` |
| `mc8.png` | 8 bit palette | `PNG8:` |
| `mc24.png` | 8 bit RGB | `PNG24:` |
| `mc32.png` | 8 bit RGBA | `-alpha on PNG32:` |
| `mc48.png` | 16 bit RGB | `-depth 16 PNG48:` |
| `mcinter.png` | 8 bit RGB, Adam7 interlaced | `-interlace PNG PNG24:` |
| `hires1.png` | 1 bit grey (from `hires1.bmp`) | `-type Bilevel PNG:` |

Damaged PNGs are made in the test itself.
