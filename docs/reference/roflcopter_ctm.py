#!/usr/bin/env python3
"""Converts the playfield (screen codes and colours) to and from a CharPad project (.ctm).

    tools/ctm.py export src/playfield_chars.bin src/playfield_colours.bin src/charset.bin playfield.ctm
    tools/ctm.py import playfield.ctm src/playfield_chars.bin src/playfield_colours.bin [src/charset.bin]

Export writes CTM version 7 as CharPad Free 2.86 saves it: multicolour, no
tiles, colour per character, the map holds character numbers. Characters 0-255
are the charset, so character numbers are screen codes. Some characters appear
in several colours; each extra colour gets a copy of the character after 255.
On import a copy stands for the character below 256 with the same image and
material (the export gives copies of characters with a common image, like the
blank $20 and $3d, a material of their own). So to use a character in a new
colour, copy it to the end of the set and colour the copy.

Import reads versions 5, 7 and 9 (CharPad Pro), with any tile size and
colouring.
Formats as read by github.com/c64lib/gradle-retro-assembler-plugin.
"""
import struct
import sys

WIDTH, HEIGHT = 40, 25

# The game's VIC colours: background $d021, $d022, $d023
SCREEN_COLOUR, MULTICOLOUR1, MULTICOLOUR2 = 14, 11, 8

TILE_SYS, CHAR_EX = 0x01, 0x02
TEXT_MULTICOLOUR = 1
GLOBAL, PER_TILE, PER_CHAR = 0, 1, 2


def export(chars_path, colours_path, charset_path, ctm_path):
    chars = open(chars_path, 'rb').read()[:1000]
    colours = [c & 15 for c in open(colours_path, 'rb').read()[:1000]]
    charset = open(charset_path, 'rb').read()

    image = [charset[c * 8:c * 8 + 8] for c in range(256)]

    # Each character keeps its most used colour, the others go to copies
    uses = {}
    for cell in zip(chars, colours):
        uses[cell] = uses.get(cell, 0) + 1
    char_colour = [0] * 256
    for ch in range(256):
        found = [co for (c, co) in uses if c == ch]
        if found:
            char_colour[ch] = max(found, key=lambda co: (uses[(ch, co)], -co))
    copies = sorted(cell for cell in uses if char_colour[cell[0]] != cell[1])
    copy_of = {cell: 256 + i for i, cell in enumerate(copies)}

    # Copied characters that share their image with others get a material of their own
    material = [0] * 256
    for ch in sorted({ch for ch, co in copies}):
        taken = {material[c] for c in range(256) if image[c] == image[ch] and c != ch}
        if 0 in taken:
            free = [m for m in range(1, 16) if m not in taken]
            if not free:
                sys.exit(f'ctm: too many characters share the image of ${ch:02x}')
            material[ch] = free[0]

    # Each block starts with $da, $b0 + its number
    blocks = []

    def block(data):
        blocks.append(bytes([0xda, 0xb0 | len(blocks)]) + data)

    block(struct.pack('<H', 256 + len(copies) - 1) + charset[:2048] + b''.join(image[ch] for ch, co in copies))
    block(bytes(material[c] << 4 | char_colour[c] for c in range(256)) +
          bytes(material[ch] << 4 | co for ch, co in copies))
    block(struct.pack('<HH', WIDTH, HEIGHT) +
          b''.join(struct.pack('<H', copy_of.get(cell, cell[0])) for cell in zip(chars, colours)))

    out = bytearray(b'CTM\x07')
    out += bytes([SCREEN_COLOUR, MULTICOLOUR1, MULTICOLOUR2, 12, 15, PER_CHAR, TEXT_MULTICOLOUR, 0])
    out += b''.join(blocks)
    open(ctm_path, 'wb').write(out)
    print(f'{ctm_path}: 256 chars + {len(copies)} copies for extra colours, map {WIDTH}x{HEIGHT}')


class Reader:
    def __init__(self, data):
        self.data, self.pos, self.block = data, 0, 0

    def bytes(self, n):
        b = self.data[self.pos:self.pos + n]
        if len(b) < n:
            sys.exit('ctm: file ends early')
        self.pos += n
        return b

    def byte(self):
        return self.bytes(1)[0]

    def word(self):
        return struct.unpack('<H', self.bytes(2))[0]

    def words(self, n):
        return list(struct.unpack(f'<{n}H', self.bytes(n * 2)))

    def marker(self):
        b0, b1 = self.byte(), self.byte()
        if b0 != 0xda or b1 != 0xb0 | self.block:
            sys.exit(f'ctm: no block {self.block} marker at {self.pos - 2}')
        self.block += 1


