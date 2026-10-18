# charpad_spritepad_assistant

Command-line tool that converts CharPad and SpritePad project files into
artifacts (e.g. binary data, source includes) that can be consumed by build
pipelines.

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
