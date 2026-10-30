import std/[sequtils, strutils, unittest]
import batchpad/[ctm, image, preview, spd]

proc be32(s: string, at: int): int =
  for i in 0 .. 3: result = result * 256 + ord(s[at + i])

proc decode(png: string): tuple[width, height: int, rows: seq[string], palette: string] =
  ## Reads back what `toPng` writes: stored blocks, no filters.
  check png.startsWith("\x89PNG\r\n\x1a\n")
  var at = 8
  var idat = ""
  while at < png.len:
    let n = be32(png, at)
    let kind = png[at + 4 .. at + 7]
    let data = png[at + 8 ..< at + 8 + n]
    case kind
    of "IHDR":
      result.width = be32(data, 0)
      result.height = be32(data, 4)
      check data[8 .. 12] == "\x08\x03\x00\x00\x00"
    of "PLTE": result.palette = data
    of "IDAT": idat.add data
    else: discard
    at += 12 + n
  var raw = ""
  var i = 2   # after the zlib header
  while true:
    let last = idat[i] == '\x01'
    let n = ord(idat[i + 1]) + 256 * ord(idat[i + 2])
    check ord(idat[i + 3]) == ((not n) and 0xff)
    raw.add idat[i + 5 ..< i + 5 + n]
    i += 5 + n
    if last: break
  for y in 0 ..< result.height:
    check raw[y * (result.width + 1)] == '\0'
    result.rows.add raw[y * (result.width + 1) + 1 ..< (y + 1) * (result.width + 1)]

proc px(img: Image, x, y: int): int = int(img.pixels[y * img.width + x])

func row(img: Image, y, x0, n: int): seq[int] =
  for x in x0 ..< x0 + n: result.add int(img.pixels[y * img.width + x])

