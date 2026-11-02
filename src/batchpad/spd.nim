## SpritePad project files (.spd). Layouts are described in docs/spritepad.md.

import std/[bitops, os]
import binio

const
  sprVersion* = -1  ## `version` of a project read from an SpritePad 1.x `.spr`

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

proc parseV0(r: var Reader): SpriteProject =
  ## The headerless format of SpritePad 1.8, version 0 here: three colours and
  ## sprites, nothing else. Like SpritePad Pro, the colours are cut to their low
  ## nibble. Overlay means "the next sprite", so both distances are 1.
  result.version = 0
  for c in result.colours.mitems: c = r.u8 and 0x0f
  result.spriteOverlay = 1
  result.tileOverlay = 1
  r.readSprites(result, (r.data.len - 3) div 64)

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

proc parseV3V4V5(r: var Reader, version: int): SpriteProject =
  ## V4 is V5 without tile tags and names; V3 is V4 without overlay distances
  ## (overlay means "the next", so both are 1). Counts whose flag is off are
  ## ignored, as SpritePad does.
  result.version = version
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
  if version >= 4:
    result.spriteOverlay = cast[int16](r.u16)
    result.tileOverlay = cast[int16](r.u16)
  else:
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
    for t in result.tiles.mitems: t.attributes = r.u8
    if version == 5:
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
  let headerless = data.len >= 67 and (data.len - 3) mod 64 == 0 and
                   not (data[0] == byte('S') and data[1] == byte('P') and data[2] == byte('D'))
  if headerless:
    if data.len > 3 + 64 * 1024: r.fail("more than 1024 sprites")
    return parseV0(r)
  if data.len < 4 or data[0] != byte('S') or data[1] != byte('P') or data[2] != byte('D'):
    r.fail("not a SpritePad project (no SPD signature)")
  r.pos = 3
  let version = r.u8.int
  case version
  of 1: result = parseV1(r)
  of 2: result = parseV2(r)
  of 3, 4, 5: result = parseV3V4V5(r, version)
  else: r.fail("SPD version " & $version & " is not supported yet")
  if r.pos != r.data.len:
    r.fail($(r.data.len - r.pos) & " bytes after the last part")

proc parseSpr*(spr: openArray[byte], inf: openArray[byte] = []): SpriteProject =
  ## Parses the `.spr` of SpritePad 1.3 to 1.7 (sprites only: 64 bytes each,
  ## 1 to 256 of them) and its `.spr.inf`. As SpritePad 1.5, it takes the colours from
  ## an `inf` of exactly 3 bytes (cut to their low nibble) and otherwise has them all 0.
  ##
  ## Also Sprite Painter 1.2 (no samples; layout from the SpritePad 1.5
  ## ReadMe): an `inf` of a colour byte per sprite and then the 3 colours. The
  ## colour byte is taken as a 64th byte (bit 7 multicolour, bits 0-3 colour),
  ## and the `.spr` may hold 63 or 64 bytes per sprite. A `.spr` of 63 byte
  ## sprites without an `inf` (perhaps Sprite Painter 1.0 and 1.1) is read too.
  var r = Reader(data: @spr)
  let painter = inf.len > 3 and (spr.len == 63 * (inf.len - 3) or spr.len == 64 * (inf.len - 3))
  let size = if painter: spr.len div (inf.len - 3)
             elif inf.len == 0 and spr.len mod 64 != 0 and spr.len mod 63 == 0: 63
             else: 64
  if spr.len == 0 or spr.len mod size != 0 or spr.len > size * 256:
    r.fail("a .spr holds 1 to 256 sprites of 64 bytes, not " & $spr.len & " bytes")
  result.version = sprVersion
  if inf.len == 3 or painter:
    for i, c in result.colours.mpairs: c = inf[inf.len - 3 + i] and 0x0f
  result.spriteOverlay = 1
  result.tileOverlay = 1
  if size == 64:
    r.readSprites(result, spr.len div 64)
  else:
    result.sprites.setLen spr.len div 63
    for s in result.sprites.mitems:
      for b in s.data.mitems: b = r.u8
  if painter:
    for i, s in result.sprites.mpairs: s.attributes = inf[i]

proc readSpr*(path: string): SpriteProject =
  ## Reads `path` and, when it exists, `path & ".inf"`.
  let s = readFile(path)
  let inf = if fileExists(path & ".inf"): readFile(path & ".inf") else: ""
  parseSpr(s.toOpenArrayByte(0, s.high), inf.toOpenArrayByte(0, inf.high))

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

proc cropTiles(p: var SpriteProject, width, height: int, leftOut: var seq[string]) =
  ## Keeps the top left `width` x `height` sprites of every tile.
  if not p.tileSystem or p.tileWidth <= width and p.tileHeight <= height: return
  leftOut.add "tile cells past " & $width & " x " & $height & " (the tiles are " &
              $p.tileWidth & " x " & $p.tileHeight & ")"
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
    for a in p.tileAnims.mitems: a.attributes.setBit(7)

