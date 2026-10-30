# CTM V6 test files

Made by us from the V7 files of the same name in `tests/files/ctm7/`: the 12 byte
V7 header becomes the 10 byte V6 header (no $d024, and the display mode becomes
the multicolour flag, bit 0, with the tile system in bit 1); the blocks are the
same. `tests/tctm.nim` checks that they read back as the V7 projects, apart from
$d024 and the version. See `tests/files/ctm7/README.md` for what they hold.

Not checked in CharPad itself.
