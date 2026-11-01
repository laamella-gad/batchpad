## Tiled map files (.tmx and .json). The layouts are described in docs/tiled.md.
##
## A Tiled map holds tile numbers, not pictures: the pictures are in the image
## a tileset names. So this model is not a CharPad project; `tiledbin.nim` turns
## its layers into the parts the binary exports write.

import std/[algorithm, base64, json, os, strtabs, strutils, xmlparser, xmltree]
import inflate

type
  TiledError* = object of ValueError

  Property* = object
    name*, kind*, value*: string   ## `kind` is Tiled's type name: string, int, float, bool, ...

  TiledObject* = object
    id*: int
    name*, class*: string
    x*, y*, width*, height*: float
    properties*: seq[Property]

  LayerKind* = enum
    lkTiles, lkObjects

  Layer* = object
    name*: string
    case kind*: LayerKind
    of lkTiles:
      originX*, originY*: int      ## tile position of the first cell (not 0 only in infinite maps)
      width*, height*: int
      gids*: seq[uint32]           ## row by row, flip bits included
    of lkObjects:
      objects*: seq[TiledObject]
    properties*: seq[Property]

  TilesetTile* = object
    id*: int
    class*: string
    properties*: seq[Property]

  Tileset* = object
    firstGid*: int
    source*: string                ## an external .tsx or .tsj; `resolveTilesets` reads it
    name*, image*: string
    tileWidth*, tileHeight*, tileCount*, columns*, spacing*, margin*: int
    imageWidth*, imageHeight*: int
    tiles*: seq[TilesetTile]

  TiledMap* = object
    version*: string
    width*, height*, tileWidth*, tileHeight*: int
    infinite*: bool
    tilesets*: seq[Tileset]
    layers*: seq[Layer]            ## tile and object layers; group layers are flattened
    properties*: seq[Property]
    skipped*: seq[string]          ## what was read but isn't kept
    layerName*, tilesetName*: string
      ## what `map` and the tile numbers use: the layer and the tileset to
      ## take; the first of each when empty
    emptyTile*: int                ## the tile number an empty cell (gid 0) gets
    objectPixels*: bool            ## object positions and sizes in pixels, not tiles
    objectFields*: seq[string]     ## integer properties written after each object

const
  flipH* = 0x80000000'u32
  flipV* = 0x40000000'u32
  flipD* = 0x20000000'u32
  hexRotate = 0x10000000'u32
  idMask* = not (flipH or flipV or flipD or hexRotate)

proc fail(msg: string) {.noreturn.} = raise newException(TiledError, msg)

func isTiles*(l: Layer): bool = l.kind == lkTiles

# --- tile data ---

proc decodeData(encoding, compression, text: string, count: int, what: string): seq[uint32] =
  ## The cells of a `data` element or of a chunk.
  case encoding
  of "csv", "":
    for field in text.split(','):
      let f = field.strip
      if f.len == 0: continue
      try: result.add uint32(parseBiggestUInt(f))
      except ValueError, OverflowDefect: fail(what & ": not a tile number: " & f)
  of "base64":
    if compression notin ["", "zlib", "gzip"]:
      fail(what & ": " & compression & " compressed data isn't supported; " &
           "set the tile layer compression to zlib or gzip, or the format to CSV (Map Properties)")
    var raw = ""
    for c in text:
      if c notin Whitespace: raw.add c
    var bytes = try: decode(raw)
                except ValueError as e: fail(what & ": bad base64: " & e.msg)
    try:
      if compression == "zlib": bytes = unzlib(bytes, count * 4)
      elif compression == "gzip": bytes = ungzip(bytes, count * 4)
    except InflateError as e: fail(what & ": " & e.msg)
    if bytes.len mod 4 != 0: fail(what & ": the data is not a whole number of cells")
    for i in 0 ..< bytes.len div 4:
      result.add uint32(bytes[4 * i].byte) or (uint32(bytes[4 * i + 1].byte) shl 8) or
                 (uint32(bytes[4 * i + 2].byte) shl 16) or (uint32(bytes[4 * i + 3].byte) shl 24)
  else:
    fail(what & ": unknown data encoding " & encoding)
  if result.len != count:
    fail(what & ": " & $count & " cells expected, found " & $result.len)

type Chunk = object
  x, y, width, height: int
  gids: seq[uint32]

