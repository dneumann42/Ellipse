import std/[math, os, tables]

import ../platform/SDL3
import ../platform/SDL3gpu
import ../platform/SDL3gpuext
import ../platform/SDL3ttfext
import ./[gpupipelines, gpushaders, gpuuploads]

type
  Artist2DError* = object of CatchableError

  SpriteTexture* = ptr GPUTexture

  TextureFilterMode* = enum
    tfLinear,
    tfNearest

  RenderTargetLoadOp* = enum
    renderTargetLoad,
    renderTargetClear

  ScissorRect* = object
    x*, y*, w*, h*: int

  SpriteTextureRegion* = object
    u0*, v0*, u1*, v1*: cfloat

  Sprite2D* = object
    position*: array[2, cfloat]
    size*: array[2, cfloat]
    scale*: array[2, cfloat]
    origin*: array[2, cfloat]
    rotation*: cfloat
    tint*: array[4, cfloat]
    texture*: SpriteTexture
    filterMode*: TextureFilterMode
    hasFilterOverride*: bool
    region*: SpriteTextureRegion
    hasRegion*: bool

  Artist2DConfig* = object
    maxSprites*: int
    maxTextureSlots*: int
    vertexShaderPath*: string
    fragmentShaderPath*: string
    samplerInfo*: GPUSamplerCreateInfo
    defaultFontPath*: string
    defaultFontSize*: cfloat

  Artist2D* = object
    device*: GPUDeviceHandle
    pipeline*: GPUGraphicsPipelineHandle
    vertexShader*: GPUShaderHandle
    fragmentShader*: GPUShaderHandle
    primitivePipeline*: GPUGraphicsPipelineHandle
    primitiveVertexShader*: GPUShaderHandle
    primitiveFragmentShader*: GPUShaderHandle
    quadVertexBuffer*: GPUBufferHandle
    quadIndexBuffer*: GPUBufferHandle
    instanceBuffer*: GPUBufferHandle
    instanceTransferBuffer*: GPUTransferBufferHandle
    primitiveVertexBuffer*: GPUBufferHandle
    primitiveIndexBuffer*: GPUBufferHandle
    primitiveVertexTransferBuffer*: GPUTransferBufferHandle
    primitiveIndexTransferBuffer*: GPUTransferBufferHandle
    whiteTexture*: GPUTextureHandle
    linearSampler*: GPUSamplerHandle
    nearestSampler*: GPUSamplerHandle
    defaultFontPath*: string
    defaultFontSize*: cfloat
    font*: TTFFontHandle
    currentFontSize: int
    maxSprites*: int
    maxTextureSlots*: int
    maxPrimitiveVertices*: int
    maxPrimitiveIndices*: int
    instances: seq[SpriteInstance]
    batches: seq[SpriteBatch]
    primitiveVertices: seq[PrimitiveVertex]
    primitiveIndices: seq[uint32]
    primitiveBatches: seq[PrimitiveBatch]
    drawCommands: seq[DrawCommand]
    currentBatchStart: int
    currentBatchCount: int
    currentPrimitiveStart: int
    currentPrimitiveCount: int
    currentBindings: seq[TextureBinding]
    currentDrawMode: DrawMode
    currentScissor: QueuedScissor
    textureFilters: Table[ptr GPUTexture, TextureFilterMode]
    textCache: Table[(int, string), int]
    cachedTextEntries: seq[CachedTextEntry]
    cachedTextTextures: seq[ptr GPUTexture]

  QuadVertex = object
    localPosition: array[2, cfloat]
    uv: array[2, cfloat]

  SpriteInstance = object
    position: array[2, cfloat]
    size: array[2, cfloat]
    scale: array[2, cfloat]
    origin: array[2, cfloat]
    uvRect: array[4, cfloat]
    tint: array[4, cfloat]
    rotation: cfloat
    textureIndex: cfloat

  SpriteBatch = object
    firstInstance: uint32
    instanceCount: uint32
    textures: array[8, ptr GPUTexture]
    filterModes: array[8, TextureFilterMode]

  PrimitiveVertex = object
    position: array[2, cfloat]
    tint: array[4, cfloat]

  PrimitiveBatch = object
    firstIndex: uint32
    indexCount: uint32

  DrawMode = enum
    drawModeNone,
    drawModeSprites,
    drawModePrimitives

  DrawCommand = object
    mode: DrawMode
    batchIndex: uint32
    scissor: QueuedScissor

  TextureBinding = object
    texture: ptr GPUTexture
    filterMode: TextureFilterMode

  QueuedScissor = object
    enabled: bool
    rect: ScissorRect

  Mat4 = array[16, cfloat]

  CachedTextEntry = object
    key: (int, string)
    texture: ptr GPUTexture
    width: int
    height: int

const
  maxShaderTextureSlots = 8
  defaultFontStyleBold = 0x01'u32
  shaderDir = currentSourcePath.parentDir / "shaders"
  defaultFontPointSize* = 10'f32
  minPrimitiveVertexCapacity = 2_048
  maxPrimitiveVertexCapacity = 65_536
  primitiveCircleMinSegments = 12
  primitiveCircleMaxSegments = 96

proc defaultVertexShaderPath*(): string =
  shaderDir / "sprites.vert.spv"

proc defaultFragmentShaderPath*(): string =
  shaderDir / "sprites.frag.spv"

proc defaultPrimitiveVertexShaderPath*(): string =
  shaderDir / "primitives.vert.spv"

proc defaultPrimitiveFragmentShaderPath*(): string =
  shaderDir / "primitives.frag.spv"

proc spriteTextureRegion*(u0, v0, u1, v1: cfloat): SpriteTextureRegion =
  SpriteTextureRegion(u0: u0, v0: v0, u1: u1, v1: v1)

proc defaultSamplerInfo(): GPUSamplerCreateInfo =
  GPUSamplerCreateInfo(
    min_filter: gpuFilterLinear,
    mag_filter: gpuFilterLinear,
    mipmap_mode: gpuSamplerMipmapModeNearest,
    address_mode_u: gpuSamplerAddressModeClampToEdge,
    address_mode_v: gpuSamplerAddressModeClampToEdge,
    address_mode_w: gpuSamplerAddressModeClampToEdge,
    mip_lod_bias: 0,
    max_anisotropy: 1,
    compare_op: gpuCompareOpInvalid,
    min_lod: 0,
    max_lod: 0,
    enable_anisotropy: false,
    enable_compare: false,
    props: 0
  )

