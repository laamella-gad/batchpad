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
- **Decompiled code.** SpritePad C64 Pro 3.80's `_NET.exe` is a plain .NET
  assembly; ilspycmd turns it back into C# (2026-10-18). It has a loader for
  the headerless 1.8 format and SPD V1 to V5, and a saver for each, though the
  menus only ever save V5. The V3 and V4 code matches the layouts below, so
  those two are confirmed without samples. See "What SpritePad Pro 3.80 does".
  SpritePad 1.5 and 1.8 are native Borland C++ Builder exes; Ghidra 12.1.4
  decompiled them to C (2026-10-18). See "What SpritePad 1.5 does" and "What
  SpritePad 1.8 does".
- **Missing.** No samples or releases for SPD V3 (never released), SPD V4 or
  Sprite Painter 1.0-1.2 (1.5 can't read 1.2's `.inf`). SpritePad Pro 3.80 has V3 and V4
  savers but no menu item that calls them. V4 came with the paid SpritePad
  Pro 2.76 to 2.90 builds (and possibly 3.01 to 3.20), which are no longer
  sold; their download links were never archived. The 2.3.0 Preview and the
  older free releases came from the Wayback Machine's copy of
  `subchristsoftware.com/downloads/`.

## Versions

| Format | Written by |
| --- | --- |
| `.spr` only, no colours | Sprite Painter 1.0, 1.1 |
| `.spr` + `.spr.inf`, colours in the `.inf` | Sprite Painter 1.2 |
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

The ReadMe gives the 64th byte from 1.3 on as bit 7 mode (0 = hires) and bits
0-3 colour; bits 4-6 aren't mentioned.

Older versions, also from the 1.5 ReadMe (no releases or samples of them):

- Up to 1.2 the program was called Sprite Painter; 1.3 renamed it to avoid a
  clash with another program.
- 1.0 and 1.1 saved the `.spr` alone. 1.2 added the `.inf` "to record colour
  and mode information for sprites".
- 1.2's `.spr` holds just the pixel data. Its `.spr.inf` holds a colour byte
  per sprite, then background, multicolour 1, multicolour 2. How that byte holds
  the mode is not said.
- 1.1 added "Save up to current", so a `.spr` can hold any number of sprites.
- The ReadMe says "the program still supports the original .inf files but they
  will be updated when saved", but 1.5's code doesn't (see below).

### What SpritePad 1.5 does

From the decompiled exe. 1.5 has a single sprite loader and a single saver.

- **Loading:** the `.spr` must be a multiple of 64 bytes and at most 16384
  (256 sprites), otherwise "Invalid file size". An empty file passes. The whole
  file goes into the sprite buffer. Then, if `<file>.inf` exists and is exactly
  3 bytes long, it supplies background, multicolour 1 and multicolour 2. An
  `.inf` of any other length is ignored, so a 1.2 `.inf` loses its colours and
  the sprites keep whatever their 64th bytes hold.
- **Command line:** a file named as the only argument is loaded at start-up.
- **Saving:** writes the first n sprites to the `.spr` and the 3 colours to
  `<file>.inf`. n is 256 ("Save All"), 16, 32, 64 or 128 ("First 16" to
  "First 128"), or the current sprite + 1. It saves no other format.
- **64th byte:** bits 0-3 sprite colour, bit 7 multicolour. Setting a sprite's
  colour writes `(byte & $80) + colour`, so it clears bits 4-6. The exe has no
  "overlay" string. New and cleared sprites get `$8c`: multicolour, colour 12.
  "Copy current sprite attributes to all" copies the whole 64th byte.
- **"View text data":** writes the current sprite's first 63 bytes as decimal,
  comma-separated (`0,0,255,...`, no line breaks or `DATA` keyword) to
  `%WINDIR%\temp\spritedata.txt`, opens it with the shell and deletes it on
  exit.

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

In SpritePad 2.0 Beta 1 (decompiled), an animation that isn't enabled shows
as blank, and the animator and "Selecting an animation selects it's images"
skip it. There is no switch for the bit: only "Send range to Animator" sets
it, and that also sets from and to to the selected sprites, the timer to 3
and the attributes to `$80` (ping-pong off). So our V1 writer sets bit 7 on
every animation of a project read from V4 or later, which has no such bit.
SpritePad 2.3.0 Preview handles the bit the same way, and its V2 writer does
the same.

SpritePad 2.3.0 Preview's V2 loader (decompiled) refuses files under 80 bytes,
sprite counts outside 1 to 4096, tile or animation counts above 256, tiles
wider or taller than 4, and any length other than 16 + 64 × sprites + 2 ×
tile cells + 6 × animations. Unlike Pro, it reads the tile and animation
counts whether their flag is set or not. Its saver writes 0 for the parts
that are off.

## What SpritePad Pro 3.80 does

From the decompiled loaders and savers.

- **Which format:** it tries V5, V4, V3, V2, V1 and then the headerless 1.8
  format, and takes the first loader that accepts the file. There is no `.spr`
  loader.
