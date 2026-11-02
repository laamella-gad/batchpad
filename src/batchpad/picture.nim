## Pictures into projects (`fromimage`, #72, #76): reads BMP and PNG files, matches their
## pixels to the nearest C64 colour and cuts them into chars plus a map, or
## into sprites. Rules are in docs/cli.md under fromimage.

import std/algorithm
import ctm, image, inflate, spd

type
  PictureError* = object of ValueError

  RgbImage* = object
    width*, height*: int
    pixels*: seq[Rgb]     ## row by row, top row first

  Fixed* = object
    ## Which shared colours were given (`--set`); the others are picked.
    colours*: array[4, bool]

proc fail(msg: string) {.noreturn.} = raise newException(PictureError, msg)

# BMP

proc u16(d: string, at: int): int =
  if at + 2 > d.len: fail("the BMP ends early")
  ord(d[at]) or (ord(d[at + 1]) shl 8)

proc u32(d: string, at: int): uint32 =
  if at + 4 > d.len: fail("the BMP ends early")
  for i in countdown(3, 0): result = (result shl 8) or uint32(ord(d[at + i]))

proc i32(d: string, at: int): int = int(cast[int32](d.u32(at)))

proc channel(v, mask: uint32): uint8 =
  ## The bits of `mask` in `v`, scaled to 0-255.
  if mask == 0: return 0
  var m = mask
  var shift = 0
  while (m and 1) == 0:
    m = m shr 1
    inc shift
  uint8(((v shr shift) and m) * 255 div m)

proc parseBmp*(d: string): RgbImage =
  ## An uncompressed BMP of 1, 4, 8, 16, 24 or 32 bits per pixel, with a
  ## Windows (40 to 124 byte) or OS/2 (12 or 64 byte) header; 16 and 32 bits
  ## may have bit field masks. Raises PictureError on anything else.
  if d.len < 26 or d[0 .. 1] != "BM": fail("not a BMP (no BM signature)")
  let offset = int(d.u32(10))
  let headerSize = int(d.u32(14))
  var width, height, bpp, compression, used: int
  var core = false
  case headerSize
  of 12:
    core = true
    (width, height, bpp) = (d.u16(18), d.u16(20), d.u16(24))
  of 16, 40, 52, 56, 64, 108, 124:
    width = d.i32(18)
    height = d.i32(22)
    bpp = d.u16(28)
    if headerSize >= 20: compression = int(d.u32(30))
    if headerSize >= 36: used = int(d.u32(46))
  else: fail("unknown BMP header of " & $headerSize & " bytes")
  let topDown = height < 0
  height = abs(height)
  if width <= 0 or height == 0: fail("the BMP is empty")
  if width > 16384 or height > 16384: fail("the BMP is larger than 16384 pixels")
  if bpp notin [1, 4, 8, 16, 24, 32]: fail($bpp & " bits per pixel is not read")
  var masks: array[3, uint32]
  case compression
  of 0:
    masks = if bpp == 16: [0x7c00'u32, 0x03e0, 0x001f] else: [0xff0000'u32, 0xff00, 0xff]
  of 3, 6:
    if bpp notin [16, 32]: fail("bit fields need 16 or 32 bits per pixel")
    let at = if headerSize >= 52: 54 else: 14 + headerSize
    for i in 0 .. 2: masks[i] = d.u32(at + 4 * i)
  of 1, 2: fail("the BMP is RLE compressed; save it uncompressed")
  else: fail("the BMP is compressed (method " & $compression & "); save it uncompressed")
  var colours: seq[Rgb]
  if bpp <= 8:
    let n = if used > 0 and used <= 1 shl bpp: used else: 1 shl bpp
    let entry = if core: 3 else: 4
    let at = 14 + headerSize + (if compression in [3, 6] and headerSize < 52: 12 else: 0)
    for i in 0 ..< n:
      let e = at + entry * i
      if e + 3 > d.len or e + 3 > offset: break
      colours.add [uint8(ord(d[e + 2])), uint8(ord(d[e + 1])), uint8(ord(d[e]))]
  let stride = (width * bpp + 31) div 32 * 4
  if offset + stride * height > d.len: fail("the BMP ends early")
  result = RgbImage(width: width, height: height, pixels: newSeq[Rgb](width * height))
  for y in 0 ..< height:
    let row = offset + stride * (if topDown: y else: height - 1 - y)
    for x in 0 ..< width:
      var c: Rgb
      case bpp
      of 1, 4, 8:
        let bit = x * bpp
        let v = (ord(d[row + bit div 8]) shr (8 - bpp - bit mod 8)) and ((1 shl bpp) - 1)
        if v >= colours.len: fail("pixel " & $x & "," & $y & " has colour " & $v &
                                  " but the palette has " & $colours.len)
        c = colours[v]
      of 16:
        let v = uint32(d.u16(row + 2 * x))
        c = [channel(v, masks[0]), channel(v, masks[1]), channel(v, masks[2])]
      of 24:
        let at = row + 3 * x
        c = [uint8(ord(d[at + 2])), uint8(ord(d[at + 1])), uint8(ord(d[at]))]
      else:
        let v = d.u32(row + 4 * x)
        c = [channel(v, masks[0]), channel(v, masks[1]), channel(v, masks[2])]
      result.pixels[y * width + x] = c

