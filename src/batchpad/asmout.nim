## Assembler source of a project, after the CharPad and SpritePad Pro templates
## (docs/import-export.md, "Assembler text"), for several assemblers. Options
## are described in docs/cli.md under asm.
##
## Unlike the templates, every label the file uses is defined, and there are
## no `* =` lines unless asked for, so the file assembles as it is.

import std/[options, sets, strutils]
import binio, ctm, rawbin, spd, tiled, tiledbin

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
    altEventLabels*: bool          ## tile event labels `<name>`, not `chtl_<name>_event`
    eventStubs* = true             ## an `rts` per tile event label

  Chunk* = object
    label*: string                 ## a label inside the block, or ""
    data*: seq[byte]

  Block* = object
    part*: string                  ## what `--org` names it by
    label*: string
    comments*: seq[string]
    chunks*: seq[Chunk]
    separate*: bool                ## the chunk labels are lists of their own (animations)
    names*: seq[string]            ## zero-terminated strings instead of chunks
    words*: seq[string]            ## `.word` entries, labels
    stubs*: seq[(string, string)]  ## comment and label of an `rts` each

  HeadKind* = enum
    hkBlank, hkComment, hkConst

  HeadLine* = object
    ## A line of what comes before the data: colours, quantities, dimensions.
    kind*: HeadKind
    name*: string                  ## the comment, or the constant's name
    value*: string                 ## `$xx` for hex, as in assembler source

const
  ctmAsmParts* = ["chars", "char-attribs", "char-attribs-l2", "char-materials",
                  "tiles", "tile-attribs", "tile-attribs-l2", "tile-tags",
                  "tile-names", "tile-events", "map", "submaps", "colour-map"]
  spdAsmParts* = ["sprites", "sprite-attribs", "tiles", "tile-attribs",
                  "tile-tags", "tile-names", "sprite-anims", "tile-anims"]

  tiledAsmParts* = ["map", "map-flags", "tile-tags", "tile-names"]
    ## `map` and `map-flags` can also name a layer: `map:ground`

proc fail(msg: string) {.noreturn.} = raise newException(AsmError, msg)

func afterText*(program: string): string =
  ## What the first line says about the template the output follows.
  if program == "Tiled": ", a Tiled map" else: ", after the " & program & " Pro template"

func size*(b: Block): int =
  for c in b.chunks: result += c.data.len
  for n in b.names: result += n.len + 1
  result += 2 * b.words.len + b.stubs.len

func hex*(n: int): string =
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

proc cellBlocks(part, label: string, comments: seq[string], o: BinOptions,
                data: proc (part: string): seq[byte]): seq[Block] =
  ## One block, or two for split cells: `label_lo` and `label_hi` (or
  ## `label_hi_packed` for 12 bit). `data` gives the bytes of a part.
  if not o.split:
    return @[Block(part: part, label: label, comments: comments,
                   chunks: @[Chunk(data: data(part))])]
  let hi = if o.cells == cf12: "_hi_packed" else: "_hi"
  result.add Block(part: part & "-lo", label: label & "_lo", comments: comments,
                   chunks: @[Chunk(data: data(part & "-lo"))])
  result.add Block(part: part & "-hi", label: label & hi,
                   chunks: @[Chunk(data: data(part & "-hi"))])

proc cellBlocks[P](p: P, part, label: string, comments: seq[string], o: BinOptions): seq[Block] =
  cellBlocks(part, label, comments, o, proc (q: string): seq[byte] = p.binPart(q, o))

proc cellSize[P](p: P, part: string, o: BinOptions): int =
  if o.split: p.binPart(part & "-lo", o).len + p.binPart(part & "-hi", o).len
  else: p.binPart(part, o).len

# CharPad

func isBitmap(p: ctm.Project): bool = p.displayMode in {dmHiresBitmap, dmMulticolourBitmap}

func mapSize(p: ctm.Project, o: BinOptions): (int, int) =
  if o.area.isSome: (o.area.get.width, o.area.get.height) else: (p.mapWidth, p.mapHeight)

proc names(tiles: seq[ctm.Tile] | seq[SpriteTile]): seq[string] =
  for t in tiles: result.add t.name

