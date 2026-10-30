## The command line, as designed in docs/cli.md.

import std/[bitops, json, options, os, streams, strutils, tables]
import argparse
import asmout, cout, ctm, image, preview, rawbin, rawimport, spd, stats

type
  CliError* = object of CatchableError
    ## An error in the input or a refusal: exit code 1.

  Kind = enum
    kCtm, kSpd

  Input = object
    case kind: Kind
    of kCtm: ctm: ctm.Project
    of kSpd: spd: SpriteProject

  Output = object
    path: string
    data: string

const
  modeNames: array[DisplayMode, string] =
    ["hires", "multicolour", "ecm", "hires-bitmap", "multicolour-bitmap"]
  colouringNames: array[ColouringMethod, string] = ["project", "tile", "char"]
  version = block:
    var v = ""
    for line in staticRead("../../batchpad.nimble").splitLines:
      if line.startsWith("version"): v = line.split('"')[1]
    v

proc fail(msg: string) {.noreturn.} = raise newException(CliError, msg)

proc notYet(issue: string) {.noreturn.} = fail("not implemented yet (" & issue & ")")

proc readInput(path, format: string): Input =
  let data = try: (if path == "-": stdin.readAll else: readFile(path))
             except IOError as e: fail(e.msg)
  let kind =
    case format
    of "ctm": kCtm
    of "spd": kSpd
    of "":
      if data.startsWith("CTM"): kCtm
      elif data.startsWith("SPD"): kSpd
      else: fail("not a CharPad or SpritePad project")
    else: fail("unknown input format: " & format)
  case kind
  of kCtm: Input(kind: kCtm, ctm: parseCtm(data.toOpenArrayByte(0, data.high)))
  of kSpd: Input(kind: kSpd, spd: parseSpd(data.toOpenArrayByte(0, data.high)))

proc colourValue(name, value: string): uint8 =
  let n = try: parseInt(value) except ValueError: -1
  if n notin 0..15: fail(name & " must be 0-15, not " & value)
  uint8(n)

proc pick[T](name, value: string, names: array[T, string]): T =
  for t, s in names:
    if s == value: return t
  fail(name & " must be one of " & names.join(", ") & ", not " & value)

proc applySet(p: var ctm.Project, name, value: string) =
  case name
  of "mode": p.displayMode = pick(name, value, modeNames)
  of "colouring": p.colouring = pick(name, value, colouringNames)
  of "bg0", "bg1", "bg2", "bg3": p.chipColours[ord(name[2]) - ord('0')] = colourValue(name, value)
  of "colour": p.colours[0] = colourValue(name, value)
  of "vmx-lo": p.colours[1] = colourValue(name, value)
  of "vmx-hi": p.colours[2] = colourValue(name, value)
  of "key-map": p.keyMap = colourValue(name, value)
  of "tiles":
    if value != "off": fail("tiles can only be set to off")
    try: p.expandTiles
    except CtmError as e: fail(e.msg)
  of "flexi-grid":
    if value == "off":
      p.flexiGrid.settings = p.flexiGrid.settings and 0x7f
    else:
      let wh = value.split(',')
      try:
        if wh.len != 2: raise newException(ValueError, "")
        let (w, h) = (parseInt(wh[0]), parseInt(wh[1]))
        if w notin 1..256 or h notin 1..256: raise newException(ValueError, "")
        p.flexiGrid.width = uint16(w)
        p.flexiGrid.height = uint16(h)
      except ValueError:
        fail("flexi-grid must be W,H (1-256 each) or off, not " & value)
      p.flexiGrid.settings = p.flexiGrid.settings or 0x80
  else: fail("unknown CharPad setting: " & name)