# Colours

# PNG

proc be32(d: string, at: int): int =
  if at + 4 > d.len: fail("the PNG ends early")
  (ord(d[at]) shl 24) or (ord(d[at + 1]) shl 16) or (ord(d[at + 2]) shl 8) or ord(d[at + 3])

func paeth(a, b, c: int): int =
  let p = a + b - c
  let (pa, pb, pc) = (abs(p - a), abs(p - b), abs(p - c))
  if pa <= pb and pa <= pc: a elif pb <= pc: b else: c

proc unfilter(raw: string, at: var int, rowBytes, rows, bpp: int): seq[string] =
  ## The rows of one (sub)image, filters undone; `bpp` bytes per pixel, at least 1.
  var prev = newString(rowBytes)
  for y in 0 ..< rows:
    if at + 1 + rowBytes > raw.len: fail("the PNG's image data ends early")
    let filter = ord(raw[at])
    var row = raw[at + 1 ..< at + 1 + rowBytes]
    at += 1 + rowBytes
    for i in 0 ..< rowBytes:
      let a = if i >= bpp: ord(row[i - bpp]) else: 0
      let b = ord(prev[i])
      let c = if i >= bpp: ord(prev[i - bpp]) else: 0
      let add = case filter
                of 0: 0
                of 1: a
                of 2: b
                of 3: (a + b) div 2
                of 4: paeth(a, b, c)
                else: fail("unknown PNG filter " & $filter)
      row[i] = char((ord(row[i]) + add) and 0xff)
    result.add row
    prev = row

