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
    expect CtmError: discard p.toCtm(version = 3)

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


  test "writer says what it leaves out":
    let p = readCtm(dir / "mctext_pertile.ctm")
    var leftOut: seq[string]
    discard p.toCtm(9, leftOut)
    check leftOut.len == 0
    var q = p
    q.tiles[0].name = repeat('x', 33)
    q.keyMap = 16
    discard q.toCtm(9, leftOut)
    check leftOut == @["the end of 1 tile name (past 32 chars or a 0 byte)",
                       "key map 16 (V9 holds 0-15)"]

suite "CTM V8":
  const dir = currentSourcePath().parentDir / "files" / "ctm8"
  const dir9 = currentSourcePath().parentDir / "files" / "ctm9"

  test "multicolour bitmap, per tile":
    let p = readCtm(dir / "mcbitmap_pertile.ctm")
    check p.version == 8
    check p.displayMode == dmMulticolourBitmap
    check p.colouring == cmPerTile
    check p.colours == [1'u8, 2, 3]
    check p.keyMap == 0
    check p.flexiGrid == FlexiGrid()
    p.checkChars
    p.checkTiles
    check p.tiles[3].colours == [10'u8, 11, 12]

  test "version byte 82 is V8 too":
    let p = readCtm(dir / "hirestext_perchar_notiles.ctm")
    check readFile(dir / "hirestext_perchar_notiles.ctm")[3] == char(82)
    check p.version == 8
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    p.checkChars
    p.checkNoTiles
    for i, c in [1'u8, 2, 5, 7, 13, 14]:
      check p.chars[i].colours == [c, 0, 0]

  test "values above 255":
    let p = readCtm(dir / "mctext_perchar_big.ctm")
    check p.chars.len == 300 and p.tiles.len == 261
    check p.map[37] == 259

  test "same project as V9, apart from the version and what V8 lacks":
    for name in ["mcbitmap_pertile.ctm", "hirestext_perchar_notiles.ctm", "mctext_perchar_big.ctm"]:
      checkpoint name
      var q = readCtm(dir9 / name)
      q.version = 8
      q.keyMap = 0
      q.flexiGrid = FlexiGrid()
      check readCtm(dir / name) == q

  test "writing gives back the same bytes, except version 82":
    var files = 0
    for kind, path in walkDir(dir):
      if path.endsWith(".ctm"):
        checkpoint path
        var data = cast[seq[byte]](readFile(path))
        data[3] = 8
        check readCtm(path).toCtm(version = 8) == data
        inc files
    check files == 3

  test "V9 to V8":
    var p = readCtm(dir9 / "hiresbitmap_perchar.ctm")
    p.keyMap = 9
    var leftOut: seq[string]
    let q = parseCtm(p.toCtm(8, leftOut))
    check leftOut == @["key map 9 (V8 has none)", "the flexi-grid (V8 has none)"]
    p.version = 8
    p.keyMap = 0
    p.flexiGrid = FlexiGrid()
    check q == p
    check parseCtm(q.toCtm(version = 9)).version == 9

  test "errors":
    let data = cast[seq[byte]](readFile(dir / "mcbitmap_pertile.ctm"))
    var bad = data
    bad[4] = 5                   # display mode
    expect CtmError: discard parseCtm(bad)
    bad = data
    bad[5] = 3                   # colouring
    expect CtmError: discard parseCtm(bad)
    bad = data
    bad.add 0
    expect CtmError: discard parseCtm(bad)
    expect CtmError: discard parseCtm(data[0 ..< 40])

const filesDir = currentSourcePath().parentDir / "files"

proc fromV7(name: string, version: int): Project =
  ## The V7 file of `name` as the project a version without tile tags and names,
  ## and without $d024, holds.
  result = readCtm(filesDir / "ctm7" / name)
  result.version = version
  result.chipColours[3] = 0
  for t in result.tiles.mitems:
    t.tag = 0
    t.name = ""

suite "CTM V5":
  const dir = filesDir / "ctm5"
  const names = ["mctext_pertile.ctm", "hirestext_perchar_notiles.ctm"]

  test "same project as V7, apart from the version, tags and names":
    for name in names:
      checkpoint name
      check readCtm(dir / name) == fromV7(name, 5)

  test "multicolour text, per tile":
    let p = readCtm(dir / "mctext_pertile.ctm")
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerTile
    check p.chipColours == [6'u8, 11, 12, 0]
    check p.colours == [14'u8, 0, 0]
    check p.tiles.len == 4 and p.tiles[3].cells == @[5'u16, 2, 2, 5]
    for i, c in [9'u8, 10, 13, 15]:
      check p.tiles[i].colours == [c, 0, 0]

  test "hires text, per char, no tiles":
    let p = readCtm(dir / "hirestext_perchar_notiles.ctm")
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    p.checkNoTiles
    for i, c in [1'u8, 2, 5, 7, 13, 14]:
      check p.chars[i].colours == [c, 0, 0]

  test "expanded char set: the tile data is left out":
    let p = readCtm(dir / "mctext_expanded.ctm")
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerProject
    check p.colours == [7'u8, 0, 0]
    check p.chars.len == 8
    check p.tileWidth == 2 and p.tileHeight == 2
    check p.tiles.len == 2
    check p.tiles[0].cells == @[0'u16, 1, 2, 3]
    check p.tiles[1].cells == @[4'u16, 5, 6, 7]
    check p.mapWidth == 3 and p.mapHeight == 2
    check p.map == @[0'u16, 1, 1, 1, 0, 0]
    # Written out in full, and read back the same.
    check parseCtm(p.toCtm(5)) == p

  test "writing gives back the same bytes":
    for name in names:
      checkpoint name
      check readCtm(dir / name).toCtm(version = 5) == cast[seq[byte]](readFile(dir / name))

  test "writer says what it leaves out":
    var p = readCtm(filesDir / "ctm7" / "mctext_pertile.ctm")
    p.chars[2].material = 0x12
    p.chipColours[3] = 4
    var leftOut: seq[string]
    let q = parseCtm(p.toCtm(5, leftOut))
    check leftOut == @["colour and material bits above the low 4 (V5 has 4)", "$d024 (V5 has none)",
                       "3 tile tags (V5 has none)", "4 tile names (V5 has none)"]
    check q.chars[2].material == 2

  test "errors":
    let data = cast[seq[byte]](readFile(dir / "mctext_pertile.ctm"))
    var bad = data
    bad[8] = 3                   # colouring
    expect CtmError: discard parseCtm(bad)
    bad = data
    bad.add 0
    expect CtmError: discard parseCtm(bad)
    bad = cast[seq[byte]](readFile(dir / "mctext_expanded.ctm"))
    bad[10] = 6                  # 7 chars are not 2 tiles of 4
    expect CtmError: discard parseCtm(bad)
    var p = readCtm(filesDir / "ctm7" / "ecm_perproject_notiles.ctm")
    expect CtmError: discard p.toCtm(version = 5)
    p.displayMode = dmMulticolourBitmap
    expect CtmError: discard p.toCtm(version = 5)

suite "CTM V4":
  const dir = filesDir / "ctm4"

  test "same project as V7 (tile colours), apart from the version, tags and names":
    check readCtm(dir / "mctext_pertile.ctm") == fromV7("mctext_pertile.ctm", 4)

  test "per tile cell colours become per char, with copies":
    let p = readCtm(dir / "hires_pertilecell.ctm")
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    check p.chars.len == 7
    check p.chars[6].data == charData[5]
    check p.chars[6].material == 5
    # Tile n has colour n + 1, except the first cell of tile 3: 5.
    for (ch, c) in [(0, 1), (1, 2), (3, 3), (5, 5), (2, 4), (6, 4)]:
      check p.chars[ch].colours[0] == uint8(c)
    check p.tiles[3].cells == @[5'u16, 2, 2, 6]
    check p.tiles[0].cells == @[0'u16, 0, 0, 0]
    check p.map == tileMap

  test "expanded char set":
    let p = readCtm(dir / "mctext_expanded.ctm")
    check p.chars.len == 8
    check p.tiles.len == 2
    check p.tiles[1].cells == @[4'u16, 5, 6, 7]
    check p.map == @[0'u16, 1, 1, 1, 0, 0]
    check p.chars[7].material == 7

  test "writing gives back the same bytes":
    let name = "mctext_pertile.ctm"
    check readCtm(dir / name).toCtm(version = 4) == cast[seq[byte]](readFile(dir / name))

  test "writing and reading give back the project":
    for name in ["hires_pertilecell.ctm", "mctext_expanded.ctm"]:
      checkpoint name
      let p = readCtm(dir / name)
      check parseCtm(p.toCtm(4)) == p

  test "writer says what it leaves out":
    var p = readCtm(filesDir / "ctm7" / "mctext_pertile.ctm")
    var leftOut: seq[string]
    discard p.toCtm(4, leftOut)
    check leftOut == @["3 tile tags (V4 has none)", "4 tile names (V4 has none)"]

  test "errors and refusals":
    let data = cast[seq[byte]](readFile(dir / "mctext_pertile.ctm"))
    var bad = data
    bad[8] = 3                   # colouring
    expect CtmError: discard parseCtm(bad)
    bad = data
    bad.add 0
    expect CtmError: discard parseCtm(bad)
    bad = data
    bad[13] = 0                  # tile width
    expect CtmError: discard parseCtm(bad)
    # A char map has no V4 form.
    var p = readCtm(filesDir / "ctm7" / "hirestext_perchar_notiles.ctm")
    expect CtmError: discard p.toCtm(version = 4)
    p = readCtm(filesDir / "ctm7" / "mctext_pertile.ctm")
    p.map[0] = 256
    expect CtmError: discard p.toCtm(version = 4)
    p = readCtm(filesDir / "ctm7" / "mctext_pertile.ctm")
    for i in 0 ..< 253: p.tiles.add p.tiles[0]
    expect CtmError: discard p.toCtm(version = 4)

suite "CTM V6":
  const dir = currentSourcePath().parentDir / "files" / "ctm6"
  const dir7 = currentSourcePath().parentDir / "files" / "ctm7"
  const names = ["mctext_pertile.ctm", "hirestext_perchar_notiles.ctm", "hirestext_perproject.ctm"]

  test "same project as V7, apart from the version and $d024":
    for name in names:
      checkpoint name
      var q = readCtm(dir7 / name)
      q.version = 6
      q.chipColours[3] = 0
      check readCtm(dir / name) == q

  test "multicolour text, per tile":
    let p = readCtm(dir / "mctext_pertile.ctm")
    check p.displayMode == dmMulticolourText
    check p.colouring == cmPerTile
    check p.chipColours == [6'u8, 11, 12, 0]
    p.checkChars
    p.checkTiles

  test "hires text, per char, no tiles":
    let p = readCtm(dir / "hirestext_perchar_notiles.ctm")
    check p.displayMode == dmHiresText
    check p.colouring == cmPerChar
    p.checkNoTiles

  test "writing gives back the same bytes":
    for name in names:
      checkpoint name
      check readCtm(dir / name).toCtm(version = 6) == cast[seq[byte]](readFile(dir / name))

  test "writer says what it leaves out":
    var p = readCtm(dir7 / "mctext_pertile.ctm")
    p.chipColours[3] = 5
    p.keyMap = 9
    p.chars[2].material = 0x12
    var leftOut: seq[string]
    let q = parseCtm(p.toCtm(6, leftOut))
    check leftOut == @["colour and material bits above the low 4 (V6 has 4)",
                       "key map 9 (V6 has none)", "$d024 (V6 has none)"]
    check q.chars[2].material == 2
    check q.chipColours == [6'u8, 11, 12, 0]

  test "errors":
    let data = cast[seq[byte]](readFile(dir / "mctext_pertile.ctm"))
    var bad = data
    bad[8] = 3                   # colouring
    expect CtmError: discard parseCtm(bad)
    bad = data
    bad.add 0
    expect CtmError: discard parseCtm(bad)
    var p = readCtm(dir7 / "ecm_perproject_notiles.ctm")
    expect CtmError: discard p.toCtm(version = 6)
    p.displayMode = dmHiresBitmap
    expect CtmError: discard p.toCtm(version = 6)

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


  test "writer says what it leaves out":
    let p = readCtm(dir / "mctext_pertile.ctm")
    var leftOut: seq[string]
    discard p.toCtm(7, leftOut)
    check leftOut.len == 0
    var q = p
    q.chars[2].material = 0x12
    q.keyMap = 9
    q.flexiGrid.settings = 0x81
    discard q.toCtm(7, leftOut)
    check leftOut == @["colour and material bits above the low 4 (V7 has 4)",
                       "key map 9 (V7 has none)", "the flexi-grid (V7 has none)"]

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

suite "expanding tiles":
  proc project(colouring: ColouringMethod): Project =
    result = Project(version: 9, displayMode: dmMulticolourText, colouring: colouring,
                     tileSystem: true, tileWidth: 2, tileHeight: 2, colours: [5'u8, 0, 0],
                     mapWidth: 2, mapHeight: 1, map: @[0'u16, 1])
    for i in 0 .. 2: result.chars.add Char(material: uint8(i), colours: [uint8(i + 1), 0, 0])
    result.tiles = @[Tile(cells: @[0'u16, 1, 2, 0], colours: [9'u8, 0, 0], tag: 3, name: "a"),
                     Tile(cells: @[1'u16, 1, 0, 2], colours: [10'u8, 0, 0], name: "b")]

  test "chars of one colour stay, the map is by chars":
    var p = project(cmPerProject)
    p.expandTiles
    check not p.tileSystem
    check p.tiles.len == 0 and p.tileWidth == 0
    check p.chars.len == 3 and p.colouring == cmPerProject
    check (p.mapWidth, p.mapHeight) == (4, 2)
    check p.map == @[0'u16, 1, 1, 1, 2, 0, 0, 2]

  test "per tile colours move to chars, with copies":
    var p = project(cmPerTile)
    p.expandTiles
    check p.colouring == cmPerChar
    # Tile 0 (9) takes chars 0-2; tile 1 (10) gets copies: 3 of 1, 4 of 0, 5 of 2.
    check p.chars.len == 6
    check p.map == @[0'u16, 1, 3, 3, 2, 0, 4, 5]
    check p.chars[0].colours[0] == 9 and p.chars[3].colours[0] == 10
    check p.chars[4].colours[0] == 10 and p.chars[5].colours[0] == 10
    check p.chars[3].material == 1 and p.chars[4].material == 0 and p.chars[5].material == 2

  test "flexi-grid in tiles is in map cells now":
    var p = project(cmPerProject)
    p.flexiGrid = FlexiGrid(width: 3, height: 1, settings: 0x80)
    p.expandTiles
    check (p.flexiGrid.width, p.flexiGrid.height) == (6'u16, 2'u16)
    var q = project(cmPerProject)
    q.flexiGrid = FlexiGrid(width: 3, height: 1, settings: 0xa0)
    q.expandTiles
    check (q.flexiGrid.width, q.flexiGrid.height) == (3'u16, 1'u16)

  test "no tiles: nothing changes, bad numbers are errors":
    var p = project(cmPerProject)
    p.map[1] = 2
    expect CtmError: p.expandTiles
    p = project(cmPerProject)
    p.tiles[0].cells[0] = 3
    expect CtmError: p.expandTiles
    var q = Project(version: 9, chars: @[Char()], map: @[0'u16], mapWidth: 1, mapHeight: 1)
    q.expandTiles
    check q.map == @[0'u16] and q.mapWidth == 1
