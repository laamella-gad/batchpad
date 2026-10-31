import std/[options, os, strutils, unittest]
import batchpad/[asmout, cout, rawbin, tiled, tiledbin]

const files = currentSourcePath().parentDir / "files" / "tiled"

proc gids(m: TiledMap): seq[(string, int, int, seq[uint32])] =
  for l in m.layers: result.add (l.name, l.width, l.height, l.gids)

let ground = @[byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

suite "Tiled maps":
  test "CSV TMX":
    let m = readTiled(files / "csv.tmx")
    check m.width == 4 and m.height == 3 and m.tileWidth == 8
    check m.layers.len == 2 and m.layers[0].name == "ground" and m.layers[1].name == "sky"
    check m.layers[0].gids == @[1'u32, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    check m.layers[1].gids[5] == 0x80000001'u32
    check m.tilesets.len == 1 and m.tilesets[0].tileCount == 16
    check m.tilesets[0].tiles[0].class == "wall"
    check m.tilesets[0].tiles[0].properties.property("tag") == "3"

  test "base64 and JSON give the same map":
    let m = readTiled(files / "csv.tmx")
    check readTiled(files / "base64.tmx").gids == m.gids
    let j = readTiled(files / "csv.json")
    check j.gids == m.gids
    check j.tilesets[0].tiles == m.tilesets[0].tiles

  test "TMX to JSON to TMX":
    let m = readTiled(files / "csv.tmx")
    let j = parseTiledJson(m.toTiledJson)
    check j.gids == m.gids
    check j.tilesets == m.tilesets
    let back = parseTmx(j.toTmx)
    check back.gids == m.gids
    check back.tilesets == m.tilesets
    check back.width == 4 and back.tileHeight == 8

  test "compressed data is refused with a hint":
    try:
      discard readTiled(files / "compressed.tmx")
      fail()
    except TiledError as e:
      check "CSV" in e.msg and "zlib" in e.msg

  test "infinite maps are flattened to the chunks' box":
    let l = readTiled(files / "infinite.tmx").layers[0]
    check l.originX == 0 and l.originY == 0 and l.width == 6 and l.height == 4
    check l.gids[0 .. 1] == @[1'u32, 2]
    check l.gids[2] == 0
    check l.gids[2 * 6 + 4 .. 2 * 6 + 5] == @[11'u32, 12]
    check l.gids[3 * 6 + 4 .. 3 * 6 + 5] == @[15'u32, 16]

  test "bad input":
    expect TiledError: discard parseTmx("<nothing/>")
    expect TiledError: discard parseTmx("not xml <")
    expect TiledError: discard parseTiledJson("{}")
    expect TiledError:
      discard parseTmx("""<map orientation="isometric" width="1" height="1" tilewidth="8" tileheight="8"/>""")

suite "Tiled parts":
  test "map, layers and flags":
    var m = readTiled(files / "csv.tmx")
    check m.binPart("map") == ground
    check m.binPart("map:ground") == ground
    check m.binPart("map:sky") == @[byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4]
    check m.binPart("map-flags:sky")[5] == 0x80
    check m.binPart("map-flags")[5] == 0
    m.layerName = "sky"
    check m.binPart("map")[11] == 4
    m.emptyTile = 9
    check m.binPart("map")[0] == 9
    expect BinError: discard m.binPart("map:nothing")

  test "area, cells":
    let m = readTiled(files / "csv.tmx")
    check m.binPart("map", BinOptions(area: some(Area(x: 1, y: 1, width: 2, height: 2)))) == @[byte 5, 6, 9, 10]
    expect BinError: discard m.binPart("map", BinOptions(area: some(Area(x: 3, y: 0, width: 2, height: 1))))
    let o = BinOptions(cells: cf16)
    check m.binPart("map-lo", o) == ground
    check m.binPart("map-hi", o) == newSeq[byte](12)
    expect BinError: discard m.binPart("map", o)

  test "tile tags":
    let t = readTiled(files / "csv.tmx").binPart("tile-tags")
    check t.len == 16 and t[0] == 3 and t[4] == 7 and t[1] == 0

  test "tiles of other tilesets":
    var m = readTiled(files / "twotilesets.tmx")
    expect BinError: discard m.binPart("map")
    m.tilesetName = "more"
    expect BinError: discard m.binPart("map")
    m.layers[0].gids = @[5'u32, 8]
    check m.binPart("map") == @[byte 0, 3]
    m.tilesetName = "nope"
    expect BinError: discard m.binPart("map")

  test "assembler and C":
    let m = readTiled(files / "csv.tmx")
    let a = m.toAsm(AsmOptions(parts: @["map", "map:sky", "map-flags:sky", "tile-tags", "tile-names"],
                               source: "csv.tmx"))
    check "map_data" in a and "map_sky_data" in a and "map_sky_flags_data" in a
    check "map_wid = 4" in a and "a Tiled map" in a
    check "\"wall\"" in a
    let c = m.toC(AsmOptions(parts: @["map", "map:sky"])).source
    check "map_data" in c and "map_sky_data" in c
