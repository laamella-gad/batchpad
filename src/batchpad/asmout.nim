## Assembler source of a project, after the CharPad and SpritePad Pro templates
## (docs/import-export.md, "Assembler text"), for several assemblers. Options
## are described in docs/cli.md under asm.
##
## Unlike the templates, every label the file uses is defined, and there are
## no `* =` lines unless asked for, so the file assembles as it is.

import std/[options, strutils]
import binio, ctm, rawbin, spd

type
  AsmError* = object of ValueError

  Dialect* = enum
    d64tass = "64tass", dAcme = "acme", dKickAss = "kickass", dCa65 = "ca65"

  AsmOptions* = object
    dialect*: Dialect
    parts*: seq[string]            ## empty: what "Export All (one file)" writes
    prefix*: string                ## put before every label and constant
    org*: seq[(string, int)]       ## part and address of a `* =` line
    segment*: string
    crlf*: bool
    bin*: BinOptions               ## cells, area, sprite attributes
    source*: string                ## named in the first line

  Chunk = object
    label: string                  ## a label inside the block, or ""
    data: seq[byte]

  Block = object
    part: string                   ## what `--org` names it by
    label: string
    comments: seq[string]
    chunks: seq[Chunk]
    names: seq[string]             ## zero-terminated strings instead of chunks

const
  ctmAsmParts* = ["chars", "char-attribs", "char-attribs-l2", "char-materials",
                  "tiles", "tile-attribs", "tile-attribs-l2", "tile-tags",
                  "tile-names", "map"]
  spdAsmParts* = ["sprites", "sprite-attribs", "tiles", "tile-attribs",
                  "tile-tags", "tile-names", "sprite-anims", "tile-anims"]

proc fail(msg: string) {.noreturn.} = raise newException(AsmError, msg)

func size(b: Block): int =
  for c in b.chunks: result += c.data.len
  for n in b.names: result += n.len + 1

func hex(n: int): string =
  result = toHex(n).toLowerAscii.strip(trailing = false, chars = {'0'})
  if result == "": result = "0"

func sizeText(n: int): string = "total size is " & $n & " ($" & hex(n) & ") bytes."

# Cell parts

func split(o: BinOptions): bool = o.cells in {cf12, cf16}

func cellText(o: BinOptions): string =
  case o.cells
  of cf8: "8 bits per cell"
  of cf12: "12 bits per cell, split, high nybbles packed"
  of cf16: "16 bits per cell, split"
  of cfWord: "16 bits per cell, little-endian words"

proc cellBlocks[P](p: P, part, label: string, comments: seq[string], o: BinOptions): seq[Block] =
  ## One block, or two for split cells: `label_lo` and `label_hi` (or
  ## `label_hi_packed` for 12 bit).
  if not o.split:
    return @[Block(part: part, label: label, comments: comments,
                   chunks: @[Chunk(data: p.binPart(part, o))])]
  let hi = if o.cells == cf12: "_hi_packed" else: "_hi"
  result.add Block(part: part & "-lo", label: label & "_lo", comments: comments,
                   chunks: @[Chunk(data: p.binPart(part & "-lo", o))])
  result.add Block(part: part & "-hi", label: label & hi,
                   chunks: @[Chunk(data: p.binPart(part & "-hi", o))])

proc cellSize[P](p: P, part: string, o: BinOptions): int =
  if o.split: p.binPart(part & "-lo", o).len + p.binPart(part & "-hi", o).len
  else: p.binPart(part, o).len

# CharPad

func isBitmap(p: ctm.Project): bool = p.displayMode in {dmHiresBitmap, dmMulticolourBitmap}

func mapSize(p: ctm.Project, o: BinOptions): (int, int) =
  if o.area.isSome: (o.area.get.width, o.area.get.height) else: (p.mapWidth, p.mapHeight)

proc names(tiles: seq[ctm.Tile] | seq[SpriteTile]): seq[string] =
  for t in tiles: result.add t.name

const vmxNote = "nb. Upper nybbles = colour (video matrix high), lower nybbles = colour (video matrix low)."

