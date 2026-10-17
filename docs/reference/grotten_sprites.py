#!/usr/bin/env python3
"""Converts the sprites to and from a SpritePad project.

    tools/sprites.py export [sprites.spd]   src/sprites.bin -> SpritePad project
    tools/sprites.py import [sprites.spd]   SpritePad project -> src/sprites.bin

src/sprites.bin is the 16 sprites at $0c00-$0fff, pointers $30-$3f, 64 bytes
each. The project is in SpritePad 1.8's format: background, sprite
multicolour 1 and 2, then the sprites, 64 bytes each, the 64th holding the
colour (bits 0-3), overlay (bit 4) and multicolour (bit 7).

The game sets the colours and modes in its code (engine_init_sprites), not in
the sprite data, so export fills them in from the table below for a correct
preview, and import keeps the game's own 64th bytes: changing a colour or mode
in SpritePad does nothing in the game. Only the pixels are imported. Keep the
16 sprites in their places.
"""
import os
import sys

COUNT = 16
SIZE = 64

# $d021, $d025, $d026 in the game
BACKGROUND, MULTICOLOUR1, MULTICOLOUR2 = 0, 7, 6

MULTICOLOUR = 0x80

# Colour and mode of each sprite, from pointer $30 on
ATTRIBUTES = [
    0x0d | MULTICOLOUR,  # $30 ship, sprite 4 (alternates with $34)
    0x0d | MULTICOLOUR,  # $31 ship, sprite 5
    0x0d | MULTICOLOUR,  # $32 ship, sprite 2
    0x0d | MULTICOLOUR,  # $33 ship, sprite 3
    0x0d | MULTICOLOUR,  # $34 ship, sprite 4's other frame
    0x06,  # $35 status line, left half (rows 6-12 are the scrolled text)
    0x06,  # $36 status line, right half
    0x01,  # $37 probe arm left/right
    0x01,  # $38 its other frame
    0x01,  # $39 probe arm up/down
    0x01,  # $3a its other frame
    0x01,  # $3b not used (another probe arm frame)
    0x09,  # $3c guardian, a big screw: 4 frames of it turning, expanded
    0x09,  # $3d
    0x09,  # $3e
    0x09,  # $3f
]

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'sprites.bin')


def load():
    data = open(SRC, 'rb').read()
    if len(data) != COUNT * SIZE:
        sys.exit(f'sprites: src/sprites.bin is {len(data)} bytes, not {COUNT * SIZE}')
    return data


def export(spd_path):
    data = load()
    out = bytearray([BACKGROUND, MULTICOLOUR1, MULTICOLOUR2])
    for n in range(COUNT):
        out += data[n * SIZE:n * SIZE + SIZE - 1] + bytes([ATTRIBUTES[n]])
    open(spd_path, 'wb').write(out)
    print(f'{spd_path}: {COUNT} sprites')


def import_(spd_path):
    project = open(spd_path, 'rb').read()
    if project[:3] == b'SPD':
        sys.exit(f'sprites: {spd_path} is in a newer SpritePad format: save it as SpritePad 1.8')
    count, rest = divmod(len(project) - 3, SIZE)
    if rest or count != COUNT:
        sys.exit(f'sprites: {spd_path} needs {COUNT} sprites in SpritePad 1.8 format')

    old = load()
    data = bytearray()
    for n in range(COUNT):
        sprite = project[3 + n * SIZE:3 + n * SIZE + SIZE]
        if sprite[SIZE - 1] != ATTRIBUTES[n]:
            print(f'sprites: colour or mode of ${0x30 + n:02x} changed: ignored, the game sets them')
        # the 64th byte isn't used by the game: keep what was there
        data += sprite[:SIZE - 1] + old[n * SIZE + SIZE - 1:n * SIZE + SIZE]
    if project[:3] != bytes([BACKGROUND, MULTICOLOUR1, MULTICOLOUR2]):
        print('sprites: background or multicolours changed: ignored, the game sets them')
    open(SRC, 'wb').write(data)
    print('src/sprites.bin: written')


if __name__ == '__main__':
    command, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else (None, [])
    if command == 'export' and len(args) <= 1:
        export(args[0] if args else 'sprites.spd')
    elif command == 'import' and len(args) <= 1:
        import_(args[0] if args else 'sprites.spd')
    else:
        sys.exit(__doc__)
