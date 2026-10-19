# Command line (#55)

How batchpad is meant to be called. `src/batchpad/cli.nim` has every
command and option below, parsed with argparse; `info` and `convert` work, the
others say which issue they wait for. This is the design the exports
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
  errors: a bitmap project to CTM V7, a cell value that doesn't fit the cell
  width.

## Shape

```
batchpad <command> <input> [<part>=<file> ...] [options]
```

| Command | Does | Issues |
| --- | --- | --- |
| `info` | Prints what a project holds | |
| `convert` | Writes the project in another project format | #6-#39, #56, #57 |
| `bin` | Writes raw binary parts | #41, #44, #45, #54 |
| `asm` | Writes assembler source | #43-#46 |
| `c` | Writes C source for oscar64 | #53 |
| `png` | Writes a preview image | #48, #50 |
| `gif` | Writes an animated GIF of a SpritePad animation | #49, #50 |
| `stats` | Writes usage statistics | #47 |
| `import` | Builds a project from raw binary parts | #42, #54 |

The input type comes from its contents, not its extension: CTM, SPD,
headerless SPD, `.spr` (with `.spr.inf` next to it when there is one), SEUCK
`.A` or `.B`. `--input-format` forces it (needed for the sideways SEUCK `.B`,
which looks the same as the normal one).

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
| `tile-events` | event jump table (asm and C only, #46) | |
| `map` | the map, or the area given by `--area` | Map, MapArea |
| `submaps` | flexi-grid sub-maps (#44) | SubMaps, SubMap |
| `colour-map` | colour matrix colour per char cell (#45) | ColourMap |

SpritePad:

| Part | Contents |
| --- | --- |
| `sprites` | 64 bytes per sprite; 64th byte as `--sprite-attribs` says |
| `sprite-attribs` | the 64th byte per sprite |
| `tiles` | sprite numbers per tile |
| `tile-attribs` | overlay bit per tile |
| `tile-tags` | tag per tile |
| `tile-names` | names (asm and C only) |
| `sprite-anims` | four lists: from, to, timer, attributes |
| `tile-anims` | the same for tile animations |

Cell parts (`tiles`, `map`, `submaps` and SpritePad `tiles`) in 12- or 16-bit
split form are two files: `map-lo` and `map-hi`. For 12 bit, `map-hi` holds the
packed nibbles. A part a project doesn't have (tiles with the tile system off,
L2 in a text mode) is an error when asked for by name.

`submaps=file` writes them all in one file, as CharPad's consolidated export.
With `{y}` and `{x}` in the name it writes one file per sub-map:
`submaps=build/room_{y}_{x}.bin`. Those names can't be known without reading
the project, so that form is for scripts more than for make.

## Options shared by the export commands

| Option | Meaning | Default |
| --- | --- | --- |
| `--cells 8\|12\|16\|word` | Cell width of tiles, map and sub-maps. `word` is one little-endian word per cell, not split. | `8`; a value that doesn't fit is an error |
| `--area X,Y,W,H` | Only this part of the map (MapArea) | whole map |
| `--set <name>=<value>` | Overrides a project setting first (below); can repeat | |
| `--sprite-attribs spritepad\|seuck\|ignore` | 64th byte style of `sprites` | `spritepad` |
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
| `tiles` | `off` expands the tiles into a char map |
| `key-map` | 0-15 |
| `flexi-grid` | `W,H` in the units the project uses, or `off` |

SpritePad:

| Name | Values |
| --- | --- |
| `bg`, `mc1`, `mc2` | 0-15 |
| `sprite-overlay`, `tile-overlay` | overlay distances, -32768 to 32767 |
| `tiles` | `off` |

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
batchpad convert old.ctm new.ctm [--to ctm7|ctm9]
batchpad convert ships.spd ships.A [--to seuck-a]
batchpad convert level.ctm level.B --to seuck-b-sideways
```

`--to` defaults to the newest version of the output's kind: `.ctm` CTM V9,
`.spd` SPD V5, `.A` and `.B` SEUCK. Versions: `ctm7`, `ctm9`, `spd1`, `spd2`,
`spd5`, and the others as their readers and writers come (#6-#39). `--set`
works here too.

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
| `--org part=ADDR` | Writes a `* =` (or the dialect's) line before that part; can repeat | none: the data follows on where the file is included |
| `--segment NAME` | ca65 `.segment`, KickAssembler `.segment` | none |
| `--event-labels normal\|alt` | `chtl_<name>_event` or `<name>` (#46) | `normal` |
| `--eol lf\|crlf` | Line endings | `lf` |

Labels and constants follow the newest CharPad and SpritePad Pro template
(`charset_data`, `colr_vic_bg0`, `char_count`, ...). Free 2.86's older
upper-case template is not offered.

Unlike CharPad, every label the file uses is defined, and without `--org` there
are no `* =` lines with dummy addresses, so the file assembles as it is when
included.

### c

```
batchpad c level.ctm -o build/level.c --header build/level.h --prefix level_
```

`-o`, `--parts`, `--prefix` as for `asm`. `--header FILE` also writes the
`extern` declarations. `--section NAME` for oscar64's `#pragma section`/
`#pragma data` placement (to be checked, #53). `--event-stubs` writes empty
event functions.

### png, gif

```
batchpad png level.ctm map -o map.png [--palette pepto.pal] [--scale 2]
batchpad png ships.spd sprites -o sheet.png --columns 8
batchpad gif ships.spd -o walk.gif --anim 0 [--scale 2]
batchpad gif ships.spd -o door.gif --tile-anim 1
```

png parts: `chars`, `tiles`, `map` (CharPad); `sprites`, `tiles` (SpritePad).

### stats

```
batchpad stats level.ctm -o stats.txt [--of chars|tiles]
```

### import

```
batchpad import -o level.ctm chars=chars.bin tiles=tiles.bin map=map.bin \
    --tile-size 4x4 --map-size 64x32 --set mode=multicolour
batchpad import -o ships.spd sprites=ships.bin --sprite-attribs seuck
```

The output kind comes from `-o` (or `--to`). Parts give the data, options the
sizes CharPad would take from the open project: `--tile-size`, `--map-size`,
`--cells`. `--load-address skip|detect|none`: skip 2 bytes, skip them when the
size says so (2 mod 8 for chars, 2 mod 64 for sprites), or never (default
`detect`). The address found is reported on stderr.

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

Or keep the data binary and `#embed` it (to check with oscar64, #53):

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
