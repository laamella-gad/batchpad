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

proc readAnims(r: var Reader, anims: var seq[Animation]) =
  ## Four lists in turn: first frames, last frames, timers, attributes.
  for a in anims.mitems: a.first = r.u16
  for a in anims.mitems: a.last = r.u16
  for a in anims.mitems: a.timer = r.u8
  for a in anims.mitems: a.attributes = r.u8

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

  result.sprites.setLen sprites
  for s in result.sprites.mitems:
    for b in s.data.mitems: b = r.u8
    s.attributes = r.u8

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
  of 5: result = parseV5(r)
  else: r.fail("SPD version " & $version & " is not supported yet")
  if r.pos != r.data.len:
    r.fail($(r.data.len - r.pos) & " bytes after the last part")

proc readSpd*(path: string): SpriteProject =
  let s = readFile(path)
  parseSpd(s.toOpenArrayByte(0, s.high))

proc fail(msg: string) {.noreturn.} =
  raise newException(SpdError, msg)

proc checkV5(p: SpriteProject) =
  if p.sprites.len notin 1..65535: fail("V5 holds 1 to 65535 sprites, not " & $p.sprites.len)
  if p.tileSystem:
    if p.tiles.len notin 1..65535: fail("V5 holds 1 to 65535 tiles, not " & $p.tiles.len)
    if p.tileWidth notin 1..255 or p.tileHeight notin 1..255:
      fail("tile size " & $p.tileWidth & " x " & $p.tileHeight & " is not 1 to 255 each way")
    for i, t in p.tiles:
      if t.cells.len != p.tileWidth * p.tileHeight:
        fail("tile " & $i & " has " & $t.cells.len & " cells, not " & $(p.tileWidth * p.tileHeight))
      if t.name.len > 32: fail("tile " & $i & " name is longer than 32 chars")
      if '\0' in t.name: fail("tile " & $i & " name holds a 0 byte")
  elif p.tiles.len > 0:
    fail("tiles while the tile system is off")
  if p.spriteAnims.len > 256: fail("V5 holds up to 256 sprite animations, not " & $p.spriteAnims.len)
  if p.tileAnims.len > 256: fail("V5 holds up to 256 tile animations, not " & $p.tileAnims.len)

proc writeAnims(w: var Writer, anims: seq[Animation]) =
  for a in anims: w.u16 a.first
  for a in anims: w.u16 a.last
  for a in anims: w.u8 a.timer
  for a in anims: w.u8 a.attributes

proc formatV5(p: SpriteProject): seq[byte] =
  p.checkV5
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

  for s in p.sprites:
    for b in s.data: w.u8 b
    w.u8 s.attributes

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
  ## Formats `p` as a .spd file of the given version. Raises SpdError when the
  ## version can't hold it.
  case version
  of 5: formatV5(p)
  else: fail("writing SPD version " & $version & " is not supported yet")

proc writeSpd*(path: string, p: SpriteProject, version = 5) =
  let data = p.toSpd(version)
  writeFile(path, data)