proc applySet(p: var SpriteProject, name, value: string) =
  case name
  of "bg": p.colours[0] = colourValue(name, value)
  of "mc1": p.colours[1] = colourValue(name, value)
  of "mc2": p.colours[2] = colourValue(name, value)
  of "sprite-overlay", "tile-overlay":
    let n = try: parseInt(value) except ValueError: int.high
    if n notin -32768..32767: fail(name & " must be -32768 to 32767, not " & value)
    if name == "sprite-overlay": p.spriteOverlay = int16(n) else: p.tileOverlay = int16(n)
  of "tiles":
    if value != "off": fail("tiles can only be set to off")
    p.tileSystem = false
    p.tiles = @[]
    p.tileAnims = @[]
  else: fail("unknown SpritePad setting: " & name)

proc applySets(input: var Input, sets: seq[string]) =
  for s in sets:
    let eq = s.find('=')
    if eq < 1: fail("--set needs name=value, not " & s)
    let (name, value) = (s[0 ..< eq], s[eq + 1 .. ^1])
    case input.kind
    of kCtm: input.ctm.applySet(name, value)
    of kSpd: input.spd.applySet(name, value)

proc toStr(data: seq[byte]): string =
  result = newString(data.len)
  if data.len > 0: copyMem(result[0].addr, data[0].unsafeAddr, data.len)

proc writeOutputs(outputs: seq[Output], alwaysWrite: bool, output: Stream) =
  ## Called only once everything is made, so an error writes nothing.
  for o in outputs:
    if o.path == "-":
      output.write(o.data)
    elif alwaysWrite or not fileExists(o.path) or readFile(o.path) != o.data:
      try: writeFile(o.path, o.data)
      except IOError as e: fail(e.msg)

proc info(input: Input): JsonNode =
  case input.kind
  of kCtm:
    let p = input.ctm
    result = %*{"format": "ctm", "version": p.version,
                "mode": modeNames[p.displayMode], "colouring": colouringNames[p.colouring],
                "chipColours": p.chipColours, "colours": p.colours,
                "chars": p.chars.len, "tileSystem": p.tileSystem,
                "mapWidth": p.mapWidth, "mapHeight": p.mapHeight}
    if p.tileSystem:
      result["tiles"] = %p.tiles.len
      result["tileWidth"] = %p.tileWidth
      result["tileHeight"] = %p.tileHeight
    if p.version >= 9:
      result["keyMap"] = %p.keyMap
      if p.flexiGrid.settings.testBit(7):
        result["flexiGrid"] = %*{"width": p.flexiGrid.width, "height": p.flexiGrid.height}
        try:
          let s = p.subMaps
          result["subMapsAcross"] = %s.across
          result["subMapsDown"] = %s.down
        except BinError: discard
  of kSpd:
    let p = input.spd
    result = %*{"format": "spd", "version": p.version, "colours": p.colours,
                "sprites": p.sprites.len, "tileSystem": p.tileSystem,
                "spriteOverlay": p.spriteOverlay, "tileOverlay": p.tileOverlay,
                "spriteAnims": p.spriteAnims.len, "tileAnims": p.tileAnims.len}
    if p.tileSystem:
      result["tiles"] = %p.tiles.len
      result["tileWidth"] = %p.tileWidth
      result["tileHeight"] = %p.tileHeight

proc infoText(j: JsonNode): string =
  for key, value in j:
    result.add key & ": " & (if value.kind == JString: value.getStr else: $value) & "\n"

proc convert(input: Input, path, to: string, leftOut: var seq[string]): Output =
  var to = to
  if to == "":
    to = case path.splitFile.ext.toLowerAscii
         of ".ctm": "ctm9"
         of ".spd": "spd5"
         else: fail("can't tell the output format from " & path & "; use --to")
  let (kind, version) =
    if to.startsWith("ctm"): (kCtm, to[3 .. ^1])
    elif to.startsWith("spd"): (kSpd, to[3 .. ^1])
    else: fail("unknown output format: " & to)
  if kind != input.kind:
    fail("can't convert a " & ($input.kind)[1 .. ^1].toUpperAscii & " project to " & to)
  let v = try: parseInt(version) except ValueError: fail("unknown output format: " & to)
  let data = case kind
             of kCtm: input.ctm.toCtm(v, leftOut)
             of kSpd: input.spd.toSpd(v, leftOut)
  Output(path: path, data: data.toStr)

