import std/[algorithm, math, os, strformat, strutils]

import zlib

import ./platform/SDL3gpuext
import ./rendering/[artist2D, artist3D]

type
  AsepriteError* = object of CatchableError

  AsepriteColorDepth* = enum
    acIndexed = 8
    acGrayscale = 16
    acRgba = 32

  AsepriteLayerType* = enum
    altNormal = 0
    altGroup = 1
    altTilemap = 2

  AsepriteCelType* = enum
    actRawImage = 0
    actLinked = 1
    actCompressedImage = 2
    actCompressedTilemap = 3

  AsepriteColor* = object
    r*, g*, b*, a*: uint8
    name*: string

  AsepritePalette* = object
    entries*: seq[AsepriteColor]

  AsepriteLayer* = object
    flags*: uint16
    layerType*: AsepriteLayerType
    childLevel*: uint16
    blendMode*: uint16
    opacity*: uint8
    name*: string
    tilesetIndex*: uint32
    uuid*: array[16, uint8]

  AsepriteCel* = object
    layerIndex*: uint16
    x*, y*: int16
    opacity*: uint8
    celType*: AsepriteCelType
    zIndex*: int16
    width*, height*: uint16
    linkedFrame*: uint16
    pixels*: seq[uint8]
    tiles*: seq[uint8]
    bitsPerTile*: uint16
    tileIdMask*, xFlipMask*, yFlipMask*, diagonalFlipMask*: uint32

  AsepriteTag* = object
    fromFrame*, toFrame*: uint16
    direction*: uint8
    repeat*: uint16
    color*: array[3, uint8]
    name*: string

  AsepriteSliceKey* = object
    frame*: uint32
    x*, y*: int32
    width*, height*: uint32
    centerX*, centerY*: int32
    centerWidth*, centerHeight*: uint32
    pivotX*, pivotY*: int32

  AsepriteSlice* = object
    flags*: uint32
    name*: string
    keys*: seq[AsepriteSliceKey]

  AsepriteTileset* = object
    id*, flags*, tileCount*: uint32
    tileWidth*, tileHeight*: uint16
    baseIndex*: int16
    name*: string
    externalFileId*, externalTilesetId*: uint32
    pixels*: seq[uint8]

  AsepriteUserData* = object
    hasText*, hasColor*, hasProperties*: bool
    text*: string
    color*: AsepriteColor

  AsepriteChunkSummary* = object
    frameIndex*: int
    chunkType*: uint16
    size*: uint32

  AsepriteFrame* = object
    durationMs*: uint16
    cels*: seq[AsepriteCel]
    userData*: seq[AsepriteUserData]

  AsepriteFile* = object
    path*: string
    width*, height*: uint16
    colorDepth*: AsepriteColorDepth
    flags*: uint32
    transparentIndex*: uint8
    colorCount*: uint16
    pixelWidth*, pixelHeight*: uint8
    gridX*, gridY*: int16
    gridWidth*, gridHeight*: uint16
    layers*: seq[AsepriteLayer]
    frames*: seq[AsepriteFrame]
    palette*: AsepritePalette
    tags*: seq[AsepriteTag]
    slices*: seq[AsepriteSlice]
    tilesets*: seq[AsepriteTileset]
    chunks*: seq[AsepriteChunkSummary]

  Reader = object
    data: seq[uint8]
    pos: int
    origin: string

const
  HeaderSize = 128
  FileMagic = 0xA5E0'u16
  FrameMagic = 0xF1FA'u16

proc fail(r: Reader; msg: string) {.noreturn.} =
  raise newException(AsepriteError, &"{r.origin}: {msg} at byte {r.pos}")

proc ensure(r: Reader; count: int) =
  if count < 0 or r.pos + count > r.data.len:
    r.fail(&"unexpected end of file while reading {count} bytes")

proc readU8(r: var Reader): uint8 =
  r.ensure(1)
  result = r.data[r.pos]
  inc r.pos

proc readU16(r: var Reader): uint16 =
  r.ensure(2)
  result = uint16(r.data[r.pos]) or (uint16(r.data[r.pos + 1]) shl 8)
  inc r.pos, 2

proc readI16(r: var Reader): int16 =
  cast[int16](r.readU16())

