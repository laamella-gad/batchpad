import std/[json, os, strutils, unittest]
import batchpad/[ctm, petmate, rawbin]

const files = currentSourcePath().parentDir / "files" / "petmate"

suite "Petmate workspaces":
  test "reads screens with the ROM charsets":
    let text = readFile(files / "screens.petmate")
    check petmateScreens(text) == 2
    let p = parsePetmate(text)
    check p.displayMode == dmHiresText and p.colouring == cmPerChar and not p.tileSystem
    check p.mapWidth == 4 and p.mapHeight == 3 and p.map.len == 12
    check p.map[5] == 15 and p.cellColours[5] == 2      # cell 1,1
    check p.chipColours[0] == 6 and p.screen.border == 14
    check p.screen.romChars == "upper" and p.screen.name == "title"
    check p.chars.len == 256 and p.chars[3].data == default(array[8, uint8])
    check p.chars[3].colours[0] == 1                    # its first cell's colour
    check p.chars[200].colours[0] == 14                 # unused
    let q = parsePetmate(text, 1)
    check q.mapWidth == 2 and q.screen.romChars == "lower" and q.screen.name == ""
    expect CtmError: discard parsePetmate(text, 2)

  test "reads its own charset":
    let p = readPetmate(files / "custom.petmate")
    check p.screen.romChars == "" and p.screen.fontName == "myfont" and p.screen.name == "level"
    check p.chars[1].data[2] == uint8((10 * 7 + 3) mod 256)
    check p.chars[255].data[7] == uint8((2047 * 7 + 3) mod 256)
    check p.map == @[0'u16, 1, 2, 1, 0, 255]
    check p.cellColours == @[5'u8, 5, 2, 9, 5, 1]

  test "version 1 has no charset field":
    let p = readPetmate(files / "v1.petmate")
    check p.screen.romChars == "upper" and p.map == @[32'u16, 33]

  test "writes the file we made":
    check readPetmate(files / "custom.petmate").toPetmate == readFile(files / "custom.petmate")
    let text = readFile(files / "screens.petmate")
    for screen in 0 .. 1:
      let p = parsePetmate(text, screen)
      check p.screen.screens == 2
      var q = parsePetmate(p.toPetmate)
      check q.screen.screens == 1
      q.screen.screens = 2
      check q == p

  test "colour-map gives the cell colours":
    let p = readPetmate(files / "custom.petmate")
    check p.binPart("colour-map") == @[5'u8, 5, 2, 9, 5, 1]
    check p.binPart("map") == @[0'u8, 1, 2, 1, 0, 255]

  test "a CharPad project as a Petmate screen":
    var p = readPetmate(files / "custom.petmate")
    p.cellColours = @[]
    p.screen = ScreenExtras()
    p.displayMode = dmMulticolourText
    p.chars[0].material = 1
    var leftOut: seq[string]
    let j = parseJson(p.toPetmate(leftOut))
    check leftOut.len == 2 and "multicolour" in leftOut[0] and "materials" in leftOut[1]
    let fb = j["framebufs"][0]
    check fb["charset"].getStr == "custom_1" and fb["borderColor"].getInt == 0
    # colours per char now: the first cell's colour
    check fb["framebuf"][1][0]["color"].getInt == 5    # char 1 first seen with 5
    # tiles are expanded
    p.tileSystem = true
    p.tileWidth = 1
    p.tileHeight = 2
    p.tiles = @[Tile(cells: @[1'u16, 2]), Tile(cells: @[3'u16, 4])]
    p.mapWidth = 2
    p.mapHeight = 1
    p.map = @[1'u16, 0]
    let q = parsePetmate(p.toPetmate)
    check q.mapWidth == 2 and q.mapHeight == 2 and q.map == @[3'u16, 1, 4, 2]

  test "what CTM can't hold is left out":
    # every char of screen 0 is used once: its colour says it all
    var leftOut: seq[string]
    discard parsePetmate(readFile(files / "screens.petmate")).toCtm(9, leftOut)
    check leftOut == @["the C64 ROM charset (upper case); the chars are blank"]
    # char 1 is in colour 5 and 9
    leftOut.setLen 0
    discard readPetmate(files / "custom.petmate").toCtm(9, leftOut)
    check leftOut == @["colours of 1 map cell (only Petmate has a colour per cell)"]

  test "refusals":
    expect CtmError: discard parsePetmate("not json")
    expect CtmError: discard parsePetmate("""{"version":3,"framebufs":[]}""")
    expect CtmError: discard parsePetmate("""{"version":2,"framebufs":[{"width":1,"height":1,"backgroundColor":0,"borderColor":0,"charset":"custom_9","framebuf":[[{"code":0,"color":0}]]}]}""")
    expect CtmError: discard parsePetmate("""{"version":2,"framebufs":[{"width":1,"height":1,"backgroundColor":0,"borderColor":0,"framebuf":[[{"code":0,"color":16}]]}]}""")
    expect CtmError: discard parsePetmate("""{"version":2,"framebufs":[{"width":2,"height":1,"backgroundColor":0,"borderColor":0,"framebuf":[[{"code":0,"color":1}]]}]}""")
    var p = readPetmate(files / "v1.petmate")
    p.displayMode = dmHiresBitmap
    expect CtmError: discard p.toPetmate
    p = readPetmate(files / "v1.petmate")
    p.mapWidth = 1025
    expect CtmError: discard p.toPetmate
