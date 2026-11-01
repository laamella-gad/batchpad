## Builds a project from raw binary parts: the reverse of rawbin.nim.
## Layouts are described in docs/import-export.md, part names in docs/cli.md.

import std/[bitops, options, strutils, tables]
import binio, ctm, rawbin, spd

type
  Parts* = Table[string, seq[byte]]
    ## Part name (as in `ctmParts`, `spdParts`) to the bytes of its file, load
    ## address already removed.

  ImportOptions* = object
    cells*: CellFormat
    spriteAttribs*: SpriteAttribStyle
    tileWidth*, tileHeight*: int    ## 0 when not given
    mapWidth*, mapHeight*: int      ## 0 when not given
    keepColouring*: bool
      ## the base project's colouring was chosen (`--set colouring`): attributes
      ## don't change it

const
  ctmImportParts* = ["chars", "char-attribs", "char-attribs-l2", "tiles", "tiles-lo",
                     "tiles-hi", "tile-attribs", "tile-attribs-l2", "tile-tags",
                     "map", "map-lo", "map-hi"]
  spdImportParts* = ["sprites", "sprite-attribs", "tiles", "tiles-lo", "tiles-hi",
                     "tile-attribs", "tile-tags"]

proc fail(msg: string) {.noreturn.} = raise newException(BinError, msg)

proc newCtmProject*(): ctm.Project =
  ## What an import starts from: multicolour text, one colour for the project.
  ctm.Project(version: 9, displayMode: dmMulticolourText, colouring: cmPerProject,
              chipColours: [0, 9, 8, 11], colours: [3, 8, 7])

proc newSpdProject*(): SpriteProject =
  SpriteProject(version: 5, colours: [0, 9, 8], spriteOverlay: 1, tileOverlay: 1)

proc divide(size, unit: int, part, what: string): int =
  ## How many `what` of `unit` bytes `size` bytes hold; no half ones.
  if size mod unit != 0:
    fail(part & ": " & $size & " bytes is not a whole number of " & what & " (" & $unit & " bytes each)")
  size div unit

proc sameCount(data: seq[byte], n: int, part, what: string) =
  if data.len != n:
    fail(part & ": " & $data.len & " bytes for " & n.count(what) & ", expected " & $n)

proc readCells(parts: Parts, what: string, o: ImportOptions, unit: int, unitName: string): seq[uint16] =
  ## The cells of `what` (`tiles` or `map`), in the file(s) for `o.cells`;
  ## `unit` cells make one `unitName`, and a partial one is an error.
  let wanted = if o.cells in {cf12, cf16}: @[what & "-lo", what & "-hi"] else: @[what]
  for name in [what, what & "-lo", what & "-hi"]:
    if name in parts and name notin wanted:
      fail("--cells " & $o.cells & " reads " & wanted.join(" and ") & ", not " & name)
  for name in wanted:
    if name notin parts: fail("--cells " & $o.cells & " needs " & name)
  case o.cells
  of cf8:
    for b in parts[what]: result.add uint16(b)
  of cfWord:
    let d = parts[what]
    discard divide(d.len, 2, what, "words")
    for i in 0 ..< d.len div 2: result.add uint16(d[2 * i]) or (uint16(d[2 * i + 1]) shl 8)
  of cf12, cf16:
    let lo = parts[what & "-lo"]
    let hi = parts[what & "-hi"]
    let expected = if o.cells == cf16: lo.len else: (lo.len + 1) div 2
    if hi.len != expected:
      fail(what & "-hi: " & $hi.len & " bytes, expected " & $expected & " for " &
           $lo.len & " cells of " & $o.cells & " bits")
    for i, b in lo:
      let high = if o.cells == cf16: uint16(hi[i])
                 else: uint16((if i mod 2 == 0: hi[i div 2] shr 4 else: hi[i div 2]) and 0x0f)
      result.add uint16(b) or (high shl 8)
  if result.len mod unit != 0:
    fail(what & ": " & $result.len & " cells is not a whole number of " & unitName &
         " (" & $unit & " cells each)")

proc hasCells(parts: Parts, what: string): bool =
  what in parts or what & "-lo" in parts or what & "-hi" in parts