proc readU32(r: var Reader): uint32 =
  r.ensure(4)
  result =
    uint32(r.data[r.pos]) or
    (uint32(r.data[r.pos + 1]) shl 8) or
    (uint32(r.data[r.pos + 2]) shl 16) or
    (uint32(r.data[r.pos + 3]) shl 24)
  inc r.pos, 4

proc readI32(r: var Reader): int32 =
  cast[int32](r.readU32())

proc readU64(r: var Reader): uint64 =
  let lo = uint64(r.readU32())
  let hi = uint64(r.readU32())
  lo or (hi shl 32)

proc readBytes(r: var Reader; count: int): seq[uint8] =
  r.ensure(count)
  result = r.data[r.pos ..< r.pos + count]
  inc r.pos, count

proc skip(r: var Reader; count: int) =
  r.ensure(count)
  inc r.pos, count

proc readString(r: var Reader): string =
  let length = int(r.readU16())
  r.ensure(length)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = char(r.data[r.pos + i])
  inc r.pos, length

proc chunkReader(r: Reader; start, stop: int): Reader =
  if start < 0 or stop < start or stop > r.data.len:
    r.fail("invalid chunk bounds")
  Reader(data: r.data[start ..< stop], pos: 0, origin: r.origin)

proc toLayerType(value: uint16; r: Reader): AsepriteLayerType =
  case value
  of 0: altNormal
  of 1: altGroup
  of 2: altTilemap
  else:
    r.fail(&"unsupported layer type {value}")

proc toCelType(value: uint16; r: Reader): AsepriteCelType =
  case value
  of 0: actRawImage
  of 1: actLinked
  of 2: actCompressedImage
  of 3: actCompressedTilemap
  else:
    r.fail(&"unsupported cel type {value}")

proc bytesPerPixel(depth: AsepriteColorDepth): int =
  case depth
  of acIndexed: 1
  of acGrayscale: 2
  of acRgba: 4

proc uncompressZlib(source: seq[uint8]; expectedLen: int; origin: string): seq[uint8] =
  if expectedLen < 0:
    raise newException(AsepriteError, &"{origin}: invalid decompressed size {expectedLen}")
  result = newSeq[uint8](expectedLen)
  var destLen = culong(expectedLen)
  let sourcePtr = if source.len == 0: nil else: cast[ptr uint8](unsafeAddr source[0])
  let destPtr = if result.len == 0: nil else: cast[ptr uint8](addr result[0])
  let code = uncompress(destPtr, destLen, sourcePtr, culong(source.len))
  if code != Z_OK:
    raise newException(AsepriteError, &"{origin}: zlib decompression failed: {code}")
  if int(destLen) != expectedLen:
    raise newException(AsepriteError, &"{origin}: zlib output length {destLen} did not match expected {expectedLen}")