proc parsePng*(d: string): RgbImage =
  ## A PNG of any colour type and bit depth, interlaced or not. Transparency
  ## is ignored: a pixel counts with its colour. Raises PictureError on
  ## anything else.
  if d.len < 8 or d[0 .. 7] != "\x89PNG\r\n\x1a\n": fail("not a PNG (no PNG signature)")
  var at = 8
  var depth, colourType, interlace = -1
  var palette: seq[Rgb]
  var data = ""
  while true:
    let length = d.be32(at)
    if at + 12 + length > d.len: fail("the PNG ends early")
    let kind = d[at + 4 ..< at + 8]
    let body = d[at + 8 ..< at + 8 + length]
    at += 12 + length
    case kind
    of "IHDR":
      if length < 13: fail("bad PNG header")
      result.width = body.be32(0)
      result.height = body.be32(4)
      depth = ord(body[8])
      colourType = ord(body[9])
      if ord(body[10]) != 0 or ord(body[11]) != 0: fail("unknown PNG compression or filter method")
      interlace = ord(body[12])
    of "PLTE":
      for i in 0 ..< length div 3:
        palette.add [uint8(ord(body[3 * i])), uint8(ord(body[3 * i + 1])), uint8(ord(body[3 * i + 2]))]
    of "IDAT": data.add body
    of "IEND": break
    else: discard
  if depth < 0: fail("the PNG has no header")
  let channels = case colourType
                 of 0: 1
                 of 2: 3
                 of 3: 1
                 of 4: 2
                 of 6: 4
                 else: fail("unknown PNG colour type " & $colourType)
  let depths = case colourType
               of 0: @[1, 2, 4, 8, 16]
               of 3: @[1, 2, 4, 8]
               else: @[8, 16]
  if depth notin depths: fail("bad PNG bit depth " & $depth & " for colour type " & $colourType)
  if colourType == 3 and palette.len == 0: fail("the PNG has no palette")
  if interlace notin 0 .. 1: fail("unknown PNG interlace method " & $interlace)
  if result.width <= 0 or result.height <= 0 or result.width > 16384 or result.height > 16384:
    fail("PNG size " & $result.width & " x " & $result.height & " is not supported")
  let bitsPerPixel = channels * depth
  let bpp = max(1, bitsPerPixel div 8)
  var raw = ""
  let most = (result.width * bitsPerPixel div 8 + 2) * result.height * 2 + 1024
  try: raw = unzlib(data, most)
  except InflateError as e: fail("the PNG's image data: " & e.msg)
  result.pixels = newSeq[Rgb](result.width * result.height)

  proc sample(row: string, x, i: int): int =
    ## Channel `i` of pixel `x`, scaled to 8 bits.
    if depth == 16: return ord(row[(x * channels + i) * 2])
    if depth == 8: return ord(row[x * channels + i])
    let bit = x * depth
    let v = (ord(row[bit div 8]) shr (8 - depth - bit mod 8)) and ((1 shl depth) - 1)
    if colourType == 3: v else: v * 255 div ((1 shl depth) - 1)

  proc place(img: var RgbImage, row: string, x, px, y: int) =
    var c: Rgb
    case colourType
    of 0, 4:
      let g = uint8(sample(row, x, 0))
      c = [g, g, g]
    of 3:
      let i = sample(row, x, 0)
      if i >= palette.len: fail("PNG colour " & $i & " is not in its palette")
      c = palette[i]
    else:
      c = [uint8(sample(row, x, 0)), uint8(sample(row, x, 1)), uint8(sample(row, x, 2))]
    img.pixels[y * img.width + px] = c

  var pos = 0
  if interlace == 0:
    let rows = unfilter(raw, pos, (result.width * bitsPerPixel + 7) div 8, result.height, bpp)
    for y in 0 ..< result.height:
      for x in 0 ..< result.width: result.place(rows[y], x, x, y)
  else:
    # Adam7: seven passes, each a smaller image of every so many pixels
    const passes = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
                    (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    for (x0, y0, dx, dy) in passes:
      let w = (result.width - x0 + dx - 1) div dx
      let h = (result.height - y0 + dy - 1) div dy
      if w <= 0 or h <= 0: continue
      let rows = unfilter(raw, pos, (w * bitsPerPixel + 7) div 8, h, bpp)
      for y in 0 ..< h:
        for x in 0 ..< w: result.place(rows[y], x, x0 + x * dx, y0 + y * dy)

proc parsePicture*(d: string): RgbImage =
  ## A BMP or a PNG, told apart by their signatures.
  if d.len >= 4 and d[0 .. 3] == "\x89PNG": parsePng(d)
  elif d.len >= 2 and d[0 .. 1] == "BM": parseBmp(d)
  else: fail("not a BMP or PNG picture")

func distance(a, b: Rgb): int =
  for i in 0 .. 2: result += (int(a[i]) - int(b[i])) * (int(a[i]) - int(b[i]))

proc quantise*(img: RgbImage, palette: openArray[Rgb], scale = 1): Image =
  ## Each pixel as the nearest colour of `palette`; with `scale` N, a picture
  ## enlarged N times is read back at its own size (the top left pixel of each
  ## N x N block counts).
  if scale < 1: fail("scale must be 1 or more")
  if img.width mod scale != 0 or img.height mod scale != 0:
    fail("the picture is " & $img.width & " x " & $img.height & ", not a multiple of the scale " & $scale)
  result = newImage(img.width div scale, img.height div scale)
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      let c = img.pixels[y * scale * img.width + x * scale]
      var best = 0
      for i in 1 ..< palette.len:
        if distance(c, palette[i]) < distance(c, palette[best]): best = i
      result.pixels[y * result.width + x] = uint8(best)

proc mostUsed(img: Image): seq[uint8] =
  ## The colours of `img`, most used first (lowest number first on a tie).
  var counts: array[16, int]
  for p in img.pixels: inc counts[p and 15]
  for i in 0'u8 .. 15'u8: result.add i
  result.sort(proc (a, b: uint8): int =
    if counts[a] != counts[b]: cmp(counts[b], counts[a]) else: cmp(a, b))

proc pickShared(img: Image, given: var array[4, uint8], fixed: Fixed, count: int) =
  ## Fills the first `count` shared colours that weren't given with the most
  ## used colours of the picture that aren't already taken.
  var taken: seq[uint8]
  for i in 0 ..< count:
    if fixed.colours[i]: taken.add given[i]
  var order = img.mostUsed
  for i in 0 ..< count:
    if fixed.colours[i]: continue
    for c in order:
      if c notin taken:
        given[i] = c
        taken.add c
        break

type
  Cell = object
    pixels: seq[uint8]   ## colour numbers, row by row, `width` wide
    width: int

proc cellAt(img: Image, x0, y0, w, h: int, back: uint8): Cell =
  ## The `w` x `h` pixels at x0,y0; outside the picture `back`.
  result = Cell(width: w, pixels: newSeq[uint8](w * h))
  for y in 0 ..< h:
    for x in 0 ..< w:
      let (px, py) = (x0 + x, y0 + y)
      result.pixels[y * w + x] =
        if px < img.width and py < img.height: img.pixels[py * img.width + px] else: back

type Fit = object
  cost: int
  colour: uint8
  multi: bool
  data: seq[uint8]     ## bit pairs or bits, one per (double) pixel, row by row

proc fitCell(c: Cell, palette: openArray[Rgb], hiresPens: proc (own: uint8): array[2, uint8],
             multiPens: proc (own: uint8): array[4, uint8], owns: openArray[uint8],
             hires, multi: bool): Fit =
  ## The cheapest way to draw `c`: in hires (pens 0 and 1) or multicolour
  ## (pens 00-11, a pixel pair each), with the cell's own colour one of `owns`.
  result.cost = int.high
  for own in owns:
    if hires:
      let pens = hiresPens(own)
      var f = Fit(colour: own, multi: false)
      for p in c.pixels:
        let (d0, d1) = (distance(palette[p], palette[pens[0]]), distance(palette[p], palette[pens[1]]))
        f.cost += min(d0, d1)
        f.data.add uint8(if d1 < d0: 1 else: 0)
      if f.cost < result.cost: result = f
    if multi:
      let pens = multiPens(own)
      var f = Fit(colour: own, multi: true)
      for i in countup(0, c.pixels.high, 2):
        var best = 0
        var bestCost = int.high
        for b in 0 .. 3:
          let cost = distance(palette[c.pixels[i]], palette[pens[b]]) +
                     distance(palette[c.pixels[i + 1]], palette[pens[b]])
          if cost < bestCost: (best, bestCost) = (b, cost)
        f.cost += bestCost
        f.data.add uint8(best)
      if f.cost < result.cost: result = f

proc pack(data: seq[uint8], multi: bool): seq[uint8] =
  ## Bits (or bit pairs) into bytes, left pixel in the high bits.
  let per = if multi: 4 else: 8
  let bits = if multi: 2 else: 1
  for i in countup(0, data.high, per):
    var b = 0'u8
    for j in 0 ..< per: b = (b shl bits) or data[i + j]
    result.add b

proc charsFromPicture*(img: Image, base: ctm.Project, fixed: Fixed,
                       palette: openArray[Rgb] = vice): ctm.Project =
  ## Chars and a map from `img` (colour numbers): 8 x 8 cells row by row, the
  ## right and bottom edge padded with background colour 0. Equal chars (with
  ## equal colours) become one. Hires or multicolour text, a colour per char;
  ## the shared colours not in `fixed` are the most used of the picture.
  result = base
  if result.displayMode notin {dmHiresText, dmMulticolourText}:
    fail("fromimage makes hires or multicolour text (mode), not ECM or bitmap modes yet")
  let multiMode = result.displayMode == dmMulticolourText
  result.colouring = cmPerChar
  result.tileSystem = false
  result.tiles = @[]
  pickShared(img, result.chipColours, fixed, if multiMode: 3 else: 1)
  let bg = result.chipColours
  let owns = block:
    var s: seq[uint8]
    for i in 0'u8 .. (if multiMode: 7'u8 else: 15'u8): s.add i
    s
  result.mapWidth = (img.width + 7) div 8
  result.mapHeight = (img.height + 7) div 8
  result.map = @[]
  result.chars = @[]
  var seen: seq[(array[8, uint8], uint8)]
  for my in 0 ..< result.mapHeight:
    for mx in 0 ..< result.mapWidth:
      let cell = img.cellAt(mx * 8, my * 8, 8, 8, bg[0])
      let f = cell.fitCell(palette,
                           proc (own: uint8): array[2, uint8] = [bg[0], own],
                           proc (own: uint8): array[4, uint8] = [bg[0], bg[1], bg[2], own],
                           owns, true, multiMode)
      var data: array[8, uint8]
      for i, b in f.data.pack(f.multi): data[i] = b
      let colour = if f.multi: f.colour or 8 else: f.colour
      let key = (data, colour)
      var n = seen.find(key)
      if n < 0:
        n = seen.len
        seen.add key
        var ch = ctm.Char(data: data)
        ch.colours[0] = colour
        result.chars.add ch
      result.map.add uint16(n)

proc spritesFromPicture*(img: Image, base: SpriteProject, fixed: Fixed, hires, multi: bool,
                         palette: openArray[Rgb] = vice): SpriteProject =
  ## Sprites from `img`: 24 x 21 cells row by row, padded with the background.
  ## Each sprite is hires or multicolour, whichever of the allowed ones fits
  ## best; the shared colours not in `fixed` (bg, mc1, mc2) are the most used.
  result = base
  result.sprites = @[]
  result.tileSystem = false
  result.tiles = @[]
  result.spriteAnims = @[]
  result.tileAnims = @[]
  var shared: array[4, uint8] = [base.colours[0], base.colours[1], base.colours[2], 0]
  pickShared(img, shared, fixed, if multi: 3 else: 1)
  for i in 0 .. 2: result.colours[i] = shared[i]
  let bg = shared
  let owns = block:
    var s: seq[uint8]
    for i in 0'u8 .. 15'u8: s.add i
    s
  for sy in 0 ..< (img.height + 20) div 21:
    for sx in 0 ..< (img.width + 23) div 24:
      let cell = img.cellAt(sx * 24, sy * 21, 24, 21, bg[0])
      let f = cell.fitCell(palette,
                           proc (own: uint8): array[2, uint8] = [bg[0], own],
                           proc (own: uint8): array[4, uint8] = [bg[0], bg[1], own, bg[2]],
                           owns, hires, multi)
      var s = Sprite(attributes: f.colour or (if f.multi: 0x80'u8 else: 0))
      for i, b in f.data.pack(f.multi): s.data[i] = b
      result.sprites.add s

proc intoTiles*(p: ctm.Project, w, h: int): ctm.Project =
  ## The chars of `p` grouped into tiles of `w` x `h` chars, numbered in the
  ## picture's reading order (as Tiled numbers the tiles of a tileset image);
  ## the map shows them where the picture had them.
  if w notin 1 .. 255 or h notin 1 .. 255: fail("tiles of " & $w & " x " & $h & " chars are not possible")
  if p.mapWidth mod w != 0 or p.mapHeight mod h != 0:
    fail("the picture is " & $(p.mapWidth * 8) & " x " & $(p.mapHeight * 8) &
         " pixels, not a whole number of " & $(w * 8) & " x " & $(h * 8) & " pixel tiles")
  result = p
  result.tileSystem = true
  result.tileWidth = w
  result.tileHeight = h
  result.mapWidth = p.mapWidth div w
  result.mapHeight = p.mapHeight div h
  result.tiles = @[]
  result.map = @[]
  for ty in 0 ..< result.mapHeight:
    for tx in 0 ..< result.mapWidth:
      var t = Tile()
      for cy in 0 ..< h:
        for cx in 0 ..< w:
          t.cells.add p.map[(ty * h + cy) * p.mapWidth + tx * w + cx]
      result.map.add uint16(result.tiles.len)
      result.tiles.add t