proc checkParts(parts: Parts, allowed: openArray[string], kind: string) =
  for name in parts.keys:
    if name notin allowed:
      fail(kind & " projects can't import the part " & name)

proc importCtm*(parts: Parts, o: ImportOptions, base = newCtmProject()): ctm.Project =
  ## A CharPad project from `parts`. Chars are required. Tiles need
  ## `o.tileWidth` and `o.tileHeight`, a map needs `o.mapWidth` and
  ## `o.mapHeight` (a tile system without a map gets an empty 0 x 0 one).
  ## Char and tile attributes switch the colouring to per char or per tile
  ## (chars win) unless `o.keepColouring`; colours are taken from them as the
  ## display mode says. Raises BinError.
  parts.checkParts(ctmImportParts, "CharPad")
  result = base
  if "chars" notin parts: fail("a CharPad project needs chars")
  let chars = parts["chars"]
  result.chars.setLen divide(chars.len, 8, "chars", "chars")
  if result.chars.len == 0: fail("chars: the file is empty")
  for i, c in result.chars.mpairs:
    for j in 0 .. 7: c.data[j] = chars[8 * i + j]

  let bitmap = result.displayMode in {dmHiresBitmap, dmMulticolourBitmap}
  if "char-attribs-l2" in parts and not bitmap: fail("char-attribs-l2 is only there in bitmap modes")
  if "tile-attribs-l2" in parts and not bitmap: fail("tile-attribs-l2 is only there in bitmap modes")

  # Attributes: `l1` is `MMMMCCCC` for chars and `0000CCCC` for tiles.
  if "char-attribs" in parts:
    let a = parts["char-attribs"]
    a.sameCount(result.chars.len, "char-attribs", "chars")
    for i, c in result.chars.mpairs:
      c.material = a[i] shr 4
      c.colours[0] = a[i] and 0x0f
  if "char-attribs-l2" in parts:
    let a = parts["char-attribs-l2"]
    a.sameCount(result.chars.len, "char-attribs-l2", "chars")
    for i, c in result.chars.mpairs:
      c.colours[1] = a[i] and 0x0f
      c.colours[2] = a[i] shr 4
  if not o.keepColouring and ("char-attribs" in parts or "char-attribs-l2" in parts):
    result.colouring = cmPerChar

  let tileUnit = o.tileWidth * o.tileHeight
  let tilesGiven = parts.hasCells("tiles")
  if not tilesGiven:
    for p in ["tile-attribs", "tile-attribs-l2", "tile-tags"]:
      if p in parts: fail(p & " needs tiles")
    if tileUnit != 0: fail("--tile-size needs tiles")
  else:
    if o.tileWidth < 1 or o.tileHeight < 1: fail("tiles need --tile-size WxH")
    let cells = parts.readCells("tiles", o, tileUnit, "tiles")
    result.tileSystem = true
    result.tileWidth = o.tileWidth
    result.tileHeight = o.tileHeight
    result.tiles.setLen cells.len div tileUnit
    if result.tiles.len == 0: fail("tiles: the file is empty")
    for i, t in result.tiles.mpairs:
      t.cells = cells[i * tileUnit ..< (i + 1) * tileUnit]
    if "tile-attribs" in parts:
      let a = parts["tile-attribs"]
      a.sameCount(result.tiles.len, "tile-attribs", "tiles")
      for i, t in result.tiles.mpairs: t.colours[0] = a[i] and 0x0f
    if "tile-attribs-l2" in parts:
      let a = parts["tile-attribs-l2"]
      a.sameCount(result.tiles.len, "tile-attribs-l2", "tiles")
      for i, t in result.tiles.mpairs:
        t.colours[1] = a[i] and 0x0f
        t.colours[2] = a[i] shr 4
    if "tile-tags" in parts:
      let a = parts["tile-tags"]
      a.sameCount(result.tiles.len, "tile-tags", "tiles")
      for i, t in result.tiles.mpairs: t.tag = a[i]
    if not o.keepColouring and result.colouring == cmPerProject and
       ("tile-attribs" in parts or "tile-attribs-l2" in parts):
      result.colouring = cmPerTile

  if parts.hasCells("map"):
    if o.mapWidth < 1 or o.mapHeight < 1: fail("a map needs --map-size WxH")
    result.map = parts.readCells("map", o, 1, "cells")
    if result.map.len != o.mapWidth * o.mapHeight:
      fail("map: " & $result.map.len & " cells for a " & $o.mapWidth & " x " & $o.mapHeight &
           " map, expected " & $(o.mapWidth * o.mapHeight))
    result.mapWidth = o.mapWidth
    result.mapHeight = o.mapHeight
  elif o.mapWidth != 0 or o.mapHeight != 0:
    fail("--map-size needs a map")

