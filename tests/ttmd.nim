import std/[options, os, strutils, unittest]
import batchpad/[asmout, ctm, rawbin, tmd]

const files = currentSourcePath().parentDir / "files" / "tmd"

proc bytesOf(path: string): seq[byte] =
  let s = readFile(path)
  @(s.toOpenArrayByte(0, s.high))

suite "Tilemedo":
  test "hires":
    let p = readTmd(files / "hires.tmd")
    check p.displayMode == dmHiresText and p.colouring == cmPerChar and p.tileSystem
    check p.chipColours[0] == 6
    check p.chars.len == 3 and p.chars[1].data[0] == 0xff and p.chars[2].colours[0] == 7
    check p.tileWidth == 4 and p.tileHeight == 4 and p.tiles.len == 2
    check p.tiles[1].cells[5] == 2
    check p.mapWidth == 3 and p.mapHeight == 2 and p.map == @[0'u16, 1, 0, 1, 0, 1]
    check p.triggers.len == 0

  test "multicolour with a trigger map":
    let p = readTmd(files / "multicolour.tmd")
    check p.displayMode == dmMulticolourText
    check p.chipColours[0 .. 2] == [0'u8, 11, 12]
    check p.chars[1].colours[0] == 13
    check p.triggers == @[0'u8, 5, 0, 0, 0, 255]
    check p.binPart("triggers") == @[byte 0, 5, 0, 0, 0, 255]
    check p.binPart("triggers", BinOptions(area: some(Area(x: 1, y: 0, width: 2, height: 2)))) ==
          @[byte 5, 0, 0, 255]

  test "round trips":
    for f in ["hires.tmd", "multicolour.tmd"]:
      let data = bytesOf(files / f)
      check parseTmd(data).toTmd == data
      # via a CTM: the trigger map is left out there
      var leftOut: seq[string]
      let back = parseCtm(parseTmd(data).toCtm(9, leftOut))
      check (leftOut.len > 0) == (f == "multicolour.tmd")
      var p = back
      p.version = 0
      check p.toTmd.len == data.len - parseTmd(data).triggers.len

  test "detection and bad files":
    check bytesOf(files / "hires.tmd").isTmd
    check not isTmd(@[byte 0, 0, 0, 0])
    var data = bytesOf(files / "hires.tmd")
    data[0] = 99
    expect CtmError: discard parseTmd(data)
    data = bytesOf(files / "hires.tmd")
    data[4] = 2
    expect CtmError: discard parseTmd(data)
    data = bytesOf(files / "hires.tmd")
    data.add 0
    data[0] = byte(data.len)
    expect CtmError: discard parseTmd(data)    # 1 byte after the map: no trigger map
    data = bytesOf(files / "hires.tmd")
    data.setLen 30
    data[0] = 30
    expect CtmError: discard parseTmd(data)

  test "writing other projects":
    var p = readTmd(files / "hires.tmd")
    p.colouring = cmPerTile
    p.tiles[0].colours[0] = 3
    p.tiles[1].colours[0] = 5
    var leftOut: seq[string]
    var back = parseTmd(p.toTmd(leftOut))
    check back.chars[1].colours[0] == 5 and back.chars[0].colours[0] == 3
    check leftOut.len == 0
    p.tiles.add Tile(cells: newSeq[uint16](16), colours: [9'u8, 0, 0])
    p.tiles[2].cells[0] = 1     # char 1 is in tile 1 too, coloured 5
    discard p.toTmd(leftOut)
    check leftOut.len == 1 and "tile colours" in leftOut[0]

    p = readTmd(files / "hires.tmd")
    p.tiles[0].tag = 4
    p.chars[0].material = 2
    for i in 0 ..< 300: p.chars.add Char()
    p.tiles[1].cells[0] = 290
    leftOut = @[]
    back = parseTmd(p.toTmd(leftOut))
    check back.chars.len == 256 and back.tiles[1].cells[0] == 0
    check leftOut.len == 4

    p.displayMode = dmHiresBitmap
    expect CtmError: discard p.toTmd
    p = readTmd(files / "hires.tmd")
    p.expandTiles
    expect CtmError: discard p.toTmd

  test "assembler":
    let a = readTmd(files / "multicolour.tmd").toAsm(AsmOptions())
    check "triggermap_data" in a
    check "triggermap_data" notin readTmd(files / "hires.tmd").toAsm(AsmOptions())