const reserved = toHashSet([
  # Registers and mnemonics, illegal ones included, can't be labels in some
  # of the dialects.
  "a", "x", "y",
  "adc", "and", "asl", "bcc", "bcs", "beq", "bit", "bmi", "bne", "bpl", "brk",
  "bvc", "bvs", "clc", "cld", "cli", "clv", "cmp", "cpx", "cpy", "dec", "dex",
  "dey", "eor", "inc", "inx", "iny", "jmp", "jsr", "lda", "ldx", "ldy", "lsr",
  "nop", "ora", "pha", "php", "pla", "plp", "rol", "ror", "rti", "rts", "sbc",
  "sec", "sed", "sei", "sta", "stx", "sty", "tax", "tay", "tsx", "txa", "txs",
  "tya", "ahx", "alr", "anc", "ane", "arr", "asr", "axs", "dcp", "dcm", "hlt",
  "isb", "isc", "ins", "jam", "kil", "lae", "las", "lax", "lxa", "rla", "rra",
  "sax", "sbx", "sha", "shs", "shx", "shy", "slo", "sre", "tas", "xaa"])

func isLabel*(s: string): bool =
  s.len > 0 and s[0] in Letters and s.allCharsInSet(IdentChars) and s.toLowerAscii notin reserved

proc eventBlocks(p: ctm.Project, ao: AsmOptions): seq[Block] =
  ## CharPad's tile event jump table: a pointer per tile to a label made from
  ## its name, and an `rts` stub per label unless `eventStubs` is off.
  if not p.tileSystem: fail("the project has no tiles")
  let null = if ao.altEventLabels: "null_event" else: "chtl_null_event"
  var table = Block(part: "tile-events", label: "chartileset_eventjumptable", comments: @[
      "CharTileSet Event Jump Table...",
      count(p.tiles.len, "pointers") & " (one per tile), 16 bits per pointer, " &
      sizeText(2 * p.tiles.len)])
  var stubs = Block(label: "chartileset_events", stubs: @[
      ("chartile \"null\" event (for tiles with blank names).", null)])
  var seen = toHashSet([null])
  for i, t in p.tiles:
    var label = null
    if t.name != "":
      label = if ao.altEventLabels: t.name else: "chtl_" & t.name & "_event"
      if not isLabel(ao.prefix & label):
        fail("tile " & $i & " is named \"" & t.name & "\", which can't be the label " &
             ao.prefix & label & ": event labels need a letter, then letters, digits and _, " &
             "and no register or mnemonic")
    table.words.add label
    if label notin seen:
      seen.incl label
      stubs.stubs.add ("event: chartile \"" & t.name & "\".", label)
  result.add table
  if ao.eventStubs:
    stubs.comments = @["CharTileSet Events (" & $stubs.stubs.len & ")...",
        "nb. the event \"type\" is unspecific but could represent ie. a player/tile contact event."]
    result.add stubs

const vmxNote = "nb. Upper nybbles = colour (video matrix high), lower nybbles = colour (video matrix low)."

proc blocks(p: ctm.Project, part: string, ao: AsmOptions): seq[Block] =
  let o = ao.bin
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
  of "submaps":
    # Labels as CharPad's text export of sub-maps; `--org submaps` puts its
    # `* =` line before the first one only.
    if o.area.isSome: fail("--area is for map, not submaps")
    let s = p.subMaps
    let a = s.width * s.height
    var size = a * (if o.cells in {cf16, cfWord}: 2 else: 1)
    if o.cells == cf12: size += (a + 1) div 2
    for y in 0 ..< s.down:
      for x in 0 ..< s.across:
        let first = y == 0 and x == 0
        var bs = cellBlocks(part, "submap_y" & $y & "_x" & $x & "_data",
            @["SubMap (" & $y & "," & $x & ")...", $s.width & "x" & $s.height & " (" & $a &
              ") cells, " & o.cellText & ", " & sizeText(size)], o,
            proc (q: string): seq[byte] = p.binSubMap(y, x, q, o))
        for b in bs.mitems:
          if not first: b.part = ""
        result.add bs
  of "colour-map":
    let (mw, mh) = p.mapSize(o)
    let (w, h) = if p.tileSystem: (mw * p.tileWidth, mh * p.tileHeight) else: (mw, mh)
    one("colourmap_data", @["ColourMap Data...",
        $w & "x" & $h & " (" & $(w * h) & ") cells, 8 bits per cell, " & sizeText(w * h)])
  of "tile-events": result = p.eventBlocks(ao)
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
  result = Block(part: part, label: label, separate: true, comments: @[comment,
      count(n, "animations") & ", " & $(2 * frameBytes + 2) & " bytes per animation, " &
      sizeText(data.len)])
  result.chunks.add Chunk(label: sub & "_from", data: data[0 ..< f])
  result.chunks.add Chunk(label: sub & "_to", data: data[f ..< 2 * f])
  result.chunks.add Chunk(label: sub & "_timereload", data: data[2 * f ..< 2 * f + n])
  result.chunks.add Chunk(label: sub & "_attrib", data: data[2 * f + n .. ^1])

