#!/usr/bin/env python3
"""Converts the cave (map, tiles, characters) to a CharPad project and a picture.

    tools/playfield.py export [playfield.ctm]   src/ -> CharPad project
    tools/playfield.py import [playfield.ctm]   CharPad project -> src/
    tools/playfield.py png [cave.png]           src/ -> picture of the whole cave

The cave is 128 x 64 tiles (src/map.bin, a byte per tile), each tile 8 x 8
characters (src/tile_chars.bin) with a colour per character (src/tile_colours.bin);
the characters are src/charset.bin, in multicolour mode.

CharPad colours a character, not a tile cell, so export gives each character
used in more than one colour a copy per extra colour after character 255, and
writes playfield_copies.txt next to the project: which character each copy
stands for. Import reads it back. To use a character in a new colour, copy it
to the end of the set and colour the copy: a copy that isn't in
playfield_copies.txt stands for the character below 256 with the same image
and material. Don't delete or move characters, and don't let CharPad remove
unused ones, or the copies point to the wrong characters.

Characters $00-$7f are drawn by the game at run time (the barriers), so the
project shows them as they start out and import ignores changes to them.
Characters $80-$bf are the font, also used by the status line and the puzzles.

Writes CTM version 7 as CharPad Free 2.x saves it, multicolour, tiles of 8 x 8,
colour per character. Import reads versions 5, 7 and 9 (CharPad Pro).
Formats as read by github.com/c64lib/gradle-retro-assembler-plugin.
"""
import os
import struct
import sys
import zlib

MAP_W, MAP_H, TILE = 128, 64, 8
TILES = 128

# The game's VIC colours: background $d021, $d022, $d023
BACKGROUND, MULTICOLOUR1, MULTICOLOUR2 = 0, 15, 7

TILE_SYS = 0x01
TEXT_MULTICOLOUR = 1
GLOBAL, PER_TILE, PER_CHAR = 0, 1, 2

# VICE's default palette
PALETTE = [0x000000, 0xffffff, 0x68372b, 0x70a4b2, 0x6f3d86, 0x588d43, 0x352879, 0xb8c76f,
           0x6f4f25, 0x433900, 0x9a6759, 0x444444, 0x6c6c6c, 0x9ad284, 0x6c5eb5, 0x959595]

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src')


def src(name):
    return os.path.join(SRC, name)


def tile_offset(t, x, y):
    """Where character (x, y) of tile t is in tile_chars.bin and tile_colours.bin."""
    return ((t >> 5) * TILE + y) * 256 + (t & 31) * TILE + x


def run_time_charset(charset):
    """Characters $00-$7f as engine_init_barrier sets them up."""
    charset = bytearray(charset)
    charset[0x000:0x100] = bytes(0x100)
    charset[0x100:0x300] = b'\xff' * 0x200
    charset[0x300:0x400] = bytes(0x100)
    return bytes(charset)


def load():
    level = open(src('map.bin'), 'rb').read()
    chars = open(src('tile_chars.bin'), 'rb').read()
    colours = open(src('tile_colours.bin'), 'rb').read()
    charset = open(src('charset.bin'), 'rb').read()
    return level, chars, colours, charset


def copies_path(ctm_path):
    return os.path.join(os.path.dirname(ctm_path) or '.', 'playfield_copies.txt')


