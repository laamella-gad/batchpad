## CharPad project files (.ctm). Layouts are described in docs/charpad.md.

import std/bitops
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

  r.readChars(result)
  r.blockMarker("char attributes")
  for ch in result.chars.mitems:
    let a = r.u8
    ch.material = a shr 4
    ch.colours[0] = a and 0x0f

  if result.tileSystem:
    r.readTiles(result)
    if result.colouring == cmPerTile:
      r.blockMarker("tile colours")
      for t in result.tiles.mitems: t.colours[0] = r.u8
    r.readTagsAndNames(result)

  r.readMap(result)

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

  r.readChars(result)
  r.blockMarker("char materials")
  for ch in result.chars.mitems: ch.material = r.u8
  if result.colouring == cmPerChar:
    r.blockMarker("char colours")
    for ch in result.chars.mitems: ch.colours = r.readColours(result.displayMode)

  if result.tileSystem:
    r.readTiles(result)
    if result.colouring == cmPerTile:
      r.blockMarker("tile colours")
      for t in result.tiles.mitems: t.colours = r.readColours(result.displayMode)
    r.readTagsAndNames(result)

  r.readMap(result)

proc parseCtm*(data: openArray[byte]): Project =
  ## Parses a whole .ctm file. Raises CtmError on anything it can't read.
  var r = Reader(data: @data)
  if data.len < 4 or data[0] != byte('C') or data[1] != byte('T') or data[2] != byte('M'):
    r.fail("not a CharPad project (no CTM signature)")
  r.pos = 3
  let version = r.u8.int
  case version
  of 7: result = parseV7(r)
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
  ## Drops what V7 and V9 can't hold: chars and tiles past 65536, tile cells
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

proc fitV7(p: Project, leftOut: var seq[string]): Project =
  ## Also drops the colour and material bits above 4, which only V8 and
  ## later have, the key map and the flexi-grid. Bitmap modes are refused: as
  ## text they would be garbage.
  if p.displayMode > dmEcmText: fail("V7 has no bitmap modes")
  result = p.fit(leftOut)
  var high = result.colours[0] > 15
  for ch in result.chars: high = high or ch.material > 15 or ch.colours[0] > 15
  for t in result.tiles: high = high or t.colours[0] > 15
  if high: leftOut.add "colour and material bits above the low 4 (V7 has 4)"
  if result.keyMap != 0: leftOut.add "key map " & $result.keyMap & " (V7 has none)"
  if result.flexiGrid.settings.testBit(7): leftOut.add "the flexi-grid (V7 has none)"
  result.colours[0] = result.colours[0] and 0x0f
  for ch in result.chars.mitems:
    ch.material = ch.material and 0x0f
    ch.colours[0] = ch.colours[0] and 0x0f
  for t in result.tiles.mitems: t.colours[0] = t.colours[0] and 0x0f

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

proc formatV7(p: Project): seq[byte] =
  var w: Writer
  for c in "CTM": w.u8 ord(c)
  w.u8 7
  for c in p.chipColours: w.u8 c
  w.u8 p.colours[0]
  w.u8 ord(p.colouring)
  w.u8 ord(p.displayMode)
  w.u8 uint8(p.tileSystem)

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
  w.data

proc toCtm*(p: Project, version: int, leftOut: var seq[string]): seq[byte] =
  ## Formats `p` as a .ctm file of version 7 or 9. What the version can't
  ## hold is left out (see `fit`, `fitV7` and `fitV9`), with a line in
  ## `leftOut` for each, and so are the colour bytes a display mode doesn't
  ## use (e.g. colour RAM in hires bitmap, screen colours in text modes),
  ## without a line. Raises CtmError on other versions, on projects that don't
  ## hold together, such as one without chars, and on bitmap modes in V7.
  p.check
  case version
  of 7: formatV7(p.fitV7(leftOut))
  of 9: formatV9(p.fitV9(leftOut))
  else: fail("writing CTM version " & $version & " is not supported yet")

proc toCtm*(p: Project, version = 9): seq[byte] =
  ## `toCtm` without the list of what is left out.
  var leftOut: seq[string]
  p.toCtm(version, leftOut)

proc writeCtm*(path: string, p: Project, version = 9) =
  let data = p.toCtm(version)
  writeFile(path, data)
