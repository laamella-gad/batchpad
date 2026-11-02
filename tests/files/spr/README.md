# SpritePad 1.x `.spr` test files

Made by us from `tests/files/spd0/sprites.spd`, which is the same data in one
file: here the 3 colours (blue, light red, cyan) are in `sprites.spr.inf` and
the 6 sprites in `sprites.spr` (384 bytes). `bare.spr` is the first 2 sprites
only, with no `.inf` (as Sprite Painter 1.0 and 1.1 saved). See
`tests/files/spd1/README.md` for the sprites. `tests/tspd.nim` checks that
`sprites.spr` reads back as the headerless project.

`painter.spr` and `painter.spr.inf` are the first 2 sprites as Sprite Painter
1.2 may have saved them (no samples exist): 63 bytes per sprite in the `.spr`
(126 bytes), and in the `.inf` the 2 sprites' colour bytes (`$01` hires white,
`$85` multicolour green) and then the 3 colours (5 bytes). The colour byte
layout is a guess: the 64th byte of SpritePad 1.3 on.

Not opened in SpritePad 1.x itself. The layout is from its ReadMe and its
decompiled loader (see `docs/spritepad.md`).
