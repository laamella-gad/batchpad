## C source of a project for oscar64: the blocks and constants of the
## assembler output (asmout.nim) as arrays and `#define`s. Options are
## described in docs/cli.md under c.
##
## Data is `__export const unsigned char` arrays, so oscar64 keeps them
## whether or not the program uses them. `--org` places a part with
## `#pragma section`, `region` and `data`. Tile names are byte arrays and a
## pointer table, not strings: oscar64 translates strings with `-psci`, even
## the escapes in them, and the bytes must stay as stored.

import std/[options, os, sets, strutils]
import asmout, binio, ctm, spd, tiled

const keywords = toHashSet([
  "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
  "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
  "register", "return", "short", "signed", "sizeof", "static", "struct", "switch",
  "typedef", "union", "unsigned", "void", "volatile", "while", "bool", "true",
  "false", "class", "new", "delete", "this", "template", "namespace", "public",
  "private", "main", "null"])

type
  CWriter = object
    o: AsmOptions
    defined: HashSet[string]
    defines: seq[string]         ## `#define` lines, comments and blank lines: the constants
    decls: seq[string]           ## `extern` declarations and function prototypes
    prototypes: seq[string]      ## function prototypes, which both files need
    data: seq[string]            ## the arrays and functions

proc fail(msg: string) {.noreturn.} = raise newException(AsmError, msg)

proc isIdent(s: string): bool =
  s.len > 0 and s[0] in IdentStartChars and s.allCharsInSet(IdentChars)

proc define(w: var CWriter, name: string) =
  let n = w.o.prefix & name
  if n in keywords: fail(n & " is a C keyword; use --prefix")
  if n in w.defined: fail(n & " would be defined twice")
  w.defined.incl n

func cValue(v: string): string =
  ## `$ff` is `0xff`.
  if v.startsWith("$"): "0x" & v[1 .. ^1] else: v

proc constant(w: var CWriter, name, value: string, note = "") =
  w.define name
  w.defines.add "#define " & w.o.prefix & name & " " & cValue(value) &
                (if note != "": " // " & note else: "")

proc byteLines(data: openArray[byte]): seq[string] =
  for i in countup(0, data.high, 16):
    var vals: seq[string]
    for b in data[i .. min(i + 15, data.high)]: vals.add "0x" & toHex(b).toLowerAscii
    result.add "    " & vals.join(",") & (if i + 16 <= data.high: "," else: "")

proc array(w: var CWriter, name: string, data: openArray[byte]) =
  w.define name
  let n = w.o.prefix & name
  w.decls.add "extern const unsigned char " & n & "[];"
  w.data.add "__export const unsigned char " & n & "[] = {"
  w.data.add byteLines(data)
  w.data.add "};"

proc prototype(w: var CWriter, label: string) =
  let n = w.o.prefix & label
  if not n.isIdent: fail(n & " is not a C name; use --prefix with letters, digits and _")
  if n in keywords: fail("the event label " & n & " is a C keyword; use --prefix or --event-labels normal")
  if n notin w.prototypes: w.prototypes.add n

proc comments(w: var CWriter, b: Block) =
  for c in b.comments: w.data.add "// " & c

proc emit(w: var CWriter, b: Block) =
  ## One block; what asm writes as a label with bytes under it.
  w.data.add ""
  if b.words.len > 0:
    # The tile event jump table: function pointers.
    w.comments b
    for l in b.words: w.prototype l
    w.define b.label
    let n = w.o.prefix & b.label
    w.decls.add "extern void (* const " & n & "[" & $b.words.len & "])(void);"
    w.data.add "__export void (* const " & n & "[" & $b.words.len & "])(void) = {"
    for i in countup(0, b.words.high, 4):
      var vals: seq[string]
      for l in b.words[i .. min(i + 3, b.words.high)]: vals.add w.o.prefix & l
      w.data.add "    " & vals.join(", ") & (if i + 4 <= b.words.high: "," else: "")
    w.data.add "};"
  elif b.stubs.len > 0:
    # The event functions, empty.
    for (comment, label) in b.stubs:
      w.prototype label
      w.data.add "// " & comment
      w.data.add "void " & w.o.prefix & label & "(void) {}"
  elif b.names.len > 0:
    # Zero-terminated bytes, and a table pointing into them.
    w.comments b
    var all: seq[byte]
    var starts: seq[int]
    for s in b.names:
      starts.add all.len
      all.add cast[seq[byte]](s)
      all.add 0
    w.array(b.label & "_data", all)
    w.define b.label
    let n = w.o.prefix & b.label
    w.decls.add "extern const unsigned char * const " & n & "[" & $b.names.len & "];"
    w.data.add "__export const unsigned char * const " & n & "[" & $b.names.len & "] = {"
    for i in countup(0, starts.high, 4):
      var vals: seq[string]
      for j in i .. min(i + 3, starts.high):
        vals.add "&" & w.o.prefix & b.label & "_data[" & $starts[j] & "]"
      w.data.add "    " & vals.join(", ") & (if i + 4 <= starts.high: "," else: "")
    w.data.add "};"
  elif b.separate:
    # Lists of their own: no array for the block itself.
    w.comments b
    for c in b.chunks:
      w.array(c.label, c.data)
  else:
    w.comments b
    var all: seq[byte]
    for c in b.chunks: all.add c.data
    w.array(b.label, all)