proc usage(msg: string) {.noreturn.} = raise newException(UsageError, msg)

proc parseAddress(s: string): int =
  ## `$c000`, `0xc000` or `49152`.
  result = try:
             if s.startsWith("$"): parseHexInt(s[1 .. ^1])
             elif s.toLowerAscii.startsWith("0x"): parseHexInt(s)
             else: parseInt(s)
           except ValueError: -1
  if result notin 0..0xffff: usage("not an address (0-65535): " & s)

proc parseArea(s: string): Area =
  let n = s.split(',')
  try:
    if n.len != 4: raise newException(ValueError, "")
    Area(x: parseInt(n[0]), y: parseInt(n[1]), width: parseInt(n[2]), height: parseInt(n[3]))
  except ValueError:
    usage("--area must be X,Y,W,H, not " & s)

proc binOutputs(input: Input, specs: seq[string], o: BinOptions, loadAddress: string): seq[Output] =
  ## `specs` are `part=file`, or `part=file@ADDR` for a load address of its own.
  if specs.len == 0: usage("nothing to write: give part=file")
  let address = if loadAddress == "": -1 else: parseAddress(loadAddress)
  for spec in specs:
    let eq = spec.find('=')
    if eq < 1 or eq == spec.high: usage("expected part=file, not " & spec)
    let part = spec[0 ..< eq]
    var path = spec[eq + 1 .. ^1]
    var a = address
    let at = path.rfind('@')
    if at > 0:
      a = parseAddress(path[at + 1 .. ^1])
      path = path[0 ..< at]
    case part
    of "tile-names", "tile-events": usage(part & " is only written by asm and c")
    elif part notin ctmParts and part notin spdParts: usage("unknown part: " & part)
    template add(file: string, bytes: seq[byte]) =
      let p = file
      for earlier in result:
        if p != "-" and earlier.path == p: usage(p & " is named twice")
      var data = bytes
      if a >= 0: data = @[byte(a and 0xff), byte(a shr 8)] & data
      result.add Output(path: p, data: data.toStr)
    if part.startsWith("submaps") and ("{y}" in path or "{x}" in path):
      # One file per sub-map.
      if input.kind != kCtm: fail("a SpritePad project has no part " & part)
      let s = input.ctm.subMaps
      if ("{y}" notin path and s.down > 1) or ("{x}" notin path and s.across > 1):
        usage(path & ": the grid makes " & $s.across & " x " & $s.down &
              " sub-maps; name them with {x} and {y}")
      for y in 0 ..< s.down:
        for x in 0 ..< s.across:
          add(path.replace("{y}", $y).replace("{x}", $x), input.ctm.binSubMap(y, x, part, o))
    else:
      add(path, case input.kind
                of kCtm: input.ctm.binPart(part, o)
                of kSpd: input.spd.binPart(part, o))

proc parseSize(name, s: string): (int, int) =
  let n = s.split({'x', 'X'})
  try:
    if n.len != 2: raise newException(ValueError, "")
    result = (parseInt(n[0]), parseInt(n[1]))
    if result[0] < 1 or result[1] < 1: raise newException(ValueError, "")
  except ValueError:
    usage(name & " must be WxH, not " & s)

