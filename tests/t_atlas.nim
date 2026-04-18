import std/[options, os, tables, unittest]

import ellipse/atlas

proc rgba(width, height: int; color: array[4, uint8]): RgbaImage =
  result = RgbaImage(width: width, height: height, pixels: newSeq[uint8](width * height * 4))
  for i in countup(0, result.pixels.high, 4):
    result.pixels[i + 0] = color[0]
    result.pixels[i + 1] = color[1]
    result.pixels[i + 2] = color[2]
    result.pixels[i + 3] = color[3]

proc fixtureDir(name: string): string =
  getTempDir() / ("ellipse-atlas-" & name & "-" & $getCurrentProcessId())

suite "atlas":
  test "roundtrips TOML metadata":
    let dir = fixtureDir("toml")
    createDir(dir)
    defer: removeDir(dir)

    let tilePath = dir / "tiles.png.toml"
    writeTileAtlasMeta(tilePath, TileAtlasMeta(tiles: @[
      TileInfo(name: "grass.png", transparent: true, order: 3, x: 4, y: 5, w: 6, h: 7)
    ]))

    let tileMeta = readTileAtlasMeta(tilePath)
    check tileMeta.tiles.len == 1
    check tileMeta.tiles[0].name == "grass.png"
    check tileMeta.tiles[0].transparent
    check tileMeta.tiles[0].order == 3
    check tileMeta.tiles[0].x == 4
    check tileMeta.tiles[0].h == 7

    let spritePath = dir / "sprites.png.toml"
    writeSpriteAtlasMeta(spritePath, SpriteAtlasMeta(sprites: @[
      SpriteInfo(name: "hero.png", transparent: false, x: 1, y: 2, w: 3, h: 4)
    ]))

    let table = readSpriteInfoTable[EntitySpriteId](spritePath)
    let found = spriteMeta(EntitySpriteId("hero.png"), table)
    check found.isSome
    check found.get.w == 3

  test "converts pixel regions to normalized rendering regions":
    let sprite = SpriteInfo(name: "hero.png", x: 16, y: 8, w: 32, h: 16)
    let region = sprite.toSpriteTextureRegion(128, 64)
    check region.u0 == 0.125'f32
    check region.v0 == 0.125'f32
    check region.u1 == 0.375'f32
    check region.v1 == 0.375'f32

    let uvs = sprite.toQuadUvs(128, 64)
    check uvs.u0 == 0.125'f32
    check uvs.v0 == 0.125'f32
    check uvs.u1 == 0.375'f32
    check uvs.v1 == 0.375'f32

  test "detects alpha transparency":
    check not rgba(2, 2, [uint8(1), 2, 3, 255]).isTransparent()
    check rgba(2, 2, [uint8(1), 2, 3, 128]).isTransparent()

  test "generates tile atlas with TOML order and coordinates":
    let dir = fixtureDir("tiles")
    let input = dir / "input"
    createDir(dir)
    createDir(input)
    defer: removeDir(dir)

    savePngRgba(input / "a.png", rgba(2, 1, [uint8(255), 0, 0, 255]))
    savePngRgba(input / "b.png", rgba(2, 2, [uint8(0), 255, 0, 128]))

    let outPath = dir / "tiles.png"
    writeTileAtlasMeta(atlasMetaPath(outPath), TileAtlasMeta(tiles: @[
      TileInfo(name: "b.png", order: 0),
      TileInfo(name: "a.png", order: 1)
    ]))

    generateTileAtlas(input, outPath, atlasWidth = 4, atlasHeight = 4)
    let meta = readTileAtlasMeta(atlasMetaPath(outPath))
    check meta.tiles.len == 2
    check meta.tiles[0].name == "b.png"
    check meta.tiles[0].x == 0
    check meta.tiles[0].y == 0
    check meta.tiles[0].transparent
    check meta.tiles[1].name == "a.png"
    check meta.tiles[1].x == 2
    check meta.tiles[1].y == 0
    check fileExists(outPath)

  test "sorts sprites by area and reports atlas overflow":
    let dir = fixtureDir("sprites")
    let input = dir / "input"
    createDir(dir)
    createDir(input)
    defer: removeDir(dir)

    savePngRgba(input / "small.png", rgba(1, 1, [uint8(0), 0, 255, 255]))
    savePngRgba(input / "big.png", rgba(2, 2, [uint8(255), 255, 0, 255]))

    let outPath = dir / "sprites.png"
    generateSpriteAtlas(input, outPath, atlasWidth = 4, atlasHeight = 4)
    let meta = readSpriteAtlasMeta(atlasMetaPath(outPath))
    check meta.sprites.len == 2
    check meta.sprites[0].name == "big.png"
    check meta.sprites[1].name == "small.png"

    savePngRgba(input / "too-wide.png", rgba(5, 1, [uint8(255), 255, 255, 255]))
    expect AtlasError:
      generateSpriteAtlas(input, dir / "overflow.png", atlasWidth = 4, atlasHeight = 4)