proc samplerInfoForFilter(
  samplerInfo: GPUSamplerCreateInfo;
  filterMode: TextureFilterMode
): GPUSamplerCreateInfo =
  result = samplerInfo
  case filterMode
  of tfLinear:
    result.min_filter = gpuFilterLinear
    result.mag_filter = gpuFilterLinear
  of tfNearest:
    result.min_filter = gpuFilterNearest
    result.mag_filter = gpuFilterNearest

proc initSprite2D*(): Sprite2D =
  Sprite2D(
    position: [0'f32, 0'f32],
    size: [1'f32, 1'f32],
    scale: [1'f32, 1'f32],
    origin: [0.5'f32, 0.5'f32],
    rotation: 0,
    tint: [1'f32, 1'f32, 1'f32, 1'f32],
    texture: nil,
    filterMode: tfLinear,
    hasFilterOverride: false,
    region: SpriteTextureRegion(u0: 0, v0: 0, u1: 1, v1: 1),
    hasRegion: false
  )

proc orthoProjection(width: uint32; height: uint32): Mat4 =
  let w = max(width, 1'u32).cfloat
  let h = max(height, 1'u32).cfloat
  result = [
    2.0'f32 / w, 0, 0, 0,
    0, -2.0'f32 / h, 0, 0,
    0, 0, 1, 0,
    -1, 1, 0, 1
  ]

proc quadVertices(): array[4, QuadVertex] =
  [
    QuadVertex(localPosition: [0'f32, 0'f32], uv: [0'f32, 0'f32]),
    QuadVertex(localPosition: [1'f32, 0'f32], uv: [1'f32, 0'f32]),
    QuadVertex(localPosition: [1'f32, 1'f32], uv: [1'f32, 1'f32]),
    QuadVertex(localPosition: [0'f32, 1'f32], uv: [0'f32, 1'f32])
  ]

proc quadIndices(): array[6, uint16] =
  [0'u16, 1'u16, 2'u16, 0'u16, 2'u16, 3'u16]

proc fullRegion(): SpriteTextureRegion =
  spriteTextureRegion(0, 0, 1, 1)

proc createSpriteTexture*(
  artist: var Artist2D;
  width: int;
  height: int;
  pixels: openArray[uint8];
  filterMode: TextureFilterMode = tfLinear
): GPUTextureHandle {.gcsafe.}

proc defaultPrimitiveVertexCapacity(maxSprites: int): int =
  let requested =
    if maxSprites <= 0:
      minPrimitiveVertexCapacity
    else:
      max(minPrimitiveVertexCapacity, maxSprites div 8)
  clamp(requested, minPrimitiveVertexCapacity, maxPrimitiveVertexCapacity)

proc primitiveColor(color: FColor): array[4, cfloat] =
  [color.r, color.g, color.b, color.a]

proc triangleArea2(
  p0, p1, p2: array[2, cfloat]
): cfloat =
  (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0])

proc hasUsableTriangle(
  p0, p1, p2: array[2, cfloat]
): bool =
  abs(triangleArea2(p0, p1, p2)) > 0.0001'f32

proc primitiveCircleSegmentCount*(radius: cfloat): int =
  if radius <= 0:
    return 0

  let estimated = int(ceil(2'f32 * PI.cfloat * radius / 10'f32))
  clamp(estimated, primitiveCircleMinSegments, primitiveCircleMaxSegments)

proc splitTextLines(text: string): seq[string] =
  result = @[""]
  for ch in text:
    case ch
    of '\n':
      result.add("")
    of '\r':
      discard
    else:
      result[^1].add(ch)

proc fontPixelSize(artist: Artist2D; scale: cfloat): int =
  max(1, int(round(max(scale, 0.01'f32) * artist.defaultFontSize)))

proc ensureFontSize(artist: var Artist2D; pixelSize: int) =
  if pixelSize == artist.currentFontSize:
    return
  artist.font.setSize(pixelSize.cfloat)
  artist.currentFontSize = pixelSize

proc lineHeight(artist: var Artist2D; pixelSize: int): int =
  artist.ensureFontSize(pixelSize)
  max(1, artist.font.fontHeight())

proc renderLineSurface(artist: var Artist2D; text: string; pixelSize: int): ptr Surface =
  artist.ensureFontSize(pixelSize)
  artist.font.renderTextBlended(text, Color(r: 255, g: 255, b: 255, a: 255))

proc measureLine(artist: var Artist2D; text: string; pixelSize: int): tuple[w, h: int] =
  artist.ensureFontSize(pixelSize)
  if text.len == 0:
    return (w: 0, h: artist.font.fontHeight())
  artist.font.stringSize(text)

proc tightSurfacePixels(surface: ptr Surface): seq[uint8] =
  let width = int(surface.w)
  let height = int(surface.h)
  result = newSeq[uint8](width * height * 4)
  if width <= 0 or height <= 0 or surface.pixels.isNil:
    return

  let srcPitch = int(surface.pitch)
  let rowBytes = width * 4
  let srcBase = cast[ptr UncheckedArray[uint8]](surface.pixels)
  for y in 0 ..< height:
    copyMem(
      addr result[y * rowBytes],
      cast[pointer](cast[uint](srcBase) + uint(y * srcPitch)),
      rowBytes
    )

proc trimTransparentRows(
  pixels: seq[uint8];
  width: int;
  height: int
): tuple[pixels: seq[uint8], height: int] =
  if width <= 0 or height <= 0 or pixels.len == 0:
    return (pixels: newSeq[uint8](max(width * max(height, 1), 1) * 4), height: max(height, 1))

  var top = 0
  while top < height:
    var opaque = false
    let rowStart = top * width * 4
    for x in 0 ..< width:
      if pixels[rowStart + x * 4 + 3] != 0:
        opaque = true
        break
    if opaque:
      break
    inc top

  if top >= height:
    return (pixels: newSeq[uint8](width * 4), height: 1)

  var bottom = height - 1
  while bottom > top:
    var opaque = false
    let rowStart = bottom * width * 4
    for x in 0 ..< width:
      if pixels[rowStart + x * 4 + 3] != 0:
        opaque = true
        break
    if opaque:
      break
    dec bottom

  let trimmedHeight = max(bottom - top + 1, 1)
  result = (pixels: newSeq[uint8](width * trimmedHeight * 4), height: trimmedHeight)
  copyMem(addr result.pixels[0], unsafeAddr pixels[top * width * 4], width * trimmedHeight * 4)

proc buildTextPixels(
  artist: var Artist2D;
  text: string;
  pixelSize: int
): tuple[pixels: seq[uint8], width, height: int] {.gcsafe.} =
  let lines = splitTextLines(text)
  var linePixels = newSeq[seq[uint8]](lines.len)
  var lineWidths = newSeq[int](lines.len)
  var lineHeights = newSeq[int](lines.len)
  var maxWidth = 0
  var totalHeight = 0

  for i, line in lines:
    if line.len == 0:
      linePixels[i] = @[]
      lineWidths[i] = 0
      lineHeights[i] = max(artist.lineHeight(pixelSize) div 2, 1)
      totalHeight += lineHeights[i]
      continue

    let surface = artist.renderLineSurface(line, pixelSize)
    defer:
      destroySurface(surface)
    let width = int(surface.w)
    let height = int(surface.h)
    let srcPixels = tightSurfacePixels(surface)
    let trimmed = trimTransparentRows(srcPixels, width, height)
    linePixels[i] = trimmed.pixels
    lineWidths[i] = width
    lineHeights[i] = trimmed.height
    maxWidth = max(maxWidth, width)
    totalHeight += trimmed.height

  let totalWidth = max(maxWidth, 1)
  let finalHeight = max(totalHeight, 1)
  result = (pixels: newSeq[uint8](totalWidth * finalHeight * 4), width: totalWidth, height: finalHeight)

  var dstY = 0
  for i, line in lines:
    let lineHeight = lineHeights[i]
    let srcPixels = linePixels[i]
    if line.len > 0 and srcPixels.len > 0:
      let width = lineWidths[i]
      for y in 0 ..< min(lineHeight, finalHeight - dstY):
        copyMem(
          addr result.pixels[((dstY + y) * totalWidth) * 4],
          unsafeAddr srcPixels[(y * width) * 4],
          width * 4
        )
    dstY += lineHeight

proc cacheTextTexture(
  artist: var Artist2D;
  text: string;
  pixelSize: int
): CachedTextEntry {.gcsafe.}

proc measureText*(
  artist: var Artist2D;
  text: string;
  scale: cfloat = 1.0
): tuple[w, h: int] {.gcsafe.} =
  if text.len == 0:
    let pixelSize = artist.fontPixelSize(scale)
    return (w: 0, h: max(artist.lineHeight(pixelSize) div 2, 1))

  let entry = artist.cacheTextTexture(text, artist.fontPixelSize(scale))
  (w: entry.width, h: entry.height)

proc cacheTextTexture(
  artist: var Artist2D;
  text: string;
  pixelSize: int
): CachedTextEntry {.gcsafe.} =
  let key = (pixelSize, text)
  if artist.textCache.hasKey(key):
    return artist.cachedTextEntries[artist.textCache[key]]

  let rendered = artist.buildTextPixels(text, pixelSize)
  let texture = artist.createSpriteTexture(rendered.width, rendered.height, rendered.pixels, tfLinear)
  let entry = CachedTextEntry(
    key: key,
    texture: raw(texture),
    width: rendered.width,
    height: rendered.height
  )
  artist.textCache[key] = artist.cachedTextEntries.len
  artist.cachedTextEntries.add(entry)
  artist.cachedTextTextures.add(entry.texture)
  entry

proc releaseCachedTextTextures*(artist: var Artist2D) =
  for texture in artist.cachedTextTextures:
    if not texture.isNil:
      releaseGPUTexture(raw(artist.device), texture)
  artist.cachedTextTextures.setLen(0)
  artist.cachedTextEntries.setLen(0)
  artist.textCache.clear()

proc registerTextureFilter(
  artist: var Artist2D;
  texture: ptr GPUTexture;
  filterMode: TextureFilterMode
) =
  if texture.isNil:
    return
  artist.textureFilters[texture] = filterMode

proc `==`(a, b: ScissorRect): bool =
  a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h

proc `==`(a, b: QueuedScissor): bool =
  a.enabled == b.enabled and (not a.enabled or a.rect == b.rect)

proc finalizeBatch(artist: var Artist2D) =
  if artist.currentBatchCount <= 0:
    return

  var batch = SpriteBatch(
    firstInstance: uint32(artist.currentBatchStart),
    instanceCount: uint32(artist.currentBatchCount)
  )
  for i in 0 ..< artist.maxTextureSlots:
    if i < artist.currentBindings.len:
      batch.textures[i] = artist.currentBindings[i].texture
      batch.filterModes[i] = artist.currentBindings[i].filterMode
    else:
      batch.textures[i] = raw(artist.whiteTexture)
      batch.filterModes[i] = tfLinear
  artist.batches.add(batch)
  artist.drawCommands.add(DrawCommand(
    mode: drawModeSprites,
    batchIndex: uint32(artist.batches.len - 1),
    scissor: artist.currentScissor
  ))
  artist.currentBatchStart = artist.instances.len
  artist.currentBatchCount = 0
  artist.currentBindings.setLen(0)

proc finalizePrimitiveBatch(artist: var Artist2D) =
  if artist.currentPrimitiveCount <= 0:
    return

  artist.primitiveBatches.add(PrimitiveBatch(
    firstIndex: uint32(artist.currentPrimitiveStart),
    indexCount: uint32(artist.currentPrimitiveCount)
  ))
  artist.drawCommands.add(DrawCommand(
    mode: drawModePrimitives,
    batchIndex: uint32(artist.primitiveBatches.len - 1),
    scissor: artist.currentScissor
  ))
  artist.currentPrimitiveStart = artist.primitiveIndices.len
  artist.currentPrimitiveCount = 0

proc flushActiveBatchForStateChange(artist: var Artist2D) =
  case artist.currentDrawMode
  of drawModeSprites:
    artist.finalizeBatch()
  of drawModePrimitives:
    artist.finalizePrimitiveBatch()
  of drawModeNone:
    discard

proc setQueuedScissor(artist: var Artist2D; scissor: QueuedScissor) =
  if artist.currentScissor == scissor:
    return
  artist.flushActiveBatchForStateChange()
  artist.currentScissor = scissor

proc textureFilter(artist: Artist2D; texture: ptr GPUTexture): TextureFilterMode =
  if texture.isNil:
    return tfLinear
  if artist.textureFilters.hasKey(texture):
    return artist.textureFilters[texture]
  tfLinear

proc textureSlot(
  artist: var Artist2D;
  texture: ptr GPUTexture;
  filterMode: TextureFilterMode
): int =
  let resolvedBinding =
    TextureBinding(
      texture:
        if texture.isNil: raw(artist.whiteTexture)
        else: texture,
      filterMode: filterMode
    )

  for i, entry in artist.currentBindings:
    if entry == resolvedBinding:
      return i

  if artist.currentBindings.len >= artist.maxTextureSlots:
    artist.finalizeBatch()
  for i, entry in artist.currentBindings:
    if entry == resolvedBinding:
      return i

  artist.currentBindings.add(resolvedBinding)
  artist.currentBindings.len - 1

proc createWhiteTexture(device: GPUDeviceHandle): GPUTextureHandle =
  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER,
    width: 1,
    height: 1,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  result = createGPUTexture(device, textureInfo)
  let pixels = [255'u8, 255'u8, 255'u8, 255'u8]
  uploadTexture2DData(device, result, 1, 1, pixels, "artist2d white texture")

proc createRenderTargetTexture*(
  device: GPUDeviceHandle;
  width: int;
  height: int
): GPUTextureHandle =
  if width <= 0 or height <= 0:
    raise newException(Artist2DError, "Render target texture dimensions must be positive")

  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER or GPU_TEXTUREUSAGE_COLOR_TARGET,
    width: uint32(width),
    height: uint32(height),
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  createGPUTexture(device, textureInfo)

proc createPipeline(artist: var Artist2D; swapchainFormat: GPUTextureFormat) =
  var vertexBufferDescriptions = [
    GPUVertexBufferDescription(
      slot: 0,
      pitch: uint32(sizeof(QuadVertex)),
      input_rate: gpuVertexInputRateVertex,
      instance_step_rate: 0
    ),
    GPUVertexBufferDescription(
      slot: 1,
      pitch: uint32(sizeof(SpriteInstance)),
      input_rate: gpuVertexInputRateInstance,
      instance_step_rate: 0
    )
  ]
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(QuadVertex, localPosition))
    ),
    GPUVertexAttribute(
      location: 1,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(QuadVertex, uv))
    ),
    GPUVertexAttribute(
      location: 2,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(SpriteInstance, position))
    ),
    GPUVertexAttribute(
      location: 3,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(SpriteInstance, size))
    ),
    GPUVertexAttribute(
      location: 4,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(SpriteInstance, scale))
    ),
    GPUVertexAttribute(
      location: 5,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(SpriteInstance, origin))
    ),
    GPUVertexAttribute(
      location: 6,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat4,
      offset: uint32(offsetof(SpriteInstance, uvRect))
    ),
    GPUVertexAttribute(
      location: 7,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat4,
      offset: uint32(offsetof(SpriteInstance, tint))
    ),
    GPUVertexAttribute(
      location: 8,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat,
      offset: uint32(offsetof(SpriteInstance, rotation))
    ),
    GPUVertexAttribute(
      location: 9,
      buffer_slot: 1,
      format: gpuVertexElementFormatFloat,
      offset: uint32(offsetof(SpriteInstance, textureIndex))
    )
  ]

  artist.pipeline = createAlphaBlendedTexturedPipeline(
    artist.device,
    swapchainFormat,
    artist.vertexShader,
    artist.fragmentShader,
    addr vertexBufferDescriptions[0],
    uint32(vertexBufferDescriptions.len),
    addr vertexAttributes[0],
    uint32(vertexAttributes.len)
  )