proc importOutput(o: auto, warnings: var seq[string]): Output =
  ## `import`: reads the parts, builds the project and formats it.
  var to = o.to
  if to == "":
    to = case o.output.splitFile.ext.toLowerAscii
         of ".ctm": "ctm9"
         of ".spd": "spd5"
         else: usage("can't tell the output format from " & o.output & "; use --to")
  let isCtm = to.startsWith("ctm")
  if not isCtm and not to.startsWith("spd"): usage("unknown output format: " & to)
  let version = try: parseInt(to[3 .. ^1]) except ValueError: usage("unknown output format: " & to)
  if o.parts.len == 0: usage("nothing to import: give part=file")
  var opts = ImportOptions(cells: parseEnum[CellFormat](o.cells),
                           spriteAttribs: parseEnum[SpriteAttribStyle](o.spriteAttribs))
  if o.tileSize != "": (opts.tileWidth, opts.tileHeight) = parseSize("--tile-size", o.tileSize)
  if o.mapSize != "": (opts.mapWidth, opts.mapHeight) = parseSize("--map-size", o.mapSize)
  var parts: Parts
  for spec in o.parts:
    let eq = spec.find('=')
    if eq < 1 or eq == spec.high: usage("expected part=file, not " & spec)
    let (part, path) = (spec[0 ..< eq], spec[eq + 1 .. ^1])
    if part notin (if isCtm: @ctmImportParts else: @spdImportParts):
      usage(part & " can't be imported into a " & (if isCtm: "CharPad" else: "SpritePad") & " project")
    if part in parts: usage(part & " is given twice")
    let text = try: (if path == "-": stdin.readAll else: readFile(path))
               except IOError as e: fail(e.msg)
    let unit = case part
               of "chars": 8
               of "sprites": 64
               else: 0
    let (data, address) = stripLoadAddress(text.toOpenArrayByte(0, text.high).toSeq, o.loadAddress, unit)
    if address.isSome:
      warnings.add path & ": load address $" & toHex(address.get, 4).toLowerAscii
    parts[part] = data
  var data: seq[byte]
  var leftOut: seq[string]
  if isCtm:
    var p = newCtmProject()
    for s in o.set:
      let eq = s.find('=')
      if eq < 1: fail("--set needs name=value, not " & s)
      p.applySet(s[0 ..< eq], s[eq + 1 .. ^1])
      if s[0 ..< eq] == "colouring": opts.keepColouring = true
    data = importCtm(parts, opts, p).toCtm(version, leftOut)
  else:
    var p = newSpdProject()
    for s in o.set:
      let eq = s.find('=')
      if eq < 1: fail("--set needs name=value, not " & s)
      p.applySet(s[0 ..< eq], s[eq + 1 .. ^1])
    data = importSpd(parts, opts, p).toSpd(version, leftOut)
  for l in leftOut: warnings.add o.output & ": left out " & l
  Output(path: o.output, data: data.toStr)

proc asmOutput(input: Input, o: AsmOptions): string =
  case input.kind
  of kCtm: input.ctm.toAsm(o)
  of kSpd: input.spd.toAsm(o)

proc parseOrg(specs: seq[string]): seq[(string, int)] =
  for spec in specs:
    let eq = spec.find('=')
    if eq < 1 or eq == spec.high: usage("--org needs part=ADDR, not " & spec)
    result.add (spec[0 ..< eq], parseAddress(spec[eq + 1 .. ^1]))

template common() =
  option("--input-format", choices = @["ctm", "spd"], help = "Format of the input, if not detected")
  option("--set", multiple = true, help = "Overrides a project setting: name=value")
  flag("--quiet", help = "Hides warnings about what is left out")
  flag("--strict", help = "Makes those warnings errors")
  flag("--always-write", help = "Writes outputs even when unchanged")

