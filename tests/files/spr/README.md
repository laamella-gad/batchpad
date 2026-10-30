# SpritePad 1.x `.spr` test files

Made by us from `tests/files/spd0/sprites.spd`, which is the same data in one
file: here the 3 colours (blue, light red, cyan) are in `sprites.spr.inf` and
the 6 sprites in `sprites.spr` (384 bytes). `bare.spr` is the first 2 sprites
only, with no `.inf` (as Sprite Painter 1.0 and 1.1 saved). See
`tests/files/spd1/README.md` for the sprites. `tests/tspd.nim` checks that
`sprites.spr` reads back as the headerless project.

Not opened in SpritePad 1.x itself. The layout is from its ReadMe and its
decompiled loader (see `docs/spritepad.md`).