def export(ctm_path):
    level, chars, colours, charset = load()
    charset = run_time_charset(charset)
    cells = [(chars[tile_offset(t, x, y)], colours[tile_offset(t, x, y)] & 15)
             for t in range(TILES) for y in range(TILE) for x in range(TILE)]

    # Each character keeps its most used colour, the others go to copies
    uses = {}
    for cell in cells:
        uses[cell] = uses.get(cell, 0) + 1
    char_colour = [0] * 256
    for ch in range(256):
        found = [co for (c, co) in uses if c == ch]
        if found:
            char_colour[ch] = max(found, key=lambda co: (uses[(ch, co)], -co))
    copies = sorted(cell for cell in uses if char_colour[cell[0]] != cell[1])
    copy_of = {cell: 256 + i for i, cell in enumerate(copies)}

    blocks = []

    def block(data):
        blocks.append(bytes([0xda, 0xb0 | len(blocks)]) + data)

    image = [charset[c * 8:c * 8 + 8] for c in range(256)]
    block(struct.pack('<H', 256 + len(copies) - 1) + charset + b''.join(image[ch] for ch, co in copies))
    block(bytes(char_colour) + bytes(co for ch, co in copies))
    block(struct.pack('<HBB', TILES - 1, TILE, TILE) +
          b''.join(struct.pack('<H', copy_of.get(cell, cell[0])) for cell in cells))
    block(bytes(TILES))  # tags
    block(b''.join(f'tile {t:02x}'.encode() + b'\0' for t in range(TILES)))  # names
    block(struct.pack('<HH', MAP_W, MAP_H) + b''.join(struct.pack('<H', b & 0x7f) for b in level))

    out = bytearray(b'CTM\x07')
    out += bytes([BACKGROUND, MULTICOLOUR1, MULTICOLOUR2, 0, 1, PER_CHAR, TEXT_MULTICOLOUR, TILE_SYS])
    out += b''.join(blocks)
    open(ctm_path, 'wb').write(out)
    with open(copies_path(ctm_path), 'w') as f:
        f.write(f'# {os.path.basename(ctm_path)}: the characters after 255 and the character each stands for\n')
        for i, (ch, co) in enumerate(copies):
            f.write(f'{256 + i} {ch}\n')
    print(f'{ctm_path}: 256 chars + {len(copies)} copies for extra colours, '
          f'{TILES} tiles, map {MAP_W}x{MAP_H}')


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
    tiles = None
    if flags & TILE_SYS:
        tiles = r.words(num_tiles * tile_w * tile_h)
        if method == PER_TILE:
            r.bytes(num_tiles)
    cells = r.words(map_w * map_h)
    return (method, charset, [a & 15 for a in attributes], [a >> 4 for a in attributes],
            tiles, tile_w, tile_h, map_w, map_h, cells)


def read_v7(r):
    r.bytes(5)  # background colours, char colour
    method, mode, flags = r.byte(), r.byte(), r.byte()
    return read_blocks(r, method, flags, per_char_block=False)


def read_v9(r):
    mode, method, flags = r.byte(), r.byte(), r.byte()
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
    tiles = None
    tile_w = tile_h = 1
    if flags & TILE_SYS:
        r.marker()
        num_tiles = r.word() + 1
        tile_w, tile_h = r.byte(), r.byte()
        tiles = r.words(num_tiles * tile_w * tile_h)
        if method == PER_TILE:
            r.marker()
            r.bytes(num_tiles)
        r.marker()
        r.bytes(num_tiles)  # tags
        r.marker()
        for _ in range(num_tiles):  # names, 0 terminated
            while r.byte():
                pass
    r.marker()
    map_w, map_h = r.word(), r.word()
    cells = r.words(map_w * map_h)
    return method, charset, char_colours, materials, tiles, tile_w, tile_h, map_w, map_h, cells


