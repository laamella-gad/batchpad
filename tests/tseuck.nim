import std/[os, strutils, unittest]
import batchpad/[ctm, seuck, spd]

const files = currentSourcePath().parentDir / "files" / "seuck"

proc bytesOf(path: string): seq[byte] =
  for c in readFile(path): result.add byte(c)

proc textOf(path: string): string = readFile(path)

suite "SEUCK sprites (.A)":
  test "reads the file":
    let p = readSeuckA(files / "sprites.A")
    check p.sprites.len == 127
    check p.sprites[0].data[0] == 1 and p.sprites[0].data[62] == 63
    check p.sprites[0].multicolour and p.sprites[0].colour == 5
    check not p.sprites[1].multicolour and p.sprites[1].colour == 2
    check p.sprites[2].multicolour and p.sprites[2].colour == 15
    check p.sprites[3].data[0] == 0 and p.sprites[3].attributes == 0
    check not p.tileSystem

  test "writes the file we made":
    check readSeuckA(files / "sprites.A").toSeuckA == textOf(files / "sprites.A")

  test "pads to 127 sprites, refuses more":
    var p = readSeuckA(files / "sprites.A")
    p.sprites.setLen 2
    let s = p.toSeuckA
    check s.len == seuckASize and s[0] == 'B' and s[1] == '\0'
    check s[2 + 64 * 5 .. 2 + 64 * 6 - 1] == newString(64)
    p.sprites.setLen 128
    expect SeuckError: discard p.toSeuckA
    p.sprites.setLen 0
    expect SeuckError: discard p.toSeuckA

  test "what SEUCK can't hold is left out":
    var p = readSeuckA(files / "sprites.A")
    p.sprites[0].attributes = p.sprites[0].attributes or 0x60
    var leftOut: seq[string]
    discard p.toSeuckA(leftOut)
    check leftOut.len == 1 and "expansion" in leftOut[0]
    leftOut.setLen 0
    discard readSeuckA(files / "sprites.A").toSeuckA(leftOut)
    check leftOut.len == 0

  test "wrong size":
    expect SeuckError: discard parseSeuckA(newSeq[byte](100))

suite "SEUCK backgrounds (.B)":
  test "reads the file, map bottom to top":
    let raw = bytesOf(files / "background.B")
    let p = readSeuckB(files / "background.B")
    check p.tileSystem and p.colouring == cmPerTile and p.displayMode == dmMulticolourText
    check p.tileWidth == 5 and p.tileHeight == 5 and p.tiles.len == 128 and p.chars.len == 254
    check p.mapWidth == 8 and p.mapHeight == 512
    # The file's first row is the map's last row.
    check p.map[511 * 8 + 3] == raw[2 + 3]
    check p.map[0] == raw[2 + 511 * 8]
    check p.tiles[5].colours[0] == 5
    check int(p.tiles[2].cells[3]) == (2 * 25 + 3) mod 254
    check p.chars[10].data[7] == 87

  test "masks tile colours":
    var raw = bytesOf(files / "background.B")
    raw[2 + 4096 + 1] = 0x1f
    check parseSeuckB(raw).tiles[1].colours[0] == 0x0f

  test "writes the file we made":
    check readSeuckB(files / "background.B").toSeuckB == textOf(files / "background.B")

  test "sideways":
    let raw = bytesOf(files / "sideways.B")
    let p = readSeuckB(files / "sideways.B", sideways = true)
    check p.mapWidth == 819 and p.mapHeight == 5
    # Byte k: column 818 - k div 5, row 4 - k mod 5.
    check p.map[4 * 819 + 818] == raw[2]
    check p.map[0 * 819 + 818] == raw[2 + 4]
    check p.map[4 * 819 + 817] == raw[2 + 5]
    check p.map[0] == raw[2 + 4094]
    check p.chipColours[0] == 0x0b and p.colours[0] == 0x0d
    check p.toSeuckB(sideways = true) == textOf(files / "sideways.B")

  test "refusals say what doesn't fit":
    let p = readSeuckB(files / "background.B")
    var q = p
    q.colouring = cmPerChar
    expect SeuckError: discard q.toSeuckB
    q = p
    q.tiles.setLen 100
    expect SeuckError: discard q.toSeuckB
    q = p
    q.chars.setLen 253
    expect SeuckError: discard q.toSeuckB
    q = p
    q.mapHeight = 511
    expect SeuckError: discard q.toSeuckB
    q = p
    q.tileWidth = 4
    expect SeuckError: discard q.toSeuckB
    q = p
    q.map[0] = 256
    expect SeuckError: discard q.toSeuckB
    expect SeuckError: discard p.toSeuckB(sideways = true)
    expect SeuckError: discard parseSeuckB(newSeq[byte](9595))

  test "sideways pads fewer tiles and chars":
    var p = readSeuckB(files / "sideways.B", sideways = true)
    p.tiles.setLen 10
    p.chars.setLen 20
    let s = p.toSeuckB(sideways = true)
    check s.len == seuckBSize
    let q = parseSeuckB(s.toOpenArrayByte(0, s.high), sideways = true)
    check q.tiles.len == 128 and q.tiles[10].cells[0] == 0 and q.chars[20].data[0] == 0
    check q.chars[19].data == p.chars[19].data

  test "left out":
    var p = readSeuckB(files / "background.B")
    p.tiles[0].tag = 3
    p.chars[0].material = 2
    var leftOut: seq[string]
    discard p.toSeuckB(leftOut)
    check leftOut == @["tile tags and names", "char materials"]

proc allData(): string =
  ## A "save all data" file: signature, then the memory from $900 to $fff9
  ## with known bytes where the background and the sprites live.
  var all = newString(seuckISize)
  all[0] = 'B'
  let back = readFile(files / "background.B")
  let spr = readFile(files / "sprites.A")
  for i in 0 ..< 0x2680 - 0x900: all[2 + i] = back[2 + i]
  for i in 0 ..< 0x10000 - 6 - 0xf800: all[2 + 0xf800 - 0x900 + i] = back[2 + 0x2680 - 0x900 + i]
  for i in 0 ..< 127 * 64: all[2 + 0xc000 - 0x900 + i] = spr[2 + i]
  all

suite "SEUCK .P00 and .I":
  test "unwraps a .P00":
    let (name, body) = unwrapP00(readFile(files / "sprites.P00"))
    check name == "SPRITES.A" and name.seuckKind == 'A'
    check body == readFile(files / "sprites.A")
    check unwrapP00(readFile(files / "background.P00")).name.seuckKind == 'B'
    check "x.i".seuckKind == 'I' and "x.j".seuckKind == '\0' and "NAME.c".seuckKind == 'C' and "NAME.Z".seuckKind == '\0'
    check not isP00(readFile(files / "sprites.A"))

  test "a name that is not 'C64File' is not a .P00":
    expect SeuckError:
      discard unwrapP00("C64Fyle\0" & newString(30))

  test "the background and sprites inside a .I are the .B and .A":
    let all = allData()
    check all.len == 63228
    check seuckIBackground(all.toOpenArrayByte(0, all.high)) == readFile(files / "background.B")
    check seuckISprites(all.toOpenArrayByte(0, all.high)) == readFile(files / "sprites.A")
    check parseSeuckIBackground(all.toOpenArrayByte(0, all.high)).tiles.len == 128
    check parseSeuckISprites(all.toOpenArrayByte(0, all.high)).sprites[0].colour == 5

  test "a .I of another size is refused":
    expect SeuckError:
      discard seuckIBackground(newSeq[byte](100))
