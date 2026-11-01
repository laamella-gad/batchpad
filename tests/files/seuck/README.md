# SEUCK test files

Made by hand for batchpad; SEUCK itself was not used on them.

| File | Holds |
| --- | --- |
| `sprites.A` | 127 sprites. Sprite 0: bytes 1 to 63, multicolour, colour 5 (64th byte `$15`); sprite 1: `$aa` bytes, colour 2, single colour; sprite 2: first byte `$ff`, multicolour, colour 15; the rest empty |
| `background.B` | a normal background: map bytes `(k*7) & $7f` in file order, tile colours `i & $0f`, tile cells `(i*25+j) mod 254`, char bytes `(i*8+j) & $ff` |
| `sideways.B` | the same with the map as CharPad 1.7's sideways layout: bytes `(k*5) & $ff` for k < 4095, then `$00`; read with `--input-format seuck-b-sideways` |