proc createPrimitivePipeline(artist: var Artist2D; swapchainFormat: GPUTextureFormat) =
  var vertexBufferDescription = GPUVertexBufferDescription(
    slot: 0,
    pitch: uint32(sizeof(PrimitiveVertex)),
    input_rate: gpuVertexInputRateVertex,
    instance_step_rate: 0
  )
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(PrimitiveVertex, position))
    ),
    GPUVertexAttribute(
      location: 1,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat4,
      offset: uint32(offsetof(PrimitiveVertex, tint))
    )
  ]

  artist.primitivePipeline = createAlphaBlendedColorPipeline(
    artist.device,
    swapchainFormat,
    artist.primitiveVertexShader,
    artist.primitiveFragmentShader,
    addr vertexBufferDescription,
    1,
    addr vertexAttributes[0],
    uint32(vertexAttributes.len)
  )

proc initArtist2D*(
  device: GPUDeviceHandle,
  swapchainFormat: GPUTextureFormat,
  config: Artist2DConfig
): Artist2D =
  if config.maxSprites <= 0:
    raise newException(Artist2DError, "Artist2D requires maxSprites > 0")

  result.device = device
  result.maxSprites = config.maxSprites
  result.maxTextureSlots = clamp(
    if config.maxTextureSlots <= 0: maxShaderTextureSlots else: config.maxTextureSlots,
    1,
    maxShaderTextureSlots
  )
  result.maxPrimitiveVertices = defaultPrimitiveVertexCapacity(result.maxSprites)
  result.maxPrimitiveIndices = result.maxPrimitiveVertices * 3
  result.instances = newSeqOfCap[SpriteInstance](result.maxSprites)
  result.batches = newSeqOfCap[SpriteBatch](max(1, result.maxSprites div 256))
  result.primitiveVertices = newSeqOfCap[PrimitiveVertex](result.maxPrimitiveVertices)
  result.primitiveIndices = newSeqOfCap[uint32](result.maxPrimitiveIndices)
  result.primitiveBatches = newSeqOfCap[PrimitiveBatch](max(1, result.maxPrimitiveVertices div 256))
  result.drawCommands = newSeqOfCap[DrawCommand](max(1, result.maxSprites div 128))
  result.currentBindings = newSeqOfCap[TextureBinding](result.maxTextureSlots)
  result.textureFilters = initTable[ptr GPUTexture, TextureFilterMode]()
  result.textCache = initTable[(int, string), int]()
  result.cachedTextEntries = @[]
  result.cachedTextTextures = @[]
  result.defaultFontPath = config.defaultFontPath
  result.defaultFontSize =
    if config.defaultFontSize > 0: config.defaultFontSize
    else: defaultFontPointSize

  result.vertexShader = createShaderFromFile(
    device,
    if config.vertexShaderPath.len > 0: config.vertexShaderPath else: defaultVertexShaderPath(),
    gpuShaderStageVertex,
    0,
    1
  )
  result.fragmentShader = createShaderFromFile(
    device,
    if config.fragmentShaderPath.len > 0: config.fragmentShaderPath else: defaultFragmentShaderPath(),
    gpuShaderStageFragment,
    uint32(maxShaderTextureSlots),
    0
  )
  result.primitiveVertexShader = createShaderFromFile(
    device,
    defaultPrimitiveVertexShaderPath(),
    gpuShaderStageVertex,
    0,
    1
  )
  result.primitiveFragmentShader = createShaderFromFile(
    device,
    defaultPrimitiveFragmentShaderPath(),
    gpuShaderStageFragment,
    0,
    0
  )

  let quadBufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX,
    size: uint32(sizeof(quadVertices())),
    props: 0
  )
  result.quadVertexBuffer = createGPUBuffer(device, quadBufferInfo)

  let indexBufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_INDEX,
    size: uint32(sizeof(quadIndices())),
    props: 0
  )
  result.quadIndexBuffer = createGPUBuffer(device, indexBufferInfo)

  let instanceBufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX,
    size: uint32(result.maxSprites * sizeof(SpriteInstance)),
    props: 0
  )
  result.instanceBuffer = createGPUBuffer(device, instanceBufferInfo)

  let transferInfo = GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(result.maxSprites * sizeof(SpriteInstance)),
    props: 0
  )
  result.instanceTransferBuffer = createGPUTransferBuffer(device, transferInfo)

  let primitiveVertexBufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX,
    size: uint32(result.maxPrimitiveVertices * sizeof(PrimitiveVertex)),
    props: 0
  )
  result.primitiveVertexBuffer = createGPUBuffer(device, primitiveVertexBufferInfo)

  let primitiveIndexBufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_INDEX,
    size: uint32(result.maxPrimitiveIndices * sizeof(uint32)),
    props: 0
  )
  result.primitiveIndexBuffer = createGPUBuffer(device, primitiveIndexBufferInfo)

  let primitiveVertexTransferInfo = GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(result.maxPrimitiveVertices * sizeof(PrimitiveVertex)),
    props: 0
  )
  result.primitiveVertexTransferBuffer = createGPUTransferBuffer(device, primitiveVertexTransferInfo)

  let primitiveIndexTransferInfo = GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(result.maxPrimitiveIndices * sizeof(uint32)),
    props: 0
  )
  result.primitiveIndexTransferBuffer = createGPUTransferBuffer(device, primitiveIndexTransferInfo)

  result.whiteTexture = createWhiteTexture(device)
  if result.defaultFontPath.len == 0:
    raise newException(Artist2DError, "Artist2D requires defaultFontPath for SDL3_ttf rendering")
  result.font = openFont(result.defaultFontPath, result.defaultFontSize)
  result.font.setStyle(defaultFontStyleBold)
  result.currentFontSize = int(result.defaultFontSize)
  let samplerInfo =
    if config.samplerInfo == default(GPUSamplerCreateInfo): defaultSamplerInfo() else: config.samplerInfo
  result.linearSampler = createGPUSampler(device, samplerInfo.samplerInfoForFilter(tfLinear))
  result.nearestSampler = createGPUSampler(device, samplerInfo.samplerInfoForFilter(tfNearest))
  result.registerTextureFilter(raw(result.whiteTexture), tfLinear)

  let quad = quadVertices()
  uploadBufferData(
    device,
    result.quadVertexBuffer,
    unsafeAddr quad[0],
    sizeof(quad),
    "artist2d quad vertex upload"
  )

  let indices = quadIndices()
  uploadBufferData(
    device,
    result.quadIndexBuffer,
    unsafeAddr indices[0],
    sizeof(indices),
    "artist2d quad index upload"
  )

  result.createPipeline(swapchainFormat)
  result.createPrimitivePipeline(swapchainFormat)

