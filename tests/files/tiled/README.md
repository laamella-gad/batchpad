# Tiled test files

Made by hand for batchpad, not by Tiled itself (Tiled was not opened on them).
All hold a 4 x 3 map of 8 x 8 pixel tiles unless said otherwise. `tiles.png`
and the other images are named but not present: batchpad never reads them.

| File | Holds |
| --- | --- |
| `csv.tmx` | layers `ground` (gids 1 to 12) and `sky` (empty cells, a horizontally flipped tile 0, gid 5), CSV data. Tileset `tiles`, firstgid 1, 16 tiles; tile 0 is class `wall` with tag 3, tile 4 class `floor` with tag 7 |
| `base64.tmx` | the same map, uncompressed base64 data |
| `csv.json` | the same map as Tiled JSON, array data |
| `compressed.tmx` | a zlib compressed layer: must be refused with a hint to use CSV |
| `infinite.tmx` | an infinite map, layer `ground` of two 2 x 2 chunks at (0,0) and (4,2) |
| `twotilesets.tmx` | 2 x 1 map with two tilesets, `tiles` (firstgid 1) and `more` (firstgid 5), one cell of each |
