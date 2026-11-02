## Petmate (`.petmate`) workspaces, read and written as CharPad projects. The
## layout is in docs/import-export.md under "Petmate".
##
## A workspace is JSON holding screens. A screen is a char map of 1 x 1 to
## 1024 x 1024 cells, each a screen code and a colour, with a background and a
## border colour, and either the C64 ROM charset ("upper" or "lower") or a
## charset of its own. One screen becomes a hires text project without tiles:
## the screen codes are the map, the colours `Project.cellColours`, and each
## char takes the colour of the first cell using it (per char colouring), so
## formats without cell colours get the closest thing. A ROM charset isn't in
## the file: the chars are then 256 blank ones, and `Project.screen.romChars`
## says which ROM set it was.

import std/[json, strutils]
import binio, ctm

proc fail(msg: string) {.noreturn.} = raise newException(CtmError, msg)

proc field(n: JsonNode, key: string, kind: JsonNodeKind, what: string): JsonNode =
  if n.kind != JObject or not n.hasKey(key) or n[key].kind != kind:
    fail(what & " has no " & key)
  n[key]

proc number(n: JsonNode, key: string, range: Slice[int], what: string): int =
  let v = n.field(key, JInt, what)
  result = v.getInt
  if result notin range: fail(what & ": " & key & " " & $result & " is not " & $range.a & " to " & $range.b)

proc parseJsonText(text: string): JsonNode =
  try: parseJson(text)
  except JsonParsingError, ValueError: fail("not a Petmate workspace: " & getCurrentExceptionMsg())

proc framebufs(j: JsonNode): JsonNode =
  if j.kind != JObject or not j.hasKey("framebufs") or not j.hasKey("version"):
    fail("not a Petmate workspace: no version and framebufs")
  let version = j.number("version", 0 .. int.high, "workspace")
  if version notin 1 .. 2: fail("Petmate workspace version " & $version & " is not supported (1 and 2 are)")
  j.field("framebufs", JArray, "workspace")

proc petmateScreens*(text: string): int =
  ## How many screens a workspace holds.
  text.parseJsonText.framebufs.len

proc parsePetmate*(text: string, screen = 0): Project =
  ## Reads screen `screen` (from 0) of a Petmate workspace. Raises CtmError
  ## when it is not one or has no such screen.
  let j = parseJsonText(text)
  let fbs = j.framebufs
  if screen notin 0 ..< fbs.len:
    fail("the workspace has " & $fbs.len & " screen(s); there is no screen " & $screen)
  let fb = fbs[screen]
  let what = "screen " & $screen
  let w = fb.number("width", 1 .. 1024, what)
  let h = fb.number("height", 1 .. 1024, what)
  result.displayMode = dmHiresText
  result.colouring = cmPerChar
  result.chipColours[0] = uint8 fb.number("backgroundColor", 0 .. 15, what)
  result.screen.screens = fbs.len
  result.screen.border = uint8 fb.number("borderColor", 0 .. 15, what)
  if fb.hasKey("name") and fb["name"].kind == JString: result.screen.name = fb["name"].getStr
  let charset = if fb.hasKey("charset") and fb["charset"].kind == JString: fb["charset"].getStr else: "upper"
  result.chars.setLen 256
  if charset in ["upper", "lower"]:
    result.screen.romChars = charset
  else:
    let fonts = if j.hasKey("customFonts"): j["customFonts"] else: newJObject()
    if fonts.kind != JObject or not fonts.hasKey(charset):
      fail(what & " uses charset '" & charset & "', which the workspace doesn't hold")
    let font = fonts[charset]
    if font.kind == JObject and font.hasKey("name") and font["name"].kind == JString:
      result.screen.fontName = font["name"].getStr
    let bits = font.field("font", JObject, "charset " & charset).field("bits", JArray, "charset " & charset)
    if bits.len > 2048: fail("charset " & charset & " has " & $bits.len & " bytes, more than 2048")
    for i, b in bits.elems:
      if b.kind != JInt or b.getInt notin 0 .. 255: fail("charset " & charset & ": byte " & $i & " is not 0 to 255")
      result.chars[i div 8].data[i mod 8] = uint8 b.getInt
  let rows = fb.field("framebuf", JArray, what)
  if rows.len != h: fail(what & " has " & $rows.len & " rows, not " & $h)
  result.mapWidth = w
  result.mapHeight = h
  result.map.setLen w * h
  result.cellColours.setLen w * h
  var coloured: array[256, bool]
  for y, row in rows.elems:
    if row.kind != JArray or row.len != w: fail(what & ": row " & $y & " doesn't have " & $w & " cells")
    for x, cell in row.elems:
      let at = what & ", cell " & $x & "," & $y
      let code = cell.number("code", 0 .. 255, at)
      let colour = uint8 cell.number("color", 0 .. 15, at)
      result.map[y * w + x] = uint16 code
      result.cellColours[y * w + x] = colour
      if not coloured[code]:
        coloured[code] = true
        result.chars[code].colours[0] = colour
  # chars no cell uses: Petmate's default colour, light blue
  for i, ch in result.chars.mpairs:
    if not coloured[i]: ch.colours[0] = 14

