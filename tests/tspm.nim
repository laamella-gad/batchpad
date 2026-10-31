import std/[json, os, strutils, unittest]
import batchpad/[spd, spm]

const files = currentSourcePath().parentDir / "files"

suite "Spritemate .spm":
  test "reads what the SPD V5 file holds":
    let spd5 = readSpd(files / "spd5" / "sprites.spd")
    let p = readSpm(files / "spm" / "sprites.spm")
    check p.version == spmVersion
    check p.colours == spd5.colours
    check p.sprites == spd5.sprites
    check not p.tileSystem

  test "older Spritemates' pen names":
    let p = readSpm(files / "spm" / "legacy.spm")
    check p.sprites == readSpd(files / "spd5" / "sprites.spd").sprites[0 .. 1]
    check p.colours == [6'u8, 10, 3]

  test "writes the file we made":
    let p = readSpd(files / "spd5" / "sprites.spd")
    check parseJson(p.toSpm) == parseJson(readFile(files / "spm" / "sprites.spm"))

  test "multicolour pens map to the SPD bit pairs":
    var p = readSpd(files / "spd5" / "sprites.spd")
    p.sprites.setLen 1
    p.sprites[0].attributes = 0x81
    p.sprites[0].data[0] = 0b00_01_10_11
    let j = parseJson(p.toSpm)
    check j["sprites"][0]["pixels"][0].elems[0 .. 7] == @[%0, %0, %2, %2, %1, %1, %3, %3]
    check readSpm(files / "spm" / "sprites.spm").sprites.len == 6
    check parseSpm(p.toSpm).sprites == p.sprites

  test "what Spritemate can't hold is left out":
    var leftOut: seq[string]
    var p = readSpd(files / "spd5" / "tiles_anims.spd")
    discard p.toSpm(leftOut)
    check leftOut.len == 2
    check "tile" in leftOut[0]

  test "broken files":
    expect SpdError: discard parseSpm("not json")
    expect SpdError: discard parseSpm("{}")
    expect SpdError: discard parseSpm("""{"colors":{"0":1,"2":2,"3":3},"sprites":[]}""")
    expect SpdError: discard parseSpm("""{"colors":{"0":1,"2":2,"3":3},"sprites":[{"color":1,"pixels":[]}]}""")
    expect SpdError: discard parseSpm("""{"colors":{"0":16,"2":2,"3":3},"sprites":[{"color":1,"pixels":[]}]}""")
