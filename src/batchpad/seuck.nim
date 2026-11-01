## SEUCK (Shoot 'em Up Construction Kit) files: `.A` sprites as sprite
## projects, `.B` backgrounds as CharPad projects. The layouts are described in
## docs/import-export.md under SEUCK; the rules follow CharPad Pro 3.88's
## loader and saver (a `.B` is not checked for its signature, only its size).
## Also `.P00` files (PC64 container) and the "save all data" `.I` file, which
## holds both a background and the sprites.

import std/strutils
import ctm, rawimport, spd

type
  SeuckError* = object of ValueError

const
  seuckASize* = 2 + 127 * 64           ## 8130
  seuckBSize* = 9596
  seuckBMapWidth = 8
  seuckBMapHeight = 512
  sidewaysWidth = 819                   ## CharPad 1.7's "sideways SEUCK mod" map
  sidewaysHeight = 5
  tileCount = 128
  charCount = 254
  tileSide = 5

  seuckISize* = 2 + (0x10000 - 6 - 0x900)  ## 63228: $900 to $fff9 after the 2 byte signature
  p00HeaderSize* = 26

proc fail(msg: string) {.noreturn.} = raise newException(SeuckError, msg)

# .P00

proc isP00*(data: string): bool =
  ## PC64 container: "C64File", $00, a 16 byte name, $00, record size.
  data.len >= p00HeaderSize and data.startsWith("C64File\0")

proc unwrapP00*(data: string): tuple[name, body: string] =
  ## The name stored in a `.P00` header, without trailing padding (SEUCK
  ## names end in `.A` to `.I`), and the file after the header.
  if not data.isP00: fail("not a .P00 file")
  var name = data[8 ..< 24]
  while name.len > 0 and name[^1] in {' ', '\0', '\xa0'}: name.setLen name.high
  (name, data[p00HeaderSize .. ^1])

proc seuckKind*(name: string): char =
  ## The letter a SEUCK file name ends in, upper case, or `\0` for another name.
  if name.len >= 2 and name[^2] == '.' and name[^1].toUpperAscii in {'A' .. 'I'}:
    name[^1].toUpperAscii
  else: '\0'

# .A

proc parseSeuckA*(data: openArray[byte]): SpriteProject =
  ## 127 sprites of 64 bytes after a 2 byte signature; the 64th byte is
  ## `000M CCCC`. Like both SpritePad and CharPad, this doesn't check the
  ## signature. Raises SeuckError for another size.
  if data.len != seuckASize:
    fail("not a SEUCK sprite file: " & $data.len & " bytes, expected " & $seuckASize)
  result = newSpdProject()
  result.sprites.setLen 127
  for i, s in result.sprites.mpairs:
    for j in 0 .. 62: s.data[j] = data[2 + 64 * i + j]
    s.attributes = seuckToSpritePad(data[2 + 64 * i + 63])

proc readSeuckA*(path: string): SpriteProject =
  let text = readFile(path)
  parseSeuckA(text.toOpenArrayByte(0, text.high))

proc toSeuckA*(p: SpriteProject, leftOut: var seq[string]): string =
  ## Formats `p` as a SEUCK sprite file, padded with empty sprites to 127.
  ## Leaves out what it can't hold, with a line in `leftOut` for each. Raises
  ## SeuckError for more than 127 sprites or none.
  if p.sprites.len == 0: fail("a SEUCK sprite file needs a sprite")
  if p.sprites.len > 127: fail("a SEUCK sprite file holds 127 sprites, not " & $p.sprites.len)
  result = newString(seuckASize)
  result[0] = 'B'
  var lost = false
  for i, s in p.sprites:
    for j in 0 .. 62: result[2 + 64 * i + j] = char(s.data[j])
    result[2 + 64 * i + 63] = char(s.colour or (if s.multicolour: 0x10 else: 0))
    if s.expandX or s.expandY or s.overlay: lost = true
  if lost: leftOut.add "sprite expansion and overlay (SEUCK has no such bits)"
  if p.tiles.len > 0: leftOut.add $p.tiles.len & " tile(s) (SEUCK sprites have none)"
  if p.spriteAnims.len > 0 or p.tileAnims.len > 0: leftOut.add "animations"

