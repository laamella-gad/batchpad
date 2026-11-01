## CharPad C16 project files (`.ctt`, V8 and V9) as CharPad projects with TED
## colours (`Project.ted`). Layouts are described in docs/charpad.md.

import std/bitops
import binio, ctm, image

type
  CttError* = object of CtmError

  Reader = binio.Reader[CttError]

const
  tedRgb: array[128, uint32] = [
  0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
  0x202020, 0x303030, 0x404040, 0x505050, 0x787878, 0x909090, 0xc0c0c0, 0xffffff,
  0x5e0700, 0x6e1710, 0x7e2720, 0x8e3730, 0xb65f58, 0xce7770, 0xfea7a0, 0xffe7e0,
  0x003940, 0x004950, 0x025960, 0x126970, 0x3a9198, 0x52a9b0, 0x82d9e0, 0xc2ffff,
  0x56006c, 0x66067c, 0x76168c, 0x86269c, 0xae4ec4, 0xc666dc, 0xf696ff, 0xffd6ff,
  0x004a00, 0x005a00, 0x0a6a00, 0x1a7a04, 0x42a22c, 0x5aba44, 0x8aea74, 0xcaffb4,
  0x150aae, 0x251abe, 0x352ace, 0x453ade, 0x6d62ff, 0x857aff, 0xb5aaff, 0xf5eaff,
  0x2b3600, 0x3b4600, 0x4b5600, 0x5b6600, 0x838e00, 0x9ba602, 0xcbd632, 0xffff72,
  0x541600, 0x642600, 0x743600, 0x844600, 0xac6e25, 0xc4863d, 0xf4b66d, 0xfff6ad,
  0x422600, 0x523600, 0x624600, 0x725600, 0x9a7e00, 0xb29616, 0xe2c646, 0xffff86,
  0x124300, 0x225300, 0x326300, 0x427300, 0x6a9b00, 0x82b304, 0xb2e334, 0xf2ff74,
  0x5f0038, 0x6f0b48, 0x7f1b58, 0x8f2b68, 0xb75390, 0xcf6ba8, 0xff9bd8, 0xffdbff,
  0x004508, 0x005518, 0x016528, 0x117538, 0x399d60, 0x51b578, 0x81e5a8, 0xc1ffe8,
  0x001a9a, 0x0e2aaa, 0x1e3aba, 0x2e4aca, 0x5672f2, 0x6e8aff, 0x9ebaff, 0xdefaff,
  0x2e00ac, 0x3e0dbc, 0x4e1dcc, 0x5e2ddc, 0x8655ff, 0x9e6dff, 0xce9dff, 0xffddff,
  0x004a00, 0x0b5a00, 0x1b6a00, 0x2b7a00, 0x53a203, 0x6bba1b, 0x9bea4b, 0xdbff8b
  ]
    ## VICE 3.9's internal TED palette (xplus4 with its default colour
    ## controls, read off a screenshot with the render filter off): 16 chromas
    ## of 8 lumas each, chroma major. The colour number of a TED colour is
    ## `luma * 16 + chroma`.

proc tedColour*(c: uint8): Rgb =
  ## The colour of a 7 bit TED colour number (higher bits are ignored).
  let v = tedRgb[int(c and 15) * 8 + int((c shr 4) and 7)]
  [uint8(v shr 16), uint8(v shr 8), uint8(v)]

func distance(a, b: Rgb): int =
  for i in 0 .. 2:
    let d = int(a[i]) - int(b[i])
    result += d * d

proc nearestC64*(c: uint8): uint8 =
  ## The colour of `vice` closest to the TED colour `c`.
  let rgb = tedColour(c)
  var best = high(int)
  for i, p in vice:
    let d = distance(rgb, p)
    if d < best:
      best = d
      result = uint8(i)

proc nearestTed*(c: uint8, chroma = -1): uint8 =
  ## The TED colour closest to the C64 colour `c` (0-15). With `chroma`
  ## (0-15) only the colours of that chroma are looked at: that picks the luma.
  let rgb = vice[int(c and 15)]
  var best = high(int)
  for v in 0'u8 .. 127:
    if chroma >= 0 and int(v and 15) != chroma: continue
    let d = distance(rgb, tedColour(v))
    if d < best:
      best = d
      result = v