proc joinChunks(l: var Layer, chunks: seq[Chunk]) =
  ## The cells of an infinite map's layer: the bounding box of its chunks.
  if chunks.len == 0:
    l.originX = 0
    l.originY = 0
    l.width = 0
    l.height = 0
    return
  var (x0, y0, x1, y1) = (chunks[0].x, chunks[0].y, chunks[0].x, chunks[0].y)
  for c in chunks:
    x0 = min(x0, c.x)
    y0 = min(y0, c.y)
    x1 = max(x1, c.x + c.width)
    y1 = max(y1, c.y + c.height)
  l.originX = x0
  l.originY = y0
  l.width = x1 - x0
  l.height = y1 - y0
  l.gids = newSeq[uint32](l.width * l.height)
  for c in chunks:
    for row in 0 ..< c.height:
      for col in 0 ..< c.width:
        l.gids[(c.y - y0 + row) * l.width + c.x - x0 + col] = c.gids[row * c.width + col]

proc checkSize(what: string, width, height: int) =
  if width < 0 or height < 0 or width.int64 * height > 1_000_000:
    fail(what & ": bad size " & $width & " x " & $height)

# --- TMX ---

proc intAttr(n: XmlNode, name: string, default = 0): int =
  let s = n.attr(name)
  if s == "": return default
  try: parseInt(s)
  except ValueError: fail("<" & n.tag & "> " & name & " is not a number: " & s)

proc floatAttr(n: XmlNode, name: string): float =
  let s = n.attr(name)
  if s == "": return 0
  try: parseFloat(s)
  except ValueError: fail("<" & n.tag & "> " & name & " is not a number: " & s)

iterator elements(n: XmlNode): XmlNode =
  for c in n:
    if c.kind == xnElement: yield c

proc tmxProperties(n: XmlNode): seq[Property] =
  for ps in n.elements:
    if ps.tag != "properties": continue
    for p in ps.elements:
      if p.tag != "property": continue
      let kind = p.attr("type")
      result.add Property(name: p.attr("name"), kind: if kind == "": "string" else: kind,
                          value: if p.attr("value") != "": p.attr("value") else: p.innerText)

proc tmxTileset(n: XmlNode): Tileset =
  result.firstGid = n.intAttr("firstgid", 1)
  result.source = n.attr("source")
  result.name = n.attr("name")
  result.tileWidth = n.intAttr("tilewidth")
  result.tileHeight = n.intAttr("tileheight")
  result.tileCount = n.intAttr("tilecount")
  result.columns = n.intAttr("columns")
  result.spacing = n.intAttr("spacing")
  result.margin = n.intAttr("margin")
  for c in n.elements:
    case c.tag
    of "image":
      result.image = c.attr("source")
      result.imageWidth = c.intAttr("width")
      result.imageHeight = c.intAttr("height")
    of "tile":
      result.tiles.add TilesetTile(id: c.intAttr("id"),
          class: if c.attr("class") != "": c.attr("class") else: c.attr("type"),
          properties: c.tmxProperties)
    else: discard

proc tmxObject(n: XmlNode): TiledObject =
  TiledObject(id: n.intAttr("id"), name: n.attr("name"),
              class: if n.attr("class") != "": n.attr("class") else: n.attr("type"),
              x: n.floatAttr("x"), y: n.floatAttr("y"), width: n.floatAttr("width"),
              height: n.floatAttr("height"), properties: n.tmxProperties)

