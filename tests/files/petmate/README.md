# Petmate test files

Made for batchpad by a Python script following Petmate's source
(`saveWorkspace` in `src/utils/index.ts`: compact JSON, keys in Petmate's
order), not saved by Petmate itself.

| File | Holds |
| --- | --- |
| `screens.petmate` | version 2, two screens. Screen 0 "title": 4 x 3, background 6, border 14, ROM charset `upper`, cell x,y has code (4y+x)*3 and colour x+y. Screen 1 (no name): 2 x 2, background 0, border 0, ROM charset `lower`, codes 1 2 / 3 4, all colour 7 |
| `custom.petmate` | version 2, one screen "level": 3 x 2, background 11, border 12, charset `custom_1` ("myfont", byte i = (7i + 3) mod 256), codes 0 1 2 / 1 0 255, colours 5 5 2 / 9 5 1 |
| `v1.petmate` | version 1: no `customFonts`, no `charset` (so `upper`); 2 x 1, codes 32 33, colour 3 |
