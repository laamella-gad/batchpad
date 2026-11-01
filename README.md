# BatchPad

Command-line tool that converts CharPad and SpritePad project files into
artifacts (e.g. binary data, source includes) that can be consumed by build
pipelines.

## Download

Get the latest build from the [releases page](https://github.com/laamella-gad/batchpad/releases/latest):

- [Linux](https://github.com/laamella-gad/batchpad/releases/latest/download/batchpad-linux.tar.gz)
- [Windows](https://github.com/laamella-gad/batchpad/releases/latest/download/batchpad-windows.zip)
- [macOS](https://github.com/laamella-gad/batchpad/releases/latest/download/batchpad-macos.tar.gz)

The macOS build is for Apple silicon. Or build it yourself with `nimble build`
(Nim 2.2.8 or later); the binary lands in `bin/`.

## Commands

```sh
batchpad info level.ctm                          # what a project holds
batchpad convert level.ctm level.ctt             # between formats and versions
batchpad bin level.ctm chars=chars.bin map=map.bin
batchpad asm level.ctm -o level.s                # assembler source
batchpad c level.ctm -o level.c --header level.h # C source for oscar64
batchpad png level.ctm map -o map.png            # previews
batchpad gif ships.spd -o walk.gif --anim 0
batchpad stats level.ctm                         # usage text
batchpad import -o level.ctm chars=chars.bin map=map.bin
```

Inputs: CharPad `.ctm`, CharPad C16 `.ctt`, SpritePad `.spd` and `.spr`,
Spritemate `.spm`, Tiled `.tmx` and JSON, SEUCK `.A` and `.B`. The design is in
[docs/cli.md](docs/cli.md). Previews use VICE's palettes, pictured in
[docs/palettes](docs/palettes/).

## Supported formats

Details per family: [CharPad](docs/charpad.md), [SpritePad](docs/spritepad.md),
[Tiled](docs/tiled.md), [import and export](docs/import-export.md). "Checked"
means every file of that version that came with the original programs reads
correctly. Without it, the format follows the program's documentation (or
decompiled code) only. Each CharPad and SpritePad release also reads all older
versions.

| Format | Introduced in | Read | Write | Remarks |
|---|---|---|---|---|
| **CharPad** | | | | |
| CTM V1 | CharPad 1.0 | yes | yes | Checked (1 file, and 2 saved from CharPad 1.0) |
| CTM V2 | CharPad 1.7 | yes | yes | Checked (24 files) |
| CTM V3 | CharPad 1.8 before Rev 3 | yes | yes | No program found that writes it, so no files to check |
| CTM V4 | CharPad 1.8 Rev 3 | yes | yes | Checked (110 files) |
| CTM V5 | CharPad 2.0 | yes | yes | Checked (292 files) |
| CTM V6 | CharPad 2.6 ("Thalamus" edition) | yes | yes | Checked (13 files) |
| CTM V7 | CharPad 2.8 | yes | yes | Checked (277 files); what CharPad Free 2.86 saves |
| CTM V8 | CharPad C64 3.0 | yes | yes | No files to check: only paid builds no longer sold wrote it (Pro 3.88 can still export it). The version byte may be 82, from a dropped prototype |
| CTM V9 | CharPad C64 Pro 3.5 | yes | yes | Checked (663 files); what CharPad Pro saves |
| **CharPad C16** | | | | |
| CTT V8 | CharPad C16 3.4 | yes | yes | No files to check. TED colours; `png`, `gif` and `stats` don't take it yet (#81) |
| CTT V9 | CharPad C16 3.5 | yes | yes | Checked (807 files). As V8; adds the key map |
| **SpritePad** | | | | |
| `.spr`, no `.spr.inf` | Sprite Painter 1.0 | yes | no | No colours; writing always makes an `.inf` too. No files to check |
| `.spr` + 3-byte `.spr.inf` | SpritePad 1.3 | yes | yes | Checked (4 files). Sprite Painter 1.2's own `.inf` is not read (#24) |
| `.spd` without header | SpritePad 1.8 | yes | yes | Checked (10 files). Has no documentation; worked out from the ReadMe and the files |
| SPD V1 | SpritePad 2.0 | yes | yes | Checked (13 files) |
| SPD V2 | SpritePad 2.3 | yes | yes | Checked (14 files); adds tiles |
| SPD V3 | SpritePad 2.8 | yes | yes | Never released: no files to check |
| SPD V4 | SpritePad 2.8 | yes | yes | No files to check: only paid builds no longer sold wrote it |
| SPD V5 | SpritePad 2.9 | yes | yes | Checked (112 files); what every Pro release saves |
| **Other editors** | | | | |
| Spritemate `.spm` | Spritemate | yes | yes | Checked (Spritemate's 5 examples). Sprites only: tiles, animations and sprite names aren't kept; older layouts are read too |
| SEUCK `.A` sprites | SEUCK (1987) | yes | yes | Real files read ([details](docs/import-export.md#real-files-checked-2026-11-01)), but none from the original program. Read and written as a sprite project |
| SEUCK `.B` background | SEUCK (1987) | yes | yes | Real files read, as `.A`. Read and written as a CharPad project; also the sideways kind of CharPad 1.7 |
| Tiled `.tmx` | Tiled | yes | yes | No files to check. A map, not a CharPad project: goes to `bin`, `asm` and `c`, and converts to and from JSON; CSV and base64 data, no compression (#77) |
| Tiled JSON (`.tmj`, `.json`) | Tiled | yes | yes | No files to check. As `.tmx` |
| **Exports and imports** | | | | |
| Raw binary (`bin`) | | | yes | Parts such as chars, tiles, map, colours, sprites |
| Raw binary (`import`) | | yes | | Binary parts into a CharPad or SpritePad project |
| Assembler source (`asm`) | | | yes | Dialects 64tass, acme, kickass, ca65 |
| C source (`c`) | | | yes | For oscar64 |
| PNG (`png`) | | | yes | Chars, tiles, map, sprites; `.pal` palette files are read |
| Animated GIF (`gif`) | | | yes | SpritePad animations |
| Usage statistics (`stats`) | | | yes | Text |
