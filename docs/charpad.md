# CharPad (.ctm)

## Sources

- **Official specs.** Every CharPad release since 1.7 ships its format docs:
  `Docs/*.txt` in 1.7 and 1.8, `Help/File Format - CTM (Vn).htm` from 2.0 on.
  CharPad C64 Pro 3.88 (2025) documents all of V1 to V9. Older releases
  document fewer versions and word some fields less precisely, but no field
  moved between releases. The releases are in `software/` (not in git).
- **Samples.** The releases come with 1369 distinct `.ctm` files: V1 (1),
  V2 (24), V4 (110), V5 (292), V6 (13), V7 (277), V9 (652). None for V3 or V8.
  A throwaway Python checker parsed every one of them by the specs below and
  consumed each file to its last byte, block markers included (2026-10-18).
  The one V1 sample colours per tile, so the user saved two more from CharPad
  1.0: `software/charpad1_per_tile.ctm` and `software/charpad1_per_char.ctm`
  (colouring method 2, per tile cell). Both parse the same way.
- **Missing.** No release found that writes V3: CSDb and the old Subchrist site
  go from 1.7 straight to 1.8.3. V8 came with the paid CharPad Pro builds
  between Free 2.86 and Pro 3.60 (2.84, 3.01, 3.09, 3.10, 3.19, 3.20, 3.30,
  3.31, from archived itch.io pages), which are no longer sold; their download
  links were never archived. `CharPad2_010915.zip` (a later 2.0 beta) and
  `CharPadExamples276.zip` came from the Wayback Machine's copy of
  `subchristsoftware.com/downloads/`.
- **Earlier projects.** Two C64 rebuilds converted game data to and from CharPad
  projects with small Python scripts:
  - `reference/grotten_playfield.py`, from De grotten van Oberon
    (`~/IdeaProjects/grotten_van_oberon/tools/playfield.py`): a tile map, 128 x 64
    tiles of 8 x 8 chars, multicolour, a colour per tile cell.
  - `reference/roflcopter_ctm.py`, from Copter Duel
    (`~/IdeaProjects/roflcopter/tools/ctm.py`): a single 40 x 25 screen, no tiles.

  Both read versions 5, 7 and 9 and write version 7. Their layouts came from
  github.com/c64lib/gradle-retro-assembler-plugin, not from the specs. The bytes
  they write match the spec, but their comments mislabel header offsets 7 and 8
  of version 7 (see there).

## Which CharPad introduced which version

From the specs. Each release reads all older versions.

| Version | Introduced in | Examples shipped with |
| --- | --- | --- |
| 1 | CharPad 1.0 | 1.0 |
| 2 | CharPad 1.7 | 1.7 |
| 3 | CharPad 1.8 before Rev 3 | none |
| 4 | CharPad 1.8 Rev 3 | 1.8.3, 2.0 beta (one) |
| 5 | CharPad 2.0 | 2.0 betas, 2.3, Free 2.6, Free 2.72 |
| 6 | CharPad 2.6 ("Thalamus" edition) | a few, in Free 2.72, Free 2.86, Pro 3.60, 3.69 |
| 7 | CharPad 2.8 | Free 2.76, Free 2.86 |
| 8 | CharPad C64 3.0; the version byte may be 82, from a dropped prototype | none |
| 9 | CharPad C64 Pro 3.5 | Pro 3.60 to 3.88 |

## File layout

Common to all versions:

- All numbers are little endian. A field called "count" holds the number minus 1.
  Map width and height are stored as they are.
- Chars are 8 bytes, top row first. Tiles and maps run left to right, then top
  to bottom.
- Colouring method: 0 one colour for the whole project, 1 per tile, 2 per char
  (V1 to V4: per tile cell).
- A colour byte has the colour in the low nibble. From V3 on, an attribute byte
  is `MMMMCCCC`: material in the high nibble, colour in the low nibble.

### Versions 1 to 5: fixed header, no block markers

Header, all versions:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 3 | `CTM` |
| 3 | 1 | version |
| 4 | 1 | $d021, background |
| 5 | 1 | $d022, multicolour 1 |
| 6 | 1 | $d023, multicolour 2 |
| 7 | 1 | char colour, used when colouring is per project |
| 8 | 1 | colouring method |

Then per version:

| Offset | V1 | V2 | V3 | V4 | V5 |
| --- | --- | --- | --- | --- | --- |
| 9 | multicolour (1 = yes) | multicolour | multicolour | multicolour | flags: bit 0 tile system on, bit 1 char set expanded, bit 2 multicolour |
| 10 | map width (word) | map width (word) | map width (word) | char count (word) | char count (word) |
| 12 | map height (word) | map height (word) | map height (word) | tile count (byte) | tile count (word) |
| 13 | | | | tile width | |
| 14 | char count (byte) | char count (word) | char count (word) | tile height | tile width |
| 15 | tile count (byte) | | | map width (word) | tile height |
| 16 | reserved (4 bytes) | tile count (byte) | tile count (byte) | | map width (word) |
| 17 | | tile size (square) | tile size (square) | map height (word) | |
| 18 | | reserved (2 bytes) | char set expanded | | map height (word) |
| 19 | | | reserved | char set expanded | |
| 20 | | | | reserved (4 bytes) | |
| size | 20 | 20 | 20 | 24 | 20 |

Data, in this order:

- **V1:** chars (8 bytes each); tiles, always 4 x 4, a byte per cell; if colouring
  is per tile cell, a colour byte per tile cell; if per tile, a colour byte per
  tile; the map, a byte per cell.
- **V2:** chars, 9 bytes each (the 9th is the material); tiles, a word per cell;
  if per tile, a colour byte per tile; if per tile cell, a colour byte per tile
  cell; the map, a byte per cell. Note the colour blocks swap order from V1.
- **V3:** chars (8 bytes); tiles, a word per cell, left out when the char set is
  expanded; an attribute byte per tile cell, always there (colour bits only
  meaningful when colouring is per tile cell); if per tile, a colour byte per
  tile; the map, a byte per cell.
- **V4:** as V3, with an attribute byte per char straight after the chars.
- **V5:** chars; an attribute byte per char; if the tile system is on: tiles, a
  word per cell, left out when the char set is expanded, then if per tile a
  colour byte per tile; the map, a **word** per cell. With the tile system off
  the map holds char numbers and the tile fields in the header mean nothing.

"Char set expanded" means every tile cell has its own char, numbered 0, 1, 2 and
so on through all tiles. The tile data is then left out because it is just that
sequence.

### Versions 6 to 9: short header, then blocks

Header:

| Offset | V6 | V7 | V8 | V9 |
| --- | --- | --- | --- | --- |
| 3 | version 6 | version 7 | version 8 (or 82) | version 9 |
| 4 | $d021 | $d021 | display mode | display mode |
| 5 | $d022 | $d022 | colouring method | colouring method |
| 6 | $d023 | $d023 | flags | flags, key map in the high nibble |
| 7 | char colour | **$d024** | $d021 | flexi-grid width (word) |
| 8 | colouring method | **char colour** | $d022 | |
| 9 | flags | colouring method | $d023 | flexi-grid height (word) |
| 10 | | display mode | $d024 | |
| 11 | | flags | colour matrix colour | flexi-grid settings |
| 12 | | | screen colour, low nibble | $d021 |
| 13 | | | screen colour, high nibble | $d022 |
| 14 | | | | $d023 |
| 15 | | | | $d024 |
| 16 | | | | colour matrix colour |
| 17 | | | | screen colour, low nibble |
| 18 | | | | screen colour, high nibble |
| size | 10 | 12 | 14 | 19 |

- Flags: in V6 bit 0 is multicolour and bit 1 the tile system. In V7 to V9 bit 0
  is the tile system and the display mode replaces the multicolour bit.
- Display mode: 0 hires text, 1 multicolour text, 2 ECM text; V8 and V9 add
  3 hires bitmap and 4 multicolour bitmap.
- V8 and V9 keep three colours per project, char or tile: the colour RAM
  colour, and the low and high nibble for screen RAM (the two colours of a
  bitmap cell). The three colours at the end of the header are the ones used
  when colouring is per project. In the per-char and per-tile blocks only some
  are stored: text modes 1 byte (colour RAM), hires bitmap 2 (screen low, high),
  multicolour bitmap 3 (colour RAM, screen low, high).
