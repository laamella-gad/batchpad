# Palettes

The colours `batchpad` uses to draw previews (`png`, `gif`) and to convert
between C64 and C16 projects (`convert` of `.ctt`). Both are VICE 3.9's
internal palettes with VICE's default colour controls, read off a screenshot
of `x64sc` and `xplus4` with the render filter off (`-VICIIfilter 0`,
`-TEDfilter 0`).

- `c64-vice.png`: the 16 C64 colours (`vice` in `src/batchpad/image.nim`).
- `ted-vice.png`: the 128 TED colours (`tedRgb` in `src/batchpad/ctt.nim`);
  chroma 0-F across, luma 0-7 down, the colour number is `luma * 16 + chroma`.
  Chroma 0 is black at every luma.