proc tmxLayers(n: XmlNode, prefix: string, m: var TiledMap) =
  for c in n.elements:
    let name = prefix & c.attr("name")
    case c.tag
    of "layer":
      var l = Layer(kind: lkTiles, name: name, properties: c.tmxProperties)
      l.width = c.intAttr("width")
      l.height = c.intAttr("height")
      checkSize("layer " & name, l.width, l.height)
      var found = false
      for d in c.elements:
        if d.tag != "data": continue
        found = true
        let (enc, comp) = (d.attr("encoding"), d.attr("compression"))
        var chunks: seq[Chunk]
        for k in d.elements:
          if k.tag != "chunk": continue
          var ch = Chunk(x: k.intAttr("x"), y: k.intAttr("y"), width: k.intAttr("width"),
                         height: k.intAttr("height"))
          checkSize("layer " & name, ch.width, ch.height)
          ch.gids = decodeData(enc, comp, k.innerText, ch.width * ch.height, "layer " & name)
          chunks.add ch
        if chunks.len > 0 or m.infinite:
          l.joinChunks chunks
        elif enc == "" and comp == "":
          # The old form: a <tile gid=...> per cell.
          for k in d.elements:
            if k.tag == "tile": l.gids.add uint32(k.intAttr("gid"))
          if l.gids.len == 0:
            l.gids = decodeData("csv", "", d.innerText, l.width * l.height, "layer " & name)
          elif l.gids.len != l.width * l.height:
            fail("layer " & name & ": " & $(l.width * l.height) & " cells expected, found " & $l.gids.len)
        else:
          l.gids = decodeData(enc, comp, d.innerText, l.width * l.height, "layer " & name)
      if not found: fail("layer " & name & " has no data")
      m.layers.add l
    of "objectgroup":
      var l = Layer(kind: lkObjects, name: name, properties: c.tmxProperties)
      for o in c.elements:
        if o.tag == "object": l.objects.add o.tmxObject
      m.layers.add l
    of "group":
      c.tmxLayers(name & "/", m)
    of "imagelayer":
      m.skipped.add "image layer " & name
    else: discard

proc parseTmx*(text: string): TiledMap =
  ## Parses a whole .tmx file. Raises TiledError on anything it can't read.
  let root = try: parseXml(text)
             except ValueError as e: fail("not a Tiled map: " & e.msg)
  if root.kind != xnElement or root.tag != "map": fail("not a Tiled map (no <map>)")
  let orientation = root.attr("orientation")
  if orientation notin ["", "orthogonal"]:
    fail("only orthogonal maps are supported, not " & orientation)
  result.version = root.attr("version")
  result.infinite = root.attr("infinite") == "1"
  result.width = root.intAttr("width")
  result.height = root.intAttr("height")
  result.tileWidth = root.intAttr("tilewidth")
  result.tileHeight = root.intAttr("tileheight")
  checkSize("the map", result.width, result.height)
  result.properties = root.tmxProperties
  for c in root.elements:
    if c.tag == "tileset": result.tilesets.add c.tmxTileset
  root.tmxLayers("", result)

# --- JSON ---

proc jsonProperties(n: JsonNode): seq[Property] =
  let ps = n.getOrDefault("properties")
  if ps == nil or ps.kind != JArray: return
  for p in ps:
    if p.kind != JObject: continue
    let v = p.getOrDefault("value")
    let kind = p.getOrDefault("type").getStr("string")
    var value = ""
    if v != nil:
      value = case v.kind
              of JString: v.getStr
              of JNull: ""
              else: $v
    result.add Property(name: p.getOrDefault("name").getStr, kind: kind, value: value)

proc jsonInt(n: JsonNode, key: string, default = 0): int =
  let v = n.getOrDefault(key)
  if v == nil: return default
  if v.kind != JInt: fail("\"" & key & "\" is not a number: " & $v)
  v.getInt

proc jsonData(d: JsonNode, encoding, compression: string, count: int, what: string): seq[uint32] =
  if d == nil: fail(what & " has no data")
  case d.kind
  of JArray:
    for v in d:
      if v.kind != JInt or v.getBiggestInt notin 0 .. 0xffffffff'i64:
        fail(what & ": not a tile number: " & $v)
      result.add uint32(v.getBiggestInt)
    if result.len != count: fail(what & ": " & $count & " cells expected, found " & $result.len)
  of JString:
    result = decodeData(if encoding == "": "base64" else: encoding, compression, d.getStr, count, what)
  else:
    fail(what & ": the data is not a list")

