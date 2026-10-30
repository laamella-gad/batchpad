import std/[strutils, unittest]
import batchpad/[ctm, stats]

proc project(): Project =
  result = Project(version: 9, tileSystem: true, tileWidth: 2, tileHeight: 1,
                   mapWidth: 3, mapHeight: 1, map: @[1'u16, 0, 1])
  result.chars = newSeq[Char](4)
  result.tiles = @[Tile(cells: @[0'u16, 1], name: "floor"), Tile(cells: @[1'u16, 1]),
                   Tile(cells: @[2'u16, 3])]

suite "usage statistics":
  test "chars":
    let s = project().statsText("chars", "level.ctm").splitLines
    check s[0] == "Char usage of level.ctm"
    check s[1] == "4 chars, 0 not used"      # 2 and 3 are only in tile 2, not in the map, but in a tile
    check s[2] == "3 tiles of 2 x 1 chars"
    check s[3] == "map 3 x 1 tiles, 3 cells"
    check "char  in tiles  in map" in s
    # Tile 1 (1,1) twice and tile 0 (0,1) once in the map: char 0 once, char 1 five times.
    check "   0         1       1" in s
    check "   1         3       5" in s
    check "   2         1       0" in s

  test "tiles, names and what is missing":
    var p = project()
    p.map[2] = 7
    p.tiles[0].cells[0] = 9
    let s = p.statsText("tiles").splitLines
    check s[0] == "Tile usage"
    check "tile  in map  name" in s
    check "   0       1  floor" in s
    check "   1       1" in s
    check "   2       0" in s
    check "1 map cells use a tile the project doesn't have" in s
    # Counted in the tiles and again where the map uses the tile.
    check "2 cells use a char the project doesn't have" in p.statsText("chars").splitLines

  test "without tiles and mistakes":
    var p = project()
    p.tileSystem = false
    p.tiles = @[]
    p.map = @[0'u16, 3, 3]
    let s = p.statsText("chars").splitLines
    check "char  in map" in s
    check "   3       2" in s
    expect StatsError: discard p.statsText("tiles")
    expect StatsError: discard p.statsText("sprites")

  test "CRLF":
    check "\r\n" in project().statsText("tiles", crlf = true)
    check "\r" notin project().statsText("tiles")
