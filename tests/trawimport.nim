import std/[options, sequtils, tables, unittest]
import batchpad/[ctm, rawbin, rawimport, spd]

proc charProject(mode = dmMulticolourText, colouring = cmPerChar): ctm.Project =
  result = ctm.Project(version: 9, displayMode: mode, colouring: colouring,
                       tileSystem: true, tileWidth: 2, tileHeight: 1,
                       mapWidth: 3, mapHeight: 2)
  for i in 0..2:
    var c = Char(material: uint8(i + 1), colours: [uint8(8 + i), uint8(2 + i), uint8(5 + i)])
    for j in 0..7: c.data[j] = uint8(16 * i + j)
    result.chars.add c
  result.tiles = @[Tile(cells: @[0'u16, 1], colours: [9'u8, 3, 4], tag: 7),
                   Tile(cells: @[2'u16, 0x123], colours: [10'u8, 5, 6], tag: 8),
                   Tile(cells: @[0x345'u16, 2], colours: [11'u8, 7, 1], tag: 9)]
  result.map = @[0'u16, 1, 2, 2, 1, 0]

proc exported(p: ctm.Project, names: openArray[string], o = BinOptions()): Parts =
  for n in names: result[n] = p.binPart(n, o)

proc spriteProject(): SpriteProject =
  result = SpriteProject(version: 5, colours: [1, 2, 3], tileSystem: true,
                         tileWidth: 2, tileHeight: 2, spriteOverlay: 1, tileOverlay: 1)
  for i in 0..2:
    var s = Sprite(attributes: uint8(0x80 + 4 + i))
    for j in 0..62: s.data[j] = uint8(i * 10 + j)
    result.sprites.add s
  result.tiles = @[SpriteTile(cells: @[0'u16, 1, 2, 0], attributes: 0x10, tag: 5)]

suite "CharPad import":
  test "round trip of everything with 16-bit cells":
    let p = charProject()
    let o = BinOptions(cells: cf16)
    let q = importCtm(p.exported(["chars", "char-attribs", "tiles-lo", "tiles-hi", "tile-tags",
                                  "map-lo", "map-hi"], o),
                      ImportOptions(cells: cf16, tileWidth: 2, tileHeight: 1, mapWidth: 3, mapHeight: 2))
    check q.chars == p.chars.mapIt(Char(data: it.data, material: it.material,
                                         colours: [it.colours[0], 0, 0]))
    check q.colouring == cmPerChar
    check q.tileSystem and q.tileWidth == 2 and q.tileHeight == 1
    check q.tiles.mapIt(it.cells) == p.tiles.mapIt(it.cells)
    check q.tiles.mapIt(it.tag) == @[7'u8, 8, 9]
    check q.map == p.map and q.mapWidth == 3 and q.mapHeight == 2

  test "cell widths":
    let p = charProject()
    for cells in [cf12, cf16, cfWord]:
      let o = BinOptions(cells: cells)
      let names = if cells in {cf12, cf16}: ["tiles-lo", "tiles-hi", "map-lo", "map-hi"]
                  else: ["tiles", "tiles", "map", "map"]
      let q = importCtm(p.exported(@["chars"] & @names, o),
                        ImportOptions(cells: cells, tileWidth: 2, tileHeight: 1, mapWidth: 3, mapHeight: 2))
      check q.tiles.mapIt(it.cells) == p.tiles.mapIt(it.cells)
      check q.map == p.map
    # 12 bits with an odd cell count: the last nibble is padding.
    var parts = p.exported(["chars"])
    parts["map-lo"] = @[byte 1, 2, 3]
    parts["map-hi"] = @[byte 0x12, 0x30]
    let q = importCtm(parts, ImportOptions(cells: cf12, mapWidth: 3, mapHeight: 1))
    check q.map == @[0x101'u16, 0x202, 0x303]

  test "8-bit cells":
    var parts: Parts
    parts["chars"] = newSeq[byte](16)
    parts["map"] = @[byte 0, 1, 1, 0]
    let q = importCtm(parts, ImportOptions(mapWidth: 2, mapHeight: 2))
    check q.chars.len == 2 and not q.tileSystem and q.map == @[0'u16, 1, 1, 0]
    check q.colouring == cmPerProject

  test "bitmap attributes":
    var p = charProject(mode = dmMulticolourBitmap, colouring = cmPerTile)
    p.tiles[1].cells[1] = 1
    p.tiles[2].cells[0] = 1
    let q = importCtm(p.exported(["chars", "tiles", "tile-attribs", "tile-attribs-l2"], BinOptions()),
                      ImportOptions(tileWidth: 2, tileHeight: 1),
                      ctm.Project(version: 9, displayMode: dmMulticolourBitmap))
    check q.colouring == cmPerTile
    check q.tiles[1].colours == [10'u8, 5, 6]
    check q.tiles[2].colours == [11'u8, 7, 1]

  test "char attributes: material and colour, L2 nibbles":
    var parts: Parts
    parts["chars"] = newSeq[byte](16)
    parts["char-attribs"] = @[byte 0x3a, 0x1f]
    parts["char-attribs-l2"] = @[byte 0x52, 0x00]
    let base = ctm.Project(version: 9, displayMode: dmHiresBitmap)
    let q = importCtm(parts, ImportOptions(), base)
    check q.chars[0].material == 3 and q.chars[0].colours == [10'u8, 2, 5]
    check q.chars[1].material == 1 and q.chars[1].colours[0] == 15
    check q.colouring == cmPerChar
    # keepColouring leaves the colouring alone
    check importCtm(parts, ImportOptions(keepColouring: true), base).colouring == cmPerProject

  test "errors":
    var parts: Parts
    expect BinError: discard importCtm(parts, ImportOptions())            # no chars
    parts["chars"] = newSeq[byte](12)
    expect BinError: discard importCtm(parts, ImportOptions())            # half a char
    parts["chars"] = newSeq[byte](16)
    parts["char-attribs"] = @[byte 1]
    expect BinError: discard importCtm(parts, ImportOptions())            # one per char
    parts.del "char-attribs"
    parts["char-attribs-l2"] = @[byte 1, 2]
    expect BinError: discard importCtm(parts, ImportOptions())            # not a bitmap mode
    parts.del "char-attribs-l2"
    parts["tiles"] = @[byte 0, 1, 1]
    expect BinError: discard importCtm(parts, ImportOptions())            # no --tile-size
    expect BinError: discard importCtm(parts, ImportOptions(tileWidth: 2, tileHeight: 1))
    parts["tiles"] = @[byte 0, 1]
    parts["tile-attribs"] = @[byte 1, 2]
    expect BinError: discard importCtm(parts, ImportOptions(tileWidth: 2, tileHeight: 1))
    parts.del "tile-attribs"
    parts["map"] = @[byte 0, 0, 0]
    expect BinError: discard importCtm(parts, ImportOptions(tileWidth: 2, tileHeight: 1))   # no map size
    expect BinError: discard importCtm(parts, ImportOptions(tileWidth: 2, tileHeight: 1, mapWidth: 2, mapHeight: 2))
    expect BinError: discard importCtm(parts, ImportOptions(cells: cf16, tileWidth: 2, tileHeight: 1, mapWidth: 3, mapHeight: 1))
    parts["colour-map"] = @[byte 0]
    expect BinError: discard importCtm(parts, ImportOptions(tileWidth: 2, tileHeight: 1, mapWidth: 3, mapHeight: 1))

suite "SpritePad import":
  test "round trip":
    let p = spriteProject()
    var parts: Parts
    for n in ["sprites", "tiles", "tile-attribs", "tile-tags"]: parts[n] = p.binPart(n)
    let q = importSpd(parts, ImportOptions(tileWidth: 2, tileHeight: 2))
    check q.sprites == p.sprites
    check q.tiles == p.tiles
    check q.tileSystem and q.tileWidth == 2

  test "attribute styles":
    var parts: Parts
    parts["sprites"] = newSeq[byte](128)
    parts["sprites"][63] = 0x15       # SEUCK: multicolour, colour 5
    parts["sprites"][127] = 0x06      # hires, colour 6
    check importSpd(parts, ImportOptions(spriteAttribs: saSpritePad)).sprites.mapIt(it.attributes) ==
      @[0x15'u8, 0x06]
    check importSpd(parts, ImportOptions(spriteAttribs: saSeuck)).sprites.mapIt(it.attributes) ==
      @[0x85'u8, 0x06]
    check importSpd(parts, ImportOptions(spriteAttribs: saBlank)).sprites.mapIt(it.attributes) ==
      @[0x8c'u8, 0x8c]
    parts["sprite-attribs"] = @[byte 0xa1, 0x42]
    check importSpd(parts, ImportOptions(spriteAttribs: saBlank)).sprites.mapIt(it.attributes) ==
      @[0xa1'u8, 0x42]

  test "errors":
    var parts: Parts
    expect BinError: discard importSpd(parts, ImportOptions())
    parts["sprites"] = newSeq[byte](65)
    expect BinError: discard importSpd(parts, ImportOptions())
    parts["sprites"] = newSeq[byte](64)
    parts["sprite-attribs"] = @[byte 1, 2]
    expect BinError: discard importSpd(parts, ImportOptions())
    parts.del "sprite-attribs"
    parts["tile-tags"] = @[byte 1]
    expect BinError: discard importSpd(parts, ImportOptions())
    parts["tiles"] = @[byte 0, 0, 0]
    expect BinError: discard importSpd(parts, ImportOptions(tileWidth: 2, tileHeight: 2))
    parts["sprite-anims"] = @[byte 0]
    expect BinError: discard importSpd(parts, ImportOptions())

suite "load addresses":
  test "skip, detect and none":
    let data = @[byte 0, 0x20, 1, 2, 3, 4, 5, 6, 7, 8]
    check stripLoadAddress(data, "skip", 0) == (data[2 .. ^1], some(0x2000))
    check stripLoadAddress(data, "detect", 8) == (data[2 .. ^1], some(0x2000))
    check stripLoadAddress(data, "detect", 0) == (data, none(int))
    check stripLoadAddress(data[1 .. ^1], "detect", 8) == (data[1 .. ^1], none(int))
    check stripLoadAddress(data, "none", 8) == (data, none(int))
    expect BinError: discard stripLoadAddress(@[byte 1], "skip", 0)
