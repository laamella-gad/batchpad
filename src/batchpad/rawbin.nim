## Raw binary parts of a project, as CharPad and SpritePad export them.
## Layouts are described in docs/import-export.md, part names in docs/cli.md.

import std/[options, strutils]
import ctm, spd

type
  BinError* = object of ValueError

  CellFormat* = enum
    cf8 = "8", cf12 = "12", cf16 = "16", cfWord = "word"

  SpriteAttribStyle* = enum
    saSpritePad = "spritepad", saSeuck = "seuck", saBlank = "blank"

  Area* = object
    x*, y*, width*, height*: int

  BinOptions* = object
    cells*: CellFormat
    area*: Option[Area]           ## only this part of the map
    spriteAttribs*: SpriteAttribStyle

const
  ctmParts* = ["chars", "char-attribs", "char-attribs-l2", "char-materials",
               "tiles", "tiles-lo", "tiles-hi", "tile-attribs", "tile-attribs-l2",
               "tile-tags", "map", "map-lo", "map-hi"]
  spdParts* = ["sprites", "sprite-attribs", "tiles", "tiles-lo", "tiles-hi",
               "tile-attribs", "tile-tags", "sprite-anims", "tile-anims"]

proc fail(msg: string) {.noreturn.} = raise newException(BinError, msg)

proc cells(values: openArray[uint16], what, part: string, o: BinOptions): seq[byte] =
  ## `part` is the name asked for: `what`, or `what` with `-lo` or `-hi`.
  let split = o.cells in {cf12, cf16}
  if split and part == what:
    fail("--cells " & $o.cells & " writes two files: use " & what & "-lo and " & what & "-hi")
  if not split and part != what:
    fail("--cells " & $o.cells & " writes one file: use " & what & ", not " & part)
  let limit = case o.cells
              of cf8: 0xff
              of cf12: 0xfff
              of cf16, cfWord: 0xffff
  for v in values:
    if int(v) > limit:
      fail(what & ": " & $v & " doesn't fit in " & $o.cells & "-bit cells; use a wider --cells")
  case o.cells
  of cf8:
    for v in values: result.add byte(v)
  of cfWord:
    for v in values:
      result.add byte(v and 0xff)
      result.add byte(v shr 8)
  of cf12, cf16:
    if part.endsWith("-lo"):
      for v in values: result.add byte(v and 0xff)
    elif o.cells == cf16:
      for v in values: result.add byte(v shr 8)
    else:
      # Two cells per byte: the even one in the high nibble.
      for i, v in values:
        let n = byte((v shr 8) and 0x0f)
        if i mod 2 == 0: result.add n shl 4
        else: result[^1] = result[^1] or n

proc mapCells(p: ctm.Project, o: BinOptions): seq[uint16] =
  if o.area.isNone: return p.map
  let a = o.area.get
  if a.width < 1 or a.height < 1 or a.x < 0 or a.y < 0 or
     a.x + a.width > p.mapWidth or a.y + a.height > p.mapHeight:
    fail("--area " & $a.x & "," & $a.y & "," & $a.width & "," & $a.height &
         " is not inside the " & $p.mapWidth & " x " & $p.mapHeight & " map")
  for y in a.y ..< a.y + a.height:
    result.add p.map[y * p.mapWidth + a.x ..< y * p.mapWidth + a.x + a.width]

func isBitmap(p: ctm.Project): bool = p.displayMode in {dmHiresBitmap, dmMulticolourBitmap}

func l1(c: Colours, p: ctm.Project, colouring: ColouringMethod): byte =
  if p.colouring == colouring and p.displayMode != dmHiresBitmap: c[0] and 0x0f else: 0

func l2(c: Colours, p: ctm.Project, colouring: ColouringMethod): byte =
  if p.colouring == colouring and p.isBitmap: (c[1] and 0x0f) or ((c[2] and 0x0f) shl 4) else: 0

proc needTiles(p: ctm.Project) =
  if not p.tileSystem: fail("the project has no tiles")

proc needBitmap(p: ctm.Project, part: string) =
  if not p.isBitmap: fail(part & " is only there in bitmap modes")

proc binPart*(p: ctm.Project, part: string, o = BinOptions()): seq[byte] =
  ## One CharPad part, `part` one of `ctmParts`.
  case part
  of "chars":
    for c in p.chars: result.add c.data
  of "char-attribs":
    for c in p.chars: result.add byte(c.material shl 4) or c.colours.l1(p, cmPerChar)
  of "char-attribs-l2":
    p.needBitmap(part)
    for c in p.chars: result.add c.colours.l2(p, cmPerChar)
  of "char-materials":
    for c in p.chars: result.add c.material
  of "tiles", "tiles-lo", "tiles-hi":
    p.needTiles
    var all: seq[uint16]
    for t in p.tiles: all.add t.cells
    result = cells(all, "tiles", part, o)
  of "tile-attribs":
    p.needTiles
    for t in p.tiles: result.add t.colours.l1(p, cmPerTile)
  of "tile-attribs-l2":
    p.needTiles
    p.needBitmap(part)
    for t in p.tiles: result.add t.colours.l2(p, cmPerTile)
  of "tile-tags":
    p.needTiles
    for t in p.tiles: result.add t.tag
  of "map", "map-lo", "map-hi":
    result = cells(p.mapCells(o), "map", part, o)
  else:
    fail("a CharPad project has no part " & part)

proc anims(anims: seq[Animation], o: BinOptions): seq[byte] =
  ## Four lists: first frames, last frames, timers, attributes.
  if o.cells notin {cf8, cfWord}:
    fail("animation frames are written with --cells 8 or word")
  var frames: seq[uint16]
  for a in anims: frames.add a.first
  result.add cells(frames, "animation frames", "animation frames", o)
  frames.setLen 0
  for a in anims: frames.add a.last
  result.add cells(frames, "animation frames", "animation frames", o)
  for a in anims: result.add a.timer
  for a in anims: result.add a.attributes

proc needTiles(p: SpriteProject) =
  if not p.tileSystem: fail("the project has no tiles")

proc binPart*(p: SpriteProject, part: string, o = BinOptions()): seq[byte] =
  ## One SpritePad part, `part` one of `spdParts`.
  case part
  of "sprites":
    for s in p.sprites:
      result.add s.data
      result.add case o.spriteAttribs
                 of saSpritePad: s.attributes
                 of saSeuck: s.colour or (if s.multicolour: 0x10 else: 0)
                 of saBlank: 0
  of "sprite-attribs":
    for s in p.sprites: result.add s.attributes
  of "tiles", "tiles-lo", "tiles-hi":
    p.needTiles
    var all: seq[uint16]
    for t in p.tiles: all.add t.cells
    result = cells(all, "tiles", part, o)
  of "tile-attribs":
    p.needTiles
    for t in p.tiles: result.add t.attributes and 0x10
  of "tile-tags":
    p.needTiles
    for t in p.tiles: result.add t.tag
  of "sprite-anims":
    result = anims(p.spriteAnims, o)
  of "tile-anims":
    p.needTiles
    result = anims(p.tileAnims, o)
  else:
    fail("a SpritePad project has no part " & part)