proc seuckToSpritePad*(b: byte): byte =
  ## Bit 4 is multicolour in SEUCK: it becomes bit 7; bits 5-7 are dropped.
  (b and 0x0f) or (if b.testBit(4): 0x80'u8 else: 0)

proc importSpd*(parts: Parts, o: ImportOptions, base = newSpdProject()): SpriteProject =
  ## A SpritePad project from `parts`. Sprites are required. The 64th byte of
  ## each sprite is read as `o.spriteAttribs` says; `sprite-attribs`, when
  ## given, replaces it. Tiles need `o.tileWidth` and `o.tileHeight`.
  ## Raises BinError.
  parts.checkParts(spdImportParts, "SpritePad")
  result = base
  if "sprites" notin parts: fail("a SpritePad project needs sprites")
  let sprites = parts["sprites"]
  result.sprites.setLen divide(sprites.len, 64, "sprites", "sprites")
  if result.sprites.len == 0: fail("sprites: the file is empty")
  for i, s in result.sprites.mpairs:
    for j in 0 .. 62: s.data[j] = sprites[64 * i + j]
    let last = sprites[64 * i + 63]
    s.attributes = case o.spriteAttribs
                   of saSpritePad: last
                   of saSeuck: seuckToSpritePad(last)
                   of saBlank: 0x8c
  if "sprite-attribs" in parts:
    let a = parts["sprite-attribs"]
    a.sameCount(result.sprites.len, "sprite-attribs", "sprites")
    for i, s in result.sprites.mpairs: s.attributes = a[i]
  # One sprite animation is always there in V1; later versions don't need it.

  let tileUnit = o.tileWidth * o.tileHeight
  if not parts.hasCells("tiles"):
    for p in ["tile-attribs", "tile-tags"]:
      if p in parts: fail(p & " needs tiles")
    if tileUnit != 0 or o.tileWidth != 0 or o.tileHeight != 0: fail("--tile-size needs tiles")
  else:
    if o.tileWidth < 1 or o.tileHeight < 1: fail("tiles need --tile-size WxH")
    let cells = parts.readCells("tiles", o, tileUnit, "tiles")
    result.tileSystem = true
    result.tileWidth = o.tileWidth
    result.tileHeight = o.tileHeight
    result.tiles.setLen cells.len div tileUnit
    if result.tiles.len == 0: fail("tiles: the file is empty")
    for i, t in result.tiles.mpairs:
      t.cells = cells[i * tileUnit ..< (i + 1) * tileUnit]
    if "tile-attribs" in parts:
      let a = parts["tile-attribs"]
      a.sameCount(result.tiles.len, "tile-attribs", "tiles")
      for i, t in result.tiles.mpairs: t.attributes = a[i] and 0x10
    if "tile-tags" in parts:
      let a = parts["tile-tags"]
      a.sameCount(result.tiles.len, "tile-tags", "tiles")
      for i, t in result.tiles.mpairs: t.tag = a[i]

proc stripLoadAddress*(data: seq[byte], mode: string, unit: int): (seq[byte], Option[int]) =
  ## `mode` is `skip` (always), `detect` (when `data.len` is 2 mod `unit`,
  ## where `unit` is 0 for parts that have no size to go by) or `none`. Gives
  ## the data without the address, and the address found.
  let skip = case mode
             of "skip": true
             of "detect": unit > 0 and data.len mod unit == 2
             else: false
  if not skip: return (data, none(int))
  if data.len < 2: fail("no room for a load address in " & $data.len & " bytes")
  (data[2 .. ^1], some(int(data[0]) or (int(data[1]) shl 8)))