proc jsonLayers(layers: JsonNode, prefix: string, m: var TiledMap) =
  if layers == nil or layers.kind != JArray: return
  for c in layers:
    if c.kind != JObject: continue
    let name = prefix & c.getOrDefault("name").getStr
    case c.getOrDefault("type").getStr
    of "tilelayer":
      var l = Layer(kind: lkTiles, name: name, properties: c.jsonProperties)
      l.width = c.jsonInt("width")
      l.height = c.jsonInt("height")
      let (enc, comp) = (c.getOrDefault("encoding").getStr, c.getOrDefault("compression").getStr)
      let chunkList = c.getOrDefault("chunks")
      if chunkList != nil and chunkList.kind == JArray:
        var chunks: seq[Chunk]
        for k in chunkList:
          var ch = Chunk(x: k.jsonInt("x"), y: k.jsonInt("y"), width: k.jsonInt("width"),
                         height: k.jsonInt("height"))
          checkSize("layer " & name, ch.width, ch.height)
          ch.gids = jsonData(k.getOrDefault("data"), enc, comp, ch.width * ch.height, "layer " & name)
          chunks.add ch
        l.joinChunks chunks
      else:
        checkSize("layer " & name, l.width, l.height)
        l.gids = jsonData(c.getOrDefault("data"), enc, comp, l.width * l.height, "layer " & name)
      m.layers.add l
    of "objectgroup":
      var l = Layer(kind: lkObjects, name: name, properties: c.jsonProperties)
      let objs = c.getOrDefault("objects")
      if objs != nil and objs.kind == JArray:
        for o in objs:
          let class = o.getOrDefault("class").getStr(o.getOrDefault("type").getStr)
          l.objects.add TiledObject(id: o.jsonInt("id"), name: o.getOrDefault("name").getStr,
              class: class, x: o.getOrDefault("x").getFloat, y: o.getOrDefault("y").getFloat,
              width: o.getOrDefault("width").getFloat, height: o.getOrDefault("height").getFloat,
              properties: o.jsonProperties)
      m.layers.add l
    of "group":
      c.getOrDefault("layers").jsonLayers(name & "/", m)
    of "imagelayer":
      m.skipped.add "image layer " & name
    else: discard

proc jsonTileset(s: JsonNode): Tileset =
  result = Tileset(firstGid: s.jsonInt("firstgid", 1), source: s.getOrDefault("source").getStr,
                   name: s.getOrDefault("name").getStr, image: s.getOrDefault("image").getStr,
                   tileWidth: s.jsonInt("tilewidth"), tileHeight: s.jsonInt("tileheight"),
                   tileCount: s.jsonInt("tilecount"), columns: s.jsonInt("columns"),
                   spacing: s.jsonInt("spacing"), margin: s.jsonInt("margin"),
                   imageWidth: s.jsonInt("imagewidth"), imageHeight: s.jsonInt("imageheight"))
  let tiles = s.getOrDefault("tiles")
  if tiles != nil and tiles.kind == JArray:
    for k in tiles:
      result.tiles.add TilesetTile(id: k.jsonInt("id"),
          class: k.getOrDefault("class").getStr(k.getOrDefault("type").getStr),
          properties: k.jsonProperties)

proc parseTiledJson*(text: string): TiledMap =
  ## Parses a whole Tiled JSON map (.tmj or .json). Raises TiledError on anything it can't read.
  let j = try: parseJson(text)
          except JsonParsingError as e: fail("not a Tiled map: " & e.msg)
  if j.kind != JObject or j.getOrDefault("layers") == nil or j.getOrDefault("tilewidth") == nil:
    fail("not a Tiled map (no layers or tilewidth)")
  let orientation = j.getOrDefault("orientation").getStr("orthogonal")
  if orientation != "orthogonal": fail("only orthogonal maps are supported, not " & orientation)
  result.version = j.getOrDefault("version").getStr
  result.infinite = j.getOrDefault("infinite").getBool
  result.width = j.jsonInt("width")
  result.height = j.jsonInt("height")
  result.tileWidth = j.jsonInt("tilewidth")
  result.tileHeight = j.jsonInt("tileheight")
  checkSize("the map", result.width, result.height)
  result.properties = j.jsonProperties
  let sets = j.getOrDefault("tilesets")
  if sets != nil and sets.kind == JArray:
    for s in sets: result.tilesets.add s.jsonTileset
  j["layers"].jsonLayers("", result)

# --- reading and finding things ---

