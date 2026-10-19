## Little-endian byte reading and writing, shared by the file formats.

type
  Reader*[E] = object
    ## Reads `data` from `pos` on and raises E on anything it can't read.
    data*: seq[byte]
    pos*: int

  Writer* = object
    data*: seq[byte]
    blocks*: int     ## for formats that number their blocks

proc fail*[E](r: Reader[E], msg: string) {.noreturn.} =
  raise newException(E, msg & " at offset " & $r.pos)

proc u8*[E](r: var Reader[E]): uint8 =
  if r.pos >= r.data.len: r.fail("unexpected end of file")
  result = r.data[r.pos]
  inc r.pos

proc u16*[E](r: var Reader[E]): uint16 =
  let lo = r.u8
  result = lo.uint16 or (r.u8.uint16 shl 8)

proc zstring*[E](r: var Reader[E]): string =
  ## A 0-terminated string.
  while true:
    let c = r.u8
    if c == 0: break
    result.add char(c)

proc u8*(w: var Writer, v: SomeInteger) = w.data.add byte(v)

proc u16*(w: var Writer, v: SomeInteger) =
  w.u8(v and 0xff)
  w.u8((v shr 8) and 0xff)

proc zstring*(w: var Writer, s: string) =
  for c in s: w.u8 ord(c)
  w.u8 0

func count*(n: int, things: string): string =
  ## `count(3, "tiles")` is "3 tiles", `count(1, "tiles")` is "1 tile".
  $n & " " & (if n == 1: things[0 .. ^2] else: things)