proc blocks(p: SpriteProject, part: string, ao: AsmOptions): seq[Block] =
  let o = ao.bin
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

# Tiled

func labelPart(s: string): string =
  ## A layer name as part of a label.
  for c in s: result.add (if c in IdentChars: c else: '_')

proc tiledLayer(t: TiledMap, name: string): Layer =
  try: t.tileLayer(name)
  except TiledError as e: fail(e.msg)

proc tileNames(t: TiledMap): seq[string] =
  let ts = try: t.tilesets[t.tilesetIndex]
           except TiledError as e: fail(e.msg)
  var count = ts.tileCount
  for k in ts.tiles: count = max(count, k.id + 1)
  result = newSeq[string](count)
  for k in ts.tiles:
    result[k.id] = if k.class != "": k.class else: k.properties.property("name")

proc blocks(t: TiledMap, part: string, ao: AsmOptions): seq[Block] =
  let o = ao.bin
  let (base, name) = splitMapPart(part)
  case base
  of "map", "map-lo", "map-hi":
    let layer = t.tiledLayer(name)
    let (w, h) = if o.area.isSome: (o.area.get.width, o.area.get.height)
                 else: (layer.width, layer.height)
    let size = if o.split: t.binPart(part.replace(base, "map") & "-lo", o).len +
                           t.binPart(part.replace(base, "map") & "-hi", o).len
               else: t.binPart(part, o).len
    let whole = if name == "": "map" else: "map:" & name
    result = cellBlocks(whole, (if name == "": "map_data" else: "map_" & name.labelPart & "_data"),
        @["Map Data" & (if name == "": "" else: " (layer " & name & ")") & "...",
          $w & "x" & $h & " (" & $(w * h) & ") cells, " & o.cellText & ", " & sizeText(size)], o,
        proc (q: string): seq[byte] = t.binPart(q, o))
  of "map-flags":
    let layer = t.tiledLayer(name)
    let data = t.binPart(part, o)
    result.add Block(part: part, label: if name == "": "map_flags_data" else: "map_" & name.labelPart & "_flags_data",
        comments: @["Map Flags Data" & (if name == "": "" else: " (layer " & layer.name & ")") & "...",
                    count(data.len, "cells") & ", 8 bits each, " & sizeText(data.len),
                    "nb. Bit 7 = flipped horizontally, bit 6 = flipped vertically, bit 5 = flipped diagonally."],
        chunks: @[Chunk(data: data)])
  of "tile-tags":
    let data = t.binPart(part, o)
    result.add Block(part: part, label: "tiles_tag_data", comments: @["Tile Tags...",
        count(data.len, "tags") & ", 1 per tile, 8 bits each, " & sizeText(data.len)],
        chunks: @[Chunk(data: data)])
  of "tile-names":
    let names = t.tileNames
    result.add Block(part: part, label: "tiles_names", names: names,
                     comments: @["Tile Names...",
                                 count(names.len, "names") & " (one per tile, each is zero-terminated)."])
  else: fail("a Tiled map has no part " & part)

func defaultParts(t: TiledMap): seq[string] = @["map"]

# Writing

type Writer = object
  o: AsmOptions
  text: string
  defined: HashSet[string]       ## labels and constants so far, lower case

proc define(w: var Writer, name: string) =
  ## 64tass ignores case, so names that only differ in case clash too.
  let n = (w.o.prefix & name).toLowerAscii
  if n in w.defined: fail(w.o.prefix & name & " would be defined twice")
  w.defined.incl n

