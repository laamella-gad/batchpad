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

proc parseV9(r: var Reader): Project =
  result.version = 9
  let mode = r.u8
  if mode > ord(DisplayMode.high): r.fail("unknown display mode " & $mode)
  result.displayMode = DisplayMode(mode)
  let colouring = r.u8
  if colouring > ord(ColouringMethod.high): r.fail("unknown colouring method " & $colouring)
  result.colouring = ColouringMethod(colouring)
  let flags = r.u8
  result.tileSystem = (flags and 1) != 0
  result.keyMap = flags shr 4
  result.flexiGrid.width = r.u16
  result.flexiGrid.height = r.u16
  result.flexiGrid.settings = r.u8
  for c in result.chipColours.mitems: c = r.u8
  for c in result.colours.mitems: c = r.u8

  r.blockMarker("chars")
  result.chars.setLen(r.u16.int + 1)
  for ch in result.chars.mitems:
    for b in ch.data.mitems: b = r.u8
  r.blockMarker("char materials")
  for ch in result.chars.mitems: ch.material = r.u8
  if result.colouring == cmPerChar:
    r.blockMarker("char colours")
    for ch in result.chars.mitems: ch.colours = r.readColours(result.displayMode)

  if result.tileSystem:
    r.blockMarker("tiles")
    result.tiles.setLen(r.u16.int + 1)
    result.tileWidth = r.u8.int
    result.tileHeight = r.u8.int
    for t in result.tiles.mitems:
      t.cells.setLen(result.tileWidth * result.tileHeight)
      for c in t.cells.mitems: c = r.u16
    if result.colouring == cmPerTile:
      r.blockMarker("tile colours")
      for t in result.tiles.mitems: t.colours = r.readColours(result.displayMode)
    r.blockMarker("tile tags")
    for t in result.tiles.mitems: t.tag = r.u8
    r.blockMarker("tile names")
    for t in result.tiles.mitems:
      while true:
        let c = r.u8
        if c == 0: break
        t.name.add char(c)

  r.blockMarker("map")
  result.mapWidth = r.u16.int
  result.mapHeight = r.u16.int
  result.map.setLen(result.mapWidth * result.mapHeight)
  for c in result.map.mitems: c = r.u16

proc parseCtm*(data: openArray[byte]): Project =
  ## Parses a whole .ctm file. Raises CtmError on anything it can't read.
  var r = Reader(data: @data)
  if data.len < 4 or data[0] != byte('C') or data[1] != byte('T') or data[2] != byte('M'):
    r.fail("not a CharPad project (no CTM signature)")
  r.pos = 3
  let version = r.u8.int
  case version
  of 9: result = parseV9(r)
  else: r.fail("CTM version " & $version & " is not supported yet")
  if r.pos != r.data.len:
    r.fail($(r.data.len - r.pos) & " bytes after the map")

proc readCtm*(path: string): Project =
  let s = readFile(path)
  parseCtm(s.toOpenArrayByte(0, s.high))
