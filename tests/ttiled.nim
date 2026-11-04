import std/[options, os, strutils, unittest]
import batchpad/[asmout, ctm, cout, image, preview, rawbin, tiled, tiledbin]

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

  test "external tileset":
    let m = readTiled(files / "external.tmx")
    let inline = readTiled(files / "csv.tmx")
    check m.tilesets[0].source == "tiles.tsx" and m.tilesets[0].firstGid == 1
    check m.tilesets[0].tileCount == 16 and m.tilesets[0].tileWidth == 8
    check m.tilesets[0].tiles == inline.tilesets[0].tiles
    check m.binPart("tile-tags") == inline.binPart("tile-tags")
    check parseTmx(m.toTmx).tilesets[0].source == "tiles.tsx"
    var broken = parseTmx("""<map width="1" height="1" tilewidth="8" tileheight="8"><tileset firstgid="1" source="nope.tsx"/></map>""")
    expect TiledError: broken.resolveTilesets(files)

  test "zlib and gzip layers":
    let m = readTiled(files / "csv.tmx")
    check readTiled(files / "zlib.tmx").gids == m.gids
    check readTiled(files / "gzip.tmx").gids == m.gids

  test "Tiled 1.12.2 map with a repeated external tileset":
    let dir = files / "tiled-1.12.2"
    var m = readTiled(dir / "aaaaaa.tmx")
    var exported = readTiled(dir / "tiled-export.tmj")
    check m.tilesets.len == 2 and exported.tilesets.len == 1
    check m.binPart("map:ground") == exported.binPart("map:ground")
    check m.binPart("map:details") == exported.binPart("map:details")
    check m.binPart("map-flags:details") == exported.binPart("map-flags:details")
    check m.binPart("map:ground")[0] == 0
    check m.binPart("map:details")[155 .. 158] == @[byte 7, 7, 7, 7]
    check m.binPart("map-flags:details")[155 .. 158] == @[byte 0, 0xc0, 0x80, 0xc0]
    m.objectFields = @["hp"]
    exported.objectFields = @["hp"]
    check m.objectClasses == @["enemy"]
    check m.binPart("objects") == @[byte 0, 4, 0, 6, 0, 8, 6, 3]
    check m.binPart("objects") == exported.binPart("objects")
    let base = readCtm(currentSourcePath().parentDir / "files" / "ctm9" / "mctext_pertile.ctm")
    var leftOut: seq[string]
    check m.withMap(base, leftOut).map == exported.withMap(base, leftOut).map
    for f in ["tiled-zlib.tmx", "tiled-gzip.tmx"]:
      var compressed = readTiled(dir / f)
      compressed.objectFields = @["hp"]
      for part in ["map:ground", "map:details", "map-flags:details", "objects"]:
        check compressed.binPart(part) == exported.binPart(part)

  test "repeated tilesets do not hide a different tileset":
    var m = readTiled(files / "tiled-1.12.2" / "aaaaaa.tmx")
    m.tilesets[1].source = "./" & m.tilesets[1].source
    m.tilesets.add Tileset(firstGid: 3, name: "other")
    m.layers[0].gids = @[1'u32, 2, 5, 6]
    check m.binPart("map") == @[byte 0, 1, 0, 1]
    m.layers[0].gids[1] = 3
    expect BinError: discard m.binPart("map")

  test "zstd data is refused with a hint":
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

  test "a layer as the map of a CharPad project":
    let base = readCtm(currentSourcePath().parentDir / "files" / "ctm9" / "mctext_perchar_big.ctm")
    var m = readTiled(files / "csv.tmx")
    var leftOut: seq[string]
    let p = m.withMap(base, leftOut)
    check p.mapWidth == 4 and p.mapHeight == 3 and leftOut.len == 0
    check p.map == @[0'u16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    check p.chars == base.chars and p.tiles == base.tiles
    # the flipped cell of sky is left out
    m.layerName = "sky"
    discard m.withMap(base, leftOut)
    check leftOut == @["the flip flags of 1 cell"]
    # char numbers without tiles; too few is an error
    var small = base
    small.tileSystem = false
    small.tiles = @[]
    small.chars.setLen 11
    m.layerName = ""
    expect BinError: discard m.withMap(small, leftOut)
    small.chars.setLen 12
    check m.withMap(small, leftOut).map == p.map

  test "a CharPad map as a Tiled map":
    let p = readCtm(currentSourcePath().parentDir / "files" / "ctm9" / "mctext_perchar_big.ctm")
    let sheet = p.tileSheet
    check sheet.count == 261 and sheet.columns == 8
    check sheet.image.width == 8 * 24 and sheet.image.height == 33 * 8
    check sheet.image == p.previewCtm("tiles")
    var leftOut: seq[string]
    let m = p.fromProject("big.png", sheet.count, sheet.columns, sheet.image.width,
                          sheet.image.height, leftOut)
    check leftOut.len == 0
    check m.tileWidth == 24 and m.tileHeight == 8 and m.width == 21 and m.height == 13
    check m.tilesets[0].image == "big.png" and m.tilesets[0].tileCount == 261
    check m.binPart("map", BinOptions(cells: cfWord)) == p.binPart("map", BinOptions(cells: cfWord))
    # and back, through TMX
    check parseTmx(m.toTmx).withMap(p, leftOut).map == p.map
    # without tiles: a tile per char; ECM numbers past the set count too
    var e = ctm.Project(displayMode: dmEcmText, colouring: cmPerProject,
                        chars: newSeq[Char](3), mapWidth: 2, mapHeight: 1, map: @[1'u16, 66],
                        cellColours: @[1'u8, 2])
    let es = e.tileSheet(4)
    check es.count == 67 and es.columns == 4 and es.image.height == 17 * 8
    let em = e.fromProject("e.png", es.count, es.columns, es.image.width, es.image.height, leftOut)
    check em.tileWidth == 8 and em.layers[0].gids == @[2'u32, 67]
    check leftOut.len == 1

  test "objects":
    var m = readTiled(files / "objects.tmx")
    check m.objectClasses == @["alien", "bat", "key"]
    check m.binPart("objects") == @[byte 1, 2, 0, 1, 0, 1, 1,
                                         0, 3, 0, 0, 0, 2, 2,
                                         255, 0, 0, 2, 0, 0, 0]
    check m.binPart("objects:items") == @[byte 2, 1, 0, 2, 0, 1, 1]
    m.objectPixels = true
    m.objectFields = @["hp", "boss"]
    check m.binPart("objects") == @[byte 1, 16, 0, 8, 0, 8, 8, 3, 1,
                                         0, 25, 0, 0, 0, 16, 16, 10, 0,
                                         255, 0, 0, 16, 0, 0, 0, 0, 0]
    expect BinError: discard m.binPart("objects:nope")
    expect BinError: discard readTiled(files / "csv.tmx").binPart("objects")
    m.objectFields = @["first"]
    m.layers[2].objects[0].properties.add Property(name: "first", kind: "int", value: "300")
    expect BinError: discard m.binPart("objects")
    m.objectFields = @["hp"]
    let a = m.toAsm(AsmOptions(parts: @["objects", "objects:items"]))
    check "objects_data" in a and "objects_items_data" in a
    check "object_size = 8" in a and "object_class_key = 2" in a

  test "object templates and maps without tile layers":
    for f in ["templates.tmx", "templates.json"]:
      var m = readTiled(files / f)
      let o = m.layers[0].objects
      check o[0].name == "enemy" and o[0].class == "bat" and o[0].gid == 2
      check o[0].width == 16 and o[0].height == 8
      check o[0].properties.property("hp") == "4" and o[0].properties.property("speed") == "2"
      check o[1].class == "alien" and o[1].width == 8 and o[1].height == 8
      check o[1].properties.property("hp") == "9" and o[1].properties.property("speed") == "2"
      check o[2].class == "key" and o[2].templ == ""
      m.objectFields = @["hp"]
      check m.binPart("objects") == @[byte 1, 1, 0, 2, 0, 2, 1, 4,
                                           0, 2, 0, 1, 0, 1, 1, 9,
                                           2, 0, 0, 0, 0, 1, 1, 0]
      let a = m.toAsm(AsmOptions())
      check "objects_data" in a and "map_wid = 4" in a
      # convert keeps the template reference and explicit overrides
      for xml in [true, false]:
        var back = if xml: parseTmx(m.toTmx) else: parseTiledJson(m.toTiledJson)
        check back.layers[0].objects[0].templ == o[0].templ and back.layers[0].objects[0].gid == 0
        back.resolveTemplates(files)
        check back.layers[0].objects[0].gid == 2
        check back.layers[0].objects[1].class == "alien" and back.layers[0].objects[1].width == 8
        check back.layers[0].objects[1].properties.property("hp") == "9"
    var m = parseTmx(readFile(files / "templates.tmx").replace("enemy.tx", "nope.tx"))
    expect TiledError: m.resolveTemplates(files)

  test "Tiled-saved tile templates retain inheritance through conversion":
    let dir = files / "tiled-1.12.2" / "template-map"
    var m = readTiled(dir / "aaaaaa.tmx")
    let original = m.objectLayer.objects
    let reference = readTiled(dir / "tiled-reference.tmj").objectLayer.objects
    check original.len == 3 and reference.len == 3
    for i in 1 .. 2:
      check original[i].name == reference[i].name
      check original[i].class == reference[i].class
      check original[i].gid == reference[i].gid and original[i].gid == 12
      check original[i].width == reference[i].width and original[i].height == reference[i].height
      check original[i].properties == reference[i].properties
    m.objectFields = @["hp"]
    check m.binPart("objects") == @[byte 0, 4, 0, 6, 0, 8, 6, 3,
                                         0, 2, 0, 3, 0, 1, 1, 3,
                                         0, 10, 0, 2, 0, 1, 1, 5]
    for xml in [true, false]:
      let serialized = (if xml: m.toTmx else: m.toTiledJson).replace("enemy.tx", "enemy-updated.tx")
      var converted = if xml: parseTmx(serialized) else: parseTiledJson(serialized)
      converted.resolveTemplates(dir)
      let objects = converted.objectLayer.objects
      check objects[1].properties.property("hp") == "9"
      check objects[2].properties.property("hp") == "5"
      check objects[1].gid == 11 and objects[1].class == "boss" and objects[1].name == "changed"
      check objects[1].width == 32 and objects[1].height == 24

    let text = readFile(dir / "aaaaaa.tmx").replace("id=\"3\" template=",
        "id=\"3\" name=\"custom\" class=\"guard\" gid=\"6\" width=\"8\" height=\"4\" template=")
        .replace("value=\"5\"", "value=\"3\"")
    var overridden = parseTmx(text)
    overridden.resolveTemplates(dir)
    for xml in [true, false]:
      let serialized = (if xml: overridden.toTmx else: overridden.toTiledJson).replace("enemy.tx", "enemy-updated.tx")
      var converted = if xml: parseTmx(serialized) else: parseTiledJson(serialized)
      converted.resolveTemplates(dir)
      let obj = converted.objectLayer.objects[1]
      check obj.name == "custom" and obj.class == "guard" and obj.gid == 6
      check obj.width == 8 and obj.height == 4 and obj.properties.property("hp") == "9"
      check converted.objectLayer.objects[2].properties.property("hp") == "3"

  test "template tile GIDs use the matching map tileset":
    let dir = files / "tiled-1.12.2" / "template-second-tileset"
    for path in ["second-tileset.tmx", "second-tileset.json"]:
      var m = readTiled(dir / path)
      let objects = m.objectLayer.objects
      check objects[0].gid == 0x8000001c'u32
      check objects[1].gid == 0x80000006'u32
      check objects[0].properties.property("hp") == "3"
      check objects[1].properties.property("hp") == "9"
      for xml in [true, false]:
        var converted = if xml: parseTmx(m.toTmx) else: parseTiledJson(m.toTiledJson)
        converted.resolveTilesets(dir)
        converted.resolveTemplates(dir)
        check converted.objectLayer.objects[0].gid == 0x8000001c'u32
        check converted.objectLayer.objects[1].gid == 0x80000006'u32
        check converted.objectLayer.objects[1].class == "override"
        check converted.objectLayer.objects[1].width == 8
        check converted.objectLayer.objects[1].properties.property("hp") == "9"

    var noMatch = parseTmx(readFile(dir / "second-tileset.tmx"))
    noMatch.tilesets[1].source = "tilesets/other.tsx"
    expect TiledError: noMatch.resolveTemplates(dir)

  test "Tiled-saved template uses second map tileset":
    let root = currentSourcePath().parentDir.parentDir
    let m = readTiled(root / "software" / "Tiled" / "two-tilesets.tmx")
    check m.objectLayer.objects.len == 1
    check m.objectLayer.objects[0].gid == 28

  test "assembler and C":
    let m = readTiled(files / "csv.tmx")
    let a = m.toAsm(AsmOptions(parts: @["map", "map:sky", "map-flags:sky", "tile-tags", "tile-names"],
                               source: "csv.tmx"))
    check "map_data" in a and "map_sky_data" in a and "map_sky_flags_data" in a
    check "map_wid = 4" in a and "a Tiled map" in a
    check "\"wall\"" in a
    let c = m.toC(AsmOptions(parts: @["map", "map:sky"])).source
    check "map_data" in c and "map_sky_data" in c
