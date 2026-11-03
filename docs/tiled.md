# Tiled maps (#66)

[Tiled](https://www.mapeditor.org) (mapeditor.org) saves maps as `.tmx` (XML)
or JSON (`.tmj`, or `.json`). Layouts: doc.mapeditor.org, "TMX Map Format" and
"JSON Map Format". We wrote the readers from those pages and made our own test
files (`tests/files/tiled/`). On
2026-11-02 the example and test maps of the Tiled repository (github.com/mapeditor/tiled,
`examples/` and `tests/`, 87 `.tmx` files and one JSON map, saved by Tiled 1.0 to 1.11) went
through `info`, `asm` and `convert` to JSON and back: every orthogonal map reads,
the JSON reads back to the same layers and cells. What was refused was right to
be (isometric and hexagonal maps, tile numbers over 255 without a wider
`--cells`, tilesets in Qt resources or missing files). That run found two bugs,
fixed since: object templates were not read, and a map with object layers only
had no `asm` or `c` output.

On 2026-11-04 a map drawn and saved in Tiled 1.12.2, its external TSX and SVG,
and Tiled-generated JSON, zlib and gzip variants were checked with `info`,
`bin`, `asm` and conversion. Tiled reopened the conversions and rendered the
tile layers pixel-for-pixel like the original. The map has two tile layers,
empty cells, horizontal and combined horizontal/vertical flips, and a rectangle
of type `enemy` with an `hp` string of `3`. Tiled collapsed two references to
the same external tileset when it reopened the original; batchpad now exports
the same local tile numbers. Fixtures and regression tests are in
`tests/files/tiled/tiled-1.12.2/` and `tests/ttiled.nim`.

Tiled 1.12.2's rasterizer also rendered three CharPad-to-Tiled exports (with
tiles, without tiles, and ECM) pixel-for-pixel like batchpad's previews; their
map bytes match too. This is not a GUI inspection. Tile objects, templates,
external JSON tilesets and negative-position infinite chunks still need checks
against files saved by Tiled (#87).

## What a Tiled map holds

Tile numbers only. A map says which tile sits in which cell; the pictures are in
the image a tileset names (`<image source="tiles.png">`), which batchpad doesn't
read with the map (`fromimage --tiles` can cut it into CharPad tiles, see
Conversion). So a Tiled map is not a CharPad project: there are no chars and no tile
cells to put in one. batchpad keeps it as a third kind of input and writes it
straight to the binary exports: `bin`, `asm` and `c`. The game's map bytes come
from Tiled; its chars and tiles come from CharPad as before, or `convert --base`
puts the map into a CharPad project, and `convert level.ctm level.tmx` makes a
Tiled map with a tileset image from one (see Conversion).

## What we read

- Orthogonal maps, finite or infinite. Other orientations are an error.
- Tile layers, with data as CSV, uncompressed base64, or (JSON) a plain array.
  zlib and gzip compressed base64 layers are inflated (`inflate.nim`, our own,
  checked against Python's zlib; the checksums are not verified). zstd layers are
  an error that says to switch the compression or the format to CSV in Tiled
  (Map Properties).
- Infinite maps (`<chunk>`s) are flattened to the bounding box of their chunks;
  cells in no chunk are empty.
- Object layers (name, class, position, size, properties, the tile of a tile
  object): kept in the model and in TMX <-> JSON conversion, and written by the
  `objects` part (#73).
- Object templates (`template="x.tx"`, or a JSON `.tj`) are read from the map's
  folder: what the object doesn't set itself (name, class, width, height, tile,
  properties) comes from the template. `convert` keeps the template reference.
  A template's tileset is not read: its tile number is taken as the map's.
- Group layers are flattened; a layer in a group is called `group/layer`.
- Image layers are skipped. External tilesets (`source="x.tsx"`, or a JSON
  `.tsj`) are read from the map's folder (#78); a missing file is an error. The
  map keeps the `firstgid` and `source`, so `convert` writes the reference again.
- Properties on the map, layers, objects and tiles. Tile property `tag` (an
  integer 0-255) and the tile's class (or property `name`) are exported.

## Tile numbers

A cell is a global tile id (gid): bit 31 horizontal flip, bit 30 vertical flip,
bit 29 diagonal flip, bit 28 hexagonal rotation (ignored); the rest is the id.
The tile number written is `id - firstgid` of the reference owning the cell,
so the first tile of the tileset is 0, as in a CharPad map. Multiple references
to the same external tileset are treated as the same tileset.

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
| `objects`, `objects:NAME` | a record per object of the first object layer, or of the layer NAME |

`--cells`, `--area` and `--org` work as for CharPad's `map`. A layer called
`x-lo` is found by its whole name before the suffix is cut off.

Assembler labels: `map_data`, `map_NAME_data`, `map_flags_data`,
`map_NAME_flags_data`, `tiles_tag_data`, `tiles_names` (characters in a layer
name that can't be in a label become `_`). Constants: `map_wid`, `map_hei`
(cells, after `--area`), `tile_wid_pxls`, `tile_hei_pxls` (Tiled's tile size).

## Objects

The `objects` part is a record per object, in the layer's order:

| Byte | Contents |
| --- | --- |
| 0 | class number: the place of the object's class in the sorted list of all classes in the map; `$ff` for no class |
| 1-2 | x, little-endian word |
| 3-4 | y, little-endian word |
| 5 | width |
| 6 | height |
| 7... | one byte per name in `--set object-fields=a,b`: that integer property (`bool` gives 0 or 1), 0 when the object doesn't have it |

Positions and sizes are in tiles (pixels divided by Tiled's tile size, rounded
down), or in pixels (rounded) with `--set object-units=pixels`. They are Tiled's
own numbers: the top left corner, except for tile objects, where Tiled puts y at
the bottom. A map without tile layers writes `objects` by default, and `map_wid`,
`map_hei` are the map's size. A negative value, a size over 255, a position over 65535 or a field
outside -128 to 255 is an error. Objects have no end marker: the count is the
size divided by the record size.

Assembler labels: `objects_data`, `objects_NAME_data`. Constants (when an
`objects` part is written): `object_size` (record size) and
`object_class_NAME` per class.

## Conversion

`convert in.tmx out.json` and back (`--to tmx` or `tiled-json`; by extension
`.tmx`, `.tmj`, `.json`). The writers produce CSV data, finite, orthogonal maps,
version 1.10. Properties, object layers and tilesets that have an image are kept;
group structure is flattened, image layers dropped.

`convert level.tmx level.ctm --base art.ctm` (#75) makes a CharPad project: the
chars, tiles and colours of `art.ctm` (any CharPad project batchpad reads, also
`.ctt`), with its map replaced by a tile layer (the first, or `--set layer=NAME`).
Tile numbers are counted as for `bin` (`--set tileset=`, `--set empty-tile=`). They
are tile numbers when the base project uses tiles and char numbers when not; a
number past the base's last tile or char is an error. Flip flags don't fit a
CharPad map and are left out with a warning, as are a trigger map or cell
colours of the base (they belong to its old map). Any CharPad output works
(`ctm1`-`ctm9`, `ctt`, `tmd`, `petmate`, `seuck-b`), within what it can hold.

`convert level.ctm level.tmx` (or `.json`, `--to tmx|tiled-json`; #74) goes the
other way: a map with one tile layer `map` and one tileset, and its image
`level.png` written next to the map (so the output can't be `-`). With tiles the
tileset holds the tiles (8 per row), without tiles the chars (16 per row: every
char number up to the highest the map uses, so in ECM the numbers past the set
are drawn on their background). Tiles are drawn as `png ... tiles` draws them:
the project's colouring method, VICE colours, or TED colours for a `.ctt`. Tile
numbers stay CharPad's, so `bin map=` gives the same bytes from either file,
and `convert level.tmx back.ctm --base level.ctm` gives the map back. Left out
with a warning: Petmate's colour per cell (a char has one colour in the tileset)
and Tilemedo's trigger map. Three example outputs were rendered with Tiled's
rasterizer as described above; they were not inspected in the editor GUI.

A tileset image drawn elsewhere becomes CharPad tiles with `fromimage
tileset.png -o tileset.ctm --tiles 2x2` (#76; see cli.md): tile numbers follow
Tiled's, so `convert level.tmx level.ctm --base tileset.ctm` then gives the
whole level as a CharPad project.