proc blocks(p: ctm.Project, part: string, o: BinOptions): seq[Block] =
  let n = p.chars.len
  let c = p.tiles.len
  let hiresBitmap = p.displayMode == dmHiresBitmap
  template one(name: string, notes: seq[string]) =
    result.add Block(part: part, label: name, comments: notes,
                     chunks: @[Chunk(data: p.binPart(part, o))])
  case part
  of "chars":
    one("charset_data", @["CharSet Data...",
        count(n, "images") & ", 8 bytes per image, " & sizeText(n * 8)])
  of "char-attribs":
    one("charset_attrib_L1_data", @["CharSet Attribute (L1) Data...",
        count(n, "attributes") & ", 1 attribute per image, 8 bits per attribute, " & sizeText(n),
        if p.colouring == cmPerChar and not hiresBitmap:
          "nb. Upper nybbles = material, lower nybbles = colour (colour matrix low)."
        else: "nb. Upper nybbles = material, lower nybbles = unused."])
  of "char-attribs-l2":
    one("charset_attrib_L2_data", @["CharSet Attribute (L2) Data...",
        count(n, "attributes") & ", 1 attribute per image, 8 bits per attribute, " & sizeText(n),
        vmxNote])
  of "char-materials":
    one("charset_material_data", @["CharSet Material Data...",
        count(n, "materials") & ", 1 per image, 8 bits each, " & sizeText(n)])
  of "tiles":
    if not p.tileSystem: fail("the project has no tiles")
    let a = p.tileWidth * p.tileHeight
    result = p.cellBlocks(part, "chartileset_data", @["CharTileSet Data...",
        count(c, "tiles") & ", " & $p.tileWidth & "x" & $p.tileHeight & " (" & $a &
        ") cells per tile, " & o.cellText & ", " & sizeText(p.cellSize(part, o))], o)
  of "tile-attribs":
    one("chartileset_attrib_L1_data", @["CharTileSet Attribute Data (L1)...",
        count(c, "attributes") & ", 1 per tile, 8 bits each, " & sizeText(c),
        if hiresBitmap: "nb. Upper nybbles = unused, lower nybbles = unused."
        else: "nb. Upper nybbles = unused, lower nybbles = colour (colour matrix low)."])
  of "tile-attribs-l2":
    one("chartileset_attrib_L2_data", @["CharTileSet Attribute Data (L2)...",
        count(c, "attributes") & ", 1 per tile, 8 bits each, " & sizeText(c), vmxNote])
  of "tile-tags":
    one("chartileset_tag_data", @["CharTileSet Tags...",
        count(c, "tags") & ", 1 per tile, 8 bits each, " & sizeText(c)])
  of "tile-names":
    if not p.tileSystem: fail("the project has no tiles")
    result.add Block(part: part, label: "chartileset_names", names: p.tiles.names,
                     comments: @["CharTileSet Names...",
                                 count(c, "names") & " (one per tile, each is zero-terminated)."])
  of "map":
    let (w, h) = p.mapSize(o)
    result = p.cellBlocks(part, "map_data", @["Map Data...",
        $w & "x" & $h & " (" & $(w * h) & ") cells, " & o.cellText & ", " &
        sizeText(p.cellSize(part, o))], o)
  of "submaps": fail("submaps are not written yet (#44)")
  of "colour-map": fail("the colour map is not written yet (#45)")
  of "tile-events": fail("tile events are not written yet (#46)")
  else: fail("a CharPad project has no part " & part)

func defaultParts(p: ctm.Project): seq[string] =
  ## What CharPad's "Export All (one file)" writes.
  result = @["chars", "char-attribs"]
  if p.colouring == cmPerChar and p.isBitmap: result.add "char-attribs-l2"
  if p.tileSystem:
    result.add "tiles"
    if p.colouring == cmPerTile:
      result.add "tile-attribs"
      if p.isBitmap: result.add "tile-attribs-l2"
    result.add "tile-tags"
  result.add "map"

# SpritePad

