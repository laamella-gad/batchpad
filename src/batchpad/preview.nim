## Pictures of the parts of a project, as the C64 would show them: chars, tiles
## and map of a CharPad project, sprites and tiles of a SpritePad project.
## Layouts and colour rules are in docs/cli.md under png.

import std/bitops
import ctm, image, spd

type
  PreviewError* = object of ValueError

proc fail(msg: string) {.noreturn.} = raise newException(PreviewError, msg)

func columnsFor(count, columns, default: int): int =
  ## Items per row of a sheet: `columns`, else `default`, never more than there are.
  max(1, min(count, if columns > 0: columns else: default))

# CharPad

func cellColours(p: ctm.Project, ch: int, tile: int): Colours =
  ## The colour matrix colours the colouring method gives a char cell; `tile`
  ## is -1 when the cell isn't in a tile (the project's colours then stand in
  ## for a per tile colouring).
  case p.colouring
  of cmPerProject: p.colours
  of cmPerTile: (if tile in 0 ..< p.tiles.len: p.tiles[tile].colours else: p.colours)
  of cmPerChar: (if ch in 0 ..< p.chars.len: p.chars[ch].colours else: p.colours)

proc drawChar(img: var Image, x0, y0: int, p: ctm.Project, ch: int, colours: Colours) =
  ## The 8 x 8 pixels of char `ch` in `colours`, at x0,y0. Nothing for a char
  ## that isn't in the set.
  let ecm = p.displayMode == dmEcmText
  let shape = if ecm: ch and 63 else: ch
  if shape >= p.chars.len: return
  let data = p.chars[shape].data
  let bg = p.chipColours
  let l0 = colours[0] and 0x0f
  let multi = case p.displayMode
              of dmMulticolourText: l0 >= 8
              of dmMulticolourBitmap: true
              else: false
  for y in 0 .. 7:
    for x in 0 ..< (if multi: 4 else: 8):
      let b = if multi: (data[y] shr (6 - 2 * x)) and 3 else: (data[y] shr (7 - x)) and 1
      let c = case p.displayMode
              of dmHiresText: (if b == 1: l0 else: bg[0])
              of dmMulticolourText:
                if not multi: (if b == 1: l0 else: bg[0])
                else: [bg[0], bg[1], bg[2], l0 and 7][b]
              of dmEcmText: (if b == 1: l0 else: bg[(ch shr 6) and 3])
              of dmHiresBitmap: (if b == 1: colours[2] else: colours[1]) and 0x0f
              of dmMulticolourBitmap:
                [bg[0], colours[2] and 0x0f, colours[1] and 0x0f, l0][b]
      if multi:
        img.pixels[(y0 + y) * img.width + x0 + 2 * x] = c
        img.pixels[(y0 + y) * img.width + x0 + 2 * x + 1] = c
      else:
        img.pixels[(y0 + y) * img.width + x0 + x] = c

proc previewCtm*(p: ctm.Project, part: string, columns = 0): Image =
  ## `part` is `chars`, `tiles` or `map`; `columns` the items per row of a
  ## sheet (16 chars, 8 tiles by default). The background is $d021.
  let back = p.chipColours[0]
  case part
  of "chars":
    if p.chars.len == 0: fail("the project has no chars")
    let cols = columnsFor(p.chars.len, columns, 16)
    let rows = (p.chars.len + cols - 1) div cols
    result = newImage(cols * 8, rows * 8, back)
    for i in 0 ..< p.chars.len:
      result.drawChar((i mod cols) * 8, (i div cols) * 8, p, i, p.cellColours(i, -1))
  of "tiles":
    if not p.tileSystem: fail("the project has no tiles")
    if p.tiles.len == 0: fail("the project has no tiles")
    let cols = columnsFor(p.tiles.len, columns, 8)
    let rows = (p.tiles.len + cols - 1) div cols
    let (tw, th) = (p.tileWidth * 8, p.tileHeight * 8)
    result = newImage(cols * tw, rows * th, back)
    for n, t in p.tiles:
      for i, ch in t.cells:
        result.drawChar((n mod cols) * tw + (i mod p.tileWidth) * 8,
                        (n div cols) * th + (i div p.tileWidth) * 8, p, int(ch),
                        p.cellColours(int(ch), n))
  of "map":
    if p.mapWidth == 0 or p.mapHeight == 0: fail("the project has no map")
    let (tw, th) = if p.tileSystem: (p.tileWidth, p.tileHeight) else: (1, 1)
    result = newImage(p.mapWidth * tw * 8, p.mapHeight * th * 8, back)
    for my in 0 ..< p.mapHeight:
      for mx in 0 ..< p.mapWidth:
        let v = int(p.map[my * p.mapWidth + mx])
        for i in 0 ..< tw * th:
          let (x, y) = ((mx * tw + i mod tw) * 8, (my * th + i div tw) * 8)
          if p.tileSystem:
            if v < p.tiles.len:
              let ch = int(p.tiles[v].cells[i])
              result.drawChar(x, y, p, ch, p.cellColours(ch, v))
          else:
            result.drawChar(x, y, p, v, p.cellColours(v, -1))
  else:
    fail("a CharPad project has no picture of " & part & " (chars, tiles, map)")

# SpritePad

proc drawSprite(img: var Image, x0, y0: int, p: SpriteProject, s: Sprite) =
  ## 24 x 21 pixels; the background is the project's.
  let multi = s.multicolour
  for y in 0 .. 20:
    for x in 0 ..< (if multi: 12 else: 24):
      let byte = s.data[y * 3 + x div (if multi: 4 else: 8)]
      let c =
        if multi:
          [p.colours[0], p.colours[1], s.colour, p.colours[2]][(byte shr (6 - 2 * (x mod 4))) and 3]
        else:
          if testBit(byte, 7 - x mod 8): s.colour else: p.colours[0]
      if multi:
        img.pixels[(y0 + y) * img.width + x0 + 2 * x] = c
        img.pixels[(y0 + y) * img.width + x0 + 2 * x + 1] = c
      else:
        img.pixels[(y0 + y) * img.width + x0 + x] = c

proc previewSpd*(p: SpriteProject, part: string, columns = 0): Image =
  ## `part` is `sprites` or `tiles`; 8 items per row by default.
  case part
  of "sprites":
    if p.sprites.len == 0: fail("the project has no sprites")
    let cols = columnsFor(p.sprites.len, columns, 8)
    let rows = (p.sprites.len + cols - 1) div cols
    result = newImage(cols * 24, rows * 21, p.colours[0])
    for i, s in p.sprites:
      result.drawSprite((i mod cols) * 24, (i div cols) * 21, p, s)
  of "tiles":
    if not p.tileSystem or p.tiles.len == 0: fail("the project has no tiles")
    let cols = columnsFor(p.tiles.len, columns, 8)
    let rows = (p.tiles.len + cols - 1) div cols
    let (tw, th) = (p.tileWidth * 24, p.tileHeight * 21)
    result = newImage(cols * tw, rows * th, p.colours[0])
    for n, t in p.tiles:
      for i, c in t.cells:
        if int(c) < p.sprites.len:
          result.drawSprite((n mod cols) * tw + (i mod p.tileWidth) * 24,
                            (n div cols) * th + (i div p.tileWidth) * 21, p, p.sprites[int(c)])
  else:
    fail("a SpritePad project has no picture of " & part & " (sprites, tiles)")
