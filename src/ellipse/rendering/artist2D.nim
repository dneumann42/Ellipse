import std/[math, os, strutils]

import ../platform/SDL3
import ../platform/SDL3gpu
import ../platform/SDL3gpuext
import ./[gpupipelines, gpushaders, gpuuploads]

type
  Artist2DError* = object of CatchableError

  SpriteTexture* = ptr GPUTexture

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
    region*: SpriteTextureRegion
    hasRegion*: bool

  Artist2DConfig* = object
    maxSprites*: int
    maxTextureSlots*: int
    vertexShaderPath*: string
    fragmentShaderPath*: string
    samplerInfo*: GPUSamplerCreateInfo

  Artist2D* = object
    device*: GPUDeviceHandle
    pipeline*: GPUGraphicsPipelineHandle
    vertexShader*: GPUShaderHandle
    fragmentShader*: GPUShaderHandle
    quadVertexBuffer*: GPUBufferHandle
    quadIndexBuffer*: GPUBufferHandle
    instanceBuffer*: GPUBufferHandle
    instanceTransferBuffer*: GPUTransferBufferHandle
    whiteTexture*: GPUTextureHandle
    fontTexture*: GPUTextureHandle
    sampler*: GPUSamplerHandle
    maxSprites*: int
    maxTextureSlots*: int
    instances: seq[SpriteInstance]
    batches: seq[SpriteBatch]
    currentBatchStart: int
    currentBatchCount: int
    currentTextures: seq[ptr GPUTexture]

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

  Mat4 = array[16, cfloat]

const
  maxShaderTextureSlots = 8
  shaderDir = currentSourcePath.parentDir / "shaders"
  firstPrintableAscii = 32
  lastPrintableAscii = 126
  fontGlyphWidth* = 8
  fontGlyphHeight* = 8
  fontGlyphAdvance* = 8
  fontAtlasColumns = 16
  fontAtlasRows = 6
  fontAtlasWidth = fontAtlasColumns * fontGlyphWidth
  fontAtlasHeight = fontAtlasRows * fontGlyphHeight

proc defaultVertexShaderPath*(): string =
  shaderDir / "sprites.vert.spv"

proc defaultFragmentShaderPath*(): string =
  shaderDir / "sprites.frag.spv"

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