proc charProject(mode: DisplayMode, colouring = cmPerProject): ctm.Project =
  result = ctm.Project(version: 9, displayMode: mode, colouring: colouring,
                       chipColours: [6'u8, 11, 12, 13], colours: [14'u8, 3, 4])
  # Char 0: 00 01 10 11 across the first row, then the same as bits 1 0 1 0 ...
  result.chars = @[Char(data: [0b00011011'u8, 0b10101010, 0, 0, 0, 0, 0, 0],
                        colours: [9'u8, 5, 7]),
                   Char(data: [0xff'u8, 0, 0, 0, 0, 0, 0, 0], colours: [2'u8, 0, 0])]

suite "palettes":
  test "the colours, names and comments":
    var text = "; Pepto\n"
    for i in 0 .. 15: text.add "#" & toHex(i * 16 + 1, 2) & "0203" & (if i == 3: " \"Cyan\"\n" else: "\n")
    let p = parsePalette(text & "\n")
    check p[0] == [1'u8, 2, 3] and p[3] == [0x31'u8, 2, 3] and p[15] == [0xf1'u8, 2, 3]

  test "mistakes":
    expect ImageError: discard parsePalette("#000000\n")
    expect ImageError: discard parsePalette("#00000\n".repeat(16))
    expect ImageError: discard parsePalette("000000\n".repeat(16))
    expect ImageError: discard parsePalette("#00000g\n".repeat(16))
    expect ImageError: discard parsePalette("#000000\n".repeat(17))
    expect ImageError: discard readPalette("/nonexistent.pal")

suite "PNG":
  test "indexed, scaled":
    var img = newImage(3, 2)
    img.pixels = @[0'u8, 1, 2, 15, 7, 3]
    let d = decode(img.toPng(pepto, 2))
    check (d.width, d.height) == (6, 4)
    check d.rows[0] == "\0\0\1\1\2\2"
    check d.rows[1] == d.rows[0]
    check d.rows[3] == "\x0f\x0f\7\7\3\3"
    check d.palette.len == 48 and d.palette[3 .. 5] == "\xff\xff\xff"
    expect ImageError: discard img.toPng(pepto, 0)

  test "bigger than one stored block":
    let img = newImage(300, 300, 5)
    let d = decode(img.toPng(pepto))
    check d.rows.len == 300 and d.rows[299] == "\5".repeat(300)

proc lzwDecode(data: string): seq[int] =
  ## GIF's LZW, minimum code size 4, from the sub-blocks' bytes.
  var table: seq[seq[int]]
  proc reset() =
    table = @[]
    for i in 0 .. 17: table.add @[i]
  reset()
  var size = 5
  var bits = 0
  var nbits = 0
  var prev: seq[int]
  for ch in data:
    bits = bits or (ord(ch) shl nbits)
    nbits += 8
    while nbits >= size:
      let code = bits and ((1 shl size) - 1)
      bits = bits shr size
      nbits -= size
      if code == 16:
        reset()
        size = 5
        prev = @[]
      elif code == 17:
        return
      else:
        var entry: seq[int]
        if code < table.len: entry = table[code]
        else: entry = prev & prev[0]   # the code about to be defined
        result.add entry
        if prev.len > 0: table.add prev & entry[0]
        prev = entry
        if table.len == (1 shl size) and size < 12: inc size

proc decodeGif(gif: string): tuple[width, height: int, delays: seq[int], frames: seq[seq[int]]] =
  check gif.startsWith("GIF89a")
  result.width = ord(gif[6]) + 256 * ord(gif[7])
  result.height = ord(gif[8]) + 256 * ord(gif[9])
  check gif[10] == '\xf3'
  var at = 13 + 48
  proc blocks(): string =
    while gif[at] != '\0':
      let n = ord(gif[at])
      result.add gif[at + 1 ..< at + 1 + n]
      at += n + 1
    inc at
  while gif[at] != ';':
    case gif[at]
    of '\x21':
      let label = gif[at + 1]
      at += 2
      let data = blocks()
      if label == '\xf9': result.delays.add ord(data[1]) + 256 * ord(data[2])
    of '\x2c':
      check gif[at + 9 .. at + 10] == "\0\x04"
      at += 11
      result.frames.add lzwDecode(blocks())
    else:
      check false
      break

suite "GIF":
  test "frames, delay and loop":
    var a = newImage(3, 2)
    a.pixels = @[0'u8, 1, 2, 3, 4, 5]
    var b = newImage(3, 2, 15)
    let d = decodeGif(toGif(@[a, b], pepto, 7, 2))
    check (d.width, d.height) == (6, 4)
    check d.delays == @[7, 7]
    check d.frames[1] == newSeqWith(24, 15)
    check d.frames[0][0 .. 5] == @[0, 0, 1, 1, 2, 2]
    check d.frames[0][18 .. 23] == @[3, 3, 4, 4, 5, 5]
    check "NETSCAPE2.0" in toGif(@[a], pepto, 7)

  test "long frames: the code size grows and the table is reset":
    var img = newImage(150, 150)
    var x = 12345'u32
    for p in img.pixels.mitems:
      x = x * 1664525 + 1013904223
      p = uint8((x shr 24) and 15)
    let d = decodeGif(toGif(@[img], pepto, 2))
    check d.frames[0].len == 150 * 150
    check d.frames[0] == img.pixels.mapIt(int(it))
    var flat = newImage(200, 200, 3)
    check decodeGif(toGif(@[flat], pepto, 2)).frames[0] == newSeqWith(40000, 3)

  test "mistakes":
    expect ImageError: discard toGif(@[], pepto, 2)
    expect ImageError: discard toGif(@[newImage(2, 2), newImage(3, 2)], pepto, 2)
    expect ImageError: discard toGif(@[newImage(2, 2)], pepto, 2, 0)

suite "CharPad previews":
  test "hires text: the char's colour on $d021":
    var p = charProject(dmHiresText, cmPerChar)
    let img = p.previewCtm("chars")
    check (img.width, img.height) == (16, 8)
    check img.row(0, 0, 8) == @[6, 6, 6, 9, 9, 6, 9, 9]   # 00011011 in colour 9
    check img.row(0, 8, 8) == @[2, 2, 2, 2, 2, 2, 2, 2]
    p.colouring = cmPerProject
    check p.previewCtm("chars").row(0, 0, 8)[3] == 14

  test "multicolour text: colour 8-15 is multicolour, 0-7 is hires":
    var p = charProject(dmMulticolourText, cmPerChar)
    let img = p.previewCtm("chars")
    # 00 01 10 11: $d021, $d022, $d023, the colour's low three bits.
    check img.row(0, 0, 8) == @[6, 6, 11, 11, 12, 12, 1, 1]
    check img.row(1, 0, 8) == @[12, 12, 12, 12, 12, 12, 12, 12]   # 10 10 10 10
    check img.row(0, 8, 8) == @[2, 2, 2, 2, 2, 2, 2, 2]   # colour 2: hires

  test "ECM: the char number picks the background":
    var p = charProject(dmEcmText, cmPerProject)
    p.chars.setLen 2
    for i in 0 .. 63: p.chars.add Char()
    p.chars[65] = Char(data: [0xff'u8, 0, 0, 0, 0, 0, 0, 0])
    let img = p.previewCtm("chars")
    # Char 1 is in the first bank, char 65 shows char 1's shape on $d022.
    check img.row(0, 8, 8) == @[14, 14, 14, 14, 14, 14, 14, 14]
    check img.row(1, 8, 8) == @[6, 6, 6, 6, 6, 6, 6, 6]
    check img.px(65 mod 16 * 8, 4 * 8 + 1) == 11

  test "hires bitmap: screen nibbles":
    var p = charProject(dmHiresBitmap, cmPerChar)
    p.chars[0].colours = [0'u8, 5, 7]    # low nibble 5 for 0 bits, high 7 for 1 bits
    check p.previewCtm("chars").row(0, 0, 8) == @[5, 5, 5, 7, 7, 5, 7, 7]

  test "multicolour bitmap: $d021, high nibble, low nibble, colour RAM":
    var p = charProject(dmMulticolourBitmap, cmPerChar)
    p.chars[0].colours = [9'u8, 5, 7]
    check p.previewCtm("chars").row(0, 0, 8) == @[6, 6, 7, 7, 5, 5, 9, 9]

  test "tiles and map with per tile colours":
    var p = charProject(dmHiresText, cmPerTile)
    p.tileSystem = true
    p.tileWidth = 2
    p.tileHeight = 1
    p.tiles = @[Tile(cells: @[1'u16, 0], colours: [10'u8, 0, 0]),
                Tile(cells: @[0'u16, 1], colours: [11'u8, 0, 0])]
    p.mapWidth = 2
    p.mapHeight = 1
    p.map = @[1'u16, 0]
    let tiles = p.previewCtm("tiles", columns = 1)
    check (tiles.width, tiles.height) == (16, 16)
    check tiles.row(0, 0, 8) == @[10, 10, 10, 10, 10, 10, 10, 10]
    check tiles.row(8, 8, 8) == @[11, 11, 11, 11, 11, 11, 11, 11]
    let map = p.previewCtm("map")
    check (map.width, map.height) == (32, 8)
    check map.row(0, 0, 4) == @[6, 6, 6, 11]
    check map.row(0, 16, 12) == @[10, 10, 10, 10, 10, 10, 10, 10, 6, 6, 6, 10]
    p.map[1] = 5   # no such tile: left as the background
    check p.previewCtm("map").row(0, 16, 16) == newSeqWith(16, 6)

  test "mistakes":
    let p = charProject(dmHiresText)
    expect PreviewError: discard p.previewCtm("tiles")
    expect PreviewError: discard p.previewCtm("map")
    expect PreviewError: discard p.previewCtm("sprites")

suite "SpritePad previews":
  proc sprites(): SpriteProject =
    result = SpriteProject(version: 5, colours: [1'u8, 2, 3], tileSystem: true,
                           tileWidth: 2, tileHeight: 1)
    var hires = Sprite(attributes: 0x05)
    var multi = Sprite(attributes: 0x87)
    hires.data[0] = 0b10100000
    multi.data[0] = 0b00011011
    result.sprites = @[hires, multi]
    result.tiles = @[SpriteTile(cells: @[1'u16, 0])]

  test "hires and multicolour":
    let img = sprites().previewSpd("sprites")
    check (img.width, img.height) == (48, 21)
    check img.row(0, 0, 4) == @[5, 1, 5, 1]
    check img.row(1, 0, 4) == @[1, 1, 1, 1]
    # 00 01 10 11: background, multicolour 1, the sprite's colour, multicolour 2.
    check img.row(0, 24, 8) == @[1, 1, 2, 2, 7, 7, 3, 3]

  test "tiles":
    let img = sprites().previewSpd("tiles")
    check (img.width, img.height) == (48, 21)
    check img.row(0, 0, 8) == @[1, 1, 2, 2, 7, 7, 3, 3]
    check img.row(0, 24, 4) == @[5, 1, 5, 1]

  test "animation order":
    check Animation(first: 2, last: 4).order == @[2, 3, 4]
    check Animation(first: 4, last: 2).order == @[4, 3, 2]
    check Animation(first: 3, last: 3).order == @[3]
    check Animation(first: 1, last: 4, attributes: 0x10).order == @[1, 2, 3, 4, 3, 2]
    check Animation(first: 1, last: 2, attributes: 0x10).order == @[1, 2]

  test "animation frames, with overlays":
    var p = sprites()
    p.spriteOverlay = 1
    p.sprites[0].attributes = 0x15           # overlay: sprite 1 over it
    p.spriteAnims = @[Animation(first: 0, last: 1, attributes: 0x10), Animation(first: 1, last: 1)]
    p.tileAnims = @[Animation(first: 0, last: 0)]
    let frames = p.animationFrames(false, 0)
    check frames.len == 2       # ping-pong over two frames adds nothing
    # Sprite 1 is drawn over sprite 0, its 00 pixels transparent.
    check frames[0].row(0, 0, 8) == @[5, 1, 2, 2, 7, 7, 3, 3]
    check frames[1].row(0, 0, 4) == @[1, 1, 2, 2]
    check p.animationFrames(true, 0).len == 1
    check p.animationFrames(true, 0)[0].width == 48
    expect PreviewError: discard p.animationFrames(false, 2)
    p.spriteAnims[1].last = 9
    expect PreviewError: discard p.animationFrames(false, 1)

  test "mistakes":
    var p = sprites()
    expect PreviewError: discard p.previewSpd("map")
    p.tileSystem = false
    expect PreviewError: discard p.previewSpd("tiles")
