# CharPad (.ctm)

## Sources

- **Official specs.** Every CharPad release since 1.7 ships its format docs:
  `Docs/*.txt` in 1.7 and 1.8, `Help/File Format - CTM (Vn).htm` from 2.0 on.
  CharPad C64 Pro 3.88 (2025) documents all of V1 to V9. Older releases
  document fewer versions and word some fields less precisely, but no field
  moved between releases. The releases are in `software/` (not in git).
- **Samples.** The releases come with 1380 distinct `.ctm` files: V1 (1),
  V2 (24), V4 (110), V5 (292), V6 (13), V7 (277), V9 (663). None for V3 or V8.
  A throwaway Python checker parsed every one of them by the specs below and
  consumed each file to its last byte, block markers included (2026-10-18).
  The one V1 sample colours per tile, so the user saved two more from CharPad
  1.0: `software/charpad1_per_tile.ctm` and `software/charpad1_per_char.ctm`
  (colouring method 2, per tile cell). Both parse the same way.
  `software/charpad_1_7.ctm` is a V2 file the user saved from CharPad 1.7
  (per tile colouring); it parses the same way too.
- **Missing.** No release found that writes V3: CSDb and the old Subchrist site
  go from 1.7 straight to 1.8.3. V8 came with the paid CharPad Pro builds
  between Free 2.86 and Pro 3.60 (2.84, 3.01, 3.09, 3.10, 3.19, 3.20, 3.30,
  3.31, from archived itch.io pages), which are no longer sold; their download
  links were never archived. CharPad Pro 3.88's "Export Project (CTM version
  8)" can still make V8 files (see `import-export.md`). `CharPad2_010915.zip` (a later 2.0 beta) and
  `CharPadExamples276.zip` came from the Wayback Machine's copy of
  `subchristsoftware.com/downloads/`.
- **Decompiled code.** CharPad C64 Pro 3.88's `CharPadC64Pro_NET.exe` is a
  plain .NET assembly (Dotfuscator renamed only some helpers), so ilspycmd turns
  it back into readable C# (2026-10-18). It has a loader for every version
  (`CPV_FileIO_CTM1` to `CTM9`, no `CTM3`) and savers for V5 to V9. The V8 and
  V9 savers match the layouts below byte for byte, which confirms V8 even
  without samples. What the loaders do differently from the specs is under
  "What CharPad Pro 3.88 does with each version". The decompiled source is not
  kept in the repo.
- **CharPad Free 2.86**, decompiled too (2026-10-18): it tries V7, V6, V5,
  V4, V2 and V1 in that order, saves V7 and has "Export Project" for V5 and
  V6. Its V2 loader also drops colouring method 2, like Pro's. It has no ECM:
  an ECM project opens as hires text, with a warning.
