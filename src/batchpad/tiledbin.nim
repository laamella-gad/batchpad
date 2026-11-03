## Raw binary parts of a Tiled map: tile numbers of a layer, their flip flags
## and the tags of the tiles. Part names are described in docs/cli.md, the
## numbering in docs/tiled.md.

import std/[options, os, strutils]
import ctm, rawbin, tiled

const
  tiledParts* = ["map", "map-lo", "map-hi", "map-flags", "tile-tags", "objects"]
    ## `map` can also name a layer: `map:ground`, `map-lo:ground` is written `map:ground-lo`;
    ## `objects` an object layer: `objects:enemies`.
  noClass* = 0xff                  ## the class number of an object without a class

proc fail(msg: string) {.noreturn.} = raise newException(BinError, msg)

func splitMapPart*(part: string): tuple[base, layer: string] =
  ## `map:ground-lo` is ("map-lo", "ground"); `map` is ("map", "").
  var prefix = ""
  for p in ["map:", "map-flags:", "objects:"]:
    if part.startsWith(p): prefix = p
  if prefix != "":
    var name = part[prefix.len .. ^1]
    var suffix = ""
    for s in ["-lo", "-hi"]:
      if prefix == "objects:": break
      if name.endsWith(s) and name.len > s.len:
        suffix = s
        name = name[0 ..< name.len - s.len]
        break
    (base: prefix[0 ..< prefix.high] & suffix, layer: name)
  else:
    (base: part, layer: "")

proc tileNumber(t: TiledMap, set: int, gid: uint32, layer: string): uint16 =
  if gid == 0: return uint16(t.emptyTile)
  let id = int(gid and idMask)
  let ts = t.tilesets[set]
  var owner = -1
  for i, o in t.tilesets:
    if o.firstGid <= id and (owner < 0 or o.firstGid > t.tilesets[owner].firstGid):
      owner = i
  if owner < 0 or (owner != set and
      (ts.source == "" or t.tilesets[owner].source == "" or
       (ts.source != t.tilesets[owner].source and
        normalizedPath(ts.source) != normalizedPath(t.tilesets[owner].source)))):
    fail("layer " & layer & " has a cell of another tileset (tile " & $id &
         "); pick it with --set tileset=NAME or draw with one tileset")
  let n = id - t.tilesets[owner].firstGid
  if n > 0xffff: fail("tile number " & $n & " doesn't fit in 16 bits")
  uint16(n)

proc layerCells(t: TiledMap, layer: Layer, o: BinOptions): seq[uint32] =
  ## The gids of `o.area`, or of the whole layer.
  let a = checkedArea(layer.width, layer.height, o)
  if o.area.isNone: return layer.gids
  for y in a.y ..< a.y + a.height:
    result.add layer.gids[y * layer.width + a.x ..< y * layer.width + a.x + a.width]

func hasLayer(t: TiledMap, name: string): bool =
  for l in t.layers:
    if l.kind == lkTiles and l.name == name: return true

func objectRecordSize*(t: TiledMap): int = 7 + t.objectFields.len
  ## class, x and y (words), width and height, then a byte per field

proc objectRecords*(t: TiledMap, name: string): seq[byte] =
  ## The objects of a layer, a record each: class number ($ff: none), x and y
  ## (little-endian words), width, height, then one byte per `objectFields`.
  let layer = try: t.objectLayer(name)
              except TiledError as e: fail(e.msg)
  let classes = t.objectClasses
  if classes.len > noClass: fail("the map has " & $classes.len & " object classes; at most 255 fit in a byte")
  let (uw, uh) = if t.objectPixels: (1.0, 1.0) else: (float(t.tileWidth), float(t.tileHeight))
  if uw <= 0 or uh <= 0: fail("the map has no tile size, so object positions can't be in tiles")
  for o in layer.objects:
    let what = "object " & (if o.name != "": o.name & " (id " & $o.id & ")" else: $o.id)
    proc unit(v, u: float, field: string, limit: int): int =
      result = if t.objectPixels: int(v + 0.5) else: int(v / u)   # pixels round, tiles floor
      if v < 0: fail(what & ": " & field & " is negative (" & $v & ")")
      if result > limit: fail(what & ": " & field & " " & $result & " doesn't fit in " &
                              (if limit == 255: "a byte" else: "a word"))
    result.add byte(if o.class == "": noClass else: classes.find(o.class))
    for (v, u, f) in [(o.x, uw, "x"), (o.y, uh, "y")]:
      let n = unit(v, u, f, 0xffff)
      result.add [byte(n and 0xff), byte(n shr 8)]
    result.add byte(unit(o.width, uw, "width", 255))
    result.add byte(unit(o.height, uh, "height", 255))
    for f in t.objectFields:
      var v = ""
      var kind = ""
      for p in o.properties:
        if p.name == f: (v, kind) = (p.value, p.kind)
      if v == "": result.add 0; continue
      let n = if kind == "bool": (if v == "true": 1 else: 0)
              else: (try: parseInt(v) except ValueError: fail(what & ": " & f & " is not an integer: " & v))
      if n notin -128 .. 255: fail(what & ": " & f & " " & $n & " doesn't fit in a byte")
      result.add byte(n and 0xff)

