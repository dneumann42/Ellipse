import std/[math, os, tables]

import vmath

import ../platform/SDL3
import ../platform/SDL3gpu
import ../platform/SDL3gpuext
import ./[artist2D, gpupipelines, gpushaders, gpuuploads, gridlighting, shadowmapping]

type
  Artist3DError* = object of CatchableError

  Texture3D* = ptr GPUTexture
  CubeTexture* = ptr GPUTexture

  QuadUvs* = object
    u0*, v0*, u1*, v1*: cfloat

  Vertex3D* = object
    position*: Vec3
    uv*: Vec2
    normal*: Vec3
    color*: Vec4
    textureIndex*: cfloat
    lightingPosition*: Vec3

  Artist3DConfig* = object
    maxQuads*: int
    maxTextureSlots*: int
    vertexShaderPath*: string
    fragmentShaderPath*: string
    shadowVertexShaderPath*: string
    shadowFragmentShaderPath*: string
    samplerInfo*: GPUSamplerCreateInfo

  Artist3D* = object
    device*: GPUDeviceHandle
    pipeline*: GPUGraphicsPipelineHandle
    overlayPipeline*: GPUGraphicsPipelineHandle
    vertexShader*: GPUShaderHandle
    fragmentShader*: GPUShaderHandle
    shadowVertexShader*: GPUShaderHandle
    shadowFragmentShader*: GPUShaderHandle
    vertexBuffer*: GPUBufferHandle
    indexBuffer*: GPUBufferHandle
    vertexTransferBuffer*: GPUTransferBufferHandle
    indexTransferBuffer*: GPUTransferBufferHandle
    whiteTexture*: GPUTextureHandle
    whiteCubeTexture*: GPUTextureHandle
    linearSampler*: GPUSamplerHandle
    nearestSampler*: GPUSamplerHandle
    shadowSampler*: GPUSamplerHandle
    shadowCubeSampler*: GPUSamplerHandle
    depthTexture*: GPUTextureHandle
    depthWidth*: uint32
    depthHeight*: uint32
    depthFormat*: GPUTextureFormat
    shadowPipeline*: GPUGraphicsPipelineHandle
    shadowFormat*: GPUTextureFormat
    shadowCascadeTextures*: array[3, GPUTextureHandle]
    shadowCascadeDepthTexture*: GPUTextureHandle
    shadowCascadeResolution*: uint32
    pointShadowTextures*: array[2, GPUTextureHandle]
    pointShadowDepthTexture*: GPUTextureHandle
    pointShadowResolution*: uint32
    maxQuads*: int
    maxTextureSlots*: int
    projection*: Mat4
    view*: Mat4
    clipNear*: float32
    clipFar*: float32
    model*: Mat4
    color*: Vec4
    normal*: Vec3
    texture*: Texture3D
    filterMode*: TextureFilterMode
    gridLightingTexture*: Texture3D
    gridLightingInfo*: GridLightTextureInfo
    gridLightingEnabled*: bool
    environmentClearEnabled*: bool
    environmentClearColor*: FColor
    ambientColor*: Vec3
    sunDirection*: Vec3
    sunColor*: Vec3
    sunIntensity*: float32
    sunEnabled*: bool
    shadowConfig*: ShadowRenderConfig
    pointLights*: seq[ShadowPointLight]
    fogTint*: Vec3
    fogDensity*: float32
    cameraPosition*: Vec3
    shadowBoundsMin*: Vec3
    shadowBoundsMax*: Vec3
    shadowBoundsEnabled*: bool
    vertices: seq[Vertex3D]
    indices: seq[uint32]
    batches: seq[Batch3D]
    currentBindings: seq[TextureBinding3D]
    currentBatchStart: int
    currentBatchCount: int
    depthTestEnabled: bool
    sceneLightingEnabled: bool
    shadowCastingEnabled: bool
    modelStack: seq[Mat4]
    textureFilters: Table[ptr GPUTexture, TextureFilterMode]

  Batch3D = object
    firstIndex: uint32
    indexCount: uint32
    depthTestEnabled: bool
    sceneLightingEnabled: bool
    shadowCastingEnabled: bool
    textures: array[8, ptr GPUTexture]
    filterModes: array[8, TextureFilterMode]

  TextureBinding3D = object
    texture: ptr GPUTexture
    filterMode: TextureFilterMode

  FrameUniforms = object
    projection: Mat4
    view: Mat4

  GridLightingUniforms = object
    sunShadowMatrices: array[3, Mat4]
    cascadeSplits: Vec4
    sunShadowTexelSize: array[3, Vec4]
    ambientColor: Vec4
    textureSize: Vec4
    sunDirectionIntensity: Vec4
    sunColorEnabled: Vec4
    sunShadowParams: Vec4
    pointShadowParams: Vec4
    pointLightPositionRadius: array[8, Vec4]
    pointLightColorIntensity: array[8, Vec4]
    pointLightFalloffShadow: array[8, Vec4]
    fogTintDensity: Vec4
    cameraPosition: Vec4

  BatchLightingUniforms = object
    flags: Vec4

  ShadowPassVertexUniforms = object
    viewProjection: Mat4

  ShadowPassFragmentUniforms = object
    lightPositionFarMode: Vec4

const
  maxShaderTextureSlots = 8
  gridLightSamplerSlot = maxShaderTextureSlots
  sunShadowSamplerSlot = gridLightSamplerSlot
  pointShadowSamplerSlot = sunShadowSamplerSlot + 3
  maxSunShadowCascades = 3
  maxShadowedPointLights = 2
  maxForwardPointLights = 8
  shaderDir = currentSourcePath.parentDir / "shaders"

proc default3DVertexShaderPath*(): string =
  shaderDir / "solid3d.vert.spv"

proc default3DFragmentShaderPath*(): string =
  shaderDir / "solid3d.frag.spv"

proc default3DShadowVertexShaderPath*(): string =
  shaderDir / "shadow3d.vert.spv"

proc default3DShadowFragmentShaderPath*(): string =
  shaderDir / "shadow3d.frag.spv"

proc defaultQuadUvs*(): QuadUvs =
  QuadUvs(u0: 0, v0: 0, u1: 1, v1: 1)

proc identityMat4(): Mat4 =
  mat4()

proc uniformsPointer(value: var FrameUniforms): pointer =
  cast[pointer](addr value)

proc lightingUniformsPointer(value: var GridLightingUniforms): pointer =
  cast[pointer](addr value)

