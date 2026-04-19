import std/[algorithm, hashes, options, os, strutils, tables]

import toml_serialization

import ./platform/[SDL3, SDL3ext]
import ./rendering/[artist2D, artist3D]

type
  AtlasError* = object of CatchableError

  TileInfo* = object
    name*: string
    transparent*: bool
    order*: int
    x*, y*: int
    w*, h*: int

  SpriteInfo* = object
    name*: string
    transparent*: bool
    x*, y*: int
    w*, h*: int

  TileAtlasMeta* = object
    tiles*: seq[TileInfo]

  SpriteAtlasMeta* = object
    sprites*: seq[SpriteInfo]

  RgbaImage* = object
    width*, height*: int
    pixels*: seq[uint8]

  EntitySpriteId* = distinct string
  DecorationSpriteId* = distinct string
  ItemSpriteId* = distinct string
  SpriteId* = EntitySpriteId | DecorationSpriteId | ItemSpriteId

proc hash*(id: EntitySpriteId): Hash {.borrow.}
proc `==`*(a, b: EntitySpriteId): bool {.borrow.}

proc hash*(id: DecorationSpriteId): Hash {.borrow.}
proc `==`*(a, b: DecorationSpriteId): bool {.borrow.}

proc hash*(id: ItemSpriteId): Hash {.borrow.}
proc `==`*(a, b: ItemSpriteId): bool {.borrow.}

proc `$`*(id: EntitySpriteId): string {.borrow.}
proc `$`*(id: DecorationSpriteId): string {.borrow.}
proc `$`*(id: ItemSpriteId): string {.borrow.}

proc atlasMetaPath*(outPath: string): string =
  outPath & ".toml"

proc readTileAtlasMeta*(path: string): TileAtlasMeta =
  if not fileExists(path):
    return TileAtlasMeta()
  Toml.decode(readFile(path), TileAtlasMeta)

proc readSpriteAtlasMeta*(path: string): SpriteAtlasMeta =
  if not fileExists(path):
    return SpriteAtlasMeta()
  Toml.decode(readFile(path), SpriteAtlasMeta)

proc writeTileAtlasMeta*(path: string; meta: TileAtlasMeta) =
  writeFile(path, Toml.encode(meta))

proc writeSpriteAtlasMeta*(path: string; meta: SpriteAtlasMeta) =
  writeFile(path, Toml.encode(meta))

proc isTransparent*(image: RgbaImage): bool =
  if image.width <= 0 or image.height <= 0:
    return false
  for i in countup(3, image.pixels.high, 4):
    if image.pixels[i] < 255:
      return true
  false

proc rgbaPixels(surface: ptr Surface): seq[uint8] =
  let width = int(surface.w)
  let height = int(surface.h)
  if width <= 0 or height <= 0:
    return @[]

  SDL3ext.lockSurface(surface)
  try:
    if surface.pixels.isNil:
      return @[]
    result = newSeq[uint8](width * height * 4)
    let srcPitch = int(surface.pitch)
    let srcBase = cast[ptr UncheckedArray[uint8]](surface.pixels)
    for y in 0 ..< height:
      let srcRow = cast[ptr UncheckedArray[uint8]](cast[pointer](cast[uint](srcBase) + uint(y * srcPitch)))
      for x in 0 ..< width:
        let srcOffset = x * 4
        let dstOffset = (y * width + x) * 4
        when cpuEndian == littleEndian:
          result[dstOffset] = srcRow[srcOffset + 3]
          result[dstOffset + 1] = srcRow[srcOffset + 2]
          result[dstOffset + 2] = srcRow[srcOffset + 1]
          result[dstOffset + 3] = srcRow[srcOffset]
        else:
          result[dstOffset] = srcRow[srcOffset]
          result[dstOffset + 1] = srcRow[srcOffset + 1]
          result[dstOffset + 2] = srcRow[srcOffset + 2]
          result[dstOffset + 3] = srcRow[srcOffset + 3]
  finally:
    SDL3ext.unlockSurface(surface)

proc loadPngRgba*(path: string): RgbaImage =
  var loaded = SDL3ext.loadPng(path)
  var converted = SDL3ext.convertSurface(loaded, PIXELFORMAT_RGBA8888)
  result = RgbaImage(
    width: int(raw(converted).w),
    height: int(raw(converted).h),
    pixels: rgbaPixels(raw(converted))
  )
  if result.width <= 0 or result.height <= 0 or result.pixels.len != result.width * result.height * 4:
    raise newException(AtlasError, "invalid PNG surface for '" & path & "'")

