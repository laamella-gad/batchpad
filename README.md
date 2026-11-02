# BatchPad

BatchPad is the conversion step between the graphics editor and your build. You
draw characters, tiles, maps and sprites in an editor such as
[CharPad](https://subchristsoftware.itch.io/charpad-c64-pro),
[SpritePad](https://subchristsoftware.itch.io/spritepad-c64-pro),
[Spritemate](https://www.spritemate.com/), [Petmate](https://github.com/nurpax/petmate), Tilemedo or [Tiled](https://www.mapeditor.org/)
and keep the project file in your repository.
BatchPad turns that file into what your assembler or compiler wants: raw binary
files to `incbin`, assembler source (64tass, acme, KickAssembler, ca65), or C
source for oscar64. Run it from a makefile or a build script, so the project
file stays the single source and the generated files are never edited by hand.
It also converts between the editors' formats and versions, and makes previews
and usage statistics. For the Shoot 'em-up Construction Kit
([SEUCK](https://www.c64-wiki.com/wiki/SEUCK)) it reads and writes the sprite
and background files, and puts them back into a saved game, so you can draw
them in CharPad and SpritePad instead.

It is meant to work well with AI coding assistants too. Everything is a plain
command with text output: `info` and `stats` describe a project in words, errors
say what is wrong and what to try, the same project file always gives the same
output, and the formats are documented in [docs](docs/), so an assistant can
inspect a binary project file, convert it and wire it into a build without a
GUI.

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
batchpad bmp level.ctm map -o map.bmp
batchpad gif ships.spd -o walk.gif --anim 0
batchpad stats level.ctm                         # usage text
batchpad import -o level.ctm chars=chars.bin map=map.bin
batchpad fromimage title.bmp -o title.ctm       # picture (BMP, PNG) to chars and map
batchpad inject game.I --sprites ships.spd --background level.ctm -o new.I
```

Inputs: CharPad `.ctm`, CharPad C16 `.ctt`, SpritePad `.spd` and `.spr`,
Spritemate `.spm`, Petmate `.petmate`, Tilemedo `.tmd`, Tiled `.tmx` and JSON, SEUCK `.A` and `.B`. The design is in
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
| CTT V8 | CharPad C16 3.4 | yes | yes | No files to check. TED colours; `png` in the TED palette |
| CTT V9 | CharPad C16 3.5 | yes | yes | Checked (807 files). As V8; adds the key map |
| **SpritePad** | | | | |
| `.spr`, no `.spr.inf` | Sprite Painter 1.0 | yes | no | No colours; 63 or 64 bytes per sprite; writing always makes an `.inf` too. No files to check |
| `.spr` + 3-byte `.spr.inf` | SpritePad 1.3 | yes | yes | Checked (4 files) |
| `.spr` + `.spr.inf` with a colour byte per sprite | Sprite Painter 1.2 | yes | yes (`spr12`) | No files to check; layout from the 1.5 ReadMe, colour byte guessed (#24) |
| `.spd` without header | SpritePad 1.8 | yes | yes | Checked (10 files). Has no documentation; worked out from the ReadMe and the files |
| SPD V1 | SpritePad 2.0 | yes | yes | Checked (13 files) |
| SPD V2 | SpritePad 2.3 | yes | yes | Checked (14 files); adds tiles |
| SPD V3 | SpritePad 2.8 | yes | yes | Never released: no files to check |
| SPD V4 | SpritePad 2.8 | yes | yes | No files to check: only paid builds no longer sold wrote it |
| SPD V5 | SpritePad 2.9 | yes | yes | Checked (112 files); what every Pro release saves |
| **Other editors** | | | | |
| Spritemate `.spm` | Spritemate | yes | yes | Checked (Spritemate's 5 examples). Sprites only: tiles, animations and sprite names aren't kept; older layouts are read too |
| Petmate `.petmate` | Petmate | yes | yes | Follows Petmate's source; our own files only. One screen as a CharPad project (`--set screen=N`), the colour per cell as part `colour-map`; the C64 ROM charsets aren't in the file, so those chars are blank |
| Tilemedo `.tmd` | Tilemedo 1.10 | yes | yes | Checked (Tilemedo's 2 examples, byte for byte, and its BMP map exports). Read and written as a CharPad project; the trigger map is part `triggers` |
| SEUCK `.A` sprites | SEUCK (1987) | yes | yes | Checked (the 4 sample games of the original SEUCK disks; [details](docs/import-export.md#the-original-disks)). Read and written as a sprite project; also from a `.P00` or the "save all data" `.I` (read only) |
| SEUCK `.B` background | SEUCK (1987) | yes | yes | Checked (4 files), as `.A`. Read and written as a CharPad project; also from a `.P00` or `.I` (read only); also the sideways kind of CharPad 1.7 |
| Tiled `.tmx` | Tiled | yes | yes | Checked (the 87 example and test maps of the Tiled repository; not opened in Tiled itself). A map, not a CharPad project: goes to `bin`, `asm` and `c`, converts to and from JSON, into a CharPad project's map with `convert --base`, and from a CharPad project with a tileset PNG; CSV and base64 data (zlib and gzip too); external `.tsx` tilesets; object layers as data tables; object templates |
| Tiled JSON (`.tmj`, `.json`) | Tiled | yes | yes | Checked (the one JSON map of the Tiled repository, and all its maps through `convert`). As `.tmx` |
| **Exports and imports** | | | | |
| Raw binary (`bin`) | | | yes | Parts such as chars, tiles, map, colours, sprites |
| Raw binary (`import`) | | yes | | Binary parts into a CharPad or SpritePad project |
| Assembler source (`asm`) | | | yes | Dialects 64tass, acme, kickass, ca65 |
| C source (`c`) | | | yes | For oscar64 |
| PNG (`png`, `fromimage`) | | yes | yes | Chars, tiles, map, sprites; `.pal` palette files are read. Import as BMP, also a tileset image into tiles (`--tiles`) |
| BMP (`bmp`, `fromimage`) | | yes | yes | Export as `png`; import 1-32 bit uncompressed BMPs into text-mode chars and a map, or sprites |
| Animated GIF (`gif`) | | | yes | SpritePad animations |
| Usage statistics (`stats`) | | | yes | Text |
