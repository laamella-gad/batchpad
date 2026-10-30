## Indexed images with a 16 colour palette, `.pal` palette files and PNG
## output, for the previews of `png` (docs/cli.md).

import std/[strutils]

type
  ImageError* = object of ValueError

  Rgb* = array[3, uint8]
  Palette* = array[16, Rgb]

  Image* = object
    width*, height*: int
    pixels*: seq[uint8]   ## colour numbers 0-15, row by row

const pepto*: Palette = [
  [0x00'u8, 0x00, 0x00], [0xff'u8, 0xff, 0xff], [0x68'u8, 0x37, 0x2b], [0x70'u8, 0xa4, 0xb2],
  [0x6f'u8, 0x3d, 0x86], [0x58'u8, 0x8d, 0x43], [0x35'u8, 0x28, 0x79], [0xb8'u8, 0xc7, 0x6f],
  [0x6f'u8, 0x4f, 0x25], [0x43'u8, 0x39, 0x00], [0x9a'u8, 0x67, 0x59], [0x44'u8, 0x44, 0x44],
  [0x6c'u8, 0x6c, 0x6c], [0x9a'u8, 0xd2, 0x84], [0x6c'u8, 0x5e, 0xb5], [0x95'u8, 0x95, 0x95]]
  ## Pepto's colours, the default.

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

proc toPng*(img: Image, palette: Palette, scale = 1): string =
  ## An 8 bit indexed PNG, each pixel `scale` times as wide and high.
  if scale < 1 or scale > 64: raise newException(ImageError, "scale must be 1-64, not " & $scale)
  let (w, h) = (img.width * scale, img.height * scale)
  var raw = newStringOfCap((w + 1) * h)
  for y in 0 ..< h:
    raw.add '\0'
    for x in 0 ..< img.width:
      let c = char(img.pixels[(y div scale) * img.width + x] and 0x0f)
      for _ in 0 ..< scale: raw.add c
  var plte = ""
  for c in palette:
    for v in c: plte.add char(v)
  result = "\x89PNG\r\n\x1a\n" &
           chunk("IHDR", be32(uint32(w)) & be32(uint32(h)) & "\x08\x03\x00\x00\x00") &
           chunk("PLTE", plte) & chunk("IDAT", zlibStored(raw)) & chunk("IEND", "")
