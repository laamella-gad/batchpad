## SpritePad project files (.spd). Layouts are described in docs/spritepad.md.

import std/bitops
import binio

type
  SpdError* = object of ValueError

  Sprite* = object
    data*: array[63, uint8]  ## 21 rows of 3 bytes
    attributes*: uint8       ## the 64th byte, `MYXOCCCC`, kept as stored

  SpriteTile* = object
    cells*: seq[uint16]      ## sprite numbers, row by row
    attributes*: uint8       ## bit 4 has overlay; kept as stored
    tag*: uint8
    name*: string

  Animation* = object
    first*, last*: uint16    ## frames: sprite or tile numbers
    timer*: uint8            ## timer reload
    attributes*: uint8       ## bit 4 ping-pong

  SpriteProject* = object
    version*: int
    colours*: array[3, uint8]       ## background, multicolour 1, multicolour 2
    spriteOverlay*, tileOverlay*: int16
      ## overlay distances: a sprite or tile with overlay is drawn under the one
      ## this far on
    sprites*: seq[Sprite]
    tileSystem*: bool
    tileWidth*, tileHeight*: int    ## in sprites
    tiles*: seq[SpriteTile]         ## empty when the tile system is off
    spriteAnims*: seq[Animation]    ## empty when off
    tileAnims*: seq[Animation]      ## empty when off

func colour*(s: Sprite): uint8 = s.attributes and 0x0f
func overlay*(s: Sprite): bool = s.attributes.testBit(4)
func expandX*(s: Sprite): bool = s.attributes.testBit(5)
func expandY*(s: Sprite): bool = s.attributes.testBit(6)
func multicolour*(s: Sprite): bool = s.attributes.testBit(7)
func overlay*(t: SpriteTile): bool = t.attributes.testBit(4)
func pingPong*(a: Animation): bool = a.attributes.testBit(4)

type Reader = binio.Reader[SpdError]

proc readSprites(r: var Reader, p: var SpriteProject, count: int) =
  p.sprites.setLen count
  for s in p.sprites.mitems:
    for b in s.data.mitems: b = r.u8
    s.attributes = r.u8

proc readAnims(r: var Reader, anims: var seq[Animation], wordFrames = true) =
  ## Four lists in turn: first frames, last frames, timers, attributes.
  for a in anims.mitems: a.first = (if wordFrames: r.u16 else: r.u8)
  for a in anims.mitems: a.last = (if wordFrames: r.u16 else: r.u8)
  for a in anims.mitems: a.timer = r.u8
  for a in anims.mitems: a.attributes = r.u8

proc parseV1(r: var Reader): SpriteProject =
  ## V1 has no tiles and always at least one sprite animation. Overlay means
  ## "the next sprite", so both overlay distances are 1.
  result.version = 1
  let sprites = r.u8.int + 1
  result.spriteAnims.setLen(r.u8.int + 1)
  for c in result.colours.mitems: c = r.u8
  result.spriteOverlay = 1
  result.tileOverlay = 1
  r.readSprites(result, sprites)
  r.readAnims(result.spriteAnims, wordFrames = false)

proc parseV2(r: var Reader): SpriteProject =
  ## V2 has tiles, but no tile attributes, tags, names or tile animations, and
  ## its counts are plain words. Counts whose flag is off are ignored, as
  ## SpritePad Pro does. Overlay distances are 1, as in V1.
  result.version = 2
  let flags = r.u8
  result.tileSystem = flags.testBit(0)
  let sprites = r.u16.int
  if sprites == 0: r.fail("no sprites")
  let tiles = r.u16.int
  let anims = r.u16.int
  let width = r.u8.int
  let height = r.u8.int
  for c in result.colours.mitems: c = r.u8
  result.spriteOverlay = 1
  result.tileOverlay = 1

  r.readSprites(result, sprites)

  if result.tileSystem:
    result.tileWidth = width
    result.tileHeight = height
    result.tiles.setLen tiles
    for t in result.tiles.mitems:
      t.cells.setLen(width * height)
      for c in t.cells.mitems: c = r.u16

  if flags.testBit(1):
    result.spriteAnims.setLen anims
    r.readAnims(result.spriteAnims)

