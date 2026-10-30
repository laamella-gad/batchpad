# SPD V4 test file

Made by us from `tests/files/spd5/tiles_anims.spd`: version byte 4, and the tile
tags and names left out (V4 has none; the header is the same 20 bytes, with
the overlay distances). `tests/tspd.nim` checks that it reads back as the V5
project without tags and names. See `tests/files/spd5/README.md` for what it holds.

Not checked in SpritePad: no release has a menu item that saves V4, so only the
layout from SpritePad Pro 3.80's V4 loader and saver (see `docs/spritepad.md`)
backs it.