proc animBlock(anims: seq[Animation], part, label, sub: string, comment: string,
               o: BinOptions): Block =
  ## The four lists of `binPart`, each with a label of its own.
  var o = o
  o.cells = if o.cells == cf8: cf8 else: cfWord
  let frameBytes = if o.cells == cf8: 1 else: 2
  let n = anims.len
  var p = SpriteProject(spriteAnims: anims)
  let data = p.binPart("sprite-anims", o)
  let f = n * frameBytes
  result = Block(part: part, label: label, comments: @[comment,
      count(n, "animations") & ", " & $(2 * frameBytes + 2) & " bytes per animation, " &
      sizeText(data.len)])
  result.chunks.add Chunk(label: sub & "_from", data: data[0 ..< f])
  result.chunks.add Chunk(label: sub & "_to", data: data[f ..< 2 * f])
  result.chunks.add Chunk(label: sub & "_timereload", data: data[2 * f ..< 2 * f + n])
  result.chunks.add Chunk(label: sub & "_attrib", data: data[2 * f + n .. ^1])

proc blocks(p: SpriteProject, part: string, o: BinOptions): seq[Block] =
  let n = p.sprites.len
  let c = p.tiles.len
  template one(name: string, notes: seq[string]) =
    result.add Block(part: part, label: name, comments: notes,
                     chunks: @[Chunk(data: p.binPart(part, o))])
  case part
  of "sprites":
    let data = p.binPart(part, o)
    var b = Block(part: part, label: "spriteset_data", comments: @["SpriteSet Data...",
                  count(n, "images") & ", 64 bytes per image, " & sizeText(n * 64)])
    for i in 0 ..< n:
      b.chunks.add Chunk(label: "sprite_image_" & $i, data: data[i * 64 ..< i * 64 + 64])
    result.add b
  of "sprite-attribs":
    one("spriteset_attrib_data", @["SpriteSet Attribute Data...",
        count(n, "attributes") & ", 1 per image, 8 bits each, " & sizeText(n),
        "nb. Upper nybbles = MYXV, lower nybbles = colour (0-15)."])
  of "tiles":
    if not p.tileSystem: fail("the project has no tiles")
    let a = p.tileWidth * p.tileHeight
    result = p.cellBlocks(part, "spritetileset_data", @["SpriteTileSet Data...",
        count(c, "tiles") & ", " & $p.tileWidth & "x" & $p.tileHeight & " (" & $a &
        ") cells per tile, " & o.cellText & ", " & sizeText(p.cellSize(part, o))], o)
  of "tile-attribs":
    one("spritetileset_attrib_data", @["SpriteTileSet Attribute Data...",
        count(c, "attributes") & ", 1 per tile, 8 bits each, " & sizeText(c),
        "nb. Lower nybbles = colour (unused), upper nybbles = xxxV (V = has overlay)."])
  of "tile-tags":
    one("spritetileset_tag_data", @["SpriteTileSet Tag Data...",
        count(c, "tags") & ", 1 per tile, 8 bits each, " & sizeText(c)])
  of "tile-names":
    if not p.tileSystem: fail("the project has no tiles")
    result.add Block(part: part, label: "spritetileset_names", names: p.tiles.names,
                     comments: @["SpriteTileSet Names...",
                                 count(c, "names") & " (one per tile, each is zero-terminated)."])
  of "sprite-anims":
    result.add animBlock(p.spriteAnims, part, "spriteanimset_data", "sprite_anims",
                         "Sprite Animation Set Data...", o)
  of "tile-anims":
    if not p.tileSystem: fail("the project has no tiles")
    result.add animBlock(p.tileAnims, part, "spritetileanimset_data", "spritetile_anims",
                         "SpriteTile Animation Set Data...", o)
  else: fail("a SpritePad project has no part " & part)

func defaultParts(p: SpriteProject): seq[string] =
  ## What SpritePad's "Export All (one file)" writes.
  result = @["sprites", "sprite-attribs"]
  if p.tileSystem: result.add ["tiles", "tile-attribs", "tile-tags"]
  if p.spriteAnims.len > 0: result.add "sprite-anims"
  if p.tileSystem and p.tileAnims.len > 0: result.add "tile-anims"

# Writing

type Writer = object
  o: AsmOptions
  text: string

proc line(w: var Writer, s = "") = w.text.add s & "\n"

proc comment(w: var Writer, s: string) =
  w.line (if w.o.dialect == dKickAss: "// " else: "; ") & s

proc constant(w: var Writer, name, value: string, note = "") =
  var s = (if w.o.dialect == dKickAss: ".const " else: "") & w.o.prefix & name & " = " & value
  if note != "": s.add (if w.o.dialect == dKickAss: " // " else: " ; ") & note
  w.line s

