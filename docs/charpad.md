# CharPad (.ctm): what earlier projects found

Gathered from two C64 rebuilds that converted game data to and from CharPad
projects with small Python scripts:

- `reference/grotten_playfield.py`, from De grotten van Oberon
  (`~/IdeaProjects/grotten_van_oberon/tools/playfield.py`): a tile map, 128 x 64
  tiles of 8 x 8 chars, multicolour, a colour per tile cell.
- `reference/roflcopter_ctm.py`, from Copter Duel
  (`~/IdeaProjects/roflcopter/tools/ctm.py`): a single 40 x 25 screen, no tiles.

Both read CTM versions 5, 7 and 9 and write version 7. The layouts were taken from
the reader in github.com/c64lib/gradle-retro-assembler-plugin. They are not checked
against CharPad's own documentation.

## What has been checked

- CharPad opened the version 7 file from `grotten_playfield.py` without problems
  (checked by the user, 2026-10-17). The file has the tile system on, colour per
  char, multicolour, 507 chars (256 plus 251 copies), 128 tiles and a 128 x 64 map.
  So more than 256 chars in a version 7 file works.
- Copter Duel's tile-less version 7 export works in CharPad Free 2.86.
- Export, then import with no edits, gives back the same bytes in both projects.
- Reading versions 5 and 9 has never been tried on a real file. The version 9
  header layout below is the least certain part.

## File layout

All numbers are little endian. A "count" field holds the number minus 1.

### Version 7 (CharPad Free 2.x)

Header, 12 bytes:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 3 | `CTM` |
| 3 | 1 | version, 7 |
| 4 | 3 | background colours: $d021, $d022, $d023 |
| 7 | 1 | char colour (default) |
| 8 | 1 | written as 1 by the scripts; ignored when reading |
| 9 | 1 | colouring method: 0 global, 1 per tile, 2 per char |
| 10 | 1 | display mode: 0 hires, 1 multicolour, 2 ECM |
| 11 | 1 | flags: bit 0 tile system on; bit 1 char ex (roflcopter defines it, unused) |

Then blocks. Each block starts with the marker `$da, $b0 | n`, where n counts the
blocks in order: 0, 1, 2 and so on.

1. Chars: a word, char count minus 1, then 8 bytes per char.
2. Char attributes, a byte per char: colour in the low nibble, material in the
   high nibble.
3. Only if the tile system is on:
   - Tiles: a word, tile count minus 1; a byte for tile width and one for tile
     height; then a word char number for every cell, tile by tile, row by row.
   - If colouring is per tile: a block with a colour byte per tile.
   - Tags: a byte per tile.
   - Names: one 0-terminated string per tile.
4. Map: a word for width and one for height, then a word per cell. Each word is a
   tile number, or a char number when the tile system is off.

### Version 9 (CharPad Pro)

The header is 3 + 1 bytes, then display mode, colouring method, flags, then 12
bytes the scripts skip: flexigrid size (4), an unknown byte (1), background
colours (4), char colours (3). Note that mode comes before method here, the
other way round from version 7.

The blocks are as in version 7, with two differences:
- Block 1 holds only the material, a byte per char.
- If colouring is per char, the next block holds a colour byte per char (low
  nibble).

### Version 5

No block markers. After `CTM`, 5: 4 bytes of colours, then method, flags, char
count minus 1 (word), tile count minus 1 (word), tile width and height (bytes),
map width and height (words). Then the chars, the attributes (a byte per char),
the tiles if the tile system is on, a colour byte per tile if colouring is per
tile, and the map as words.

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
