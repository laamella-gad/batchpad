import std/[os, sequtils, unittest]
import batchpad/[ctm, image, picture, preview, spd]

const files = currentSourcePath().parentDir / "files"

proc bmp(name: string): Image =
  parseBmp(readFile(files / "bmp" / name)).quantise(vice)

proc mostUsedColour(img: Image): uint8 =
  var counts: array[16, int]
  for p in img.pixels: inc counts[p]
  uint8(counts.maxIndex)

proc le16(v: int): string = $char(v and 0xff) & $char((v shr 8) and 0xff)
proc le32(v: int): string = le16(v and 0xffff) & le16((v shr 16) and 0xffff)

proc windows(w, h, bpp, compression: int, extra, palette, pixels: string): string =
  ## A BMP with a 40 byte header; `extra` goes between header and palette.
  let offset = 14 + 40 + extra.len + palette.len
  "BM" & le32(offset + pixels.len) & le32(0) & le32(offset) & le32(40) & le32(w) & le32(h) &
    le16(1) & le16(bpp) & le32(compression) & le32(pixels.len) & le32(0) & le32(0) &
    le32(0) & le32(0) & extra & palette & pixels

suite "BMP":
  test "pictures saved by ImageMagick 6.9":
    let mc = readCtm(files / "ctm9" / "mctext_pertile.ctm").previewCtm("map")
    for name in ["mc4.bmp", "mc24.bmp", "mc32.bmp", "mcos2.bmp"]:
      checkpoint name
      check bmp(name) == mc
    # in black and white
    var hires = readCtm(files / "ctm9" / "hirestext_perchar_notiles.ctm").previewCtm("map")
    for p in hires.pixels.mitems: p = min(p, 1)
    check bmp("hires1.bmp") == hires
    check bmp("sprites.bmp") == readSpd(files / "spd5" / "sprites.spd").previewSpd("sprites", 3)

  test "PNGs saved by ImageMagick 6.9":
    let mc = readCtm(files / "ctm9" / "mctext_pertile.ctm").previewCtm("map")
    for name in ["mc4.png", "mc8.png", "mc24.png", "mc32.png", "mc48.png", "mcinter.png"]:
      checkpoint name
      check parsePicture(readFile(files / "png" / name)).quantise(vice) == mc
    var hires = readCtm(files / "ctm9" / "hirestext_perchar_notiles.ctm").previewCtm("map")
    for p in hires.pixels.mitems: p = min(p, 1)
    check parsePng(readFile(files / "png" / "hires1.png")).quantise(vice) == hires
    # and what we write
    check parsePicture(mc.toPng(vice, 2)).quantise(vice, 2) == mc
    check parsePicture(mc.toBmp(vice)).quantise(vice) == mc

  test "PNG refusals":
    let good = readFile(files / "png" / "mc24.png")
    expect PictureError: discard parsePng("GIF89a")
    expect PictureError: discard parsePicture("GIF89a")
    expect PictureError: discard parsePng(good[0 ..< 40])                # ends early
    var bad = good
    bad[8 + 8 + 9] = '\x05'                                             # colour type 5
    expect PictureError: discard parsePng(bad)
    bad = good
    bad[8 + 8 + 8] = '\x03'                                             # 3 bits
    expect PictureError: discard parsePng(bad)

  test "what we write reads back":
    let mc = readCtm(files / "ctm9" / "mctext_pertile.ctm").previewCtm("map")
    check parseBmp(mc.toBmp(vice)).quantise(vice) == mc
    check parseBmp(mc.toBmp(vice, 3)).quantise(vice, 3) == mc
    expect PictureError: discard parseBmp(mc.toBmp(vice, 3)).quantise(vice, 5)

  test "8 and 16 bits, top row first":
    # 2 x 2: red, white / black, cyan; 8 bit rows padded to 4 bytes
    let pal = "\x58\x3c\xaf\0" & "\xff\xff\xff\0" & "\0\0\0\0" & "\xd6\xf3\x7e\0"
    let eight = windows(2, 2, 8, 0, "", pal, "\x02\x03\0\0" & "\x00\x01\0\0")
    let want = Image(width: 2, height: 2, pixels: @[2'u8, 1, 0, 3])
    check parseBmp(eight).quantise(vice) == want
    # top-down: negative height
    let down = windows(2, -2 and 0xffffffff, 8, 0, "", pal, "\x00\x01\0\0" & "\x02\x03\0\0")
    check parseBmp(down).quantise(vice) == want
    # 16 bit 5-5-5, and 5-6-5 with bit fields
    proc c555(r, g, b: int): string = le16((r shr 3) shl 10 or (g shr 3) shl 5 or (b shr 3))
    proc c565(r, g, b: int): string = le16((r shr 3) shl 11 or (g shr 2) shl 5 or (b shr 3))
    let s555 = windows(2, 2, 16, 0, "", "", c555(0, 0, 0) & c555(0x7e, 0xf3, 0xd6) &
                       c555(0xaf, 0x3c, 0x58) & c555(255, 255, 255))
    check parseBmp(s555).quantise(vice) == want
    let s565 = windows(2, 2, 16, 3, le32(0xf800) & le32(0x07e0) & le32(0x001f), "",
                       c565(0, 0, 0) & c565(0x7e, 0xf3, 0xd6) & c565(0xaf, 0x3c, 0x58) &
                       c565(255, 255, 255))
    check parseBmp(s565).quantise(vice) == want

  test "refusals":
    let pal = "\0\0\0\0\xff\xff\xff\0"
    expect PictureError: discard parseBmp("GIF89a")
    expect PictureError: discard parseBmp(windows(2, 2, 8, 1, "", pal, "\0\0\0\0"))   # RLE
    expect PictureError: discard parseBmp(windows(2, 2, 8, 0, "", pal, "\0\0"))       # short
    expect PictureError: discard parseBmp(windows(2, 1, 8, 0, "", pal, "\x05\0\0\0")) # colour 5
    expect PictureError: discard parseBmp(windows(2, 1, 2, 0, "", pal, "\0\0\0\0"))   # 2 bits

suite "Pictures to projects":
  test "hires chars come back as they were":
    let p = readCtm(files / "ctm9" / "hirestext_perchar_notiles.ctm")
    let img = p.previewCtm("map")
    var base = ctm.Project(version: 9, displayMode: dmHiresText)
    let q = img.charsFromPicture(base, Fixed())
    check q.colouring == cmPerChar and not q.tileSystem
    check q.mapWidth == p.mapWidth and q.mapHeight == p.mapHeight
    check q.previewCtm("map") == img
    check q.chars.len <= p.chars.len

  test "multicolour chars: the shared colours are the most used":
    let p = readCtm(files / "ctm9" / "mctext_pertile.ctm")
    let img = p.previewCtm("map")
    var base = ctm.Project(version: 9, displayMode: dmMulticolourText)
    # with the project's own shared colours it comes back as it was
    base.chipColours = p.chipColours
    let q = img.charsFromPicture(base, Fixed(colours: [true, true, true, false]))
    check q.previewCtm("map") == img
    # picked: background first
    let picked = img.charsFromPicture(base, Fixed())
    check picked.chipColours[0] == img.mostUsedColour
    # a given colour stays
    base.chipColours[0] = 2
    let r = img.charsFromPicture(base, Fixed(colours: [true, false, false, false]))
    check r.chipColours[0] == 2

  test "equal cells share a char, edges are padded":
    var img = newImage(20, 9, 6)       # 3 x 2 cells, blue
    img.pixels[0] = 1                  # one white pixel in cell 0
    let q = img.charsFromPicture(ctm.Project(displayMode: dmHiresText), Fixed())
    check q.chipColours[0] == 6 and q.mapWidth == 3 and q.mapHeight == 2
    check q.chars.len == 2 and q.map == @[0'u16, 1, 1, 1, 1, 1]
    check q.chars[0].data[0] == 0x80 and q.chars[0].colours[0] == 1

  test "sprites, hires or multicolour each":
    let p = readSpd(files / "spd5" / "sprites.spd")
    let img = p.previewSpd("sprites", 3)
    let q = img.spritesFromPicture(p, Fixed(colours: [true, true, true, false]), true, true)
    check q.sprites.len == p.sprites.len
    check q.previewSpd("sprites", 3) == img
    for i in 0 ..< q.sprites.len:
      check q.sprites[i].data == p.sprites[i].data
    let h = img.spritesFromPicture(p, Fixed(), true, false)
    for s in h.sprites: check not s.multicolour

  test "tiles from a tileset picture":
    var img = newImage(32, 8, 0)
    img.pixels[0] = 1                  # chars 0 and 1 differ, 2 and 3 are equal to 1
    var q = img.charsFromPicture(ctm.Project(displayMode: dmHiresText), Fixed())
    check q.map == @[0'u16, 1, 1, 1]
    let t = q.intoTiles(2, 1)
    check t.tileSystem and t.tileWidth == 2 and t.tileHeight == 1
    check t.mapWidth == 2 and t.mapHeight == 1 and t.map == @[0'u16, 1]
    check t.tiles.len == 2 and t.tiles[0].cells == @[0'u16, 1] and t.tiles[1].cells == @[1'u16, 1]
    check t.previewCtm("map") == q.previewCtm("map")
    expect PictureError: discard q.intoTiles(3, 1)

  test "only text modes":
    expect PictureError:
      discard newImage(8, 8).charsFromPicture(ctm.Project(displayMode: dmEcmText), Fixed())