proc label(w: var Writer, name: string) =
  w.line w.o.prefix & name & (if w.o.dialect in {dKickAss, dCa65}: ":" else: "")

func byteDirective(d: Dialect): string = (if d == dAcme: "!byte " else: ".byte ")

proc bytes(w: var Writer, data: openArray[byte]) =
  for i in countup(0, data.high, 16):
    var vals: seq[string]
    for b in data[i .. min(i + 15, data.high)]: vals.add "$" & toHex(b).toLowerAscii
    w.line byteDirective(w.o.dialect) & vals.join(",")

func printable(c: char): bool = c in {' ' .. '~'} - {'"', '\\'}

proc name(w: var Writer, s: string) =
  ## A zero-terminated name. 64tass and ACME keep the bytes of a string as they
  ## are; KickAssembler and ca65 may translate them, so they get bytes.
  if w.o.dialect in {d64tass, dAcme}:
    var parts: seq[string]
    var i = 0
    while i < s.len:
      if s[i].printable:
        var j = i
        while j < s.len and s[j].printable: inc j
        parts.add "\"" & s[i ..< j] & "\""
        i = j
      else:
        parts.add "$" & toHex(ord(s[i]), 2).toLowerAscii
        inc i
    parts.add "0"
    w.line (if w.o.dialect == dAcme: "!text " else: ".text ") & parts.join(", ")
  else:
    var shown = s
    for c in shown.mitems:
      if not c.printable and c != '"': c = '?'
    w.comment "\"" & shown & "\""
    var data = cast[seq[byte]](s)
    data.add 0
    w.bytes data

func orgFor(o: AsmOptions, part: string): Option[int] =
  ## `map` also names `map-lo`, the start of a split map.
  for (p, a) in o.org:
    if p == part or (p & "-lo") == part: return some(a)

proc header(w: var Writer, blocks: seq[Block]) =
  ## Sizes, and addresses when `--org` gives them.
  var hasOrg = false
  for b in blocks:
    if w.o.orgFor(b.part).isSome: hasOrg = true
  w.line
  w.line
  w.comment (if hasOrg: "Data block addresses and sizes..." else: "Data block sizes...")
  if not hasOrg: w.line
  for b in blocks:
    let a = w.o.orgFor(b.part)
    if a.isSome: w.line
    if a.isSome: w.constant("addr_" & b.label, "$" & hex(a.get))
    w.constant("size_" & b.label, "$" & hex(b.size), "(" & count(b.size, "bytes") & ")")

proc body(w: var Writer, blocks: seq[Block]) =
  for b in blocks:
    w.line
    w.line
    if b.comments.len > 0:
      for c in b.comments: w.comment c
      w.line
    let a = w.o.orgFor(b.part)
    if a.isSome:
      w.line (if w.o.dialect == dCa65: ".org " else: "* = ") & w.o.prefix & "addr_" & b.label
    w.label b.label
    for i, c in b.chunks:
      if c.label != "":
        if i > 0: w.line
        w.label c.label
      w.bytes c.data
    for n in b.names: w.name n

proc start(w: var Writer, program: string) =
  w.comment "Generated by batchpad" & (if w.o.source != "": " from " & w.o.source else: "") &
            ", after the " & program & " Pro template."
  w.comment "Assemble with " & (case w.o.dialect
                                of d64tass: "64tass"
                                of dAcme: "ACME"
                                of dKickAss: "KickAssembler"
                                of dCa65: "ca65") & "."
  if w.o.segment != "":
    w.line
    w.line (if w.o.dialect == dCa65: ".segment \"" & w.o.segment & "\""
            else: ".segment " & w.o.segment)

proc finish(w: Writer): string =
  result = w.text
  if w.o.crlf: result = result.replace("\n", "\r\n")

proc collect[P](p: P, o: AsmOptions): seq[Block] =
  let parts = if o.parts.len > 0: o.parts else: p.defaultParts
  for i, part in parts:
    if part in parts[0 ..< i]: fail(part & " is named twice")
    result.add p.blocks(part, o.bin)
  for (part, _) in o.org:
    var found = false
    for b in result:
      if b.part == part or b.part == part & "-lo": found = true
    if not found: fail("--org " & part & ": the output has no such part")

