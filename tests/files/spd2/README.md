# SPD V2 test files

Made by us, byte by byte from the V2 layout in `docs/spritepad.md`; `tests/tspd.nim`
checks that they read back as described here. V2 is what SpritePad 2.3.0
Preview saves, the last free SpritePad.

The sprite patterns are those of `tests/files/spd5/README.md`. Colours are C64
palette names, with the number in brackets; they list background, multicolour 1,
multicolour 2. V2 has tiles, but no tile attributes, tags, names or tile
animations, and no overlay distance: overlay means the next sprite is drawn over
this one. Animation attributes: bit 7 enabled, bit 5 overlay (the next animation
is drawn over this one), bit 4 ping-pong.

| File | Colours | Sprites | Tiles | Animations |
| --- | --- | --- | --- | --- |
| `sprites_anims.spd` | black, red, orange | 0-5 bar 0 to bar 5, hires, white (1). 6 box, multicolour, dark grey (11), overlay on, so sprite 7 is drawn over it. 7 diagonal, hires, yellow (7). | off | 0 frames 0-5, timer 4, enabled. 1 frames 2-4, timer 10, enabled, ping-pong. 2 frame 6, timer 1, enabled, overlay on, so animation 3 is drawn over it. 3 frame 7, timer 3, enabled. 4 frames 1-3, timer 2, not enabled (shows blank). |
| `tiles.spd` | blue, white, black | 0 bands, multicolour, green (5). 1 solid, multicolour, light blue (14). 2 checker, hires, white. 3 stripes, hires, yellow. | 2 x 2: 0 sprites 0 1 / 2 3; 1 sprites 3 2 / 1 0; 2 sprites 0 0 / 1 1 | off |

## Checked in SpritePad

Opened in SpritePad and found to look as described above:

- `sprites_anims.spd` (2026-10-19), in SpritePad 2.3.0 Preview (under Wine
  with .NET 4)
- `tiles.spd` (2026-10-19), in SpritePad 2.3.0 Preview