- **CharPad Glaze C64** (free on itch.io, 1.60 from June 2026) builds parallax
  scrolling data from a foreground and a background CharPad project. Its 55
  examples are all V9 (11 not in the other releases); they parse like the rest.
  Decompiled (2026-10-18): it shares Pro's loaders but only calls V4 to V9, so
  it can't open V1 to V3 files, and it saves no project. It exports the
  parallax data (four char sets, attributes, two maps, 8 bit) as binaries and
  64tass source; see `import-export.md`.
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
| 9 | CharPad C64 Pro 3.5 | Pro 3.60 to 3.88, Glaze 1.60 |

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
  if per tile, a colour byte per tile; the map, a byte per cell. The Pro spec
  adds a colour byte per tile cell for method 2, after the per-tile block, but
  no V2 file has one: CharPad 1.7's own spec (`Docs/CharPad - CTM (V2)
  Format.txt`) allows only 0 (global) and 1 (per tile), and its UI has just a
  "Use Global Tile Colour" checkbox.
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
CharPad 2.x has no 1 x 1 tiles (turn the tile system off instead), but Pro 3.88
offers every size from 1 x 1 to 16 x 16 again (its Tile Set size list).

Pro 3.88 allows up to 500,000 chars (`CPV_Project.MaxCharCount`; its help says
so too), more than a CTM file can hold. The V9 saver doesn't check: it writes
the count minus 1 as a word and every char after it, so a project with more
than 65536 chars gives a file that can't be read back. Map and tile cells are
words as well, so char numbers above 65535 lose their high bits. Our writer
refuses such projects.

## What CharPad Pro 3.88 does with each version

From the decompiled loaders and savers. Where Pro differs from the spec, a
reader of ours should follow the spec, but these are the cases to test.

- **All versions:** colours read from the file are masked to the low nibble.
  An unknown colouring method becomes per project in V2, V4, V5 and V6, but
  per char in V7 to V9 (values above 2 are clamped to 2). V7 clamps the
  display mode to 2, V8 and V9 to 4.
- **V1:** per-tile colours are read when the method is 1. With method 2 the
  per-tile-cell colours are read and thrown away.
- **V2:** the 9th char byte goes through the same attribute decoder as V4 and
  later (material in the high nibble, colour in the low nibble, colour kept
  only when colouring is per char). Pro reads the per-tile colour block for
  method 1, and no per-tile-cell block for method 2; method 2 then turns into
  per project. That matches CharPad 1.7, which can't write method 2 (see the V2
  layout above). Tile size 1 turns the tile system off (per tile then becomes
  per char).
- **V4:** the per-char attribute block straight after the chars is read and
  thrown away. The tile-cell attribute block is applied to the chars the cells
  point at. With 1 x 1 tiles the tile words are char numbers, used to rebuild
  the char set.
- **V5 saver:** flags bit 0 tile system on, bit 1 char set expanded, bit 2
  multicolour. With the tile system off the tile fields are written as 0 (count)
  and 1, 1 (size). The colour in each attribute byte is cleared unless
  colouring is per char.
- **V6 and V5 savers** refuse display modes above multicolour text; the V7
  saver allows ECM; V8 and V9 allow everything up to multicolour bitmap.
- **V8:** the saver always writes version 8; the loader accepts 8 and 82.
- **V9:** tile names are read up to 33 bytes or the 0. Before saving, Pro
  clamps out-of-range values (`CorrectDataLimits`). Files under 19 bytes are
  refused; bytes after the map are ignored.
- **V8, V9 project colours:** the three at the end of the header are only read
  when colouring is per project, screen low and high only in bitmap modes.
  Otherwise Pro keeps its defaults, cyan, orange, yellow (3, 8, 7), and writes
  those on the next save. The help says the same: matrix colours a project
  doesn't use are reset to the defaults when it is saved. So a file saved by
  Pro after loading ours can differ in those header bytes only (seen with
  `tests/files/ctm9/mctext_pertile.ctm`: 14, 0, 0 came back as 3, 8, 7).

## How we read and write V1 to V5

- **V1:** chars of 8 bytes (no material), always 4 x 4 tiles of byte cells, a
  byte map. Colouring per project, per tile (a colour byte per tile; masked to
  the low nibble as Pro does) or per tile cell, which is read like V4's: a
  char used in several colours gets copies, and the colouring becomes per char
  (Pro throws these colours away). The writer refuses tiles smaller than 4 x 4
  and cuts bigger ones (reported), leaves out the materials (reported) and
  writes colouring per char as a colour per tile cell. More than 256 chars
  (what reading a per tile cell file gives when a char has several colours)
  go back to the first char with the same shape; that fails when a tile cell
  uses more than 256 shapes. The three CharPad 1.0 samples (one that comes
  with it, two the user saved) read and write back byte for byte.
- **V4 reader:** colour (method 2) and material are per tile cell in the file,
  but per char in our model. A char used with another colour or material gets
  a copy (added at the end of the set), and the tile cell points at the copy;
  method 2 becomes per char. The per-char attribute block only supplies chars
  no tile cell uses. CHAREX files get their tile data made up.
- **V2:** the 9th char byte is the material, whole (in all 25 samples it is
  0 to 3, or 0 for every char). Colouring is per project or per tile; a method
  of 2 counts as per project, above 2 is an error. Tile colour bytes are cut
  to the low nibble (two SEUCK samples have bit 4 and more set in some). Tile
  size 1 (a char map in CharPad's eyes) stays a tile system of 1 x 1 tiles.
  The writer refuses char maps and more than 256 tiles like V4, cuts
  non-square tiles to a square, and turns colouring per char into per project
  (reported). Of the 25 distinct samples of CharPad 1.7, 23 write back byte
  for byte; the other two differ in the masked tile colour bits.
- **V3:** read and written as V4 with its own header (the map size first, one
  square tile size) and no attribute byte per char, so chars no tile cell
  uses keep material 0. The writer cuts non-square tiles to a square
  (reported). No sample exists; only the layout above backs it.
- **V5 reader:** CHAREX likewise; with the tile system off, the tile fields and
  the CHAREX flag are ignored.
- **Writers:** V4 and V5 never set CHAREX, and write no tags or names (reported
  as left out). V4 refuses projects without tiles and with over 256 tiles. The
  attribute byte per char always holds the char's colour, as CharPad 2.x
  files do. V5 with the tile system off writes 0 for the tile fields.
- Checked on the V4 and V5 samples of the CharPad 1.8 and 2.x downloads: all
  read; V5 writes back byte for byte (apart from unused tile size fields).

## ECM chars 64 and up

Settled 2026-10-31 (#59), from the help ("ECM Mode Tips", "Form - Character
Set"), the dev log, all ECM samples and the decompiled CharPad Pro 3.88
(`CharPadC64Pro_NET.exe`): `CPV_ECM_Splitter` cuts the char set into banks of 64,
runs insert/delete/paste on each bank and `Combine` trims or pads every bank
to exactly 64 chars. Nothing in the project save or export code treats ECM
specially, so chars 64 and up are written as stored.

- **The model.** ECM shows 64 shapes. CharPad treats the set as four banks of
  64 chars, bank *b* being the background colour `$d021 + b`: char *n* has the
  shape of char *n* & 63 and background *n* >> 6. Every char still has its own
  colour (and material). The help says CharPad "supports any number of images
  but only 64 shapes max", and sees no use for more than 256. A cell holds
  8 bits, so only chars 0 to 255 can be shown.
- **The stored bytes of chars 64 and up are not authoritative.** Pixel edits
  and transforms go to char *n* & 63 only (dev log: "transforms ... translate the
  selection to be within the first 64"; before that they had no visible effect
  on chars above 63, as their "real" images are hidden). So nothing keeps the
  bytes in step, and a file holds whatever was there.
- **What the files hold.** 17 distinct ECM files (V7 and V9, every one of the
  774 distinct readable samples that is ECM; all have exactly 256 chars). Of
  the chars from 64 up that a tile or the map uses, most are all-zero bytes
  (e.g. all 56 in `ECM Icon Samples`, all 90 in `Transitions 1`), some are
  copies of char *n* & 63, and a few hold other shapes: only the two
  third-party `Astrid - TEC` and `Outdoors - TEC` files have non-blank
  differing ones (10 and 12 used ones). Colours of chars 64 and up do differ
  from those of char *n* & 63 (the point of the model); materials never did.
- **What we do.** Readers keep the stored bytes, writers write them back, so
  round trips are exact. Whatever draws a char (`png`, `gif`) uses the shape
  of char & 63 and the background of char >> 6. Exports (`bin`, `asm`, `c`)
  write the set as stored, as CharPad's own export does; a C64 program only
  fetches the first 64 shapes (512 bytes of the charset) so the rest is
  harmless. Nothing in our code reads the bytes of chars 64 and up as a shape.
  Converting a project to or from ECM doesn't change them either.

## CharPad C16 (`.ctt`)

CharPad C16 Pro (3.69 and 3.81 checked, 2026-11-01) saves `.ctt` projects: magic
`CTT`, version 8 (CharPad C16 3.4) or 9 (3.5; the key map in the high nibble of
the flags byte was added in October 2023). Official specs: `Help/File Format -
CTT (V8|V9).htm` in its releases, which also hold 807 V9 samples and no V8 file.
CharPad C64 Pro 3.88 can also open them (`CPV_FileIO_CTT8_Converter`,
`CTT9_Converter`) and the layout below agrees with that code. The blocks are
those of CTM V8 and V9; the header and colours differ:

| Offset | CTT V8 | CTT V9 |
| --- | --- | --- |
| 4 | display mode | display mode |
| 5 | colouring method | colouring method |
| 6 | flags, bit 0 tile system | flags, key map (0-10) in the high nibble |
| 7 | 4 chip colours | flexi-grid width, height, settings (as CTM V9) |
| 11 | 2 project colours | |
| 12 | | 4 chip colours |
| 16 | | 2 project colours |
| size | 13 | 18 |

- Colours are TED colours, 7 bits: luma (bits 4-6) times 16 plus chroma (bits
  0-3). The palette has 16 chromas of 8 lumas; black stays black at every luma
  (120 different colours). `src/batchpad/ctt.nim` holds VICE 3.9's internal TED palette (xplus4, default colour controls, read off a screenshot with the render filter off), not CharPad C16's own (see `docs/palettes/`).
- The project colours are two bytes in every mode. Text modes use the first;
  the second is unused but samples keep a value in it, so we keep it (in
  `colours[1]`) to write files back as read. Bitmap modes use both.
- Per-char and per-tile colour blocks: 1 byte in text modes, 2 in bitmap modes.
  The spec calls them the Colour Matrix and Screen Matrix colour; C64 Pro's
  converter reads the first as pen 01/1 and the second as pen 10/0, which is
  what we do (first into `colours[2]`, second into `colours[1]`). There is no
  colour-RAM byte; multicolour bitmap takes pen 11 from chip colour 1, the same
  for every cell.
- Multicolour text: bit 3 of a cell's chroma says multicolour, as bit 3 of a
  C64 colour does, so only chromas 0-7 are usable. Chromas 0-7 are the same
  colours as C64 colours 0-7 (black, white, red, cyan, purple, green, blue,
  yellow).
- The tile name block is there as in CTM V8. Limits: the format holds 65536
  chars and tiles, tiles of 255 x 255 and maps of 65535 x 65535; CharPad C16
  3.5 itself stops at tiles of 10 x 10 and maps of 8192 x 8192.
- CharPad C64 Pro's converter maps each TED colour to the nearest C64 colour
  and changes the file name to `.ctm`; in per-project multicolour bitmap it
  moves chip colour 1 to the colour RAM colour. CharPad C16 has a C64 to C16
  converter of its own, using the VICE palettes (dev log, 3.5 and later).
- What we do: `ctt.nim` reads and writes V8 and V9 (all 807 samples read and
  write back byte for byte; V8 has no sample, so it follows the spec) and keeps
  the TED colours (`Project.ted`). `convert` to `ctm` maps them to the nearest
  VICE colour as above; `convert` from a CTM to `ctt` maps back (multicolour
  text keeps the multicolour flag and only the luma is picked, multicolour
  bitmap makes pen 11 the shared chip colour 1 and reports cells that differ).
  The colour conversions are approximate and not CharPad's own.
- Raw exports follow CharPad C16's text: `char-attribs` and `tile-attribs`
  hold the TED colour in the text modes (luma and chroma, no material, see
  `char-materials`) and in the bitmap modes the lumas (pen 10/0 high, 01/1
  low); `char-attribs-l2` and `tile-attribs-l2` the chromas (01/1 high, 10/0
  low). These two are there in both bitmap modes.
- Not done: `png`, `gif` and `stats` of a `.ctt` (they say so).

## Tilemedo (`.tmd`)

Tilemedo (Phil / Retroleum, freeware, Windows; `software/tilemedo.zip` holds
version 1.10, its help `tilemedo.html` with the format, and two example
projects) is a 4 x 4 tile map editor for C64 text modes. batchpad reads and
writes its projects as CharPad projects (#80): `src/batchpad/tmd.nim`.

All numbers little-endian:

| Size | Contents |
| --- | --- |
| 4 | length of the file, counting itself |
| 1 | mode: 0 mixed (hires and multicolour chars), 1 hires chars only |
| 1 | background colour ($d021) |
| 1 | multicolour 0 ($d022) |
| 1 | multicolour 1 ($d023) |
| 2 | number of chars |
| 8 per char | char data |
| 1 per char | char colour (colour RAM: in mixed mode 8-15 are multicolour chars) |
| 1 | tile width |
| 1 | tile height |
| 2 | number of tiles |
| width x height per tile | char numbers, a byte each |
| 2 | map width, in tiles |
| 2 | map height |
| 1 per map cell | tile numbers |
| 1 per map cell | trigger map: only when it is switched on in Tilemedo |

There is no signature: batchpad takes a `.tmd` whose first 4 bytes are its size
and whose mode is 0 or 1. The trigger map is there when the file has a map's
worth of bytes left; any other number of bytes left is an error.

As a CharPad project: per char colouring, tile system on, hires or multicolour
text. Char and tile numbers are bytes, so at most 256 of each are usable. The
trigger map has no place in a CTM: the model keeps it in `Project.triggers`,
`bin`/`asm`/`c` write it as part `triggers`, and writing a CTM or CTT leaves it
out with a warning. Writing a `.tmd` leaves out (with a warning) materials, tile
tags and names, the key map, the flexi-grid, chars and tiles past 256; ECM is
written as hires; per project or per tile colours become per char colours (a
char in tiles of different colours keeps the first). Bitmap modes and projects
without tiles are refused.

Checked: both example projects read and write back byte for byte (directly
and through a CTM V9), and `png ... map` of each gives the same pixels as the
`.bmp` Tilemedo exported of it (one RGB colour for one RGB colour; the palettes
differ). Tilemedo itself was not run.

Tilemedo's headerless exports are batchpad's raw parts: charset `chars`,
colours `char-attribs` (the material nibble is 0), tile set `tiles` with
`--cells 8`, map `map` with `--cells 8`, trigger map `triggers`. Its BMP map
import and export belong with #72.

## What has been checked in CharPad itself

- CharPad opened the version 7 file from `grotten_playfield.py` without problems
  (checked by the user, 2026-10-17). The file has the tile system on, colour per
  char, multicolour, 507 chars (256 plus 251 copies), 128 tiles and a 128 x 64 map.
  So more than 256 chars in a version 7 file works.
- Copter Duel's tile-less version 7 export works in CharPad Free 2.86.
- Export, then import with no edits, gives back the same bytes in both projects.
- CharPad C64 Pro 3.88 shows tile 1's tag as 0 right after loading a V7 or V9 file,
  although the file holds another value and Pro's loader reads it unchanged.
  Setting it, saving and reloading gives 0 again; the saved file does hold the
  new tag. A CharPad bug in the Tile Editor: loading selects tile 1, while the
  editor shows tile 0 and its tag; the tag field writes that tag to the
  selected tiles, so tile 1 gets tile 0's tag. Other tiles keep their tag
  (checked by the user for V9 and V7, 2026-10-18; tile 1 selected on load,
  2026-10-19). CharPad Free 2.86 does not show tags at all.

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