proc dropOverlays(p: var SpriteProject, leftOut: var seq[string]) =
  ## Up to V3 overlay means the next sprite, so overlays at another distance
  ## are left out.
  if p.spriteOverlay != 1:
    var n = 0
    for s in p.sprites.mitems:
      if s.overlay: inc n
      s.attributes.clearBit(4)
    if n > 0:
      leftOut.add "the overlay of " & count(n, "sprites") & " (overlay distance " & $p.spriteOverlay &
                  "; up to V3 overlay means the next sprite)"

proc dropTileOverlays(p: var SpriteProject, leftOut: var seq[string]) =
  ## As `dropOverlays`, for the tiles.
  if p.tileOverlay != 1:
    var n = 0
    for t in p.tiles.mitems:
      if t.overlay: inc n
      t.attributes.clearBit(4)
    if n > 0:
      leftOut.add "the overlay of " & count(n, "tiles") & " (overlay distance " & $p.tileOverlay &
                  "; up to V3 overlay means the next tile)"

proc limit[T](s: var seq[T], n: int, what: string, leftOut: var seq[string]) =
  if s.len > n:
    leftOut.add count(s.len - n, what) & " past " & $n
    s.setLen n

proc dropNames(p: var SpriteProject, leftOut: var seq[string]) =
  var cut = 0
  for t in p.tiles.mitems:
    let zero = t.name.find('\0')
    if zero >= 0 or t.name.len > 32: inc cut
    if zero >= 0: t.name.setLen zero
    if t.name.len > 32: t.name.setLen 32
  if cut > 0: leftOut.add "the end of " & count(cut, "tile names") & " (past 32 chars or a 0 byte)"

proc fitV1(p: SpriteProject, leftOut: var seq[string]): SpriteProject =
  ## Drops what V1 can't hold: tiles, tile animations, sprites and animations
  ## past 256, animations with frames above 255, and overlays when the overlay
  ## distance isn't 1. Adds a line to `leftOut` for each. V1 always holds an
  ## animation, so a project without one gets a blank one (not enabled). See
  ## `enableAnims` for the enabled bit.
  result = p
  result.sprites.limit(256, "sprites", leftOut)
  if p.tileSystem: leftOut.add "the tiles (V1 has none)"
  if p.tileAnims.len > 0: leftOut.add "the tile animations (V1 has none)"
  result.tileSystem = false
  result.tiles = @[]
  result.tileAnims = @[]
  result.spriteAnims = @[]
  var high = 0
  for a in p.spriteAnims:
    if a.first > 255 or a.last > 255: inc high
    else: result.spriteAnims.add a
  if high > 0: leftOut.add count(high, "sprite animations") & " with frames above 255"
  result.spriteAnims.limit(256, "sprite animations", leftOut)
  result.enableAnims(p.version)
  if result.spriteAnims.len == 0: result.spriteAnims.add Animation()
  result.dropOverlays(leftOut)

proc fitV2(p: SpriteProject, leftOut: var seq[string]): SpriteProject =
  ## Drops what V2 can't hold, or SpritePad 2.3 won't load: sprites past 4096,
  ## tiles and animations past 256, tile cells past 4 either way, tile
  ## animations, and overlays when the overlay distance isn't 1. Tile
  ## attributes, tags and names are not written. Adds a line to `leftOut` for
  ## each. See `enableAnims` for the enabled bit.
  result = p
  result.sprites.limit(4096, "sprites", leftOut)
  if not result.tileSystem: result.tiles = @[]
  result.tiles.limit(256, "tiles", leftOut)
  result.cropTiles(4, 4, leftOut)
  var overlays, tags, names = 0
  for t in result.tiles:
    if t.overlay: inc overlays
    if t.tag != 0: inc tags
    if t.name != "": inc names
  if overlays > 0: leftOut.add "the overlay of " & count(overlays, "tiles") & " (V2 has no tile attributes)"
  if tags > 0: leftOut.add "the tags of " & count(tags, "tiles") & " (V2 has none)"
  if names > 0: leftOut.add "the names of " & count(names, "tiles") & " (V2 has none)"
  if p.tileAnims.len > 0: leftOut.add "the tile animations (V2 has none)"
  result.tileAnims = @[]
  result.spriteAnims.limit(256, "sprite animations", leftOut)
  result.enableAnims(p.version)
  result.dropOverlays(leftOut)

