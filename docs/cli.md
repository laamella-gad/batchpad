# Command line (#55)

How batchpad is meant to be called. `src/batchpad/cli.nim` has every
command and option below, parsed with argparse; `info`, `convert`, `bin`, `asm` and `import` work, the others
say which issue they wait for. Raw binary layouts are in
`src/batchpad/rawbin.nim`, assembler source in `src/batchpad/asmout.nim`. This is the design the exports
(#41-#54, #56, #57) are written against. Decided
2026-10-19; the choices are listed at the end.

## Goals

Batchpad runs inside a build: a Makefile, a shell script, CMake or a CI job.
That gives the rules below.

- Every output file is named on the command line. Batchpad never makes up
  file names, so a build rule knows its outputs without running it. CharPad's
  "Export All" naming (`<name> - Chars.bin`, ...) is not used.
- One call can write several files from one project, so a rule with several
  outputs needs one call.
- Nothing is asked interactively, and there is no "are you sure".
- Exit code 0 on success, 1 on an error in the input or a refusal, 2 on bad
  arguments. Errors go to stderr as `batchpad: <file>: <message>`. Nothing is
  written when there is an error, not even the outputs that were fine.
- Output that is the same as the file already there is not written again, so
  its time stamp stays and make doesn't rebuild what depends on it
  (`--always-write` turns this off).
- `-` as a file name means stdin or stdout.
- What doesn't fit the output is left out without an error (the writer
  policy), but each thing left out is reported on stderr as a warning;
  `--quiet` hides warnings, `--strict` makes them errors. Refusals stay
  errors: a bitmap project to CTM V4 to V7, an ECM project to CTM V4 to V6,
  a char map or over 256 tiles to CTM V4, tiles smaller than 4 x 4 to CTM V1, a cell value that doesn't fit the
  cell width.

## Shape

```
batchpad <command> <input> [<part>=<file> ...] [options]
```

| Command | Does | Issues |
| --- | --- | --- |
| `info` | Prints what a project holds | |
| `convert` | Writes the project in another project format | #6-#40, #56, #57, #64-#66, #74, #75, #79, #80 |
| `bin` | Writes raw binary parts | #41, #44, #45, #54 |
| `asm` | Writes assembler source | #43-#46 |
| `c` | Writes C source for oscar64 | #53 |
| `png` | Writes a preview image | #48, #50 |
| `bmp` | Writes a preview image as a BMP | #72 |
| `gif` | Writes an animated GIF of a SpritePad animation | #49, #50 |
| `stats` | Writes usage statistics | #47 |
| `import` | Builds a project from raw binary parts | #42, #54 |
| `inject` | Puts sprites and a background into a SEUCK game file | #86 |
| `fromimage` | Builds chars and a map, tiles, or sprites, from a picture (BMP or PNG) | #72, #76 |

