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
    check batchpad("bin", files / "spd5" / "sprites.spd", "sprites=" & tmp / "s.bin")[0] == 1

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

removeDir(tmp)
