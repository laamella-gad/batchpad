# SpritePad (.spd)

## SpritePad 1.8 format (no header)

Worked out from SpritePad 1.8 (Subchrist Software, 2003-2011): its ReadMe and
the 10 example projects that come with it. The download is at
`~/Downloads/SpritePad 1.8` and is not in this repo.

SpritePad 1.8 doesn't write a magic number or a version:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 1 | background colour ($d021) |
| 1 | 1 | sprite multicolour 1 ($d025) |
| 2 | 1 | sprite multicolour 2 ($d026) |
| 3 | 64 × n | sprites, 64 bytes each (up to 256) |

The first 63 bytes of a sprite are its pixels: 21 rows of 3 bytes, as the VIC
reads them. The 64th byte is spare for the VIC, so SpritePad keeps its settings
for the sprite there:

| Bits | Meaning |
| --- | --- |
| 0-3 | sprite colour ($d027+n) |
| 4 | overlay: draw the next sprite over this one |
| 5-6 | not used by SpritePad, but may hold other data (see below) |
| 7 | multicolour |

How sure:

- Every example is 3 + 64 × n bytes long, from 32 to 159 sprites.
- Bit 7 means multicolour, according to the ReadMe ("Sprite Pad uses [the spare byte] to store colour and
  mode information"). Hires sets such as Thrust have it clear in every sprite;
  multicolour sets such as Armalyte and Uridium have it set in every sprite.
- Bit 4: QuedexBall alternates $9c (multicolour, overlay on) and $0b (hires).
  That fits a multicolour sprite with a hires detail sprite drawn over it,
  which is the overlay technique the ReadMe describes.
- Bits 5-6 are set in a few sprites of Antiriad ($ef, $af, $6e, ...), a set
  ripped from a VICE snapshot. The ripper copies the game's whole 64-byte
  blocks, so these bits are probably the game's own data. SpritePad 1.8
  has no expand-X/Y setting: the exe's strings mention only colour, multicolour
  and overlay. So a reader should ignore bits 5-6 but keep them when writing the
  file back.

To tell this format apart: newer SpritePad versions (2.x, Pro) write files
that start with the magic `SPD`. A 1.8 file starts with a colour byte (0-15).
So treat a file as 1.8 when it doesn't start with `SPD` and its length is
3 mod 64. The newer formats are not covered here yet.

## Other formats SpritePad 1.8 can export

From the exe's strings, not tried:
- `Sprites.prg` and `Sprites.raw`. Probably a load address plus the 64-byte
  blocks, and the bare blocks.
- SEUCK `.a` sprite files: always 127 sprites, and the file name must be 16
  characters ending in `.A` on the D64.
- Rips sprites from a VICE snapshot (`.vsf`).

## From earlier projects

- A game's sprite data is usually 64-byte blocks from the VIC bank, numbered by
  the sprite pointers (block = address / 64 within the bank). That is the same
  layout as the 1.8 format minus the 3-byte header. To edit a game's sprites,
  prepend background, MC1 and MC2 to get a project, and strip those 3 bytes to
  get the data back.
- For an exact round trip, keep the game's 64th bytes as they are. Write
  SpritePad's colour, multicolour and overlay settings only where the user
  changed them.