proc line(w: var Writer, s = "") = w.text.add s & "\n"

proc comment(w: var Writer, s: string) =
  w.line (if w.o.dialect == dKickAss: "// " else: "; ") & s

proc constant(w: var Writer, name, value: string, note = "") =
  w.define name
  var s = (if w.o.dialect == dKickAss: ".const " else: "") & w.o.prefix & name & " = " & value
  if note != "": s.add (if w.o.dialect == dKickAss: " // " else: " ; ") & note
  w.line s

proc label(w: var Writer, name: string) =
  w.define name
  w.line w.o.prefix & name & (if w.o.dialect in {dKickAss, dCa65}: ":" else: "")

func byteDirective(d: Dialect): string = (if d == dAcme: "!byte " else: ".byte ")

proc bytes(w: var Writer, data: openArray[byte]) =
  for i in countup(0, data.high, 16):
    var vals: seq[string]
    for b in data[i .. min(i + 15, data.high)]: vals.add "$" & toHex(b).toLowerAscii
    w.line byteDirective(w.o.dialect) & vals.join(",")

proc words(w: var Writer, labels: openArray[string]) =
  ## Four to a line, as CharPad writes them.
  for i in countup(0, labels.high, 4):
    var vals: seq[string]
    for l in labels[i .. min(i + 3, labels.high)]: vals.add w.o.prefix & l
    w.line (if w.o.dialect == dAcme: "!word " else: ".word ") & vals.join(", ")

proc name(w: var Writer, s: string) =
  ## A zero-terminated name, as the bytes stored, with the name in a comment
  ## above. A string would be translated by some assemblers or their options
  ## (64tass -a, KickAssembler, ca65 -t c64).
  var shown = s
  for c in shown.mitems:
    if c notin {' ' .. '~'}: c = '?'
  w.comment "\"" & shown & "\""
  var data = cast[seq[byte]](s)
  data.add 0
  w.bytes data

func orgFor*(o: AsmOptions, part: string): Option[int] =
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
    w.words b.words
    for (comment, label) in b.stubs:
      w.line
      w.comment comment
      w.label label
      w.line "rts"

proc start(w: var Writer, program: string) =
  w.comment "Generated by batchpad" & (if w.o.source != "": " from " & w.o.source else: "") &
            afterText(program) & "."
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

proc collect*[P](p: P, o: AsmOptions): seq[Block] =
  let parts = if o.parts.len > 0: o.parts else: p.defaultParts
  for i, part in parts:
    if part in parts[0 ..< i]: fail(part & " is named twice")
    result.add p.blocks(part, o)
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

type Head = seq[HeadLine]

proc blank(h: var Head) = h.add HeadLine(kind: hkBlank)
proc comment(h: var Head, s: string) = h.add HeadLine(kind: hkComment, name: s)
proc constant(h: var Head, name, value: string) =
  h.add HeadLine(kind: hkConst, name: name, value: value)