proc savePngRgba*(path: string; image: RgbaImage) =
  if image.width <= 0 or image.height <= 0:
    raise newException(AtlasError, "PNG dimensions must be positive for '" & path & "'")
  if image.pixels.len != image.width * image.height * 4:
    raise newException(AtlasError, "PNG pixels must be tightly packed RGBA8 for '" & path & "'")

  var surface = SDL3ext.createSurface(image.width, image.height, PIXELFORMAT_RGBA8888)
  SDL3ext.lockSurface(surface)
  try:
    let dstPitch = int(raw(surface).pitch)
    let dstBase = cast[ptr UncheckedArray[uint8]](raw(surface).pixels)
    for y in 0 ..< image.height:
      let dstRow = cast[ptr UncheckedArray[uint8]](cast[pointer](cast[uint](dstBase) + uint(y * dstPitch)))
      for x in 0 ..< image.width:
        let srcOffset = (y * image.width + x) * 4
        let dstOffset = x * 4
        when cpuEndian == littleEndian:
          dstRow[dstOffset] = image.pixels[srcOffset + 3]
          dstRow[dstOffset + 1] = image.pixels[srcOffset + 2]
          dstRow[dstOffset + 2] = image.pixels[srcOffset + 1]
          dstRow[dstOffset + 3] = image.pixels[srcOffset]
        else:
          dstRow[dstOffset] = image.pixels[srcOffset]
          dstRow[dstOffset + 1] = image.pixels[srcOffset + 1]
          dstRow[dstOffset + 2] = image.pixels[srcOffset + 2]
          dstRow[dstOffset + 3] = image.pixels[srcOffset + 3]
  finally:
    SDL3ext.unlockSurface(surface)
  SDL3ext.savePng(surface, path)

proc toSpriteTextureRegion*(info: SpriteInfo; atlasWidth, atlasHeight: int): SpriteTextureRegion =
  if atlasWidth <= 0 or atlasHeight <= 0:
    raise newException(AtlasError, "atlas dimensions must be positive")
  spriteTextureRegion(
    cfloat(info.x) / cfloat(atlasWidth),
    cfloat(info.y) / cfloat(atlasHeight),
    cfloat(info.x + info.w) / cfloat(atlasWidth),
    cfloat(info.y + info.h) / cfloat(atlasHeight)
  )

proc toSpriteTextureRegion*(info: TileInfo; atlasWidth, atlasHeight: int): SpriteTextureRegion =
  SpriteInfo(x: info.x, y: info.y, w: info.w, h: info.h).toSpriteTextureRegion(atlasWidth, atlasHeight)

proc toQuadUvs*(info: SpriteInfo; atlasWidth, atlasHeight: int): QuadUvs =
  if atlasWidth <= 0 or atlasHeight <= 0:
    raise newException(AtlasError, "atlas dimensions must be positive")
  QuadUvs(
    u0: cfloat(info.x) / cfloat(atlasWidth),
    v0: cfloat(info.y) / cfloat(atlasHeight),
    u1: cfloat(info.x + info.w) / cfloat(atlasWidth),
    v1: cfloat(info.y + info.h) / cfloat(atlasHeight)
  )

proc toQuadUvs*(info: TileInfo; atlasWidth, atlasHeight: int): QuadUvs =
  SpriteInfo(x: info.x, y: info.y, w: info.w, h: info.h).toQuadUvs(atlasWidth, atlasHeight)

proc tileOrder(name: string; prior: Table[string, int]): int =
  prior.getOrDefault(name, 0)

proc tileCmp(a, b: TileInfo): int =
  if a.order == b.order:
    cmp(a.name, b.name)
  else:
    cmp(a.order, b.order)

proc spriteCmp(a, b: RgbaImage; aName, bName: string): int =
  let
    aArea = a.width * a.height
    bArea = b.width * b.height
  if aArea == bArea:
    cmp(aName, bName)
  else:
    cmp(bArea, aArea)

proc pngPaths(path: string): seq[string] =
  for kind, filePath in walkDir(path):
    if kind == pcFile and filePath.endsWith(".png"):
      result.add(filePath)
  result.sort(system.cmp[string])

proc blit(dst: var RgbaImage; src: RgbaImage; dstX, dstY: int) =
  if dstX < 0 or dstY < 0 or dstX + src.width > dst.width or dstY + src.height > dst.height:
    raise newException(AtlasError, "source image does not fit in atlas")
  for y in 0 ..< src.height:
    let
      srcOffset = y * src.width * 4
      dstOffset = ((dstY + y) * dst.width + dstX) * 4
      rowBytes = src.width * 4
    copyMem(addr dst.pixels[dstOffset], unsafeAddr src.pixels[srcOffset], rowBytes)

proc initAtlas(width, height: int): RgbaImage =
  if width <= 0 or height <= 0:
    raise newException(AtlasError, "atlas dimensions must be positive")
  RgbaImage(width: width, height: height, pixels: newSeq[uint8](width * height * 4))

