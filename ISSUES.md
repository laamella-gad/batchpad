# Issues

Format: `- #N [type, priority] Title` with optional indented details.
Types: bug, feature, task. Priorities: high, normal, low.
Move an issue between sections to change its status. Never reuse a number; next free number: **#40**.

## Open

- #1 [feature, high] Parse CharPad project files (.ctm)
  - Header, charset, tiles, map, colours.
  - Umbrella: model #4, per-version readers/writers #6-#23. Specs for V1-V9: `docs/charpad.md`.
- #2 [feature, high] Parse SpritePad project files (.spd)
  - Sprite data, colours, animations.
  - Umbrella: model #5, per-version readers/writers #24-#39. Specs for all formats: `docs/spritepad.md`.
- #3 [task, normal] Decide output artifact formats and CLI options
  - Which outputs (raw binary, assembler includes, ...) and which assemblers to target.
- #4 [feature, high] Shared in-memory model for all CharPad formats
  - One model every CTM reader fills and every writer reads: chars, materials, colours (per project/tile/char, 1-3 per item for bitmap modes), tiles, tags, names, map, display mode, V9 extras.
  - Readers convert older layouts into it (V1-V4 tile-cell colours, V2 9-byte chars, expanded char sets); writers report what the target version can't hold.
- #5 [feature, high] Shared in-memory model for all SpritePad formats
  - One model every SpritePad reader fills and every writer reads: sprites with 64th-byte attributes, colours, tiles with attributes/tags/names, sprite and tile animations, overlay distances.
  - Keep unused bits of the 64th byte for round trips; writers report what the target format can't hold.
- #6 [feature, low] CharPad CTM V1 reader
  - CharPad 1.0. 4x4 tiles, byte map, colour per tile cell.
- #7 [feature, low] CharPad CTM V1 writer
- #8 [feature, low] CharPad CTM V2 reader
  - CharPad 1.7. 9-byte chars (material), byte map.
- #9 [feature, low] CharPad CTM V2 writer
- #10 [feature, low] CharPad CTM V3 reader
  - CharPad 1.8 before Rev 3. No samples; expanded char set omits tile data.
- #11 [feature, low] CharPad CTM V3 writer
- #12 [feature, normal] CharPad CTM V4 reader
  - CharPad 1.8 Rev 3. 110 samples.
- #13 [feature, low] CharPad CTM V4 writer
- #14 [feature, high] CharPad CTM V5 reader
  - CharPad 2.0-2.5. 282 samples; flags byte, word map.
- #15 [feature, low] CharPad CTM V5 writer
- #16 [feature, normal] CharPad CTM V6 reader
  - CharPad 2.6. First block format; flags bit 0 = multicolour, bit 1 = tiles.
- #17 [feature, low] CharPad CTM V6 writer
- #18 [feature, high] CharPad CTM V7 reader
  - CharPad 2.8 / Free 2.86. 277 samples; writer already proven in Python references.
- #19 [feature, normal] CharPad CTM V7 writer
- #20 [feature, normal] CharPad CTM V8 reader
  - CharPad C64 3.0; version byte 8 or 82. No samples; bitmap modes, 1-3 colour bytes.
- #21 [feature, low] CharPad CTM V8 writer
- #22 [feature, high] CharPad CTM V9 reader
  - CharPad Pro 3.5+. 652 samples; flexi-grid, key map, bitmap modes.
- #23 [feature, normal] CharPad CTM V9 writer
- #24 [feature, low] SpritePad 1.2 `.spr` + `.spr.inf` (colours in .inf) reader
  - No samples; layout from 1.5 ReadMe only.
- #25 [feature, low] SpritePad 1.2 `.spr` + `.spr.inf` (colours in .inf) writer
- #26 [feature, low] SpritePad 1.3-1.7 `.spr` + `.spr.inf` reader
  - Samples in 1.5 and 1.7.
- #27 [feature, low] SpritePad 1.3-1.7 `.spr` + `.spr.inf` writer
- #28 [feature, high] SpritePad 1.8 headerless .spd reader
  - 10 samples; writer already proven in Python reference.
- #29 [feature, normal] SpritePad 1.8 headerless .spd writer
- #30 [feature, normal] SPD V1 reader
  - SpritePad 2.0. 13 samples.
- #31 [feature, low] SPD V1 writer
- #32 [feature, low] SPD V2 reader
  - SpritePad 2.3. No samples; plain-word counts.
- #33 [feature, low] SPD V2 writer
- #34 [feature, low] SPD V3 reader
  - SpritePad 2.8 private build, never released. No samples.
- #35 [feature, low] SPD V3 writer
- #36 [feature, normal] SPD V4 reader
  - SpritePad 2.8. No samples; overlay distances.
- #37 [feature, low] SPD V4 writer
- #38 [feature, high] SPD V5 reader
  - SpritePad 2.9 / Pro. 112 samples.
- #39 [feature, normal] SPD V5 writer

## In progress

## Closed