- V9 key map (high nibble of flags, added October 2023): 0 none, 1-4 SUBSCII x96,
  x64, x48, x37, 5 ASCII x95, 6 PETSCII shifted x91, 7 PETSCII unshifted x62,
  8 C64 ROM mixed case, 9 C64 ROM upper case, 10 C16 ROM. 74 of the samples set it.
- V9 flexi-grid settings byte, `ETUx xxCC`: E on, T thick line, U units (0 map
  cells, 1 chars), CC colour (red, green, blue, black). Editor-only.

Then blocks. Each starts with `$da, $b0 | n`, where n counts the blocks in order
(0, 1, 2, ...), whatever they hold. The specs say the markers are only a
development aid, but every sample has them right.

1. Chars: a word, char count minus 1, then 8 bytes per char.
2. V6, V7: an attribute byte per char (`MMMMCCCC`; colour only kept when
   colouring is per char). V8, V9: a material byte per char, low nibble.
3. V8, V9, only when colouring is per char: 1 to 3 colour bytes per char, see
   above.
4. Only if the tile system is on:
   - Tiles: a word, tile count minus 1; a byte each for tile width and height;
     then a word per cell.
   - If colouring is per tile: colours, a byte per tile (V8, V9: 1 to 3).
   - Tags: a byte per tile.
   - Names: a 0-terminated string per tile, 0 to 32 ASCII chars.
5. Map: a word each for width and height, then a word per cell. Each word is a
   tile number, or a char number when the tile system is off.

### Limits

The format allows 65536 chars, 65536 tiles (256 in V1 to V4), tiles up to
255 x 255 and maps up to 65535 x 65535. CharPad itself allows less: tiles up to
8 x 8 (2.0), 10 x 10 (2.6 to 3.0) or 16 x 16 (3.8), maps up to 8192 x 8192.
CharPad 2.0 and later have no 1 x 1 tiles: turn the tile system off instead.

## What has been checked in CharPad itself

- CharPad opened the version 7 file from `grotten_playfield.py` without problems
  (checked by the user, 2026-10-17). The file has the tile system on, colour per
  char, multicolour, 507 chars (256 plus 251 copies), 128 tiles and a 128 x 64 map.
  So more than 256 chars in a version 7 file works.
- Copter Duel's tile-less version 7 export works in CharPad Free 2.86.
- Export, then import with no edits, gives back the same bytes in both projects.

## Colours per cell: char copies

CharPad gives each char one colour. C64 games colour each screen cell (colour
RAM), so the same char often shows in several colours. Both scripts deal with
this the same way:

- Every char keeps the colour it is used with most (on a tie, the lowest colour).
- For each other colour it is used with, a copy of the char is added after char 255,
  coloured that way.
- Tiles or the map then point at the copy.
- On import, a char above 255 maps back to the original it copies.

There are two ways import can find the original:

1. **By image and material.** Copter Duel does this. The copy maps to the one
   char below 256 with the same pixels and material. Chars that share their
   pixels, like several blank chars, get a material of their own so they stay
   apart.
   - The material is 4 bits, so this stops working when more than 15 groups of
     identical chars need telling apart. Oberon had 37 blank chars with copies,
     so it could not use this.
2. **With a mapping file.** Oberon does this. Next to the project it writes
   `playfield_copies.txt`, one line per copy: `<copy number> <original>`.
   - Import trusts a line only if the copy still has the same pixels as its
     original.
   - If not, or if the copy is new (a user copied a char to give it a new
     colour), import falls back to the image-and-material lookup.

Either way the user must not delete or move chars, and must not let CharPad
remove unused ones, or the copy numbers point at the wrong chars.

## Things worth keeping from the game side

- Export only the bits the game uses, and keep the rest of each byte on import.
  Oberon's map bytes have an unused bit 7, and its colour bytes an unused high
  nibble. Import restores those from the old data, so an unedited round trip
  is byte-exact.
- Some chars are drawn by the game while it runs (Oberon chars $00-$7f). Export
  shows them as they look at startup. Import ignores changes to them and prints a
  warning.
- Don't use CharPad's own map export: it drops colours and cuts char numbers to
  a byte. Read the project file instead.
- Multicolour preview: a colour of 8 or more makes the cell multicolour. The bit
  pairs then pick background, $d022, $d023, or the cell colour & 7. Pixels are
  double width. `grotten_playfield.py png` renders a whole map this way with the
  VICE palette.