- **Length checks:** V1 to V4 must be exactly the size the header implies (V1:
  9 + 64 × sprites + 4 × animations; V3, V4: header + 64 × sprites + 2 × tile
  cells + tiles + 6 × sprite animations + 6 × tile animations). V5 is not
  checked. Headerless: 3 + 64 × n with n from 1 to 256; the three colours are
  masked to the low nibble.
- **Counts:** the tile count and the animation counts are only read when their
  flag is set; otherwise they count as 0, whatever the header says. V2 also
  refuses more than 4096 sprites or 256 animations.
- **64th byte:** decoded the same way in every version, expand X and Y
  included. So bits 5 and 6 of an old file show up as expansion in Pro.
- **Overlay distance:** 1 when the format has none (V1 to V3).
- **Tile attributes:** only bit 4 (has overlay) is kept.
- **Animation attributes:** only bit 4 (ping-pong) is read and written. The
  enabled and overlay bits of V1 to V3 are dropped, and the savers write 0 or
  `$10`.
- **V5 loader:** files under 84 bytes (header and one sprite) and a sprite
  count of 0 are refused; bytes after the last part are ignored.
- **V5 tile names:** read up to 33 bytes or the 0, then trimmed.
- **V5 tile attributes in older builds:** 30 of the 112 V5 samples (e.g. examples
  of 3.52 and 3.79) have tile attribute bytes of 3 or `$13`: the tile's
  colour (default 3, cyan) in the low nibble, next to the overlay bit. 3.80
  writes only bit 4. Our reader and writer keep the whole byte.
- **Saving:** "Save" and "Save As" write V5, up to 65536 sprites (the count is
  a word, so 65536 is written as 0 and the file can't be loaded again; our
  writer leaves out the sprites past 65535). The unused V3 and V4 savers drop tile tags
  and names. With tiles or animations off,
  their header fields are written as 0.

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

## What SpritePad 1.8 does

From the decompiled exe (native Borland C++ Builder; Ghidra 12.1.4,
2026-10-18). Every routine works on a 256-sprite (16 KB) buffer.

- **Open / Save** (`.spd`): the format above. The loader wants the file size
  minus 3 to be a positive multiple of 64 and at most 65536, so it accepts up
  to 1024 sprites although its buffer holds 256. "New" fills the buffer with 0
  and sets every 64th byte to `$85` (multicolour, colour 5).
- **Old `.spr`:** 1.5's loader is still there, with the same rules (64 to 16384
  bytes, a multiple of 64; colours from `<file>.inf` only when it is exactly 3
  bytes), called only from start-up code, not from Open. The `.spr` saver's
  strings are left over, its code is gone.
- **Export sprites** (dialog: Raw or PRG; SpritePad or SEUCK attributes):
  all sprites, 64 bytes each. PRG puts a 2-byte load address first, typed as
  hex digits (`0`-`9`, `A`-`F` only; anything else or nothing means no load
  address). Default names `Sprites.raw` and `Sprites.prg`. The 64th byte is
  kept, or with SEUCK attributes written as `000M CCCC`: colour, plus `$10`
  if multicolour.
- **Import sprites** (Raw, PRG or Auto; SpritePad, SEUCK or Ignore
  attributes): PRG skips 2 bytes; Auto skips them when the size is 2 mod 64.
  At least 64 bytes (raw) or 66 (PRG); count = size / 64, at most 256. SEUCK
  attributes move bit 4 (multicolour) to bit 7 and drop bits 5-7 (`(b & $0f) +
  (b & $10) * 8`); Ignore sets every 64th byte to `$8c`. The same three styles
  as Pro (see `docs/import-export.md`).
- **SEUCK `.a`:** save writes `$42 $00`, then the sprites with SEUCK
  attributes, padded with zero blocks to 127 sprites (8130 bytes); more than
  127 sprites is refused. Load is the import above with Auto and SEUCK.
- **Text data** (Decimal or Hex): the selected range, written to
  `spritedata.txt` next to the exe and opened with the shell. Per sprite a
  blank line, `; Sprite n`, a blank line, then all 64 bytes on one line:
  `0,12,255,...` or `$00,$0C,$FF,...` (upper case). No `.byte` keyword; text
  mode, so CRLF on Windows.
- **VICE Snapshot Ripper** (`.vsf`): reads the whole file, finds the
  `VICE Snapshot File` signature and then the `C64MEM` module; the 64 KB RAM
  starts 26 bytes after the module name. It shows one 16 KB VIC bank at a time
  as 256 sprite blocks to copy from. A file without both strings gives
  "Invalid VICE snapshot file".
- **Palettes** (`palettes.pal`): per palette a quoted name (up to 32 chars),
  then 16 colours, each `#` followed by exactly 6 hex digits (either case). A
  palette counts only when all 16 colours parse.
- **Save Bitmap:** a `.bmp` of the sprites; not looked at.

## From earlier projects

- A game's sprite data is usually 64-byte blocks from the VIC bank, numbered by
  the sprite pointers (block = address / 64 within the bank). That is the same
  layout as the 1.8 format minus the 3-byte header. To edit a game's sprites,
  prepend background, MC1 and MC2 to get a project, and strip those 3 bytes to
  get the data back.
- For an exact round trip, keep the game's 64th bytes as they are. Write
  SpritePad's colour, multicolour and overlay settings only where the user
  changed them.
