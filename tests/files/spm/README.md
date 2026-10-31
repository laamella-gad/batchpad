# Spritemate `.spm` test files

Made by us with `batchpad convert` from `tests/files/spd5/sprites.spd` (see
`tests/files/spd5/README.md` for the sprites), then checked by `tests/tspm.nim`.

- `sprites.spm`: all 6 sprites, in the layout of the current Spritemate (pens as
  numbers, `colors` keyed `0`, `2`, `3`).
- `legacy.spm`: the first 2 sprites in the layout of older Spritemates: `colors`
  keyed `t`, `m1`, `m2`, pens as `"t"`, `"i"`, `"m1"`, `"m2"`, no sprite names, no
  `version`, no `filename`.

Not opened in Spritemate itself. The layout is from its source (`Save.ts`,
`Load.ts`, `SpriteTypes.ts`); its own example projects (`bruce-lee`, `duck`,
`fluddie`, `frog`, `goose`) read and write back through SPD unchanged. See
`docs/spritepad.md`.
