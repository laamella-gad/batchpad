# Tiled test files

The files in this directory were made by hand for batchpad, not by Tiled.
All hold a 4 x 3 map of 8 x 8 pixel tiles unless said otherwise. `tiles.png`
and the other images are named but not present: batchpad never reads them.
The `tiled-1.12.2/` subdirectory instead holds an actual Tiled-saved map and
tileset, its SVG image, and JSON, zlib and gzip variants written by Tiled 1.12.2.
`generate-compressed.js` regenerates the compressed variants using Tiled's
`--evaluate` option from the repository root. The original map references the
same external tileset twice; Tiled merges the references when it loads the map.

| File | Holds |
| --- | --- |
| `csv.tmx` | layers `ground` (gids 1 to 12) and `sky` (empty cells, a horizontally flipped tile 0, gid 5), CSV data. Tileset `tiles`, firstgid 1, 16 tiles; tile 0 is class `wall` with tag 3, tile 4 class `floor` with tag 7 |
| `base64.tmx` | the same map, uncompressed base64 data |
| `csv.json` | the same map as Tiled JSON, array data |
| `zlib.tmx`, `gzip.tmx` | the `csv.tmx` map with layers as base64 plus zlib / gzip (made with Python's zlib and gzip) |
| `compressed.tmx` | a `zstd` compressed layer (not supported): must be refused with a hint |
| `infinite.tmx` | an infinite map, layer `ground` of two 2 x 2 chunks at (0,0) and (4,2) |
| `twotilesets.tmx` | 2 x 1 map with two tilesets, `tiles` (firstgid 1) and `more` (firstgid 5), one cell of each |
| `external.tmx` | `csv.tmx` with its tileset in `tiles.tsx` (external, firstgid 1) |
| `tiles.tsx` | the external tileset: the same as `csv.tmx` holds inline |
| `objects.tmx` | `csv.tmx` plus object layers `enemies` (bat "first" at 16,8 8x8 with `hp` 3 and `boss` true; alien at 24.5,0 16x16 with `hp` 10; a point without class at 0,16) and `items` (key at 8,16 8x8) |
| `templates.tmx` | a map of object layer `enemies` only (no tile layer): two objects from the template `enemy.tx` (the second overrides class `alien`, width 8 and `hp` 9) and a `key` without template |
| `enemy.tx` | the object template: name `enemy`, class (`type`) `bat`, tile gid 2, 16 x 8, `hp` 4, `speed` 2 |
| `templates.json`, `enemy.tj` | the same map and template as Tiled JSON |
