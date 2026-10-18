# SpritePad (.spd)

## Sources

- **Official specs.** SpritePad C64 Pro (3.52 to 3.80) ships
  `Help/File Format - SPD (Vn).htm` for versions 1 to 5. The releases agree
  apart from wording. Older SpritePads have no spec, only a ReadMe. All
  releases are in `software/` (not in git).
- **Samples.** 149 distinct example projects: 10 headerless (1.8), 13 SPD V1
  (2.0 beta 1), 14 SPD V2 (2.3.0 Preview), 112 SPD V5 (Pro). A throwaway Python
  checker parsed every one by the layouts below and consumed each file to its
  last byte (2026-10-18). None of the V2 samples use tiles, so the user saved
  `software/spritepad23_tiles.spd` from 2.3.0 Preview: 32 sprites, 12 tiles of
  2 x 2, 15 animations. It parses the same way.
- **Missing.** No samples or releases for SPD V3 (never released), SPD V4 or
  the `.inf`-colour `.spr` of 1.2 and before. V4 came with the paid SpritePad
  Pro 2.76 to 2.90 builds (and possibly 3.01 to 3.20), which are no longer
  sold; their download links were never archived. The 2.3.0 Preview and the
  older free releases came from the Wayback Machine's copy of
  `subchristsoftware.com/downloads/`.

## Versions

| Format | Written by |
| --- | --- |
| `.spr` + `.spr.inf`, colours in the `.inf` | SpritePad 1.2 and before |
| `.spr` + `.spr.inf`, colours in the 64th bytes | SpritePad 1.3 to 1.7 |
| `.spd` without header | SpritePad 1.8 |
| SPD V1 | SpritePad 2.0 (beta 1 is from 2014) |
| SPD V2 | SpritePad 2.3 (adds tiles) |
| SPD V3 | SpritePad 2.8 private build only, never released |
| SPD V4 | SpritePad 2.8 |
| SPD V5 | SpritePad 2.9, and every Pro release we have |

## SpritePad 1.x `.spr` + `.spr.inf`

From the SpritePad 1.5 ReadMe, checked against the 1.5 and 1.7 examples.
`.spr` holds the sprites, 64 bytes each, with the 64th byte as in the 1.8 format
below. `.spr.inf` holds 3 bytes: background, multicolour 1, multicolour 2.
Together that is exactly a 1.8 file split in two: 1.8 puts the 3 bytes first.

Up to 1.2, the 64th bytes held nothing and `.spr.inf` held a colour byte per
sprite, then the 3 colours. 1.3 and later still read that.

## SPD versions 1 to 5

All numbers are little endian. A field called "count" holds the number minus 1.

Header, version 1 (9 bytes):

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 3 | `SPD` |
| 3 | 1 | version, 1 |
| 4 | 1 | sprite count |
| 5 | 1 | animation count |
| 6 | 1 | background colour ($d021) |
| 7 | 1 | sprite multicolour 1 ($d025) |
| 8 | 1 | sprite multicolour 2 ($d026) |

Then: the sprites, 64 bytes each; then a byte per animation for each of these
four lists in turn: from frame, to frame, timer reload, attributes.

Header, versions 2 to 5:

| Offset | Size | V2 | V3 to V5 |
| --- | --- | --- | --- |
| 0 | 3 | `SPD` | `SPD` |
| 3 | 1 | version | version |
| 4 | 1 | flags: bit 0 tiles, bit 1 sprite animations | flags: also bit 2 tile animations |
| 5 | 2 | number of sprites (not minus 1) | number of sprites |
| 7 | 2 | number of tiles | number of tiles |
| 9 | 2 / 1 | number of animations (word) | sprite animation count (byte) |
| 10 | 1 | | tile animation count (byte) |
| 11 | 1 | tile width, in sprites (1-4) | tile width (1-8) |
| 12 | 1 | tile height (1-4) | tile height (1-8) |
| 13 | 1 | background colour | background colour |
| 14 | 1 | multicolour 1 | multicolour 1 |
| 15 | 1 | multicolour 2 | multicolour 2 |
| 16 | 2 | | V4, V5: sprite overlay distance (signed) |
| 18 | 2 | | V4, V5: tile overlay distance (signed) |

The header is 16 bytes in V2 and V3, 20 in V4 and V5. Mind the counts: sprites
and tiles are stored as they are, animations as count minus 1, except in V2,
where all three are plain words.

Then, in this order, each part only when its flag is set:

1. Sprites, 64 bytes each.
2. Tiles (flag bit 0): a word per cell, a sprite number, left to right then top
   to bottom. V3 and later: an attribute byte per tile. V5: a tag byte per tile,
   then a 0-terminated name per tile (0 to 32 ASCII chars).
3. Sprite animations (bit 1): from frame (word), for each animation; then to
   frame (word); then timer reload (byte); then attributes (byte). V1 stores
   from and to frame as bytes.
4. Tile animations (bit 2, V3 and later): the same four lists for tiles.

The 64th byte of each sprite:

| Bits | V1 to V4 | V5 |
| --- | --- | --- |
| 0-3 | sprite colour | sprite colour |
| 4 | overlay | overlay |
| 5 | unused | expand X where possible |
| 6 | unused | expand Y where possible |
| 7 | multicolour | multicolour |

Overlay: up to V3 "overlay next", the next sprite is drawn on top of this one.
V4 and later: "has overlay", the overlay is the sprite at this index plus the
overlay distance from the header (+1 gives the old behaviour). The distance lets
a set keep all base frames together and all overlays together, so animations
don't have to skip overlay frames. The tile attribute byte uses bit 4 the same
way, with the tile overlay distance.

Animation attribute byte: bit 4 ping-pong. Up to V3 also bit 7 enabled (not
blanked in the editor) and, from V2, bit 5 overlay.

## SpritePad 1.8 format (no header)

Worked out from SpritePad 1.8 (Subchrist Software, 2003-2011): its ReadMe and
the 10 example projects that come with it. There is no spec for it.

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
- SpritePad 1.8 opened a file written this way without problems (checked by
  the user, 2026-10-17): 16 sprites from De grotten van Oberon, written by
  `~/IdeaProjects/grotten_van_oberon/tools/sprites.py`. Some were multicolour,
  some hires, all with their colours set. Exporting and importing again gives
  back the same bytes.
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
  file back. SPD V5 later gave these bits a meaning: expand X and Y.

To tell this format apart: SpritePad 2.0 and later write files that start with
the magic `SPD`. A 1.8 file starts with a colour byte (0-15). So treat a file as
1.8 when it doesn't start with `SPD` and its length is 3 mod 64.

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