proc beginFrame*(artist: var Artist2D) =
  artist.instances.setLen(0)
  artist.batches.setLen(0)
  artist.primitiveVertices.setLen(0)
  artist.primitiveIndices.setLen(0)
  artist.primitiveBatches.setLen(0)
  artist.drawCommands.setLen(0)
  artist.currentBindings.setLen(0)
  artist.currentBatchStart = 0
  artist.currentBatchCount = 0
  artist.currentPrimitiveStart = 0
  artist.currentPrimitiveCount = 0
  artist.currentDrawMode = drawModeNone
  artist.currentScissor = QueuedScissor()

proc setScissor*(artist: var Artist2D; scissor: ScissorRect) =
  artist.setQueuedScissor(QueuedScissor(
    enabled: true,
    rect: ScissorRect(
      x: scissor.x,
      y: scissor.y,
      w: max(scissor.w, 0),
      h: max(scissor.h, 0)
    )
  ))

proc setScissor*(artist: var Artist2D; x, y, w, h: int) =
  artist.setScissor(ScissorRect(x: x, y: y, w: w, h: h))

proc clearScissor*(artist: var Artist2D) =
  artist.setQueuedScissor(QueuedScissor())

proc drawSprite*(artist: var Artist2D; sprite: Sprite2D): bool =
  if artist.currentDrawMode == drawModePrimitives:
    artist.finalizePrimitiveBatch()
  artist.currentDrawMode = drawModeSprites

  if artist.instances.len >= artist.maxSprites:
    return false

  let filterMode =
    if sprite.hasFilterOverride: sprite.filterMode
    else: artist.textureFilter(sprite.texture)
  let slot = artist.textureSlot(sprite.texture, filterMode)
  let region =
    if sprite.hasRegion: sprite.region
    else: fullRegion()

  artist.instances.add(SpriteInstance(
    position: sprite.position,
    size: sprite.size,
    scale: sprite.scale,
    origin: sprite.origin,
    uvRect: [region.u0, region.v0, region.u1, region.v1],
    tint: sprite.tint,
    rotation: sprite.rotation,
    textureIndex: cfloat(slot)
  ))
  inc artist.currentBatchCount
  true

