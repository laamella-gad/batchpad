// Run from the repository root with Tiled 1.12.2 --evaluate.
const dir = "tests/files/tiled/tiled-1.12.2/";
const format = tiled.mapFormat("tmx");
const map = format.read(dir + "aaaaaa.tmx");
for (const [encoding, name] of [[TileMap.Base64Zlib, "tiled-zlib.tmx"],
                                [TileMap.Base64Gzip, "tiled-gzip.tmx"]]) {
    map.layerDataFormat = encoding;
    const error = format.write(map, dir + name);
    if (error) throw new Error(error);
}