proc resolveTilesets*(m: var TiledMap, dir: string) =
  ## Reads the external tilesets (`.tsx`, or JSON `.tsj`) the map names, looking in
  ## `dir`. Their `firstgid` and `source` stay as the map has them.
  for t in m.tilesets.mitems:
    if t.source == "": continue
    let path = dir / t.source
    if not fileExists(path): fail("can't find the tileset " & t.source & " (looked for " & path & ")")
    let text = readFile(path)
    let (firstGid, source) = (t.firstGid, t.source)
    if text.strip.startsWith("<"):
      var root: XmlNode
      try: root = parseXml(text)
      except CatchableError as e: fail("tileset " & t.source & " is not valid XML: " & e.msg)
      if root.tag != "tileset": fail("tileset " & t.source & " is not a tileset")
      t = root.tmxTileset
    else:
      var j: JsonNode
      try: j = parseJson(text)
      except CatchableError as e: fail("tileset " & t.source & " is not valid JSON: " & e.msg)
      t = j.jsonTileset
    t.firstGid = firstGid
    t.source = source

proc readTiled*(path: string): TiledMap =
  ## Reads a .tmx, or else a JSON map, and the external tilesets it names.
  let text = readFile(path)
  result = if text.strip.startsWith("<"): parseTmx(text) else: parseTiledJson(text)
  result.resolveTilesets(path.parentDir)

func tileLayer*(m: TiledMap, name = ""): Layer =
  ## The tile layer called `name`, `m.layerName` when that is empty, and then the first one.
  let want = if name != "": name else: m.layerName
  for l in m.layers:
    if l.kind == lkTiles and (want == "" or l.name == want): return l
  if want == "": fail("the map has no tile layer")
  fail("the map has no tile layer " & want)

func objectLayer*(m: TiledMap, name = ""): Layer =
  ## The object layer called `name`, or the first one.
  for l in m.layers:
    if l.kind == lkObjects and (name == "" or l.name == name): return l
  if name == "": fail("the map has no object layer")
  fail("the map has no object layer " & name)

func objectClasses*(m: TiledMap): seq[string] =
  ## The classes of all objects in the map, sorted: an object's class number is
  ## its place in this list.
  for l in m.layers:
    if l.kind == lkObjects:
      for o in l.objects:
        if o.class != "" and o.class notin result: result.add o.class
  result.sort

func tilesetIndex*(m: TiledMap): int =
  ## The tileset `m.tilesetName` names, or the first.
  if m.tilesets.len == 0: fail("the map has no tileset")
  if m.tilesetName == "": return 0
  for i, t in m.tilesets:
    if t.name == m.tilesetName: return i
  fail("the map has no tileset " & m.tilesetName)

func property*(props: openArray[Property], name: string): string =
  ## The value of the property `name`, "" when there is none.
  for p in props:
    if p.name == name: return p.value

# --- writing ---

proc propertyJson(p: Property): JsonNode =
  let v = case p.kind
          of "int", "object":
            (try: %parseBiggestInt(p.value) except ValueError: %p.value)
          of "float":
            (try: %parseFloat(p.value) except ValueError: %p.value)
          of "bool": %(p.value == "true")
          else: %p.value
  result = %*{"name": p.name, "type": p.kind, "value": v}

const writerVersion = "1.10"

proc toTiledJson*(m: TiledMap): string =
  ## Formats `m` as a Tiled JSON map: CSV data, finite, orthogonal.
  var tilesets = newJArray()
  for t in m.tilesets:
    if t.source != "":
      tilesets.add %*{"firstgid": t.firstGid, "source": t.source}
      continue
    var o = %*{"firstgid": t.firstGid, "name": t.name, "tilewidth": t.tileWidth,
               "tileheight": t.tileHeight, "tilecount": t.tileCount, "columns": t.columns,
               "spacing": t.spacing, "margin": t.margin, "image": t.image,
               "imagewidth": t.imageWidth, "imageheight": t.imageHeight}
    if t.tiles.len > 0:
      var tiles = newJArray()
      for k in t.tiles:
        var e = %*{"id": k.id}
        if k.class != "": e["class"] = %k.class
        if k.properties.len > 0:
          e["properties"] = newJArray()
          for p in k.properties: e["properties"].add p.propertyJson
        tiles.add e
      o["tiles"] = tiles
    tilesets.add o
  var layers = newJArray()
  var id = 0
  for l in m.layers:
    inc id
    var o = %*{"id": id, "name": l.name, "visible": true, "opacity": 1, "x": 0, "y": 0}
    case l.kind
    of lkTiles:
      o["type"] = %"tilelayer"
      o["width"] = %l.width
      o["height"] = %l.height
      o["data"] = newJArray()
      for g in l.gids: o["data"].add %g
    of lkObjects:
      o["type"] = %"objectgroup"
      o["draworder"] = %"topdown"
      var objs = newJArray()
      for e in l.objects:
        var oo = %*{"id": e.id, "name": e.name, "class": e.class, "x": e.x, "y": e.y,
                    "width": e.width, "height": e.height, "visible": true, "rotation": 0}
        if e.properties.len > 0:
          oo["properties"] = newJArray()
          for p in e.properties: oo["properties"].add p.propertyJson
        objs.add oo
      o["objects"] = objs
    if l.properties.len > 0:
      o["properties"] = newJArray()
      for p in l.properties: o["properties"].add p.propertyJson
    layers.add o
  var j = %*{"type": "map", "version": writerVersion, "orientation": "orthogonal",
             "renderorder": "right-down", "infinite": false, "width": m.width,
             "height": m.height, "tilewidth": m.tileWidth, "tileheight": m.tileHeight,
             "nextlayerid": id + 1, "nextobjectid": 1, "tilesets": tilesets, "layers": layers}
  if m.properties.len > 0:
    j["properties"] = newJArray()
    for p in m.properties: j["properties"].add p.propertyJson
  j.pretty & "\n"

