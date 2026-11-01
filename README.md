# BatchPad

Command-line tool that converts CharPad and SpritePad project files into
artifacts (e.g. binary data, source includes) that can be consumed by build
pipelines.

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

## File format versions

### CharPad (`.ctm`)

Each CharPad release also reads all older versions. Details in
[docs/charpad.md](docs/charpad.md).

| CTM version | Introduced in |
|---|---|
| 1 | CharPad 1.0 |
| 2 | CharPad 1.7 |
| 3 | CharPad 1.8 before Rev 3 |
| 4 | CharPad 1.8 Rev 3 |
| 5 | CharPad 2.0 |
| 6 | CharPad 2.6 ("Thalamus" edition) |
| 7 | CharPad 2.8 |
| 8 | CharPad C64 3.0; the version byte may be 82, from a dropped prototype |
| 9 | CharPad C64 Pro 3.5 |

### CharPad C16 (`.ctt`)

CTT V8 (CharPad C16 3.4) and V9 (3.5) are read and written, and converted to and
from CTM; the colours are TED colours. Details in [docs/charpad.md](docs/charpad.md).

### SpritePad (`.spr`, `.spd`)

Details in [docs/spritepad.md](docs/spritepad.md).

| Format | Used by |
|---|---|
| `.spr` + `.spr.inf`, colours in the `.inf` | SpritePad 1.2 and before |
| `.spr` + `.spr.inf`, colours in each sprite's 64th byte | SpritePad 1.3 to 1.7 |
| `.spd` without header | SpritePad 1.8 |
| SPD V1 | SpritePad 2.0 |
| SPD V2 | SpritePad 2.3 (adds tiles) |
| SPD V3 | SpritePad 2.8 private build only, never released |
| SPD V4 | SpritePad 2.8 |
| SPD V5 | SpritePad 2.9 and every Pro release |

### Tiled (`.tmx`, JSON)

Tiled maps go straight to the binary, assembler and C exports. Details in
[docs/tiled.md](docs/tiled.md).

### SEUCK (`.A`, `.B`)

SEUCK sprite files (`.A`) are read and written as sprite projects, background
files (`.B`, also the sideways kind of CharPad 1.7) as CharPad projects, through
`convert`. Details in [docs/import-export.md](docs/import-export.md).