proc toSeuckA*(p: SpriteProject): string =
  var leftOut: seq[string]
  p.toSeuckA(leftOut)

# .B

proc parseSeuckB*(data: openArray[byte], sideways = false): ctm.Project =
  ## A background as a CharPad project: multicolour text, colours per tile,
  ## 128 tiles of 5 x 5 and 254 chars; the map is 8 x 512, with the file's
  ## first row at the bottom. `sideways` reads CharPad 1.7's "sideways SEUCK
  ## mod" files instead: an 819 x 5 map, stored as columns from right to left,
  ## each from bottom to top. Raises SeuckError for another size.
  if data.len != seuckBSize:
    fail("not a SEUCK background: " & $data.len & " bytes, expected " & $seuckBSize)
  result = newCtmProject()
  result.colouring = cmPerTile
  result.tileSystem = true
  result.tileWidth = tileSide
  result.tileHeight = tileSide
  var at = 2
  let (w, h) = if sideways: (sidewaysWidth, sidewaysHeight) else: (seuckBMapWidth, seuckBMapHeight)
  result.mapWidth = w
  result.mapHeight = h
  result.map.setLen w * h
  if sideways:
    for k in 0 ..< w * h:
      let (x, y) = (w - 1 - k div h, h - 1 - k mod h)
      result.map[y * w + x] = data[at + k]
  else:
    for row in 0 ..< h:
      for x in 0 ..< w:
        result.map[(h - 1 - row) * w + x] = data[at + row * w + x]
  at += 4096
  result.tiles.setLen tileCount
  for i, t in result.tiles.mpairs:
    t.colours[0] = if sideways: data[at + i] else: data[at + i] and 0x0f
  at += 256                      # 128 tile colours, then 128 unused bytes
  for t in result.tiles.mitems:
    t.cells.setLen tileSide * tileSide
    for c in t.cells.mitems:
      c = data[at]
      inc at
  result.chars.setLen charCount
  for ch in result.chars.mitems:
    for b in ch.data.mitems:
      b = data[at]
      inc at
  if sideways:
    # What CharPad 1.7 sets on loading one.
    result.chipColours[0] = 0x0b
    result.chipColours[1] = 0x00
    result.chipColours[2] = 0x01
    result.colours[0] = 0x0d

proc readSeuckB*(path: string, sideways = false): ctm.Project =
  let text = readFile(path)
  parseSeuckB(text.toOpenArrayByte(0, text.high), sideways)