proc canAddPrimitive(
  artist: Artist2D;
  verticesNeeded: int;
  indicesNeeded: int
): bool =
  artist.primitiveVertices.len + verticesNeeded <= artist.maxPrimitiveVertices and
    artist.primitiveIndices.len + indicesNeeded <= artist.maxPrimitiveIndices

proc beginPrimitiveGeometry(artist: var Artist2D) =
  if artist.currentDrawMode == drawModeSprites:
    artist.finalizeBatch()
  if artist.currentDrawMode != drawModePrimitives:
    artist.currentDrawMode = drawModePrimitives
    artist.currentPrimitiveStart = artist.primitiveIndices.len

proc addPrimitiveVertex(
  artist: var Artist2D;
  position: array[2, cfloat];
  tint: array[4, cfloat]
): uint32 =
  result = uint32(artist.primitiveVertices.len)
  artist.primitiveVertices.add(PrimitiveVertex(position: position, tint: tint))

proc addPrimitiveTriangleIndices(
  artist: var Artist2D;
  i0, i1, i2: uint32
) =
  artist.primitiveIndices.add(i0)
  artist.primitiveIndices.add(i1)
  artist.primitiveIndices.add(i2)
  artist.currentPrimitiveCount += 3

proc addColoredTriangle(
  artist: var Artist2D;
  p0, p1, p2: array[2, cfloat];
  tint: array[4, cfloat]
): bool =
  if not hasUsableTriangle(p0, p1, p2):
    return true
  if not artist.canAddPrimitive(3, 3):
    return false

  artist.beginPrimitiveGeometry()
  let base = artist.addPrimitiveVertex(p0, tint)
  discard artist.addPrimitiveVertex(p1, tint)
  discard artist.addPrimitiveVertex(p2, tint)
  artist.addPrimitiveTriangleIndices(base, base + 1, base + 2)
  true

