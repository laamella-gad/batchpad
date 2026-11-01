# Tilemedo test files

Made by hand for batchpad (a Python script following the format in
`tilemedo.html`), not by Tilemedo itself. Both hold 3 chars (empty, a box, a
diamond), 2 tiles of 4 x 4 (tile 0 empty, tile 1 a box frame with diamonds in
the middle) and a 3 x 2 map.

| File | Holds |
| --- | --- |
| `hires.tmd` | mode 1 (hires chars only), background 6, char colours 1, 14, 7; map 0 1 0 / 1 0 1; no trigger map |
| `multicolour.tmd` | mode 0 (mixed), background 0, multicolours 11 and 12, char colours 1, 13 (multicolour), 10 (multicolour); map 1 1 0 / 0 1 0; trigger map 0 5 0 / 0 0 255 |
