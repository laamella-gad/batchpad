import std/[options, os, osproc, strutils, unittest]
import batchpad/[asmout, ctm, rawbin, spd]

proc charProject(mode = dmMulticolourText, colouring = cmPerTile): ctm.Project =
  result = ctm.Project(version: 9, displayMode: mode, colouring: colouring,
                       tileSystem: true, tileWidth: 2, tileHeight: 1,
                       chipColours: [6'u8, 11, 12, 0], colours: [14'u8, 3, 4],
                       mapWidth: 3, mapHeight: 2)
  for i in 0..2:
    var c = Char(material: uint8(i + 1), colours: [uint8(8 + i), uint8(2 + i), uint8(5 + i)])
    for j in 0..7: c.data[j] = uint8(16 * i + j)
    result.chars.add c
  result.tiles = @[Tile(cells: @[0'u16, 1], colours: [9'u8, 3, 4], tag: 7, name: "floor"),
                   Tile(cells: @[2'u16, 0x123], colours: [10'u8, 5, 6], tag: 8, name: "say \"hi\""),
                   Tile(cells: @[0x345'u16, 2], colours: [11'u8, 7, 1], tag: 9)]
  result.map = @[0'u16, 1, 2, 2, 1, 0]

proc spriteProject(): SpriteProject =
  result = SpriteProject(version: 5, colours: [11'u8, 1, 0], tileSystem: true,
                         tileWidth: 2, tileHeight: 1)
  for i in 0..2:
    var s = Sprite(attributes: uint8(0x80 + i))
    for j in 0..62: s.data[j] = uint8(i)
    result.sprites.add s
  result.tiles = @[SpriteTile(cells: @[0'u16, 1], attributes: 0x10, tag: 4),
                   SpriteTile(cells: @[2'u16, 0], tag: 5)]
  result.spriteAnims = @[Animation(first: 0, last: 2, timer: 6, attributes: 0x10)]
  result.tileAnims = @[Animation(first: 0, last: 1, timer: 3)]

proc lines(s: string): seq[string] = s.splitLines

proc defines(text, name: string): bool =
  ## `name` is a label or a constant in `text`.
  for l in text.splitLines:
    let l = l.strip
    if l == name or l == name & ":" or l.startsWith(name & " = ") or
       l.startsWith(".const " & name & " = "):
      return true

proc everyOrgDefined(text: string): bool =
  ## Every address a `* =` or `.org` line uses is defined.
  for l in text.splitLines:
    for start in ["* = ", ".org "]:
      if l.startsWith(start) and not text.defines(l[start.len .. ^1]): return false
  true

const tass = AsmOptions(dialect: d64tass)

suite "CharPad assembler source":
  test "64tass, what Export All writes":
    let s = charProject().toAsm(AsmOptions(dialect: d64tass, bin: BinOptions(cells: cf16)))
    check "; Display mode : Text (Multi-colour)." in s
    check "; Matrix colouring method : Per Tile." in s
    for c in ["colr_vic_bg0 = 6", "colr_vic_bg1 = 11", "colr_vic_bg2 = 12",
              "colr_cmxlo_proj = 14", "char_count = 3", "tile_count = 3", "tile_wid = 2",
              "tile_hei = 1", "map_wid = 3", "map_hei = 2", "map_wid_chrs = 6",
              "map_hei_chrs = 2", "map_wid_pxls = 48", "map_hei_pxls = 16",
              "size_charset_data = $18 ; (24 bytes)", "size_chartileset_data_lo = $6 ; (6 bytes)",
              "size_chartileset_data_hi = $6 ; (6 bytes)"]:
      check c in s.lines
    for label in ["charset_data", "charset_attrib_L1_data", "chartileset_data_lo",
                  "chartileset_data_hi", "chartileset_attrib_L1_data",
                  "chartileset_tag_data", "map_data_lo", "map_data_hi"]:
      check s.defines(label)
    check not s.defines("charset_attrib_L2_data")    # text mode
    check not s.defines("chartileset_names")         # not in Export All
    check "* =" notin s
    check "addr_" notin s
    check ".byte $00,$01,$02,$03,$04,$05,$06,$07,$10,$11,$12,$13,$14,$15,$16,$17" in s.lines
    check "; 3 tiles, 2x1 (2) cells per tile, 16 bits per cell, split, total size is 12 ($c) bytes." in s.lines

  test "values that don't fit the cells are an error":
    expect BinError: discard charProject().toAsm(tass)

  test "12 bit cells":
    let s = charProject().toAsm(AsmOptions(bin: BinOptions(cells: cf12)))
    check s.defines("chartileset_data_hi_packed")
    check s.defines("size_chartileset_data_hi_packed")
    check "; 3 tiles, 2x1 (2) cells per tile, 12 bits per cell, split, high nybbles packed, total size is 9 ($9) bytes." in s.lines

  test "Export All in the bitmap modes":
    let perChar = charProject(dmMulticolourBitmap, cmPerChar).toAsm(AsmOptions(parts: @["chars", "char-attribs", "char-attribs-l2", "map"]))
    check perChar.defines("charset_attrib_L2_data")
    check "colr_vmxlo_proj = 3" in perChar.lines
    check "colr_vmxhi_proj = 4" in perChar.lines
    var p = charProject(dmHiresBitmap, cmPerChar)
    p.tiles[1].cells[1] = 0
    p.tiles[2].cells[0] = 0
    let s = p.toAsm(tass)
    check s.defines("charset_attrib_L2_data")
    check not s.defines("chartileset_attrib_L1_data")
    check not s.defines("colr_vic_bg0")
    check "; nb. Upper nybbles = material, lower nybbles = unused." in s.lines
    p.colouring = cmPerTile
    let t = p.toAsm(tass)
    check t.defines("chartileset_attrib_L1_data")
    check t.defines("chartileset_attrib_L2_data")
    check not t.defines("charset_attrib_L2_data")

  test "parts, names, prefix and org":
    let o = AsmOptions(parts: @["chars", "tile-names", "map"], prefix: "lv_",
                       org: @[("chars", 0x2000), ("map", 0xc000)],
                       bin: BinOptions(cells: cf16))
    let s = charProject().toAsm(o)
    check "lv_addr_charset_data = $2000" in s.lines
    check "lv_addr_map_data_lo = $c000" in s.lines
    check "* = lv_addr_charset_data" in s.lines
    check "* = lv_addr_map_data_lo" in s.lines
    check s.everyOrgDefined
    check not s.defines("lv_addr_map_data_hi")
    check not s.defines("charset_data")
    check s.defines("lv_charset_data")
    check "; \"floor\"" in s.lines
    check ".byte $66,$6c,$6f,$6f,$72,$00" in s.lines
    check "; \"say \"hi\"\"" in s.lines
    check ".byte $73,$61,$79,$20,$22,$68,$69,$22,$00" in s.lines
    check ".byte $00" in s.lines
    check not s.defines("lv_charset_attrib_L1_data")

  test "org on the high half of a split part":
    let s = charProject().toAsm(AsmOptions(parts: @["map"], org: @[("map-hi", 0x5000)],
                                           bin: BinOptions(cells: cf16)))
    check "addr_map_data_hi = $5000" in s.lines
    check "* = addr_map_data_hi" in s.lines
    check s.everyOrgDefined

  test "the map area":
    let s = charProject().toAsm(AsmOptions(parts: @["map"],
                                           bin: BinOptions(area: some(Area(x: 1, y: 0, width: 2, height: 2)))))
    check "map_wid = 2" in s.lines
    check ".byte $01,$02,$01,$00" in s.lines

  test "sub-maps":
    var p = charProject()
    p.flexiGrid = FlexiGrid(width: 2, height: 1)
    let s = p.toAsm(AsmOptions(parts: @["map", "submaps"], org: @[("submaps", 0x4000)]))
    check "submap_wid = 2" in s.lines
    check "submap_hei = 1" in s.lines
    check "submap_count_x = 1" in s.lines
    check "submap_count_y = 2" in s.lines
    check "; SubMap (1,0)..." in s.lines
    check "; 2x1 (2) cells, 8 bits per cell, total size is 2 ($2) bytes." in s.lines
    check "submap_y0_x0_data" in s.lines
    check "submap_y1_x0_data" in s.lines
    check ".byte $02,$01" in s.lines
    check "size_submap_y1_x0_data = $2 ; (2 bytes)" in s.lines
    # Only the first sub-map gets the org.
    check "* = addr_submap_y0_x0_data" in s.lines
    check s.everyOrgDefined
    check not s.defines("addr_submap_y1_x0_data")
    let w = p.toAsm(AsmOptions(parts: @["submaps"], bin: BinOptions(cells: cf12)))
    check "submap_y1_x0_data_hi_packed" in w.lines
    check "; 2x1 (2) cells, 12 bits per cell, split, high nybbles packed, total size is 3 ($3) bytes." in w.lines
    check not p.toAsm(AsmOptions(parts: @["map"])).defines("submap_wid")
    expect AsmError:
      discard p.toAsm(AsmOptions(parts: @["submaps"],
                                 bin: BinOptions(area: some(Area(x: 0, y: 0, width: 1, height: 1)))))

  test "colour map":
    let s = charProject().toAsm(AsmOptions(parts: @["colour-map"], bin: BinOptions(cells: cf16),
                                           org: @[("colour-map", 0xd800)]))
    check "; ColourMap Data..." in s.lines
    check "; 6x2 (12) cells, 8 bits per cell, total size is 12 ($c) bytes." in s.lines
    check "colourmap_data" in s.lines
    check ".byte $09,$09,$0a,$00,$00,$0b,$00,$0b,$0a,$00,$09,$09" in s.lines
    check "addr_colourmap_data = $d800" in s.lines
    check s.everyOrgDefined
    expect AsmError:
      discard charProject().toAsm(AsmOptions(parts: @["colour-map"],
                                             bin: BinOptions(area: some(Area(x: 0, y: 0, width: 1, height: 1)))))

  test "tile events":
    var p = charProject()
    p.tiles.add Tile(cells: @[0'u16, 0], name: "floor")
    p.tiles.add Tile(cells: @[0'u16, 0], name: "Lava")
    p.tiles.add Tile(cells: @[0'u16, 0], name: "chtl")
    p.tiles[1].name = "null"    # the same label as a tile without a name
    let s = p.toAsm(AsmOptions(parts: @["tile-events"], org: @[("tile-events", 0x2000)]))
    check "; 6 pointers (one per tile), 16 bits per pointer, total size is 12 ($c) bytes." in s.lines
    check "addr_chartileset_eventjumptable = $2000" in s.lines
    check "* = addr_chartileset_eventjumptable" in s.lines
    check ".word chtl_floor_event, chtl_null_event, chtl_null_event, chtl_floor_event" in s.lines
    check ".word chtl_Lava_event, chtl_chtl_event" in s.lines
    check "; CharTileSet Events (4)..." in s.lines
    check "size_chartileset_events = $4 ; (4 bytes)" in s.lines
    check "; event: chartile \"Lava\"." in s.lines
    check "chtl_Lava_event" in s.lines
    check s.count("rts\n") == 4
    check s.everyOrgDefined
    let alt = p.toAsm(AsmOptions(dialect: dKickAss, parts: @["tile-events"], altEventLabels: true,
                                 prefix: "lv_"))
    check ".word lv_floor, lv_null, lv_null_event, lv_floor" in alt.lines
    check "lv_null_event:" in alt.lines
    check "lv_Lava:" in alt.lines
    let bare = p.toAsm(AsmOptions(dialect: dAcme, parts: @["tile-events"], eventStubs: false))
    check "!word chtl_Lava_event, chtl_chtl_event" in bare.lines
    check not bare.defines("chartileset_events")
    check not bare.defines("chtl_null_event")

  test "tile names that can't be event labels":
    for name in ["say \"hi\"", "a-b", "ünï"]:
      var p = charProject()
      p.tiles[0].name = name
      expect AsmError: discard p.toAsm(AsmOptions(parts: @["tile-events"]))
    for name in ["x", "LDA", "rts", "_up", "3d", "lax"]:
      var p = charProject()
      p.tiles = @[Tile(cells: @[0'u16, 0], name: name)]
      check p.toAsm(AsmOptions(parts: @["tile-events"])).defines("chtl_" & name & "_event")
      expect AsmError:
        discard p.toAsm(AsmOptions(parts: @["tile-events"], altEventLabels: true))
    var p = charProject()
    p.tiles = @[Tile(cells: @[0'u16, 0], name: "x")]
    check p.toAsm(AsmOptions(parts: @["tile-events"], altEventLabels: true,
                             prefix: "lv_")).defines("lv_x")
    # Names that only differ in case are the same label in 64tass; names
    # can't take the labels of other parts.
    p.tiles = @[Tile(cells: @[0'u16, 0], name: "door"), Tile(cells: @[0'u16, 0], name: "Door")]
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["tile-events"]))
    p.tiles = @[Tile(cells: @[0'u16, 0], name: "map_data")]
    expect AsmError:
      discard p.toAsm(AsmOptions(parts: @["map", "tile-events"], altEventLabels: true))
    p.tileSystem = false
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["tile-events"]))

  test "mistakes":
    let p = charProject()
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["sprites"]))
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["chars", "chars"]))
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["chars"], org: @[("map", 0x1000)]))
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["chars"], segment: "DATA"))
    expect BinError: discard p.toAsm(AsmOptions(parts: @["submaps"]))   # no flexi-grid size
    var n = p
    n.tileSystem = false
    n.tiles = @[]
    expect AsmError: discard n.toAsm(AsmOptions(parts: @["tile-names"]))
    expect AsmError: discard n.toAsm(AsmOptions(parts: @["tiles"]))
    check not n.toAsm(tass).defines("tile_count")

suite "dialects":
  let o = AsmOptions(parts: @["chars", "tile-names"], org: @[("chars", 0x2000)])
  test "ACME":
    var a = o
    a.dialect = dAcme
    let s = charProject().toAsm(a)
    check "charset_data" in s.lines
    check "!byte $00,$01,$02,$03,$04,$05,$06,$07,$10,$11,$12,$13,$14,$15,$16,$17" in s.lines
    check "!byte $66,$6c,$6f,$6f,$72,$00" in s.lines
    check "* = addr_charset_data" in s.lines

  test "KickAssembler":
    var k = o
    k.dialect = dKickAss
    k.segment = "Data"
    let s = charProject().toAsm(k)
    check ".const char_count = 3" in s.lines
    check ".const size_charset_data = $18 // (24 bytes)" in s.lines
    check "charset_data:" in s.lines
    check "// CharSet Data..." in s.lines
    check ".segment Data" in s.lines
    check "* = addr_charset_data" in s.lines
    check s.everyOrgDefined
    check ";" notin s
    check "// \"floor\"" in s.lines
    check ".byte $66,$6c,$6f,$6f,$72,$00" in s.lines

  test "ca65":
    var c = o
    c.dialect = dCa65
    c.segment = "DATA"
    let s = charProject().toAsm(c)
    check "charset_data:" in s.lines
    check ".segment \"DATA\"" in s.lines
    check ".org addr_charset_data" in s.lines
    check s.everyOrgDefined
    check ".byte $66,$6c,$6f,$6f,$72,$00" in s.lines

  test "CRLF":
    var c = o
    c.crlf = true
    let s = charProject().toAsm(c)
    check s.count("\r\n") == s.count("\n")

suite "SpritePad assembler source":
  test "what Export All writes":
    let s = spriteProject().toAsm(tass)
    for c in ["colr_vic_bg0 = 11", "colr_vic_sprite_mc1 = 1", "colr_vic_sprite_mc2 = 0",
              "sprite_count = 3", "spriteanim_count = 1", "spritetile_count = 2",
              "spritetile_wid = 2", "spritetile_hei = 1", "spritetileanim_count = 1",
              "size_spriteset_data = $c0 ; (192 bytes)", "size_spriteanimset_data = $4 ; (4 bytes)"]:
      check c in s.lines
    for label in ["spriteset_data", "sprite_image_0", "sprite_image_2", "spriteset_attrib_data",
                  "spritetileset_data", "spritetileset_attrib_data", "spritetileset_tag_data",
                  "spriteanimset_data", "sprite_anims_from", "sprite_anims_to",
                  "sprite_anims_timereload", "sprite_anims_attrib", "spritetileanimset_data",
                  "spritetile_anims_from", "spritetile_anims_attrib"]:
      check s.defines(label)
    check ".byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$81" in s.lines
    check "; 1 animation, 4 bytes per animation, total size is 4 ($4) bytes." in s.lines
    check ".byte $10,$00" in s.lines     # tile attributes: overlay bit only

  test "sprite attribute styles and word frames":
    let s = spriteProject().toAsm(AsmOptions(parts: @["sprites", "sprite-anims"],
        bin: BinOptions(spriteAttribs: saBlank, cells: cfWord)))
    check ".byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00" in s.lines
    check "; 1 animation, 6 bytes per animation, total size is 6 ($6) bytes." in s.lines
    check ".byte $02,$00" in s.lines

  test "without tiles or animations":
    var p = spriteProject()
    p.tileSystem = false
    p.tiles = @[]
    p.tileAnims = @[]
    p.spriteAnims = @[]
    let s = p.toAsm(tass)
    check not s.defines("spritetile_count")
    check not s.defines("spriteanim_count")
    check not s.defines("spriteanimset_data")
    expect AsmError: discard p.toAsm(AsmOptions(parts: @["tile-anims"]))

suite "assembling":
  ## Each assembler is used when it is on the PATH (KickAssembler: when
  ## KICKASS_JAR names its jar and java is on the PATH), and left out otherwise.
  let dir = getTempDir() / "batchpad_tasm"
  let parts = AsmOptions(prefix: "lv_", bin: BinOptions(cells: cf12),
                         parts: @["chars", "char-attribs", "tiles", "tile-attribs",
                                  "tile-tags", "tile-names", "map", "submaps", "colour-map"])

  proc assemble(d: Dialect, main, command: string): string =
    ## The bytes the assembler makes of both projects, after `main`.
    var o = parts
    o.dialect = d
    var level = charProject()
    level.flexiGrid = FlexiGrid(width: 1, height: 2)
    writeFile(dir / "level.s", level.toAsm(o))
    writeFile(dir / "sprites.s", spriteProject().toAsm(AsmOptions(dialect: d, prefix: "sp_")))
    var events = charProject()
    events.tiles[1].name = "say_hi"
    writeFile(dir / "events.s",
              events.toAsm(AsmOptions(dialect: d, prefix: "ev_", parts: @["tile-events"])) &
              events.toAsm(AsmOptions(dialect: d, prefix: "alt_", parts: @["tile-events"],
                                      altEventLabels: true)))
    writeFile(dir / "main.s", main)
    let (output, code) = execCmdEx("cd " & quoteShell(dir) & " && " & command)
    check code == 0
    if code != 0: echo output
    else: result = readFile(dir / "out.bin")

  setup: createDir(dir)
  teardown: removeDir(dir)

  test "64tass, ACME, KickAssembler and ca65 give the same bytes":
    var made: seq[(string, string)]
    if findExe("64tass") != "":
      made.add ("64tass", assemble(d64tass, "* = $1000\n.include \"level.s\"\n.include \"sprites.s\"\n.include \"events.s\"\n",
                                   "64tass -q -b -o out.bin main.s"))
    if findExe("acme") != "":
      made.add ("acme", assemble(dAcme, "* = $1000\n!source \"level.s\"\n!source \"sprites.s\"\n!source \"events.s\"\n",
                                 "acme -f plain -o out.bin main.s"))
    if findExe("ca65") != "" and findExe("ld65") != "":
      made.add ("ca65", assemble(dCa65, ".include \"level.s\"\n.include \"sprites.s\"\n.include \"events.s\"\n",
                                 "ca65 -o main.o main.s && ld65 -t none -o out.bin main.o"))
    let kickAss = getEnv("KICKASS_JAR")
    if kickAss != "" and findExe("java") != "":
      made.add ("kickass", assemble(dKickAss, "* = $1000\n#import \"level.s\"\n#import \"sprites.s\"\n#import \"events.s\"\n",
                                    "java -jar " & quoteShell(kickAss) & " main.s -binfile -o out.bin"))
    if made.len == 0: skip()
    for (name, bytes) in made:
      checkpoint name
      # chars, attributes, tiles, tile attributes, tags, names, map, sub-maps,
      # colour map; sprites, attributes, tiles, tile attributes, tags, two lots
      # of animations; two lots of tile events (jump table, rts stubs)
      check bytes.len == 24 + 3 + 9 + 3 + 3 + 16 + 9 + 9 + 12 + 192 + 3 + 4 + 2 + 2 + 4 + 4 +
                         2 * (6 + 3)
      check bytes == made[0][1]

  test "64tass with --org":
    if findExe("64tass") == "":
      skip()
    else:
      var o = parts
      o.org = @[("chars", 0x2000), ("tiles", 0x3000)]
      var level = charProject()
      level.flexiGrid = FlexiGrid(width: 1, height: 2)
      o.org.add ("submaps", 0x4000)
      writeFile(dir / "main.s", "* = $1000\n" & level.toAsm(o))
      let (output, code) = execCmdEx("cd " & quoteShell(dir) & " && 64tass -q -o out.prg main.s")
      check code == 0
      if code != 0: echo output