proc initSprite2D*(): Sprite2D =
  Sprite2D(
    position: [0'f32, 0'f32],
    size: [1'f32, 1'f32],
    scale: [1'f32, 1'f32],
    origin: [0.5'f32, 0.5'f32],
    rotation: 0,
    tint: [1'f32, 1'f32, 1'f32, 1'f32],
    texture: nil,
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

proc glyphRows(ch: char): array[7, uint8] =
  case ch.toUpperAscii
  of 'A': [0b01110'u8, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
  of 'B': [0b11110'u8, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]
  of 'C': [0b01110'u8, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]
  of 'D': [0b11110'u8, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]
  of 'E': [0b11111'u8, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111]
  of 'F': [0b11111'u8, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]
  of 'G': [0b01110'u8, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110]
  of 'H': [0b10001'u8, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
  of 'I': [0b11111'u8, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111]
  of 'J': [0b00001'u8, 0b00001, 0b00001, 0b00001, 0b10001, 0b10001, 0b01110]
  of 'K': [0b10001'u8, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001]
  of 'L': [0b10000'u8, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111]
  of 'M': [0b10001'u8, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]
  of 'N': [0b10001'u8, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]
  of 'O': [0b01110'u8, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
  of 'P': [0b11110'u8, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000]
  of 'Q': [0b01110'u8, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101]
  of 'R': [0b11110'u8, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001]
  of 'S': [0b01111'u8, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110]
  of 'T': [0b11111'u8, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]
  of 'U': [0b10001'u8, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
  of 'V': [0b10001'u8, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100]
  of 'W': [0b10001'u8, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010]
  of 'X': [0b10001'u8, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001]
  of 'Y': [0b10001'u8, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100]
  of 'Z': [0b11111'u8, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111]
  of '0': [0b01110'u8, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110]
  of '1': [0b00100'u8, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]
  of '2': [0b01110'u8, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]
  of '3': [0b11110'u8, 0b00001, 0b00001, 0b00110, 0b00001, 0b00001, 0b11110]
  of '4': [0b00010'u8, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]
  of '5': [0b11111'u8, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110]
  of '6': [0b00110'u8, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]
  of '7': [0b11111'u8, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]
  of '8': [0b01110'u8, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]
  of '9': [0b01110'u8, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b11100]
  of ':': [0b00000'u8, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000]
  of '.': [0b00000'u8, 0b00000, 0b00000, 0b00000, 0b00000, 0b00110, 0b00110]
  of '-': [0b00000'u8, 0b00000, 0b00000, 0b01110, 0b00000, 0b00000, 0b00000]
  of '/': [0b00001'u8, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000, 0b00000]
  of '+': [0b00000'u8, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000]
  of '(': [0b00010'u8, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010]
  of ')': [0b01000'u8, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000]
  of '[': [0b01110'u8, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110]
  of ']': [0b01110'u8, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110]
  of '=': [0b00000'u8, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000]
  of ' ': [0'u8, 0, 0, 0, 0, 0, 0]
  else: [0b01110'u8, 0b10001, 0b00010, 0b00100, 0b00100, 0b00000, 0b00100]

proc atlasIndex(ch: char): int =
  let code =
    if ch.ord < firstPrintableAscii or ch.ord > lastPrintableAscii:
      '?'.ord
    else:
      ch.ord
  code - firstPrintableAscii

proc fontRegion(ch: char): SpriteTextureRegion =
  let index = atlasIndex(ch)
  let column = index mod fontAtlasColumns
  let row = index div fontAtlasColumns
  spriteTextureRegion(
    cfloat(column * fontGlyphWidth) / cfloat(fontAtlasWidth),
    cfloat(row * fontGlyphHeight) / cfloat(fontAtlasHeight),
    cfloat((column + 1) * fontGlyphWidth) / cfloat(fontAtlasWidth),
    cfloat((row + 1) * fontGlyphHeight) / cfloat(fontAtlasHeight)
  )

proc createFontTexture(device: GPUDeviceHandle): GPUTextureHandle =
  var pixels = newSeq[uint8](fontAtlasWidth * fontAtlasHeight * 4)
  for code in firstPrintableAscii .. lastPrintableAscii:
    let index = code - firstPrintableAscii
    let column = index mod fontAtlasColumns
    let row = index div fontAtlasColumns
    let baseX = column * fontGlyphWidth
    let baseY = row * fontGlyphHeight
    let rows = glyphRows(char(code))
    for y in 0 ..< 7:
      let bits = rows[y]
      for x in 0 ..< 5:
        if (bits and (1'u8 shl (4 - x))) == 0:
          continue
        let dstX = baseX + x + 1
        let dstY = baseY + y
        let offset = (dstY * fontAtlasWidth + dstX) * 4
        pixels[offset + 0] = 255
        pixels[offset + 1] = 255
        pixels[offset + 2] = 255
        pixels[offset + 3] = 255

  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER,
    width: uint32(fontAtlasWidth),
    height: uint32(fontAtlasHeight),
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  result = createGPUTexture(device, textureInfo)
  uploadTexture2DData(
    device,
    result,
    fontAtlasWidth,
    fontAtlasHeight,
    pixels,
    "artist2d font texture"
  )

proc finalizeBatch(artist: var Artist2D) =
  if artist.currentBatchCount <= 0:
    return

  var batch = SpriteBatch(
    firstInstance: uint32(artist.currentBatchStart),
    instanceCount: uint32(artist.currentBatchCount)
  )
  for i in 0 ..< artist.maxTextureSlots:
    batch.textures[i] =
      if i < artist.currentTextures.len: artist.currentTextures[i]
      else: raw(artist.whiteTexture)
  artist.batches.add(batch)
  artist.currentBatchStart = artist.instances.len
  artist.currentBatchCount = 0
  artist.currentTextures.setLen(0)

proc textureSlot(artist: var Artist2D; texture: ptr GPUTexture): int =
  let resolvedTexture =
    if texture.isNil: raw(artist.whiteTexture)
    else: texture

  for i, entry in artist.currentTextures:
    if entry == resolvedTexture:
      return i

  if artist.currentTextures.len >= artist.maxTextureSlots:
    artist.finalizeBatch()
  for i, entry in artist.currentTextures:
    if entry == resolvedTexture:
      return i

  artist.currentTextures.add(resolvedTexture)
  artist.currentTextures.len - 1

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
  result.instances = newSeqOfCap[SpriteInstance](result.maxSprites)
  result.batches = newSeqOfCap[SpriteBatch](max(1, result.maxSprites div 256))
  result.currentTextures = newSeqOfCap[ptr GPUTexture](result.maxTextureSlots)

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

  result.whiteTexture = createWhiteTexture(device)
  result.fontTexture = createFontTexture(device)
  result.sampler = createGPUSampler(
    device,
    if config.samplerInfo == default(GPUSamplerCreateInfo): defaultSamplerInfo() else: config.samplerInfo
  )

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

proc beginFrame*(artist: var Artist2D) =
  artist.instances.setLen(0)
  artist.batches.setLen(0)
  artist.currentTextures.setLen(0)
  artist.currentBatchStart = 0
  artist.currentBatchCount = 0

proc drawSprite*(artist: var Artist2D; sprite: Sprite2D): bool =
  if artist.instances.len >= artist.maxSprites:
    return false

  let slot = artist.textureSlot(sprite.texture)
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

proc drawText*(
  artist: var Artist2D;
  text: string;
  position: array[2, cfloat];
  tint: array[4, cfloat] = [1'f32, 1'f32, 1'f32, 1'f32];
  scale: cfloat = 1.0
): bool =
  if scale <= 0:
    return true

  let lineAdvance = cfloat(fontGlyphHeight) * scale
  let glyphAdvance = cfloat(fontGlyphAdvance) * scale
  let glyphSize = [cfloat(fontGlyphWidth), cfloat(fontGlyphHeight)]
  var cursor = position

  for ch in text:
    case ch
    of '\n':
      cursor[0] = position[0]
      cursor[1] += lineAdvance
      continue
    of '\r':
      continue
    else:
      var sprite = initSprite2D()
      sprite.position = cursor
      sprite.size = glyphSize
      sprite.scale = [scale, scale]
      sprite.origin = [0'f32, 0'f32]
      sprite.tint = tint
      sprite.texture = raw(artist.fontTexture)
      sprite.region = fontRegion(ch)
      sprite.hasRegion = true
      if not artist.drawSprite(sprite):
        return false
      cursor[0] += glyphAdvance

  true

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

proc render*(
  artist: var Artist2D,
  commandBuffer: ptr GPUCommandBuffer,
  targetTexture: ptr GPUTexture,
  targetWidth: uint32,
  targetHeight: uint32,
  clearColor: FColor = FColor(r: 0.08, g: 0.10, b: 0.13, a: 1.0)
) =
  artist.finalizeBatch()
  artist.uploadInstances(commandBuffer)

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
    load_op: gpuLoadOpClear,
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

  var vertexBindings = [
    GPUBufferBinding(buffer: raw(artist.quadVertexBuffer), offset: 0),
    GPUBufferBinding(buffer: raw(artist.instanceBuffer), offset: 0)
  ]
  var indexBinding = GPUBufferBinding(buffer: raw(artist.quadIndexBuffer), offset: 0)

  bindGPUGraphicsPipeline(renderPass, raw(artist.pipeline))
  bindGPUVertexBuffers(renderPass, 0, addr vertexBindings[0], uint32(vertexBindings.len))
  bindGPUIndexBuffer(renderPass, addr indexBinding, gpuIndexElementSize16Bit)

  for batch in artist.batches:
    var samplers: array[maxShaderTextureSlots, GPUTextureSamplerBinding]
    for i in 0 ..< maxShaderTextureSlots:
      samplers[i] = GPUTextureSamplerBinding(
        texture: batch.textures[i],
        sampler: raw(artist.sampler)
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

  endGPURenderPass(renderPass)

proc whiteSpriteTexture*(artist: Artist2D): SpriteTexture =
  raw(artist.whiteTexture)

proc createSpriteTexture*(
  artist: Artist2D;
  width: int;
  height: int;
  pixels: openArray[uint8]
): GPUTextureHandle =
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