proc batchLightingUniformsPointer(value: var BatchLightingUniforms): pointer =
  cast[pointer](addr value)

proc shadowPassVertexUniformsPointer(value: var ShadowPassVertexUniforms): pointer =
  cast[pointer](addr value)

proc shadowPassFragmentUniformsPointer(value: var ShadowPassFragmentUniforms): pointer =
  cast[pointer](addr value)

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

proc defaultSamplerInfo(): GPUSamplerCreateInfo =
  GPUSamplerCreateInfo(
    min_filter: gpuFilterLinear,
    mag_filter: gpuFilterLinear,
    mipmap_mode: gpuSamplerMipmapModeNearest,
    address_mode_u: gpuSamplerAddressModeRepeat,
    address_mode_v: gpuSamplerAddressModeRepeat,
    address_mode_w: gpuSamplerAddressModeRepeat,
    mip_lod_bias: 0,
    max_anisotropy: 1,
    compare_op: gpuCompareOpInvalid,
    min_lod: 0,
    max_lod: 0,
    enable_anisotropy: false,
    enable_compare: false,
    props: 0
  )

proc registerTextureFilter(
  artist: var Artist3D;
  texture: ptr GPUTexture;
  filterMode: TextureFilterMode
) =
  if texture.isNil:
    return
  artist.textureFilters[texture] = filterMode

proc textureFilter(artist: Artist3D; texture: ptr GPUTexture): TextureFilterMode =
  if texture.isNil:
    return tfLinear
  if artist.textureFilters.hasKey(texture):
    return artist.textureFilters[texture]
  artist.filterMode

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
  uploadTexture2DData(device, result, 1, 1, pixels, "artist3d white texture")

proc createWhiteCubeTexture(device: GPUDeviceHandle): GPUTextureHandle =
  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureTypeCube,
    format: GPU_TEXTUREFORMAT_R16_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER or GPU_TEXTUREUSAGE_COLOR_TARGET,
    width: 1,
    height: 1,
    layer_count_or_depth: 6,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  result = createGPUTexture(device, textureInfo)

proc createShadowMapTexture(
  device: GPUDeviceHandle;
  width, height: uint32;
  format: GPUTextureFormat
): GPUTextureHandle =
  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: format,
    usage: GPU_TEXTUREUSAGE_SAMPLER or GPU_TEXTUREUSAGE_COLOR_TARGET,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  createGPUTexture(device, textureInfo)

proc createShadowCubeTexture(
  device: GPUDeviceHandle;
  size: uint32;
  format: GPUTextureFormat
): GPUTextureHandle =
  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureTypeCube,
    format: format,
    usage: GPU_TEXTUREUSAGE_SAMPLER or GPU_TEXTUREUSAGE_COLOR_TARGET,
    width: size,
    height: size,
    layer_count_or_depth: 6,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  createGPUTexture(device, textureInfo)

proc finalizeBatch(artist: var Artist3D) {.gcsafe.}

proc textureSlot(
  artist: var Artist3D;
  texture: ptr GPUTexture;
  filterMode: TextureFilterMode
): int {.gcsafe.} =
  let resolved = TextureBinding3D(
    texture:
      if texture.isNil: raw(artist.whiteTexture)
      else: texture,
    filterMode: filterMode
  )

  for i, entry in artist.currentBindings:
    if entry == resolved:
      return i

  if artist.currentBindings.len >= artist.maxTextureSlots:
    artist.finalizeBatch()
  for i, entry in artist.currentBindings:
    if entry == resolved:
      return i

  artist.currentBindings.add(resolved)
  artist.currentBindings.len - 1

proc finalizeBatch(artist: var Artist3D) {.gcsafe.} =
  if artist.currentBatchCount <= 0:
    return

  var batch = Batch3D(
    firstIndex: uint32(artist.currentBatchStart),
    indexCount: uint32(artist.currentBatchCount),
    depthTestEnabled: artist.depthTestEnabled,
    sceneLightingEnabled: artist.sceneLightingEnabled,
    shadowCastingEnabled: artist.shadowCastingEnabled
  )
  for i in 0 ..< artist.maxTextureSlots:
    if i < artist.currentBindings.len:
      batch.textures[i] = artist.currentBindings[i].texture
      batch.filterModes[i] = artist.currentBindings[i].filterMode
    else:
      batch.textures[i] = raw(artist.whiteTexture)
      batch.filterModes[i] = tfLinear
  artist.batches.add(batch)
  artist.currentBatchStart = artist.indices.len
  artist.currentBatchCount = 0
  artist.currentBindings.setLen(0)

proc canAdd(artist: Artist3D; verticesNeeded, indicesNeeded: int): bool =
  artist.vertices.len + verticesNeeded <= artist.maxQuads * 4 and
    artist.indices.len + indicesNeeded <= artist.maxQuads * 6