def read_v5(r):
    r.bytes(4)  # screen, multicolour 1 and 2, char colour
    method, flags = r.byte(), r.byte()
    num_chars, num_tiles = r.word() + 1, r.word() + 1
    tile_w, tile_h = r.byte(), r.byte()
    map_w, map_h = r.word(), r.word()
    charset = r.bytes(num_chars * 8)
    attributes = r.bytes(num_chars)
    char_colours = [a & 15 for a in attributes]
    materials = [a >> 4 for a in attributes]
    tiles = tile_colours = None
    if flags & TILE_SYS:
        if flags & CHAR_EX:
            sys.exit('ctm: expanded characters (CharEx) are not supported')
        tiles = r.words(num_tiles * tile_w * tile_h)
        if method == PER_TILE:
            tile_colours = list(r.bytes(num_tiles))
    cells = r.words(map_w * map_h)
    return method, charset, char_colours, materials, tiles, tile_colours, tile_w, tile_h, map_w, map_h, cells


def read_v7(r):
    r.bytes(5)  # background colours, char colour
    method, mode, flags = r.byte(), r.byte(), r.byte()
    if mode > 2:
        sys.exit('ctm: bitmap modes are not supported')
    return read_blocks(r, method, flags, per_char_block=False)


def read_v9(r):
    mode, method, flags = r.byte(), r.byte(), r.byte()
    if mode > 2:
        sys.exit('ctm: bitmap modes are not supported')
    r.bytes(4 + 1 + 4 + 3)  # flexigrid size, ?, background colours, char colours
    return read_blocks(r, method, flags, per_char_block=True)


# Version 7 has char attributes (colour in the low nibble) in block 1,
# version 9 materials in block 1 and per char colours in block 2
def read_blocks(r, method, flags, per_char_block):
    r.marker()
    num_chars = r.word() + 1
    charset = r.bytes(num_chars * 8)
    r.marker()
    attributes = r.bytes(num_chars)
    char_colours = [a & 15 for a in attributes]
    materials = [a >> 4 for a in attributes]
    if per_char_block:
        materials = list(attributes)
        char_colours = [0] * num_chars
        if method == PER_CHAR:
            r.marker()
            char_colours = [c & 15 for c in r.bytes(num_chars)]
    tiles = tile_colours = None
    tile_w = tile_h = 1
    if flags & TILE_SYS:
        r.marker()
        num_tiles = r.word() + 1
        tile_w, tile_h = r.byte(), r.byte()
        tiles = r.words(num_tiles * tile_w * tile_h)
        if method == PER_TILE:
            r.marker()
            tile_colours = list(r.bytes(num_tiles))
        r.marker()
        r.bytes(num_tiles)  # tags
        r.marker()
        for _ in range(num_tiles):  # names, 0 terminated
            while r.byte():
                pass
    r.marker()
    map_w, map_h = r.word(), r.word()
    cells = r.words(map_w * map_h)
    return method, charset, char_colours, materials, tiles, tile_colours, tile_w, tile_h, map_w, map_h, cells


def import_(ctm_path, chars_path, colours_path, charset_path=None):
    r = Reader(open(ctm_path, 'rb').read())
    magic, version = r.bytes(3), r.byte()
    if magic != b'CTM' or version not in (5, 7, 9):
        sys.exit(f'ctm: {ctm_path} is not a CTM version 5, 7 or 9 file')
    (method, charset, char_colours, materials, tiles, tile_colours,
     tile_w, tile_h, map_w, map_h, cells) = {5: read_v5, 7: read_v7, 9: read_v9}[version](r)

    # The screen in characters, expanding tiles
    width, height = map_w * tile_w, map_h * tile_h
    if width < WIDTH or height < HEIGHT:
        sys.exit(f'ctm: map is {width}x{height} characters, needs at least {WIDTH}x{HEIGHT}')
    image = [charset[c * 8:c * 8 + 8] for c in range(len(charset) // 8)]

    # A character after 255 is a copy of the one below 256 with the same image and material
    def screen_code(ch, x, y):
        if ch < 256:
            return ch
        for c in range(min(256, len(image))):
            if image[c] == image[ch] and materials[c] == materials[ch]:
                return c
        sys.exit(f'ctm: character {ch} at {x},{y} is past 255 and no character below 256 '
                 f'has its image and material {materials[ch]}')

    chars, colours = bytearray(1000), bytearray(1000)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            cell = cells[(y // tile_h) * map_w + x // tile_w]
            if tiles is None:
                ch = cell
            else:
                ch = tiles[(cell * tile_h + y % tile_h) * tile_w + x % tile_w]
            if method == PER_TILE and tile_colours is not None:
                co = tile_colours[cell]
            else:
                co = char_colours[ch]
            chars[y * WIDTH + x], colours[y * WIDTH + x] = screen_code(ch, x, y), co & 15
    open(chars_path, 'wb').write(chars)
    open(colours_path, 'wb').write(colours)
    print(f'{chars_path}, {colours_path}: written')

    if charset_path:
        open(charset_path, 'wb').write(charset[:2048].ljust(2048, b'\0'))
        print(f'{charset_path}: written')


if __name__ == '__main__':
    if len(sys.argv) == 6 and sys.argv[1] == 'export':
        export(*sys.argv[2:])
    elif len(sys.argv) in (5, 6) and sys.argv[1] == 'import':
        import_(*sys.argv[2:])
    else:
        sys.exit(__doc__)