proc addColoredQuad(
  artist: var Artist2D;
  p0, p1, p2, p3: array[2, cfloat];
  tint: array[4, cfloat]
): bool =
  if not artist.canAddPrimitive(4, 6):
    return false

  artist.beginPrimitiveGeometry()
  let base = artist.addPrimitiveVertex(p0, tint)
  discard artist.addPrimitiveVertex(p1, tint)
  discard artist.addPrimitiveVertex(p2, tint)
  discard artist.addPrimitiveVertex(p3, tint)
  artist.addPrimitiveTriangleIndices(base, base + 1, base + 2)
  artist.addPrimitiveTriangleIndices(base, base + 2, base + 3)
  true

proc drawFilledRect*(
  artist: var Artist2D;
  position: array[2, cfloat];
  size: array[2, cfloat];
  tint: array[4, cfloat]
): bool =
  let width = abs(size[0])
  let height = abs(size[1])
  if width <= 0 or height <= 0:
    return true

  let left = min(position[0], position[0] + size[0])
  let top = min(position[1], position[1] + size[1])
  let right = left + width
  let bottom = top + height
  artist.addColoredQuad(
    [left, top],
    [right, top],
    [right, bottom],
    [left, bottom],
    tint
  )

proc drawFilledRect*(
  artist: var Artist2D;
  position: array[2, cfloat];
  size: array[2, cfloat];
  tint: FColor
): bool =
  artist.drawFilledRect(position, size, primitiveColor(tint))

proc drawLine*(
  artist: var Artist2D;
  fromPos: array[2, cfloat];
  toPos: array[2, cfloat];
  tint: array[4, cfloat];
  thickness: cfloat = 1'f32
): bool =
  if thickness <= 0:
    return true

  let dx = toPos[0] - fromPos[0]
  let dy = toPos[1] - fromPos[1]
  let length = sqrt(dx * dx + dy * dy)
  if length <= 0.0001'f32:
    let half = thickness * 0.5'f32
    return artist.drawFilledRect(
      [fromPos[0] - half, fromPos[1] - half],
      [thickness, thickness],
      tint
    )

  let halfThickness = thickness * 0.5'f32
  let nx = -dy / length * halfThickness
  let ny = dx / length * halfThickness
  artist.addColoredQuad(
    [fromPos[0] - nx, fromPos[1] - ny],
    [fromPos[0] + nx, fromPos[1] + ny],
    [toPos[0] + nx, toPos[1] + ny],
    [toPos[0] - nx, toPos[1] - ny],
    tint
  )

proc drawLine*(
  artist: var Artist2D;
  fromPos: array[2, cfloat];
  toPos: array[2, cfloat];
  tint: FColor;
  thickness: cfloat = 1'f32
): bool =
  artist.drawLine(fromPos, toPos, primitiveColor(tint), thickness)

proc drawRect*(
  artist: var Artist2D;
  position: array[2, cfloat];
  size: array[2, cfloat];
  tint: array[4, cfloat];
  thickness: cfloat = 1'f32
): bool =
  let width = abs(size[0])
  let height = abs(size[1])
  if width <= 0 or height <= 0 or thickness <= 0:
    return true

  let left = min(position[0], position[0] + size[0])
  let top = min(position[1], position[1] + size[1])
  let right = left + width
  let bottom = top + height

  artist.drawLine([left, top], [right, top], tint, thickness) and
    artist.drawLine([right, top], [right, bottom], tint, thickness) and
    artist.drawLine([right, bottom], [left, bottom], tint, thickness) and
    artist.drawLine([left, bottom], [left, top], tint, thickness)

proc drawRect*(
  artist: var Artist2D;
  position: array[2, cfloat];
  size: array[2, cfloat];
  tint: FColor;
  thickness: cfloat = 1'f32
): bool =
  artist.drawRect(position, size, primitiveColor(tint), thickness)

proc drawTriangle*(
  artist: var Artist2D;
  p0, p1, p2: array[2, cfloat];
  tint: array[4, cfloat]
): bool =
  artist.addColoredTriangle(p0, p1, p2, tint)

proc drawTriangle*(
  artist: var Artist2D;
  p0, p1, p2: array[2, cfloat];
  tint: FColor
): bool =
  artist.drawTriangle(p0, p1, p2, primitiveColor(tint))

