## Spritemate project files (.spm), as sprite projects. The layout is described in
## docs/spritepad.md.

import std/json
import spd

const
  spmVersion* = -2  ## `version` of a project read from a Spritemate `.spm`
  spmWriterVersion = "26.07.29"  ## the Spritemate release whose source we followed

proc fail(msg: string) {.noreturn.} = raise newException(SpdError, msg)

proc pen(n: JsonNode, what: string): int =
  ## A pen of a pixel: 0 to 3, or in files of old Spritemates "t", "i", "m1", "m2".
  case n.kind
  of JInt:
    result = n.getInt
  of JString:
    result = case n.getStr
             of "t": 0
             of "i": 1
             of "m1": 2
             of "m2": 3
             else: -1
  else:
    result = -1
  if result notin 0..3: fail(what & ": not a pen: " & $n)

proc colourOf(n: JsonNode, what: string): uint8 =
  if n.kind != JInt or n.getInt notin 0..15: fail(what & " must be 0 to 15, not " & $n)
  uint8(n.getInt)

proc shared(colors: JsonNode, key, oldKey: string): JsonNode =
  result = colors.getOrDefault(key)
  if result == nil: result = colors.getOrDefault(oldKey)
  if result == nil: fail("no colour " & key & " in colors")

proc parseSprite(s: JsonNode, i: int): Sprite =
  let what = "sprite " & $i
  if s.kind != JObject: fail(what & " is not an object")
  let multicolour = s.getOrDefault("multicolor").getBool
  var attributes = colourOf(s.getOrDefault("color"), what & " colour")
  if multicolour: attributes = attributes or 0x80
  if s.getOrDefault("double_y").getBool: attributes = attributes or 0x40
  if s.getOrDefault("double_x").getBool: attributes = attributes or 0x20
  if s.getOrDefault("overlay").getBool: attributes = attributes or 0x10
  result.attributes = attributes
  let rows = s.getOrDefault("pixels")
  if rows == nil or rows.kind != JArray or rows.len != 21:
    fail(what & " needs 21 rows of pixels")
  for y in 0 ..< rows.len:
    let row = rows[y]
    if row.kind != JArray or row.len != 24: fail(what & ", row " & $y & " needs 24 pixels")
    for b in 0 .. 2:
      var v = 0
      if multicolour:
        # a pixel of a multicolour sprite is 2 entries wide; the first one counts
        for k in 0 .. 3:
          v = v shl 2 or [0, 2, 1, 3][row[b * 8 + k * 2].pen(what)]
      else:
        for k in 0 .. 7:
          v = v shl 1 or (if row[b * 8 + k].pen(what) == 0: 0 else: 1)
      result.data[y * 3 + b] = uint8(v)

proc parseSpm*(text: string): SpriteProject =
  ## Parses a whole .spm file. Raises SpdError on anything it can't read. It
  ## takes the sprites (pixels, colour, multicolour, expansion, overlay) and
  ## the three shared colours; the rest (names, the drawing pen, animation
  ## settings) is not kept.
  let j = try: parseJson(text)
          except JsonParsingError as e: fail("not a Spritemate project: " & e.msg)
  if j.kind != JObject or j.getOrDefault("sprites") == nil or j["sprites"].kind != JArray:
    fail("not a Spritemate project (no sprites)")
  if j.getOrDefault("colors") == nil or j["colors"].kind != JObject:
    fail("not a Spritemate project (no colors)")
  let sprites = j["sprites"]
  if sprites.len == 0: fail("a Spritemate project without sprites")
  if sprites.len > 1024: fail("more than 1024 sprites")
  result.version = spmVersion
  let colors = j["colors"]
  for i, (key, oldKey) in [("0", "t"), ("2", "m1"), ("3", "m2")]:
    result.colours[i] = colourOf(colors.shared(key, oldKey), "colour " & key)
  result.spriteOverlay = 1
  result.tileOverlay = 1
  for i in 0 ..< sprites.len:
    result.sprites.add parseSprite(sprites[i], i)

proc readSpm*(path: string): SpriteProject =
  parseSpm(readFile(path))

proc toSpm*(p: SpriteProject, leftOut: var seq[string]): string =
  ## Formats `p` as a Spritemate project. Leaves out what it can't hold, with a
  ## line in `leftOut` for each: the tile system and animations. Raises SpdError
  ## for a project without sprites or with more than 1024.
  if p.sprites.len == 0: fail("a Spritemate project needs a sprite")
  if p.sprites.len > 1024: fail("more than 1024 sprites")
  if p.tiles.len > 0: leftOut.add $p.tiles.len & " tile(s) (Spritemate has none)"
  if p.spriteAnims.len > 0 or p.tileAnims.len > 0:
    leftOut.add "animations (Spritemate keeps its own kind)"
  var sprites = newJArray()
  for i, s in p.sprites:
    var rows = newJArray()
    for y in 0 .. 20:
      var row = newJArray()
      for b in 0 .. 2:
        let v = s.data[y * 3 + b].int
        if s.multicolour:
          for k in 0 .. 3:
            let pen = [0, 2, 1, 3][v shr (6 - 2 * k) and 3]
            row.add %pen
            row.add %pen
        else:
          for k in 0 .. 7: row.add %(v shr (7 - k) and 1)
      rows.add row
    sprites.add %*{"name": "sprite" & $i, "color": s.colour.int, "multicolor": s.multicolour,
                   "double_x": s.expandX, "double_y": s.expandY, "overlay": s.overlay,
                   "pixels": rows}
  let j = %*{"version": spmWriterVersion, "filename": "untitled",
             "colors": {"0": p.colours[0].int, "2": p.colours[1].int, "3": p.colours[2].int},
             "sprites": sprites, "current_sprite": 0, "pen": 1,
             "animation": {"startSprite": 0, "endSprite": p.sprites.high, "fps": 6,
                           "mode": "restart", "doubleX": false, "doubleY": false}}
  $j

proc toSpm*(p: SpriteProject): string =
  var leftOut: seq[string]
  p.toSpm(leftOut)

proc writeSpm*(path: string, p: SpriteProject) =
  writeFile(path, p.toSpm)
