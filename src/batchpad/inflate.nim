## Decompression of zlib (RFC 1950), gzip (RFC 1952) and raw deflate (RFC 1951)
## data, for the compressed layers of Tiled maps. Reading only; the Nim standard
## library has no zlib.

type InflateError* = object of CatchableError

type
  BitReader = object
    data: string
    pos: int          ## next byte
    bits: uint32      ## bits not used yet, lowest first
    count: int        ## how many of them

  Huffman = object
    counts: array[16, int]     ## codes per length
    symbols: seq[int]          ## symbols ordered by code

proc fail(msg: string) {.noreturn.} = raise newException(InflateError, msg)

proc need(r: var BitReader, n: int) =
  while r.count < n:
    if r.pos >= r.data.len: fail("compressed data ends too soon")
    r.bits = r.bits or (uint32(r.data[r.pos].byte) shl r.count)
    inc r.pos
    r.count += 8

proc take(r: var BitReader, n: int): int =
  if n == 0: return 0
  r.need n
  result = int(r.bits and ((1'u32 shl n) - 1))
  r.bits = r.bits shr n
  r.count -= n

proc build(lengths: openArray[int]): Huffman =
  for l in lengths: inc result.counts[l]
  result.counts[0] = 0
  var left = 1
  for len in 1 .. 15:
    left = left * 2 - result.counts[len]
    if left < 0: fail("bad Huffman code lengths")
  var offsets: array[17, int]
  for len in 1 .. 15: offsets[len + 1] = offsets[len] + result.counts[len]
  result.symbols = newSeq[int](lengths.len)
  for sym, l in lengths:
    if l != 0:
      result.symbols[offsets[l]] = sym
      inc offsets[l]

proc decode(r: var BitReader, h: Huffman): int =
  var code, first, index = 0
  for len in 1 .. 15:
    code = code or r.take(1)
    let c = h.counts[len]
    if code - c < first: return h.symbols[index + (code - first)]
    index += c
    first += c
    first = first shl 1
    code = code shl 1
  fail("bad Huffman code in the compressed data")

const
  lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
                67, 83, 99, 115, 131, 163, 195, 227, 258]
  lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
  distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
              1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
  distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
  codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

proc codes(r: var BitReader, output: var string, lit, dist: Huffman, limit: int) =
  while true:
    let sym = r.decode(lit)
    if sym < 256:
      output.add char(sym)
    elif sym == 256:
      return
    else:
      let li = sym - 257
      if li >= 29: fail("bad length code in the compressed data")
      let length = lengthBase[li] + r.take(lengthExtra[li])
      let di = r.decode(dist)
      if di >= 30: fail("bad distance code in the compressed data")
      let distance = distBase[di] + r.take(distExtra[di])
      if distance > output.len: fail("the compressed data points before its start")
      for _ in 1 .. length: output.add output[output.len - distance]
    if output.len > limit: fail("the compressed data is larger than expected")

proc inflateRaw(r: var BitReader, limit: int): string =
  var fixedLit, fixedDist: Huffman
  var haveFixed = false
  while true:
    let last = r.take(1)
    case r.take(2)
    of 0:
      r.bits = 0
      r.count = 0
      if r.pos + 4 > r.data.len: fail("compressed data ends too soon")
      let n = int(r.data[r.pos].byte) or (int(r.data[r.pos + 1].byte) shl 8)
      let inv = int(r.data[r.pos + 2].byte) or (int(r.data[r.pos + 3].byte) shl 8)
      if n != (inv xor 0xffff): fail("bad stored block in the compressed data")
      r.pos += 4
      if r.pos + n > r.data.len: fail("compressed data ends too soon")
      result.add r.data[r.pos ..< r.pos + n]
      r.pos += n
    of 1:
      if not haveFixed:
        var l = newSeq[int](288)
        for i in 0 ..< 144: l[i] = 8
        for i in 144 ..< 256: l[i] = 9
        for i in 256 ..< 280: l[i] = 7
        for i in 280 ..< 288: l[i] = 8
        fixedLit = build(l)
        var d = newSeq[int](30)
        for i in 0 ..< 30: d[i] = 5
        fixedDist = build(d)
        haveFixed = true
      codes(r, result, fixedLit, fixedDist, limit)
    of 2:
      let nlen = r.take(5) + 257
      let ndist = r.take(5) + 1
      let ncode = r.take(4) + 4
      if nlen > 286 or ndist > 30: fail("bad dynamic block in the compressed data")
      var lengths = newSeq[int](19)
      for i in 0 ..< ncode: lengths[codeLengthOrder[i]] = r.take(3)
      let clen = build(lengths)
      var all = newSeq[int](nlen + ndist)
      var i = 0
      while i < nlen + ndist:
        let sym = r.decode(clen)
        if sym < 16:
          all[i] = sym
          inc i
        else:
          var prev = 0
          var rep: int
          if sym == 16:
            if i == 0: fail("bad dynamic block in the compressed data")
            prev = all[i - 1]
            rep = 3 + r.take(2)
          elif sym == 17: rep = 3 + r.take(3)
          else: rep = 11 + r.take(7)
          if i + rep > nlen + ndist: fail("bad dynamic block in the compressed data")
          for _ in 1 .. rep:
            all[i] = prev
            inc i
      if all[256] == 0: fail("bad dynamic block in the compressed data")
      codes(r, result, build(all[0 ..< nlen]), build(all[nlen ..< nlen + ndist]), limit)
    else:
      fail("bad block type in the compressed data")
    if result.len > limit: fail("the compressed data is larger than expected")
    if last == 1: return

proc unzlib*(data: string, limit = 1 shl 28): string =
  ## Decompresses zlib data (a 2 byte header, deflate, an Adler-32 we don't check).
  if data.len < 6: fail("zlib data is too short")
  let cmf = data[0].byte
  let flg = data[1].byte
  if (cmf and 15) != 8 or ((int(cmf) shl 8) or int(flg)) mod 31 != 0:
    fail("not zlib data")
  if (flg and 32) != 0: fail("zlib data with a preset dictionary isn't supported")
  var r = BitReader(data: data, pos: 2)
  inflateRaw(r, limit)

proc ungzip*(data: string, limit = 1 shl 28): string =
  ## Decompresses gzip data (header, deflate, CRC-32 and size we don't check).
  if data.len < 18 or data[0].byte != 0x1f or data[1].byte != 0x8b or data[2].byte != 8:
    fail("not gzip data")
  let flags = data[3].byte
  var pos = 10
  if (flags and 4) != 0:
    if pos + 2 > data.len: fail("gzip data is too short")
    pos += 2 + int(data[pos].byte) + (int(data[pos + 1].byte) shl 8)
  for bit in [8'u8, 16]:           # file name, comment: zero terminated
    if (flags and bit) != 0:
      while pos < data.len and data[pos] != '\0': inc pos
      inc pos
  if (flags and 2) != 0: pos += 2
  if pos >= data.len: fail("gzip data is too short")
  var r = BitReader(data: data, pos: pos)
  inflateRaw(r, limit)
