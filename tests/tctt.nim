import std/[os, unittest]
import batchpad/[ctm, ctt, image, rawbin]

const dir = currentSourcePath.parentDir / "files"

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  for c in s: result.add byte(c)

suite "CTT":
  test "V9 text multicolour, colour per tile":
    let p = readCtt(dir / "ctt9" / "text-mc-tiles.ctt")
    check p.ted
    check p.version == 9
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerTile
    check p.keyMap == 3
    check p.chipColours == [0x02'u8, 0x35, 0x4a, 0x00]
    check p.colours[0] == 0x71
    check p.colours[1] == 0x03       # the unused second project colour is kept
    check p.chars.len == 3
    check p.chars[2].data == [0xaa'u8, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55]
    check p.chars[2].material == 2
    check p.tiles.len == 2
    check p.tileWidth == 2 and p.tileHeight == 2
    check p.tiles[0].cells == @[0'u16, 1, 1, 2]
    check p.tiles[0].colours[0] == 0x1c and p.tiles[1].colours[0] == 0x4d
    check p.tiles[0].tag == 5 and p.tiles[1].tag == 9
    check p.tiles[0].name == "wall" and p.tiles[1].name == "sky"
    check p.mapWidth == 3 and p.mapHeight == 2
    check p.map == @[0'u16, 1, 0, 1, 0, 1]

  test "V9 bitmap multicolour: two project colours, first one into colours[2]":
    let p = readCtt(dir / "ctt9" / "bitmap-mc-project.ctt")
    check p.displayMode == dmMulticolourBitmap
    check p.colouring == cmPerProject
    check p.keyMap == 10
    check not p.tileSystem
    check p.colours[2] == 0x23 and p.colours[1] == 0x5c
    check p.chars.len == 2 and p.chars[1].material == 3
    check p.map == @[0'u16, 1, 1, 0]

  test "V8 hires text, colour per char":
    let p = readCtt(dir / "ctt8" / "text-hires-chars.ctt")
    check p.version == 8 and p.ted
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    check p.chipColours[0] == 0x10
    check p.colours[0] == 0x36
    check p.chars[0].colours[0] == 0x6f and p.chars[1].colours[0] == 0x21
    check p.chars[0].material == 1
    check p.map == @[0'u16, 1]

  test "files are written back as read":
    for f in ["ctt9" / "text-mc-tiles.ctt", "ctt9" / "bitmap-mc-project.ctt", "ctt8" / "text-hires-chars.ctt"]:
      let p = readCtt(dir / f)
      check p.toCtt(p.version) == readFileBytes(dir / f)

  test "V9 to V8 drops the key map, V8 to V9 keeps the rest":
    let p = readCtt(dir / "ctt9" / "text-mc-tiles.ctt")
    var left: seq[string]
    let v8 = parseCtt(p.toCtt(8, left))
    check left.len == 1 and left[0] == "key map 3 (V8 has none)"
    check v8.version == 8 and v8.keyMap == 0
    check v8.tiles[1].name == "sky" and v8.map == p.map

  test "errors":
    let good = readFileBytes(dir / "ctt9" / "text-mc-tiles.ctt")
    expect CttError: discard parseCtt(@[byte(67), 84, 77, 9])
    var wrongVersion = good
    wrongVersion[3] = 7
    expect CttError: discard parseCtt(wrongVersion)
    expect CttError: discard parseCtt(good[0 ..< good.len - 1])
    expect CttError: discard parseCtt(good & @[byte 0])
    var noMarker = good
    noMarker[18] = 0
    expect CttError: discard parseCtt(noMarker)
    var mode = good
    mode[4] = 5
    expect CttError: discard parseCtt(mode)
    # a C64 project can't be written as it is, nor a TED one as CTM
    var c64 = readCtt(dir / "ctt9" / "text-mc-tiles.ctt").toC64
    expect CttError: discard c64.toCtt(9)
    expect CtmError: discard readCtt(dir / "ctt9" / "text-mc-tiles.ctt").toCtm(9)
    expect CttError: discard readCtt(dir / "ctt9" / "text-mc-tiles.ctt").toCtt(7)

  test "TED palette":
    check tedColour(0) == [0'u8, 0, 0]
    check tedColour(0x71) == [0xff'u8, 0xff, 0xff]        # white at luma 7
    check tedColour(0x02) == [0x5e'u8, 0x07, 0x00]        # red at luma 0
    check tedColour(0xf1) == tedColour(0x71)             # bit 7 is ignored

  test "to C64 colours":
    let p = readCtt(dir / "ctt9" / "text-mc-tiles.ctt").toC64
    check not p.ted
    check p.chipColours[3] == 0                          # black
    # the multicolour flag (bit 3 of the cell colour) is kept, the colour under it is the chroma
    check p.tiles[0].colours[0] == 12                # $1c: flag, colour 4 (purple)
    expect CtmError: discard p.toCtm(10)
    discard p.toCtm(9)

  test "to C64 and back: black, white and the multicolour flag":
    var p = readCtt(dir / "ctt9" / "text-mc-tiles.ctt")
    p.tiles[0].colours[0] = 0x73                         # luma 7, chroma 3 (cyan), no flag
    p.tiles[1].colours[0] = 0x2b                         # luma 2, chroma 11: flag + chroma 3
    let c64 = p.toC64
    check c64.tiles[0].colours[0] == 3
    check c64.tiles[1].colours[0] == 11'u8
    var left: seq[string]
    let ted = c64.toTed(left)
    check ted.ted
    check (ted.tiles[0].colours[0] and 15) == 3
    check (ted.tiles[1].colours[0] and 15) == 11
    check ted.tiles[1].colours[0] shr 4 < 8

  test "multicolour bitmap: TED colour 1 is the C64 colour RAM colour":
    let p = readCtt(dir / "ctt9" / "bitmap-mc-project.ctt")
    let c64 = p.toC64
    check not c64.ted
    check c64.colours[0] == nearestC64(0x1d)             # chip colour 1
    check c64.chipColours[1] == 0                        # per project: moved
    check c64.colours[1] == nearestC64(0x5c) and c64.colours[2] == nearestC64(0x23)
    var left: seq[string]
    let back = c64.toTed(left)
    check left.len == 0
    check back.ted
    check nearestC64(back.chipColours[1]) == c64.colours[0]
    check back.colours[0] == 0                           # no colour RAM colour on the C16

  test "C64 per-char colour RAM colours that differ are reported":
    var c64 = readCtt(dir / "ctt9" / "bitmap-mc-project.ctt").toC64
    c64.colouring = cmPerChar
    c64.chars[0].colours[0] = 5
    c64.chars[1].colours[0] = 6
    var left: seq[string]
    discard c64.toTed(left)
    check left == @["the colour RAM colours of chars (CharPad C16 has one shared colour)"]

  test "raw parts use CharPad C16's attribute bytes":
    let t = readCtt(dir / "ctt9" / "text-mc-tiles.ctt")
    check t.binPart("tile-attribs") == @[byte 0x1c, 0x4d]
    check t.binPart("char-materials") == @[byte 0, 1, 2]
    check t.binPart("tile-tags") == @[byte 5, 9]
    var b = readCtt(dir / "ctt9" / "bitmap-mc-project.ctt")
    b.colouring = cmPerChar
    b.chars[0].colours = [0'u8, 0x5a, 0x23]              # pen 10: $5a; pen 01: $23
    check b.binPart("char-attribs")[0] == 0x52           # lumas: pen 10 high, pen 01 low
    check b.binPart("char-attribs-l2")[0] == 0x3a        # chromas: pen 01 high, pen 10 low