let parser = newParser("batchpad"):
  help("Converts CharPad and SpritePad projects into build artifacts. See docs/cli.md.")
  flag("--version", shortcircuit = true, help = "Prints the version")
  command("info"):
    help("Prints what a project holds")
    option("--input-format", choices = @["ctm", "spd"], help = "Format of the input, if not detected")
    flag("--json", help = "Prints JSON")
    arg("input")
  command("convert"):
    help("Writes the project in another project format")
    option("--to", help = "ctm4 to ctm9, spd1, spd2, spd4 or spd5; default from the output's extension")
    common()
    arg("input")
    arg("output")
  command("bin"):
    help("Writes raw binary parts: part=file ...")
    option("--cells", choices = @["8", "12", "16", "word"], default = some("8"),
           help = "Cell width of tiles, map and sub-maps")
    option("--area", help = "Only this part of the map: X,Y,W,H")
    option("--sprite-attribs", choices = @["spritepad", "seuck", "blank"],
           default = some("spritepad"), help = "64th byte style of sprites")
    option("--load-address", help = "Writes a PRG load address in front of every file")
    common()
    arg("input")
    arg("parts", nargs = -1)
  command("asm"):
    help("Writes assembler source")
    option("-o", "--output", default = some("-"), help = "Output file")
    option("--dialect", choices = @["64tass", "acme", "kickass", "ca65"], default = some("64tass"))
    option("--parts", help = "Comma-separated parts to include")
    option("--prefix", help = "Put before every label and constant")
    option("--org", multiple = true, help = "part=ADDR: a * = line before that part")
    option("--segment", help = "Segment for ca65 and KickAssembler")
    option("--event-labels", choices = @["normal", "alt"], default = some("normal"))
    flag("--no-event-stubs", help = "Leaves out the rts per tile event; the program defines them")
    option("--eol", choices = @["lf", "crlf"], default = some("lf"))
    option("--cells", choices = @["8", "12", "16", "word"], default = some("8"))
    option("--area", help = "Only this part of the map: X,Y,W,H")
    option("--sprite-attribs", choices = @["spritepad", "seuck", "blank"],
           default = some("spritepad"), help = "64th byte style of sprites")
    common()
    arg("input")
  command("c"):
    help("Writes C source for oscar64")
    option("-o", "--output", default = some("-"), help = "Output file")
    option("--header", help = "Also writes a header with the declarations")
    option("--parts", help = "Comma-separated parts to include")
    option("--prefix", help = "Put before every name")
    option("--org", multiple = true, help = "part=ADDR: places that part at the address")
    flag("--event-stubs", help = "Writes empty event functions")
    option("--event-labels", choices = @["normal", "alt"], default = some("normal"))
    option("--eol", choices = @["lf", "crlf"], default = some("lf"))
    option("--cells", choices = @["8", "12", "16", "word"], default = some("8"))
    option("--area", help = "Only this part of the map: X,Y,W,H")
    option("--sprite-attribs", choices = @["spritepad", "seuck", "blank"],
           default = some("spritepad"), help = "64th byte style of sprites")
    common()
    arg("input")
  command("png"):
    help("Writes a preview image")
    option("-o", "--output", default = some("-"), help = "Output file")
    option("--palette", help = ".pal file")
    option("--scale", default = some("1"))
    option("--columns", help = "Items per row in a sheet")
    common()
    arg("input")
    arg("part")
  command("gif"):
    help("Writes an animated GIF of a SpritePad animation")
    option("-o", "--output", default = some("-"), help = "Output file")
    option("--anim", help = "Sprite animation number")
    option("--tile-anim", help = "Tile animation number")
    option("--tick", default = some("20"), help = "Milliseconds of one timer tick")
    option("--palette", help = ".pal file")
    option("--scale", default = some("1"))
    common()
    arg("input")
  command("stats"):
    help("Writes usage statistics")
    option("-o", "--output", default = some("-"), help = "Output file")
    option("--of", choices = @["chars", "tiles"], default = some("chars"))
    option("--eol", choices = @["lf", "crlf"], default = some("lf"))
    common()
    arg("input")
  command("import"):
    help("Builds a project from raw binary parts: part=file ...")
    option("-o", "--output", required = true, help = "Project file to write")
    option("--to", help = "ctm4 to ctm9, spd1, spd2, spd4 or spd5; default from the output's extension")
    option("--tile-size", help = "WxH")
    option("--map-size", help = "WxH")
    option("--cells", choices = @["8", "12", "16", "word"], default = some("8"))
    option("--sprite-attribs", choices = @["spritepad", "seuck", "blank"], default = some("spritepad"))
    option("--load-address", choices = @["skip", "detect", "none"], default = some("detect"))
    option("--set", multiple = true, help = "Sets a project setting: name=value")
    flag("--always-write", help = "Writes the output even when unchanged")
    arg("parts", nargs = -1)

