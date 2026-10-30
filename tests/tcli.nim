import std/[os, sequtils, streams, strutils, times, unittest]
import batchpad/[cli, ctm, spd]

const files = currentSourcePath().parentDir / "files"

proc batchpad(args: varargs[string]): (int, string) =
  let output = newStringStream()
  let code = run(@args, output, newStringStream())
  (code, output.data)

proc warnings(args: varargs[string]): (int, string) =
  ## Exit code and what goes to stderr.
  let errors = newStringStream()
  let code = run(@args, newStringStream(), errors)
  (code, errors.data)

let tmp = getTempDir() / "batchpad_tcli"
removeDir(tmp)
createDir(tmp)

suite "command line":
  test "version and help":
    let (vcode, version) = batchpad("--version")
    check vcode == 0 and version.startsWith("batchpad ")
    let (code, help) = batchpad("--help")
    check code == 0
    check "convert" in help and "import" in help

  test "usage errors exit with 2":
    check batchpad()[0] == 2
    check batchpad("frob")[0] == 2
    check batchpad("info")[0] == 2
    check batchpad("bin", "x.ctm", "--cells", "9")[0] == 2

  test "info":
    let (code, text) = batchpad("info", files / "spd2" / "tiles.spd")
    check code == 0
    check "format: spd\n" in text and "version: 2\n" in text and "tiles: 3\n" in text
    let (jcode, json) = batchpad("info", "--json", files / "ctm9" / "ecm_perproject_notiles.ctm")
    check jcode == 0
    check "\"mode\": \"ecm\"" in json

  test "input errors exit with 1":
    check batchpad("info", files / "spd5" / "README.md")[0] == 1
    check batchpad("info", tmp / "missing.ctm")[0] == 1
    check batchpad("bin", files / "spd5" / "sprites.spd", "tiles=" & tmp / "s.bin")[0] == 1

  test "convert":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("convert", src, tmp / "a.ctm", "--to", "ctm7")[0] == 0
    check readCtm(tmp / "a.ctm").version == 7
    for v in [4, 5, 6, 8]:
      check batchpad("convert", src, tmp / "v.ctm", "--to", "ctm" & $v)[0] == 0
      check readCtm(tmp / "v.ctm").version == v
    check batchpad("convert", src, tmp / "a8.ctm", "--to", "ctm8")[0] == 0
    check readCtm(tmp / "a8.ctm").version == 8
    check batchpad("convert", files / "ctm8" / "mcbitmap_pertile.ctm", tmp / "a9.ctm")[0] == 0
    check readCtm(tmp / "a9.ctm").version == 9
    check batchpad("convert", src, tmp / "b.ctm")[0] == 0
    check readCtm(tmp / "b.ctm").version == 9
    check batchpad("convert", src, tmp / "c.bin")[0] == 1
    check batchpad("convert", src, tmp / "c.spd")[0] == 1
    check not fileExists(tmp / "c.bin") and not fileExists(tmp / "c.spd")
    let (code, data) = batchpad("convert", src, "-", "--to", "ctm9")
    check code == 0 and data.startsWith("CTM\x09")

  test "headerless SPD":
    let src = files / "spd0" / "sprites.spd"
    let (code, text) = batchpad("info", src)
    check code == 0 and "version: 0" in text
    check batchpad("convert", files / "spd5" / "sprites.spd", tmp / "h.spd", "--to", "spd0")[0] == 0
    check readSpd(tmp / "h.spd").version == 0
    check batchpad("convert", src, tmp / "h5.spd")[0] == 0
    check readSpd(tmp / "h5.spd").version == 5

  test "convert to spd3 and spd4":
    for v in [3, 4]:
      check batchpad("convert", files / "spd5" / "tiles_anims.spd", tmp / "v.spd", "--to", "spd" & $v)[0] == 0
      check readSpd(tmp / "v.spd").version == v

  test "convert with --set":
    let src = files / "spd5" / "sprites.spd"
    check batchpad("convert", src, tmp / "a.spd", "--to", "spd1", "--set", "bg=3",
                   "--set", "mc2=12")[0] == 0
    let p = readSpd(tmp / "a.spd")
    check p.version == 1 and p.colours[0] == 3 and p.colours[2] == 12
    check batchpad("convert", src, tmp / "b.spd", "--set", "mc1=99")[0] == 1
    check batchpad("convert", src, tmp / "b.spd", "--set", "frob=1")[0] == 1
    check not fileExists(tmp / "b.spd")

  test "convert with --set tiles=off":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("convert", src, tmp / "flat.ctm", "--set", "tiles=off")[0] == 0
    let p = readCtm(tmp / "flat.ctm")
    let q = readCtm(src)
    check not p.tileSystem and p.tiles.len == 0
    check p.colouring == cmPerChar
    check (p.mapWidth, p.mapHeight) == (q.mapWidth * q.tileWidth, q.mapHeight * q.tileHeight)
    # The colour of every char cell is the same as before.
    check batchpad("bin", tmp / "flat.ctm", "colour-map=" & tmp / "flat.bin")[0] == 0
    check batchpad("bin", src, "colour-map=" & tmp / "tiled.bin")[0] == 0
    check readFile(tmp / "flat.bin") == readFile(tmp / "tiled.bin")
    check batchpad("convert", src, tmp / "x.ctm", "--set", "tiles=on")[0] == 1

  test "convert warns about what is left out":
    let src = files / "spd5" / "tiles_anims.spd"
    let (code, text) = warnings("convert", src, tmp / "w.spd", "--to", "spd1")
    check code == 0 and fileExists(tmp / "w.spd")
    check text.splitLines.len == 4
    check text.startsWith("batchpad: " & tmp / "w.spd" & ": warning: left out the tiles (V1 has none)\n")
    check warnings("convert", src, tmp / "w5.spd") == (0, "")
    check warnings("convert", src, tmp / "q.spd", "--to", "spd1", "--quiet") == (0, "")
    let (scode, stext) = warnings("convert", src, tmp / "s.spd", "--to", "spd1", "--strict")
    check scode == 1 and "--strict" in stext and "the tiles (V1 has none)" in stext
    check not fileExists(tmp / "s.spd")

  test "unchanged output is not written again":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    let path = tmp / "same.ctm"
    check batchpad("convert", src, path)[0] == 0
    let old = fromUnix(946684800)
    setLastModificationTime(path, old)
    check batchpad("convert", src, path)[0] == 0
    check getLastModificationTime(path) == old
    check batchpad("convert", src, path, "--always-write")[0] == 0
    check getLastModificationTime(path) != old

  test "bin":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("bin", src, "chars=" & tmp / "chars.bin", "map=" & tmp / "map.bin")[0] == 0
    check readFile(tmp / "chars.bin").len == 6 * 8
    check readFile(tmp / "map.bin") == "\x01\x02\x03\x01\x02\x03\x02\x03\x01\x02\x03\x01\x00\x01\x00\x01\x00\x01"
    let (code, area) = batchpad("bin", src, "map=-", "--area", "1,1,2,2")
    check code == 0 and area == "\x03\x01\x01\x00"

  test "bin load addresses":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("bin", src, "--load-address", "$2000", "chars=" & tmp / "a.prg",
                   "tile-tags=" & tmp / "b.prg@0x4000", "tile-attribs=" & tmp / "c.prg@49152")[0] == 0
    check readFile(tmp / "a.prg")[0..1] == "\x00\x20"
    check readFile(tmp / "b.prg") == "\x00\x40\x00\x01\x02\x03"
    check readFile(tmp / "c.prg")[0..1] == "\x00\xc0"
    check batchpad("bin", src, "chars=" & tmp / "x.prg@$10000")[0] == 2

  test "bin argument errors":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("bin", src)[0] == 2
    check batchpad("bin", src, "frob=" & tmp / "x.bin")[0] == 2
    check batchpad("bin", src, "chars")[0] == 2
    check batchpad("bin", src, "chars=" & tmp / "x.bin", "map=" & tmp / "x.bin")[0] == 2
    check batchpad("bin", src, "tile-names=" & tmp / "x.bin")[0] == 2
    check batchpad("bin", src, "--area", "1,2", "map=" & tmp / "x.bin")[0] == 2
    check not fileExists(tmp / "x.bin")

  test "bin writes nothing when one part fails":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("bin", src, "chars=" & tmp / "y.bin", "map-lo=" & tmp / "z.bin")[0] == 1
    check not fileExists(tmp / "y.bin")
    check batchpad("bin", files / "ctm9" / "ecm_perproject_notiles.ctm",
                   "chars=" & tmp / "y.bin", "tiles=" & tmp / "z.bin")[0] == 1
    check not fileExists(tmp / "y.bin")

  test "bin sub-maps":
    let src = files / "ctm9" / "hiresbitmap_perchar.ctm"   # 6 x 3 map, 3 x 2 grid
    check batchpad("bin", src, "submaps=" & tmp / "all.bin",
                   "submaps=" & tmp / "room_{y}_{x}.prg@$c000")[0] == 0
    check readFile(tmp / "all.bin").len == 12
    check readFile(tmp / "room_0_0.prg")[0..1] == "\x00\xc0"
    check readFile(tmp / "room_0_1.prg").len == 2 + 6
    check readFile(tmp / "all.bin")[6..^1] == readFile(tmp / "room_0_1.prg")[2..^1]
    check not fileExists(tmp / "room_1_0.prg")
    check batchpad("bin", src, "submaps=" & tmp / "room_{y}.bin")[0] == 2
    check batchpad("bin", src, "--set", "flexi-grid=7,1", "submaps=" & tmp / "x.bin")[0] == 1
    check batchpad("bin", src, "--set", "flexi-grid=0,1", "submaps=" & tmp / "x.bin")[0] == 1
    check batchpad("bin", files / "spd5" / "tiles_anims.spd", "submaps=" & tmp / "x.bin")[0] == 1
    check not fileExists(tmp / "x.bin")
    let (code, info) = batchpad("info", src)
    check code == 0 and "subMapsAcross: 2\nsubMapsDown: 1\n" in info

  test "bin colour map":
    check batchpad("bin", files / "ctm9" / "hirestext_perchar_notiles.ctm",
                   "--set", "colouring=project", "--set", "colour=6",
                   "colour-map=" & tmp / "blue.bin")[0] == 0
    check readFile(tmp / "blue.bin") == "\x06".repeat(12)
    check batchpad("bin", files / "ctm9" / "hirestext_perchar_notiles.ctm",
                   "colour-map=" & tmp / "plain.bin")[0] == 0
    check readFile(tmp / "plain.bin") == "\x02\x05\x07\x0d\x0e\x01\x0e\x0d\x07\x05\x02\x01"
    check batchpad("bin", files / "ctm9" / "mctext_pertile.ctm",
                   "colour-map=" & tmp / "tiles.bin")[0] == 0
    let tiles = readFile(tmp / "tiles.bin")
    check tiles.len == 12 * 6
    check tiles[0 .. 11] == "\x0a\x0a\x0d\x0d\x0f\x0f\x0a\x0a\x0d\x0d\x0f\x0f"
    check batchpad("bin", files / "spd5" / "tiles_anims.spd", "colour-map=" & tmp / "x.bin")[0] == 1

  test "asm":
    let (code, text) = batchpad("asm", files / "ctm9" / "mctext_pertile.ctm",
                                "--prefix", "lv_", "--parts", "chars,tile-names,map",
                                "--org", "chars=$2000", "--cells", "16")
    check code == 0
    check "; Generated by batchpad from mctext_pertile.ctm, after the CharPad Pro template." in text
    check "lv_addr_charset_data = $2000\n" in text
    check "lv_map_data_hi\n" in text
    check "; \"bands\"\n.byte $62,$61,$6e,$64,$73,$00\n" in text
    check "\r" notin text
    let (scode, sprites) = batchpad("asm", files / "spd5" / "tiles_anims.spd",
                                    "--dialect", "ca65", "--segment", "DATA", "--eol", "crlf")
    check scode == 0
    check ".segment \"DATA\"\r\n" in sprites
    check "spritetile_anims_attrib:\r\n" in sprites
    check batchpad("asm", files / "spd5" / "tiles_anims.spd", "--org", "map=$1000")[0] == 1
    check batchpad("asm", files / "spd5" / "tiles_anims.spd", "--org", "sprites")[0] == 2
    check batchpad("asm", files / "ctm9" / "mctext_perchar_big.ctm")[0] == 1
    let (ecode, events) = batchpad("asm", files / "ctm9" / "mctext_pertile.ctm",
                                   "--parts", "tile-events", "--event-labels", "alt",
                                   "--no-event-stubs")
    check ecode == 0
    check ".word empty, solid, box, bands\n" in events
    check "rts" notin events
    check batchpad("asm", files / "ctm9" / "hirestext_perchar_notiles.ctm",
                   "--parts", "tile-events")[0] == 1

  test "c":
    let (code, text) = batchpad("c", files / "ctm9" / "mctext_pertile.ctm",
                                "--prefix", "lv_", "--parts", "chars,tile-events",
                                "--event-stubs", "--org", "chars=$2000")
    check code == 0
    check "// Generated by batchpad from mctext_pertile.ctm, after the CharPad Pro template." in text
    check "#define lv_addr_charset_data 0x2000\n" in text
    check "#pragma data(lv_sec_charset_data)\n" in text
    check "__export const unsigned char lv_charset_data[] = {\n" in text
    check "void lv_chtl_box_event(void) {}\n" in text
    check "#include" notin text
    let header = tmp / "c.h"
    let source = tmp / "c.c"
    check batchpad("c", files / "spd5" / "tiles_anims.spd", "-o", source, "--header", header)[0] == 0
    check "#pragma compile(\"c.c\")\n" in readFile(header)
    check "extern const unsigned char spriteset_data[];\n" in readFile(header)
    check "#include \"c.h\"\n" in readFile(source)
    check batchpad("c", files / "spd5" / "tiles_anims.spd", "--header", header)[0] == 2
    check batchpad("c", files / "spd5" / "tiles_anims.spd", "-o", header, "--header", header)[0] == 2
    check batchpad("c", files / "spd5" / "tiles_anims.spd", "--prefix", "1")[0] == 1
    check batchpad("c", files / "spd5" / "tiles_anims.spd", "--org", "map=$1000")[0] == 1

  test "png":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("png", src, "map", "-o", tmp / "map.png", "--scale", "2")[0] == 0
    let png = readFile(tmp / "map.png")
    check png.startsWith("\x89PNG\r\n\x1a\n")
    # 12 x 6 chars of 8 pixels, doubled: 192 x 96.
    check png[16 .. 23] == "\0\0\0\xc0\0\0\0\x60"
    let (code, text) = batchpad("png", files / "spd5" / "sprites.spd", "sprites", "--columns", "3")
    check code == 0 and text.startsWith("\x89PNG")
    var pal = ""
    for i in 0 .. 15: pal.add "#" & toHex(i, 2) & "0000\n"
    writeFile(tmp / "red.pal", pal)
    check batchpad("png", src, "chars", "--palette", tmp / "red.pal", "-o", tmp / "red.png")[0] == 0
    check readFile(tmp / "red.png").contains("\x00\x00\x00\x01\x00\x00")
    check batchpad("png", src, "chars", "--palette", tmp / "nope.pal")[0] == 1
    check batchpad("png", src, "sprites")[0] == 1
    check batchpad("png", src, "chars", "--scale", "0")[0] == 2
    check batchpad("png", src, "chars", "--columns", "x")[0] == 2

  test "gif":
    let src = files / "spd5" / "tiles_anims.spd"
    check batchpad("gif", src, "--anim", "0", "-o", tmp / "a.gif", "--scale", "2")[0] == 0
    check readFile(tmp / "a.gif").startsWith("GIF89a")
    let (tcode, tiles) = batchpad("gif", src, "--tile-anim", "0", "--tick", "40")
    check tcode == 0 and tiles.startsWith("GIF89a")
    check batchpad("gif", src)[0] == 2
    check batchpad("gif", src, "--anim", "0", "--tile-anim", "0")[0] == 2
    check batchpad("gif", src, "--anim", "x")[0] == 2
    check batchpad("gif", src, "--anim", "0", "--tick", "0")[0] == 2
    check batchpad("gif", src, "--anim", "99")[0] == 1
    check batchpad("gif", files / "ctm9" / "mctext_pertile.ctm", "--anim", "0")[0] == 1

  test "stats":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    let (code, text) = batchpad("stats", src)
    check code == 0
    check text.startsWith("Char usage of mctext_pertile.ctm\n6 chars, 1 not used\n")
    let (tcode, tiles) = batchpad("stats", src, "--of", "tiles", "--eol", "crlf")
    check tcode == 0 and "   3       4  bands\r\n" in tiles
    check batchpad("stats", src, "--of", "sprites")[0] == 2
    check batchpad("stats", files / "ctm9" / "hirestext_perchar_notiles.ctm", "--of", "tiles")[0] == 1
    check batchpad("stats", files / "spd5" / "sprites.spd")[0] == 1

  test "import":
    let src = files / "ctm9" / "mctext_pertile.ctm"
    check batchpad("bin", src, "chars=" & tmp / "ic.bin", "tiles=" & tmp / "it.bin",
                   "tile-attribs=" & tmp / "ia.bin", "map=" & tmp / "im.bin")[0] == 0
    let before = readCtm(src)
    let args = @["import", "-o", tmp / "imp.ctm", "chars=" & tmp / "ic.bin", "tiles=" & tmp / "it.bin",
                 "tile-attribs=" & tmp / "ia.bin", "map=" & tmp / "im.bin",
                 "--tile-size", $before.tileWidth & "x" & $before.tileHeight,
                 "--map-size", $before.mapWidth & "x" & $before.mapHeight]
    check batchpad(args)[0] == 0
    let p = readCtm(tmp / "imp.ctm")
    check p.chars.mapIt(it.data) == before.chars.mapIt(it.data)
    check p.tiles.mapIt(it.cells) == before.tiles.mapIt(it.cells)
    check p.map == before.map and p.colouring == cmPerTile
    check batchpad(args & @["--to", "ctm7"])[0] == 0 and readCtm(tmp / "imp.ctm").version == 7
    check batchpad(args & @["--set", "colouring=project"])[0] == 0
    check readCtm(tmp / "imp.ctm").colouring == cmPerProject

  test "import sprites, load address":
    writeFile(tmp / "sp.bin", "\x00\x20" & repeat('\x05', 62) & "\x00" & "\x11")
    # 66 bytes: 2 mod 64, so detect skips the address and reports it
    let (code, err) = warnings("import", "-o", tmp / "imp.spd", "sprites=" & tmp / "sp.bin")
    check code == 0 and "load address $2000" in err
    check readSpd(tmp / "imp.spd").sprites.len == 1
    check warnings("import", "-o", tmp / "imp2.spd", "--load-address", "none",
                   "sprites=" & tmp / "sp.bin")[0] == 1
    check not fileExists(tmp / "imp2.spd")
    check batchpad("import", "-o", tmp / "imp3.spd", "--sprite-attribs", "seuck",
                   "sprites=" & tmp / "sp.bin")[0] == 0
    check readSpd(tmp / "imp3.spd").sprites[0].attributes == 0x81

  test "import argument errors":
    check batchpad("import", "-o", tmp / "x.ctm")[0] == 2
    check batchpad("import", "-o", tmp / "x.bin", "chars=" & tmp / "ic.bin")[0] == 2
    check batchpad("import", "-o", tmp / "x.ctm", "frob=" & tmp / "ic.bin")[0] == 2
    check batchpad("import", "-o", tmp / "x.ctm", "sprites=" & tmp / "ic.bin")[0] == 2
    check batchpad("import", "-o", tmp / "x.ctm", "chars=" & tmp / "ic.bin", "chars=" & tmp / "ic.bin")[0] == 2
    check batchpad("import", "-o", tmp / "x.ctm", "chars=" & tmp / "ic.bin", "--map-size", "3")[0] == 2
    check batchpad("import", "-o", tmp / "x.ctm", "chars=" & tmp / "missing.bin")[0] == 1
    check batchpad("import", "-o", tmp / "x.ctm", "map=" & tmp / "im.bin")[0] == 1
    check not fileExists(tmp / "x.ctm")

removeDir(tmp)
