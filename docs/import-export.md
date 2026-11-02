# What CharPad, SpritePad and Glaze import and export

Covers the releases on itch.io: CharPad C64 Pro 3.88, CharPad Free 2.86,
SpritePad C64 Pro 3.80 and CharPad Glaze C64 1.60. Sources: the `File IO
Importing`, `File IO Exporting` and `File Format - C64 - *` help pages, and the
menu items, file filters and text templates in the .NET exes (found with
`strings -el`). The exact layouts, file names and text templates come from the
decompiled `_NET.exe` builds of all four (ilspycmd, 2026-10-18). Nothing below
has been tried in the programs yet unless it says so.

## Summary

| Format | CharPad Pro | CharPad Free | SpritePad Pro | Glaze |
| --- | --- | --- | --- | --- |
| Own project (`.ctm` / `.spd`) | read V1-V9 (not V3), write V9; "Export Project" writes V5, V6, V7, V8 | read V1-V7 (not V3), write V7; export V5, V6; ECM opens as hires | read headerless 1.8 and SPD V1-V5, write V5 | read CTM V4-V9; no project save |
| CharPad C16 project (`.ctt`) | open (file filter) | - | - | - |
| Raw binary | import, export | import, export | import, export | export |
| Assembler text (`.asm`, 64tass) | export; import map as text | export (own template); import map as text | export | export |
| Images (BMP, PNG, GIF) | import (Image Importer), export | import BMP/PNG, export | import, export, sheets, animated GIF | - |
| VICE snapshot (`.vsf`) | import (Snapshot Ripper) | import | import | - |
| SEUCK | `.B` background, import, export | `.B`, import, export | `.A` sprites, import, export | - |
| Koala Painter, Art Studio, Advanced Art Studio | import, export | - | - | - |
| Palette (`.pal` text, or image) | import, export | - | import, export | - |

