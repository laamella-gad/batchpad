# What CharPad, SpritePad and Glaze import and export

Covers the releases on itch.io: CharPad C64 Pro 3.88, CharPad Free 2.86,
SpritePad C64 Pro 3.80 and CharPad Glaze C64 1.60. Sources: the `File IO
Importing`, `File IO Exporting` and `File Format - C64 - *` help pages, and the
menu items, file filters and text templates in the .NET exes (found with
`strings -el`). The exact layouts, file names and text templates of CharPad
Pro 3.88 and SpritePad Pro 3.80 come from their decompiled `_NET.exe` builds
(ilspycmd, 2026-10-18). Nothing below has been tried in the programs yet
unless it says so.

## Summary

| Format | CharPad Pro | CharPad Free | SpritePad Pro | Glaze |
| --- | --- | --- | --- | --- |
| Own project (`.ctm` / `.spd`) | read V1-V9 (not V3), write V9; "Export Project" writes V5, V6, V7, V8 | read V1-V7, write V7; export V5, V6 | read headerless 1.8 and SPD V1-V5, write V5 | read CTM V1-V9 (not V3), save V9 |
| CharPad C16 project (`.ctt`) | open (file filter) | - | - | - |
| Raw binary | import, export | import, export | import, export | export |
| Assembler text (`.asm`, 64tass) | export; import map as text | export; import map as text | export | export |
| Images (BMP, PNG, GIF) | import (Image Importer), export | import BMP/PNG, export | import, export, sheets, animated GIF | - |
| VICE snapshot (`.vsf`) | import (Snapshot Ripper) | import | import | - |
| SEUCK | `.B` background, import, export | `.B`, import, export | `.A` sprites, import, export | - |
| Koala Painter, Art Studio, Advanced Art Studio | import, export | - | - | - |
| Palette (`.pal` text, or image) | import, export | - | import, export | - |

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

Cell widths for tiles, maps, areas and sub-maps (Pro; Free has 8 bit only):

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
| Ignore | 0 | every sprite multicolour, colour 12 (`$8c`) |

Import of sprites: count = file size / 64, 2 bytes skipped first when the size
is 2 mod 64. The sprite set is resized and all sprite animations are reset.
Attributes: a byte per sprite, up to the current count. Tiles: 8 bit, loaded
over the existing tiles with their existing size.

"Export All (essentials, multiple files)" writes `<name> - Sprites.bin`
(SpritePad style), `<name> - SpriteAttribs.bin`, and with tiles
`<name> - Tiles.bin` and `<name> - TileAttribs.bin`. Animations have no binary
export.

### Glaze

Glaze exports `chars1_Nx.bin` to `chars4_Nx.bin` (four char sets, the four
steps of the scroll animation), `char_attribs_Nx.bin`, `mapfg_WxH.bin` and
`mapbg_WxH.bin`.

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
  bytes; 128 tiles of 5 x 5 bytes; 254 chars of 8 bytes; then 9 x `$ff` and
  `$cf`. CharPad only exports a project with exactly those sizes and per-tile
  colouring.

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

- Raw binary: write and read (#41, #42).
- Assembler source: write, for several assemblers, 64tass first (#43).
- C source for oscar64: the same data as arrays, tile events as function pointers (#53).
- CharPad Pro extras: flexi-grid sub-maps (#44), colour map (#45), tile event
  jump table (#46), usage statistics (#47).
- PNG previews (#48), animated GIFs of SpritePad animations (#49), `.pal`
  palettes for colouring both (#50).
- CharPad C16 `.ctt`: decide after #40 (#51).
- A load address option shared by binary exports and imports (#54).
- Skipped: SEUCK, Koala / Art Studio / Advanced Art Studio, image import,
  VICE snapshots, Glaze's parallax build.

## Glaze

Glaze reads a foreground and a background CharPad project and builds parallax
scrolling data: the four char sets, char attributes, and both maps, in 8, 12 or
16 bits, as binaries or 64tass source.
