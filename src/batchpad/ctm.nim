## CharPad project files (.ctm). Layouts are described in docs/charpad.md.

import std/[bitops, tables]
import binio

type
  CtmError* = object of ValueError

  DisplayMode* = enum
    dmHiresText, dmMulticolourText, dmEcmText, dmHiresBitmap, dmMulticolourBitmap

  ColouringMethod* = enum
    cmPerProject, cmPerTile, cmPerChar

  Colours* = array[3, uint8]
    ## Colour RAM colour, then the low and high nibble for screen RAM (the two
    ## colours of a bitmap cell). Text modes only use the first.

  Char* = object
    data*: array[8, uint8]
    material*: uint8
    colours*: Colours     ## only meaningful when colouring is per char

  Tile* = object
    cells*: seq[uint16]   ## char numbers, row by row
    colours*: Colours     ## only meaningful when colouring is per tile
    tag*: uint8
    name*: string

  FlexiGrid* = object
    width*, height*: uint16
    settings*: uint8      ## `ETUx xxCC`, see docs/charpad.md

  Project* = object
    version*: int
    displayMode*: DisplayMode
    colouring*: ColouringMethod
    tileSystem*: bool
    keyMap*: uint8
    flexiGrid*: FlexiGrid
    chipColours*: array[4, uint8]  ## $d021-$d024, as stored
    colours*: Colours              ## used when colouring is per project
    chars*: seq[Char]
    tileWidth*, tileHeight*: int
    tiles*: seq[Tile]              ## empty when the tile system is off
    mapWidth*, mapHeight*: int
    map*: seq[uint16]              ## tile numbers, or char numbers without tiles

func colourCount*(mode: DisplayMode): int =
  ## Colour bytes per char or tile in the V8/V9 colour blocks.
  case mode
  of dmHiresText, dmMulticolourText, dmEcmText: 1
  of dmHiresBitmap: 2
  of dmMulticolourBitmap: 3

type Reader = binio.Reader[CtmError]

proc blockMarker(r: var Reader, what: string) =
  ## Every block starts with `$da, $b0 | n`, n counting the blocks in order.
  let start = r.pos
  if r.u8 != 0xda'u8:
    r.pos = start
    r.fail("missing block marker before " & what)
  discard r.u8

proc readColours(r: var Reader, mode: DisplayMode): Colours =
  case mode.colourCount
  of 1: result[0] = r.u8
  of 2:
    result[1] = r.u8
    result[2] = r.u8
  else:
    for c in result.mitems: c = r.u8

proc readDisplayMode(r: var Reader, max: DisplayMode): DisplayMode =
  let mode = r.u8
  if mode.int > ord(max): r.fail("unknown display mode " & $mode)
  DisplayMode(mode)

proc readColouring(r: var Reader): ColouringMethod =
  let colouring = r.u8
  if colouring > ord(ColouringMethod.high): r.fail("unknown colouring method " & $colouring)
  ColouringMethod(colouring)

proc readChars(r: var Reader, p: var Project) =
  r.blockMarker("chars")
  p.chars.setLen(r.u16.int + 1)
  for ch in p.chars.mitems:
    for b in ch.data.mitems: b = r.u8

proc readTiles(r: var Reader, p: var Project) =
  ## The tile block up to, not including, the tile colours.
  r.blockMarker("tiles")
  p.tiles.setLen(r.u16.int + 1)
  p.tileWidth = r.u8.int
  p.tileHeight = r.u8.int
  for t in p.tiles.mitems:
    t.cells.setLen(p.tileWidth * p.tileHeight)
    for c in t.cells.mitems: c = r.u16

proc readTagsAndNames(r: var Reader, p: var Project) =
  r.blockMarker("tile tags")
  for t in p.tiles.mitems: t.tag = r.u8
  r.blockMarker("tile names")
  for t in p.tiles.mitems: t.name = r.zstring

proc readMap(r: var Reader, p: var Project) =
  r.blockMarker("map")
  p.mapWidth = r.u16.int
  p.mapHeight = r.u16.int
  p.map.setLen(p.mapWidth * p.mapHeight)
  for c in p.map.mitems: c = r.u16