batchpad reads and writes `.ctt` V8 and V9 (#40, #79; see `charpad.md`): `convert` to and from `ctm`, `bin`, `asm` and `c` straight from a `.ctt`, and `png`, `bmp` and `stats` of one (#81).

Internal files, not for exchange: the clipboard files
(`CharPadC64_CopiedChars.bin`, `SpritePad_CopiedSprites.bin`, ...), the
Snapshot Ripper's `.ini` settings, and `AppPaletteAuto*.pal`.

## Own project files

CTM and SPD are described in `charpad.md` and `spritepad.md`.

CharPad Pro 3.88 has "Export Project (CTM version 5)" up to "(CTM version 8)",
so it can still write V8, for which there are no samples yet. CharPad Free 2.86
has the same for V5 and V6. The V5 and V6 savers refuse display modes above
multicolour text and V7 above ECM; otherwise they drop what the version can't
hold. What the loaders do with each version: `charpad.md`, "What CharPad Pro
3.88 does with each version", and `spritepad.md`, "What SpritePad Pro 3.80
does".

CharPad Pro also opens CharPad C16 projects (`.ctt` V8 and V9) and converts
their TED colours to C64 ones; the layout is in `charpad.md`.

## Raw binary

Plain data: no header, no sizes, no load address on export. Tile and map
imports need the project to have the right dimensions first.

### CharPad

| File | Contents |
| --- | --- |
| Chars | 8 bytes per char, top row first. |
| Char attributes L1 | 1 byte per char: material in the high nibble, colour matrix colour in the low nibble. The colour is 0 unless colouring is per char and the mode isn't hires bitmap. Free 2.86 has this one only. |
| Char attributes L2 (Pro) | 1 byte per char: video matrix high nibble, low nibble (the two bitmap colours). 0 unless colouring is per char in a bitmap mode. |
| Char attributes M (Pro) | 1 byte per char, the material. Export only. |
| Tiles | tile width x height cells per tile, top left first, row by row. |
| Tile attributes L1, L2 | 1 byte per tile, as for chars but with the high nibble of L1 always 0. 0 unless colouring is per tile. |
| Map, selected map area | width x height cells, top left first, row by row. |
| Flexi-grid sub-maps (Pro) | The map cut into flexi-grid cells, see below. |
| Colour map (Pro) | 1 byte per char cell of the whole map (map size x tile size): the colour matrix colour of the project, tile or char, depending on the colouring method. 0 for a char number out of range. |

Cell widths for tiles, maps, areas and sub-maps (Pro; Free 2.86 has 8 bit
only, see below):

- 8 bit: a byte per cell, the value's low byte.
- 12 bit "split, packed": a file of low bytes (`12bpc LSBs`) and a file of the
  next 4 bits (`12bpc MSNs`), two cells per byte: the even cell in the high
  nibble, the odd one in the low nibble. With an odd cell count the last low
  nibble is 0.
- 16 bit "split": a file of low bytes and a file of high bytes (`16bpc LSBs`,
  `16bpc MSBs`).

CharPad warns when a cell value may not fit (more tiles or chars than 2^bits)
but writes the file anyway, clipped.

"Export All (essentials, multiple files, configurable)" asks for a directory and
writes, with `<name>` the project's file name without extension:

- `<name> - Chars.bin`, `<name> - CharAttribs_L1.bin`,
  `<name> - CharAttribs_M.bin`, and `<name> - CharAttribs_L2.bin` when colouring
  is per char in a bitmap mode.
- With tiles: `<name> - Tiles (WxH), 8bpc.bin`, or the pair
  `... 12bpc LSBs.bin` / `... 12bpc MSNs.bin`, or `... 16bpc LSBs.bin` /
  `... 16bpc MSBs.bin`. When colouring is per tile, `<name> -
  TileAttribs_L1.bin`, plus `_L2` in bitmap modes.
- The map as `<name> - Map (WxH), 8bpc.bin` (or the 12/16-bit pairs), or only
  the selected area, or the sub-maps as `<name> - SubMap (WxH) [yy,xx],
  8bpc.bin` (two-digit indices, row first).

The single-item menu entries export 8 bit only: `Tiles (8bpc, WxH)`,
`Map (8bpc, WxH)`, `MapArea (8bpc, WxH)`, `ColourMap (8bpc, WxH)`, and sub-maps
either one file each or all in one file, `SubMaps (8bpc, [NxM]x[WxH])`.

Sub-maps: the map is cut into flexi-grid cells, floor(map size / cell size)
in each direction; a partial cell at the right or bottom is dropped. The
consolidated file holds them row by row of sub-maps, each sub-map's cells
together, row by row. CharPad refuses when the project has tiles and the
flexi-grid is measured in chars.

Import:

- Chars: count = file size / 8; 2 bytes are skipped first when the size is 2
  mod 8 (a PRG load address). The char set is resized to fit.
- Char attributes L1, L2: a byte per char, up to the current char count. No
  import for M.
- Tiles: 8 bit only; as many tiles as the file holds (size / tile area), up to
  the current tile count. Sets the whole cell value, so tiles above char 255
  can't be imported.
- Tile attributes L1, L2.
- Map: 8 bit only, fills the current map row by row.

CharPad Free 2.86 has a smaller set, all 8 bit (the low byte of each cell):

- Chars, `<name> - Chars`; char attributes (L1), `<name> - CharAttribs`; tiles,
  `<name> - Tiles`; tile colours, `<name> - TileAttribs` (the low nibble, high
  nibble 0); map, `<name> - Map (8bpc, WxH)`; map area,
  `<name> - MapArea (8bpc, WxH)`; sub-maps, one file each,
  `<name> - SubMap (8bpc, WxH) [y,x].bin` (indices not padded). No colour map,
  no consolidated sub-maps, no L2 or M.
- "Export All" writes `<name> - Chars.bin`, `<name> - CharAttribs.bin`,
  `<name> - Tiles.bin`, `<name> - TileAttribs.bin` (only when colouring is per
  tile) and `<name> - Map (WxH).bin` (no `8bpc` in this name).
- Imports work as in Pro: chars skip a load address when the size is 2 mod 8;
  the others load over the existing data. A 16-bit map is only possible as
  assembler text (below).

CharPad 1.7 (Ghidra decompile of its exe; not on itch.io) has one export
dialog with four checkboxes and a Raw/PRG choice:

- Chars, default name `CHARS`: 8 bytes per char, without the 9th (material)
  byte.
- Tiles, `TILES`: n x n cells per tile (tiles are square), row by row, the low
  byte of each cell. The bundled `Docs/CharPad - Export Formats.txt` says it
  warns above 256 chars; the exe has no such message, it just truncates.
- Tile colours, `TILECOLOURS`: one byte per tile. The bundled doc doesn't
  mention this one.
- Map, `MAP`: one byte per cell, row by row. 1.7 keeps the map as bytes.
- PRG puts a little-endian load address in front of each file. Each file has
  its own address field, in hex with digits `0-9` and `A-F` only (no lower
  case, no `$`); an empty or invalid field gives "Not all PRG addresses are
  valid" and nothing is written.
- Import takes chars only: a size of 2 mod 8 skips a load address, and 1 to
  256 chars are accepted. It starts a new project with that many 1 x 1 tiles
  (tile n = char n), the map keeps its size but is cleared to 0, tile colours
  become `$0d`, and multicolour and per-tile colouring are switched on.

### SpritePad

| File | Contents |
| --- | --- |
| Sprites | 64 bytes per sprite. The 64th byte depends on the attribute style, below. |
| Sprite attributes | 1 byte per sprite: `MYXVCCCC`, multicolour, expand Y, expand X, has overlay, colour. The same as the 64th byte. |
| Tiles | tile width x height sprite numbers per tile, top left first, 8 bit only (SpritePad warns above 256 sprites). |
| Tile attributes | 1 byte per tile, `000V0000`: has overlay. Export only. |

Sprite export and import ask for an attribute style for the 64th byte:

| Style | Export | Import |
| --- | --- | --- |
| SpritePad | `MYXVCCCC` | taken as it is |
| SEUCK | colour, plus `$10` if multicolour | bit 4 becomes multicolour; the other high bits are dropped |
| Blank (`Ignore` in the code) | 0 | every sprite multicolour, colour 12 (`$8c`) |

Import of sprites: count = file size / 64, 2 bytes skipped first when the size
is 2 mod 64. The sprite set is resized and all sprite animations are reset.
Attributes: a byte per sprite, up to the current count. Tiles: 8 bit, loaded
over the existing tiles with their existing size.

"Export All (essentials, multiple files)" writes `<name> - Sprites.bin`
(SpritePad style), `<name> - SpriteAttribs.bin`, and with tiles
`<name> - Tiles.bin` and `<name> - TileAttribs.bin`. Animations have no binary
export.

### Glaze

"Export binaries" asks for a directory and writes, with N the char count of
each set:

- `chars1_Nx.bin` to `chars4_Nx.bin`: the four char sets, 8 bytes per char.
- `char_attribs_Nx.bin`: the L1 byte per char (material, colour), as in Pro.
- `mapfg_WxH.bin`, `mapbg_WxH.bin`: the two maps, 8 bit only. Glaze warns when
  a set has more than 256 chars and writes the low bytes anyway.

What goes into them is under "Glaze" at the end.

## Assembler text

The `.asm` files are written for 64tass, with CRLF line endings. Data goes in
`.byte` lines of 16 values, `$xx` in lower case, separated by a comma without a
space. Each part starts with a `;` comment that gives its size, then a
`* = addr_...` line and a label.

### CharPad header

```
; Generated by CharPad C64 - Subchrist Software, 2003-2026.
; Assemble with 64TASS or similar.


; Display mode : <mode>.
; Matrix colouring method : <method>.


; Colour values...

; cmxlo = colour matrix low nybble.
; vmxlo = video matrix low nybble.
; vmxhi = video matrix high nybble.
; nb. any matrix colours listed here are usually only needed in a 'per project' matrix colouring system.

colr_vic_bg0 = 0
colr_cmxlo_proj = 1


; Quantities and dimensions...

char_count = 256
tile_count = 64
...

; Data block addresses (dummy values) and sizes...

addr_charset_data = $1000
size_charset_data = $800 ; (2048 bytes)
...
; * INSERT EXAMPLE PROGRAM HERE! * (or just include this file in your project).
```

- Colour constants by display mode: hires text `colr_vic_bg0`,
  `colr_cmxlo_proj`; multicolour text adds `colr_vic_bg1`, `bg2`; ECM adds
  `bg3`; hires bitmap only `colr_vmxlo_proj`, `colr_vmxhi_proj`; multicolour
  bitmap `colr_vic_bg0`, `colr_cmxlo_proj`, `colr_vmxlo_proj`,
  `colr_vmxhi_proj`.
- Quantities: `char_count`; with tiles `tile_count`, `tile_wid`, `tile_hei`;
  `map_wid`, `map_hei`; with tiles also `map_wid_chrs`, `map_hei_chrs`,
  `map_wid_pxls`, `map_hei_pxls`.
- Address and size pairs (all addresses `$1000`, the sizes in hex with the
  decimal in a comment): `charset_data`, `charset_attrib_L1_data`,
  `charset_attrib_L2_data` (per char, bitmap modes), `chartileset_data`,
  `chartileset_attrib_L1_data` and `_L2_data` (per tile), `chartileset_tag_data`,
  `map_data`.
- Quirk: in 12- and 16-bit output the blocks use `* = addr_map_data_lo`,
  `addr_map_data_hi` and `addr_map_data_hi_packed` (and the same for
  `chartileset`), which the header never defines, and `size_map_data` stays the
  cell count. The file doesn't assemble as is. Ours should define them.

### CharPad blocks

`charset_data`, `charset_attrib_L1_data`, `charset_attrib_L2_data`,
`chartileset_data` (16 bit: `_lo`, `_hi`; 12 bit: `_lo`, `_hi_packed`),
`chartileset_attrib_L1_data`, `_L2_data`, `chartileset_tag_data`,
`chartileset_names` (`* = addr_chartileset_names`, undefined too, then a
`.text "name", 0` line per tile), `map_data` (and the
same suffixes), `colourmap_data`.

"Export All (one file)" writes the header, then chars, char L1, char L2, tiles,
tile L1, tile L2, tags and the map. Names, events and the colour map have their
own menu entries.

Sub-maps in text: a `; SubMap (y,x)...` comment and a label
`submap_y{i}_x{j}_data` (or with `_lo`/`_hi`, `_lo`/`_hi_packed`) per sub-map,
without `* =` lines.

**Tile events** ("Export Tile Events"): `* = addr_chartileset_eventjumptable`,
the label `chartileset_eventjumptable`, then `.word` lines of 4 entries
separated by `, `: `chtl_<name>_event` per tile, or `chtl_null_event` for a
tile without a name. "Alt" leaves out prefix and suffix (`<name>`,
`null_event`). Then `* = addr_chartileset_events`, the label
`chartileset_events`, a `chtl_null_event` stub that is just `rts`, and an `rts`
stub for each distinct name, each after a `; event: chartile "<name>".`
comment. The name goes into the label as it is, so a name with spaces won't
assemble; neither address is defined in the header.

**Usage statistics** (plain text):

```
Generated by CharPad C64, Subchrist Software, 2003-2026.
Stats - Character image occurrences in the tile-set...
Char    | Occurrences
```

then a row per char, `{0,-7}   {1,-7}` (number and count, each padded to 7).
Without tiles it counts `in the map...`. Tile statistics are the same with
`Tile    | Occurrences`.

**Import Map (ASCII text)**: needs a key map (V9 header) and a file of at most
100 KB. The map is resized to (width, 10) and cleared. Each space-separated
word is written through the key map's ASCII table, with an empty cell between
words, and a new map row per line.

### CharPad Free 2.86

Free 2.86 still writes the CharPad 2.8 template, which differs from Pro's
throughout. There are no `* = addr_...` lines, so it assembles as it is. Its
header (part of "Export All" only):

```


; Generated by CharPad 2.8, Subchrist Software, 2021.
; Assemble with 64TASS or similar.


; Character display mode : Multi-colour.

; Character colouring method : Per-Tile.

; Colour values...

COLR_SCREEN = 0
COLR_CHAR_DEF = 1
COLR_CHAR_MC1 = 2
COLR_CHAR_MC2 = 3


; Quantities and dimensions...

CHAR_COUNT = 256
TILE_COUNT = 64
...

; Data block sizes (in bytes)...

SZ_CHARSET_DATA        = 2048 ; ($800)
...
```

- Display modes: `High Resolution`, `Multi-colour`, `Extended Colour (ECM)`;
  colouring methods: `Per-Map`, `Per-Tile`, `Per-Character`.
- Colours: hires `COLR_SCREEN` (background) and `COLR_CHAR_DEF` (the
  project's char colour); multicolour adds `COLR_CHAR_MC1`, `MC2`; ECM
  `COLR_CHAR_DEF` and `COLR_CHAR_BG1` to `BG4`.
- Quantities as in Pro, in upper case: `CHAR_COUNT`, `TILE_COUNT`, `TILE_WID`,
  `TILE_HEI`, `MAP_WID`, `MAP_HEI`, `MAP_WID_CHRS`, ... `MAP_HEI_PXLS`.
- Sizes, decimal with the hex in a comment: `SZ_CHARSET_DATA`,
  `SZ_CHARSET_ATTRIB_DATA`, `SZ_TILESET_DATA`, `SZ_TILESET_ATTRIB_DATA` (per
  tile only), `SZ_MAP_DATA`.

Blocks, each after a `; CHARSET IMAGE DATA...`-style comment and a size line:

- `charset_data`; `charset_attrib_data` (the L1 byte).
- `chartileset_data`, 8 bit only; `chartileset_colour_data` (per tile only);
  `chartileset_tag_data`. No names.
- `map_data` (8 bit), or `map_data_lo` + `map_data_hi` for both 16 bit and
  12 bit. In 12 bit, `map_data_hi` holds the packed nibbles (Pro calls it
  `_hi_packed`).
- Sub-maps: one file, `; Generated by CharPad 2.87...`, then per sub-map
  `; SUB-MAP (y,x)...` and `submap_y{i}_x{j}_data` (or `_lo`/`_hi`).
- Tile events: the label is `chartile_eventjumptable` and `chartile_events`
  (Pro: `chartileset_...`), the same entries and stubs otherwise. "Alt" leaves
  out the prefix and suffix.
- Statistics: the same as Pro's, with `Generated by CharPad 2.8, Subchrist
  Software, 2021.`

"Export All" writes the header, chars, char attributes, tiles (with colours
when per tile, and tags) and the 8-bit map.

### Glaze

"Export source" (default name `CharPadGlazeC64Data`) uses Pro's template:

- Header `; Generated by CharPad Glaze C64 - Subchrist Software, 2003-2026.`,
  display mode, colouring method (always per character after the build), and
  the colour constants as in Pro.
- `char_count`; `mapbg_wid_chrs`, `mapbg_hei_chrs`, `mapbg_wid_pxls`,
  `mapbg_hei_pxls`, and the same for `mapfg`.
- Addresses and sizes: `charset1_data` to `charset4_data` at `$1000`, `$1800`,
  `$2000`, `$2800`; `charset_attrib_L1_data`, `mapbg_data` and `mapfg_data` at
  `$1000`. All are defined, so the file assembles once the addresses are set.
- Blocks with `* =` lines in that order: `charset1_data` to `charset4_data`,
  `charset_attrib_L1_data`, `mapbg_data`, `mapfg_data`; maps 8 bit only.

### SpritePad

```
; Generated by SpritePad C64 - Subchrist Software, 2003-2025.
; Assemble with 64TASS or similar.


; Colour values...

colr_vic_bg0 = 0
colr_vic_sprite_mc1 = 1
colr_vic_sprite_mc2 = 2


; Quantities and dimensions...

sprite_count = 32
spriteanim_count = 4        ; when there are sprite animations
spritetile_count = 12       ; these three when there are tiles
spritetile_wid = 2
spritetile_hei = 2


; Data block addresses (dummy values) and sizes...

addr_spriteset_data = $1000
size_spriteset_data = $800 ; (2048 bytes)
```

Address and size pairs: `spriteset_data`, `spriteset_attrib_data`; with tiles
`spritetileset_data`, `spritetileset_attrib_data`, `spritetileset_tag_data`;
`spriteanimset_data` and `spritetileanimset_data` (4 bytes per animation).
Then the same `INSERT EXAMPLE PROGRAM HERE!` line.

Blocks:

- `spriteset_data`, then `sprite_image_<n>` before each sprite's 64 bytes
  (SpritePad attribute style).
- `spriteset_attrib_data`: the attribute bytes.
- `spritetileset_data` (8 bit), `spritetileset_attrib_data`,
  `spritetileset_tag_data`.
- `spriteanimset_data`, then four lists: `sprite_anims_from`,
  `sprite_anims_to`, `sprite_anims_timereload`, `sprite_anims_attrib` (`$10`
  for ping-pong). The frame numbers are written as bytes, so above 255 they
  are clipped.
- `spritetileanimset_data` with `spritetile_anims_from`, `_to`,
  `_timereload`, `_attrib`.

"Export All (essentials, one file)" writes all of these in that order. The
separate entries write sprites with attributes, tiles with attributes and tags,
sprite animations or tile animations.

## Animated GIFs (SpritePad)

"Export Sprite Animation" and "Export Tile Animation" write the current
animation as `<name> - AnimNN.gif`. Options: scale (default 2), a border of a
chosen colour, painted or not. Frame delay in 1/100 s: (timer reload + 1) x 2,
or 2 when the timer reload is 0 or 1. So the timer counts 50 Hz frames.

## Images

- Import (BMP, PNG, GIF): the Image Importer picks a colour scheme for the
  display mode and turns each 8 x 8 area (CharPad) or sprite-sized area
  (SpritePad) into a char or sprite. CharPad removes duplicate chars and builds
  a map.
- Export: CharPad exports the char set, tile set or map as BMP or PNG.
  SpritePad also writes sprite and tile sheets, and animations as animated GIFs
  ("GIF Composer", optionally scaled to tile size).
- batchpad (#72): `png` and `bmp` write the chars, tiles and map (CharPad)
  or the sprite and tile sheets (SpritePad); `gif` the animations.
  `fromimage` reads a BMP or PNG into hires or multicolour text chars plus a
  map (or tiles, `--tiles WxH`, #76), or into sprites (nearest colour, equal
  chars merged; see cli.md). Not done: ECM and bitmap modes, GIF input, a
  colour scheme per area as CharPad's Image Importer picks.

## VICE snapshots

The Snapshot Ripper reads a VICE `.vsf` snapshot, which holds the C64's 64 KB
RAM, and lets the user look for chars, tiles, maps or sprites in it by hand,
in all eight orders ("Z-pattern" formats) for tile and map data. That is how
most of the bundled game rips were made.

## SEUCK

The Shoot 'em Up Construction Kit (1987). Its files start with `$42, $00`, and
on disk their names are 16 characters ending in `.A` to `.G`.

- `.A` sprites, 8130 bytes: the signature, then 127 sprites of 64 bytes, the
  64th byte `xxxM CCCC`. SpritePad pads to 127 sprites on export.
- `.B` background, 9596 bytes: the signature; the map, 8 x 512 bytes, left to
  right then bottom to top; tile colours, 128 bytes (low nibble); 128 unused
  bytes; 128 tiles of 5 x 5 bytes; 254 chars of 8 bytes; then `$3f` and
  9 x `$ff`. CharPad only exports a project with exactly those sizes and
  per-tile colouring. Loading masks the tile colours with `$0f` and skips the
  last 10 bytes.
- CharPad 1.7 (`Docs/CharPad - Export Formats.txt` and its decompiled exe)
  also saved and loaded `.B` files, with the same 9596-byte layout. It asks
  "Is this background for the sideways SEUCK mod?", since nothing in the file
  tells. The sideways map is 819 wide x 5 high, and takes the 4096 map bytes
  as 819 columns, right to left, each column bottom to top, then one `$00`.
  On save 1.7 needs 5 x 5 tiles, multicolour, per-tile colouring, a map of
  8 x 512 or 819 x 5 and at most 254 chars; fewer than 128 tiles or 254 chars
  are padded with zeros. It loads the tile colour bytes unmasked and sets
  $d021 to `$0b`, $d022 to `$00`, $d023 to `$01` and the char colour to `$0d`.
  Pro has no sideways option.

batchpad (`src/batchpad/seuck.nim`, #56, #57) follows Pro 3.88's loader and
saver, read from the decompiled code (`CPV_FileIO_SEUCK`): the loader only
checks that the file is 9596 bytes, not the signature; it reads the file's map
rows into the project's rows 511 down to 0, masks the 128 tile colours with
`$0f`, skips the 128 unused bytes and the last 10 bytes, and leaves everything
else at defaults (multicolour text, per-tile colouring, 254 chars, 128 tiles,
5 x 5). The saver refuses a project that isn't exactly that, and writes
`$42 $00`, the map, the tile colours, 128 zeros, the tiles, the chars, `$3f`
and 9 x `$ff`. `.A` follows SpritePad Pro's rules (above). The sideways
variant follows 1.7 as noted here and has not been checked against a real
file; it pads fewer tiles and chars and keeps tile colours unmasked.

`inject` (#86) writes a sprite project and a CharPad project into a game's
`.I` (bare or in a `.P00`), at the addresses of the memory map below, and
leaves every other byte alone (docs/cli.md). The game's bits that projects
don't hold stay: bits 5 to 7 of the sprites' 64th bytes (`$20` is set in some
games) and the high nibble of tile colours (`$10` in some). Checked on the 48
"save all data" files of the repository below: reading each into a `.spd` and
a `.ctm` and injecting those gives the same file back, byte for byte.

### Real files (checked 2026-11-01)

Real `.A` and `.B` files are in Martin Piper's repository
[martinpiper/C64Public](https://github.com/martinpiper/C64Public) (no licence,
so none are copied into `tests/files/`; tests build their own bytes): `SEUCK/Debug1/T______A.P00`
and `T______B.P00`, `SEUCK/BG1____B.P00`, and many "save all data" `.P00`
files. They are `.P00` (PC64) files: a 26-byte header (`C64File`, a 16-byte
name, two zero bytes), then the file as SEUCK saved it. With the header cut off
they are 8130 bytes (`.A`) and 9596 bytes (`.B`), start with `$42 $00`, and
batchpad reads them with the sizes and layouts above.

Writing such a file back with `convert` changes only bytes that loading does
not use:

- `.A`: the high bits 5 to 7 of the 64th byte of some sprites (`$CC` becomes
  `$0C`). Colour and multicolour are kept. What those bits mean is not known.
- `.B`: the 128 unused bytes (not zero in real files; we write zeros), the high
  nibble of some tile colours (masked with `$0f`, as Pro does), and the last 10
  bytes (`$ff` in the real file where we write `$3f`). Map, tiles and chars are
  identical.

Martin Piper's SEUCK Redux is a replacement game engine (`Scroller/` in that
repository) that plays the data stock SEUCK saves. His notes
(`Scroller/README.md`, `SEUCK/UnlockTheEditor.txt`) show no change to the file
formats, and the files above have the stock sizes.

### The original disks

`Shoot-em-up-Construction-Kit_C64_EN.zip` (in `software/`, from the GameBase64
collection) holds two `.D64` disks of the original SEUCK: the program, and four
sample games, each as seven PRG files named `game N .a` to `.g` (the 2-byte
PRG load address is the signature `$42 $00`). Sizes: 8130, 9596, 1414, 242,
3062, 156, 514 bytes. All four `.A` and `.B` read, and `convert` writes them back
changing only what is described above, plus: the original `.B` unused bytes are
`$02`, and its last 10 bytes are `$ff` except `$3f` first in game 3 and `$cf`
last in game 4, so loading really must ignore them. The high bits of the sprite
colour byte are set in these original files too (`$20`, `$40`, `$80`, in all
combinations), so they come from SEUCK itself, not from Redux. Each of these
games is also in the repository's `SEUCK/GAME1__I.P00` to `GAME4__I.P00`, and
their memory addresses are the ones in the table below.

### Memory map (#83)

Every SEUCK file is a piece of the editor's memory behind a 2-byte signature
(`$42 $00`, not a real load address). The "save all data" file is the name
ending `.I`: signature, then memory from `$0900` to `$fff9`, 63228 bytes, or
63254 in a `.P00`. Found by searching the files of that repository for the
contents of real `.A` to `.G` files (the repository's own, and the four sample
games of the original disks, see below), which all matched byte for byte:

| File | Address | Bytes | Holds |
| --- | --- | --- | --- |
| `.A` | `$c000` | 8128 | 127 sprites of 64 bytes |
| `.B` | `$0900` to `$267f`, then `$f800` to `$fff9` | 7552 + 2042 | map (8 x 512, 4096), tile colours (128), 128 unused, tiles (128 x 25), then the chars (254 x 8) and the last 10 bytes |
| `.C` | `$2c80` | 1412 | 58 animations of 20 bytes ($488), then 36 enemy property records of 7 bytes ($3108, 252): see below |
| `.D` | `$b810` | 240 | sound effects (the repository's `BRZRKSFX.P00` is one) |
| `.E` | `$340c` | 3060 | enemy attack waves: 7 bytes per enemy from the start, movement streams from the end; see below |
| `.F` | `$b776` | 154 | not worked out; 6-byte records such as `00 01 00 ff 00 00` |
| `.G` | `$f400` | 512 | 64 chars of 8 bytes: the font of the score panel |
| `.I` | `$0900` | 63226 | everything |

A `.B` made from a `.I` this way is identical to the `.B` SEUCK saves from the
same game, and so is a `.A`. Other things in the `.I` that the repository's
sources name: `$4085` to `$4087` the screen colour and the two extra
background colours, `$4081` and `$4083` the two sprite multicolours, `$ae92`
the level table (7 bytes per level: start, end, duration, type and speed,
flags).

#### Animations (`.C`)

Layout from the comments in Piper's `Scroller/ScrollerData.a`, and checked
against the four original games (frames are sprite numbers, the first animations
of every game have plausible contiguous runs such as `32 33 34 ... 3b`):

| Byte | Holds |
| --- | --- |
| 0 to 17 | Frames: sprite numbers (0 to 126). Bit 7 set on a frame marks the end of the animation, which then loops; the bytes after it are leftovers |
| 18 | Animation speed |
| 19 | Low nibble: sprite colour. High nibble: `%0001` directional, `%0010` directional hold |

After the 58 animations come 36 enemy property records of 7 bytes (bullet and
explosion sound, fire type, hits to kill, fire rate, collision and speed bits,
explosion and bullet type, points divided by ten; Piper's file lists them).

#### Attack waves (`.E`)

From the start, 7 bytes per enemy: map position (2 bytes), address of its
movement stream (2), x position / 2, y position, animation number; a position of
`$ffff` ends the list. The movement streams grow down from the end of the
block, each a list of bytes (low nibble the direction bits right, left, down,
up; high nibble the number of frames) ending in `$ff`. Not checked against real
files by batchpad.

### `.P00`

PC64 container (also what VICE writes with `-fs8savep00`): 26 bytes, `C64File`,
`$00`, a 16-byte name padded with spaces or `$00`, `$00`, a record size (`$00`);
then the file. The name is the SEUCK name, `T` and spaces ending in `.A` and so
on, which tells what the file holds. batchpad reads a `.P00` of any name by that
suffix (`.A`, `.B`, `.I`); the other letters are refused with a message.

batchpad reads `.I` files (or a `.P00` of one): the background (`.B`) by
default, the sprites with `--input-format seuck-i-sprites`. It does not write
`.I` or `.P00`, and does not read `.C` to `.G` (#84).

## C64 bitmap pictures

All three are PRG files: a load address, then the data. CharPad exports them
only from a 40 x 25 project in that bitmap mode, without tiles, coloured per
char.

| Format | Mode | Size | Layout after the load address |
| --- | --- | --- | --- |
| Koala Painter (`.kla`, `.koa`) | multicolour | 10003 | bitmap 8000, video matrix 1000, colour matrix 1000, $d021 |
| Art Studio (`.ast`), load $2000 | hires | 9003 (9009 seen) | bitmap 8000, video matrix 1000, border colour |
| Advanced Art Studio (`.aas`), load $2000 | multicolour | 10018 | bitmap 8000, video matrix 1000, border, $d021, 14 unused, colour matrix 1000 |

Koala load address: CharPad Pro writes $4000 (`$00, $40`), as its help says,
and puts $d021 (chip colour 0) in the last byte. Koala files are also commonly
loaded at $6000. The Art Studio loader accepts 9003 to 9012 bytes.

### Multipaint (#68)

[Multipaint](http://multipaint.kameli.net/) (manual: "About file import / export") has no project format. It saves Art Studio (hires) and Advanced Art Studio (multicolour), Koala (multicolour; the default since a 2019 release), PNG, and an "export emulator" `.prg` (a runnable viewer with the picture; FLI and AFLI are not exported). It also loads PNG and JPEG. We don't support Multipaint (#68): its PNG export is easy enough to use, and we don't read these bitmap formats.

## Tilemedo (#80)

Tilemedo 1.10 saves its own `.tmd` project, which batchpad reads and writes as a
CharPad project (layout in [charpad.md](charpad.md#tilemedo-tmd)). Its
headerless binary exports are batchpad's `bin` parts: charset `chars`, colours
`char-attribs`, tile set `tiles --cells 8`, map `map --cells 8`, trigger map
`triggers`. `import` does not take a trigger map. Its BMP map import and export
are #72.

## Petmate (#65)

[Petmate](https://github.com/nurpax/petmate) (a PETSCII screen editor, MIT
licensed) saves a workspace as JSON, `.petmate`. Read from its source
(`src/utils/index.ts` `saveWorkspace`, `src/redux/workspace.ts`), version 2:

```
{"version":2,"screens":[0,1],"framebufs":[{"width":40,"height":25,
 "backgroundColor":6,"borderColor":14,"charset":"upper","name":"title",
 "framebuf":[[{"code":32,"color":14},...],...]}, ...],
 "customFonts":{"custom_1":{"name":"font","font":{"bits":[2048 bytes],"charOrder":[256 numbers]}}}}
```

- `framebufs` holds the screens in order (`screens` is always 0 to N-1). Each
  is 1 x 1 to 1024 x 1024 cells (the size editor clamps to that), rows top to
  bottom, a screen code and a colour (0-15) per cell. `name` is left out when
  the screen has none.
- `charset` is `upper` or `lower` (the C64 ROM charsets, which the file
  doesn't hold) or the key of one of `customFonts`. Version 1 has no
  `customFonts`, and a missing `charset` means `upper`. Custom fonts come
  from a `.64c` (2 bytes load address, then 2048 bytes); `charOrder` only
  orders the chars in Petmate's picker.
- Petmate writes it with `JSON.stringify`: no spaces, keys in the order above.

batchpad reads one screen (`--set screen=N`, default 0) as a hires CharPad
project without tiles: the screen codes are the map, the colours a colour per
cell (part `colour-map`), the background `bg0`. Each char also takes the colour
of the first cell using it (per char colouring, 14 when unused), so a
conversion to CTM or another format without cell colours keeps the closest
thing and warns about the cells whose colour differs. A ROM charset gives 256
blank chars, with a warning when they are written to another format; `info`
shows `romCharset`. The border colour, screen name and font name are kept for
writing Petmate again only.

Writing makes a workspace with one screen. A ROM charset stays a ROM charset;
otherwise the chars become `custom_1` (padded to 256). Tiles are expanded,
multicolour and ECM are written as hires (ECM cells keep their char, not the
background bits), chars past 256 are left out; bitmap modes are refused. Petmate's
other exports (PNG, GIF, `.seq`, `.prg`, BASIC, assembler, C, JSON, `.pet`) are
not read.

## Palettes

A `.pal` text file, or an image of the palette. It sets how the 16 C64
colours look in the editor. It has no effect on the C64 data.

The text format: 16 `#RRGGBB` values separated by spaces, one palette per
line. Older `palettes.pal` files (CharPad 1.7/1.8, SpritePad 1.7/1.8) hold
several lines, each starting with a quoted name (`"Bright Pepto" #000000
...`). CharPad Pro 3.88 ships `ZxSpectrum.pal`: one unnamed line, no newline.

The Pro loader (`SUBC_ColourPaletteARGB.LoadFromText`) looks for each `#`,
reads the 6 hex digits after it as RGB and stops after 16. Everything else,
names included, is skipped, so of a multi-palette file only the first line is
read. The writer starts with a CRLF and writes `#rrggbb ` (lower case, with a
trailing space) per colour, 8 per line.

## What we support

Decided 2026-10-18; issues #41-#51, #53 and #54.

- Raw binary: write and read (#41, #42; done).
- Assembler source: write, for several assemblers, 64tass first (#43).
- C source for oscar64: the same data as arrays, tile events as function pointers (#53; done).
- CharPad Pro extras: flexi-grid sub-maps (#44), colour map (#45), tile event
  jump table (#46), usage statistics (#47).
- PNG previews (#48), animated GIFs of SpritePad animations (#49), `.pal`
  palettes for colouring both (#50).
- CharPad C16 `.ctt` V8 and V9: read and write (#40, #79; done 2026-11-01).
- A load address option shared by binary exports and imports (#54).
- SEUCK `.A` sprites and `.B` backgrounds, and the SEUCK attribute style for
  raw sprites (#56, #57; added 2026-10-18).
- Tiled maps (`.tmx` and JSON): read into the binary, assembler and C exports,
  converted to each other (#66; see tiled.md), from a CharPad project with a
  tileset PNG (#74) and into a CharPad project's map with `--base` (#75).
- SEUCK `.A` and `.B` files: read and write through `convert` (#56, #57; done).
- Tilemedo `.tmd`: read and write as a CharPad project; trigger map as part
  `triggers` (#80; done 2026-11-01).
- Petmate `.petmate`: read and write one screen as a CharPad project; cell
  colours as part `colour-map` (#65; done 2026-11-02).
- BMP export (`bmp`) and import (`fromimage`; text modes and sprites) (#72;
  done 2026-11-02). PNG import too, and tileset images into tiles (#76; done
  2026-11-02).
- Skipped: Koala / Art Studio / Advanced Art Studio,
  VICE snapshots, Glaze's parallax build.

## Glaze

Glaze reads a foreground and a background CharPad project and builds parallax
scrolling data: the four char sets, char attributes, and both maps, 8 bit
only, as binaries or 64tass source (above). It loads CTM V4 to V9 (in the order
V9 down to V4; its V1 and V2 loaders are never called) and saves no project.

The build, from the decompiled code:

1. Both projects must use the same display mode, hires or multicolour text.
   Bitmap modes and ECM are refused.
2. Tiles are expanded into a char map, and colouring is switched to per char.
3. If "insert blank at zero" is on (default) and the foreground's char 0 isn't
   blank, a blank char is inserted there.
4. Duplicate and unused chars are removed from both projects.
5. If "attribute compliance" is on (default), each background char's colour is
   copied to its neighbour in the scroll direction.
6. Every pair in the background map, a char and its neighbour in the scroll
   direction (255 at the map's edge), becomes one new char. Only the low byte
   of the char number is used, so a background above 256 chars breaks.
7. The four sets get the foreground chars first, unchanged, then the pairs,
   scrolled by 0, 2, 4 and 6 pixels in the scroll direction (set 1 to 4).
8. The foreground map keeps its chars, the background map points at the pairs,
   and pairs that come out the same in all four sets are merged.

Scroll directions: up, down, left, right (default right). Glaze's preview
shows set `(7 - fine scroll) / 2` of the background, which moves at half the
foreground speed by default.
