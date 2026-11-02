## Indexed images with a 16 colour palette, `.pal` palette files and PNG,
## BMP and GIF output, for the previews of `png`, `bmp` and `gif` (docs/cli.md).

import std/[strutils, tables]

type
  ImageError* = object of ValueError

  Rgb* = array[3, uint8]
  Palette* = array[16, Rgb]

  Image* = object
    width*, height*: int
    pixels*: seq[uint8]   ## colour numbers 0-15, row by row

const vice*: Palette = [
  [0x00'u8, 0x00, 0x00], [0xff'u8, 0xff, 0xff], [0xaf'u8, 0x3c, 0x58], [0x7e'u8, 0xf3, 0xd6],
  [0xaa'u8, 0x40, 0xf5], [0x62'u8, 0xd5, 0x32], [0x2c'u8, 0x3d, 0xec], [0xff'u8, 0xff, 0x46],
  [0xb7'u8, 0x63, 0x1e], [0x77'u8, 0x53, 0x00], [0xee'u8, 0x7b, 0x95], [0x62'u8, 0x62, 0x62],
  [0x94'u8, 0x94, 0x94], [0xb7'u8, 0xff, 0x86], [0x73'u8, 0x85, 0xff], [0xcd'u8, 0xcd, 0xcd]]
  ## The default palette: the colours of VICE 3.9's internal VIC-II palette
  ## (read off x64sc's screenshot with its default colour settings, no filter).

