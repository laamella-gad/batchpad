# SPD V1 test files

Made by us, byte by byte from the V1 layout in `docs/spritepad.md`; `tests/tspd.nim`
checks that they read back as described here. V1 is what SpritePad 2.0 Beta 1
saves, the first free SpritePad with the `SPD` header.

The sprite patterns are those of `tests/files/spd5/README.md`. Colours are C64
palette names, with the number in brackets; they list background, multicolour 1,
multicolour 2. V1 has no tiles, no expand bits and no overlay distance: overlay
means the next sprite is drawn over this one. A V1 file always holds at least one
animation. Animation attributes: bit 7 enabled, bit 4 ping-pong.

| File | Colours | Sprites | Animations |
| --- | --- | --- | --- |
| `sprites.spd` | blue, light red, cyan | 0 box, hires, white (1). 1 bands, multicolour, green (5). 2 solid, multicolour, dark grey (11), overlay on, so sprite 3 is drawn over it. 3 diagonal, hires, yellow (7). 4 checker, hires, light blue (14). 5 stripes, multicolour, purple (4). | 0 frames 0-5, timer 4, enabled |
| `anims.spd` | black, red, orange | bar 0 to bar 5, hires, white | 0 frames 0-5, timer 4, enabled; 1 frames 2-4, timer 10, enabled, ping-pong; 2 frames 1-3, timer 2, not enabled |

## Checked in SpritePad

Not yet.