proc blockMarker(r: var Reader, what: string) =
  let start = r.pos
  if r.u8 != 0xda'u8:
    r.pos = start
    r.fail("missing block marker before " & what)
  discard r.u8

proc readColours(r: var Reader, mode: DisplayMode): Colours =
  ## One colour in the text modes; in the bitmap modes two, the first one
  ## going into `colours[2]`, as CharPad C64 Pro's converter does. Both 7 bit.
  if mode in {dmHiresBitmap, dmMulticolourBitmap}:
    result[2] = r.u8 and 0x7f
    result[1] = r.u8 and 0x7f
  else:
    result[0] = r.u8 and 0x7f

proc parseCtt*(data: openArray[byte]): Project =
  ## Parses a whole .ctt file (V8 or V9). Raises CttError on anything it
  ## can't read. The colours stay TED colours (`ted` is set).
  var r = Reader(data: @data)
  if data.len < 4 or data[0] != byte('C') or data[1] != byte('T') or data[2] != byte('T'):
    r.fail("not a CharPad C16 project (no CTT signature)")
  r.pos = 3
  let version = r.u8.int
  if version notin [8, 9]: r.fail("CTT version " & $version & " is not supported")
  result.version = version
  result.ted = true
  let mode = r.u8
  if mode.int > ord(DisplayMode.high): r.fail("unknown display mode " & $mode)
  result.displayMode = DisplayMode(mode)
  let colouring = r.u8
  if colouring > ord(ColouringMethod.high): r.fail("unknown colouring method " & $colouring)
  result.colouring = ColouringMethod(colouring)
  let flags = r.u8
  result.tileSystem = flags.testBit(0)
  if version == 9:
    result.keyMap = flags shr 4
    result.flexiGrid.width = r.u16
    result.flexiGrid.height = r.u16
    result.flexiGrid.settings = r.u8
  for c in result.chipColours.mitems: c = r.u8 and 0x7f
  # The project colours are two bytes in every mode. Text modes use the first;
  # the second is kept in `colours[1]` so that a file is written back as read.
  result.colours = r.readColours(result.displayMode)
  if result.displayMode notin {dmHiresBitmap, dmMulticolourBitmap}:
    result.colours[1] = r.u8 and 0x7f

  r.blockMarker("chars")
  result.chars.setLen(r.u16.int + 1)
  for ch in result.chars.mitems:
    for b in ch.data.mitems: b = r.u8
  r.blockMarker("char materials")
  for ch in result.chars.mitems: ch.material = r.u8 and 0x0f
  if result.colouring == cmPerChar:
    r.blockMarker("char colours")
    for ch in result.chars.mitems: ch.colours = r.readColours(result.displayMode)

  if result.tileSystem:
    r.blockMarker("tiles")
    result.tiles.setLen(r.u16.int + 1)
    result.tileWidth = r.u8.int
    result.tileHeight = r.u8.int
    for t in result.tiles.mitems:
      t.cells.setLen(result.tileWidth * result.tileHeight)
      for c in t.cells.mitems: c = r.u16
    if result.colouring == cmPerTile:
      r.blockMarker("tile colours")
      for t in result.tiles.mitems: t.colours = r.readColours(result.displayMode)
    r.blockMarker("tile tags")
    for t in result.tiles.mitems: t.tag = r.u8
    r.blockMarker("tile names")
    for t in result.tiles.mitems: t.name = r.zstring

  r.blockMarker("map")
  result.mapWidth = r.u16.int
  result.mapHeight = r.u16.int
  result.map.setLen(result.mapWidth * result.mapHeight)
  for c in result.map.mitems: c = r.u16
  if r.pos != r.data.len:
    r.fail($(r.data.len - r.pos) & " bytes after the map")

proc readCtt*(path: string): Project =
  let s = readFile(path)
  parseCtt(s.toOpenArrayByte(0, s.high))

