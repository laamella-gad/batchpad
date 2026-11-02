## Pictures of the parts of a project, as the C64 would show them: chars, tiles
## and map of a CharPad project, sprites and tiles of a SpritePad project.
## Layouts and colour rules are in docs/cli.md under png.

import ctm, image, spd

type
  PreviewError* = object of ValueError

proc fail(msg: string) {.noreturn.} = raise newException(PreviewError, msg)

func columnsFor(count, columns, default: int): int =
  ## Items per row of a sheet: `columns`, else `default`, never more than there are.
  max(1, min(count, if columns > 0: columns else: default))

# CharPad

func colourOf(p: ctm.Project, ch: int, tile: int): Colours =
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
  # C64 colours are 4 bits; TED colours (CharPad C16) 7: luma * 16 + chroma.
  # In multicolour text bit 3 says multicolour on both, and pen 11 is the
  # colour without it.
  let mask = if p.ted: 0x7f'u8 else: 0x0f'u8
  let bg = p.chipColours
  let l0 = colours[0] and mask
  let multi = case p.displayMode
              of dmMulticolourText: (l0 and 8) != 0
              of dmMulticolourBitmap: true
              else: false
  for y in 0 .. 7:
    for x in 0 ..< (if multi: 4 else: 8):
      let b = if multi: (data[y] shr (6 - 2 * x)) and 3 else: (data[y] shr (7 - x)) and 1
      let c = case p.displayMode
              of dmHiresText: (if b == 1: l0 else: bg[0])
              of dmMulticolourText:
                if not multi: (if b == 1: l0 else: bg[0])
                else: [bg[0], bg[1], bg[2], l0 and (mask xor 8)][b]
              of dmEcmText: (if b == 1: l0 else: bg[(ch shr 6) and 3])
              of dmHiresBitmap: (if b == 1: colours[2] else: colours[1]) and mask
              of dmMulticolourBitmap:
                # the C16 has no colour RAM colour: pen 11 is chip colour 1
                [bg[0], colours[2] and mask, colours[1] and mask, (if p.ted: bg[1] else: l0)][b]
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
      result.drawChar((i mod cols) * 8, (i div cols) * 8, p, i, p.colourOf(i, -1))
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
                        p.colourOf(int(ch), n))
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
              result.drawChar(x, y, p, ch, p.colourOf(ch, v))
          elif p.cellColours.len == p.map.len:
            var c = p.colourOf(v, -1)
            c[0] = p.cellColours[my * p.mapWidth + mx]
            result.drawChar(x, y, p, v, c)
          else:
            result.drawChar(x, y, p, v, p.colourOf(v, -1))
  else:
    fail("a CharPad project has no picture of " & part & " (chars, tiles, map)")

proc tileSheet*(p: ctm.Project, columns = 0): tuple[image: Image, count, columns: int] =
  ## The tileset image of a Tiled map made from `p`: every tile, or without
  ## tiles every char number up to the highest the map uses (in ECM a number
  ## past the set is a char shape on another background), `columns` per row
  ## (8 tiles, 16 chars by default).
  if p.tileSystem:
    if p.tiles.len == 0: fail("the project has no tiles")
    let cols = columnsFor(p.tiles.len, columns, 8)
    return (p.previewCtm("tiles", cols), p.tiles.len, cols)
  var count = p.chars.len
  for v in p.map: count = max(count, int(v) + 1)
  if count == 0: fail("the project has no chars")
  let cols = columnsFor(count, columns, 16)
  var img = newImage(cols * 8, ((count + cols - 1) div cols) * 8, p.chipColours[0])
  for i in 0 ..< count:
    img.drawChar((i mod cols) * 8, (i div cols) * 8, p, i, p.colourOf(i, -1))
  (img, count, cols)

# SpritePad

proc drawSprite(img: var Image, x0, y0: int, p: SpriteProject, s: Sprite,
                transparent = false) =
  ## 24 x 21 pixels; the background is the project's. When `transparent`, the
  ## background pixels (bits 00) are left as they are.
  let multi = s.multicolour
  for y in 0 .. 20:
    for x in 0 ..< (if multi: 12 else: 24):
      let byte = s.data[y * 3 + x div (if multi: 4 else: 8)]
      let bits = if multi: (byte shr (6 - 2 * (x mod 4))) and 3 else: (byte shr (7 - x mod 8)) and 1
      if transparent and bits == 0: continue
      let c =
        if multi: [p.colours[0], p.colours[1], s.colour, p.colours[2]][bits]
        else: (if bits == 1: s.colour else: p.colours[0])
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

# Animations

func order*(a: Animation): seq[int] =
  ## The frame numbers in the order they play, once through: first to last
  ## (down if last is lower), and with ping-pong back to just after the first.
  let step = if a.last >= a.first: 1 else: -1
  var i = int(a.first)
  while true:
    result.add i
    if i == int(a.last): break
    i += step
  if a.pingPong:
    for j in countdown(result.len - 2, 1): result.add result[j]

proc drawSpriteOver(img: var Image, x0, y0: int, p: SpriteProject, n: int, transparent: bool) =
  ## Sprite `n`, and over it the sprite its overlay flag points at.
  img.drawSprite(x0, y0, p, p.sprites[n], transparent)
  let o = n + int(p.spriteOverlay)
  if p.sprites[n].overlay and o in 0 ..< p.sprites.len:
    img.drawSprite(x0, y0, p, p.sprites[o], transparent = true)

proc drawTile(img: var Image, x0, y0: int, p: SpriteProject, n: int, transparent: bool) =
  for i, c in p.tiles[n].cells:
    if int(c) < p.sprites.len:
      img.drawSpriteOver(x0 + (i mod p.tileWidth) * 24, y0 + (i div p.tileWidth) * 21, p, int(c),
                         transparent)

proc animationFrames*(p: SpriteProject, tiles: bool, number: int): seq[Image] =
  ## The pictures of sprite animation (or tile animation) `number`, in play
  ## order, with each sprite's or tile's overlay drawn over it. A number or a
  ## frame that isn't there raises PreviewError.
  let anims = if tiles: p.tileAnims else: p.spriteAnims
  let what = if tiles: "tile animation" else: "sprite animation"
  if number notin 0 ..< anims.len:
    fail("there is no " & what & " " & $number & " (the project has " & $anims.len & ")")
  if tiles and not p.tileSystem: fail("the project has no tiles")
  let count = if tiles: p.tiles.len else: p.sprites.len
  let (w, h) = if tiles: (p.tileWidth * 24, p.tileHeight * 21) else: (24, 21)
  for n in anims[number].order:
    if n >= count:
      fail(what & " " & $number & " uses " & (if tiles: "tile " else: "sprite ") & $n &
           " but there are " & $count)
    var img = newImage(w, h, p.colours[0])
    if tiles:
      img.drawTile(0, 0, p, n, false)
      let o = n + int(p.tileOverlay)
      if p.tiles[n].overlay and o in 0 ..< p.tiles.len: img.drawTile(0, 0, p, o, true)
    else:
      img.drawSpriteOver(0, 0, p, n, false)
    result.add img
