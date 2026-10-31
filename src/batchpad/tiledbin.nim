## Raw binary parts of a Tiled map: tile numbers of a layer, their flip flags
## and the tags of the tiles. Part names are described in docs/cli.md, the
## numbering in docs/tiled.md.

import std/[options, strutils]
import rawbin, tiled

const
  tiledParts* = ["map", "map-lo", "map-hi", "map-flags", "tile-tags"]
    ## `map` can also name a layer: `map:ground`, `map-lo:ground` is written `map:ground-lo`.

proc fail(msg: string) {.noreturn.} = raise newException(BinError, msg)

func splitMapPart*(part: string): tuple[base, layer: string] =
  ## `map:ground-lo` is ("map-lo", "ground"); `map` is ("map", "").
  var prefix = ""
  for p in ["map:", "map-flags:"]:
    if part.startsWith(p): prefix = p
  if prefix != "":
    var name = part[prefix.len .. ^1]
    var suffix = ""
    for s in ["-lo", "-hi"]:
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
  var next = high(int)
  for o in t.tilesets:
    if o.firstGid > ts.firstGid: next = min(next, o.firstGid)
  if id < ts.firstGid or id >= next:
    fail("layer " & layer & " has a cell of another tileset (tile " & $id &
         "); pick it with --set tileset=NAME or draw with one tileset")
  let n = id - ts.firstGid
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
  else:
    fail("a Tiled map has no part " & part)
