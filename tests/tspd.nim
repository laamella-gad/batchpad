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
    q.tileSystem = false
    expect SpdError: discard q.toSpd
    q = p
    q.tiles[1].cells.add 0
    expect SpdError: discard q.toSpd
    q = p
    q.tiles[0].name = repeat('x', 33)
    expect SpdError: discard q.toSpd
    q = p
    q.spriteAnims.setLen 257
    expect SpdError: discard q.toSpd
    expect SpdError: discard p.toSpd(version = 4)
