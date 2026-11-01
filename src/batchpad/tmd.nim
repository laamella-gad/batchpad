## Tilemedo (`.tmd`) projects, read and written as CharPad projects. The
## layout is in docs/charpad.md under "Tilemedo".
##
## Tilemedo is a 4 x 4 tile editor for C64 text modes: chars with one colour
## each (per char colouring), tiles and a map of byte-sized numbers, and an
## optional trigger map (a byte per map cell), kept in `Project.triggers`.

import binio, ctm

type Reader = binio.Reader[CtmError]

proc fail(msg: string) {.noreturn.} = raise newException(CtmError, msg)

func isTmd*(data: openArray[byte]): bool =
  ## A Tilemedo project starts with its own length, and has a mode of 0 or 1.
  data.len >= 18 and
    (int(data[0]) or (int(data[1]) shl 8) or (int(data[2]) shl 16) or (int(data[3]) shl 24)) == data.len and
    data[4] <= 1

proc parseTmd*(data: openArray[byte]): Project =
  ## Reads a Tilemedo project. Raises CtmError when it is not one.
  if data.len < 8: fail("not a Tilemedo project: too short")
  var r = Reader(data: @data)
  let length = int(r.u16) or (int(r.u16) shl 16)
  if length != data.len:
    fail("not a Tilemedo project: it says it is " & $length & " bytes, but it is " & $data.len)
  let mode = r.u8
  if mode > 1: fail("unknown Tilemedo mode " & $mode)
  result.displayMode = if mode == 1: dmHiresText else: dmMulticolourText
  result.colouring = cmPerChar
  result.tileSystem = true
  for i in 0 .. 2: result.chipColours[i] = r.u8 and 0x0f
  result.chars.setLen r.u16.int
  for ch in result.chars.mitems:
    for b in ch.data.mitems: b = r.u8
  for ch in result.chars.mitems: ch.colours[0] = r.u8 and 0x0f
  result.tileWidth = r.u8.int
  result.tileHeight = r.u8.int
  result.tiles.setLen r.u16.int
  for t in result.tiles.mitems:
    t.cells.setLen result.tileWidth * result.tileHeight
    for c in t.cells.mitems: c = r.u8
  result.mapWidth = r.u16.int
  result.mapHeight = r.u16.int
  result.map.setLen result.mapWidth * result.mapHeight
  for c in result.map.mitems: c = r.u8
  let left = data.len - r.pos
  if left >= result.map.len and result.map.len > 0:
    result.triggers.setLen result.map.len
    for t in result.triggers.mitems: t = r.u8
  elif left > 0:
    fail("Tilemedo project has " & $left & " bytes after the map, not a trigger map of " & $result.map.len)

proc readTmd*(path: string): Project =
  let data = readFile(path)
  parseTmd(data.toOpenArrayByte(0, data.high))