proc check(o: AsmOptions) =
  if o.segment != "" and o.dialect notin {dKickAss, dCa65}:
    fail("--segment is for ca65 and kickass, not " & $o.dialect)

const modeText: array[DisplayMode, string] = ["Text (High Resolution)",
  "Text (Multi-colour)", "Text (Extended Colour)", "Bitmap (High Resolution)",
  "Bitmap (Multi-colour)"]
const colouringText: array[ColouringMethod, string] = ["Per Project", "Per Tile",
  "Per Character"]

proc toAsm*(p: ctm.Project, o: AsmOptions): string =
  ## Assembler source of a CharPad project.
  o.check
  let blocks = p.collect(o)
  var w = Writer(o: o)
  w.start("CharPad")
  w.line
  w.line
  w.comment "Display mode : " & modeText[p.displayMode] & "."
  w.comment "Matrix colouring method : " & colouringText[p.colouring] & "."
  w.line
  w.line
  w.comment "Colour values..."
  w.line
  w.comment "cmxlo = colour matrix low nybble."
  w.comment "vmxlo = video matrix low nybble."
  w.comment "vmxhi = video matrix high nybble."
  w.comment "nb. any matrix colours listed here are usually only needed in a 'per project' matrix colouring system."
  w.line
  let bg = p.chipColours
  case p.displayMode
  of dmHiresText:
    w.constant("colr_vic_bg0", $bg[0])
    w.constant("colr_cmxlo_proj", $p.colours[0])
  of dmMulticolourText:
    for i in 0..2: w.constant("colr_vic_bg" & $i, $bg[i])
    w.constant("colr_cmxlo_proj", $p.colours[0])
  of dmEcmText:
    for i in 0..3: w.constant("colr_vic_bg" & $i, $bg[i])
    w.constant("colr_cmxlo_proj", $p.colours[0])
  of dmHiresBitmap:
    w.constant("colr_vmxlo_proj", $p.colours[1])
    w.constant("colr_vmxhi_proj", $p.colours[2])
  of dmMulticolourBitmap:
    w.constant("colr_vic_bg0", $bg[0])
    w.constant("colr_cmxlo_proj", $p.colours[0])
    w.constant("colr_vmxlo_proj", $p.colours[1])
    w.constant("colr_vmxhi_proj", $p.colours[2])
  w.line
  w.line
  w.comment "Quantities and dimensions..."
  w.line
  w.constant("char_count", $p.chars.len)
  if p.tileSystem:
    w.constant("tile_count", $p.tiles.len)
    w.constant("tile_wid", $p.tileWidth)
    w.constant("tile_hei", $p.tileHeight)
  let (mw, mh) = p.mapSize(o.bin)
  w.constant("map_wid", $mw)
  w.constant("map_hei", $mh)
  if p.tileSystem:
    w.constant("map_wid_chrs", $(mw * p.tileWidth))
    w.constant("map_hei_chrs", $(mh * p.tileHeight))
    w.constant("map_wid_pxls", $(mw * p.tileWidth * 8))
    w.constant("map_hei_pxls", $(mh * p.tileHeight * 8))
  w.header(blocks)
  w.body(blocks)
  w.finish

proc toAsm*(p: SpriteProject, o: AsmOptions): string =
  ## Assembler source of a SpritePad project.
  o.check
  let blocks = p.collect(o)
  var w = Writer(o: o)
  w.start("SpritePad")
  w.line
  w.line
  w.comment "Colour values..."
  w.line
  w.constant("colr_vic_bg0", $p.colours[0])
  w.constant("colr_vic_sprite_mc1", $p.colours[1])
  w.constant("colr_vic_sprite_mc2", $p.colours[2])
  w.line
  w.line
  w.comment "Quantities and dimensions..."
  w.line
  w.constant("sprite_count", $p.sprites.len)
  if p.spriteAnims.len > 0: w.constant("spriteanim_count", $p.spriteAnims.len)
  if p.tileSystem:
    w.constant("spritetile_count", $p.tiles.len)
    w.constant("spritetile_wid", $p.tileWidth)
    w.constant("spritetile_hei", $p.tileHeight)
    if p.tileAnims.len > 0: w.constant("spritetileanim_count", $p.tileAnims.len)
  w.header(blocks)
  w.body(blocks)
  w.finish
