# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Command-line tool that converts CharPad and SpritePad project files into artifacts (e.g. binary data, source includes) that can be consumed by build pipelines.

## Project status

Early. `src/batchpad.nim` runs the command line in `src/batchpad/cli.nim` (argparse; design in `docs/cli.md`), tested by `tests/tcli.nim`: `info`, `convert`, `bin` (raw binary parts, `src/batchpad/rawbin.nim`, tested by `tests/trawbin.nim`) and `asm` (assembler source, `src/batchpad/asmout.nim`, tested by `tests/tasm.nim`) and `c` (C source for oscar64, `src/batchpad/cout.nim`, tested by `tests/tcout.nim`) and `png` and `gif` (previews: `src/batchpad/preview.nim` draws, `src/batchpad/image.nim` holds the palette and PNG writer, tested by `tests/timage.nim`) and `stats` (usage text, `src/batchpad/stats.nim`, tested by `tests/tstats.nim`) and `import` (raw binary parts into a project, `src/batchpad/rawimport.nim`, tested by `tests/trawimport.nim`) work, the other commands are stubs. `src/batchpad/ctm.nim` holds the CharPad project model, and the CTM V1 to V9 readers and writers (#6, #8, #10, #12, #14, #16, #18, #19, #20, #22, #23), tested by `tests/tctm.nim`. `src/batchpad/ctt.nim` reads and writes CharPad C16 `.ctt` V8 and V9 as CharPad projects with TED colours (`Project.ted`; #40, #79), and converts the colours to and from C64 ones; tested by `tests/tctt.nim`. `src/batchpad/spd.nim` holds the SpritePad project model and the SPD V1 to V5 and headerless 1.8 (version 0) and `.spr` + `.spr.inf` (`parseSpr`, `toSpr`) readers and writers (#26, #28, #30-#36, #38, #39), tested by `tests/tspd.nim`. `src/batchpad/spm.nim` reads and writes Spritemate `.spm` as sprite projects (#64), tested by `tests/tspm.nim`. `src/batchpad/seuck.nim` reads and writes SEUCK `.A` sprites (as a sprite project) and `.B` backgrounds (as a CharPad project) (#56, #57), and reads them from `.P00` containers and from the "save all data" `.I` (#83), tested by `tests/tseuck.nim`. `src/batchpad/tiled.nim` reads and writes Tiled maps (TMX and JSON; a third kind of input next to CharPad and SpritePad projects, #66), `src/batchpad/tiledbin.nim` makes their binary parts, `tests/ttiled.nim` tests both. CharPad and SpritePad use `src/batchpad/binio.nim` for reading and writing bytes. `README.md` holds the purpose and the format version tables — update this file as the project takes shape.

## Priorities

Formats written by the releases currently on itch.io (subchristsoftware.itch.io) matter most: CTM V9 (CharPad C64 Pro 3.6+), CTM V7 (CharPad Free 2.86) and SPD V5 (SpritePad C64 Pro). The formats of the last free SpritePads matter as much: SPD V1 (2.0 Beta 1) and SPD V2 (2.3.0 Preview). Older versions come after these, including `.spr` + `.spr.inf` (1.5, 1.7) and headerless `.spd` (1.8, 1.8.1).

## Issue tracking

Issues live in `ISSUES.md` (format described at its top). When finishing work on an issue, move it to "Closed"; when adding one, use the next free number and bump it.

## Toolchain

- Nim >= 2.2.8 (declared in `batchpad.nimble`), managed with Nimble.
- Project is opened in IntelliJ IDEA with the Nim plugin (`.idea/`).

## Commands

```sh
nimble build                 # compile to bin/batchpad
nimble run                   # build and run
nim c -r src/batchpad.nim   # compile + run directly
nim check src/batchpad.nim  # type-check without building
nimble test                  # runs tests/t*.nim
nim c -r -p:src tests/tctm.nim   # run a single test file (also tests/tspd.nim, tests/tctt.nim, tests/tspm.nim, tests/ttiled.nim, tests/tseuck.nim, tests/tcli.nim, tests/trawbin.nim, tests/trawimport.nim, tests/tasm.nim, tests/tcout.nim, tests/timage.nim, tests/tstats.nim)
# tests/tasm.nim assembles with 64tass, acme, ca65 when on the PATH, and KickAssembler when KICKASS_JAR names its jar; tests/tcout.nim compiles with oscar64 when on the PATH
```

## Releases

`.github/workflows/release.yml` builds and tests on Linux, Windows and macOS, and publishes `batchpad-linux.tar.gz`, `batchpad-windows.zip` and `batchpad-macos.tar.gz` to a GitHub release when a `v*` tag is pushed. The README download links use these names.

## Layout

- `srcDir = "src"`, `binDir = "bin"`; the binary entry point is `src/batchpad.nim` (code under `when isMainModule:`).
- Library modules for the package should go in `src/batchpad/`; tests in `tests/` with `t` prefix (Nimble convention picked up by `nimble test`). Tests build their input bytes themselves: they must never need `software/` or other commercial downloads. Work on a format version includes making a few small test files for it ourselves, in `tests/files/<format><version>/` with a README saying what they hold (e.g. `tests/files/ctm1/`, `tests/files/ctm2/`, `tests/files/ctm3/`, `tests/files/ctm4/`, `tests/files/ctm5/`, `tests/files/ctm6/`, `tests/files/ctm7/`, `tests/files/ctm8/`, `tests/files/ctm9/`, `tests/files/ctt8/`, `tests/files/ctt9/`, `tests/files/spd0/`, `tests/files/spd1/`, `tests/files/spd2/`, `tests/files/spd3/`, `tests/files/spd4/`, `tests/files/spd5/`, `tests/files/spr/`, `tests/files/spm/`, `tests/files/tiled/`, `tests/files/seuck/`).
- `docs/spritepad.md`: SpritePad formats: 1.x `.spr`+`.inf`, headerless 1.8 `.spd`, SPD V1-V5.
- `docs/cli.md`: the command line design (#55).
- `docs/tiled.md`: Tiled maps: what we read, tile numbers, parts (#66).
- `docs/import-export.md`: every import/export format of the current CharPad, SpritePad and Glaze releases, and which we support.
- `docs/charpad.md`: CTM V1-V9 format (from CharPad's official specs, checked against all bundled samples) and lessons from earlier projects; `docs/reference/` holds the Python scripts they came from.
- `software/` (untracked, ~100 MB): every CharPad (also C16 Pro) and SpritePad release found, Tilemedo, and the original SEUCK disks (4 sample games), as zip/rar. They hold the official spec HTML (`Help/File Format - *.htm`) and ~1500 distinct sample `.ctm`/`.spd` files plus ~800 `.ctt`, a good test corpus. Extract to a scratch dir; don't commit.