proc parseLayer(r: var Reader; sprite: var AsepriteFile) =
  var layer: AsepriteLayer
  layer.flags = r.readU16()
  layer.layerType = toLayerType(r.readU16(), r)
  layer.childLevel = r.readU16()
  discard r.readU16()
  discard r.readU16()
  layer.blendMode = r.readU16()
  layer.opacity = r.readU8()
  r.skip(3)
  layer.name = r.readString()
  if layer.layerType == altTilemap:
    layer.tilesetIndex = r.readU32()
  if (sprite.flags and 4'u32) != 0:
    for i in 0 ..< layer.uuid.len:
      layer.uuid[i] = r.readU8()
  sprite.layers.add layer

proc parseCel(r: var Reader; sprite: AsepriteFile; frame: var AsepriteFrame) =
  var cel: AsepriteCel
  cel.layerIndex = r.readU16()
  cel.x = r.readI16()
  cel.y = r.readI16()
  cel.opacity = r.readU8()
  cel.celType = toCelType(r.readU16(), r)
  cel.zIndex = r.readI16()
  r.skip(5)

  case cel.celType
  of actRawImage, actCompressedImage:
    cel.width = r.readU16()
    cel.height = r.readU16()
    let expected = int(cel.width) * int(cel.height) * bytesPerPixel(sprite.colorDepth)
    if cel.celType == actRawImage:
      cel.pixels = r.readBytes(expected)
    else:
      cel.pixels = uncompressZlib(r.readBytes(r.data.len - r.pos), expected, r.origin)
  of actLinked:
    cel.linkedFrame = r.readU16()
  of actCompressedTilemap:
    cel.width = r.readU16()
    cel.height = r.readU16()
    cel.bitsPerTile = r.readU16()
    cel.tileIdMask = r.readU32()
    cel.xFlipMask = r.readU32()
    cel.yFlipMask = r.readU32()
    cel.diagonalFlipMask = r.readU32()
    r.skip(10)
    if cel.bitsPerTile == 0 or (cel.bitsPerTile mod 8) != 0:
      r.fail(&"invalid tile bit depth {cel.bitsPerTile}")
    let expected = int(cel.width) * int(cel.height) * (int(cel.bitsPerTile) div 8)
    cel.tiles = uncompressZlib(r.readBytes(r.data.len - r.pos), expected, r.origin)
  frame.cels.add cel

proc parseOldPalette(r: var Reader; sprite: var AsepriteFile; scale63: bool) =
  if sprite.palette.entries.len < 256:
    sprite.palette.entries.setLen(256)
  var index = 0
  let packets = int(r.readU16())
  for _ in 0 ..< packets:
    index += int(r.readU8())
    var count = int(r.readU8())
    if count == 0:
      count = 256
    for _ in 0 ..< count:
      var color: AsepriteColor
      color.r = r.readU8()
      color.g = r.readU8()
      color.b = r.readU8()
      color.a = 255
      if scale63:
        color.r = uint8((uint16(color.r) * 255'u16) div 63'u16)
        color.g = uint8((uint16(color.g) * 255'u16) div 63'u16)
        color.b = uint8((uint16(color.b) * 255'u16) div 63'u16)
      if index >= sprite.palette.entries.len:
        sprite.palette.entries.setLen(index + 1)
      sprite.palette.entries[index] = color
      inc index

proc parsePalette(r: var Reader; sprite: var AsepriteFile) =
  let size = int(r.readU32())
  let first = int(r.readU32())
  let last = int(r.readU32())
  r.skip(8)
  if size < 0 or last < first:
    r.fail("invalid palette range")
  sprite.palette.entries.setLen(size)
  for index in first .. last:
    let flags = r.readU16()
    var color = AsepriteColor(r: r.readU8(), g: r.readU8(), b: r.readU8(), a: r.readU8())
    if (flags and 1'u16) != 0:
      color.name = r.readString()
    if index >= 0 and index < sprite.palette.entries.len:
      sprite.palette.entries[index] = color

proc skipPropertyValue(r: var Reader; propertyType: uint16) {.gcsafe.}

proc skipPropertyMap(r: var Reader) {.gcsafe.} =
  discard r.readU32()
  let count = r.readU32()
  for _ in 0'u32 ..< count:
    discard r.readString()
    let propertyType = r.readU16()
    r.skipPropertyValue(propertyType)

proc skipPropertyValue(r: var Reader; propertyType: uint16) {.gcsafe.} =
  case propertyType
  of 0x0001, 0x0002, 0x0003:
    r.skip(1)
  of 0x0004, 0x0005:
    r.skip(2)
  of 0x0006, 0x0007, 0x000A, 0x000B:
    r.skip(4)
  of 0x0008, 0x0009, 0x000C, 0x000E:
    r.skip(8)
  of 0x000D:
    discard r.readString()
  of 0x000F:
    r.skip(8)
  of 0x0010:
    r.skip(16)
  of 0x0011:
    let count = r.readU32()
    let elementType = r.readU16()
    for _ in 0'u32 ..< count:
      let itemType = if elementType == 0: r.readU16() else: elementType
      r.skipPropertyValue(itemType)
  of 0x0012:
    let count = r.readU32()
    for _ in 0'u32 ..< count:
      discard r.readString()
      r.skipPropertyValue(r.readU16())
  of 0x0013:
    r.skip(16)
  else:
    r.fail(&"unsupported user-data property type 0x{propertyType.toHex(4)}")

proc parseUserData(r: var Reader; frame: var AsepriteFrame) {.gcsafe.} =
  let flags = r.readU32()
  var data = AsepriteUserData(
    hasText: (flags and 1'u32) != 0,
    hasColor: (flags and 2'u32) != 0,
    hasProperties: (flags and 4'u32) != 0
  )
  if data.hasText:
    data.text = r.readString()
  if data.hasColor:
    data.color = AsepriteColor(r: r.readU8(), g: r.readU8(), b: r.readU8(), a: r.readU8())
  if data.hasProperties:
    let start = r.pos
    let totalSize = int(r.readU32())
    if totalSize < 8:
      r.fail("invalid user-data property map size")
    let maps = r.readU32()
    for _ in 0'u32 ..< maps:
      r.skipPropertyMap()
    let consumed = r.pos - start
    if consumed < totalSize:
      r.skip(totalSize - consumed)
    elif consumed > totalSize:
      r.fail("user-data properties overran declared size")
  frame.userData.add data

proc parseTags(r: var Reader; sprite: var AsepriteFile) =
  let count = int(r.readU16())
  r.skip(8)
  for _ in 0 ..< count:
    var tag: AsepriteTag
    tag.fromFrame = r.readU16()
    tag.toFrame = r.readU16()
    tag.direction = r.readU8()
    tag.repeat = r.readU16()
    r.skip(6)
    for i in 0 ..< tag.color.len:
      tag.color[i] = r.readU8()
    r.skip(1)
    tag.name = r.readString()
    sprite.tags.add tag

proc parseSlice(r: var Reader; sprite: var AsepriteFile) =
  let count = r.readU32()
  var slice: AsepriteSlice
  slice.flags = r.readU32()
  discard r.readU32()
  slice.name = r.readString()
  for _ in 0'u32 ..< count:
    var key: AsepriteSliceKey
    key.frame = r.readU32()
    key.x = r.readI32()
    key.y = r.readI32()
    key.width = r.readU32()
    key.height = r.readU32()
    if (slice.flags and 1'u32) != 0:
      key.centerX = r.readI32()
      key.centerY = r.readI32()
      key.centerWidth = r.readU32()
      key.centerHeight = r.readU32()
    if (slice.flags and 2'u32) != 0:
      key.pivotX = r.readI32()
      key.pivotY = r.readI32()
    slice.keys.add key
  sprite.slices.add slice

proc parseTileset(r: var Reader; sprite: var AsepriteFile) =
  var tileset: AsepriteTileset
  tileset.id = r.readU32()
  tileset.flags = r.readU32()
  tileset.tileCount = r.readU32()
  tileset.tileWidth = r.readU16()
  tileset.tileHeight = r.readU16()
  tileset.baseIndex = r.readI16()
  r.skip(14)
  tileset.name = r.readString()
  if (tileset.flags and 1'u32) != 0:
    tileset.externalFileId = r.readU32()
    tileset.externalTilesetId = r.readU32()
  if (tileset.flags and 2'u32) != 0:
    let compressedLen = int(r.readU32())
    let expected = int(tileset.tileWidth) * int(tileset.tileHeight) * int(tileset.tileCount) * bytesPerPixel(sprite.colorDepth)
    tileset.pixels = uncompressZlib(r.readBytes(compressedLen), expected, r.origin)
  sprite.tilesets.add tileset

proc parseExternalFiles(r: var Reader) =
  let count = r.readU32()
  r.skip(8)
  for _ in 0'u32 ..< count:
    r.skip(4 + 1 + 7)
    discard r.readString()

proc parseMask(r: var Reader) =
  discard r.readI16()
  discard r.readI16()
  let width = r.readU16()
  let height = r.readU16()
  r.skip(8)
  discard r.readString()
  r.skip(int(height) * ((int(width) + 7) div 8))

proc parseCelExtra(r: var Reader) =
  r.skip(4 + 4 + 4 + 4 + 4 + 16)

proc parseColorProfile(r: var Reader) =
  let profileType = r.readU16()
  r.skip(2 + 4 + 8)
  if profileType == 2:
    r.skip(int(r.readU32()))

proc parseFrameChunk(
  r: var Reader;
  sprite: var AsepriteFile;
  frame: var AsepriteFrame;
  frameIndex: int;
  chunkType: uint16;
  chunkSize: uint32
) {.gcsafe.} =
  sprite.chunks.add AsepriteChunkSummary(frameIndex: frameIndex, chunkType: chunkType, size: chunkSize)
  case chunkType
  of 0x0004:
    parseOldPalette(r, sprite, false)
  of 0x0011:
    parseOldPalette(r, sprite, true)
  of 0x2004:
    parseLayer(r, sprite)
  of 0x2005:
    parseCel(r, sprite, frame)
  of 0x2006:
    parseCelExtra(r)
  of 0x2007:
    parseColorProfile(r)
  of 0x2008:
    parseExternalFiles(r)
  of 0x2016:
    parseMask(r)
  of 0x2017:
    discard
  of 0x2018:
    parseTags(r, sprite)
  of 0x2019:
    parsePalette(r, sprite)
  of 0x2020:
    parseUserData(r, frame)
  of 0x2022:
    parseSlice(r, sprite)
  of 0x2023:
    parseTileset(r, sprite)
  else:
    r.skip(r.data.len - r.pos)

proc bytesToSeq(s: string): seq[uint8] =
  result = newSeq[uint8](s.len)
  for i, ch in s:
    result[i] = uint8(ch)

proc loadAseprite*(path: string): AsepriteFile {.gcsafe.} =
  var r = Reader(data: bytesToSeq(readFile(path)), origin: path)
  if r.data.len < HeaderSize:
    r.fail("file is shorter than the 128-byte header")
  let fileSize = r.readU32()
  if fileSize != uint32(r.data.len):
    r.fail(&"declared file size {fileSize} does not match actual size {r.data.len}")
  if r.readU16() != FileMagic:
    r.fail("invalid ASE magic")
  let frameCount = r.readU16()
  result.path = path
  result.width = r.readU16()
  result.height = r.readU16()
  result.colorDepth =
    case r.readU16()
    of 8: acIndexed
    of 16: acGrayscale
    of 32: acRgba
    else:
      r.fail("unsupported color depth")
  result.flags = r.readU32()
  let speed = r.readU16()
  r.skip(8)
  result.transparentIndex = r.readU8()
  r.skip(3)
  result.colorCount = r.readU16()
  result.pixelWidth = r.readU8()
  result.pixelHeight = r.readU8()
  result.gridX = r.readI16()
  result.gridY = r.readI16()
  result.gridWidth = r.readU16()
  result.gridHeight = r.readU16()
  r.skip(84)

  for frameIndex in 0 ..< int(frameCount):
    let frameStart = r.pos
    let frameBytes = int(r.readU32())
    if frameBytes < 16:
      r.fail("invalid frame size")
    let frameEnd = frameStart + frameBytes
    if frameEnd > r.data.len:
      r.fail("frame overruns file")
    if r.readU16() != FrameMagic:
      r.fail("invalid frame magic")
    let oldChunkCount = r.readU16()
    var frame = AsepriteFrame(durationMs: speed)
    let duration = r.readU16()
    if duration > 0:
      frame.durationMs = duration
    r.skip(2)
    let newChunkCount = r.readU32()
    let chunkCount = if newChunkCount != 0: int(newChunkCount) else: int(oldChunkCount)
    for _ in 0 ..< chunkCount:
      let chunkStart = r.pos
      let chunkSize = r.readU32()
      if chunkSize < 6:
        r.fail("invalid chunk size")
      let chunkType = r.readU16()
      let chunkEnd = chunkStart + int(chunkSize)
      if chunkEnd > frameEnd:
        r.fail("chunk overruns frame")
      var cr = r.chunkReader(r.pos, chunkEnd)
      parseFrameChunk(cr, result, frame, frameIndex, chunkType, chunkSize)
      if cr.pos != cr.data.len:
        cr.fail("chunk parser did not consume the full chunk")
      r.pos = chunkEnd
    if r.pos != frameEnd:
      r.fail("frame parser did not consume the full frame")
    result.frames.add frame

  if r.pos != r.data.len:
    r.fail("trailing bytes after declared frames")

proc layerVisible(layer: AsepriteLayer): bool =
  (layer.flags and 1'u16) != 0

proc findLinkedCel(sprite: AsepriteFile; cel: AsepriteCel): AsepriteCel =
  if int(cel.linkedFrame) >= sprite.frames.len:
    raise newException(AsepriteError, &"{sprite.path}: linked cel references missing frame {cel.linkedFrame}")
  for candidate in sprite.frames[int(cel.linkedFrame)].cels:
    if candidate.layerIndex == cel.layerIndex and candidate.celType != actLinked:
      return candidate
  raise newException(AsepriteError, &"{sprite.path}: linked cel target not found for layer {cel.layerIndex}")

proc pixelRgba(sprite: AsepriteFile; data: seq[uint8]; pixelIndex: int; layer: AsepriteLayer): array[4, uint8] =
  case sprite.colorDepth
  of acRgba:
    let offset = pixelIndex * 4
    [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
  of acGrayscale:
    let offset = pixelIndex * 2
    [data[offset], data[offset], data[offset], data[offset + 1]]
  of acIndexed:
    let index = data[pixelIndex]
    if index == sprite.transparentIndex and (layer.flags and 8'u16) == 0:
      [0'u8, 0'u8, 0'u8, 0'u8]
    elif int(index) < sprite.palette.entries.len:
      let color = sprite.palette.entries[int(index)]
      [color.r, color.g, color.b, color.a]
    else:
      raise newException(AsepriteError, &"{sprite.path}: indexed pixel {index} has no palette entry")

proc blendOver(dst: var seq[uint8]; dstOffset: int; src: array[4, uint8]; opacity: float32) =
  let sa = (src[3].float32 / 255'f32) * opacity
  if sa <= 0'f32:
    return
  let da = dst[dstOffset + 3].float32 / 255'f32
  let outA = sa + da * (1'f32 - sa)
  if outA <= 0'f32:
    return
  for channel in 0 .. 2:
    let sc = src[channel].float32 / 255'f32
    let dc = dst[dstOffset + channel].float32 / 255'f32
    let outC = (sc * sa + dc * da * (1'f32 - sa)) / outA
    dst[dstOffset + channel] = uint8(clamp(round(outC * 255'f32), 0'f32, 255'f32))
  dst[dstOffset + 3] = uint8(clamp(round(outA * 255'f32), 0'f32, 255'f32))

proc renderFrameRgba*(sprite: AsepriteFile; frameIndex = 0): seq[uint8] {.gcsafe.} =
  if frameIndex < 0 or frameIndex >= sprite.frames.len:
    raise newException(AsepriteError, &"{sprite.path}: frame {frameIndex} is out of range")
  result = newSeq[uint8](int(sprite.width) * int(sprite.height) * 4)
  type OrderedCel = object
    cel: AsepriteCel
    layerIndex: int
    zIndex: int
  var ordered: seq[OrderedCel]
  for cel in sprite.frames[frameIndex].cels:
    ordered.add OrderedCel(cel: cel, layerIndex: int(cel.layerIndex), zIndex: int(cel.zIndex))
  ordered.sort(proc(a, b: OrderedCel): int =
    let ao = a.layerIndex + a.zIndex
    let bo = b.layerIndex + b.zIndex
    if ao != bo: cmp(ao, bo) else: cmp(a.zIndex, b.zIndex)
  )

  for item in ordered:
    if item.layerIndex < 0 or item.layerIndex >= sprite.layers.len:
      raise newException(AsepriteError, &"{sprite.path}: cel references missing layer {item.layerIndex}")
    let layer = sprite.layers[item.layerIndex]
    if not layer.layerVisible:
      continue
    if layer.layerType == altTilemap:
      raise newException(AsepriteError, &"{sprite.path}: tilemap rendering is parsed but not implemented")
    if layer.layerType == altGroup:
      continue
    if layer.blendMode != 0:
      raise newException(AsepriteError, &"{sprite.path}: blend mode {layer.blendMode} rendering is not implemented")
    var cel = item.cel
    if cel.celType == actLinked:
      cel = findLinkedCel(sprite, cel)
    if cel.celType notin {actRawImage, actCompressedImage}:
      continue
    let layerOpacity =
      if (sprite.flags and 1'u32) != 0: layer.opacity.float32 / 255'f32 else: 1'f32
    let opacity = layerOpacity * (cel.opacity.float32 / 255'f32)
    for cy in 0 ..< int(cel.height):
      let dy = int(cel.y) + cy
      if dy < 0 or dy >= int(sprite.height):
        continue
      for cx in 0 ..< int(cel.width):
        let dx = int(cel.x) + cx
        if dx < 0 or dx >= int(sprite.width):
          continue
        let src = sprite.pixelRgba(cel.pixels, cy * int(cel.width) + cx, layer)
        let dstOffset = (dy * int(sprite.width) + dx) * 4
        blendOver(result, dstOffset, src, opacity)

proc createAsepriteTexture3D*(
  artist3D: var Artist3D;
  path: string;
  frameIndex = 0;
  filterMode: TextureFilterMode = tfNearest
): GPUTextureHandle {.gcsafe.} =
  let sprite = loadAseprite(path)
  let pixels = sprite.renderFrameRgba(frameIndex)
  createTexture3D(artist3D, int(sprite.width), int(sprite.height), pixels, filterMode)