proc readV7Blocks(r: var Reader, p: var Project) =
  ## The blocks of V6 and V7, which are the same.
  r.readChars(p)
  r.blockMarker("char attributes")
  for ch in p.chars.mitems:
    let a = r.u8
    ch.material = a shr 4
    ch.colours[0] = a and 0x0f

  if p.tileSystem:
    r.readTiles(p)
    if p.colouring == cmPerTile:
      r.blockMarker("tile colours")
      for t in p.tiles.mitems: t.colours[0] = r.u8
    r.readTagsAndNames(p)

  r.readMap(p)

proc parseV7(r: var Reader): Project =
  ## V7 has no bitmap modes: one colour per project, tile or char, kept in
  ## `colours[0]`. The char attribute byte is split into material (high
  ## nibble) and colour (low nibble).
  result.version = 7
  for c in result.chipColours.mitems: c = r.u8
  result.colours[0] = r.u8
  result.colouring = r.readColouring
  result.displayMode = r.readDisplayMode(dmEcmText)
  let flags = r.u8
  result.tileSystem = flags.testBit(0)

  r.readV7Blocks(result)

proc readV8Blocks(r: var Reader, p: var Project) =
  ## The blocks of V8 and V9, which are the same.
  r.readChars(p)
  r.blockMarker("char materials")
  for ch in p.chars.mitems: ch.material = r.u8
  if p.colouring == cmPerChar:
    r.blockMarker("char colours")
    for ch in p.chars.mitems: ch.colours = r.readColours(p.displayMode)

  if p.tileSystem:
    r.readTiles(p)
    if p.colouring == cmPerTile:
      r.blockMarker("tile colours")
      for t in p.tiles.mitems: t.colours = r.readColours(p.displayMode)
    r.readTagsAndNames(p)

  r.readMap(p)

proc readMapOf(r: var Reader, p: var Project, bytes: bool) =
  ## The map of V4 and V5, which have no block marker or size of their own:
  ## `p.mapWidth` and `p.mapHeight` are set. A byte or a word per cell.
  p.map.setLen(p.mapWidth * p.mapHeight)
  for c in p.map.mitems: c = if bytes: r.u8.uint16 else: r.u16

proc readCharsAndAttribs(r: var Reader, p: var Project, count: int) =
  ## The chars and their attribute bytes, `MMMMCCCC`, of V4 and V5.
  p.chars.setLen count
  for ch in p.chars.mitems:
    for b in ch.data.mitems: b = r.u8
  for ch in p.chars.mitems:
    let a = r.u8
    ch.material = a shr 4
    ch.colours[0] = a and 0x0f

proc expandedCells(r: Reader, p: var Project) =
  ## The tile data that CHAREX leaves out: 0, 1, 2 ... through all cells.
  if p.tiles.len * p.tileWidth * p.tileHeight != p.chars.len:
    r.fail("the char set is expanded, but " & $p.chars.len & " chars are not " &
           $p.tiles.len & " tiles of " & $p.tileWidth & " x " & $p.tileHeight)
  var n = 0'u16
  for t in p.tiles.mitems:
    t.cells.setLen(p.tileWidth * p.tileHeight)
    for c in t.cells.mitems:
      c = n
      inc n

proc parseV5(r: var Reader): Project =
  ## No display modes past multicolour text, one colour per char or tile, no
  ## tags or names. The tile fields mean nothing when the tile system is off.
  result.version = 5
  for i in 0 .. 2: result.chipColours[i] = r.u8
  result.colours[0] = r.u8
  result.colouring = r.readColouring
  let flags = r.u8
  result.tileSystem = flags.testBit(0)
  let expanded = flags.testBit(1)
  result.displayMode = if flags.testBit(2): dmMulticolourText else: dmHiresText
  let charCount = r.u16.int + 1
  let tileCount = r.u16.int + 1
  let (tw, th) = (r.u8.int, r.u8.int)
  result.mapWidth = r.u16.int
  result.mapHeight = r.u16.int
  r.readCharsAndAttribs(result, charCount)
  if result.tileSystem:
    if tw == 0 or th == 0: r.fail("tile size " & $tw & " x " & $th)
    result.tileWidth = tw
    result.tileHeight = th
    result.tiles.setLen tileCount
    if expanded: r.expandedCells(result)
    else:
      for t in result.tiles.mitems:
        t.cells.setLen(tw * th)
        for c in t.cells.mitems: c = r.u16
    if result.colouring == cmPerTile:
      for t in result.tiles.mitems: t.colours[0] = r.u8
  r.readMapOf(result, bytes = false)