proc fail(msg: string) {.noreturn.} = raise newException(CttError, msg)

proc blockMarker(w: var Writer) =
  w.u8 0xda
  w.u8(0xb0 + w.blocks)
  inc w.blocks

proc writeColours(w: var Writer, c: Colours, mode: DisplayMode) =
  if mode in {dmHiresBitmap, dmMulticolourBitmap}:
    w.u8 c[2] and 0x7f
    w.u8 c[1] and 0x7f
  else:
    w.u8 c[0] and 0x7f

proc toCtt*(p: Project, version: int, leftOut: var seq[string]): seq[byte] =
  ## Formats a TED project (`p.ted`) as a .ctt file of version 8 or 9. Leaves
  ## out what the version can't hold, with a line in `leftOut` for each: the
  ## key map and the flexi-grid in V8, key maps above 10 in V9. Raises
  ## CttError for other versions, for a project with C64 colours (use
  ## `toTed` first) and for one that doesn't hold together.
  if version notin [8, 9]: fail("writing CTT version " & $version & " is not supported")
  if not p.ted: fail("the project has C64 colours; convert them with toTed first")
  if p.chars.len == 0: fail("no chars")
  if p.chars.len > 65536: fail("more than 65536 chars")
  if p.tileSystem:
    if p.tiles.len == 0: fail("the tile system is on, but there are no tiles")
    if p.tiles.len > 65536: fail("more than 65536 tiles")
    if p.tileWidth notin 1 .. 255 or p.tileHeight notin 1 .. 255:
      fail("tile size " & $p.tileWidth & " x " & $p.tileHeight & " is not 1 x 1 to 255 x 255")
    for i, t in p.tiles:
      if t.cells.len != p.tileWidth * p.tileHeight:
        fail("tile " & $i & " has " & $t.cells.len & " cells, not " & $(p.tileWidth * p.tileHeight))
  if p.mapWidth notin 0 .. 65535 or p.mapHeight notin 0 .. 65535 or p.map.len != p.mapWidth * p.mapHeight:
    fail("map has " & $p.map.len & " cells, not " & $p.mapWidth & " x " & $p.mapHeight)
  var keyMap = p.keyMap
  if keyMap > 10:
    leftOut.add "key map " & $keyMap & " (CharPad C16 has 0-10)"
    keyMap = 0
  if version == 8:
    if keyMap != 0: leftOut.add "key map " & $keyMap & " (V8 has none)"
    if p.flexiGrid.settings.testBit(7): leftOut.add "the flexi-grid (V8 has none)"
  var w: Writer
  for c in "CTT": w.u8 ord(c)
  w.u8 version
  w.u8 ord(p.displayMode)
  w.u8 ord(p.colouring)
  if version == 9:
    w.u8((keyMap shl 4) or uint8(p.tileSystem))
    w.u16 p.flexiGrid.width
    w.u16 p.flexiGrid.height
    w.u8 p.flexiGrid.settings
  else:
    w.u8 uint8(p.tileSystem)
  for c in p.chipColours: w.u8 c and 0x7f
  w.writeColours(p.colours, p.displayMode)
  if p.displayMode notin {dmHiresBitmap, dmMulticolourBitmap}: w.u8 p.colours[1] and 0x7f
  w.blockMarker
  w.u16 p.chars.len - 1
  for ch in p.chars:
    for b in ch.data: w.u8 b
  w.blockMarker
  for ch in p.chars: w.u8 ch.material and 0x0f
  if p.colouring == cmPerChar:
    w.blockMarker
    for ch in p.chars: w.writeColours(ch.colours, p.displayMode)
  if p.tileSystem:
    w.blockMarker
    w.u16 p.tiles.len - 1
    w.u8 p.tileWidth
    w.u8 p.tileHeight
    for t in p.tiles:
      for c in t.cells: w.u16 c
    if p.colouring == cmPerTile:
      w.blockMarker
      for t in p.tiles: w.writeColours(t.colours, p.displayMode)
    w.blockMarker
    for t in p.tiles: w.u8 t.tag
    w.blockMarker
    var cut = 0
    for t in p.tiles:
      var name = t.name
      let zero = name.find('\0')
      if zero >= 0: name.setLen zero
      if name.len > 32: name.setLen 32
      if name != t.name: inc cut
      w.zstring name
    if cut > 0: leftOut.add "the end of " & count(cut, "tile names") & " (past 32 chars or a 0 byte)"
  w.blockMarker
  w.u16 p.mapWidth
  w.u16 p.mapHeight
  for c in p.map: w.u16 c
  w.data