proc propertiesXml(props: seq[Property]): XmlNode =
  result = newElement("properties")
  for p in props:
    let e = newElement("property")
    e.attrs = {"name": p.name, "type": p.kind, "value": p.value}.toXmlAttributes
    result.add e

proc toTmx*(m: TiledMap): string =
  ## Formats `m` as a TMX map: CSV data, finite, orthogonal.
  let root = newElement("map")
  var id = 0
  for l in m.layers: inc id
  root.attrs = {"version": writerVersion, "orientation": "orthogonal", "renderorder": "right-down",
                "width": $m.width, "height": $m.height, "tilewidth": $m.tileWidth,
                "tileheight": $m.tileHeight, "infinite": "0", "nextlayerid": $(id + 1),
                "nextobjectid": "1"}.toXmlAttributes
  if m.properties.len > 0: root.add m.properties.propertiesXml
  for t in m.tilesets:
    let e = newElement("tileset")
    if t.source != "":
      e.attrs = {"firstgid": $t.firstGid, "source": t.source}.toXmlAttributes
    else:
      e.attrs = {"firstgid": $t.firstGid, "name": t.name, "tilewidth": $t.tileWidth,
                 "tileheight": $t.tileHeight, "tilecount": $t.tileCount,
                 "columns": $t.columns, "spacing": $t.spacing,
                 "margin": $t.margin}.toXmlAttributes
      if t.image != "":
        let img = newElement("image")
        img.attrs = {"source": t.image, "width": $t.imageWidth,
                     "height": $t.imageHeight}.toXmlAttributes
        e.add img
      for k in t.tiles:
        let tile = newElement("tile")
        tile.attrs = {"id": $k.id}.toXmlAttributes
        if k.class != "": tile.attrs["class"] = k.class
        if k.properties.len > 0: tile.add k.properties.propertiesXml
        e.add tile
    root.add e
  id = 0
  for l in m.layers:
    inc id
    case l.kind
    of lkTiles:
      let e = newElement("layer")
      e.attrs = {"id": $id, "name": l.name, "width": $l.width,
                 "height": $l.height}.toXmlAttributes
      if l.properties.len > 0: e.add l.properties.propertiesXml
      let d = newElement("data")
      d.attrs = {"encoding": "csv"}.toXmlAttributes
      var rows: seq[string]
      for y in 0 ..< l.height:
        var row: seq[string]
        for x in 0 ..< l.width: row.add $l.gids[y * l.width + x]
        rows.add row.join(",")
      d.add newText("\n" & rows.join(",\n") & "\n")
      e.add d
      root.add e
    of lkObjects:
      let e = newElement("objectgroup")
      e.attrs = {"id": $id, "name": l.name}.toXmlAttributes
      if l.properties.len > 0: e.add l.properties.propertiesXml
      for o in l.objects:
        let oe = newElement("object")
        oe.attrs = {"id": $o.id, "name": o.name, "class": o.class, "x": $o.x, "y": $o.y,
                    "width": $o.width, "height": $o.height}.toXmlAttributes
        if o.properties.len > 0: oe.add o.properties.propertiesXml
        e.add oe
      root.add e
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" & $root & "\n"