The input type comes from its contents, not its extension: CTM, SPD,
headerless SPD, `.spr` (recognised by its extension, or `--input-format spr`; with `.spr.inf` next to it when there is one), Spritemate `.spm` (by its extension, or `--input-format spm`), Tilemedo `.tmd` (by its extension and its length field, or `--input-format tmd`; a CharPad project, see [charpad.md](charpad.md)), Petmate `.petmate` (by its extension or contents, or `--input-format petmate`; one screen as a CharPad project, the first unless `--set screen=N`; see [import-export.md](import-export.md#petmate-65)), Tiled `.tmx` or JSON (by its contents or extension, or `--input-format tmx` / `tiled-json`; see [tiled.md](tiled.md)),
CharPad C16 `.ctt` (by its signature, or `--input-format ctt`; colours stay TED colours, 0-127, so `--set` takes those), SEUCK
`.A` or `.B` (by extension and exact size, or `--input-format seuck-a`, `seuck-b`), a `.P00` of one of those (by the name inside it), and the "save all data" `.I` (by extension and size, or a `.P00`; `--input-format seuck-i` for the background, `seuck-i-sprites` for the sprites). `--input-format seuck-b-sideways`
reads the sideways SEUCK `.B`, which looks the same as the normal one.

`batchpad --help`, `batchpad <command> --help`, `batchpad --version`.

## Parts

Parts name the pieces of a project. They are used the same way by `bin`
(`part=file`), `asm`, `c` (`--parts`) and `import`.

CharPad:

| Part | Contents | CharPad name |
| --- | --- | --- |
| `chars` | 8 bytes per char | Chars |
| `char-attribs` | material and colour matrix colour per char | CharAttribs_L1 |
| `char-attribs-l2` | video matrix nibbles per char (bitmap modes) | CharAttribs_L2 |
| `char-materials` | material per char | CharAttribs_M |
| `tiles` | cells per tile | Tiles |
| `tile-attribs` | colour matrix colour per tile | TileAttribs_L1 |
| `tile-attribs-l2` | video matrix nibbles per tile | TileAttribs_L2 |
| `tile-tags` | tag per tile | |
| `tile-names` | names (asm and C only) | |
| `tile-events` | event jump table and `rts` stubs (asm and C only) | |
| `map` | the map, or the area given by `--area` | Map, MapArea |
| `submaps` | flexi-grid sub-maps (#44) | SubMaps, SubMap |
| `colour-map` | colour matrix colour per char cell of the map, or of the area given by `--area` (#45) | ColourMap |
| `triggers` | Tilemedo's trigger map: a byte per map cell, or of `--area` (only projects read from a `.tmd`) | |

SpritePad:

| Part | Contents |
| --- | --- |
| `sprites` | 64 bytes per sprite; 64th byte as `--sprite-attribs` says |
| `sprite-attribs` | the 64th byte per sprite |
| `tiles` | sprite numbers per tile |
| `tile-attribs` | overlay bit per tile |
| `tile-tags` | tag per tile |
| `tile-names` | names (asm and C only) |
| `sprite-anims` | four lists: first frames, last frames, timers, attributes; frames as `--cells` says (8 or `word` only) |
| `tile-anims` | the same for tile animations |

Tiled maps (`bin`, `asm`, `c` only; details in [tiled.md](tiled.md)):

| Part | Contents |
| --- | --- |
| `map`, `map:NAME` | tile numbers of a tile layer (the first, or `--set layer=`; or the one named) |
| `map-flags`, `map-flags:NAME` | flip flags per cell: bit 7 horizontal, 6 vertical, 5 diagonal |
| `tile-tags` | property `tag` per tile of the tileset |
| `tile-names` | tile classes (asm and C only) |
| `objects`, `objects:NAME` | a record per object of an object layer (the first, or the one named) |

Cell parts (`tiles`, `map`, `submaps` and SpritePad `tiles`) in 12- or 16-bit
split form are two files: `map-lo` and `map-hi`. For 12 bit, `map-hi` holds the
packed nibbles. A part a project doesn't have (tiles with the tile system off,
L2 in a text mode) is an error when asked for by name.

`submaps=file` writes them all in one file, as CharPad's consolidated export.
With `{y}` and `{x}` in the name it writes one file per sub-map:
`submaps=build/room_{y}_{x}.bin` (numbers from 0, not padded). Those names
can't be known without reading the project, so that form is for scripts more
than for make; `info` gives `subMapsAcross` and `subMapsDown`.

Sub-maps follow CharPad Pro 3.88: the flexi-grid's cell size cuts the whole map
into whole cells, row by row, and a part cell at the right or bottom is left
out. The grid needn't be switched on, only sized; a V7 project has no size, so
it needs `--set flexi-grid=W,H`. It is an error when no whole cell fits, when
the grid is measured in chars in a project with tiles (as CharPad refuses), and
with `--area`. The one-file form in 12 bit packs the nibbles of all sub-maps
together, so with an odd cell count per sub-map it differs from the per-file
form.

`colour-map` follows CharPad Pro 3.88's ColourMap: one byte per char cell of
the map (tiles expanded, so map size times tile size), row by row,
holding the low nibble of the project's, the tile's or the char's colour
matrix colour as the colouring method says, ready to copy to $d800. A char or
tile number the set doesn't have gives 0. It is always 8 bits a cell whatever
`--cells` says. `--area` (an addition: Pro has none) is in map cells as for
`map`, so with tiles it gives the chars of those tiles. A Petmate screen has a
colour per cell: `colour-map` gives those.

## Options shared by the export commands

| Option | Meaning | Default |
| --- | --- | --- |
| `--cells 8\|12\|16\|word` | Cell width of tiles, map and sub-maps. `word` is one little-endian word per cell, not split. | `8`; a value that doesn't fit is an error |
| `--area X,Y,W,H` | Only this part of the map (MapArea) | whole map |
| `--set <name>=<value>` | Overrides a project setting first (below); can repeat | |
| `--sprite-attribs spritepad\|seuck\|blank` | 64th byte style of `sprites` | `spritepad` |
| `--quiet`, `--strict`, `--always-write` | See Goals | |

Why 8 and refuse, not the smallest width that fits: a fixed width keeps the
layout stable when the project grows past 256 tiles. Picking the width would
change the layout the program reading it expects, without a word. CharPad
writes clipped values with a warning, which trashes the output.

### Project settings that can be overridden

`--set` changes the project in memory before anything is written. It never
changes the input file.

CharPad:

| Name | Values |
| --- | --- |
| `mode` | `hires`, `multicolour`, `ecm`, `hires-bitmap`, `multicolour-bitmap` |
| `colouring` | `project`, `tile`, `char` |
| `bg0` to `bg3` | chip colours $d021-$d024, 0-15 |
| `colour` | project colour matrix colour, 0-15 |
| `vmx-lo`, `vmx-hi` | project video matrix nibbles (bitmap modes) |
| `tiles` | `off` expands the tiles into a char map (see below) |
| `key-map` | 0-15 |
| `flexi-grid` | `W,H` (1-256 each) in the units the project uses, or `off` |
| `screen` | which screen of a Petmate workspace to read, from 0 (read with the file, so only for `.petmate` inputs) |

`tiles=off`: the map becomes a char map of map size times tile size, and the
tile tags and names are dropped. With per tile colouring the colours move to
the chars and the colouring becomes per char: a char used in tiles of different
colours gets a copy (same shape and material) per colour. A flexi-grid in map
cells is multiplied by the tile size. A map cell or tile cell out of range is
an error. The colour map (`bin colour-map`) is the same before and after.

SpritePad:

| Name | Values |
| --- | --- |
| `bg`, `mc1`, `mc2` | 0-15 |
| `sprite-overlay`, `tile-overlay` | overlay distances, -32768 to 32767 |
| `tiles` | `off` |

Tiled maps:

| Name | Values |
| --- | --- |
| `layer` | name of the tile layer `map` uses |
| `tileset` | name of the tileset tile numbers count in |
| `empty-tile` | tile number of an empty cell, 0-65535 |
| `object-units` | `tiles` (default) or `pixels`: units of object positions and sizes |
| `object-fields` | integer properties written after each object, e.g. `hp,speed` |

## Commands

### info

```
batchpad info level.ctm
batchpad info --json level.ctm
```

Format and version, display mode, colouring, colours, counts and sizes of
chars, tiles, map, sprites and animations. `--json` for scripts, for example
to get the sub-map count or the char count into a build.

### convert

```
batchpad convert old.ctm new.ctm [--to ctm1|ctm2|ctm3|ctm4|ctm5|ctm6|ctm7|ctm8|ctm9]
batchpad convert ships.spd ships.A [--to seuck-a]
batchpad convert level.ctm level.B --to seuck-b-sideways
batchpad convert level.tmx level.ctm --base art.ctm
batchpad convert level.ctm level.tmx              # and level.png, the tileset
```

`--to` defaults to the newest version of the output's kind: `.ctm` CTM V9,
`.spd` SPD V5, `.tmd` Tilemedo, `.petmate` Petmate, `.A` and `.B` SEUCK. Versions: `ctm1` to `ctm9`, `ctt8` and `ctt9` (CharPad C16; TED colours from the nearest VICE colour, and a `.ctt` converted to `ctm` goes the other way), `spd0` (SpritePad 1.8, no header), `spr` (SpritePad 1.x, writes `.spr` and `.spr.inf`), `spr12` (Sprite Painter 1.2: the `.inf` holds a colour byte per sprite, then the 3 colours; see spritepad.md), `spm` (Spritemate; leaves out tiles and animations), `tmd` (Tilemedo: needs tiles, no bitmap modes; at most 256 chars and tiles), `petmate` (Petmate: one hires screen of at most 1024 x 1024, tiles expanded, at most 256 chars; no bitmap modes), `tmx` and `tiled-json` (Tiled maps, from each other and from CharPad projects), `seuck-a` (127 sprites; a sprite project), `seuck-b` and `seuck-b-sideways` (a CharPad project with exactly 128 tiles of 5 x 5, 254 chars, per-tile colouring and an 8 x 512 map; sideways: 819 x 5, see import-export.md), `spd1`, `spd2`, `spd3`, `spd4`,
`spd5`, and the others as their readers and writers come (#6-#39). `--set`
works here too.

`--base art.ctm` (#75) turns a Tiled map into any CharPad output: the chars and
tiles of the base project, its map replaced by a tile layer of the map. The
other way, `tmx` or `tiled-json` from a CharPad project writes a Tiled map and its
tileset image (`.png` next to the map). See tiled.md.

### bin

```
batchpad bin level.ctm chars=build/chars.bin tiles=build/tiles.bin map=build/map.bin
batchpad bin level.ctm --cells 16 map-lo=build/map_lo.bin map-hi=build/map_hi.bin
batchpad bin ships.spd sprites=build/ships.bin --load-address 0x2000
```

| Option | Meaning |
| --- | --- |
| `--load-address ADDR` | Writes a 2-byte PRG load address in front of every file (#54). `0x2000`, `$2000` or `8192`. A part can have its own with `part=file@ADDR`. |

### asm

```
batchpad asm level.ctm -o build/level.s
batchpad asm level.ctm -o build/level.asm --dialect kickass --parts chars,map --prefix level_
```

| Option | Meaning | Default |
| --- | --- | --- |
| `-o FILE` | Output | stdout |
| `--dialect` | `64tass`, `acme`, `kickass`, `ca65`, ... (#43) | `64tass` |
| `--parts LIST` | What to include | what CharPad's "Export All (one file)" writes |
| `--prefix TEXT` | Put before every label and constant, so two projects can go in one program | none |
| `--org part=ADDR` | Writes an `addr_` constant and a `* =` (ca65: `.org`) line before that part; can repeat. For split cells `map` names the low half, `map-hi` the high one. | none: the data follows on where the file is included |
| `--segment NAME` | ca65 `.segment`, KickAssembler `.segment`; an error for the others. The program defines the segment: ld65's config, or KickAssembler's `.segmentdef` (KickAssembler refuses one it doesn't know). | none |
| `--cells`, `--area`, `--sprite-attribs` | As for `bin`. Animation frames are bytes with `--cells 8`, words otherwise. | |
| `--event-labels normal\|alt` | `chtl_<name>_event` or `<name>` | `normal` |
| `--no-event-stubs` | Leaves out the `rts` stubs of `tile-events`, so the program can define the labels itself | stubs written |
| `--eol lf\|crlf` | Line endings | `lf` |

Labels and constants follow the newest CharPad and SpritePad Pro template
(`charset_data`, `colr_vic_bg0`, `char_count`, ...). Free 2.86's older
upper-case template is not offered.

Unlike CharPad, every label the file uses is defined, and without `--org` there
are no `* =` lines with dummy addresses, so the file assembles as it is when
included. Split cells get a block each, `map_data_lo` and `map_data_hi` (or
`map_data_hi_packed` for 12 bit), each with its own `size_` constant.

`submaps` writes a block per sub-map with CharPad's labels,
`submap_y{i}_x{j}_data` (or with `_lo`, `_hi`, `_hi_packed`), plus the
constants `submap_wid`, `submap_hei` (cells per sub-map), `submap_count_x` and
`submap_count_y`. `--org submaps=ADDR` puts the `* =` line before the first one
only; the others follow on.

`colour-map` writes `colourmap_data`, as CharPad's text export of the colour
map. It is not in the default parts, as CharPad's Export All leaves it out.

`tile-events` writes CharPad's "Export Tile Events": `chartileset_eventjumptable`,
a `.word` per tile pointing at `chtl_<name>_event` (`<name>` with
`--event-labels alt`), or at `chtl_null_event` (`null_event`) for a tile
without a name, four to a line; then `chartileset_events` with an `rts` stub
for the null event and for each distinct label, in the order the tiles first
use them. A tile name whose label would be the null label shares its stub.
`--org tile-events=ADDR` places the jump table; the stubs follow on. It is not
in the default parts either.

CharPad puts tile names into labels as they are, so a name with a space gives
a file that won't assemble. Ours refuses with an error, naming the tile, when a
label (with `--prefix`) doesn't start with a letter or holds anything but
letters, digits and `_`, or is a register or 6502 mnemonic (illegal ones
included), which only happens with `alt` and no prefix: those break in at
least one dialect, and a leading `_` is a local label in 64tass. Names that
only differ in case are refused too (64tass ignores case), as is any label or
constant the output would define twice, such as an `alt` tile named
`map_data`. Checked 2026-10-19 with all four assemblers.

| Dialect | Constants | Labels | Data | Comments |
| --- | --- | --- | --- | --- |
| `64tass` | `x = 1` | `name` | `.byte` | `;` |
| `acme` | `x = 1` | `name` | `!byte` | `;` |
| `kickass` | `.const x = 1` | `name:` | `.byte` | `//` |
| `ca65` | `x = 1` | `name:` | `.byte` | `;` |

Tile names are written as the bytes stored (ASCII), zero-terminated, with the
name in a comment above, not as strings as CharPad does: an assembler may
translate a string's characters (64tass with `-a`, KickAssembler, ca65 with
`-t c64`), so the bytes would depend on how it is called. Decided 2026-10-19.

Checked 2026-10-19 with 64tass 1.6, ACME 0.97, KickAssembler 5.25 and ca65:
every test file in every cell width gives the same bytes in all four.

### c

```
batchpad c level.ctm -o build/level.c --header build/level.h --prefix level_
```

`-o`, `--parts`, `--prefix`, `--org`, `--cells`, `--area`,
`--sprite-attribs`, `--event-labels`, `--eol` as for `asm` (`--dialect` and
`--segment` don't apply). Same parts, same names, same sizes.

- Constants (`colr_*`, `*_count`, `size_*`, `addr_*`) are `#define`s, hex as `0x..`.
- Data is `__export const unsigned char name[]`, so oscar64 keeps it when the
  program doesn't use it. Animations are one array per list
  (`sprite_anims_from[]`, ...); the sprite image labels `asm` writes inside the
  sprite set are not written.
- Tile names: the bytes, zero-terminated, in `name_data[]`, and
  `const unsigned char * const name[n]` pointing into them. Not strings: oscar64
  translates strings under `-psci`, escapes included.
- Tile events: `void (* const chartileset_eventjumptable[n])(void)` and a
  prototype per event function. The user's code defines the functions;
  `--event-stubs` writes empty ones (off by default, unlike `asm`).
- `--org part=ADDR` puts the part in an oscar64 section of its own, in a region
  of exactly its size (`#pragma section`, `#pragma region`, `#pragma data`), and
  defines `addr_<label>`. Unlike asm, what follows isn't dragged along: the
  section ends after the part (both halves of a split part, and all sub-maps,
  stay together). An address past `$ffff` is an error. Tile names take their
  pointer table with them.
- `--header FILE` (needs `-o`) writes the constants, prototypes and `extern`
  declarations there, and the source includes it by file name (keep the two
  in one directory). The header has `#pragma compile("<source>")`, so a program
  that includes it gets the data without listing the source. Without
  `--header` everything is in the source.
- Names that aren't C names or are C keywords (`--prefix`, tile event labels)
  are errors.

Checked 2026-10-30 with oscar64 1.32: every part compiles, `--org` data is
at its addresses in the PRG.

### png, bmp, gif

```
batchpad png level.ctm map -o map.png [--palette my.pal] [--scale 2]
batchpad bmp level.ctm map -o map.bmp
batchpad png ships.spd sprites -o sheet.png --columns 8
batchpad gif ships.spd -o walk.gif --anim 0 [--scale 2]
batchpad gif ships.spd -o door.gif --tile-anim 1
```

png parts: `chars`, `tiles`, `map` (CharPad); `sprites`, `tiles` (SpritePad).
`bmp` takes the same parts and options and writes the same picture as an
uncompressed 8 bit BMP (40 byte Windows header, the palette's 16 colours, or
TED's 128, as its colour table; rows bottom first, padded to 4 bytes).
The picture is an 8 bit indexed PNG (16 colours) in the C64's own pixels:
8 wide per char, 24 x 21 per sprite, a multicolour pixel two wide. `--scale N`
(1-64) repeats every pixel N times each way. `--columns N` sets the items per
row of a sheet (default 16 chars, 8 tiles or sprites; the rest of the last row
is background). The map is the whole map with tiles expanded. `--palette FILE`
reads a `.pal` file (16 lines of `#RRGGBB`, each with an optional name after
it; blank lines and `;` or `//` lines are skipped); the default is VICE's (the internal VIC-II palette of VICE 3.9, pictured in `docs/palettes/`).
A CharPad C16 `.ctt` gives a 128 colour PNG in the TED palette (from the CTT
spec; `--palette` is refused): in multicolour text bit 3 of the chroma says
multicolour, and in multicolour bitmap pen 11 is chip colour 1 (the C16 has
no colour RAM).
There is no compression yet: files are as big as their pixels.

Colours, as the C64 shows them:

| Mode | Pixel |
| --- | --- |
| hires text | bit 1 colour of the cell, 0 `$d021` |
| multicolour text | colour 0-7: as hires. 8-15: `00` `$d021`, `01` `$d022`, `10` `$d023`, `11` the colour minus 8 |
| ECM text | as hires, with the background `$d021`-`$d024` by the char number / 64; the shape is char & 63: the bytes of chars 64 and up aren't used, see `docs/charpad.md` |
| hires bitmap | bit 1 the high nibble of the cell's screen colour (`vmx-hi`), 0 the low one (`vmx-lo`) |
| multicolour bitmap | `00` `$d021`, `01` high nibble, `10` low nibble, `11` the cell's colour |
| sprite | hires: bit 1 the sprite's colour, 0 the project background. Multicolour: `00` background, `01` multicolour 1, `10` the sprite's colour, `11` multicolour 2 |

The colour of a cell comes from the project's, the tile's or the char's
colours as the colouring method says. In the chars sheet a per tile
colouring has no tile to ask, so the project's colours are used. A map or
tile cell without a tile or char is background. Sprite overlay, expand and
the sprite animations aren't drawn (animations are #49).

gif plays one animation of a SpritePad project: `--anim N` a sprite animation,
`--tile-anim N` a tile animation (numbers from 0, as `info` counts them). The
frames go from the animation's first to its last number (downwards when the
last is lower), with ping-pong back to just after the first, and the GIF
repeats forever. A frame is shown for the animation's timer reload times
`--tick` milliseconds (default 20, one PAL frame; it is not known whether
SpritePad counts something else), at least 2 hundredths of a second, as
viewers show less as 10. Sprites and tiles with overlay have the sprite or
tile at the overlay distance drawn over them, its background pixels left
transparent. `--palette`, `--scale` and the colours are as for png; expand
flags aren't drawn.

### stats

```
batchpad stats level.ctm -o stats.txt [--of chars|tiles] [--eol lf|crlf]
```

Plain text, for CharPad projects. `--of chars` (the default) lists every char
with the number of cells of tiles that use it and of map char cells that use
it (the map with its tiles expanded; just the map without tiles), and counts
the chars that are in neither. `--of tiles` lists every tile with the number of
map cells that use it, and its name. Numbers the project doesn't have (a tile
cell with a char beyond the set, a map cell with a tile beyond the list) are
counted in a line at the end. A project without tiles has no `--of tiles`.

### import

```
batchpad import -o level.ctm chars=chars.bin tiles=tiles.bin map=map.bin \
    --tile-size 4x4 --map-size 64x32 --set mode=multicolour
batchpad import -o ships.spd sprites=ships.bin --sprite-attribs seuck
```

The output kind comes from `-o`'s extension (or `--to`: `ctm1` to `ctm9`,
`spd0`, `spd1`, `spd2`, `spd3`, `spd4`, `spd5`). Parts are the ones `bin` writes, as far as CharPad and
SpritePad import them (`src/batchpad/rawimport.nim`):

- CharPad: `chars` (required), `char-attribs`, `char-attribs-l2`, `tiles`,
  `tile-attribs`, `tile-attribs-l2`, `tile-tags`, `map`; `tiles` and `map` as
  `-lo` and `-hi` for `--cells 12` and `16`. Not `char-materials`, `submaps` and
  `colour-map`, which are for export only.
- SpritePad: `sprites` (required), `sprite-attribs`, `tiles`, `tile-attribs`,
  `tile-tags`. Not the animations.

Options give what CharPad would take from the open project:

| Option | Meaning |
| --- | --- |
| `--tile-size WxH` | Required with `tiles`; an error without them |
| `--map-size WxH` | Required with `map`; the file must hold exactly that many cells |
| `--cells` | As for `bin`; the files for the other widths are an error |
| `--sprite-attribs` | How the 64th byte of each sprite is read: `spritepad` as it is, `seuck` (bit 4 is multicolour, bits 5-7 dropped), `blank` (every sprite multicolour, colour 12). `sprite-attribs=file` replaces it |
| `--load-address skip\|detect\|none` | Skips 2 bytes in every file, skips them when the size says so (2 mod 8 for `chars`, 2 mod 64 for `sprites`; no other part is detected), or never. Default `detect`. The address found is reported on stderr |
| `--set` | Sets project settings before the data is read, so `--set mode=hires-bitmap` allows `char-attribs-l2` |

The project starts as multicolour text with one colour per project (colours
`bg0..bg3` 0, 9, 8, 11 and matrix colour 3, 8, 7 for CharPad; 0, 9, 8 for
SpritePad, overlay distances 1), our choice. Char and tile attributes switch
the colouring to per char or per tile (chars win) unless `--set colouring`
says otherwise. Colours come from the attribute bytes the way `bin` writes
them: `char-attribs` is material (high nibble) and colour (low), the L2 files
are the two bitmap colours. Attribute files must hold one byte per char, tile
or sprite. A file whose size isn't a whole number of chars, sprites, tiles
or cells, a missing `--tile-size` or `--map-size`, and a tile or map cell the
output version can't hold are errors; nothing is written then. What the output
version can't hold is left out and reported on stderr, as for `convert`.

### inject

```
batchpad inject game.I --sprites ships.spd --background level.ctm -o new.I
batchpad inject game.P00 --background level.ctm -o new.P00
```

Puts sprites and a background into a SEUCK "save all data" game file (#86): a
`.I`, or a `.P00` holding one (named `.I`, or of that size). `--sprites` takes
any sprite project, `--background` any CharPad project; give one or both. They
must fit as for `convert --to seuck-a` and `seuck-b` (at most 127 sprites,
padded with empty ones; exactly 128 tiles of 5 x 5, 254 chars, an 8 x 512 map,
per-tile colouring), and what they can't hold is left out with a warning
(`--quiet`, `--strict` as for `convert`). Only the bytes of the sprites (at
`$c000`) and of the map, tile colours, tiles and chars (`$0900`, `$1a00`,
`$f800`) are written; every other byte keeps the game's value, including the
128 unused bytes after the tile colours, the 10 bytes after the chars, bits 5
to 7 of each sprite's 64th byte and the high nibble of each tile colour. A
`.P00` keeps its header. Animations and the rest of the game are not touched
(#85, #84).

### fromimage

```
batchpad fromimage title.bmp -o title.ctm [--set mode=multicolour] [--set bg0=6]
batchpad fromimage ships.bmp -o ships.spd [--sprites any|hires|multicolour] [--set bg=0]
batchpad fromimage tileset.png -o level.ctm --tiles 2x2
```

Cuts a picture into a project (#72). The output's extension (or `--to`, as for
`import`) says what: a CharPad project gets chars and a map (8 x 8 cells),
a SpritePad project sprites (24 x 21 cells), both read row by row from the top
left. Cells on the right and bottom edge that the picture doesn't fill are
padded with the background colour.

The picture is a BMP or a PNG (told apart by their first bytes). BMP: 1, 4, 8,
16, 24 or 32 bits per pixel, uncompressed (16 and 32 bits may have bit field
masks), with a Windows or OS/2 header; RLE is refused. PNG (#76): every colour
type and bit depth, interlaced or not; transparency is ignored (a pixel counts
with its colour), and so are gamma and colour profiles. Each pixel becomes the nearest colour of the palette (VICE's, or
`--palette FILE`; distance in RGB). `--scale N` reads a picture that was
enlarged N times (the top left pixel of each N x N block counts); its size
must be a multiple of N. Multicolour pixels are two picture pixels wide, so a
multicolour picture as `png` or `bmp` draws it reads back as it was.

CharPad: hires text unless `--set mode=multicolour`; ECM and the bitmap modes
are not done yet. The colouring is per char. `bg0` (and in multicolour `bg1`,
`bg2`) are the colours given with `--set`, else the most used colours of the
picture, in that order. Each cell takes the char colour (and, in multicolour,
hires or multicolour: colour 0-7, or 8-15 for multicolour) that is closest to
the picture, summed over its pixels; equal chars with equal colours are made
once. There is no limit on the number of chars: the output version leaves out
what it can't hold, with a warning (`--quiet`, `--strict` as for `convert`).

`--tiles WxH` (#76) reads the picture as a tileset image, e.g. the PNG a Tiled
tileset names: the chars are grouped into tiles of W x H chars, numbered row by
row as Tiled numbers a tileset's tiles (equal tiles stay separate, so the
numbers match), and the map shows each tile once, where the picture has it. The
picture must be a whole number of tiles; Tiled's margin and spacing are not
handled. Then `convert level.tmx level.ctm --base tileset.ctm` puts a Tiled map
on those tiles (see tiled.md). As shared colours are picked from the picture,
give them with `--set` when they matter.

SpritePad: each sprite is hires or multicolour, whichever is closer (or only
the one `--sprites` names). `bg`, `mc1` and `mc2` come from `--set`, else the
most used colours. A sprite's own colour is any of the 16. No tiles or
animations are made.

## In a build

Make, with 64tass:

```make
build/level.s: assets/level.ctm
	batchpad asm $< -o $@ --prefix level_

build/chars.bin build/map.bin &: assets/level.ctm
	batchpad bin $< chars=build/chars.bin map=build/map.bin

game.prg: main.s build/level.s build/chars.bin build/map.bin
	64tass -o $@ main.s
```

ca65 / cc65:

```make
build/sprites.s: assets/ships.spd
	batchpad asm $< -o $@ --dialect ca65 --segment SPRITES --prefix ships_
```

oscar64:

```make
build/level.c build/level.h &: assets/level.ctm
	batchpad c $< -o build/level.c --header build/level.h --prefix level_
```

Or keep the data binary and `#embed` it (works in oscar64 1.32, but gives no constants):

```c
static const char charset[] = {
    #embed "build/chars.bin"
};
```

## Decisions

Made 2026-10-19:

1. What is left out is reported on stderr as a warning; `--quiet` hides
   warnings, `--strict` makes them errors.
2. `--cells` defaults to 8; a value that doesn't fit is an error.
3. One `bin` call writes as many files as it is given.
4. `asm` writes no `* =` lines unless `--org` asks for them.
5. Text output has LF line endings; `--eol crlf` for CRLF.
6. Assembler output follows the newest CharPad and SpritePad Pro template
   only; there is no option for Free 2.86's.