proc toCtt*(p: Project, version = 9): seq[byte] =
  var leftOut: seq[string]
  p.toCtt(version, leftOut)

proc writeCtt*(path: string, p: Project, version = 9) =
  writeFile(path, p.toCtt(version))

proc convertColours(p: var Project, toTed: bool) =
  ## Maps every colour of `p` to the other palette. In multicolour text the
  ## top bit of a cell colour (the multicolour flag) is kept and the colour
  ## under it, 0-7, is the same number on both machines: only the TED luma
  ## has to be picked.
  let mode = p.displayMode
  func plain(v: uint8): uint8 = (if toTed: nearestTed(v) else: nearestC64(v))
  func cell(v: uint8): uint8 =
    if mode == dmMulticolourText:
      let flag = v and 8
      (if toTed: nearestTed(v and 7, int(v and 7)) else: v and 7) or flag
    else: plain(v)
  func cellColours(c: Colours): Colours =
    result = c
    if mode in {dmHiresBitmap, dmMulticolourBitmap}:
      for i in 1 .. 2: result[i] = plain(c[i])
    else:
      result[0] = cell(c[0])
  for c in p.chipColours.mitems: c = plain(c)
  p.colours = cellColours(p.colours)
  for ch in p.chars.mitems: ch.colours = cellColours(ch.colours)
  for t in p.tiles.mitems: t.colours = cellColours(t.colours)
  p.ted = toTed

proc toTed*(p: Project, leftOut: var seq[string]): Project =
  ## A copy of `p` with its C64 colours turned into the nearest TED colours
  ## (CharPad C16's own palette against VICE's C64 palette). A project that already has
  ## TED colours is returned unchanged. Bitmap modes have no colour RAM colour
  ## on the C16; in multicolour bitmap the pen 11 colour becomes TED colour 1,
  ## which all cells share, and a line goes to `leftOut` when cells differ in it.
  result = p
  if p.ted: return
  let bitmap = p.displayMode in {dmHiresBitmap, dmMulticolourBitmap}
  result.convertColours(true)
  if p.displayMode == dmMulticolourBitmap:
    case p.colouring
    of cmPerProject: result.chipColours[1] = nearestTed(p.colours[0])
    of cmPerTile:
      for t in p.tiles:
        if t.colours[0] != p.colours[0]:
          leftOut.add "the colour RAM colours of tiles (CharPad C16 has one shared colour)"
          break
    of cmPerChar:
      for c in p.chars:
        if c.colours[0] != p.colours[0]:
          leftOut.add "the colour RAM colours of chars (CharPad C16 has one shared colour)"
          break
  if bitmap:
    result.colours[0] = 0
    for c in result.chars.mitems: c.colours[0] = 0
    for t in result.tiles.mitems: t.colours[0] = 0

proc toC64*(p: Project): Project =
  ## A copy of `p` with its TED colours turned into the nearest C64 colours,
  ## as CharPad C64 Pro does when it opens a .ctt. A project that already has
  ## C64 colours is returned unchanged. In multicolour bitmap the TED colour 1
  ## becomes the colour RAM colour (pen 11) of the project, of every char and
  ## of every tile; with per-project colouring the chip colour 1 is then 0.
  result = p
  if not p.ted: return
  result.convertColours(false)
  if p.displayMode == dmMulticolourBitmap:
    let shared = result.chipColours[1]
    result.colours[0] = shared
    for c in result.chars.mitems: c.colours[0] = shared
    for t in result.tiles.mitems: t.colours[0] = shared
    if p.colouring == cmPerProject: result.chipColours[1] = 0
