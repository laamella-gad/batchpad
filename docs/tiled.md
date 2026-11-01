# Tiled maps (#66)

[Tiled](https://www.mapeditor.org) (mapeditor.org) saves maps as `.tmx` (XML)
or JSON (`.tmj`, or `.json`). Layouts: doc.mapeditor.org, "TMX Map Format" and
"JSON Map Format". We wrote the readers from those pages and made our own test
files (`tests/files/tiled/`); none of them was opened in Tiled itself.

## What a Tiled map holds

Tile numbers only. A map says which tile sits in which cell; the pictures are in
the image a tileset names (`<image source="tiles.png">`), which batchpad never
reads. So a Tiled map is not a CharPad project: there are no chars and no tile
cells to put in one. batchpad keeps it as a third kind of input and writes it
straight to the binary exports: `bin`, `asm` and `c`. The game's map bytes come
from Tiled; its chars and tiles come from CharPad as before.

## What we read

- Orthogonal maps, finite or infinite. Other orientations are an error.
- Tile layers, with data as CSV, uncompressed base64, or (JSON) a plain array.
  zlib and gzip compressed base64 layers are inflated (`inflate.nim`, our own,
  checked against Python's zlib; the checksums are not verified). zstd layers are
  an error that says to switch the compression or the format to CSV in Tiled
  (Map Properties).
- Infinite maps (`<chunk>`s) are flattened to the bounding box of their chunks;
  cells in no chunk are empty.
- Object layers (name, class, position, size, properties): kept in the model and
  in TMX <-> JSON conversion, not exported (#73).
- Group layers are flattened; a layer in a group is called `group/layer`.
- Image layers are skipped. External tilesets (`source="x.tsx"`, or a JSON
  `.tsj`) are read from the map's folder (#78); a missing file is an error. The
  map keeps the `firstgid` and `source`, so `convert` writes the reference again.
- Properties on the map, layers, objects and tiles. Tile property `tag` (an
  integer 0-255) and the tile's class (or property `name`) are exported.

## Tile numbers

A cell is a global tile id (gid): bit 31 horizontal flip, bit 30 vertical flip,
bit 29 diagonal flip, bit 28 hexagonal rotation (ignored); the rest is the id.
The tile number written is `id - firstgid` of the chosen tileset, so the first
tile of the tileset is 0, as in a CharPad map.

- The tileset is the first one, or the one `--set tileset=NAME` names. A cell
  from another tileset is an error.
- An empty cell (gid 0) is tile 0, or `--set empty-tile=N`.
- A tile number over 65535 is an error; over 255 needs `--cells` 12, 16 or `word`
  as for a CharPad map.
- The layer is the first tile layer, or the one `--set layer=NAME` names.

## Parts

| Part | Contents |
| --- | --- |
| `map` | tile numbers of the layer chosen by `--set layer=`, or the first |
| `map:NAME` | tile numbers of the tile layer NAME (`map:NAME-lo`, `map:NAME-hi` with split `--cells`) |
| `map-flags`, `map-flags:NAME` | one byte per cell: bit 7 flipped horizontally, bit 6 vertically, bit 5 diagonally |
| `tile-tags` | property `tag` per tile of the tileset, 0 where there is none; as many as the tileset has tiles |
| `tile-names` | class (or property `name`) per tile, zero-terminated (asm and C only) |

`--cells`, `--area` and `--org` work as for CharPad's `map`. A layer called
`x-lo` is found by its whole name before the suffix is cut off.

Assembler labels: `map_data`, `map_NAME_data`, `map_flags_data`,
`map_NAME_flags_data`, `tiles_tag_data`, `tiles_names` (characters in a layer
name that can't be in a label become `_`). Constants: `map_wid`, `map_hei`
(cells, after `--area`), `tile_wid_pxls`, `tile_hei_pxls` (Tiled's tile size).

## Conversion

`convert in.tmx out.json` and back (`--to tmx` or `tiled-json`; by extension
`.tmx`, `.tmj`, `.json`). The writers produce CSV data, finite, orthogonal maps,
version 1.10. Properties, object layers and tilesets that have an image are kept;
group structure is flattened, image layers dropped.
Tiled <-> CharPad/SpritePad conversion doesn't exist (#74, #75).