proc head*(p: ctm.Project, o: AsmOptions): seq[HeadLine] =
  ## What the CharPad template writes before the data blocks.
  var h: Head
  h.blank
  h.blank
  h.comment "Display mode : " & modeText[p.displayMode] & "."
  h.comment "Matrix colouring method : " & colouringText[p.colouring] & "."
  h.blank
  h.blank
  h.comment "Colour values..."
  h.blank
  h.comment "cmxlo = colour matrix low nybble."
  h.comment "vmxlo = video matrix low nybble."
  h.comment "vmxhi = video matrix high nybble."
  h.comment "nb. any matrix colours listed here are usually only needed in a 'per project' matrix colouring system."
  h.blank
  let bg = p.chipColours
  case p.displayMode
  of dmHiresText:
    h.constant("colr_vic_bg0", $bg[0])
    h.constant("colr_cmxlo_proj", $p.colours[0])
  of dmMulticolourText:
    for i in 0..2: h.constant("colr_vic_bg" & $i, $bg[i])
    h.constant("colr_cmxlo_proj", $p.colours[0])
  of dmEcmText:
    for i in 0..3: h.constant("colr_vic_bg" & $i, $bg[i])
    h.constant("colr_cmxlo_proj", $p.colours[0])
  of dmHiresBitmap:
    h.constant("colr_vmxlo_proj", $p.colours[1])
    h.constant("colr_vmxhi_proj", $p.colours[2])
  of dmMulticolourBitmap:
    h.constant("colr_vic_bg0", $bg[0])
    h.constant("colr_cmxlo_proj", $p.colours[0])
    h.constant("colr_vmxlo_proj", $p.colours[1])
    h.constant("colr_vmxhi_proj", $p.colours[2])
  h.blank
  h.blank
  h.comment "Quantities and dimensions..."
  h.blank
  h.constant("char_count", $p.chars.len)
  if p.tileSystem:
    h.constant("tile_count", $p.tiles.len)
    h.constant("tile_wid", $p.tileWidth)
    h.constant("tile_hei", $p.tileHeight)
  let (mw, mh) = p.mapSize(o.bin)
  h.constant("map_wid", $mw)
  h.constant("map_hei", $mh)
  if p.tileSystem:
    h.constant("map_wid_chrs", $(mw * p.tileWidth))
    h.constant("map_hei_chrs", $(mh * p.tileHeight))
    h.constant("map_wid_pxls", $(mw * p.tileWidth * 8))
    h.constant("map_hei_pxls", $(mh * p.tileHeight * 8))
  if "submaps" in o.parts:
    let s = p.subMaps
    h.constant("submap_wid", $s.width)
    h.constant("submap_hei", $s.height)
    h.constant("submap_count_x", $s.across)
    h.constant("submap_count_y", $s.down)
  h

proc head*(p: SpriteProject, o: AsmOptions): seq[HeadLine] =
  ## What the SpritePad template writes before the data blocks.
  var h: Head
  h.blank
  h.blank
  h.comment "Colour values..."
  h.blank
  h.constant("colr_vic_bg0", $p.colours[0])
  h.constant("colr_vic_sprite_mc1", $p.colours[1])
  h.constant("colr_vic_sprite_mc2", $p.colours[2])
  h.blank
  h.blank
  h.comment "Quantities and dimensions..."
  h.blank
  h.constant("sprite_count", $p.sprites.len)
  if p.spriteAnims.len > 0: h.constant("spriteanim_count", $p.spriteAnims.len)
  if p.tileSystem:
    h.constant("spritetile_count", $p.tiles.len)
    h.constant("spritetile_wid", $p.tileWidth)
    h.constant("spritetile_hei", $p.tileHeight)
    if p.tileAnims.len > 0: h.constant("spritetileanim_count", $p.tileAnims.len)
  h

proc head*(t: TiledMap, o: AsmOptions): seq[HeadLine] =
  ## Sizes of the map, in the names of the CharPad template.
  var h: Head
  h.blank
  h.blank
  h.comment "Quantities and dimensions..."
  h.blank
  let layer = t.tiledLayer("")
  let (w, h2) = if o.bin.area.isSome: (o.bin.area.get.width, o.bin.area.get.height)
                else: (layer.width, layer.height)
  h.constant("map_wid", $w)
  h.constant("map_hei", $h2)
  h.constant("tile_wid_pxls", $t.tileWidth)
  h.constant("tile_hei_pxls", $t.tileHeight)
  h

proc render(w: var Writer, h: seq[HeadLine]) =
  for l in h:
    case l.kind
    of hkBlank: w.line
    of hkComment: w.comment l.name
    of hkConst: w.constant(l.name, l.value)

proc toAsm*(p: ctm.Project, o: AsmOptions): string =
  ## Assembler source of a CharPad project.
  o.check
  let blocks = p.collect(o)
  var w = Writer(o: o)
  w.start("CharPad")
  w.render p.head(o)
  w.header(blocks)
  w.body(blocks)
  w.finish

proc toAsm*(p: SpriteProject, o: AsmOptions): string =
  ## Assembler source of a SpritePad project.
  o.check
  let blocks = p.collect(o)
  var w = Writer(o: o)
  w.start("SpritePad")
  w.render p.head(o)
  w.header(blocks)
  w.body(blocks)
  w.finish

proc toAsm*(t: TiledMap, o: AsmOptions): string =
  ## Assembler source of a Tiled map.
  o.check
  let blocks = t.collect(o)
  var w = Writer(o: o)
  w.start("Tiled")
  w.render t.head(o)
  w.header(blocks)
  w.body(blocks)
  w.finish
