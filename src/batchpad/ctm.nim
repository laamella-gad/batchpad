## CharPad project files (.ctm). Layouts are described in docs/charpad.md.

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

type Reader = object
  data: seq[byte]
  pos: int

proc fail(r: Reader, msg: string) {.noreturn.} =
  raise newException(CtmError, msg & " at offset " & $r.pos)

proc u8(r: var Reader): uint8 =
  if r.pos >= r.data.len: r.fail("unexpected end of file")
  result = r.data[r.pos]
  inc r.pos

proc u16(r: var Reader): uint16 =
  let lo = r.u8
  result = lo.uint16 or (r.u8.uint16 shl 8)

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
  for t in p.tiles.mitems:
    while true:
      let c = r.u8
      if c == 0: break
      t.name.add char(c)

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
  result.tileSystem = (flags and 1) != 0

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
  result.tileSystem = (flags and 1) != 0
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

type Writer = object
  data: seq[byte]
  blocks: int

proc u8(w: var Writer, v: SomeInteger) = w.data.add byte(v)

proc u16(w: var Writer, v: SomeInteger) =
  w.u8(v and 0xff)
  w.u8((v shr 8) and 0xff)

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

proc checkV9(p: Project) =
  if p.chars.len notin 1..65536: fail("V9 holds 1 to 65536 chars, not " & $p.chars.len)
  if p.keyMap > 15: fail("key map " & $p.keyMap & " does not fit in 4 bits")
  if p.tileSystem:
    if p.tiles.len notin 1..65536: fail("V9 holds 1 to 65536 tiles, not " & $p.tiles.len)
    if p.tileWidth notin 1..255 or p.tileHeight notin 1..255:
      fail("tile size " & $p.tileWidth & " x " & $p.tileHeight & " is not 1 to 255 each way")
    for i, t in p.tiles:
      if t.cells.len != p.tileWidth * p.tileHeight:
        fail("tile " & $i & " has " & $t.cells.len & " cells, not " & $(p.tileWidth * p.tileHeight))
      if t.name.len > 32: fail("tile " & $i & " name is longer than 32 chars")
      if '\0' in t.name: fail("tile " & $i & " name holds a 0 byte")
  if p.mapWidth notin 0..65535 or p.mapHeight notin 0..65535:
    fail("map size " & $p.mapWidth & " x " & $p.mapHeight & " is over 65535 one way")
  if p.map.len != p.mapWidth * p.mapHeight:
    fail("map has " & $p.map.len & " cells, not " & $(p.mapWidth * p.mapHeight))

proc formatV9(p: Project): seq[byte] =
  p.checkV9
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

  w.blockMarker
  w.u16 p.chars.len - 1
  for ch in p.chars:
    for b in ch.data: w.u8 b
  w.blockMarker
  for ch in p.chars: w.u8 ch.material
  if p.colouring == cmPerChar:
    w.blockMarker
    for ch in p.chars: w.writeColours(ch.colours, p.displayMode)

  if p.tileSystem:
    w.blockMarker
    w.u16 p.tiles.len - 1
    w.u8 p.tileWidth
    w.u8 p.tileHeight
    for t in p.tiles:
      for c in t.cells: w.u16 c
    if p.colouring == cmPerTile:
      w.blockMarker
      for t in p.tiles: w.writeColours(t.colours, p.displayMode)
    w.blockMarker
    for t in p.tiles: w.u8 t.tag
    w.blockMarker
    for t in p.tiles:
      for c in t.name: w.u8 ord(c)
      w.u8 0

  w.blockMarker
  w.u16 p.mapWidth
  w.u16 p.mapHeight
  for c in p.map: w.u16 c
  w.data

proc toCtm*(p: Project, version = 9): seq[byte] =
  ## Formats `p` as a .ctm file of the given version. Raises CtmError when the
  ## version can't hold it. The colour bytes a display mode doesn't store
  ## (e.g. colour RAM in hires bitmap) are dropped.
  case version
  of 9: formatV9(p)
  else: fail("writing CTM version " & $version & " is not supported yet")

proc writeCtm*(path: string, p: Project, version = 9) =
  let data = p.toCtm(version)
  writeFile(path, data)
