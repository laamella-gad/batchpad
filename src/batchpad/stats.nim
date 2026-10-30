## Usage statistics of a CharPad project as plain text: how often each char is
## used in the tiles and the map, and each tile in the map. Described in
## docs/cli.md under stats.

import std/[strutils]
import ctm

type
  StatsError* = object of ValueError

  Usage = object
    inTiles, inMap: seq[int]     ## per char: cells of tiles, and char cells of the map
    tileInMap: seq[int]          ## per tile: map cells
    missingChars, missingTiles: int    ## references to what the project doesn't have

proc count(p: ctm.Project): Usage =
  result.inTiles = newSeq[int](p.chars.len)
  result.inMap = newSeq[int](p.chars.len)
  result.tileInMap = newSeq[int](p.tiles.len)
  proc use(u: var Usage, counts: var seq[int], c: uint16) =
    if int(c) < counts.len: inc counts[int(c)] else: inc u.missingChars
  for t in p.tiles:
    for c in t.cells: result.use(result.inTiles, c)
  for v in p.map:
    if p.tileSystem:
      if int(v) >= p.tiles.len:
        inc result.missingTiles
        continue
      inc result.tileInMap[int(v)]
      for c in p.tiles[int(v)].cells: result.use(result.inMap, c)
    else:
      result.use(result.inMap, v)

proc pad(n: int, width: int): string = ($n).align(width)

proc statsText*(p: ctm.Project, what: string, source = "", crlf = false): string =
  ## `what` is `chars` or `tiles`. Raises StatsError for tiles of a project
  ## without them.
  let u = p.count
  var lines: seq[string]
  let named = if source != "": " of " & source else: ""
  case what
  of "chars":
    var unused = 0
    for i in 0 ..< p.chars.len:
      if u.inTiles[i] == 0 and u.inMap[i] == 0: inc unused
    lines.add "Char usage" & named
    lines.add $p.chars.len & " chars, " & $unused & " not used"
    if p.tileSystem: lines.add $p.tiles.len & " tiles of " & $p.tileWidth & " x " & $p.tileHeight & " chars"
    lines.add "map " & $p.mapWidth & " x " & $p.mapHeight & " " & (if p.tileSystem: "tiles" else: "chars") &
              ", " & $(p.mapWidth * p.mapHeight) & " cells"
    lines.add ""
    lines.add (if p.tileSystem: "char  in tiles  in map" else: "char  in map")
    for i in 0 ..< p.chars.len:
      lines.add pad(i, 4) & (if p.tileSystem: pad(u.inTiles[i], 10) else: "") & pad(u.inMap[i], 8)
    if u.missingChars > 0:
      lines.add ""
      lines.add $u.missingChars & " cells use a char the project doesn't have"
    if u.missingTiles > 0:
      lines.add ""
      lines.add $u.missingTiles & " map cells use a tile the project doesn't have"
  of "tiles":
    if not p.tileSystem: raise newException(StatsError, "the project has no tiles")
    var unused = 0
    var named = false
    for i in 0 ..< p.tiles.len:
      if u.tileInMap[i] == 0: inc unused
      if p.tiles[i].name != "": named = true
    lines.add "Tile usage" & (if source != "": " of " & source else: "")
    lines.add $p.tiles.len & " tiles, " & $unused & " not in the map"
    lines.add "map " & $p.mapWidth & " x " & $p.mapHeight & " tiles, " & $(p.mapWidth * p.mapHeight) & " cells"
    lines.add ""
    lines.add "tile  in map" & (if named: "  name" else: "")
    for i, t in p.tiles:
      lines.add pad(i, 4) & pad(u.tileInMap[i], 8) & (if named and t.name != "": "  " & t.name else: "")
    if u.missingTiles > 0:
      lines.add ""
      lines.add $u.missingTiles & " map cells use a tile the project doesn't have"
  else:
    raise newException(StatsError, "no statistics of " & what & " (chars, tiles)")
  lines.join(if crlf: "\r\n" else: "\n") & (if crlf: "\r\n" else: "\n")