proc parseV5(r: var Reader): SpriteProject =
  ## Counts whose flag is off are ignored, as SpritePad does.
  result.version = 5
  let flags = r.u8
  result.tileSystem = flags.testBit(0)
  let sprites = r.u16.int
  if sprites == 0: r.fail("no sprites")
  let tiles = r.u16.int
  let spriteAnims = r.u8.int + 1
  let tileAnims = r.u8.int + 1
  let width = r.u8.int
  let height = r.u8.int
  for c in result.colours.mitems: c = r.u8
  result.spriteOverlay = cast[int16](r.u16)
  result.tileOverlay = cast[int16](r.u16)

  r.readSprites(result, sprites)

  if result.tileSystem:
    result.tileWidth = width
    result.tileHeight = height
    result.tiles.setLen tiles
    for t in result.tiles.mitems:
      t.cells.setLen(width * height)
      for c in t.cells.mitems: c = r.u16
    for t in result.tiles.mitems: t.attributes = r.u8
    for t in result.tiles.mitems: t.tag = r.u8
    for t in result.tiles.mitems: t.name = r.zstring

  if flags.testBit(1):
    result.spriteAnims.setLen spriteAnims
    r.readAnims(result.spriteAnims)
  if flags.testBit(2):
    result.tileAnims.setLen tileAnims
    r.readAnims(result.tileAnims)

proc parseSpd*(data: openArray[byte]): SpriteProject =
  ## Parses a whole .spd file. Raises SpdError on anything it can't read.
  var r = Reader(data: @data)
  if data.len < 4 or data[0] != byte('S') or data[1] != byte('P') or data[2] != byte('D'):
    r.fail("not a SpritePad project (no SPD signature)")
  r.pos = 3
  let version = r.u8.int
  case version
  of 1: result = parseV1(r)
  of 2: result = parseV2(r)
  of 5: result = parseV5(r)
  else: r.fail("SPD version " & $version & " is not supported yet")
  if r.pos != r.data.len:
    r.fail($(r.data.len - r.pos) & " bytes after the last part")

proc readSpd*(path: string): SpriteProject =
  let s = readFile(path)
  parseSpd(s.toOpenArrayByte(0, s.high))

proc fail(msg: string) {.noreturn.} =
  raise newException(SpdError, msg)

proc check(p: SpriteProject) =
  ## What no version can write: a project that doesn't hold together.
  if p.sprites.len == 0: fail("no sprites")
  if p.tileSystem:
    if p.tiles.len == 0: fail("the tile system is on, but there are no tiles")
    if p.tileWidth < 1 or p.tileHeight < 1:
      fail("tile size " & $p.tileWidth & " x " & $p.tileHeight & " is under 1 x 1")
    for i, t in p.tiles:
      if t.cells.len != p.tileWidth * p.tileHeight:
        fail("tile " & $i & " has " & $t.cells.len & " cells, not " & $(p.tileWidth * p.tileHeight))

proc cropTiles(p: var SpriteProject, width, height: int) =
  ## Keeps the top left `width` x `height` sprites of every tile.
  if p.tileWidth <= width and p.tileHeight <= height: return
  let (w, h) = (min(p.tileWidth, width), min(p.tileHeight, height))
  for t in p.tiles.mitems:
    var cells = newSeq[uint16](w * h)
    for y in 0..<h:
      for x in 0..<w: cells[y * w + x] = t.cells[y * p.tileWidth + x]
    t.cells = cells
  p.tileWidth = w
  p.tileHeight = h

proc enableAnims(p: var SpriteProject, fromVersion: int) =
  ## V1 to V3 have an enabled bit (bit 7) in the animation attributes, and
  ## SpritePad 2.0 and 2.3 hide animations without it. Projects from other
  ## formats have no such bit, so it is set on every animation.
  if fromVersion notin 1..3:
    for a in p.spriteAnims.mitems: a.attributes.setBit(7)

proc dropOverlays(p: var SpriteProject) =
  ## Up to V3 overlay means the next sprite, so overlays at another distance
  ## are left out.
  if p.spriteOverlay != 1:
    for s in p.sprites.mitems: s.attributes.clearBit(4)

proc fitV1(p: SpriteProject): SpriteProject =
  ## Drops what V1 can't hold: tiles, tile animations, sprites and animations
  ## past 256, animations with frames above 255, and overlays when the overlay
  ## distance isn't 1. V1 always holds an animation, so a project without one
  ## gets a blank one (not enabled). See `enableAnims` for the enabled bit.
  result = p
  if result.sprites.len > 256: result.sprites.setLen 256
  result.tileSystem = false
  result.tiles = @[]
  result.tileAnims = @[]
  result.spriteAnims = @[]
  for a in p.spriteAnims:
    if a.first <= 255 and a.last <= 255 and result.spriteAnims.len < 256:
      result.spriteAnims.add a
  result.enableAnims(p.version)
  if result.spriteAnims.len == 0: result.spriteAnims.add Animation()
  result.dropOverlays

proc fitV2(p: SpriteProject): SpriteProject =
  ## Drops what V2 can't hold, or SpritePad 2.3 won't load: sprites past 4096,
  ## tiles and animations past 256, tile cells past 4 either way, tile
  ## animations, and overlays when the overlay distance isn't 1. Tile
  ## attributes, tags and names are not written. See `enableAnims` for the
  ## enabled bit.
  result = p
  if result.sprites.len > 4096: result.sprites.setLen 4096
  if not result.tileSystem: result.tiles = @[]
  if result.tiles.len > 256: result.tiles.setLen 256
  result.cropTiles(4, 4)
  result.tileAnims = @[]
  if result.spriteAnims.len > 256: result.spriteAnims.setLen 256
  result.enableAnims(p.version)
  result.dropOverlays