proc run*(args: seq[string], output: Stream = newFileStream(stdout),
           errors: Stream = newFileStream(stderr)): int =
  ## Runs batchpad with `args` and returns its exit code. Errors and warnings
  ## go to `errors`.
  var inputPath = ""

  proc load(path, format: string, sets: seq[string] = @[]): Input =
    inputPath = path
    result = readInput(path, format)
    result.applySets(sets)

  try:
    let opts = parser.parse(args, quitOnHelp = false)
    var outputs: seq[Output]
    var alwaysWrite = false
    case opts.command
    of "info":
      let o = opts.argparse_info_opts.get
      let j = load(o.input, o.inputFormat).info
      outputs.add Output(path: "-", data: if o.json: j.pretty & "\n" else: j.infoText)
    of "convert":
      let o = opts.argparse_convert_opts.get
      alwaysWrite = o.alwaysWrite
      var leftOut: seq[string]
      outputs.add load(o.input, o.inputFormat, o.set).convert(o.output, o.to, leftOut)
      if o.strict and leftOut.len > 0:
        fail("--strict: " & o.output & " can't hold " & leftOut.join("; "))
      if not o.quiet:
        for l in leftOut: errors.writeLine "batchpad: " & o.output & ": warning: left out " & l
    of "bin":
      let o = opts.argparse_bin_opts.get
      alwaysWrite = o.alwaysWrite
      var bo = BinOptions(cells: parseEnum[CellFormat](o.cells),
                          spriteAttribs: parseEnum[SpriteAttribStyle](o.spriteAttribs))
      if o.area != "": bo.area = some(parseArea(o.area))
      outputs.add load(o.input, o.inputFormat, o.set).binOutputs(o.parts, bo, o.loadAddress)
    of "asm":
      let o = opts.argparse_asm_opts.get
      alwaysWrite = o.alwaysWrite
      var ao = AsmOptions(dialect: parseEnum[Dialect](o.dialect), prefix: o.prefix,
                          org: parseOrg(o.org), segment: o.segment, crlf: o.eol == "crlf",
                          bin: BinOptions(cells: parseEnum[CellFormat](o.cells),
                                          spriteAttribs: parseEnum[SpriteAttribStyle](o.spriteAttribs)),
                          source: if o.input == "-": "stdin" else: o.input.extractFilename,
                          altEventLabels: o.eventLabels == "alt", eventStubs: not o.noEventStubs)
      if o.area != "": ao.bin.area = some(parseArea(o.area))
      if o.parts != "": ao.parts = o.parts.split(',')
      outputs.add Output(path: o.output, data: load(o.input, o.inputFormat, o.set).asmOutput(ao))
    of "c":
      let o = opts.argparse_c_opts.get
      alwaysWrite = o.alwaysWrite
      var ao = AsmOptions(prefix: o.prefix, org: parseOrg(o.org), crlf: o.eol == "crlf",
                          bin: BinOptions(cells: parseEnum[CellFormat](o.cells),
                                          spriteAttribs: parseEnum[SpriteAttribStyle](o.spriteAttribs)),
                          source: if o.input == "-": "stdin" else: o.input.extractFilename,
                          altEventLabels: o.eventLabels == "alt", eventStubs: o.eventStubs)
      if o.area != "": ao.bin.area = some(parseArea(o.area))
      if o.parts != "": ao.parts = o.parts.split(',')
      if o.header != "" and o.output == "-": usage("--header needs -o: the header is included by the source")
      let input = load(o.input, o.inputFormat, o.set)
      let c = case input.kind
              of kCtm: input.ctm.toC(ao, o.header, o.output.extractFilename)
              of kSpd: input.spd.toC(ao, o.header, o.output.extractFilename)
      outputs.add Output(path: o.output, data: c.source)
      if o.header != "":
        if o.header == o.output: usage("--header names the same file as -o")
        outputs.add Output(path: o.header, data: c.header)
    of "png":
      let o = opts.argparse_png_opts.get
      alwaysWrite = o.alwaysWrite
      let scale = try: parseInt(o.scale) except ValueError: 0
      if scale notin 1..64: usage("--scale must be 1-64, not " & o.scale)
      let columns = if o.columns == "": 0 else: (try: parseInt(o.columns) except ValueError: 0)
      if o.columns != "" and columns < 1: usage("--columns must be a positive number, not " & o.columns)
      let palette = if o.palette == "": pepto else: readPalette(o.palette)
      let input = load(o.input, o.inputFormat, o.set)
      let picture = case input.kind
                    of kCtm: input.ctm.previewCtm(o.part, columns)
                    of kSpd: input.spd.previewSpd(o.part, columns)
      outputs.add Output(path: o.output, data: picture.toPng(palette, scale))
    of "gif":
      let o = opts.argparse_gif_opts.get
      alwaysWrite = o.alwaysWrite
      if (o.anim == "") == (o.tileAnim == ""): usage("give one of --anim and --tile-anim")
      let scale = try: parseInt(o.scale) except ValueError: 0
      if scale notin 1..64: usage("--scale must be 1-64, not " & o.scale)
      let tick = try: parseInt(o.tick) except ValueError: 0
      if tick notin 1..1000: usage("--tick must be 1-1000 milliseconds, not " & o.tick)
      let tiles = o.tileAnim != ""
      let numberText = if tiles: o.tileAnim else: o.anim
      let number = try: parseInt(numberText) except ValueError: -1
      if number < 0: usage("the animation number must be 0 or more, not " & numberText)
      let palette = if o.palette == "": pepto else: readPalette(o.palette)
      let input = load(o.input, o.inputFormat, o.set)
      if input.kind != kSpd: fail("only SpritePad projects have animations")
      let frames = input.spd.animationFrames(tiles, number)
      let timer = int((if tiles: input.spd.tileAnims else: input.spd.spriteAnims)[number].timer)
      # GIF counts hundredths of a second; viewers play less than 2 as 10.
      let delay = max(2, (timer * tick + 5) div 10)
      outputs.add Output(path: o.output, data: frames.toGif(palette, delay, scale))
    of "stats":
      let o = opts.argparse_stats_opts.get
      alwaysWrite = o.alwaysWrite
      let input = load(o.input, o.inputFormat, o.set)
      if input.kind != kCtm: fail("statistics are for CharPad projects")
      outputs.add Output(path: o.output, data: input.ctm.statsText(
        o.of, if o.input == "-": "stdin" else: o.input.extractFilename, o.eol == "crlf"))
    of "import":
      let o = opts.argparse_import_opts.get
      alwaysWrite = o.alwaysWrite
      var notes: seq[string]
      outputs.add importOutput(o, notes)
      for n in notes: errors.writeLine "batchpad: " & n
    else:
      errors.write(parser.help)
      errors.flush
      return 2
    outputs.writeOutputs(alwaysWrite, output)
    output.flush
    errors.flush
  except ShortCircuit as e:
    output.write(if e.flag == "version": "batchpad " & version & "\n" else: e.help)
    output.flush
  except UsageError as e:
    errors.writeLine "batchpad: " & e.msg
    errors.flush
    return 2
  except CliError, CtmError, SpdError, BinError, AsmError, ImageError, PreviewError, StatsError:
    let e = getCurrentException()
    errors.writeLine "batchpad: " & (if inputPath != "": inputPath & ": " else: "") & e.msg
    errors.flush
    return 1