proc binPart*(t: TiledMap, part: string, o = BinOptions()): seq[byte] =
  ## One part of a Tiled map, `part` one of `tiledParts` or `map:LAYER`.
  var (base, name) = splitMapPart(part)
  if part.startsWith("map:") and not t.hasLayer(name) and t.hasLayer(part[4 .. ^1]):
    (base, name) = ("map", part[4 .. ^1])   # a layer that really is called x-lo
  case base
  of "map", "map-lo", "map-hi":
    let layer = try: t.tileLayer(name)
                except TiledError as e: fail(e.msg)
    let set = try: t.tilesetIndex
              except TiledError as e: fail(e.msg)
    var nums: seq[uint16]
    for g in t.layerCells(layer, o): nums.add t.tileNumber(set, g, layer.name)
    result = cells(nums, "map", base, o)
  of "map-flags":
    let layer = try: t.tileLayer(name)
                except TiledError as e: fail(e.msg)
    for g in t.layerCells(layer, o):
      result.add byte((if (g and flipH) != 0: 0x80 else: 0) or
                      (if (g and flipV) != 0: 0x40 else: 0) or
                      (if (g and flipD) != 0: 0x20 else: 0))
  of "tile-tags":
    let set = try: t.tilesetIndex
              except TiledError as e: fail(e.msg)
    let ts = t.tilesets[set]
    var count = ts.tileCount
    for k in ts.tiles: count = max(count, k.id + 1)
    result = newSeq[byte](count)
    for k in ts.tiles:
      let v = k.properties.property("tag")
      if v == "": continue
      let n = try: parseInt(v) except ValueError: fail("tile " & $k.id & ": tag is not a number: " & v)
      if n notin 0 .. 255: fail("tile " & $k.id & ": tag " & $n & " doesn't fit in a byte")
      result[k.id] = byte(n)
  of "objects":
    result = t.objectRecords(name)
  else:
    fail("a Tiled map has no part " & part)

proc withMap*(t: TiledMap, base: ctm.Project, leftOut: var seq[string]): ctm.Project =
  ## `base` with its map replaced by the tile layer of `t` (`--set layer=NAME`):
  ## tile numbers when `base` uses tiles, char numbers when not. Flip flags
  ## don't fit a CharPad map and are left out.
  let layer = try: t.tileLayer
              except TiledError as e: fail(e.msg)
  let set = try: t.tilesetIndex
            except TiledError as e: fail(e.msg)
  result = base
  let (what, count) = if base.tileSystem: ("tile", base.tiles.len) else: ("char", base.chars.len)
  result.map.setLen 0
  var flipped = 0
  for g in layer.gids:
    let n = t.tileNumber(set, g, layer.name)
    if int(n) >= count:
      fail("layer " & layer.name & " uses " & what & " " & $n & ", the base project has " &
           $count & " " & what & "s")
    if (g and (flipH or flipV or flipD)) != 0: inc flipped
    result.map.add n
  result.mapWidth = layer.width
  result.mapHeight = layer.height
  if flipped > 0: leftOut.add "the flip flags of " & $flipped & (if flipped == 1: " cell" else: " cells")
  if base.triggers.len > 0:
    result.triggers.setLen 0
    leftOut.add "the base project's trigger map"
  if base.cellColours.len > 0:
    result.cellColours.setLen 0
    leftOut.add "the base project's cell colours"

proc fromProject*(p: ctm.Project, image: string, count, columns, imageWidth, imageHeight: int,
                  leftOut: var seq[string]): TiledMap =
  ## A Tiled map of the map of `p`: one tile layer `map` and one tileset whose
  ## image (`image`, `count` tiles in `columns` columns) shows the tiles, or the
  ## chars without tiles; `preview.tileSheet` draws it. Tile numbers stay as
  ## they are in CharPad, so `bin` gives the same map bytes from either.
  if p.mapWidth == 0 or p.mapHeight == 0: fail("the project has no map")
  let (tw, th) = if p.tileSystem: (p.tileWidth * 8, p.tileHeight * 8) else: (8, 8)
  result = TiledMap(width: p.mapWidth, height: p.mapHeight, tileWidth: tw, tileHeight: th)
  result.tilesets.add Tileset(firstGid: 1, name: (if p.tileSystem: "tiles" else: "chars"),
                              image: image, tileWidth: tw, tileHeight: th, tileCount: count,
                              columns: columns, imageWidth: imageWidth,
                              imageHeight: imageHeight)
  var layer = Layer(name: "map", kind: lkTiles, width: p.mapWidth, height: p.mapHeight)
  for v in p.map: layer.gids.add uint32(v) + 1
  result.layers.add layer
  if p.cellColours.len > 0:
    leftOut.add "the colour of each map cell (the tileset shows every char in one colour)"
  if p.triggers.len > 0: leftOut.add "the trigger map"