proc fitV5(p: SpriteProject, leftOut: var seq[string], version = 5): SpriteProject =
  ## Drops what V5 can't hold: sprites and tiles past 65535, tile cells past
  ## 255 either way, animations past 256 and name chars past 32 or a 0 byte.
  ## Adds a line to `leftOut` for each. For V3 and V4, also the tags and names,
  ## which they have none of; for V3 also overlays at another distance than 1,
  ## and see `enableAnims` for the enabled bit.
  result = p
  result.sprites.limit(65535, "sprites", leftOut)
  if not result.tileSystem: result.tiles = @[]
  result.tiles.limit(65535, "tiles", leftOut)
  result.cropTiles(255, 255, leftOut)
  if version <= 4:
    var tags, names = 0
    for t in result.tiles:
      if t.tag != 0: inc tags
      if t.name != "": inc names
    if tags > 0: leftOut.add "the tags of " & count(tags, "tiles") & " (V" & $version & " has none)"
    if names > 0: leftOut.add "the names of " & count(names, "tiles") & " (V" & $version & " has none)"
  else:
    result.dropNames(leftOut)
  result.spriteAnims.limit(256, "sprite animations", leftOut)
  result.tileAnims.limit(256, "tile animations", leftOut)
  if version == 3:
    result.enableAnims(p.version)
    result.dropOverlays(leftOut)
    result.dropTileOverlays(leftOut)

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

proc fitV0(p: SpriteProject, leftOut: var seq[string], what = "the headerless format"): SpriteProject =
  ## Drops what the headerless format (or `.spr`, `what`) can't hold: tiles, animations, sprites
  ## past 256 (SpritePad Pro refuses more) and overlays when the overlay
  ## distance isn't 1.
  result = p
  result.sprites.limit(256, "sprites", leftOut)
  if p.tileSystem: leftOut.add "the tiles (" & what & " has none)"
  if p.spriteAnims.len + p.tileAnims.len > 0: leftOut.add "the animations (" & what & " has none)"
  result.tileSystem = false
  result.tiles = @[]
  result.spriteAnims = @[]
  result.tileAnims = @[]
  result.dropOverlays(leftOut)

proc formatV0(p: SpriteProject): seq[byte] =
  var w: Writer
  for c in p.colours: w.u8 c
  w.writeSprites(p)
  w.data

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

proc formatV5(p: SpriteProject, version = 5): seq[byte] =
  ## V4 has no tile tags and names, V3 also no overlay distances.
  var w: Writer
  for c in "SPD": w.u8 ord(c)
  w.u8 version
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
  if version >= 4:
    w.u16 cast[uint16](p.spriteOverlay)
    w.u16 cast[uint16](p.tileOverlay)

  w.writeSprites(p)

  if p.tileSystem:
    for t in p.tiles:
      for c in t.cells: w.u16 c
    for t in p.tiles: w.u8 t.attributes
    if version == 5:
      for t in p.tiles: w.u8 t.tag
      for t in p.tiles: w.zstring t.name

  w.writeAnims(p.spriteAnims)
  w.writeAnims(p.tileAnims)
  w.data

proc toSpr*(p: SpriteProject, leftOut: var seq[string]): tuple[spr, inf: seq[byte]] =
  ## Formats `p` as the `.spr` and `.spr.inf` of SpritePad 1.3 to 1.7. Leaves
  ## out the same as `toSpd` does for the headerless format.
  p.check
  let q = p.fitV0(leftOut, "a .spr")
  var w: Writer
  w.writeSprites(q)
  result.spr = w.data
  result.inf = @(q.colours)

proc toSprPainter*(p: SpriteProject, leftOut: var seq[string]): tuple[spr, inf: seq[byte]] =
  ## Formats `p` as the `.spr` and `.spr.inf` of Sprite Painter 1.2, as far as
  ## its layout is known (see `parseSpr`): the `.inf` holds each sprite's 64th
  ## byte and then the 3 colours. The `.spr` keeps the 64th bytes too, so
  ## SpritePad 1.3 to 1.7 read it (without the colours: their `.inf` is 3 bytes).
  result = p.toSpr(leftOut)
  let colours = result.inf
  result.inf = newSeq[byte]()
  for i in 0 ..< result.spr.len div 64: result.inf.add result.spr[i * 64 + 63]
  result.inf.add colours

proc toSpd*(p: SpriteProject, version: int, leftOut: var seq[string]): seq[byte] =
  ## Formats `p` as a .spd file of version 0 (headerless), 1, 2, 3, 4 or 5. What the version can't
  ## hold is left out (see `fitV0`, `fitV1`, `fitV2` and `fitV5`, which also does V3 and V4), with a line in
  ## `leftOut` for each. Raises SpdError on other versions and on projects
  ## that don't hold together, such as one without sprites.
  p.check
  case version
  of 0: formatV0(p.fitV0(leftOut))
  of 1: formatV1(p.fitV1(leftOut))
  of 2: formatV2(p.fitV2(leftOut))
  of 3: formatV5(p.fitV5(leftOut, 3), 3)
  of 4: formatV5(p.fitV5(leftOut, 4), 4)
  of 5: formatV5(p.fitV5(leftOut))
  else: fail("writing SPD version " & $version & " is not supported yet")

proc toSpd*(p: SpriteProject, version = 5): seq[byte] =
  ## `toSpd` without the list of what is left out.
  var leftOut: seq[string]
  p.toSpd(version, leftOut)

proc writeSpd*(path: string, p: SpriteProject, version = 5) =
  let data = p.toSpd(version)
  writeFile(path, data)
