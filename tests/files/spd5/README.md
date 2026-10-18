# SPD V5 test files

Made by us, byte by byte from the V5 layout in `docs/spritepad.md`; `tests/tspd.nim`
checks that they read back as described here. V5 is what SpritePad C64 Pro
saves.

Sprite patterns (24 x 21):

| Pattern | Looks like |
| --- | --- |
| box | outline of the whole sprite |
| solid | every pixel set |
| checker | rows alternate `$aa` and `$55` (in multicolour: stripes of sprite colour and multicolour 1) |
| bands | four bands of 5, 5, 5 and 6 rows: bit pairs 00, 01, 10, 11 (in multicolour: background, multicolour 1, sprite colour, multicolour 2) |
| diagonal | top left to bottom right, 21 pixels |
| stripes | vertical stripes, 4 pixels wide |
| bar n | a vertical bar 4 pixels wide, at x = 4n |

Colours are C64 palette names, with the number in brackets. Colours list
background, multicolour 1, multicolour 2. Overlay distances are 1 (SpritePad's
default) unless listed.

| File | Colours | Sprites | Tiles | Animations |
| --- | --- | --- | --- | --- |
| `sprites.spd` | blue, light red, cyan | 0 box, hires, white (1). 1 bands, multicolour, green (5). 2 solid, multicolour, dark grey (11), overlay on, so sprite 3 is drawn over it. 3 diagonal, hires, yellow (7). 4 checker, hires, light blue (14), expand X. 5 stripes, multicolour, purple (4), expand Y. | off | off |
| `sprite_anims.spd` | black, red, orange | bar 0 to bar 5, hires, white | off | sprite animations: 0 frames 0-5, timer 4; 1 frames 2-4, timer 10, ping-pong |
| `tiles_anims.spd` | dark grey, white, black | 0 bands, 1 solid, 2 checker, 3 box: multicolour, overlay on, colours red, green, orange, light blue (2, 5, 8, 14). 4 diagonal, 5 box: hires, white. 6 stripes, 7 diagonal: hires, yellow. Sprite overlay distance 4: sprites 4-7 are drawn over sprites 0-3. | 2 x 1: 0 "left" sprites 0 1, tag 1; 1 "right" sprites 2 3, tag 2, overlay on (tile 2 drawn over it); 2 "mixed" sprites 0 3, tag 3 | sprite animation 0: frames 0-3, timer 6. Tile animations: 0 frames 0-2, timer 8; 1 frames 1-2, timer 3, ping-pong |

## Checked in SpritePad

Opened in SpritePad and found to look as described above:

- `sprites.spd` (2026-10-19), in SpritePad C64 Pro 3.80
- `sprite_anims.spd` (2026-10-19), in SpritePad C64 Pro 3.80
- `tiles_anims.spd` (2026-10-19), in SpritePad C64 Pro 3.80
