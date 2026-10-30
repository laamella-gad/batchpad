# Headerless SPD test file (SpritePad 1.8)

Made by us from `tests/files/spd1/sprites.spd`: its three colours (blue, light
red, cyan), then its 6 sprites, 64 bytes each, with no header, tiles or
animations (3 + 6 × 64 = 387 bytes). Overlay on sprite 2 means sprite 3 is
drawn over it. See `tests/files/spd1/README.md` for the sprites.
`tests/tspd.nim` checks that it reads back as the V1 project without
animations.

Not opened in SpritePad 1.8 itself; the layout is the one worked out in
`docs/spritepad.md` from its example projects, one of which (written by
another tool) it opened without problems.