proc transformPoint(model: Mat4; point: Vec3): Vec3 =
  let p = model * vec4(point, 1'f32)
  if abs(p.w) > 0.00001'f32:
    vec3(p.x / p.w, p.y / p.w, p.z / p.w)
  else:
    p.xyz

proc transformNormal(model: Mat4; normal: Vec3): Vec3 =
  let n = model * vec4(normal, 0'f32)
  let transformed = n.xyz
  if lengthSq(transformed) <= 0.000001'f32:
    normal
  else:
    normalize(transformed)

proc faceNormal(p0, p1, p2: Vec3): Vec3 =
  let n = cross(p1 - p0, p2 - p0)
  if lengthSq(n) <= 0.000001'f32:
    vec3(0'f32, 0'f32, 1'f32)
  else:
    normalize(n)

proc createDepthTexture(
  device: GPUDeviceHandle;
  width, height: uint32;
  format: GPUTextureFormat
): GPUTextureHandle =
  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: format,
    usage: GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  createGPUTexture(device, textureInfo)

proc ensureShadowCascadeResources(artist: var Artist3D; resolution: uint32) =
  let size = max(resolution, 1'u32)
  if raw(artist.shadowCascadeDepthTexture).isNil or artist.shadowCascadeResolution != size:
    reset(artist.shadowCascadeDepthTexture)
    for texture in artist.shadowCascadeTextures.mitems:
      reset(texture)
    artist.shadowCascadeDepthTexture = createDepthTexture(artist.device, size, size, artist.depthFormat)
    for texture in artist.shadowCascadeTextures.mitems:
      texture = createShadowMapTexture(artist.device, size, size, artist.shadowFormat)
    artist.shadowCascadeResolution = size

proc ensurePointShadowResources(artist: var Artist3D; resolution: uint32) =
  let size = max(resolution, 1'u32)
  if raw(artist.pointShadowDepthTexture).isNil or artist.pointShadowResolution != size:
    reset(artist.pointShadowDepthTexture)
    for texture in artist.pointShadowTextures.mitems:
      reset(texture)
    artist.pointShadowDepthTexture = createDepthTexture(artist.device, size, size, artist.depthFormat)
    for texture in artist.pointShadowTextures.mitems:
      texture = createShadowCubeTexture(artist.device, size, artist.shadowFormat)
    artist.pointShadowResolution = size

proc ensureDepthTexture(artist: var Artist3D; width, height: uint32) =
  let w = max(width, 1'u32)
  let h = max(height, 1'u32)
  if raw(artist.depthTexture).isNil or artist.depthWidth != w or artist.depthHeight != h:
    reset(artist.depthTexture)
    artist.depthTexture = createDepthTexture(artist.device, w, h, artist.depthFormat)
    artist.depthWidth = w
    artist.depthHeight = h

proc createPipeline(
  artist: var Artist3D;
  swapchainFormat: GPUTextureFormat
) =
  var vertexBufferDescription = GPUVertexBufferDescription(
    slot: 0,
    pitch: uint32(sizeof(Vertex3D)),
    input_rate: gpuVertexInputRateVertex,
    instance_step_rate: 0
  )
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat3,
      offset: uint32(offsetof(Vertex3D, position))
    ),
    GPUVertexAttribute(
      location: 1,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(Vertex3D, uv))
    ),
    GPUVertexAttribute(
      location: 2,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat3,
      offset: uint32(offsetof(Vertex3D, normal))
    ),
    GPUVertexAttribute(
      location: 3,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat4,
      offset: uint32(offsetof(Vertex3D, color))
    ),
    GPUVertexAttribute(
      location: 4,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat,
      offset: uint32(offsetof(Vertex3D, textureIndex))
    ),
    GPUVertexAttribute(
      location: 5,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat3,
      offset: uint32(offsetof(Vertex3D, lightingPosition))
    )
  ]

  artist.pipeline = createDepthTexturedPipeline(
    artist.device,
    swapchainFormat,
    artist.depthFormat,
    artist.vertexShader,
    artist.fragmentShader,
    addr vertexBufferDescription,
    1,
    addr vertexAttributes[0],
    uint32(vertexAttributes.len)
  )
  artist.overlayPipeline = createOverlayDepthTexturedPipeline(
    artist.device,
    swapchainFormat,
    artist.depthFormat,
    artist.vertexShader,
    artist.fragmentShader,
    addr vertexBufferDescription,
    1,
    addr vertexAttributes[0],
    uint32(vertexAttributes.len)
  )

  var shadowVertexBufferDescription = GPUVertexBufferDescription(
    slot: 0,
    pitch: uint32(sizeof(Vertex3D)),
    input_rate: gpuVertexInputRateVertex,
    instance_step_rate: 0
  )
  var shadowVertexAttribute = GPUVertexAttribute(
    location: 0,
    buffer_slot: 0,
    format: gpuVertexElementFormatFloat3,
    offset: uint32(offsetof(Vertex3D, position))
  )
  artist.shadowPipeline = createShadowMapPipeline(
    artist.device,
    artist.shadowFormat,
    artist.depthFormat,
    artist.shadowVertexShader,
    artist.shadowFragmentShader,
    addr shadowVertexBufferDescription,
    1,
    addr shadowVertexAttribute,
    1
  )

proc initArtist3D*(
  device: GPUDeviceHandle,
  swapchainFormat: GPUTextureFormat,
  config: Artist3DConfig
): Artist3D =
  let maxQuads =
    if config.maxQuads <= 0: 20_000
    else: config.maxQuads
  if maxQuads <= 0:
    raise newException(Artist3DError, "Artist3D requires maxQuads > 0")

  result.device = device
  result.maxQuads = maxQuads
  result.maxTextureSlots = clamp(
    if config.maxTextureSlots <= 0: maxShaderTextureSlots else: config.maxTextureSlots,
    1,
    maxShaderTextureSlots
  )
  result.depthFormat = GPU_TEXTUREFORMAT_D16_UNORM
  if not gpuTextureSupportsFormat(device, result.depthFormat, gpuTextureType2D, GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET):
    raise newException(Artist3DError, "D16_UNORM depth textures are not supported by this SDL GPU device")
  result.shadowFormat = GPU_TEXTUREFORMAT_R16_UNORM
  if not gpuTextureSupportsFormat(
      device,
      result.shadowFormat,
      gpuTextureType2D,
      GPU_TEXTUREUSAGE_SAMPLER or GPU_TEXTUREUSAGE_COLOR_TARGET):
    raise newException(Artist3DError, "R16_UNORM shadow map textures are not supported by this SDL GPU device")
  if not gpuTextureSupportsFormat(
      device,
      result.shadowFormat,
      gpuTextureTypeCube,
      GPU_TEXTUREUSAGE_SAMPLER or GPU_TEXTUREUSAGE_COLOR_TARGET):
    raise newException(Artist3DError, "Cubemap R16_UNORM shadow textures are not supported by this SDL GPU device")

  result.vertices = newSeqOfCap[Vertex3D](result.maxQuads * 4)
  result.indices = newSeqOfCap[uint32](result.maxQuads * 6)
  result.batches = newSeqOfCap[Batch3D](max(1, result.maxQuads div 128))
  result.currentBindings = newSeqOfCap[TextureBinding3D](result.maxTextureSlots)
  result.modelStack = newSeqOfCap[Mat4](32)
  result.textureFilters = initTable[ptr GPUTexture, TextureFilterMode]()
  result.projection = identityMat4()
  result.view = identityMat4()
  result.model = identityMat4()
  result.clipNear = 0.03'f32
  result.clipFar = 100'f32
  result.color = vec4(1'f32, 1'f32, 1'f32, 1'f32)
  result.normal = vec3(0'f32, 0'f32, 1'f32)
  result.filterMode = tfLinear
  result.depthTestEnabled = true
  result.sceneLightingEnabled = true
  result.shadowCastingEnabled = true
  result.gridLightingTexture = nil
  result.gridLightingInfo = default(GridLightTextureInfo)
  result.gridLightingEnabled = false
  result.environmentClearEnabled = false
  result.environmentClearColor = default(FColor)
  result.ambientColor = vec3(1'f32, 1'f32, 1'f32)
  result.sunDirection = vec3(0.4'f32, -1'f32, 0.2'f32)
  result.sunColor = vec3(1'f32, 1'f32, 1'f32)
  result.sunIntensity = 0'f32
  result.sunEnabled = false
  result.shadowConfig = defaultShadowRenderConfig()
  result.pointLights = @[]
  result.fogTint = vec3(0'f32, 0'f32, 0'f32)
  result.fogDensity = 0'f32
  result.cameraPosition = vec3(0'f32, 0'f32, 0'f32)
  result.shadowBoundsMin = vec3(0'f32, 0'f32, 0'f32)
  result.shadowBoundsMax = vec3(0'f32, 0'f32, 0'f32)
  result.shadowBoundsEnabled = false

  result.vertexShader = createShaderFromFile(
    device,
    if config.vertexShaderPath.len > 0: config.vertexShaderPath else: default3DVertexShaderPath(),
    gpuShaderStageVertex,
    0,
    1
  )
  result.fragmentShader = createShaderFromFile(
    device,
    if config.fragmentShaderPath.len > 0: config.fragmentShaderPath else: default3DFragmentShaderPath(),
    gpuShaderStageFragment,
    uint32(maxShaderTextureSlots + maxSunShadowCascades + maxShadowedPointLights),
    2
  )
  result.shadowVertexShader = createShaderFromFile(
    device,
    if config.shadowVertexShaderPath.len > 0: config.shadowVertexShaderPath else: default3DShadowVertexShaderPath(),
    gpuShaderStageVertex,
    0,
    1
  )
  result.shadowFragmentShader = createShaderFromFile(
    device,
    if config.shadowFragmentShaderPath.len > 0: config.shadowFragmentShaderPath else: default3DShadowFragmentShaderPath(),
    gpuShaderStageFragment,
    0,
    1
  )

  result.vertexBuffer = createGPUBuffer(device, GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX,
    size: uint32(result.maxQuads * 4 * sizeof(Vertex3D)),
    props: 0
  ))
  result.indexBuffer = createGPUBuffer(device, GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_INDEX,
    size: uint32(result.maxQuads * 6 * sizeof(uint32)),
    props: 0
  ))
  result.vertexTransferBuffer = createGPUTransferBuffer(device, GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(result.maxQuads * 4 * sizeof(Vertex3D)),
    props: 0
  ))
  result.indexTransferBuffer = createGPUTransferBuffer(device, GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(result.maxQuads * 6 * sizeof(uint32)),
    props: 0
  ))

  result.whiteTexture = createWhiteTexture(device)
  result.whiteCubeTexture = createWhiteCubeTexture(device)
  result.registerTextureFilter(raw(result.whiteTexture), tfLinear)
  let samplerInfo =
    if config.samplerInfo == default(GPUSamplerCreateInfo): defaultSamplerInfo() else: config.samplerInfo
  result.linearSampler = createGPUSampler(device, samplerInfo.samplerInfoForFilter(tfLinear))
  result.nearestSampler = createGPUSampler(device, samplerInfo.samplerInfoForFilter(tfNearest))
  var shadowSamplerInfo = samplerInfo
  shadowSamplerInfo.address_mode_u = gpuSamplerAddressModeClampToEdge
  shadowSamplerInfo.address_mode_v = gpuSamplerAddressModeClampToEdge
  shadowSamplerInfo.address_mode_w = gpuSamplerAddressModeClampToEdge
  result.shadowSampler = createGPUSampler(device, shadowSamplerInfo.samplerInfoForFilter(tfLinear))
  result.shadowCubeSampler = createGPUSampler(device, shadowSamplerInfo.samplerInfoForFilter(tfLinear))
  result.createPipeline(swapchainFormat)

proc beginFrame*(artist: var Artist3D) =
  artist.vertices.setLen(0)
  artist.indices.setLen(0)
  artist.batches.setLen(0)
  artist.currentBindings.setLen(0)
  artist.currentBatchStart = 0
  artist.currentBatchCount = 0
  artist.modelStack.setLen(0)
  artist.model = identityMat4()
  artist.clipNear = 0.03'f32
  artist.clipFar = 100'f32
  artist.color = vec4(1'f32, 1'f32, 1'f32, 1'f32)
  artist.normal = vec3(0'f32, 0'f32, 1'f32)
  artist.texture = nil
  artist.filterMode = tfLinear
  artist.depthTestEnabled = true
  artist.sceneLightingEnabled = true
  artist.shadowCastingEnabled = true
  artist.gridLightingTexture = nil
  artist.gridLightingInfo = default(GridLightTextureInfo)
  artist.gridLightingEnabled = false
  artist.environmentClearEnabled = false
  artist.environmentClearColor = default(FColor)
  artist.ambientColor = vec3(1'f32, 1'f32, 1'f32)
  artist.sunDirection = vec3(0.4'f32, -1'f32, 0.2'f32)
  artist.sunColor = vec3(1'f32, 1'f32, 1'f32)
  artist.sunIntensity = 0'f32
  artist.sunEnabled = false
  artist.pointLights.setLen(0)
  artist.fogTint = vec3(0'f32, 0'f32, 0'f32)
  artist.fogDensity = 0'f32
  artist.cameraPosition = vec3(0'f32, 0'f32, 0'f32)
  artist.shadowBoundsMin = vec3(0'f32, 0'f32, 0'f32)
  artist.shadowBoundsMax = vec3(0'f32, 0'f32, 0'f32)
  artist.shadowBoundsEnabled = false

proc setProjection*(artist: var Artist3D; projection: Mat4) =
  artist.projection = projection

proc setClipPlanes*(artist: var Artist3D; nearPlane, farPlane: float32) =
  artist.clipNear = max(0.0001'f32, nearPlane)
  artist.clipFar = max(artist.clipNear + 0.001'f32, farPlane)

proc setView*(artist: var Artist3D; view: Mat4) =
  artist.view = view

proc setModel*(artist: var Artist3D; model: Mat4) =
  artist.model = model

proc pushModel*(artist: var Artist3D) =
  artist.modelStack.add(artist.model)

proc popModel*(artist: var Artist3D) =
  if artist.modelStack.len > 0:
    artist.model = artist.modelStack.pop()

proc setTexture*(artist: var Artist3D; texture: Texture3D) =
  artist.texture = texture

proc setColor*(artist: var Artist3D; color: Vec4) =
  artist.color = color

proc setNormal*(artist: var Artist3D; normal: Vec3) =
  artist.normal =
    if lengthSq(normal) <= 0.000001'f32:
      vec3(0'f32, 0'f32, 1'f32)
    else:
      normalize(normal)

proc setFilterMode*(artist: var Artist3D; filterMode: TextureFilterMode) =
  artist.filterMode = filterMode

proc setDepthTestEnabled*(artist: var Artist3D; enabled: bool) =
  if artist.depthTestEnabled == enabled:
    return
  artist.finalizeBatch()
  artist.depthTestEnabled = enabled

proc setSceneLightingEnabled*(artist: var Artist3D; enabled: bool) =
  if artist.sceneLightingEnabled == enabled:
    return
  artist.finalizeBatch()
  artist.sceneLightingEnabled = enabled

proc setShadowCastingEnabled*(artist: var Artist3D; enabled: bool) =
  if artist.shadowCastingEnabled == enabled:
    return
  artist.finalizeBatch()
  artist.shadowCastingEnabled = enabled

proc setAmbientLight*(artist: var Artist3D; ambient: Vec3) =
  artist.ambientColor = ambient

proc setSunLight*(
  artist: var Artist3D;
  direction: Vec3;
  color: Vec3;
  intensity: float32;
  enabled = true
) =
  artist.sunDirection =
    if lengthSq(direction) <= 0.000001'f32:
      vec3(0.4'f32, -1'f32, 0.2'f32)
    else:
      normalize(direction)
  artist.sunColor = color
  artist.sunIntensity = max(0'f32, intensity)
  artist.sunEnabled = enabled and artist.sunIntensity > 0'f32

proc setPointLights*(artist: var Artist3D; lights: openArray[ShadowPointLight]) =
  artist.pointLights.setLen(0)
  for light in lights:
    artist.pointLights.add(light)

proc setShadowConfig*(artist: var Artist3D; config: ShadowRenderConfig) =
  artist.shadowConfig = config

proc setShadowBounds*(artist: var Artist3D; boundsMin, boundsMax: Vec3) =
  artist.shadowBoundsMin = boundsMin
  artist.shadowBoundsMax = boundsMax
  artist.shadowBoundsEnabled =
    boundsMax.x > boundsMin.x and
    boundsMax.y > boundsMin.y and
    boundsMax.z > boundsMin.z

proc setGridLighting*(
  artist: var Artist3D;
  texture: Texture3D;
  info: GridLightTextureInfo
) =
  artist.gridLightingTexture = texture
  artist.gridLightingInfo = info
  artist.gridLightingEnabled = not texture.isNil and
    info.textureWidth > 0 and info.textureHeight > 0 and
    info.gridWidth > 0 and info.gridHeight > 0 and
    info.cellSize > 0'f32 and info.samplesPerCell > 0 and
    info.blockStride > 0

proc clearGridLighting*(artist: var Artist3D) =
  artist.gridLightingTexture = nil
  artist.gridLightingInfo = default(GridLightTextureInfo)
  artist.gridLightingEnabled = false

proc setEnvironment*(
  artist: var Artist3D;
  clearColor: Vec3;
  fogTint: Vec3;
  fogDensity: float32;
  cameraPosition: Vec3
) =
  artist.environmentClearEnabled = true
  artist.environmentClearColor = FColor(r: clearColor.x, g: clearColor.y, b: clearColor.z, a: 1'f32)
  artist.fogTint = fogTint
  artist.fogDensity = max(0'f32, fogDensity)
  artist.cameraPosition = cameraPosition

proc quadWithLightingPositions*(
  artist: var Artist3D;
  p0, p1, p2, p3: Vec3;
  lightingPositions: array[4, Vec3];
  uvs: QuadUvs = defaultQuadUvs();
  normal: Vec3 = vec3(0'f32, 0'f32, 0'f32);
  color: Vec4 = vec4(-1'f32, -1'f32, -1'f32, -1'f32)
): bool {.gcsafe.} =
  if not artist.canAdd(4, 6):
    return false

  let filterMode = artist.textureFilter(artist.texture)
  let slot = artist.textureSlot(artist.texture, filterMode)
  let base = uint32(artist.vertices.len)
  let resolvedColor =
    if color.x < 0'f32 or color.y < 0'f32 or color.z < 0'f32 or color.w < 0'f32:
      artist.color
    else:
      color
  let resolvedNormal =
    if lengthSq(normal) <= 0.000001'f32:
      faceNormal(p0, p1, p2)
    else:
      normalize(normal)
  let worldNormal = transformNormal(artist.model, resolvedNormal)
  let transformed = [
    transformPoint(artist.model, p0),
    transformPoint(artist.model, p1),
    transformPoint(artist.model, p2),
    transformPoint(artist.model, p3)
  ]
  let quadUvs = [
    vec2(uvs.u0, uvs.v0),
    vec2(uvs.u1, uvs.v0),
    vec2(uvs.u1, uvs.v1),
    vec2(uvs.u0, uvs.v1)
  ]

  for i in 0 .. 3:
    artist.vertices.add(Vertex3D(
      position: transformed[i],
      uv: quadUvs[i],
      normal: worldNormal,
      color: resolvedColor,
      textureIndex: cfloat(slot),
      lightingPosition: lightingPositions[i]
    ))

  artist.indices.add(base)
  artist.indices.add(base + 1)
  artist.indices.add(base + 2)
  artist.indices.add(base)
  artist.indices.add(base + 2)
  artist.indices.add(base + 3)
  artist.currentBatchCount += 6
  true

proc quad*(
  artist: var Artist3D;
  p0, p1, p2, p3: Vec3;
  uvs: QuadUvs = defaultQuadUvs();
  normal: Vec3 = vec3(0'f32, 0'f32, 0'f32);
  color: Vec4 = vec4(-1'f32, -1'f32, -1'f32, -1'f32)
): bool {.gcsafe.} =
  artist.quadWithLightingPositions(
    p0,
    p1,
    p2,
    p3,
    [p0, p1, p2, p3],
    uvs,
    normal,
    color
  )

proc cube*(artist: var Artist3D; center, size: Vec3): bool =
  let h = size * 0.5'f32
  let x0 = center.x - h.x
  let x1 = center.x + h.x
  let y0 = center.y - h.y
  let y1 = center.y + h.y
  let z0 = center.z - h.z
  let z1 = center.z + h.z

  artist.quad(vec3(x0, y0, z1), vec3(x1, y0, z1), vec3(x1, y1, z1), vec3(x0, y1, z1), normal = vec3(0'f32, 0'f32, 1'f32)) and
    artist.quad(vec3(x1, y0, z0), vec3(x0, y0, z0), vec3(x0, y1, z0), vec3(x1, y1, z0), normal = vec3(0'f32, 0'f32, -1'f32)) and
    artist.quad(vec3(x0, y0, z0), vec3(x0, y0, z1), vec3(x0, y1, z1), vec3(x0, y1, z0), normal = vec3(-1'f32, 0'f32, 0'f32)) and
    artist.quad(vec3(x1, y0, z1), vec3(x1, y0, z0), vec3(x1, y1, z0), vec3(x1, y1, z1), normal = vec3(1'f32, 0'f32, 0'f32)) and
    artist.quad(vec3(x0, y1, z1), vec3(x1, y1, z1), vec3(x1, y1, z0), vec3(x0, y1, z0), normal = vec3(0'f32, 1'f32, 0'f32)) and
    artist.quad(vec3(x0, y0, z0), vec3(x1, y0, z0), vec3(x1, y0, z1), vec3(x0, y0, z1), normal = vec3(0'f32, -1'f32, 0'f32))

proc createTexture3D*(
  artist: var Artist3D;
  width: int;
  height: int;
  pixels: openArray[uint8];
  filterMode: TextureFilterMode = tfLinear
): GPUTextureHandle {.gcsafe.} =
  if width <= 0 or height <= 0:
    raise newException(Artist3DError, "3D texture dimensions must be positive")
  if pixels.len != width * height * 4:
    raise newException(Artist3DError, "3D textures require tightly packed RGBA8 pixels")

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
  uploadTexture2DData(artist.device, result, width, height, pixels, "artist3d texture upload")
  artist.registerTextureFilter(raw(result), filterMode)

proc createGridLightTexture3D*(
  artist: var Artist3D;
  field: GridLightField
): GPUTextureHandle {.gcsafe.} =
  createTexture3D(
    artist,
    field.info.textureWidth,
    field.info.textureHeight,
    field.pixels,
    tfLinear
  )

proc uploadGeometry(artist: var Artist3D; commandBuffer: ptr GPUCommandBuffer) =
  if artist.vertices.len <= 0 or artist.indices.len <= 0:
    return

  let vertexBytes = artist.vertices.len * sizeof(Vertex3D)
  let mappedVertices = mapGPUTransferBuffer(artist.device, artist.vertexTransferBuffer, true)
  copyMem(mappedVertices, unsafeAddr artist.vertices[0], vertexBytes)
  unmapGPUTransferBuffer(artist.device, artist.vertexTransferBuffer)

  let indexBytes = artist.indices.len * sizeof(uint32)
  let mappedIndices = mapGPUTransferBuffer(artist.device, artist.indexTransferBuffer, true)
  copyMem(mappedIndices, unsafeAddr artist.indices[0], indexBytes)
  unmapGPUTransferBuffer(artist.device, artist.indexTransferBuffer)

  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(Artist3DError, "beginGPUCopyPass failed: " & $getError())

  var vertexSource = GPUTransferBufferLocation(
    transfer_buffer: raw(artist.vertexTransferBuffer),
    offset: 0
  )
  var vertexDestination = GPUBufferRegion(
    buffer: raw(artist.vertexBuffer),
    offset: 0,
    size: uint32(vertexBytes)
  )
  uploadToGPUBuffer(copyPass, addr vertexSource, addr vertexDestination, true)

  var indexSource = GPUTransferBufferLocation(
    transfer_buffer: raw(artist.indexTransferBuffer),
    offset: 0
  )
  var indexDestination = GPUBufferRegion(
    buffer: raw(artist.indexBuffer),
    offset: 0,
    size: uint32(indexBytes)
  )
  uploadToGPUBuffer(copyPass, addr indexSource, addr indexDestination, true)
  endGPUCopyPass(copyPass)

proc renderShadowPass(
  artist: var Artist3D;
  commandBuffer: ptr GPUCommandBuffer;
  shadowTexture: ptr GPUTexture;
  depthTexture: ptr GPUTexture;
  width, height: uint32;
  layer: uint32;
  viewProjection: Mat4;
  lightPosition: Vec3;
  lightFarOrZero: float32
) =
  var shadowVertexUniforms = ShadowPassVertexUniforms(viewProjection: viewProjection)
  pushGPUVertexUniformData(
    commandBuffer,
    0,
    shadowPassVertexUniformsPointer(shadowVertexUniforms),
    uint32(sizeof(shadowVertexUniforms))
  )

  var shadowFragmentUniforms = ShadowPassFragmentUniforms(
    lightPositionFarMode: vec4(lightPosition.x, lightPosition.y, lightPosition.z, lightFarOrZero)
  )
  pushGPUFragmentUniformData(
    commandBuffer,
    0,
    shadowPassFragmentUniformsPointer(shadowFragmentUniforms),
    uint32(sizeof(shadowFragmentUniforms))
  )

  var colorTarget = GPUColorTargetInfo(
    texture: shadowTexture,
    mip_level: 0,
    layer_or_depth_plane: layer,
    clear_color: FColor(r: 1'f32, g: 1'f32, b: 1'f32, a: 1'f32),
    load_op: gpuLoadOpClear,
    store_op: gpuStoreOpStore,
    resolve_texture: nil,
    resolve_mip_level: 0,
    resolve_layer: 0,
    cycle: false,
    cycle_resolve_texture: false
  )
  var depthTarget = GPUDepthStencilTargetInfo(
    texture: depthTexture,
    clear_depth: 1'f32,
    load_op: gpuLoadOpClear,
    store_op: gpuStoreOpDontCare,
    stencil_load_op: gpuLoadOpDontCare,
    stencil_store_op: gpuStoreOpDontCare,
    cycle: false,
    clear_stencil: 0,
    mip_level: 0,
    layer: 0
  )
  let renderPass = beginGPURenderPass(commandBuffer, addr colorTarget, 1, addr depthTarget)
  if renderPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(Artist3DError, "beginGPURenderPass failed for shadow pass: " & $getError())

  var fullScissor = Rect(x: 0, y: 0, w: cint(width), h: cint(height))
  setGPUScissor(renderPass, addr fullScissor)
  bindGPUGraphicsPipeline(renderPass, raw(artist.shadowPipeline))

  var vertexBinding = GPUBufferBinding(buffer: raw(artist.vertexBuffer), offset: 0)
  var indexBinding = GPUBufferBinding(buffer: raw(artist.indexBuffer), offset: 0)
  bindGPUVertexBuffers(renderPass, 0, addr vertexBinding, 1)
  bindGPUIndexBuffer(renderPass, addr indexBinding, gpuIndexElementSize32Bit)

  for batch in artist.batches:
    if not batch.depthTestEnabled or not batch.shadowCastingEnabled:
      continue
    drawGPUIndexedPrimitives(
      renderPass,
      batch.indexCount,
      1,
      batch.firstIndex,
      0,
      0
    )

  endGPURenderPass(renderPass)

proc render*(
  artist: var Artist3D,
  commandBuffer: ptr GPUCommandBuffer,
  targetTexture: ptr GPUTexture,
  targetWidth: uint32,
  targetHeight: uint32,
  clearColor: FColor = FColor(r: 0.03, g: 0.04, b: 0.06, a: 1.0)
) =
  artist.finalizeBatch()
  artist.uploadGeometry(commandBuffer)
  artist.ensureDepthTexture(targetWidth, targetHeight)

  let shadowConfig = artist.shadowConfig
  let maxVisiblePointLights = clamp(shadowConfig.maxVisiblePointLights, 0, maxForwardPointLights)
  let maxShadowedLights = clamp(shadowConfig.maxShadowedPointLights, 0, maxShadowedPointLights)
  let activePointLights = selectActivePointLights(
    artist.pointLights,
    artist.cameraPosition,
    maxVisiblePointLights,
    maxShadowedLights
  )
  let shadowCamera = ShadowCamera(
    position: artist.cameraPosition,
    view: artist.view,
    projection: artist.projection,
    nearPlane: artist.clipNear,
    farPlane: artist.clipFar
  )
  let sunCascades =
    if artist.sunEnabled:
      if artist.shadowBoundsEnabled:
        buildDirectionalShadowCascades(
          shadowCamera,
          artist.sunDirection,
          artist.shadowBoundsMin,
          artist.shadowBoundsMax,
          clamp(shadowConfig.cascadeCount, 0, maxSunShadowCascades),
          shadowConfig.maxSunDistance,
          shadowConfig.splitLambda,
          shadowConfig.cascadeResolution
        )
      else:
        buildDirectionalShadowCascades(
          shadowCamera,
          artist.sunDirection,
          clamp(shadowConfig.cascadeCount, 0, maxSunShadowCascades),
          shadowConfig.maxSunDistance,
          shadowConfig.splitLambda,
          shadowConfig.cascadeResolution
        )
    else:
      @[]
  var shadowedPointLightCount = 0
  for light in activePointLights:
    if light.castsShadow:
      inc shadowedPointLightCount

  if sunCascades.len > 0:
    artist.ensureShadowCascadeResources(uint32(max(1, shadowConfig.cascadeResolution)))
    for cascadeIndex, cascade in sunCascades:
      artist.renderShadowPass(
        commandBuffer,
        raw(artist.shadowCascadeTextures[cascadeIndex]),
        raw(artist.shadowCascadeDepthTexture),
        artist.shadowCascadeResolution,
        artist.shadowCascadeResolution,
        0,
        cascade.viewProjection,
        vec3(0'f32, 0'f32, 0'f32),
        0'f32
      )

  if shadowedPointLightCount > 0:
    artist.ensurePointShadowResources(uint32(max(1, shadowConfig.pointShadowResolution)))
    var shadowTextureIndex = 0
    for light in activePointLights:
      if not light.castsShadow:
        continue
      let faceMatrices = buildPointLightFaceViewProjections(light.light.position, light.light.radius)
      for faceIndex, faceMatrix in faceMatrices:
        artist.renderShadowPass(
          commandBuffer,
          raw(artist.pointShadowTextures[shadowTextureIndex]),
          raw(artist.pointShadowDepthTexture),
          artist.pointShadowResolution,
          artist.pointShadowResolution,
          uint32(faceIndex),
          faceMatrix,
          light.light.position,
          light.light.radius
        )
      inc shadowTextureIndex

  var uniforms = FrameUniforms(
    projection: artist.projection,
    view: artist.view
  )
  pushGPUVertexUniformData(
    commandBuffer,
    0,
    uniformsPointer(uniforms),
    uint32(sizeof(uniforms))
  )

  var lightingUniforms = GridLightingUniforms()
  for cascadeIndex in 0 ..< maxSunShadowCascades:
    if cascadeIndex < sunCascades.len:
      lightingUniforms.sunShadowMatrices[cascadeIndex] = sunCascades[cascadeIndex].viewProjection
      lightingUniforms.sunShadowTexelSize[cascadeIndex] = vec4(
        1'f32 / max(1'u32, artist.shadowCascadeResolution).float32,
        1'f32 / max(1'u32, artist.shadowCascadeResolution).float32,
        0'f32,
        0'f32
      )
    else:
      lightingUniforms.sunShadowMatrices[cascadeIndex] = mat4()
      lightingUniforms.sunShadowTexelSize[cascadeIndex] = vec4(0'f32, 0'f32, 0'f32, 0'f32)
  lightingUniforms.cascadeSplits = vec4(
    if sunCascades.len > 0: sunCascades[0].splitFar else: 0'f32,
    if sunCascades.len > 1: sunCascades[1].splitFar else: 0'f32,
    if sunCascades.len > 2: sunCascades[2].splitFar else: 0'f32,
    sunCascades.len.float32
  )
  lightingUniforms.ambientColor = vec4(
    artist.ambientColor.x,
    artist.ambientColor.y,
    artist.ambientColor.z,
    1'f32
  )
  lightingUniforms.textureSize = vec4(0'f32, 0'f32, 0'f32, 0'f32)
  lightingUniforms.sunDirectionIntensity = vec4(
    artist.sunDirection.x,
    artist.sunDirection.y,
    artist.sunDirection.z,
    artist.sunIntensity
  )
  lightingUniforms.sunColorEnabled = vec4(
    artist.sunColor.x,
    artist.sunColor.y,
    artist.sunColor.z,
    if artist.sunEnabled: 1'f32 else: 0'f32
  )
  lightingUniforms.sunShadowParams = vec4(
    shadowConfig.sunDepthBias,
    shadowConfig.sunNormalBias,
    shadowConfig.sunFilterRadiusTexels,
    sunCascades.len.float32
  )
  lightingUniforms.pointShadowParams = vec4(
    activePointLights.len.float32,
    shadowedPointLightCount.float32,
    shadowConfig.pointDepthBias,
    shadowConfig.pointSoftness
  )
  for lightIndex in 0 ..< maxForwardPointLights:
    if lightIndex < activePointLights.len:
      let light = activePointLights[lightIndex]
      lightingUniforms.pointLightPositionRadius[lightIndex] = vec4(
        light.light.position.x,
        light.light.position.y,
        light.light.position.z,
        light.light.radius
      )
      lightingUniforms.pointLightColorIntensity[lightIndex] = vec4(
        light.light.color.x,
        light.light.color.y,
        light.light.color.z,
        light.light.intensity
      )
      var shadowIndex = -1'f32
      if light.castsShadow:
        var assignedIndex = 0
        for previousIndex in 0 .. lightIndex:
          if activePointLights[previousIndex].castsShadow:
            shadowIndex = assignedIndex.float32
            inc assignedIndex
      lightingUniforms.pointLightFalloffShadow[lightIndex] = vec4(
        light.light.falloff,
        shadowIndex,
        shadowConfig.pointNormalBias,
        0'f32
      )
    else:
      lightingUniforms.pointLightPositionRadius[lightIndex] = vec4(0'f32, 0'f32, 0'f32, 0'f32)
      lightingUniforms.pointLightColorIntensity[lightIndex] = vec4(0'f32, 0'f32, 0'f32, 0'f32)
      lightingUniforms.pointLightFalloffShadow[lightIndex] = vec4(0'f32, -1'f32, 0'f32, 0'f32)
  lightingUniforms.fogTintDensity = vec4(
    artist.fogTint.x,
    artist.fogTint.y,
    artist.fogTint.z,
    artist.fogDensity
  )
  lightingUniforms.cameraPosition = vec4(
    artist.cameraPosition.x,
    artist.cameraPosition.y,
    artist.cameraPosition.z,
    1'f32
  )
  pushGPUFragmentUniformData(
    commandBuffer,
    0,
    lightingUniformsPointer(lightingUniforms),
    uint32(sizeof(lightingUniforms))
  )

  var colorTarget = GPUColorTargetInfo(
    texture: targetTexture,
    mip_level: 0,
    layer_or_depth_plane: 0,
    clear_color:
      if artist.environmentClearEnabled:
        artist.environmentClearColor
      else:
        clearColor,
    load_op: gpuLoadOpClear,
    store_op: gpuStoreOpStore,
    resolve_texture: nil,
    resolve_mip_level: 0,
    resolve_layer: 0,
    cycle: false,
    cycle_resolve_texture: false
  )
  var depthTarget = GPUDepthStencilTargetInfo(
    texture: raw(artist.depthTexture),
    clear_depth: 1'f32,
    load_op: gpuLoadOpClear,
    store_op: gpuStoreOpDontCare,
    stencil_load_op: gpuLoadOpDontCare,
    stencil_store_op: gpuStoreOpDontCare,
    cycle: false,
    clear_stencil: 0,
    mip_level: 0,
    layer: 0
  )
  let renderPass = beginGPURenderPass(commandBuffer, addr colorTarget, 1, addr depthTarget)
  if renderPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(Artist3DError, "beginGPURenderPass failed: " & $getError())

  var fullScissor = Rect(
    x: 0,
    y: 0,
    w: cint(targetWidth),
    h: cint(targetHeight)
  )
  setGPUScissor(renderPass, addr fullScissor)

  var vertexBinding = GPUBufferBinding(buffer: raw(artist.vertexBuffer), offset: 0)
  var indexBinding = GPUBufferBinding(buffer: raw(artist.indexBuffer), offset: 0)
  bindGPUVertexBuffers(renderPass, 0, addr vertexBinding, 1)
  bindGPUIndexBuffer(renderPass, addr indexBinding, gpuIndexElementSize32Bit)

  for batch in artist.batches:
    bindGPUGraphicsPipeline(
      renderPass,
      raw(if batch.depthTestEnabled: artist.pipeline else: artist.overlayPipeline)
    )
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
    var sunShadowSamplers: array[maxSunShadowCascades, GPUTextureSamplerBinding]
    for shadowIndex in 0 ..< maxSunShadowCascades:
      sunShadowSamplers[shadowIndex] = GPUTextureSamplerBinding(
        texture:
          if shadowIndex < sunCascades.len:
            raw(artist.shadowCascadeTextures[shadowIndex])
          else:
            raw(artist.whiteTexture),
        sampler: raw(artist.shadowSampler)
      )
    bindGPUFragmentSamplers(renderPass, sunShadowSamplerSlot, addr sunShadowSamplers[0], uint32(sunShadowSamplers.len))
    var pointShadowSamplers: array[maxShadowedPointLights, GPUTextureSamplerBinding]
    for shadowIndex in 0 ..< maxShadowedPointLights:
      pointShadowSamplers[shadowIndex] = GPUTextureSamplerBinding(
        texture:
          if shadowIndex < shadowedPointLightCount:
            raw(artist.pointShadowTextures[shadowIndex])
          else:
            raw(artist.whiteCubeTexture),
        sampler: raw(artist.shadowCubeSampler)
      )
    bindGPUFragmentSamplers(renderPass, pointShadowSamplerSlot, addr pointShadowSamplers[0], uint32(pointShadowSamplers.len))
    var batchUniforms = BatchLightingUniforms(
      flags: vec4(if batch.sceneLightingEnabled: 1'f32 else: 0'f32, 0'f32, 0'f32, 0'f32)
    )
    pushGPUFragmentUniformData(
      commandBuffer,
      1,
      batchLightingUniformsPointer(batchUniforms),
      uint32(sizeof(batchUniforms))
    )
    drawGPUIndexedPrimitives(
      renderPass,
      batch.indexCount,
      1,
      batch.firstIndex,
      0,
      0
    )

  endGPURenderPass(renderPass)

proc whiteTexture3D*(artist: Artist3D): Texture3D =
  raw(artist.whiteTexture)

proc whiteCubeTexture3D*(artist: Artist3D): CubeTexture =
  raw(artist.whiteCubeTexture)