def import_(ctm_path):
    r = Reader(open(ctm_path, 'rb').read())
    magic, version = r.bytes(3), r.byte()
    if magic != b'CTM' or version not in (5, 7, 9):
        sys.exit(f'ctm: {ctm_path} is not a CTM version 5, 7 or 9 file')
    (method, charset, char_colours, materials, tiles,
     tile_w, tile_h, map_w, map_h, cells) = {5: read_v5, 7: read_v7, 9: read_v9}[version](r)
    if method != PER_CHAR:
        sys.exit('ctm: the colouring has to be per character')
    if tiles is None or (tile_w, tile_h) != (TILE, TILE):
        sys.exit(f'ctm: needs tiles of {TILE} x {TILE} characters')
    if len(tiles) != TILES * TILE * TILE:
        sys.exit(f'ctm: needs {TILES} tiles, has {len(tiles) // (TILE * TILE)}')
    if (map_w, map_h) != (MAP_W, MAP_H):
        sys.exit(f'ctm: the map has to be {MAP_W} x {MAP_H} tiles, is {map_w} x {map_h}')
    if any(c >= TILES for c in cells):
        sys.exit(f'ctm: the map uses a tile past {TILES - 1}')

    old_level, old_chars, old_colours, old_charset = load()
    image = [charset[c * 8:c * 8 + 8] for c in range(len(charset) // 8)]

    known = {}
    if os.path.exists(copies_path(ctm_path)):
        for line in open(copies_path(ctm_path)):
            if line.strip() and not line.startswith('#'):
                copy, ch = map(int, line.split())
                known[copy] = ch

    # A character after 255 stands for the one below 256 in playfield_copies.txt,
    # or else the one with the same image and material
    def character(ch, t, x, y):
        if ch < 256:
            return ch
        if ch in known and ch < len(image) and image[ch] == image[known[ch]]:
            return known[ch]
        same = [c for c in range(256) if image[c] == image[ch] and materials[c] == materials[ch]]
        if len(same) != 1:
            sys.exit(f'ctm: character {ch} in tile {t} at {x},{y}: '
                     f'{len(same)} characters below 256 have its image and material {materials[ch]}')
        return same[0]

    chars, colours = bytearray(old_chars), bytearray(old_colours)
    for t in range(TILES):
        for y in range(TILE):
            for x in range(TILE):
                ch = tiles[(t * TILE + y) * TILE + x]
                at = tile_offset(t, x, y)
                chars[at] = character(ch, t, x, y)
                # the high nibble isn't used: keep what was there
                colours[at] = old_colours[at] & 0xf0 | char_colours[ch] & 15

    # Bit 7 of a map byte isn't used either: kept where the tile stays the same
    level = bytearray(old_level)
    for i, tile in enumerate(cells):
        if old_level[i] & 0x7f != tile:
            level[i] = tile

    new_charset = bytearray(old_charset)
    new_charset[0x400:0x800] = charset[0x400:0x800].ljust(0x400, b'\0')
    if charset[:0x400] != run_time_charset(old_charset)[:0x400]:
        print('ctm: characters $00-$7f changed: ignored, the game draws them')

    for name, data in (('map.bin', level), ('tile_chars.bin', chars),
                       ('tile_colours.bin', colours), ('charset.bin', new_charset)):
        open(src(name), 'wb').write(data)
        print(f'src/{name}: written')


def png(png_path):
    level, chars, colours, charset = load()
    charset = run_time_charset(charset)
    rgb = [bytes([p >> 16, p >> 8 & 255, p & 255]) for p in PALETTE]

    # Each tile as 64 rows of 64 pixels
    tile_rows = []
    for t in range(TILES):
        rows = []
        for y in range(TILE):
            for line in range(8):
                row = bytearray()
                for x in range(TILE):
                    at = tile_offset(t, x, y)
                    bits, colour = charset[chars[at] * 8 + line], colours[at] & 15
                    if colour < 8:
                        for b in range(7, -1, -1):
                            row += rgb[colour] if bits >> b & 1 else rgb[BACKGROUND]
                    else:
                        pair = [BACKGROUND, MULTICOLOUR1, MULTICOLOUR2, colour & 7]
                        for b in range(6, -1, -2):
                            row += rgb[pair[bits >> b & 3]] * 2
                rows.append(bytes(row))
        tile_rows.append(rows)

    raw = bytearray()
    for ty in range(MAP_H):
        for line in range(TILE * 8):
            raw.append(0)
            for tx in range(MAP_W):
                raw += tile_rows[level[ty * MAP_W + tx] & 0x7f][line]
    width, height = MAP_W * TILE * 8, MAP_H * TILE * 8

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    open(png_path, 'wb').write(b'\x89PNG\r\n\x1a\n' +
                               chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
                               chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    print(f'{png_path}: {width}x{height}')


if __name__ == '__main__':
    command, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else (None, [])
    if command == 'export' and len(args) <= 1:
        export(args[0] if args else 'playfield.ctm')
    elif command == 'import' and len(args) <= 1:
        import_(args[0] if args else 'playfield.ctm')
    elif command == 'png' and len(args) <= 1:
        png(args[0] if args else 'cave.png')
    else:
        sys.exit(__doc__)