proc parseV3V4(r: var Reader, version: int): Project =
  ## V3 is V4 with a different header (square tiles) and no attribute block
  ## per char. Always has tiles, 256 at most. Colour and material are kept per tile
  ## cell, not per char: a char used with another colour or material gets a
  ## copy, so that a project colours per char, as the later versions do
  ## ("per tile cell" becomes "per char"). The attribute block per char is only
  ## used for chars no tile cell points at, as CharPad does.
  result.version = version
  for i in 0 .. 2: result.chipColours[i] = r.u8
  result.colours[0] = r.u8
  let colourMethod = r.u8
  if colourMethod > 2: r.fail("unknown colouring method " & $colourMethod)
  result.colouring = if colourMethod == 2: cmPerChar else: ColouringMethod(colourMethod)
  result.displayMode = if r.u8 == 1: dmMulticolourText else: dmHiresText
  var charCount, tileCount: int
  var expanded: bool
  if version == 3:
    result.mapWidth = r.u16.int
    result.mapHeight = r.u16.int
    charCount = r.u16.int + 1
    tileCount = r.u8.int + 1
    result.tileWidth = r.u8.int
    result.tileHeight = result.tileWidth
    expanded = r.u8 == 1
    discard r.u8
  else:
    charCount = r.u16.int + 1
    tileCount = r.u8.int + 1
    result.tileWidth = r.u8.int
    result.tileHeight = r.u8.int
    result.mapWidth = r.u16.int
    result.mapHeight = r.u16.int
    expanded = r.u8 == 1
    for i in 0 .. 3: discard r.u8
  if result.tileWidth == 0 or result.tileHeight == 0:
    r.fail("tile size " & $result.tileWidth & " x " & $result.tileHeight)
  result.tileSystem = true
  if version == 3:
    result.chars.setLen charCount
    for ch in result.chars.mitems:
      for b in ch.data.mitems: b = r.u8
  else:
    r.readCharsAndAttribs(result, charCount)
  result.tiles.setLen tileCount
  if expanded: r.expandedCells(result)
  else:
    for t in result.tiles.mitems:
      t.cells.setLen(result.tileWidth * result.tileHeight)
      for c in t.cells.mitems: c = r.u16
  var seen = initTable[(uint16, uint8, uint8), uint16]()
  var claimed = newSeq[bool](result.chars.len)
  for t in result.tiles.mitems:
    for c in t.cells.mitems:
      let a = r.u8
      let key = (c, a shr 4, if colourMethod == 2: a and 0x0f else: 0'u8)
      if c.int >= result.chars.len: r.fail("a tile cell uses char " & $c & " but there are " & $result.chars.len)
      if key in seen:
        c = seen[key]
      elif not claimed[c.int]:
        claimed[c.int] = true
        result.chars[c.int].material = key[1]
        if colourMethod == 2: result.chars[c.int].colours[0] = key[2]
        seen[key] = c
      else:
        if result.chars.len >= 65536: r.fail("tile cells need more than 65536 chars")
        var copy = result.chars[c.int]
        copy.material = key[1]
        if colourMethod == 2: copy.colours[0] = key[2]
        seen[key] = uint16(result.chars.len)
        result.chars.add copy
        c = seen[key]
  if colourMethod == 1:
    for t in result.tiles.mitems: t.colours[0] = r.u8
  r.readMapOf(result, bytes = true)

proc parseV6(r: var Reader): Project =
  ## As V7, but multicolour is a flag instead of a display mode (no ECM) and
  ## there is no $d024.
  result.version = 6
  for i in 0 .. 2: result.chipColours[i] = r.u8
  result.colours[0] = r.u8
  result.colouring = r.readColouring
  let flags = r.u8
  result.displayMode = if flags.testBit(0): dmMulticolourText else: dmHiresText
  result.tileSystem = flags.testBit(1)
  r.readV7Blocks(result)

proc parseV8(r: var Reader, version: int): Project =
  ## V8 is V9 without the flexi-grid and the key map. `version` is 8, or 82
  ## from a prototype; either way the project is called V8.
  result.version = 8
  result.displayMode = r.readDisplayMode(DisplayMode.high)
  result.colouring = r.readColouring
  result.tileSystem = r.u8.testBit(0)
  for c in result.chipColours.mitems: c = r.u8
  for c in result.colours.mitems: c = r.u8
  r.readV8Blocks(result)

proc parseV9(r: var Reader): Project =
  result.version = 9
  result.displayMode = r.readDisplayMode(DisplayMode.high)
  result.colouring = r.readColouring
  let flags = r.u8
  result.tileSystem = flags.testBit(0)
  result.keyMap = flags shr 4
  result.flexiGrid.width = r.u16
  result.flexiGrid.height = r.u16
  result.flexiGrid.settings = r.u8
  for c in result.chipColours.mitems: c = r.u8
  for c in result.colours.mitems: c = r.u8
  r.readV8Blocks(result)

proc parseCtm*(data: openArray[byte]): Project =
  ## Parses a whole .ctm file. Raises CtmError on anything it can't read.
  var r = Reader(data: @data)
  if data.len < 4 or data[0] != byte('C') or data[1] != byte('T') or data[2] != byte('M'):
    r.fail("not a CharPad project (no CTM signature)")
  r.pos = 3
  let version = r.u8.int
  case version
  of 3, 4: result = parseV3V4(r, version)
  of 5: result = parseV5(r)
  of 6: result = parseV6(r)
  of 7: result = parseV7(r)
  of 8, 82: result = parseV8(r, version)
  of 9: result = parseV9(r)
  else: r.fail("CTM version " & $version & " is not supported yet")
  if r.pos != r.data.len:
    r.fail($(r.data.len - r.pos) & " bytes after the map")

proc readCtm*(path: string): Project =
  let s = readFile(path)
  parseCtm(s.toOpenArrayByte(0, s.high))

proc blockMarker(w: var Writer) =
  w.u8 0xda
  w.u8(0xb0 + w.blocks)
  inc w.blocks

proc writeColours(w: var Writer, c: Colours, mode: DisplayMode) =
  case mode.colourCount
  of 1: w.u8 c[0]
  of 2:
    w.u8 c[1]
    w.u8 c[2]
  else:
    for v in c: w.u8 v

proc fail(msg: string) {.noreturn.} =
  raise newException(CtmError, msg)

proc check(p: Project) =
  ## What no version can write: a project that doesn't hold together.
  if p.chars.len == 0: fail("no chars")
  if p.tileSystem:
    if p.tiles.len == 0: fail("the tile system is on, but there are no tiles")
    if p.tileWidth < 1 or p.tileHeight < 1:
      fail("tile size " & $p.tileWidth & " x " & $p.tileHeight & " is under 1 x 1")
    for i, t in p.tiles:
      if t.cells.len != p.tileWidth * p.tileHeight:
        fail("tile " & $i & " has " & $t.cells.len & " cells, not " & $(p.tileWidth * p.tileHeight))
  if p.mapWidth < 0 or p.mapHeight < 0 or p.map.len != p.mapWidth * p.mapHeight:
    fail("map has " & $p.map.len & " cells, not " & $p.mapWidth & " x " & $p.mapHeight)

proc fit(p: Project, leftOut: var seq[string]): Project =
  ## Drops what V6 to V9 can't hold: chars and tiles past 65536, tile cells
  ## past 255 either way, map cells past 65535 either way and name chars past
  ## 32 or a 0 byte. Adds a line to `leftOut` for each.
  result = p
  if result.chars.len > 65536:
    leftOut.add count(p.chars.len - 65536, "chars") & " past 65536"
    result.chars.setLen 65536
  if not result.tileSystem: result.tiles = @[]
  if result.tiles.len > 65536:
    leftOut.add count(result.tiles.len - 65536, "tiles") & " past 65536"
    result.tiles.setLen 65536
  if result.tileSystem and (result.tileWidth > 255 or result.tileHeight > 255):
    leftOut.add "tile cells past 255 x 255 (the tiles are " & $p.tileWidth & " x " & $p.tileHeight & ")"
    let (w, h) = (min(p.tileWidth, 255), min(p.tileHeight, 255))
    for t in result.tiles.mitems:
      var cells = newSeq[uint16](w * h)
      for y in 0..<h:
        for x in 0..<w: cells[y * w + x] = t.cells[y * p.tileWidth + x]
      t.cells = cells
    result.tileWidth = w
    result.tileHeight = h
  var cut = 0
  for t in result.tiles.mitems:
    let zero = t.name.find('\0')
    if zero >= 0 or t.name.len > 32: inc cut
    if zero >= 0: t.name.setLen zero
    if t.name.len > 32: t.name.setLen 32
  if cut > 0: leftOut.add "the end of " & count(cut, "tile names") & " (past 32 chars or a 0 byte)"
  if result.mapWidth > 65535 or result.mapHeight > 65535:
    leftOut.add "map cells past 65535 x 65535 (the map is " & $p.mapWidth & " x " & $p.mapHeight & ")"
    let (w, h) = (min(p.mapWidth, 65535), min(p.mapHeight, 65535))
    result.map = newSeq[uint16](w * h)
    for y in 0..<h:
      for x in 0..<w: result.map[y * w + x] = p.map[y * p.mapWidth + x]
    result.mapWidth = w
    result.mapHeight = h

proc fitLow(p: Project, version: int, maxMode: DisplayMode, leftOut: var seq[string]): Project =
  ## V4 to V7: also drops the colour and material bits above 4, which only V8
  ## and later have, the key map and the flexi-grid. Modes past `maxMode` are
  ## refused: as another mode they would be garbage.
  let v = "V" & $version
  if p.displayMode > maxMode:
    fail(v & " has no " & (if p.displayMode > dmEcmText: "bitmap modes" else: "ECM mode"))
  result = p.fit(leftOut)
  var high = result.colours[0] > 15
  for ch in result.chars: high = high or ch.material > 15 or ch.colours[0] > 15
  for t in result.tiles: high = high or t.colours[0] > 15
  if high: leftOut.add "colour and material bits above the low 4 (" & v & " has 4)"
  if result.keyMap != 0: leftOut.add "key map " & $result.keyMap & " (" & v & " has none)"
  if result.flexiGrid.settings.testBit(7): leftOut.add "the flexi-grid (" & v & " has none)"
  if version <= 6 and result.chipColours[3] != 0: leftOut.add "$d024 (" & v & " has none)"
  if version <= 5:
    var tags, names = 0
    for t in result.tiles:
      if t.tag != 0: inc tags
      if t.name != "": inc names
    if tags > 0: leftOut.add count(tags, "tile tags") & " (" & v & " has none)"
    if names > 0: leftOut.add count(names, "tile names") & " (" & v & " has none)"
  result.colours[0] = result.colours[0] and 0x0f
  for ch in result.chars.mitems:
    ch.material = ch.material and 0x0f
    ch.colours[0] = ch.colours[0] and 0x0f
  for t in result.tiles.mitems: t.colours[0] = t.colours[0] and 0x0f

proc fitV3V4(p: Project, version: int, leftOut: var seq[string]): Project =
  ## Also what V3 and V4 lack: a map of chars, more than 256 tiles. A tile cell
  ## whose char is past the char set is refused: the cell's colour comes from it.
  ## V3 has square tiles only: bigger rectangles are cut to a square.
  let v = "V" & $version
  if not p.tileSystem: fail(v & " always has tiles, and this project is a char map")
  result = p.fitLow(version, dmMulticolourText, leftOut)
  if result.tiles.len > 256: fail(v & " holds 256 tiles; the project has " & $result.tiles.len)
  for i, c in result.map:
    if c > 255: fail(v & " holds tiles 0 to 255; map cell " & $i & " uses tile " & $c)
  if version == 3 and result.tileWidth != result.tileHeight:
    let side = min(result.tileWidth, result.tileHeight)
    leftOut.add "tile cells past " & $side & " x " & $side & " (V3 has square tiles; the tiles are " &
                $result.tileWidth & " x " & $result.tileHeight & ")"
    for t in result.tiles.mitems:
      var cells = newSeq[uint16](side * side)
      for y in 0 ..< side:
        for x in 0 ..< side: cells[y * side + x] = t.cells[y * result.tileWidth + x]
      t.cells = cells
    result.tileWidth = side
    result.tileHeight = side
  for i, t in result.tiles:
    for c in t.cells:
      if c.int >= result.chars.len: fail("tile " & $i & " uses char " & $c & " but there are " & $result.chars.len)

proc fitV8(p: Project, leftOut: var seq[string]): Project =
  ## Also drops the key map and the flexi-grid, which V8 has none of.
  result = p.fit(leftOut)
  if result.keyMap != 0: leftOut.add "key map " & $result.keyMap & " (V8 has none)"
  if result.flexiGrid.settings.testBit(7): leftOut.add "the flexi-grid (V8 has none)"
  result.keyMap = 0
  result.flexiGrid = FlexiGrid()

proc fitV9(p: Project, leftOut: var seq[string]): Project =
  ## Also drops key maps above 15, which don't fit in their 4 bits.
  result = p.fit(leftOut)
  if result.keyMap > 15:
    leftOut.add "key map " & $result.keyMap & " (V9 holds 0-15)"
    result.keyMap = 0

proc writeChars(w: var Writer, p: Project) =
  w.blockMarker
  w.u16 p.chars.len - 1
  for ch in p.chars:
    for b in ch.data: w.u8 b

proc writeTiles(w: var Writer, p: Project) =
  ## The tile block up to, not including, the tile colours.
  w.blockMarker
  w.u16 p.tiles.len - 1
  w.u8 p.tileWidth
  w.u8 p.tileHeight
  for t in p.tiles:
    for c in t.cells: w.u16 c

proc writeTagsAndNames(w: var Writer, p: Project) =
  w.blockMarker
  for t in p.tiles: w.u8 t.tag
  w.blockMarker
  for t in p.tiles: w.zstring t.name

proc writeMap(w: var Writer, p: Project) =
  w.blockMarker
  w.u16 p.mapWidth
  w.u16 p.mapHeight
  for c in p.map: w.u16 c

proc writeV7Blocks(w: var Writer, p: Project) =
  ## The blocks of V6 and V7, which are the same.
  w.writeChars(p)
  w.blockMarker
  for ch in p.chars: w.u8((ch.material shl 4) or ch.colours[0])

  if p.tileSystem:
    w.writeTiles(p)
    if p.colouring == cmPerTile:
      w.blockMarker
      for t in p.tiles: w.u8 t.colours[0]
    w.writeTagsAndNames(p)

  w.writeMap(p)

proc formatV6(p: Project): seq[byte] =
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 6
  for i in 0 .. 2: w.u8 p.chipColours[i]
  w.u8 p.colours[0]
  w.u8 ord(p.colouring)
  w.u8(uint8(p.displayMode == dmMulticolourText) or (uint8(p.tileSystem) shl 1))
  w.writeV7Blocks(p)
  w.data

proc formatV7(p: Project): seq[byte] =
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 7
  for c in p.chipColours: w.u8 c
  w.u8 p.colours[0]
  w.u8 ord(p.colouring)
  w.u8 ord(p.displayMode)
  w.u8 uint8(p.tileSystem)
  w.writeV7Blocks(p)
  w.data

proc writeCharsAndAttribs(w: var Writer, p: Project) =
  for ch in p.chars:
    for b in ch.data: w.u8 b
  for ch in p.chars:
    w.u8((ch.material shl 4) or ch.colours[0])

proc formatV5(p: Project): seq[byte] =
  ## The tile data is always written, never left out as CHAREX.
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 5
  for i in 0 .. 2: w.u8 p.chipColours[i]
  w.u8 p.colours[0]
  w.u8 ord(p.colouring)
  w.u8(uint8(p.tileSystem) or (uint8(p.displayMode == dmMulticolourText) shl 2))
  w.u16 p.chars.len - 1
  if p.tileSystem:
    w.u16 p.tiles.len - 1
    w.u8 p.tileWidth
    w.u8 p.tileHeight
  else:
    w.u16 0       # as CharPad 2.x writes them
    w.u8 0
    w.u8 0
  w.u16 p.mapWidth
  w.u16 p.mapHeight
  w.writeCharsAndAttribs(p)
  if p.tileSystem:
    for t in p.tiles:
      for c in t.cells: w.u16 c
    if p.colouring == cmPerTile:
      for t in p.tiles: w.u8 t.colours[0]
  for c in p.map: w.u16 c
  w.data

proc formatV3V4(p: Project, version: int): seq[byte] =
  ## V3 has a different header, and no attribute block per char.
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 version
  for i in 0 .. 2: w.u8 p.chipColours[i]
  w.u8 p.colours[0]
  w.u8 ord(p.colouring)
  w.u8 uint8(p.displayMode == dmMulticolourText)
  if version == 3:
    w.u16 p.mapWidth
    w.u16 p.mapHeight
    w.u16 p.chars.len - 1
    w.u8 p.tiles.len - 1
    w.u8 p.tileWidth
    w.u8 0
    w.u8 0
    for ch in p.chars:
      for b in ch.data: w.u8 b
  else:
    w.u16 p.chars.len - 1
    w.u8 p.tiles.len - 1
    w.u8 p.tileWidth
    w.u8 p.tileHeight
    w.u16 p.mapWidth
    w.u16 p.mapHeight
    w.u8 0
    for i in 0 .. 3: w.u8 0
    w.writeCharsAndAttribs(p)
  for t in p.tiles:
    for c in t.cells: w.u16 c
  for t in p.tiles:
    for c in t.cells:
      let ch = p.chars[c.int]
      w.u8((ch.material shl 4) or (if p.colouring == cmPerChar: ch.colours[0] else: 0))
  if p.colouring == cmPerTile:
    for t in p.tiles: w.u8 t.colours[0]
  for c in p.map: w.u8 c
  w.data

proc writeV8Blocks(w: var Writer, p: Project) =
  ## The blocks of V8 and V9, which are the same.
  w.writeChars(p)
  w.blockMarker
  for ch in p.chars: w.u8 ch.material
  if p.colouring == cmPerChar:
    w.blockMarker
    for ch in p.chars: w.writeColours(ch.colours, p.displayMode)

  if p.tileSystem:
    w.writeTiles(p)
    if p.colouring == cmPerTile:
      w.blockMarker
      for t in p.tiles: w.writeColours(t.colours, p.displayMode)
    w.writeTagsAndNames(p)

  w.writeMap(p)

proc formatV8(p: Project): seq[byte] =
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 8
  w.u8 ord(p.displayMode)
  w.u8 ord(p.colouring)
  w.u8 uint8(p.tileSystem)
  for c in p.chipColours: w.u8 c
  for c in p.colours: w.u8 c
  w.writeV8Blocks(p)
  w.data

proc formatV9(p: Project): seq[byte] =
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 9
  w.u8 ord(p.displayMode)
  w.u8 ord(p.colouring)
  w.u8((p.keyMap shl 4) or uint8(p.tileSystem))
  w.u16 p.flexiGrid.width
  w.u16 p.flexiGrid.height
  w.u8 p.flexiGrid.settings
  for c in p.chipColours: w.u8 c
  for c in p.colours: w.u8 c
  w.writeV8Blocks(p)
  w.data

proc toCtm*(p: Project, version: int, leftOut: var seq[string]): seq[byte] =
  ## Formats `p` as a .ctm file of version 3 to 9. What the version can't
  ## hold is left out (see `fit`, `fitLow`, `fitV3V4`, `fitV8` and `fitV9`), with a line in
  ## `leftOut` for each, and so are the colour bytes a display mode doesn't
  ## use (e.g. colour RAM in hires bitmap, screen colours in text modes),
  ## without a line. Raises CtmError on other versions, on projects that don't
  ## hold together, such as one without chars, and on bitmap modes in V6 and V7 and ECM in V3 to V6, and on char maps and more than 256 tiles in V3 and V4.
  p.check
  case version
  of 3, 4: formatV3V4(p.fitV3V4(version, leftOut), version)
  of 5: formatV5(p.fitLow(5, dmMulticolourText, leftOut))
  of 6: formatV6(p.fitLow(6, dmMulticolourText, leftOut))
  of 7: formatV7(p.fitLow(7, dmEcmText, leftOut))
  of 8: formatV8(p.fitV8(leftOut))
  of 9: formatV9(p.fitV9(leftOut))
  else: fail("writing CTM version " & $version & " is not supported yet")

proc toCtm*(p: Project, version = 9): seq[byte] =
  ## `toCtm` without the list of what is left out.
  var leftOut: seq[string]
  p.toCtm(version, leftOut)

proc writeCtm*(path: string, p: Project, version = 9) =
  let data = p.toCtm(version)
  writeFile(path, data)

proc expandTiles*(p: var Project) =
  ## Turns the tile map into a char map and switches the tile system off.
  ## With per tile colouring the colours move to the chars: a char used in
  ## tiles of different colours gets a copy per colour, and the colouring
  ## becomes per char. Tile tags and names are lost. Raises CtmError when a
  ## tile or char number is out of range.
  if not p.tileSystem: return
  let used = case p.displayMode.colourCount
             of 1: {0}
             of 2: {1, 2}
             else: {0, 1, 2}
  proc key(c: Colours): Colours =
    for i in used: result[i] = c[i]
  let tileUnit = p.tileWidth * p.tileHeight
  let perTile = p.colouring == cmPerTile
  var chars = p.chars
  var coloured = newSeq[bool](chars.len)
  var copies: seq[(int, Colours, int)]   ## char, colours, number of the copy
  var map = newSeq[uint16](p.map.len * tileUnit)
  let wide = p.mapWidth * p.tileWidth
  for my in 0 ..< p.mapHeight:
    for mx in 0 ..< p.mapWidth:
      let n = int(p.map[my * p.mapWidth + mx])
      if n >= p.tiles.len:
        raise newException(CtmError, "map cell " & $mx & "," & $my & " uses tile " & $n &
                           " but there are " & $p.tiles.len)
      for ty in 0 ..< p.tileHeight:
        for tx in 0 ..< p.tileWidth:
          var ch = int(p.tiles[n].cells[ty * p.tileWidth + tx])
          if ch >= p.chars.len:
            raise newException(CtmError, "tile " & $n & " uses char " & $ch &
                               " but there are " & $p.chars.len)
          if perTile:
            let c = p.tiles[n].colours.key
            if not coloured[ch]:
              coloured[ch] = true
              chars[ch].colours = c
            elif chars[ch].colours.key != c:
              var found = -1
              for (orig, colours, number) in copies:
                if orig == ch and colours == c: found = number
              if found < 0:
                found = chars.len
                if found > 0xffff:
                  raise newException(CtmError, "expanding the tiles needs more than 65536 chars")
                chars.add p.chars[ch]
                chars[found].colours = c
                copies.add (ch, c, found)
              ch = found
          map[(my * p.tileHeight + ty) * wide + mx * p.tileWidth + tx] = uint16(ch)
  if perTile: p.colouring = cmPerChar

  if not p.flexiGrid.settings.testBit(5):
    let (w, h) = (int(p.flexiGrid.width) * p.tileWidth, int(p.flexiGrid.height) * p.tileHeight)
    if w > 0xffff or h > 0xffff:
      raise newException(CtmError, "the flexi-grid is too big in chars")
    p.flexiGrid.width = uint16(w)
    p.flexiGrid.height = uint16(h)
  p.chars = chars
  p.map = map
  p.mapWidth = wide
  p.mapHeight = p.mapHeight * p.tileHeight
  p.tileSystem = false
  p.tiles = @[]
  p.tileWidth = 0
  p.tileHeight = 0
