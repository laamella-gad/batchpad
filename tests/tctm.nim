import std/[os, strutils, unittest]
import batchpad/ctm

proc words(values: varargs[int]): seq[byte] =
  for v in values:
    result.add byte(v and 0xff)
    result.add byte(v shr 8)

proc v9(mode, colouring, flags: int, body: seq[byte]): seq[byte] =
  result = @[byte('C'), byte('T'), byte('M'), 9, byte(mode), byte(colouring), byte(flags)]
  result.add words(40, 25)
  result.add 0x81           # flexi-grid on, red
  result.add @[byte 6, 11, 12, 15, 1, 2, 3]
  result.add body

const charData = [
  [0x00'u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
  [0xff'u8, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
  [0xaa'u8, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55],
  [0xff'u8, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0xff],
  [0x80'u8, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01],
  [0x00'u8, 0x00, 0x55, 0x55, 0xaa, 0xaa, 0xff, 0xff]]
const tileMap = @[1'u16, 2, 3, 1, 2, 3,
                  2, 3, 1, 2, 3, 1,
                  0, 1, 0, 1, 0, 1]
const charMap = @[1'u16, 2, 3, 4, 5, 0,
                  5, 4, 3, 2, 1, 0]

proc checkChars(p: Project) =
  check p.chars.len == 6
  for i, ch in p.chars:
    check ch.data == charData[i]
    check ch.material == uint8(i)

proc checkTiles(p: Project) =
  check p.tileSystem
  check p.tileWidth == 2 and p.tileHeight == 2
  check p.tiles.len == 4
  check p.tiles[3].cells == @[5'u16, 2, 2, 5]
  for i, name in ["empty", "solid", "box", "bands"]:
    check p.tiles[i].name == name
    check p.tiles[i].tag == uint8(i)
  check p.mapWidth == 6 and p.mapHeight == 3
  check p.map == tileMap

proc checkNoTiles(p: Project) =
  check not p.tileSystem
  check p.tiles.len == 0
  check p.mapWidth == 6 and p.mapHeight == 2
  check p.map == charMap

suite "CTM V9":
  const dir = currentSourcePath().parentDir / "files" / "ctm9"
  test "multicolour text, per tile":
    let p = readCtm(dir / "mctext_pertile.ctm")
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerTile
    check p.flexiGrid == FlexiGrid(width: 10, height: 10, settings: 0x40)
    check p.chipColours == [6'u8, 11, 12, 0]
    check p.colours == [14'u8, 0, 0]
    p.checkChars
    p.checkTiles
    for i, c in [9'u8, 10, 13, 15]:
      check p.tiles[i].colours == [c, 0, 0]

  test "hires text, per char, no tiles":
    let p = readCtm(dir / "hirestext_perchar_notiles.ctm")
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    p.checkChars
    p.checkNoTiles
    for i, c in [1'u8, 2, 5, 7, 13, 14]:
      check p.chars[i].colours == [c, 0, 0]

  test "multicolour bitmap, per tile":
    let p = readCtm(dir / "mcbitmap_pertile.ctm")
    check p.displayMode == dmMulticolourBitmap
    check p.colouring == cmPerTile
    check p.colours == [1'u8, 2, 3]
    p.checkChars
    p.checkTiles
    check p.tiles[0].colours == [1'u8, 2, 3]
    check p.tiles[3].colours == [10'u8, 11, 12]

  test "hires bitmap, per char, flexi-grid":
    let p = readCtm(dir / "hiresbitmap_perchar.ctm")
    check p.displayMode == dmHiresBitmap
    check p.colouring == cmPerChar
    check p.flexiGrid == FlexiGrid(width: 3, height: 2, settings: 0x81)
    p.checkChars
    p.checkTiles
    check p.chars[1].colours == [0'u8, 2, 7]
    check p.chars[5].colours == [0'u8, 0, 1]

  test "multicolour text, per char, values above 255":
    let p = readCtm(dir / "mctext_perchar_big.ctm")
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerChar
    check p.chars.len == 300
    check p.chars[299].material == 11
    check p.chars[299].colours[0] == 11
    check p.tiles.len == 261
    check p.tiles[100].cells == @[0'u16, 1, 2]
    check p.tiles[260].tag == 4
    check p.tiles[260].name == "t260"
    check p.mapWidth == 21 and p.mapHeight == 13
    check p.map[38] == 5
    check p.map[37] == 259

  test "ECM text, per project, key map":
    let p = readCtm(dir / "ecm_perproject_notiles.ctm")
    check p.displayMode == dmEcmText
    check p.colouring == cmPerProject
    check p.keyMap == 9
    check p.chipColours == [0'u8, 2, 5, 6]
    check p.colours == [1'u8, 0, 0]
    p.checkChars
    p.checkNoTiles

  test "errors":
    expect CtmError: discard parseCtm(cast[seq[byte]]("CTX\9"))
    expect CtmError: discard parseCtm(@[byte('C'), byte('T'), byte('M'), 3])
    expect CtmError: discard parseCtm(v9(0, 0, 0, @[byte 0xda]))
    expect CtmError: discard parseCtm(v9(5, 0, 0, @[]))
    expect CtmError: discard parseCtm(v9(0, 3, 0, @[]))
    var trailing = v9(0, 0, 0, @[byte 0xda, 0xb0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                  0xda, 0xb1, 0, 0xda, 0xb2, 1, 0, 1, 0, 0, 0])
    discard parseCtm(trailing)
    trailing.add 0
    expect CtmError: discard parseCtm(trailing)

  test "writing gives back the same bytes":
    var files = 0
    for kind, path in walkDir(dir):
      if path.endsWith(".ctm"):
        checkpoint path
        let data = readFile(path)
        check readCtm(path).toCtm == cast[seq[byte]](data)
        inc files
    check files == 6

  test "writeCtm":
    let path = getTempDir() / "batchpad_tctm.ctm"
    let p = readCtm(dir / "mctext_pertile.ctm")
    writeCtm(path, p)
    check readCtm(path) == p
    removeFile path

  test "writer errors":
    let p = readCtm(dir / "mctext_pertile.ctm")
    var q = p
    q.chars.setLen 0
    expect CtmError: discard q.toCtm
    q = p
    q.tiles.setLen 0
    expect CtmError: discard q.toCtm
    q = p
    q.tiles[2].cells.add 0
    expect CtmError: discard q.toCtm
    q = p
    q.map.add 0
    expect CtmError: discard q.toCtm
    expect CtmError: discard p.toCtm(version = 8)

  test "writer leaves out what doesn't fit":
    let p = readCtm(dir / "mctext_pertile.ctm")
    var q = p
    q.tiles[0].name = repeat('x', 33)
    q.tiles[1].name = "ab\0cd"
    q.keyMap = 16
    let r = parseCtm(q.toCtm)
    check r.tiles[0].name == repeat('x', 32)
    check r.tiles[1].name == "ab"
    check r.keyMap == 0
    q = p
    q.tileSystem = false
    q.mapWidth = 6
    q.mapHeight = 3
    check parseCtm(q.toCtm).tiles.len == 0
    q = p
    q.tileHeight = 256
    for t in q.tiles.mitems: t.cells = newSeq[uint16](2 * 256)
    q.tiles[0].cells[3] = 5
    q.mapWidth = 65536
    q.mapHeight = 1
    q.map = newSeq[uint16](65536)
    q.map[1] = 2
    let c = parseCtm(q.toCtm)
    check c.tileHeight == 255 and c.tiles[0].cells.len == 510 and c.tiles[0].cells[3] == 5
    check c.mapWidth == 65535 and c.map.len == 65535 and c.map[1] == 2

suite "CTM V7":
  const dir = currentSourcePath().parentDir / "files" / "ctm7"

  proc v7(mode, colouring, flags: int, body: seq[byte]): seq[byte] =
    result = @[byte('C'), byte('T'), byte('M'), 7, 6, 11, 12, 15, 1,
               byte(colouring), byte(mode), byte(flags)]
    result.add body

  test "multicolour text, per tile":
    let p = readCtm(dir / "mctext_pertile.ctm")
    check p.version == 7
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerTile
    check p.chipColours == [6'u8, 11, 12, 0]
    check p.colours == [14'u8, 0, 0]
    p.checkChars
    p.checkTiles
    for i, c in [9'u8, 10, 13, 15]:
      check p.tiles[i].colours == [c, 0, 0]
    for ch in p.chars:
      check ch.colours == [0'u8, 0, 0]

  test "hires text, per char, no tiles":
    let p = readCtm(dir / "hirestext_perchar_notiles.ctm")
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    check p.colours == [1'u8, 0, 0]
    p.checkChars
    p.checkNoTiles
    for i, c in [1'u8, 2, 5, 7, 13, 14]:
      check p.chars[i].colours == [c, 0, 0]

  test "hires text, per project":
    let p = readCtm(dir / "hirestext_perproject.ctm")
    check p.displayMode == dmHiresText
    check p.colouring == cmPerProject
    check p.chipColours == [6'u8, 0, 0, 0]
    check p.colours == [7'u8, 0, 0]
    p.checkChars
    p.checkTiles

  test "ECM text, per project, no tiles":
    let p = readCtm(dir / "ecm_perproject_notiles.ctm")
    check p.displayMode == dmEcmText
    check p.colouring == cmPerProject
    check p.chipColours == [0'u8, 2, 5, 6]
    check p.colours == [1'u8, 0, 0]
    p.checkChars
    p.checkNoTiles

  test "errors":
    expect CtmError: discard parseCtm(v7(3, 0, 0, @[]))     # no bitmap modes in V7
    expect CtmError: discard parseCtm(v7(0, 3, 0, @[]))
    expect CtmError: discard parseCtm(v7(0, 0, 0, @[byte 0xda]))
    var trailing = v7(0, 0, 0, @[byte 0xda, 0xb0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                  0xda, 0xb1, 0x5a, 0xda, 0xb2, 1, 0, 1, 0, 0, 0])
    let p = parseCtm(trailing)
    check p.chars[0].material == 5 and p.chars[0].colours[0] == 10
    trailing.add 0
    expect CtmError: discard parseCtm(trailing)

  test "writing gives back the same bytes":
    var files = 0
    for kind, path in walkDir(dir):
      if path.endsWith(".ctm"):
        checkpoint path
        let data = readFile(path)
        check readCtm(path).toCtm(version = 7) == cast[seq[byte]](data)
        inc files
    check files == 4

  test "V9 to V7":
    # Keeps what V7 holds, drops the key map and the flexi-grid.
    var p = readCtm(currentSourcePath().parentDir / "files" / "ctm9" / "mctext_pertile.ctm")
    p.keyMap = 9
    let q = parseCtm(p.toCtm(version = 7))
    check q.version == 7
    p.version = 7
    p.keyMap = 0
    p.flexiGrid = FlexiGrid()
    check q == p

  test "writer leaves out what doesn't fit":
    let p = readCtm(dir / "mctext_pertile.ctm")
    var q = p
    q.chars[2].material = 0x12
    q.tiles[1].colours[0] = 0x1a
    let r = parseCtm(q.toCtm(version = 7))
    check r.chars[2].material == 2
    check r.tiles[1].colours[0] == 10

  test "writer errors":
    let p = readCtm(dir / "mctext_pertile.ctm")
    var q = p
    q.displayMode = dmHiresBitmap
    expect CtmError: discard q.toCtm(version = 7)
    q.displayMode = dmMulticolourBitmap
    expect CtmError: discard q.toCtm(version = 7)
    q = p
    q.chars.setLen 0
    expect CtmError: discard q.toCtm(version = 7)
