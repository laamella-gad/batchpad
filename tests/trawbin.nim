import std/[options, unittest]
import batchpad/[ctm, rawbin, spd]

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

suite "CharPad parts":
  test "chars and char attributes":
    let p = charProject()
    check p.binPart("chars") == @[byte 0, 1, 2, 3, 4, 5, 6, 7, 16, 17, 18, 19, 20, 21, 22, 23,
                                  32, 33, 34, 35, 36, 37, 38, 39]
    check p.binPart("char-attribs") == @[byte 0x18, 0x29, 0x3a]
    check p.binPart("char-materials") == @[byte 1, 2, 3]

  test "char colours only count when colouring is per char":
    check charProject(colouring = cmPerTile).binPart("char-attribs") == @[byte 0x10, 0x20, 0x30]
    check charProject(mode = dmHiresBitmap).binPart("char-attribs") == @[byte 0x10, 0x20, 0x30]
    check charProject(mode = dmMulticolourBitmap).binPart("char-attribs") == @[byte 0x18, 0x29, 0x3a]

  test "L2 attributes":
    check charProject(mode = dmHiresBitmap).binPart("char-attribs-l2") == @[byte 0x52, 0x63, 0x74]
    check charProject(mode = dmHiresBitmap).binPart("tile-attribs-l2") == @[byte 0, 0, 0]
    let t = charProject(mode = dmMulticolourBitmap, colouring = cmPerTile)
    check t.binPart("tile-attribs-l2") == @[byte 0x43, 0x65, 0x17]
    check t.binPart("char-attribs-l2") == @[byte 0, 0, 0]
    expect BinError: discard charProject().binPart("char-attribs-l2")
    expect BinError: discard charProject().binPart("tile-attribs-l2")

  test "tile attributes and tags":
    check charProject(colouring = cmPerTile).binPart("tile-attribs") == @[byte 9, 10, 11]
    check charProject(mode = dmHiresBitmap, colouring = cmPerTile).binPart("tile-attribs") ==
      @[byte 0, 0, 0]
    check charProject().binPart("tile-attribs") == @[byte 0, 0, 0]
    check charProject().binPart("tile-tags") == @[byte 7, 8, 9]

  test "tiles in every cell width":
    let p = charProject()
    expect BinError: discard p.binPart("tiles")    # 0x345 doesn't fit in 8 bits
    let o12 = BinOptions(cells: cf12)
    check p.binPart("tiles-lo", o12) == @[byte 0, 1, 2, 0x23, 0x45, 2]
    check p.binPart("tiles-hi", o12) == @[byte 0x00, 0x01, 0x30]
    let o16 = BinOptions(cells: cf16)
    check p.binPart("tiles-lo", o16) == @[byte 0, 1, 2, 0x23, 0x45, 2]
    check p.binPart("tiles-hi", o16) == @[byte 0, 0, 0, 1, 3, 0]
    check p.binPart("tiles", BinOptions(cells: cfWord)) ==
      @[byte 0, 0, 1, 0, 2, 0, 0x23, 1, 0x45, 3, 2, 0]

  test "12 bit packs an odd count with a zero low nibble":
    var p = charProject()
    p.tiles = @[Tile(cells: @[0x100'u16, 0x200]), Tile(cells: @[0x300'u16, 0x400]),
                Tile(cells: @[0x500'u16, 0x600])]
    p.tileWidth = 1
    for t in p.tiles.mitems: t.cells.setLen 1
    check p.binPart("tiles-hi", BinOptions(cells: cf12)) == @[byte 0x13, 0x50]

  test "split widths need -lo and -hi, the others don't":
    let p = charProject()
    expect BinError: discard p.binPart("tiles", BinOptions(cells: cf16))
    expect BinError: discard p.binPart("tiles-lo", BinOptions(cells: cfWord))
    expect BinError: discard p.binPart("map-hi")

  test "map and map area":
    let p = charProject()
    check p.binPart("map") == @[byte 0, 1, 2, 2, 1, 0]
    check p.binPart("map", BinOptions(area: some(Area(x: 1, y: 0, width: 2, height: 2)))) ==
      @[byte 1, 2, 1, 0]
    expect BinError:
      discard p.binPart("map", BinOptions(area: some(Area(x: 2, y: 0, width: 2, height: 1))))

  test "sub-maps":
    var p = charProject()
    p.mapWidth = 5
    p.mapHeight = 3
    p.map = @[]
    for i in 0'u16 ..< 15: p.map.add i * 0x11
    p.flexiGrid = FlexiGrid(width: 2, height: 1)    # needn't be switched on
    check p.subMaps == SubMaps(width: 2, height: 1, across: 2, down: 3)
    # Row by row of sub-maps; the column the grid doesn't fill is left out.
    check p.binPart("submaps", BinOptions(cells: cfWord)) ==
      @[byte 0x00, 0, 0x11, 0, 0x22, 0, 0x33, 0, 0x55, 0, 0x66, 0, 0x77, 0, 0x88, 0,
        0xaa, 0, 0xbb, 0, 0xcc, 0, 0xdd, 0]
    check p.binSubMap(1, 1, "submaps") == @[byte 0x77, 0x88]
    p.map[14] = 0x123
    p.flexiGrid = FlexiGrid(width: 1, height: 3)
    check p.binSubMap(0, 4, "submaps-hi", BinOptions(cells: cf12)) == @[byte 0x00, 0x10]
    check p.binPart("submaps-hi", BinOptions(cells: cf16)) == @[byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    expect BinError: discard p.binSubMap(1, 0, "submaps")

  test "sub-maps the flexi-grid can't make":
    var p = charProject()
    expect BinError: discard p.binPart("submaps")             # no size (as V7)
    p.flexiGrid = FlexiGrid(width: 4, height: 1)
    expect BinError: discard p.binPart("submaps")             # wider than the map
    p.flexiGrid = FlexiGrid(width: 1, height: 1, settings: 0x20)
    expect BinError: discard p.binPart("submaps")             # measured in chars
    p.tileSystem = false
    check p.binPart("submaps") == @[byte 0, 1, 2, 2, 1, 0]    # chars are map cells
    expect BinError:
      discard p.binPart("submaps", BinOptions(area: some(Area(x: 0, y: 0, width: 1, height: 1))))

  test "colour map":
    # Tiles expanded into a 6 x 2 char map; 0x123 and 0x345 aren't chars.
    var p = charProject()
    check (p.charsWide, p.charsHigh) == (6, 2)
    check p.binPart("colour-map") == @[byte 8, 9, 10, 0, 0, 10, 0, 10, 10, 0, 8, 9]
    p.colouring = cmPerTile
    check p.binPart("colour-map") == @[byte 9, 9, 10, 0, 0, 11, 0, 11, 10, 0, 9, 9]
    p.colouring = cmPerProject
    p.colours = [0x16'u8, 0, 0]    # only the low nibble
    check p.binPart("colour-map") == @[byte 6, 6, 6, 0, 0, 6, 0, 6, 6, 0, 6, 6]
    # --cells doesn't change it; --area isn't for it.
    check p.binPart("colour-map", BinOptions(cells: cf16)).len == 12
    expect BinError:
      discard p.binPart("colour-map", BinOptions(area: some(Area(x: 0, y: 0, width: 1, height: 1))))
    p.map[0] = 7    # no such tile
    check p.binPart("colour-map")[0 .. 1] == @[byte 0, 0]
    p.tileSystem = false
    p.colouring = cmPerChar
    p.map = @[0'u16, 1, 2, 2, 1, 0]
    check p.binPart("colour-map") == @[byte 8, 9, 10, 10, 9, 8]
    p.colouring = cmPerTile
    expect BinError: discard p.binPart("colour-map")

  test "no tiles":
    var p = charProject()
    p.tileSystem = false
    p.tiles = @[]
    for part in ["tiles", "tile-attribs", "tile-tags"]:
      expect BinError: discard p.binPart(part)
    expect BinError: discard p.binPart("sprites")

proc spriteProject(): SpriteProject =
  result = SpriteProject(version: 5, tileSystem: true, tileWidth: 1, tileHeight: 2)
  for i in 0..1:
    var s = Sprite(attributes: [0x81'u8, 0x1e][i])
    s.data[0] = uint8(i + 1)
    s.data[62] = 0xee
    result.sprites.add s
  result.tiles = @[SpriteTile(cells: @[0'u16, 1], attributes: 0x13, tag: 4),
                   SpriteTile(cells: @[1'u16, 0], attributes: 0x00, tag: 5)]
  result.spriteAnims = @[Animation(first: 0, last: 1, timer: 4, attributes: 0x80),
                         Animation(first: 1, last: 1, timer: 9, attributes: 0x90)]

suite "SpritePad parts":
  test "sprites in each attribute style":
    let p = spriteProject()
    let s = p.binPart("sprites")
    check s.len == 128
    check s[0] == 1 and s[62] == 0xee and s[63] == 0x81 and s[64] == 2 and s[127] == 0x1e
    let seuck = p.binPart("sprites", BinOptions(spriteAttribs: saSeuck))
    check seuck[63] == 0x11 and seuck[127] == 0x0e
    let blank = p.binPart("sprites", BinOptions(spriteAttribs: saBlank))
    check blank[63] == 0 and blank[127] == 0
    check p.binPart("sprite-attribs") == @[byte 0x81, 0x1e]

  test "tiles, attributes and tags":
    let p = spriteProject()
    check p.binPart("tiles") == @[byte 0, 1, 1, 0]
    check p.binPart("tile-attribs") == @[byte 0x10, 0]
    check p.binPart("tile-tags") == @[byte 4, 5]

  test "animations":
    let p = spriteProject()
    check p.binPart("sprite-anims") == @[byte 0, 1, 1, 1, 4, 9, 0x80, 0x90]
    check p.binPart("sprite-anims", BinOptions(cells: cfWord)) ==
      @[byte 0, 0, 1, 0, 1, 0, 1, 0, 4, 9, 0x80, 0x90]
    expect BinError: discard p.binPart("sprite-anims", BinOptions(cells: cf16))
    check p.binPart("tile-anims") == newSeq[byte]()