proc drawCircle*(
  artist: var Artist2D;
  center: array[2, cfloat];
  radius: cfloat;
  tint: array[4, cfloat]
): bool =
  let segments = primitiveCircleSegmentCount(radius)
  if segments <= 0:
    return true
  if not artist.canAddPrimitive(segments + 1, segments * 3):
    return false

  artist.beginPrimitiveGeometry()
  let centerIndex = artist.addPrimitiveVertex(center, tint)
  let angleStep = 2'f32 * PI.cfloat / cfloat(segments)
  var firstOuterIndex = uint32(0)
  var previousOuterIndex = uint32(0)

  for i in 0 ..< segments:
    let angle = cfloat(i) * angleStep
    let point = [
      center[0] + cos(angle) * radius,
      center[1] + sin(angle) * radius
    ]
    let outerIndex = artist.addPrimitiveVertex(point, tint)
    if i == 0:
      firstOuterIndex = outerIndex
    else:
      artist.addPrimitiveTriangleIndices(centerIndex, previousOuterIndex, outerIndex)
    previousOuterIndex = outerIndex

  artist.addPrimitiveTriangleIndices(centerIndex, previousOuterIndex, firstOuterIndex)
  true

proc drawCircle*(
  artist: var Artist2D;
  center: array[2, cfloat];
  radius: cfloat;
  tint: FColor
): bool =
  artist.drawCircle(center, radius, primitiveColor(tint))

proc drawRing*(
  artist: var Artist2D;
  center: array[2, cfloat];
  radius: cfloat;
  tint: array[4, cfloat];
  thickness: cfloat = 1'f32
): bool =
  if radius <= 0 or thickness <= 0:
    return true
  if thickness >= radius:
    return artist.drawCircle(center, radius, tint)

  let segments = primitiveCircleSegmentCount(radius)
  if segments <= 0:
    return true
  if not artist.canAddPrimitive(segments * 2, segments * 6):
    return false

  artist.beginPrimitiveGeometry()
  let angleStep = 2'f32 * PI.cfloat / cfloat(segments)
  let innerRadius = radius - thickness
  var firstOuterIndex = uint32(0)
  var firstInnerIndex = uint32(0)
  var previousOuterIndex = uint32(0)
  var previousInnerIndex = uint32(0)

  for i in 0 ..< segments:
    let angle = cfloat(i) * angleStep
    let unit = [cos(angle), sin(angle)]
    let outerPoint = [
      center[0] + unit[0] * radius,
      center[1] + unit[1] * radius
    ]
    let innerPoint = [
      center[0] + unit[0] * innerRadius,
      center[1] + unit[1] * innerRadius
    ]
    let outerIndex = artist.addPrimitiveVertex(outerPoint, tint)
    let innerIndex = artist.addPrimitiveVertex(innerPoint, tint)
    if i == 0:
      firstOuterIndex = outerIndex
      firstInnerIndex = innerIndex
    else:
      artist.addPrimitiveTriangleIndices(previousOuterIndex, previousInnerIndex, outerIndex)
      artist.addPrimitiveTriangleIndices(outerIndex, previousInnerIndex, innerIndex)
    previousOuterIndex = outerIndex
    previousInnerIndex = innerIndex

  artist.addPrimitiveTriangleIndices(previousOuterIndex, previousInnerIndex, firstOuterIndex)
  artist.addPrimitiveTriangleIndices(firstOuterIndex, previousInnerIndex, firstInnerIndex)
  true

proc drawRing*(
  artist: var Artist2D;
  center: array[2, cfloat];
  radius: cfloat;
  tint: FColor;
  thickness: cfloat = 1'f32
): bool =
  artist.drawRing(center, radius, primitiveColor(tint), thickness)

proc drawText*(
  artist: var Artist2D;
  text: string;
  position: array[2, cfloat];
  tint: array[4, cfloat] = [1'f32, 1'f32, 1'f32, 1'f32];
  scale: cfloat = 1.0
): bool {.gcsafe.} =
  if scale <= 0 or text.len == 0:
    return true

  let entry = artist.cacheTextTexture(text, artist.fontPixelSize(scale))
  var sprite = initSprite2D()
  sprite.position = position
  sprite.size = [entry.width.cfloat, entry.height.cfloat]
  sprite.scale = [1'f32, 1'f32]
  sprite.origin = [0'f32, 0'f32]
  sprite.tint = tint
  sprite.texture = entry.texture
  artist.drawSprite(sprite)

proc uploadInstances(artist: var Artist2D; commandBuffer: ptr GPUCommandBuffer) =
  if artist.instances.len <= 0:
    return

  let byteCount = artist.instances.len * sizeof(SpriteInstance)
  let mapped = mapGPUTransferBuffer(artist.device, artist.instanceTransferBuffer, true)
  copyMem(mapped, unsafeAddr artist.instances[0], byteCount)
  unmapGPUTransferBuffer(artist.device, artist.instanceTransferBuffer)

  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(Artist2DError, "beginGPUCopyPass failed: " & $getError())

  var source = GPUTransferBufferLocation(
    transfer_buffer: raw(artist.instanceTransferBuffer),
    offset: 0
  )
  var destination = GPUBufferRegion(
    buffer: raw(artist.instanceBuffer),
    offset: 0,
    size: uint32(byteCount)
  )
  uploadToGPUBuffer(copyPass, addr source, addr destination, true)
  endGPUCopyPass(copyPass)

proc uploadPrimitives(artist: var Artist2D; commandBuffer: ptr GPUCommandBuffer) =
  if artist.primitiveVertices.len <= 0 or artist.primitiveIndices.len <= 0:
    return

  let vertexBytes = artist.primitiveVertices.len * sizeof(PrimitiveVertex)
  let mappedVertices = mapGPUTransferBuffer(artist.device, artist.primitiveVertexTransferBuffer, true)
  copyMem(mappedVertices, unsafeAddr artist.primitiveVertices[0], vertexBytes)
  unmapGPUTransferBuffer(artist.device, artist.primitiveVertexTransferBuffer)

  let indexBytes = artist.primitiveIndices.len * sizeof(uint32)
  let mappedIndices = mapGPUTransferBuffer(artist.device, artist.primitiveIndexTransferBuffer, true)
  copyMem(mappedIndices, unsafeAddr artist.primitiveIndices[0], indexBytes)
  unmapGPUTransferBuffer(artist.device, artist.primitiveIndexTransferBuffer)

  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(Artist2DError, "beginGPUCopyPass failed: " & $getError())

  var vertexSource = GPUTransferBufferLocation(
    transfer_buffer: raw(artist.primitiveVertexTransferBuffer),
    offset: 0
  )
  var vertexDestination = GPUBufferRegion(
    buffer: raw(artist.primitiveVertexBuffer),
    offset: 0,
    size: uint32(vertexBytes)
  )
  uploadToGPUBuffer(copyPass, addr vertexSource, addr vertexDestination, true)

  var indexSource = GPUTransferBufferLocation(
    transfer_buffer: raw(artist.primitiveIndexTransferBuffer),
    offset: 0
  )
  var indexDestination = GPUBufferRegion(
    buffer: raw(artist.primitiveIndexBuffer),
    offset: 0,
    size: uint32(indexBytes)
  )
  uploadToGPUBuffer(copyPass, addr indexSource, addr indexDestination, true)
  endGPUCopyPass(copyPass)

