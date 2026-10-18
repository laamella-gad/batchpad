import std/[os, strutils, unittest]
import batchpad/spd

proc v5(flags, sprites, tiles, spriteAnims, tileAnims, width, height: int,
        body: seq[byte]): seq[byte] =
  result = @[byte('S'), byte('P'), byte('D'), 5, byte(flags),
             byte(sprites and 0xff), byte(sprites shr 8), byte(tiles and 0xff), byte(tiles shr 8),
             byte(spriteAnims), byte(tileAnims), byte(width), byte(height),
             6, 10, 3, 0xfe, 0xff, 1, 0]
  result.add body

proc rows(f: proc (x, y: int): bool): array[63, uint8] =
  for y in 0..20:
    for x in 0..23:
      if f(x, y): result[3 * y + x div 8] = result[3 * y + x div 8] or (0x80'u8 shr (x mod 8))

let
  box = rows(proc (x, y: int): bool = x in [0, 23] or y in [0, 20])
  diagonal = rows(proc (x, y: int): bool = x == y)

suite "SPD V1":
  const dir = currentSourcePath().parentDir / "files" / "spd1"

  test "sprites":
    let p = readSpd(dir / "sprites.spd")
    check p.version == 1
    check p.colours == [6'u8, 10, 3]
    check p.spriteOverlay == 1 and p.tileOverlay == 1
    check p.sprites.len == 6
    check p.sprites[0].data == box
    check p.sprites[3].data == diagonal
    check not p.tileSystem and p.tiles.len == 0 and p.tileAnims.len == 0
    let s = p.sprites
    check s[0].colour == 1 and not s[0].multicolour
    check s[1].colour == 5 and s[1].multicolour and not s[1].overlay
    check s[2].colour == 11 and s[2].multicolour and s[2].overlay
    check s[4].colour == 14 and not s[4].multicolour
    check s[5].colour == 4 and s[5].multicolour
    check p.spriteAnims == @[Animation(first: 0, last: 5, timer: 4, attributes: 0x80)]

  test "animations":
    let p = readSpd(dir / "anims.spd")
    check p.colours == [0'u8, 2, 8]
    check p.sprites.len == 6
    check p.spriteAnims == @[Animation(first: 0, last: 5, timer: 4, attributes: 0x80),
                             Animation(first: 2, last: 4, timer: 10, attributes: 0x90),
                             Animation(first: 1, last: 3, timer: 2)]
    check p.spriteAnims[1].pingPong and not p.spriteAnims[2].pingPong

  test "errors":
    let sprite = newSeq[byte](64)
    let one = @[byte('S'), byte('P'), byte('D'), 1, 0, 0, 6, 10, 3] & sprite & @[byte 0, 0, 1, 0x80]
    check parseSpd(one).sprites.len == 1
    expect SpdError: discard parseSpd(one[0 .. ^2])        # short
    expect SpdError: discard parseSpd(one & @[byte 0])     # trailing byte

  test "writing gives back the same bytes":
    var files = 0
    for kind, path in walkDir(dir):
      if path.endsWith(".spd"):
        checkpoint path
        check readSpd(path).toSpd(version = 1) == cast[seq[byte]](readFile(path))
        inc files
    check files == 2

  test "V5 to V1":
    let p = readSpd(currentSourcePath().parentDir / "files" / "spd5" / "sprite_anims.spd")
    let q = parseSpd(p.toSpd(version = 1))
    check q.sprites == p.sprites
    check q.spriteAnims == @[Animation(first: 0, last: 5, timer: 4, attributes: 0x80),  # enabled
                             Animation(first: 2, last: 4, timer: 10, attributes: 0x90)]

  test "writer leaves out what doesn't fit":
    let p = readSpd(dir / "anims.spd")
    var q = p
    q.sprites.setLen 257
    check parseSpd(q.toSpd(version = 1)).sprites.len == 256
    q = p
    q.spriteAnims.setLen 0                                   # V1 needs one
    check parseSpd(q.toSpd(version = 1)).spriteAnims == @[Animation()]
    q = p
    q.spriteAnims[0].last = 256
    check parseSpd(q.toSpd(version = 1)).spriteAnims == p.spriteAnims[1..2]
    q = p
    q.spriteOverlay = 4
    q.sprites[0].attributes = 0x11
    check parseSpd(q.toSpd(version = 1)).sprites[0].attributes == 0x01
    let t = readSpd(currentSourcePath().parentDir / "files" / "spd5" / "tiles_anims.spd")
    let r = parseSpd(t.toSpd(version = 1))
    check not r.tileSystem and r.tiles.len == 0 and r.tileAnims.len == 0
    check r.spriteAnims == @[Animation(first: 0, last: 3, timer: 6, attributes: 0x80)]
    check r.sprites[0].attributes == 0x82                    # overlay distance was 4
    q = p
    q.sprites.setLen 0
    expect SpdError: discard q.toSpd(version = 1)

suite "SPD V2":
  const dir = currentSourcePath().parentDir / "files" / "spd2"

  test "sprites and animations":
    let p = readSpd(dir / "sprites_anims.spd")
    check p.version == 2
    check p.colours == [0'u8, 2, 8]
    check p.spriteOverlay == 1 and p.tileOverlay == 1
    check p.sprites.len == 8
    check p.sprites[7].data == diagonal
    check p.sprites[6].overlay and p.sprites[6].colour == 11 and p.sprites[6].multicolour
    check not p.tileSystem and p.tiles.len == 0 and p.tileAnims.len == 0
    check p.spriteAnims == @[Animation(first: 0, last: 5, timer: 4, attributes: 0x80),
                             Animation(first: 2, last: 4, timer: 10, attributes: 0x90),
                             Animation(first: 6, last: 6, timer: 1, attributes: 0xa0),
                             Animation(first: 7, last: 7, timer: 3, attributes: 0x80),
                             Animation(first: 1, last: 3, timer: 2)]

  test "tiles":
    let p = readSpd(dir / "tiles.spd")
    check p.colours == [6'u8, 1, 0]
    check p.sprites.len == 4
    check p.tileSystem and p.tileWidth == 2 and p.tileHeight == 2
    check p.tiles == @[SpriteTile(cells: @[0'u16, 1, 2, 3]), SpriteTile(cells: @[3'u16, 2, 1, 0]),
                       SpriteTile(cells: @[0'u16, 0, 1, 1])]
    check p.spriteAnims.len == 0

  test "errors and odd files":
    let sprite = newSeq[byte](64)
    let one = @[byte('S'), byte('P'), byte('D'), 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 6, 10, 3] & sprite
    check parseSpd(one).sprites.len == 1
    expect SpdError: discard parseSpd(one[0 .. ^2])
    expect SpdError: discard parseSpd(one & @[byte 0])
    var none = one
    none[5] = 0
    expect SpdError: discard parseSpd(none)                  # no sprites
    var counts = one
    counts[7] = 5                                            # tiles and animations are off
    counts[9] = 5
    check parseSpd(counts).tiles.len == 0 and parseSpd(counts).spriteAnims.len == 0

  test "writing gives back the same bytes":
    var files = 0
    for kind, path in walkDir(dir):
      if path.endsWith(".spd"):
        checkpoint path
        check readSpd(path).toSpd(version = 2) == cast[seq[byte]](readFile(path))
        inc files
    check files == 2

  test "V5 to V2":
    let p = readSpd(currentSourcePath().parentDir / "files" / "spd5" / "tiles_anims.spd")
    let q = parseSpd(p.toSpd(version = 2))
    check q.tileSystem and q.tileWidth == 2 and q.tileHeight == 1
    check q.tiles == @[SpriteTile(cells: @[0'u16, 1]), SpriteTile(cells: @[2'u16, 3]),
                       SpriteTile(cells: @[0'u16, 3])]               # no attributes, tags, names
    check q.tileAnims.len == 0
    check q.spriteAnims == @[Animation(first: 0, last: 3, timer: 6, attributes: 0x80)]  # enabled
    for s in q.sprites: check not s.overlay                    # overlay distance was 4

  test "writer leaves out what doesn't fit":
    let p = readSpd(dir / "tiles.spd")
    var q = p
    q.sprites.setLen 4097
    q.tiles.setLen 257
    for t in q.tiles.mitems: t.cells.setLen 4
    q.spriteAnims.setLen 257
    var r = parseSpd(q.toSpd(version = 2))
    check r.sprites.len == 4096 and r.tiles.len == 256 and r.spriteAnims.len == 256
    q = p
    q.tileWidth = 5
    for t in q.tiles.mitems:
      t.cells = newSeq[uint16](10)
      t.cells[5] = 3
    r = parseSpd(q.toSpd(version = 2))
    check r.tileWidth == 4 and r.tiles[0].cells == @[0'u16, 0, 0, 0, 3, 0, 0, 0]

suite "SPD V5":
  const dir = currentSourcePath().parentDir / "files" / "spd5"

  test "sprites":
    let p = readSpd(dir / "sprites.spd")
    check p.version == 5
    check p.colours == [6'u8, 10, 3]
    check p.spriteOverlay == 1 and p.tileOverlay == 1
    check p.sprites.len == 6
    check p.sprites[0].data == box
    check p.sprites[3].data == diagonal
    check not p.tileSystem and p.tiles.len == 0
    check p.spriteAnims.len == 0 and p.tileAnims.len == 0
    let s = p.sprites
    check s[0].colour == 1 and not s[0].multicolour
    check s[1].colour == 5 and s[1].multicolour and not s[1].overlay
    check s[2].colour == 11 and s[2].multicolour and s[2].overlay
    check s[4].colour == 14 and s[4].expandX and not s[4].expandY
    check s[5].colour == 4 and s[5].multicolour and s[5].expandY and not s[5].expandX

  test "sprite animations":
    let p = readSpd(dir / "sprite_anims.spd")
    check p.sprites.len == 6
    check p.spriteAnims == @[Animation(first: 0, last: 5, timer: 4),
                             Animation(first: 2, last: 4, timer: 10, attributes: 0x10)]
    check not p.spriteAnims[0].pingPong and p.spriteAnims[1].pingPong
    check p.tileAnims.len == 0

  test "tiles and tile animations":
    let p = readSpd(dir / "tiles_anims.spd")
    check p.colours == [11'u8, 1, 0]
    check p.spriteOverlay == 4 and p.tileOverlay == 1
    check p.sprites.len == 8
    for i in 0..3: check p.sprites[i].overlay
    for i in 4..7: check not p.sprites[i].overlay
    check p.tileSystem
    check p.tileWidth == 2 and p.tileHeight == 1
    check p.tiles == @[SpriteTile(cells: @[0'u16, 1], tag: 1, name: "left"),
                       SpriteTile(cells: @[2'u16, 3], attributes: 0x10, tag: 2, name: "right"),
                       SpriteTile(cells: @[0'u16, 3], tag: 3, name: "mixed")]
    check p.tiles[1].overlay
    check p.spriteAnims == @[Animation(first: 0, last: 3, timer: 6)]
    check p.tileAnims == @[Animation(first: 0, last: 2, timer: 8),
                           Animation(first: 1, last: 2, timer: 3, attributes: 0x10)]

  test "errors and odd files":
    let sprite = newSeq[byte](64)
    expect SpdError: discard parseSpd(cast[seq[byte]]("SPX\5"))
    expect SpdError: discard parseSpd(v5(0, 1, 0, 0, 0, 0, 0, @[]))
    expect SpdError: discard parseSpd(v5(0, 0, 0, 0, 0, 0, 0, @[]))     # no sprites
    var data = v5(0, 1, 0, 0, 0, 0, 0, sprite)
    let p = parseSpd(data)
    check p.spriteOverlay == -2                                          # signed
    data.add 0
    expect SpdError: discard parseSpd(data)
    # Counts and sizes of parts that are off are ignored.
    check parseSpd(v5(0, 1, 7, 3, 3, 2, 2, sprite)).spriteAnims.len == 0
    # Older SpritePad Pro builds keep the tile colour in the low nibble.
    let q = parseSpd(v5(1, 1, 1, 0, 0, 1, 1, sprite & @[byte 0, 0, 0x13, 0, 0]))
    check q.tiles[0].overlay and q.tiles[0].attributes == 0x13

  test "writing gives back the same bytes":
    var files = 0
    for kind, path in walkDir(dir):
      if path.endsWith(".spd"):
        checkpoint path
        let data = readFile(path)
        check readSpd(path).toSpd == cast[seq[byte]](data)
        inc files
    check files == 3

  test "writeSpd":
    let path = getTempDir() / "batchpad_tspd.spd"
    let p = readSpd(dir / "tiles_anims.spd")
    writeSpd(path, p)
    check readSpd(path) == p
    removeFile path

  test "writer errors":
    let p = readSpd(dir / "tiles_anims.spd")
    var q = p
    q.sprites.setLen 0
    expect SpdError: discard q.toSpd
    q = p
    q.tiles.setLen 0
    expect SpdError: discard q.toSpd
    q = p
    q.tiles[1].cells.add 0
    expect SpdError: discard q.toSpd
    expect SpdError: discard p.toSpd(version = 4)

  test "writer leaves out what doesn't fit":
    let p = readSpd(dir / "tiles_anims.spd")
    var q = p
    q.tiles[0].name = repeat('x', 33)
    q.tiles[1].name = "ab\0cd"
    q.spriteAnims.setLen 257
    var r = parseSpd(q.toSpd)
    check r.tiles[0].name == repeat('x', 32)
    check r.tiles[1].name == "ab"
    check r.spriteAnims.len == 256
    q = p
    q.tileSystem = false
    r = parseSpd(q.toSpd)
    check r.tiles.len == 0 and r.tileAnims == p.tileAnims
    q = p
    q.tileWidth = 256
    for t in q.tiles.mitems:
      t.cells = newSeq[uint16](256)
      t.cells[255] = 7
      t.cells[1] = 3
    r = parseSpd(q.toSpd)
    check r.tileWidth == 255 and r.tiles[0].cells.len == 255 and r.tiles[0].cells[1] == 3
