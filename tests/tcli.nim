import std/[os, streams, strutils, times, unittest]
import batchpad/[cli, ctm, spd]

const files = currentSourcePath().parentDir / "files"

proc batchpad(args: varargs[string]): (int, string) =
  let output = newStringStream()
  let code = run(@args, output)
  (code, output.data)

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
    check batchpad("convert", src, tmp / "b.ctm")[0] == 0
    check readCtm(tmp / "b.ctm").version == 9
    check batchpad("convert", src, tmp / "c.bin")[0] == 1
    check batchpad("convert", src, tmp / "c.spd")[0] == 1
    check not fileExists(tmp / "c.bin") and not fileExists(tmp / "c.spd")
    let (code, data) = batchpad("convert", src, "-", "--to", "ctm9")
    check code == 0 and data.startsWith("CTM\x09")

  test "convert with --set":
    let src = files / "spd5" / "sprites.spd"
    check batchpad("convert", src, tmp / "a.spd", "--to", "spd1", "--set", "bg=3",
                   "--set", "mc2=12")[0] == 0
    let p = readSpd(tmp / "a.spd")
    check p.version == 1 and p.colours[0] == 3 and p.colours[2] == 12
    check batchpad("convert", src, tmp / "b.spd", "--set", "mc1=99")[0] == 1
    check batchpad("convert", src, tmp / "b.spd", "--set", "frob=1")[0] == 1
    check not fileExists(tmp / "b.spd")

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

removeDir(tmp)