proc toTmd*(p: Project, leftOut: var seq[string]): seq[byte] =
  ## Formats `p` as a Tilemedo project. What Tilemedo can't hold is left out,
  ## with a line in `leftOut` for each: chars past 256 and tiles past 256 (cells
  ## using them become 0), materials, tile tags and names, the key map and the
  ## flexi-grid. ECM is written as hires text. Per project and per tile colours
  ## become per char colours; a char used in tiles of different colours keeps
  ## the colour of the first. Raises CtmError on bitmap modes, TED colours,
  ## projects without tiles and projects that don't hold together.
  if p.ted: fail("the project has TED colours (CharPad C16); convert them with toC64 first")
  if p.displayMode in {dmHiresBitmap, dmMulticolourBitmap}: fail("Tilemedo has no bitmap modes")
  if p.chars.len == 0: fail("no chars")
  if not p.tileSystem or p.tiles.len == 0:
    fail("Tilemedo needs tiles; this project has a char map")
  if p.tileWidth notin 1 .. 255 or p.tileHeight notin 1 .. 255:
    fail("tile size " & $p.tileWidth & " x " & $p.tileHeight & " is not 1 x 1 to 255 x 255")
  for i, t in p.tiles:
    if t.cells.len != p.tileWidth * p.tileHeight:
      fail("tile " & $i & " has " & $t.cells.len & " cells, not " & $(p.tileWidth * p.tileHeight))
  if p.mapWidth notin 0 .. 65535 or p.mapHeight notin 0 .. 65535 or p.map.len != p.mapWidth * p.mapHeight:
    fail("map has " & $p.map.len & " cells, not " & $p.mapWidth & " x " & $p.mapHeight)

  if p.displayMode == dmEcmText: leftOut.add "extended colour mode (written as hires text)"
  let chars = min(p.chars.len, 256)
  let tiles = min(p.tiles.len, 256)
  if p.chars.len > 256: leftOut.add count(p.chars.len - 256, "chars") & " past 256"
  if p.tiles.len > 256: leftOut.add count(p.tiles.len - 256, "tiles") & " past 256"
  var materials, tags, names = 0
  for ch in p.chars:
    if ch.material != 0: inc materials
  for t in p.tiles:
    if t.tag != 0: inc tags
    if t.name != "": inc names
  if materials > 0: leftOut.add "materials of " & count(materials, "chars")
  if tags > 0: leftOut.add "tags of " & count(tags, "tiles")
  if names > 0: leftOut.add "names of " & count(names, "tiles")
  if p.keyMap != 0: leftOut.add "key map " & $p.keyMap
  if (p.flexiGrid.settings and 0x80) != 0: leftOut.add "the flexi-grid"
  if p.triggers.len != 0 and p.triggers.len != p.map.len:
    leftOut.add "the trigger map (" & $p.triggers.len & " cells, the map has " & $p.map.len & ")"

  var colours = newSeq[uint8](chars)
  case p.colouring
  of cmPerChar:
    for i in 0 ..< chars: colours[i] = p.chars[i].colours[0]
  of cmPerProject:
    for i in 0 ..< chars: colours[i] = p.colours[0]
  of cmPerTile:
    var seen = newSeq[bool](chars)
    var clash = 0
    for t in p.tiles[0 ..< tiles]:
      for c in t.cells:
        if int(c) >= chars: continue
        if not seen[c]:
          seen[c] = true
          colours[c] = t.colours[0]
        elif colours[c] != t.colours[0]: inc clash
    if clash > 0: leftOut.add count(clash, "tile colours") & " of chars used in tiles of another colour"

  var lostCells, lostMap = 0
  var w: Writer
  w.u16 0
  w.u16 0
  w.u8 (if p.displayMode == dmMulticolourText: 0 else: 1)
  for i in 0 .. 2: w.u8 p.chipColours[i] and 0x0f
  w.u16 chars
  for ch in p.chars[0 ..< chars]:
    for b in ch.data: w.u8 b
  for c in colours: w.u8 c and 0x0f
  w.u8 p.tileWidth
  w.u8 p.tileHeight
  w.u16 tiles
  for t in p.tiles[0 ..< tiles]:
    for c in t.cells:
      if int(c) < chars: w.u8 c
      else:
        w.u8 0
        inc lostCells
  w.u16 p.mapWidth
  w.u16 p.mapHeight
  for c in p.map:
    if int(c) < tiles: w.u8 c
    else:
      w.u8 0
      inc lostMap
  if lostCells > 0: leftOut.add count(lostCells, "tile cells") & " using chars past 256 (now char 0)"
  if lostMap > 0: leftOut.add count(lostMap, "map cells") & " using tiles past 256 (now tile 0)"
  if p.triggers.len == p.map.len:
    for t in p.triggers: w.u8 t
  let n = w.data.len
  for i in 0 .. 3: w.data[i] = byte((n shr (8 * i)) and 0xff)
  w.data

proc toTmd*(p: Project): seq[byte] =
  var leftOut: seq[string]
  p.toTmd(leftOut)

proc writeTmd*(path: string, p: Project) =
  let data = p.toTmd
  writeFile(path, data)