proc readPetmate*(path: string, screen = 0): Project =
  parsePetmate(readFile(path), screen)

proc toPetmate*(p: Project, leftOut: var seq[string]): string =
  ## Formats `p` as a Petmate workspace with one screen. What Petmate can't
  ## hold is left out, with a line in `leftOut` for each: multicolour and ECM
  ## (written as hires; ECM cells keep their char number, without the
  ## background bits), chars past 256 (cells using them become 0), materials,
  ## the key map and the flexi-grid. Tiles are expanded into a char map. Cell
  ## colours come from `cellColours`, else from the colouring. Raises CtmError
  ## on bitmap modes, TED colours, maps larger than 1024 x 1024 or empty, and
  ## projects that don't hold together.
  if p.ted: fail("the project has TED colours (CharPad C16); convert them with toC64 first")
  if p.displayMode in {dmHiresBitmap, dmMulticolourBitmap}: fail("Petmate has no bitmap modes")
  if p.chars.len == 0: fail("no chars")
  var q = p
  if q.tileSystem:
    if q.cellColours.len > 0: leftOut.add "the cell colours (they don't fit a tile map)"
    q.cellColours = @[]
    q.expandTiles
  if q.mapWidth notin 1 .. 1024 or q.mapHeight notin 1 .. 1024:
    fail("the map is " & $q.mapWidth & " x " & $q.mapHeight & "; Petmate screens are 1 x 1 to 1024 x 1024")
  if q.map.len != q.mapWidth * q.mapHeight:
    fail("map has " & $q.map.len & " cells, not " & $q.mapWidth & " x " & $q.mapHeight)
  case q.displayMode
  of dmMulticolourText: leftOut.add "multicolour (written as hires)"
  of dmEcmText: leftOut.add "extended colour mode (written as hires)"
  else: discard
  if q.chars.len > 256: leftOut.add count(q.chars.len - 256, "chars") & " past 256"
  var materials = 0
  for ch in q.chars:
    if ch.material != 0: inc materials
  if materials > 0: leftOut.add "materials of " & count(materials, "chars")
  if q.keyMap != 0: leftOut.add "key map " & $q.keyMap
  if (q.flexiGrid.settings and 0x80) != 0: leftOut.add "the flexi-grid"
  if q.triggers.len > 0: leftOut.add "the trigger map"
  let ownColours = q.cellColours.len == q.map.len
  if q.cellColours.len > 0 and not ownColours:
    leftOut.add "the cell colours (" & $q.cellColours.len & ", the map has " & $q.map.len & " cells)"

  var lost = 0
  var rows = newJArray()
  for y in 0 ..< q.mapHeight:
    var row = newJArray()
    for x in 0 ..< q.mapWidth:
      let i = y * q.mapWidth + x
      var code = int(q.map[i])
      let shape = if q.displayMode == dmEcmText: code and 63 else: code
      let colour =
        if ownColours: q.cellColours[i]
        else:
          case q.colouring
          of cmPerProject: q.colours[0]
          of cmPerChar: (if shape < q.chars.len: q.chars[shape].colours[0] else: 0)
          of cmPerTile: q.colours[0]   # gone with expandTiles
      if q.displayMode == dmEcmText: code = shape
      if code > 255:
        inc lost
        code = 0
      row.add %*{"code": code, "color": int(colour and 0x0f)}
    rows.add row
  if lost > 0: leftOut.add count(lost, "map cells") & " using chars past 256 (now char 0)"

  var fb = %*{"width": q.mapWidth, "height": q.mapHeight,
              "backgroundColor": int(q.chipColours[0] and 0x0f),
              "borderColor": int(q.screen.border and 0x0f)}
  var fonts = newJObject()
  if q.screen.romChars in ["upper", "lower"]:
    fb["charset"] = %q.screen.romChars
  else:
    fb["charset"] = %"custom_1"
    var bits = newJArray()
    var order = newJArray()
    for i in 0 ..< 256:
      order.add %i
      for b in (if i < q.chars.len: q.chars[i].data else: default(array[8, uint8])): bits.add %int(b)
    let name = if q.screen.fontName != "": q.screen.fontName else: "charset"
    fonts["custom_1"] = %*{"name": name, "font": {"bits": bits, "charOrder": order}}
  if q.screen.name != "": fb["name"] = %q.screen.name
  fb["framebuf"] = rows
  $(%*{"version": 2, "screens": [0], "framebufs": [fb], "customFonts": fonts})

proc toPetmate*(p: Project): string =
  var leftOut: seq[string]
  p.toPetmate(leftOut)

proc writePetmate*(path: string, p: Project) =
  writeFile(path, p.toPetmate)

func isPetmate*(text: string): bool =
  ## Looks like a Petmate workspace: a JSON object with framebufs.
  let t = text.strip
  t.startsWith("{") and "\"framebufs\"" in t and "\"version\"" in t