proc toSeuckB*(p: ctm.Project, leftOut: var seq[string], sideways = false): string =
  ## Formats `p` as a SEUCK background. As CharPad Pro does, the project must
  ## have exactly 128 tiles of 5 x 5, colours per tile, 254 chars and an
  ## 8 x 512 map; `sideways` (CharPad 1.7's rule) takes an 819 x 5 map and at
  ## most 128 tiles and 254 chars, padded with zeros, in multicolour text mode.
  ## Raises SeuckError saying what doesn't fit.
  if not p.tileSystem or p.tiles.len == 0: fail("a SEUCK background needs tiles (128, 5 x 5)")
  if p.tileWidth != tileSide or p.tileHeight != tileSide:
    fail("the tiles must be 5 x 5, not " & $p.tileWidth & " x " & $p.tileHeight)
  if p.colouring != cmPerTile: fail("the colouring must be per tile")
  let (w, h) = if sideways: (sidewaysWidth, sidewaysHeight) else: (seuckBMapWidth, seuckBMapHeight)
  if p.mapWidth != w or p.mapHeight != h:
    fail("the map must be " & $w & " x " & $h & ", not " & $p.mapWidth & " x " & $p.mapHeight)
  if sideways:
    if p.displayMode != dmMulticolourText: fail("the display mode must be multicolour text")
    if p.tiles.len > tileCount: fail("at most 128 tiles, not " & $p.tiles.len)
    if p.chars.len > charCount: fail("at most 254 chars, not " & $p.chars.len)
  else:
    if p.tiles.len != tileCount: fail("the project needs 128 tiles, not " & $p.tiles.len)
    if p.chars.len != charCount: fail("the project needs 254 chars, not " & $p.chars.len)
  var data = newString(seuckBSize)
  data[0] = 'B'
  var at = 2
  template put(b: int) =
    data[at] = char(b)
    inc at
  for v in p.map:
    if v > 255: fail("map cell " & $v & " doesn't fit in a byte")
  if sideways:
    for k in 0 ..< w * h:
      put int(p.map[(h - 1 - k mod h) * w + (w - 1 - k div h)])
    put 0
  else:
    for row in 0 ..< h:
      for x in 0 ..< w: put int(p.map[(h - 1 - row) * w + x])
  at = 2 + 4096
  for i in 0 ..< tileCount:
    put (if i < p.tiles.len: int(p.tiles[i].colours[0]) else: 0)
  at += 128
  for i in 0 ..< tileCount:
    for j in 0 ..< tileSide * tileSide:
      if i < p.tiles.len:
        if p.tiles[i].cells[j] > 255: fail("tile cell " & $p.tiles[i].cells[j] & " doesn't fit in a byte")
        put int(p.tiles[i].cells[j])
      else: put 0
  for i in 0 ..< charCount:
    for j in 0 .. 7: put (if i < p.chars.len: int(p.chars[i].data[j]) else: 0)
  put 0x3f
  for i in 0 ..< 9: put 0xff
  result = data
  for t in p.tiles:
    if t.tag != 0 or t.name != "":
      leftOut.add "tile tags and names"
      break
  for c in p.chars:
    if c.material != 0:
      leftOut.add "char materials"
      break

proc toSeuckB*(p: ctm.Project, sideways = false): string =
  var leftOut: seq[string]
  p.toSeuckB(leftOut, sideways)

# .I, "save all data"

const
  mapAt = 0x900           ## the map, tile colours, tiles: $900 to $267f
  mapEnd = 0x2680
  charsAt = 0xf800        ## the chars, and the 10 bytes after them
  memEnd = 0xfffa
  spritesAt = 0xc000

proc memory(data: openArray[byte], at, len: int): string =
  ## `len` bytes of SEUCK memory from address `at`, out of a `.I` file.
  for i in at ..< at + len: result.add char(data[2 + i - mapAt])

proc checkI(data: openArray[byte]) =
  if data.len != seuckISize:
    fail("not a SEUCK \"save all data\" file: " & $data.len & " bytes, expected " & $seuckISize)

proc seuckIBackground*(data: openArray[byte]): string =
  ## The `.B` file inside a `.I` file: the memory from $900 to $267f, then from
  ## $f800 to $fff9. Raises SeuckError for another size.
  data.checkI
  "B\0" & memory(data, mapAt, mapEnd - mapAt) & memory(data, charsAt, memEnd - charsAt)

proc seuckISprites*(data: openArray[byte]): string =
  ## The `.A` file inside a `.I` file: the 127 sprites at $c000.
  data.checkI
  "B\0" & memory(data, spritesAt, 127 * 64)

proc parseSeuckIBackground*(data: openArray[byte]): ctm.Project =
  let b = seuckIBackground(data)
  parseSeuckB(b.toOpenArrayByte(0, b.high))

proc parseSeuckISprites*(data: openArray[byte]): SpriteProject =
  let a = seuckISprites(data)
  parseSeuckA(a.toOpenArrayByte(0, a.high))