func cSize(b: Block): int =
  ## What the block takes in memory in C: names also have their pointer table,
  ## and event functions are code.
  if b.stubs.len > 0: 0 else: b.size + 2 * b.names.len

func continues(first, next: Block): bool =
  ## Whether `next` belongs with `first` at one address: the other half of a
  ## split part, or one more sub-map.
  next.part == "" or (first.part.endsWith("-lo") and next.part == first.part[0 ..< ^3] & "-hi")

proc place(w: var CWriter, blocks: seq[Block]) =
  ## `--org`: a block with an address goes into a section of its own, in a
  ## region of exactly its size, together with what belongs to it (`continues`).
  ## Unlike asm, what follows is not dragged along: the section ends there.
  var open = false
  var first: Block
  for i, b in blocks:
    let a = w.o.orgFor(b.part)
    if open and (a.isSome or not first.continues(b)):
      w.data.add ""
      w.data.add "#pragma data(data)"
      open = false
    if a.isSome:
      var size = b.cSize
      var j = i + 1
      while j < blocks.len and b.continues(blocks[j]) and w.o.orgFor(blocks[j].part).isNone:
        size += blocks[j].cSize
        inc j
      let (start, stop) = (a.get, a.get + size)
      if stop > 0x10000:
        fail("--org " & b.part & ": " & $size & " bytes from $" & hex(start) & " go past $ffff")
      let sec = w.o.prefix & "sec_" & b.label
      w.constant("addr_" & b.label, "$" & hex(start))
      w.data.add ""
      w.data.add "#pragma section(" & sec & ", 0)"
      w.data.add "#pragma region(" & w.o.prefix & "reg_" & b.label & ", 0x" & toHex(start, 4).toLowerAscii &
                 ", 0x" & toHex(stop, 4).toLowerAscii & ", , , {" & sec & "})"
      w.data.add "#pragma data(" & sec & ")"
      open = true
      first = b
    w.emit b
  if open:
    w.data.add ""
    w.data.add "#pragma data(data)"

proc toC[P](p: P, o: AsmOptions, header, sourceName: string, program: string): tuple[source, header: string] =
  if o.prefix != "" and not o.prefix.isIdent:
    fail("--prefix " & o.prefix & " is not the start of a C name")
  let blocks = p.collect(o)
  var w = CWriter(o: o)
  for l in p.head(o):
    case l.kind
    of hkBlank: w.defines.add ""
    of hkComment: w.defines.add "// " & l.name
    of hkConst: w.constant(l.name, l.value)
  w.defines.add ""
  w.defines.add ""
  w.defines.add "// Data block " & (if o.org.len > 0: "addresses and " else: "") & "sizes..."
  w.defines.add ""
  w.place blocks
  for b in blocks:
    if b.stubs.len == 0: w.constant("size_" & b.label, "$" & hex(b.size), "(" & b.size.count("bytes") & ")")
  let intro = "// Generated by batchpad" & (if o.source != "": " from " & o.source else: "") &
              afterText(program) & ".\n// Compile with oscar64.\n"
  var protos: seq[string]
  for n in w.prototypes: protos.add "void " & n & "(void);"
  let eol = if o.crlf: "\r\n" else: "\n"
  proc join(lines: seq[string]): string = lines.join(eol) & eol
  if header == "":
    result.source = intro.replace("\n", eol) & eol & (w.defines & @[""] & protos & w.data).join
  else:
    let stem = header.extractFilename
    var guard = "BATCHPAD_"
    for c in stem.toUpperAscii: guard.add (if c in IdentChars: c else: '_')
    result.header = intro.replace("\n", eol) & eol & ("#ifndef " & guard & eol & "#define " & guard & eol).replace("\n", eol) &
                    "#pragma compile(\"" & sourceName & "\")" & eol & eol &
                    (w.defines & @[""] & protos & w.decls & @["", "#endif"]).join
    result.source = intro.replace("\n", eol) & eol & "#include \"" & stem & "\"" & eol & (w.data).join

proc toC*(p: ctm.Project, o: AsmOptions, header = "", sourceName = ""): tuple[source, header: string] =
  ## C source of a CharPad project. With a `header` file name, also the
  ## header with the constants and declarations: the source includes it, and it
  ## has the `#pragma compile` of the source, named `sourceName`, so a program
  ## that includes the header gets the data.
  toC(p, o, header, sourceName, "CharPad")

proc toC*(p: SpriteProject, o: AsmOptions, header = "", sourceName = ""): tuple[source, header: string] =
  toC(p, o, header, sourceName, "SpritePad")

proc toC*(t: TiledMap, o: AsmOptions, header = "", sourceName = ""): tuple[source, header: string] =
  ## C source of a Tiled map, laid out as for a CharPad project.
  toC(t, o, header, sourceName, "Tiled")