proc fitV5(p: SpriteProject): SpriteProject =
  ## Drops what V5 can't hold: sprites and tiles past 65535, tile cells past
  ## 255 either way, animations past 256 and name chars past 32 or a 0 byte.
  result = p
  if result.sprites.len > 65535: result.sprites.setLen 65535
  if not result.tileSystem: result.tiles = @[]
  if result.tiles.len > 65535: result.tiles.setLen 65535
  result.cropTiles(255, 255)
  for t in result.tiles.mitems:
    let zero = t.name.find('\0')
    if zero >= 0: t.name.setLen zero
    if t.name.len > 32: t.name.setLen 32
  if result.spriteAnims.len > 256: result.spriteAnims.setLen 256
  if result.tileAnims.len > 256: result.tileAnims.setLen 256

proc writeSprites(w: var Writer, p: SpriteProject) =
  for s in p.sprites:
    for b in s.data: w.u8 b
    w.u8 s.attributes

proc writeAnims(w: var Writer, anims: seq[Animation], wordFrames = true) =
  for a in anims:
    if wordFrames: w.u16 a.first else: w.u8 a.first
  for a in anims:
    if wordFrames: w.u16 a.last else: w.u8 a.last
  for a in anims: w.u8 a.timer
  for a in anims: w.u8 a.attributes

proc formatV1(p: SpriteProject): seq[byte] =
  var w: Writer
  for c in "SPD": w.u8 ord(c)
  w.u8 1
  w.u8 p.sprites.len - 1
  w.u8 p.spriteAnims.len - 1
  for c in p.colours: w.u8 c
  w.writeSprites(p)
  w.writeAnims(p.spriteAnims, wordFrames = false)
  w.data

proc formatV2(p: SpriteProject): seq[byte] =
  var w: Writer
  for c in "SPD": w.u8 ord(c)
  w.u8 2
  w.u8(uint8(p.tileSystem) or uint8(p.spriteAnims.len > 0) shl 1)
  w.u16 p.sprites.len
  # Like SpritePad, 0 for the parts that are off.
  w.u16 p.tiles.len
  w.u16 p.spriteAnims.len
  w.u8(if p.tileSystem: p.tileWidth else: 0)
  w.u8(if p.tileSystem: p.tileHeight else: 0)
  for c in p.colours: w.u8 c

  w.writeSprites(p)
  if p.tileSystem:
    for t in p.tiles:
      for c in t.cells: w.u16 c
  w.writeAnims(p.spriteAnims)
  w.data

proc formatV5(p: SpriteProject): seq[byte] =
  var w: Writer
  for c in "SPD": w.u8 ord(c)
  w.u8 5
  w.u8(uint8(p.tileSystem) or uint8(p.spriteAnims.len > 0) shl 1 or
       uint8(p.tileAnims.len > 0) shl 2)
  w.u16 p.sprites.len
  w.u16 p.tiles.len
  # Like SpritePad, 0 for the parts that are off.
  w.u8 max(p.spriteAnims.len - 1, 0)
  w.u8 max(p.tileAnims.len - 1, 0)
  w.u8(if p.tileSystem: p.tileWidth else: 0)
  w.u8(if p.tileSystem: p.tileHeight else: 0)
  for c in p.colours: w.u8 c
  w.u16 cast[uint16](p.spriteOverlay)
  w.u16 cast[uint16](p.tileOverlay)

  w.writeSprites(p)

  if p.tileSystem:
    for t in p.tiles:
      for c in t.cells: w.u16 c
    for t in p.tiles: w.u8 t.attributes
    for t in p.tiles: w.u8 t.tag
    for t in p.tiles: w.zstring t.name

  w.writeAnims(p.spriteAnims)
  w.writeAnims(p.tileAnims)
  w.data

proc toSpd*(p: SpriteProject, version = 5): seq[byte] =
  ## Formats `p` as a .spd file of version 1, 2 or 5. What the version can't
  ## hold is left out (see `fitV1`, `fitV2` and `fitV5`). Raises SpdError on other versions
  ## and on projects that don't hold together, such as one without sprites.
  p.check
  case version
  of 1: formatV1(p.fitV1)
  of 2: formatV2(p.fitV2)
  of 5: formatV5(p.fitV5)
  else: fail("writing SPD version " & $version & " is not supported yet")

proc writeSpd*(path: string, p: SpriteProject, version = 5) =
  let data = p.toSpd(version)
  writeFile(path, data)