proc nextPlacement(
  cursorX, cursorY, rowHeight: var int;
  atlasWidth, atlasHeight: int;
  width, height: int;
  name: string
): tuple[x, y: int] =
  if width <= 0 or height <= 0:
    raise newException(AtlasError, "invalid image dimensions for '" & name & "'")
  if width > atlasWidth or height > atlasHeight:
    raise newException(AtlasError, "image '" & name & "' is larger than the atlas")
  if cursorX > 0 and cursorX + width > atlasWidth:
    cursorX = 0
    cursorY += rowHeight
    rowHeight = 0
  if cursorY + height > atlasHeight:
    raise newException(AtlasError, "atlas overflow while placing '" & name & "'")

  result = (x: cursorX, y: cursorY)
  cursorX += width
  rowHeight = max(rowHeight, height)

proc priorTileOrders(metaPath: string): Table[string, int] =
  result = initTable[string, int]()
  for tile in readTileAtlasMeta(metaPath).tiles:
    result[tile.name] = tile.order

proc generateTileAtlas*(
  path, outPath: string;
  atlasWidth = 512;
  atlasHeight = 512
) =
  var atlas = initAtlas(atlasWidth, atlasHeight)
  let prior = priorTileOrders(atlasMetaPath(outPath))
  var tiles: seq[TileInfo]

  for filePath in pngPaths(path):
    let
      image = loadPngRgba(filePath)
      name = filePath.extractFilename
    tiles.add(TileInfo(
      name: name,
      transparent: image.isTransparent(),
      order: tileOrder(name, prior),
      w: image.width,
      h: image.height
    ))

  tiles.sort(tileCmp)

  var cursorX, cursorY, rowHeight: int
  for tile in tiles.mitems:
    let image = loadPngRgba(path / tile.name)
    let placement = nextPlacement(cursorX, cursorY, rowHeight, atlasWidth, atlasHeight, image.width, image.height, tile.name)
    tile.x = placement.x
    tile.y = placement.y
    atlas.blit(image, tile.x, tile.y)

  savePngRgba(outPath, atlas)
  writeTileAtlasMeta(atlasMetaPath(outPath), TileAtlasMeta(tiles: tiles))

proc generateSpriteAtlas*(
  path, outPath: string;
  atlasWidth = 1280;
  atlasHeight = 1280
) =
  type PendingSprite = object
    image: RgbaImage
    name: string
    transparent: bool

  var atlas = initAtlas(atlasWidth, atlasHeight)
  var pending: seq[PendingSprite]
  for filePath in pngPaths(path):
    let image = loadPngRgba(filePath)
    pending.add(PendingSprite(
      image: image,
      name: filePath.extractFilename,
      transparent: image.isTransparent()
    ))

  pending.sort(proc(a, b: PendingSprite): int =
    spriteCmp(a.image, b.image, a.name, b.name)
  )

  var cursorX, cursorY, rowHeight: int
  var sprites: seq[SpriteInfo]
  for sprite in pending:
    let placement = nextPlacement(cursorX, cursorY, rowHeight, atlasWidth, atlasHeight, sprite.image.width, sprite.image.height, sprite.name)
    atlas.blit(sprite.image, placement.x, placement.y)
    sprites.add(SpriteInfo(
      name: sprite.name,
      transparent: sprite.transparent,
      x: placement.x,
      y: placement.y,
      w: sprite.image.width,
      h: sprite.image.height
    ))

  savePngRgba(outPath, atlas)
  writeSpriteAtlasMeta(atlasMetaPath(outPath), SpriteAtlasMeta(sprites: sprites))

proc tileInformation*(path: string): seq[TileInfo] =
  result = readTileAtlasMeta(path).tiles
  result.sort(tileCmp)

proc meta*(id: int; path: string): Option[TileInfo] =
  let tiles = readTileAtlasMeta(path).tiles
  if id < 0 or id >= tiles.len:
    return
  some(tiles[id])

proc readSpriteInfoTable*[T: SpriteId](path: string): Table[T, SpriteInfo] =
  result = initTable[T, SpriteInfo]()
  for it in readSpriteAtlasMeta(path).sprites:
    result[T(it.name)] = it

proc spriteMeta*[T: SpriteId](id: T; table: Table[T, SpriteInfo]): Option[SpriteInfo] =
  if not table.hasKey(id):
    return
  some(table[id])

let decorationMetaTable = readSpriteInfoTable[DecorationSpriteId]("res/decorations.png.toml")
let entityMetaTable = readSpriteInfoTable[EntitySpriteId]("res/entities.png.toml")
let itemMetaTable = readSpriteInfoTable[ItemSpriteId]("res/items.png.toml")

proc getDecorationMetaTable*(): auto =
  decorationMetaTable

proc getEntityMetaTable*(): auto =
  entityMetaTable

proc getItemMetaTable*(): auto =
  itemMetaTable

proc spriteMeta*[T: SpriteId](id: T): Option[SpriteInfo] =
  when T is DecorationSpriteId:
    id.spriteMeta(getDecorationMetaTable())
  elif T is ItemSpriteId:
    id.spriteMeta(getItemMetaTable())
  else:
    id.spriteMeta(getEntityMetaTable())