proc newImage*(width, height: int, fill = 0'u8): Image =
  result = Image(width: width, height: height, pixels: newSeq[uint8](width * height))
  if fill != 0:
    for p in result.pixels.mitems: p = fill

proc parsePalette*(text: string): Palette =
  ## Sixteen colours as `#RRGGBB`, one per line, each with an optional name
  ## after it (`#6f4f25 "Brown"`). Blank lines and lines starting with `;` or
  ## `//` are skipped.
  var n = 0
  for raw in text.splitLines:
    let line = raw.strip
    if line == "" or line.startsWith(";") or line.startsWith("//"): continue
    let hex = line.split({' ', '\t'})[0]
    if n == 16: raise newException(ImageError, "a palette has 16 colours, found more")
    if hex.len != 7 or hex[0] != '#' or not hex[1 .. ^1].allCharsInSet(HexDigits):
      raise newException(ImageError, "colour " & $n & ": expected #RRGGBB, found " & hex)
    for i in 0 .. 2: result[n][i] = uint8(parseHexInt(hex[1 + 2 * i .. 2 + 2 * i]))
    inc n
  if n != 16: raise newException(ImageError, "a palette has 16 colours, found " & $n)

proc readPalette*(path: string): Palette =
  let text = try: readFile(path) except IOError: raise newException(ImageError, path & ": cannot open")
  try: parsePalette(text)
  except ImageError as e: raise newException(ImageError, path & ": " & e.msg)

proc crc32(data: string): uint32 =
  var table {.global.}: array[256, uint32]
  var ready {.global.} = false
  if not ready:
    for n in 0 ..< 256:
      var c = uint32(n)
      for _ in 0 ..< 8: c = if (c and 1) != 0: 0xedb88320'u32 xor (c shr 1) else: c shr 1
      table[n] = c
    ready = true
  result = 0xffffffff'u32
  for ch in data: result = table[(result xor uint32(ord(ch))) and 0xff] xor (result shr 8)
  result = not result

proc be32(v: uint32): string =
  for s in [24, 16, 8, 0]: result.add char((v shr s) and 0xff)

proc chunk(kind, data: string): string =
  be32(uint32(data.len)) & kind & data & be32(crc32(kind & data))

proc zlibStored(data: string): string =
  ## A zlib stream of stored (uncompressed) blocks.
  result = "\x78\x01"
  var i = 0
  while true:
    let n = min(0xffff, data.len - i)
    let last = i + n >= data.len
    result.add char(if last: 1 else: 0)
    result.add char(n and 0xff)
    result.add char(n shr 8)
    result.add char(not n and 0xff)
    result.add char((not n shr 8) and 0xff)
    result.add data[i ..< i + n]
    i += n
    if last: break
  var a = 1'u32
  var b = 0'u32
  for ch in data:
    a = (a + uint32(ord(ch))) mod 65521
    b = (b + a) mod 65521
  result.add be32((b shl 16) or a)

proc toPng*(img: Image, palette: openArray[Rgb], scale = 1): string =
  ## An 8 bit indexed PNG, each pixel `scale` times as wide and high. With 16
  ## colours (a C64 palette) pixels count modulo 16; with more (TED's 128)
  ## modulo the palette size, which must then be a power of two.
  if scale < 1 or scale > 64: raise newException(ImageError, "scale must be 1-64, not " & $scale)
  let (w, h) = (img.width * scale, img.height * scale)
  var raw = newStringOfCap((w + 1) * h)
  for y in 0 ..< h:
    raw.add '\0'
    for x in 0 ..< img.width:
      let c = char(img.pixels[(y div scale) * img.width + x] and uint8(palette.len - 1))
      for _ in 0 ..< scale: raw.add c
  var plte = ""
  for c in palette:
    for v in c: plte.add char(v)
  result = "\x89PNG\r\n\x1a\n" &
           chunk("IHDR", be32(uint32(w)) & be32(uint32(h)) & "\x08\x03\x00\x00\x00") &
           chunk("PLTE", plte) & chunk("IDAT", zlibStored(raw)) & chunk("IEND", "")

proc le32(v: int): string =
  for s in [0, 8, 16, 24]: result.add char((v shr s) and 0xff)

proc toBmp*(img: Image, palette: openArray[Rgb], scale = 1): string =
  ## An uncompressed 8 bit BMP (Windows BITMAPINFOHEADER) with `palette` as its
  ## colour table, each pixel `scale` times as wide and high; rows bottom
  ## first, padded to 4 bytes. Pixels count as in `toPng`.
  if scale < 1 or scale > 64: raise newException(ImageError, "scale must be 1-64, not " & $scale)
  let (w, h) = (img.width * scale, img.height * scale)
  let stride = (w + 3) and not 3
  let offset = 14 + 40 + 4 * palette.len
  result = "BM" & le32(offset + stride * h) & le32(0) & le32(offset) &
           le32(40) & le32(w) & le32(h) & "\x01\x00\x08\x00" & le32(0) & le32(stride * h) &
           le32(2835) & le32(2835) & le32(palette.len) & le32(0)
  for c in palette: result.add char(c[2]) & char(c[1]) & char(c[0]) & '\0'
  for y in countdown(h - 1, 0):
    for x in 0 ..< img.width:
      let c = char(img.pixels[(y div scale) * img.width + x] and uint8(palette.len - 1))
      for _ in 0 ..< scale: result.add c
    for _ in w ..< stride: result.add '\0'

proc lzw(pixels: openArray[uint8]): string =
  ## GIF's LZW for 4 bit pixels, as sub-blocks of at most 255 bytes.
  const (clear, eoi) = (16, 17)
  var bits = 0'u32
  var nbits = 0
  var bytes = ""
  proc put(code, size: int) =
    bits = bits or (uint32(code) shl nbits)
    nbits += size
    while nbits >= 8:
      bytes.add char(bits and 0xff)
      bits = bits shr 8
      nbits -= 8
  var table = initTable[int, int]()
  var next = 18
  var size = 5
  put(clear, size)
  var prefix = -1
  for p in pixels:
    if prefix < 0:
      prefix = int(p)
      continue
    let key = prefix * 16 + int(p)
    if key in table:
      prefix = table[key]
    else:
      put(prefix, size)
      if next < 4096:
        table[key] = next
        if next == (1 shl size): inc size
        inc next
      else:
        put(clear, size)
        table.clear
        next = 18
        size = 5
      prefix = int(p)
  if prefix >= 0: put(prefix, size)
  put(eoi, size)
  if nbits > 0: bytes.add char(bits and 0xff)
  for i in countup(0, bytes.high, 255):
    let n = min(255, bytes.len - i)
    result.add char(n)
    result.add bytes[i ..< i + n]
  result.add '\0'

proc le16(v: int): string = $char(v and 0xff) & $char((v shr 8) and 0xff)

proc toGif*(frames: seq[Image], palette: Palette, delay: int, scale = 1): string =
  ## An animated GIF that plays the `frames`, all of one size, `delay`
  ## hundredths of a second each, and repeats.
  if frames.len == 0: raise newException(ImageError, "no frames")
  if scale < 1 or scale > 64: raise newException(ImageError, "scale must be 1-64, not " & $scale)
  let (w, h) = (frames[0].width * scale, frames[0].height * scale)
  result = "GIF89a" & le16(w) & le16(h) & "\xf3\0\0"   # a 16 colour global table
  for c in palette:
    for v in c: result.add char(v)
  result.add "\x21\xff\x0bNETSCAPE2.0\x03\x01\0\0\0"
  for f in frames:
    if (f.width * scale, f.height * scale) != (w, h): raise newException(ImageError, "frames of different sizes")
    result.add "\x21\xf9\x04\x00" & le16(delay) & "\0\0"
    result.add "\x2c" & le16(0) & le16(0) & le16(w) & le16(h) & "\0\x04"
    var pixels = newSeqOfCap[uint8](w * h)
    for y in 0 ..< h:
      for x in 0 ..< f.width:
        let c = f.pixels[(y div scale) * f.width + x] and 0x0f
        for _ in 0 ..< scale: pixels.add c
    result.add lzw(pixels)
  result.add ';'
