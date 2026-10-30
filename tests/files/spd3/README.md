# SPD V3 test file

Made by us from `tests/files/spd4/tiles_anims.spd`: version byte 3, and the 4
bytes of overlay distances cut from the header (V3's is 16 bytes). Overlay
means "the next sprite or tile" there, so it reads back with both distances 1.
`tests/tspd.nim` checks that. See `tests/files/spd5/README.md` for what the
sprites, tiles and animations are.

Not checked in SpritePad: V3 was never released, so only the layout from
SpritePad Pro 3.80's V3 loader and saver (see `docs/spritepad.md`) backs it.