proc render*(
  artist: var Artist2D,
  commandBuffer: ptr GPUCommandBuffer,
  targetTexture: ptr GPUTexture,
  targetWidth: uint32,
  targetHeight: uint32,
  clearColor: FColor = FColor(r: 0.08, g: 0.10, b: 0.13, a: 1.0),
  loadOp: RenderTargetLoadOp = renderTargetClear
) =
  case artist.currentDrawMode
  of drawModeSprites:
    artist.finalizeBatch()
  of drawModePrimitives:
    artist.finalizePrimitiveBatch()
  of drawModeNone:
    discard
  artist.uploadInstances(commandBuffer)
  artist.uploadPrimitives(commandBuffer)

  let projection = orthoProjection(targetWidth, targetHeight)
  pushGPUVertexUniformData(
    commandBuffer,
    0,
    unsafeAddr projection[0],
    uint32(sizeof(projection))
  )

  var colorTarget = GPUColorTargetInfo(
    texture: targetTexture,
    mip_level: 0,
    layer_or_depth_plane: 0,
    clear_color: clearColor,
    load_op:
      if loadOp == renderTargetClear:
        gpuLoadOpClear
      else:
        gpuLoadOpLoad,
    store_op: gpuStoreOpStore,
    resolve_texture: nil,
    resolve_mip_level: 0,
    resolve_layer: 0,
    cycle: false,
    cycle_resolve_texture: false
  )

  let renderPass = beginGPURenderPass(commandBuffer, addr colorTarget, 1, nil)
  if renderPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(Artist2DError, "beginGPURenderPass failed: " & $getError())

  var fullScissor = Rect(
    x: 0,
    y: 0,
    w: cint(targetWidth),
    h: cint(targetHeight)
  )
  setGPUScissor(renderPass, addr fullScissor)
  var activeScissor = QueuedScissor()

  var vertexBindings = [
    GPUBufferBinding(buffer: raw(artist.quadVertexBuffer), offset: 0),
    GPUBufferBinding(buffer: raw(artist.instanceBuffer), offset: 0)
  ]
  var indexBinding = GPUBufferBinding(buffer: raw(artist.quadIndexBuffer), offset: 0)
  var primitiveVertexBinding = GPUBufferBinding(buffer: raw(artist.primitiveVertexBuffer), offset: 0)
  var primitiveIndexBinding = GPUBufferBinding(buffer: raw(artist.primitiveIndexBuffer), offset: 0)

  proc applyScissor(scissor: QueuedScissor) =
    if scissor == activeScissor:
      return
    var rect =
      if scissor.enabled:
        Rect(
          x: cint(scissor.rect.x),
          y: cint(scissor.rect.y),
          w: cint(scissor.rect.w),
          h: cint(scissor.rect.h)
        )
      else:
        fullScissor
    setGPUScissor(renderPass, addr rect)
    activeScissor = scissor

  for command in artist.drawCommands:
    applyScissor(command.scissor)
    case command.mode
    of drawModeSprites:
      let batch = artist.batches[int(command.batchIndex)]
      bindGPUGraphicsPipeline(renderPass, raw(artist.pipeline))
      bindGPUVertexBuffers(renderPass, 0, addr vertexBindings[0], uint32(vertexBindings.len))
      bindGPUIndexBuffer(renderPass, addr indexBinding, gpuIndexElementSize16Bit)

      var samplers: array[maxShaderTextureSlots, GPUTextureSamplerBinding]
      for i in 0 ..< maxShaderTextureSlots:
        samplers[i] = GPUTextureSamplerBinding(
          texture: batch.textures[i],
          sampler:
            if batch.filterModes[i] == tfNearest:
              raw(artist.nearestSampler)
            else:
              raw(artist.linearSampler)
        )
      bindGPUFragmentSamplers(renderPass, 0, addr samplers[0], uint32(samplers.len))
      drawGPUIndexedPrimitives(
        renderPass,
        6,
        batch.instanceCount,
        0,
        0,
        batch.firstInstance
      )
    of drawModePrimitives:
      let batch = artist.primitiveBatches[int(command.batchIndex)]
      bindGPUGraphicsPipeline(renderPass, raw(artist.primitivePipeline))
      bindGPUVertexBuffers(renderPass, 0, addr primitiveVertexBinding, 1)
      bindGPUIndexBuffer(renderPass, addr primitiveIndexBinding, gpuIndexElementSize32Bit)
      drawGPUIndexedPrimitives(
        renderPass,
        batch.indexCount,
        1,
        batch.firstIndex,
        0,
        0
      )
    of drawModeNone:
      discard

  endGPURenderPass(renderPass)

proc whiteSpriteTexture*(artist: Artist2D): SpriteTexture =
  raw(artist.whiteTexture)

proc createSpriteTexture*(
  artist: var Artist2D;
  width: int;
  height: int;
  pixels: openArray[uint8];
  filterMode: TextureFilterMode = tfLinear
): GPUTextureHandle {.gcsafe.} =
  if width <= 0 or height <= 0:
    raise newException(Artist2DError, "Sprite texture dimensions must be positive")
  if pixels.len != width * height * 4:
    raise newException(Artist2DError, "Sprite textures require tightly packed RGBA8 pixels")

  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER,
    width: uint32(width),
    height: uint32(height),
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  result = createGPUTexture(artist.device, textureInfo)
  uploadTexture2DData(artist.device, result, width, height, pixels, "artist2d texture upload")
  artist.registerTextureFilter(raw(result), filterMode)
