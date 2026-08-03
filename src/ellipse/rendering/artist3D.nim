import std/[os, strformat, tables]

import sdl3, vmath

import cameras
import ../errors
import ../resources

const
  DefaultCameraID* = "default"
  DefaultMeshID* = "default"
const
  DefaultSpecularStrength* = 0.35'f32
  CameraUniformSlot = 0'u32
  DefaultFovY = 70'f32
  DefaultNearPlane = 0.1'f32
  DefaultFarPlane = 100'f32

type Vertex* = object
  position*, normal*: Vec3
  uv*, splatUv*: Vec2
  splatIndices*, splatWeights*: Vec4

type
  MeshID* = string

  MeshRenderMode* = enum
    SolidMesh, WireframeMesh

  RenderEffect* = enum
    StandardEffect, WaterEffect

  TextureSampling* = enum
    Single, Splat

  WaterRenderOptions* = object
    time*: float32
    waveAmplitude*: float32
    waveLength*: float32
    waveSpeed*: float32
    surfaceColor*: Vec3
    deepColor*: Vec3
    opacity*: float32
    specularStrength*: float32

  FogRenderOptions* = object
    nearColor*: Vec3
    farColor*: Vec3
    density*: float32
    falloff*: float32
    limit*: float32

  SkyRenderOptions* = object
    horizonColor*: Vec3
    zenithColor*: Vec3
    groundColor*: Vec3
    exposure*: float32
    useSkybox*: bool

  RenderOptions* = object
    effect*: RenderEffect
    mode*: MeshRenderMode
    depthTest*: bool
    depthWrite*: bool
    baseColor*: Vec3
    materialID*: string
    fog*: FogRenderOptions
    water*: WaterRenderOptions

  Material* = object
    id*: string
    texture*: TextureResourceHandle
    baseColor*: Vec3
    useTexture*: bool
    textureSampling*: TextureSampling
    atlasColumns*, atlasRows*: int
    specularStrength*: float32

  Model* = object
    meshID*: MeshID
    transform*: Mat4
    renderOptions*: RenderOptions

  Mesh = object
    vertexBuffer, indexBuffer: GPUBuffer
    vertexBufferSize, indexBufferSize: uint32
    vertices: seq[Vertex]
    indices: seq[uint32]
    verticesDirty, indicesDirty: bool

  GpuMaterial = object
    material: Material
    texture: GPUTexture
    textureWidth, textureHeight: uint32
    textureDirty: bool

  TransformUniforms = object
    modelViewProjection: Mat4
    model: Mat4

  LightingUniforms = object
    cameraPosition: Vec3
    cameraPadding: float32
    baseColor: Vec3
    useTexture: float32
    splat: Vec4
    fogNearColor: Vec3
    fogDensity: float32
    fogFarColor: Vec3
    fogFalloff: float32
    fogLimit: float32
    specularStrength: float32
    lightingPadding0: Vec3

  WaterUniforms = object
    cameraPosition: Vec3
    time: float32
    surfaceColor: Vec3
    waveAmplitude: float32
    deepColor: Vec3
    waveLength: float32
    opacity: float32
    waveSpeed: float32
    specularStrength: float32
    padding: float32
    fogNearColor: Vec3
    fogDensity: float32
    fogFarColor: Vec3
    fogFalloff: float32
    fogLimit: float32
    waterPadding0: Vec3

  SkyUniforms = object
    inverseViewProjection: Mat4
    cameraPosition: Vec3
    exposure: float32
    horizonColor: Vec3
    useSkybox: float32
    zenithColor: Vec3
    padding0: float32
    groundColor: Vec3
    padding1: float32

type
  Artist3DState = object
    renderer: Renderer
    device: GPUDevice
    solidPipeline, overlayPipeline, wireframePipeline, overlayWireframePipeline,
      waterPipeline, skyPipeline: GPUGraphicsPipeline
    vertexShader, waterVertexShader, skyVertexShader: GPUShader
    fragmentShader, waterFragmentShader, skyFragmentShader: GPUShader
    meshes: Table[MeshID, Mesh]
    materials: Table[string, GpuMaterial]
    sampler: pointer
    samplerReady: bool
    textureFiltering*: bool
    whiteTexture: GPUTexture
    defaultModel: Model
    colorTexture, depthTexture: GPUTexture
    renderTexture: Texture
    textureWidth, textureHeight: uint32
    allCameras: Table[string, cameras.Camera]
    activeCameraID: string

  Artist3D* = object
    state: ref Artist3DState

const PropTextureCreateGpuTexture = cstring"SDL.texture.create.gpu.texture"

var defaultRenderer: Renderer

type
  GpuTransferBufferLocation {.bycopy.} = object
    transfer_buffer: GPUTransferBuffer
    offset: uint32

  GpuBufferRegion {.bycopy.} = object
    buffer: GPUBuffer
    offset: uint32
    size: uint32

  GpuTextureTransferInfo {.bycopy.} = object
    transfer_buffer: GPUTransferBuffer
    offset: uint32
    pixels_per_row: uint32
    rows_per_layer: uint32

  GpuTextureRegion {.bycopy.} = object
    texture: GPUTexture
    mip_level: uint32
    layer: uint32
    x, y, z: uint32
    w, h, d: uint32

  GpuGraphicsPipelineCreateInfo {.bycopy.} = object
    vertex_shader: GPUShader
    fragment_shader: GPUShader
    vertex_input_state: GPUVertexInputState
    primitive_type: GPUPrimitiveType
    rasterizer_state: GPURasterizerState
    multisample_state: GPUMultisampleState
    depth_stencil_state: GPUDepthStencilState
    target_info: GPUGraphicsPipelineTargetInfo
    props: PropertiesID

  GpuColorTargetInfo {.bycopy.} = object
    texture: GPUTexture
    mip_level: uint32
    layer_or_depth_plane: uint32
    clear_color: FColor
    load_op: GPULoadOp
    store_op: GPUStoreOp
    resolve_texture: GPUTexture
    resolve_mip_level: uint32
    resolve_layer: uint32
    cycle: bool
    cycle_resolve_texture: bool
    padding1: uint8
    padding2: uint8

  GpuDepthStencilTargetInfo {.bycopy.} = object
    texture: GPUTexture
    clear_depth: cfloat
    load_op: GPULoadOp
    store_op: GPUStoreOp
    stencil_load_op: GPULoadOp
    stencil_store_op: GPUStoreOp
    cycle: bool
    clear_stencil: uint8
    padding1: uint8
    padding2: uint8

  GpuBufferBinding {.bycopy.} = object
    buffer: GPUBuffer
    offset: uint32

  GpuTextureSamplerBinding {.bycopy.} = object
    texture: GPUTexture
    sampler: pointer

proc createGpuGraphicsPipeline(
  device: GPUDevice, createInfo: ptr GpuGraphicsPipelineCreateInfo
): GPUGraphicsPipeline {.
  cdecl, dynlib: LibName, importc: "SDL_CreateGPUGraphicsPipeline"
.}

proc uploadToGpuBuffer(
  copyPass: GPUCopyPass,
  source: ptr GpuTransferBufferLocation,
  destination: ptr GpuBufferRegion,
  cycle: bool,
) {.cdecl, dynlib: LibName, importc: "SDL_UploadToGPUBuffer".}

proc uploadToGpuTexture(
  copyPass: GPUCopyPass,
  source: ptr GpuTextureTransferInfo,
  destination: ptr GpuTextureRegion,
  cycle: bool,
) {.cdecl, dynlib: LibName, importc: "SDL_UploadToGPUTexture".}

proc beginGpuRenderPass(
  commandBuffer: GPUCommandBuffer,
  colorTargetInfos: ptr GpuColorTargetInfo,
  numColorTargets: uint32,
  depthStencilTargetInfo: ptr GpuDepthStencilTargetInfo,
): GPURenderPass {.cdecl, dynlib: LibName, importc: "SDL_BeginGPURenderPass".}

proc bindGpuVertexBuffers(
  renderPass: GPURenderPass,
  firstSlot: uint32,
  bindings: ptr GpuBufferBinding,
  numBindings: uint32,
) {.cdecl, dynlib: LibName, importc: "SDL_BindGPUVertexBuffers".}

proc bindGpuIndexBuffer(
  renderPass: GPURenderPass,
  binding: ptr GpuBufferBinding,
  indexElementSize: GPUIndexElementSize,
) {.cdecl, dynlib: LibName, importc: "SDL_BindGPUIndexBuffer".}

proc bindGpuFragmentSamplers(
  renderPass: GPURenderPass,
  firstSlot: uint32,
  textureSamplerBindings: ptr GpuTextureSamplerBinding,
  numBindings: uint32,
) {.cdecl, dynlib: LibName, importc: "SDL_BindGPUFragmentSamplers".}

proc createGpuSampler(
  device: GPUDevice, createInfo: ptr GPUSamplerCreateInfo
): pointer {.cdecl, dynlib: LibName, importc: "SDL_CreateGPUSampler".}

proc releaseGpuSampler(device: GPUDevice, sampler: pointer) {.
  cdecl, dynlib: LibName, importc: "SDL_ReleaseGPUSampler"
.}

proc `=copy`*(artist: var Artist3D, source: Artist3D) {.error.}

proc activeCamera*(artist: Artist3DState): cameras.Camera
proc uploadMesh(artist: var Artist3DState, meshID: MeshID)
proc uploadMaterialTexture(artist: var Artist3DState, materialID: string)

proc raiseGpuError(context: string) {.noreturn.} =
  raise SDLException.newException(context & ": " & $sdl3.getError())

proc shaderPath(name: string): string =
  currentSourcePath().parentDir.parentDir.parentDir.parentDir / "build" /
      "shaders" /
    name

proc loadShaderCode(name: string): string =
  let path = shaderPath(name)
  if not fileExists(path):
    raiseGpuError(&"Missing shader {path}; run `nimble shaders`")
  result = readFile(path)
  if result.len == 0:
    raiseGpuError(&"Shader {path} is empty")

proc createShader(
    device: GPUDevice,
    name: string,
    stage: GPUShaderStage,
    uniformBuffers = 1'u32,
    samplers = 0'u32,
): GPUShader =
  let code = loadShaderCode(name)
  var info = GPUShaderCreateInfo(
    code_size: code.len.csize_t,
    code: cast[ptr UncheckedArray[uint8]](unsafeAddr code[0]),
    entrypoint: cstring"main",
    format: GPU_SHADERFORMAT_SPIRV.GPUShaderFormat,
    stage: stage,
    num_samplers: samplers,
    num_uniform_buffers: uniformBuffers,
  )
  result = createGPUShader(device, addr info)
  if result.isNil:
    raiseGpuError("Failed to create GPU shader")

proc forwardPerspective(fovy, aspect, near, far: float32): Mat4 =
  let
    focalLength = 1'f32 / tan(fovy * PI.float32 / 360'f32)
    depth = far - near
  result[0, 0] = focalLength / aspect
  result[1, 1] = focalLength
  result[2, 2] = far / depth
  result[2, 3] = 1
  result[3, 2] = -(near * far) / depth

proc identityMat4(): Mat4 =
  result[0, 0] = 1
  result[1, 1] = 1
  result[2, 2] = 1
  result[3, 3] = 1

proc init*(
    T: typedesc[WaterRenderOptions],
    time = 0'f32,
    waveAmplitude = 0.12'f32,
    waveLength = 9'f32,
    waveSpeed = 0.8'f32,
    surfaceColor = vec3(0.2'f32, 0.75'f32, 0.92'f32),
    deepColor = vec3(0.01'f32, 0.16'f32, 0.28'f32),
    opacity = 0.82'f32,
    specularStrength = 0.55'f32,
): T =
  T(
    time: time,
    waveAmplitude: waveAmplitude,
    waveLength: waveLength,
    waveSpeed: waveSpeed,
    surfaceColor: surfaceColor,
    deepColor: deepColor,
    opacity: opacity,
    specularStrength: specularStrength,
  )

proc init*(
    T: typedesc[FogRenderOptions],
    nearColor = vec3(0.72'f32, 0.8'f32, 0.86'f32),
    farColor = vec3(0.42'f32, 0.56'f32, 0.66'f32),
    density = 0'f32,
    falloff = 1'f32,
    limit = 120'f32,
): T =
  T(
    nearColor: nearColor,
    farColor: farColor,
    density: density,
    falloff: falloff,
    limit: limit,
  )

proc init*(
    T: typedesc[SkyRenderOptions],
    horizonColor = vec3(0.72'f32, 0.8'f32, 0.86'f32),
    zenithColor = vec3(0.42'f32, 0.56'f32, 0.66'f32),
    groundColor = vec3(0.45'f32, 0.5'f32, 0.48'f32),
    exposure = 1'f32,
    useSkybox = false,
): T =
  T(
    horizonColor: horizonColor,
    zenithColor: zenithColor,
    groundColor: groundColor,
    exposure: exposure,
    useSkybox: useSkybox,
  )

proc init*(
    T: typedesc[RenderOptions],
    mode = SolidMesh,
    depthTest = true,
    depthWrite = true,
    baseColor = vec3(0.9'f32, 0.52'f32, 0.22'f32),
    materialID = "",
    fog = FogRenderOptions.init(),
): T =
  T(
    effect: StandardEffect,
    mode: mode,
    depthTest: depthTest,
    depthWrite: depthWrite,
    baseColor: baseColor,
    materialID: materialID,
    fog: fog,
    water: WaterRenderOptions.init(),
  )

proc init*(
    T: typedesc[Model],
    meshID: MeshID,
    transform = identityMat4(),
    renderOptions = RenderOptions.init(),
): T =
  T(meshID: meshID, transform: transform, renderOptions: renderOptions)

proc viewProjection(artist: Artist3DState): Mat4 =
  let aspect =
    if artist.textureHeight == 0:
      1'f32
    else:
      artist.textureWidth.float32 / artist.textureHeight.float32
  let projection =
    forwardPerspective(DefaultFovY, aspect, DefaultNearPlane, DefaultFarPlane)
  projection * artist.activeCamera.viewMatrix

proc transformUniforms(artist: Artist3DState,
    modelTransform: Mat4): TransformUniforms =
  result.model = modelTransform
  result.modelViewProjection = artist.viewProjection * modelTransform

proc lightingUniforms(artist: Artist3DState, model: Model): LightingUniforms =
  result.cameraPosition = artist.activeCamera.position
  result.baseColor = model.renderOptions.baseColor
  result.fogNearColor = model.renderOptions.fog.nearColor
  result.fogFarColor = model.renderOptions.fog.farColor
  result.fogDensity = max(model.renderOptions.fog.density, 0'f32)
  result.fogFalloff = max(model.renderOptions.fog.falloff, 0.001'f32)
  result.fogLimit = max(model.renderOptions.fog.limit, 0.001'f32)
  result.specularStrength = DefaultSpecularStrength
  if model.renderOptions.materialID.len > 0 and
      artist.materials.hasKey(model.renderOptions.materialID):
    let material = artist.materials[model.renderOptions.materialID].material
    result.baseColor = material.baseColor
    result.specularStrength = max(material.specularStrength, 0'f32)
    result.useTexture =
      if material.useTexture and material.texture != nil and
          material.texture.pixels.len > 0:
        1'f32
      else:
        0'f32
    result.splat = vec4(
      if material.textureSampling == Splat: 1'f32 else: 0'f32,
      max(material.atlasColumns, 1).float32,
      max(material.atlasRows, 1).float32,
      0,
    )

proc waterUniforms(artist: Artist3DState, model: Model): WaterUniforms =
  let water = model.renderOptions.water
  result.cameraPosition = artist.activeCamera.position
  result.time = water.time
  result.surfaceColor = water.surfaceColor
  result.waveAmplitude = water.waveAmplitude
  result.deepColor = water.deepColor
  result.waveLength = max(water.waveLength, 0.001'f32)
  result.opacity = clamp(water.opacity, 0'f32, 1'f32)
  result.waveSpeed = water.waveSpeed
  result.specularStrength = max(water.specularStrength, 0'f32)
  result.fogNearColor = model.renderOptions.fog.nearColor
  result.fogFarColor = model.renderOptions.fog.farColor
  result.fogDensity = max(model.renderOptions.fog.density, 0'f32)
  result.fogFalloff = max(model.renderOptions.fog.falloff, 0.001'f32)
  result.fogLimit = max(model.renderOptions.fog.limit, 0.001'f32)

proc skyUniforms(artist: Artist3DState, sky: SkyRenderOptions): SkyUniforms =
  result.inverseViewProjection = inverse(artist.viewProjection)
  result.cameraPosition = artist.activeCamera.position
  result.exposure = max(sky.exposure, 0'f32)
  result.horizonColor = sky.horizonColor
  result.zenithColor = sky.zenithColor
  result.groundColor = sky.groundColor
  result.useSkybox = if sky.useSkybox: 1'f32 else: 0'f32

proc releaseRenderTarget(artist: var Artist3DState) =
  if not artist.renderTexture.isNil:
    destroyTexture(artist.renderTexture)
    artist.renderTexture = nil
  if not artist.colorTexture.isNil:
    releaseGPUTexture(artist.device, artist.colorTexture)
    artist.colorTexture = nil
  if not artist.depthTexture.isNil:
    releaseGPUTexture(artist.device, artist.depthTexture)
    artist.depthTexture = nil
  artist.textureWidth = 0
  artist.textureHeight = 0

proc releaseMeshBuffers(artist: var Artist3DState, mesh: var Mesh) =
  if not mesh.vertexBuffer.isNil:
    releaseGPUBuffer(artist.device, mesh.vertexBuffer)
    mesh.vertexBuffer = nil
  if not mesh.indexBuffer.isNil:
    releaseGPUBuffer(artist.device, mesh.indexBuffer)
    mesh.indexBuffer = nil
  mesh.vertexBufferSize = 0
  mesh.indexBufferSize = 0

proc releaseMeshBuffers(artist: var Artist3DState) =
  for mesh in artist.meshes.mvalues:
    artist.releaseMeshBuffers(mesh)

proc releaseMaterials(artist: var Artist3DState) =
  for material in artist.materials.mvalues:
    if material.texture != nil:
      releaseGPUTexture(artist.device, material.texture)
      material.texture = nil
  artist.materials.clear()
  if artist.whiteTexture != nil:
    releaseGPUTexture(artist.device, artist.whiteTexture)
    artist.whiteTexture = nil
  if artist.samplerReady:
    releaseGpuSampler(artist.device, artist.sampler)
    artist.sampler = nil
    artist.samplerReady = false

proc releasePipelines(artist: var Artist3DState) =
  if not artist.solidPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.solidPipeline)
    artist.solidPipeline = nil
  if not artist.overlayPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.overlayPipeline)
    artist.overlayPipeline = nil
  if not artist.wireframePipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.wireframePipeline)
    artist.wireframePipeline = nil
  if not artist.overlayWireframePipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.overlayWireframePipeline)
    artist.overlayWireframePipeline = nil
  if not artist.waterPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.waterPipeline)
    artist.waterPipeline = nil
  if not artist.skyPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.skyPipeline)
    artist.skyPipeline = nil

proc createMeshBuffer(
    artist: var Artist3DState, usage: GPUBufferUsageFlags, size: uint32,
        context: string
): GPUBuffer =
  var info = GPUBufferCreateInfo(usage: usage, size: size)
  result = createGPUBuffer(artist.device, addr info)
  if result.isNil:
    raiseGpuError(context)

proc ensureVertexBuffer(artist: var Artist3DState, mesh: var Mesh,
    bufferSize: uint32) =
  if bufferSize == 0:
    return
  if mesh.vertexBuffer.isNil or mesh.vertexBufferSize < bufferSize:
    if not mesh.vertexBuffer.isNil:
      releaseGPUBuffer(artist.device, mesh.vertexBuffer)
    mesh.vertexBuffer = artist.createMeshBuffer(
      GPU_BUFFERUSAGE_VERTEX.GPUBufferUsageFlags, bufferSize,
      "Failed to create GPU vertex buffer",
    )
    mesh.vertexBufferSize = bufferSize
    mesh.verticesDirty = true

proc ensureIndexBuffer(artist: var Artist3DState, mesh: var Mesh,
    bufferSize: uint32) =
  if bufferSize == 0:
    return
  if mesh.indexBuffer.isNil or mesh.indexBufferSize < bufferSize:
    if not mesh.indexBuffer.isNil:
      releaseGPUBuffer(artist.device, mesh.indexBuffer)
    mesh.indexBuffer = artist.createMeshBuffer(
      GPU_BUFFERUSAGE_INDEX.GPUBufferUsageFlags, bufferSize,
      "Failed to create GPU index buffer",
    )
    mesh.indexBufferSize = bufferSize
    mesh.indicesDirty = true

proc uploadBytesToGpuBuffer(
    artist: var Artist3DState,
    commandBuffer: GPUCommandBuffer,
    buffer: GPUBuffer,
    sourceBytes: pointer,
    bufferSize: uint32,
    context: string,
): GPUTransferBuffer =
  if bufferSize == 0:
    return

  var transferInfo =
    GPUTransferBufferCreateInfo(usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        size: bufferSize)
  let transferBuffer = createGPUTransferBuffer(artist.device, addr transferInfo)
  if transferBuffer.isNil:
    raiseGpuError("Failed to create GPU transfer buffer for " & context)

  let mapped = mapGPUTransferBuffer(artist.device, transferBuffer, false)
  if mapped.isNil:
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to map GPU transfer buffer for " & context)
  copyMem(mapped, sourceBytes, bufferSize)
  unmapGPUTransferBuffer(artist.device, transferBuffer)

  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to begin GPU copy pass for " & context)

  var source = GpuTransferBufferLocation(transfer_buffer: transferBuffer, offset: 0)
  var destination = GpuBufferRegion(buffer: buffer, offset: 0, size: bufferSize)
  uploadToGpuBuffer(copyPass, addr source, addr destination, true)
  endGPUCopyPass(copyPass)
  transferBuffer

proc createSampledTexture(
    artist: var Artist3DState, width, height: uint32, context: string
): GPUTexture =
  var textureInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER.GPUTextureUsageFlags,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: GPU_SAMPLECOUNT_1,
  )
  result = createGPUTexture(artist.device, addr textureInfo)
  if result.isNil:
    raiseGpuError(context)

proc uploadBytesToGpuTexture(
    artist: var Artist3DState,
    commandBuffer: GPUCommandBuffer,
    texture: GPUTexture,
    sourceBytes: pointer,
    width, height: uint32,
    context: string,
): GPUTransferBuffer =
  let bufferSize = width * height * 4
  if bufferSize == 0:
    return

  var transferInfo =
    GPUTransferBufferCreateInfo(usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        size: bufferSize)
  let transferBuffer = createGPUTransferBuffer(artist.device, addr transferInfo)
  if transferBuffer.isNil:
    raiseGpuError("Failed to create GPU transfer buffer for " & context)

  let mapped = mapGPUTransferBuffer(artist.device, transferBuffer, false)
  if mapped.isNil:
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to map GPU transfer buffer for " & context)
  copyMem(mapped, sourceBytes, bufferSize)
  unmapGPUTransferBuffer(artist.device, transferBuffer)

  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to begin GPU copy pass for " & context)

  var source = GpuTextureTransferInfo(
    transfer_buffer: transferBuffer,
    offset: 0,
    pixels_per_row: width,
    rows_per_layer: height,
  )
  var destination = GpuTextureRegion(
    texture: texture,
    mip_level: 0,
    layer: 0,
    x: 0,
    y: 0,
    z: 0,
    w: width,
    h: height,
    d: 1,
  )
  uploadToGpuTexture(copyPass, addr source, addr destination, true)
  endGPUCopyPass(copyPass)
  transferBuffer

proc uploadTexturePixels(
    artist: var Artist3DState,
    texture: GPUTexture,
    pixels: var seq[uint8],
    width, height: uint32,
    context: string,
) =
  if texture == nil or pixels.len == 0:
    return
  let commandBuffer = acquireGPUCommandBuffer(artist.device)
  if commandBuffer.isNil:
    raiseGpuError("Failed to acquire GPU command buffer")
  let transferBuffer = artist.uploadBytesToGpuTexture(
    commandBuffer,
    texture,
    unsafeAddr pixels[0],
    width,
    height,
    context,
  )
  defer:
    if transferBuffer != nil:
      releaseGPUTransferBuffer(artist.device, transferBuffer)
  if not submitGPUCommandBuffer(commandBuffer):
    raiseGpuError("Failed to submit GPU texture upload")

proc ensureSampler(artist: var Artist3DState) =
  if artist.device.isNil or artist.samplerReady:
    return
  let filter =
    if artist.textureFiltering:
      GPU_FILTER_LINEAR
    else:
      GPU_FILTER_NEAREST
  let mipmapMode =
    if artist.textureFiltering:
      GPU_SAMPLERMIPMAPMODE_LINEAR
    else:
      GPU_SAMPLERMIPMAPMODE_NEAREST
  var samplerInfo = GPUSamplerCreateInfo(
    min_filter: filter,
    mag_filter: filter,
    mipmap_mode: mipmapMode,
    address_mode_u: GPU_SAMPLERADDRESSMODE_REPEAT,
    address_mode_v: GPU_SAMPLERADDRESSMODE_REPEAT,
    address_mode_w: GPU_SAMPLERADDRESSMODE_REPEAT,
  )
  artist.sampler = createGpuSampler(artist.device, addr samplerInfo)
  if artist.sampler.isNil:
    raiseGpuError("Failed to create GPU sampler")
  artist.samplerReady = true

proc ensureWhiteTexture(artist: var Artist3DState) =
  if artist.device.isNil or artist.whiteTexture != nil:
    return
  artist.whiteTexture = artist.createSampledTexture(1, 1,
      "Failed to create default texture")
  var pixels = @[255'u8, 255, 255, 255]
  artist.uploadTexturePixels(artist.whiteTexture, pixels, 1, 1, "default texture")

proc uploadMaterialTexture(artist: var Artist3DState, materialID: string) =
  if artist.device.isNil or not artist.materials.hasKey(materialID):
    return
  var gpuMaterial = artist.materials[materialID]
  defer:
    artist.materials[materialID] = gpuMaterial
  if not gpuMaterial.textureDirty:
    return
  if gpuMaterial.texture != nil:
    releaseGPUTexture(artist.device, gpuMaterial.texture)
    gpuMaterial.texture = nil
  gpuMaterial.textureWidth = 0
  gpuMaterial.textureHeight = 0

  let texture = gpuMaterial.material.texture
  if texture == nil or texture.pixels.len == 0 or texture.width <= 0 or
      texture.height <= 0:
    gpuMaterial.textureDirty = false
    return

  gpuMaterial.texture = artist.createSampledTexture(
    texture.width.uint32,
    texture.height.uint32,
    "Failed to create material texture",
  )
  var pixels = texture.pixels
  artist.uploadTexturePixels(
    gpuMaterial.texture,
    pixels,
    texture.width.uint32,
    texture.height.uint32,
    "material texture",
  )
  gpuMaterial.textureWidth = texture.width.uint32
  gpuMaterial.textureHeight = texture.height.uint32
  gpuMaterial.textureDirty = false

proc uploadMesh(artist: var Artist3DState, meshID: MeshID) =
  if artist.device.isNil:
    return
  if not artist.meshes.hasKey(meshID):
    return
  var mesh = artist.meshes[meshID]
  defer:
    artist.meshes[meshID] = mesh
  if mesh.vertices.len == 0 or mesh.indices.len == 0:
    return

  let
    vertexBytes = uint32(mesh.vertices.len * sizeof(Vertex))
    indexBytes = uint32(mesh.indices.len * sizeof(uint32))
  artist.ensureVertexBuffer(mesh, vertexBytes)
  artist.ensureIndexBuffer(mesh, indexBytes)

  if not mesh.verticesDirty and not mesh.indicesDirty:
    return

  let commandBuffer = acquireGPUCommandBuffer(artist.device)
  if commandBuffer.isNil:
    raiseGpuError("Failed to acquire GPU command buffer")
  var transferBuffers: seq[GPUTransferBuffer]
  defer:
    for transferBuffer in transferBuffers:
      releaseGPUTransferBuffer(artist.device, transferBuffer)

  if mesh.verticesDirty:
    transferBuffers.add(
      artist.uploadBytesToGpuBuffer(
        commandBuffer,
        mesh.vertexBuffer,
        unsafeAddr mesh.vertices[0],
        vertexBytes,
        "vertices",
      )
    )
  if mesh.indicesDirty:
    transferBuffers.add(
      artist.uploadBytesToGpuBuffer(
        commandBuffer,
        mesh.indexBuffer,
        unsafeAddr mesh.indices[0],
        indexBytes,
        "indices",
      )
    )

  if not submitGPUCommandBuffer(commandBuffer):
    raiseGpuError("Failed to submit GPU mesh upload")
  mesh.verticesDirty = false
  mesh.indicesDirty = false

proc createTrianglePipeline(
    artist: var Artist3DState, mode: MeshRenderMode, depthTest, depthWrite: bool
): GPUGraphicsPipeline =
  var vertexBuffers = [
    GPUVertexBufferDescription(
      slot: 0, pitch: sizeof(Vertex).uint32,
          input_rate: GPU_VERTEXINPUTRATE_VERTEX
    )
  ]
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT3,
      offset: offsetof(Vertex, position).uint32,
    ),
    GPUVertexAttribute(
      location: 1,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT3,
      offset: offsetof(Vertex, normal).uint32,
    ),
    GPUVertexAttribute(
      location: 2,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT2,
      offset: offsetof(Vertex, uv).uint32,
    ),
    GPUVertexAttribute(
      location: 3,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT2,
      offset: offsetof(Vertex, splatUv).uint32,
    ),
    GPUVertexAttribute(
      location: 4,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT4,
      offset: offsetof(Vertex, splatIndices).uint32,
    ),
    GPUVertexAttribute(
      location: 5,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT4,
      offset: offsetof(Vertex, splatWeights).uint32,
    ),
  ]
  var colorTarget = GPUColorTargetDescription(
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    blend_state: GPUColorTargetBlendState(
      color_write_mask: (
        GPU_COLORCOMPONENT_R or GPU_COLORCOMPONENT_G or GPU_COLORCOMPONENT_B or
        GPU_COLORCOMPONENT_A
    ).GPUColorComponentFlags,
    enable_color_write_mask: true,
  ),
  )
  var targetInfo = GPUGraphicsPipelineTargetInfo(
    color_target_descriptions:
    cast[ptr UncheckedArray[GPUColorTargetDescription]](addr colorTarget),
    num_color_targets: 1,
    depth_stencil_format: GPU_TEXTUREFORMAT_D16_UNORM,
    has_depth_stencil_target: true,
  )
  var pipelineInfo = GpuGraphicsPipelineCreateInfo(
    vertex_shader: artist.vertexShader,
    fragment_shader: artist.fragmentShader,
    vertex_input_state: GPUVertexInputState(
      vertex_buffer_descriptions:
    cast[ptr UncheckedArray[GPUVertexBufferDescription]](addr vertexBuffers[0]),
      num_vertex_buffers: vertexBuffers.len.uint32,
      vertex_attributes:
    cast[ptr UncheckedArray[GPUVertexAttribute]](addr vertexAttributes[0]),
      num_vertex_attributes: vertexAttributes.len.uint32,
    ),
    primitive_type: GPU_PRIMITIVETYPE_TRIANGLELIST,
    rasterizer_state: GPURasterizerState(
      fill_mode: if mode == WireframeMesh: GPU_FILLMODE_LINE else: GPU_FILLMODE_FILL,
      cull_mode: if mode == WireframeMesh: GPU_CULLMODE_NONE else: GPU_CULLMODE_BACK,
      front_face: GPU_FRONTFACE_CLOCKWISE,
    ),
    multisample_state: GPUMultisampleState(sample_count: GPU_SAMPLECOUNT_1),
    depth_stencil_state: GPUDepthStencilState(
      compare_op: GPU_COMPAREOP_LESS_OR_EQUAL,
      enable_depth_test: depthTest,
      enable_depth_write: depthWrite,
    ),
    target_info: targetInfo,
  )
  result = createGpuGraphicsPipeline(artist.device, addr pipelineInfo)
  if result.isNil:
    raiseGpuError("Failed to create GPU graphics pipeline")

proc createWaterPipeline(artist: var Artist3DState): GPUGraphicsPipeline =
  var vertexBuffers = [
    GPUVertexBufferDescription(
      slot: 0, pitch: sizeof(Vertex).uint32,
          input_rate: GPU_VERTEXINPUTRATE_VERTEX
    )
  ]
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT3,
      offset: offsetof(Vertex, position).uint32,
    ),
    GPUVertexAttribute(
      location: 1,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT3,
      offset: offsetof(Vertex, normal).uint32,
    ),
    GPUVertexAttribute(
      location: 2,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT2,
      offset: offsetof(Vertex, uv).uint32,
    ),
  ]
  var colorTarget = GPUColorTargetDescription(
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    blend_state: GPUColorTargetBlendState(
      src_color_blendfactor: GPU_BLENDFACTOR_SRC_ALPHA,
      dst_color_blendfactor: GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
      color_blend_op: GPU_BLENDOP_ADD,
      src_alpha_blendfactor: GPU_BLENDFACTOR_ONE,
      dst_alpha_blendfactor: GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
      alpha_blend_op: GPU_BLENDOP_ADD,
      color_write_mask: (
        GPU_COLORCOMPONENT_R or GPU_COLORCOMPONENT_G or GPU_COLORCOMPONENT_B or
        GPU_COLORCOMPONENT_A
    ).GPUColorComponentFlags,
    enable_blend: true,
    enable_color_write_mask: true,
  ),
  )
  var targetInfo = GPUGraphicsPipelineTargetInfo(
    color_target_descriptions:
    cast[ptr UncheckedArray[GPUColorTargetDescription]](addr colorTarget),
    num_color_targets: 1,
    depth_stencil_format: GPU_TEXTUREFORMAT_D16_UNORM,
    has_depth_stencil_target: true,
  )
  var pipelineInfo = GpuGraphicsPipelineCreateInfo(
    vertex_shader: artist.waterVertexShader,
    fragment_shader: artist.waterFragmentShader,
    vertex_input_state: GPUVertexInputState(
      vertex_buffer_descriptions:
    cast[ptr UncheckedArray[GPUVertexBufferDescription]](addr vertexBuffers[0]),
      num_vertex_buffers: vertexBuffers.len.uint32,
      vertex_attributes:
    cast[ptr UncheckedArray[GPUVertexAttribute]](addr vertexAttributes[0]),
      num_vertex_attributes: vertexAttributes.len.uint32,
    ),
    primitive_type: GPU_PRIMITIVETYPE_TRIANGLELIST,
    rasterizer_state: GPURasterizerState(
      fill_mode: GPU_FILLMODE_FILL,
      cull_mode: GPU_CULLMODE_NONE,
      front_face: GPU_FRONTFACE_CLOCKWISE,
    ),
    multisample_state: GPUMultisampleState(sample_count: GPU_SAMPLECOUNT_1),
    depth_stencil_state: GPUDepthStencilState(
      compare_op: GPU_COMPAREOP_LESS_OR_EQUAL,
      enable_depth_test: true,
      enable_depth_write: false,
    ),
    target_info: targetInfo,
  )
  result = createGpuGraphicsPipeline(artist.device, addr pipelineInfo)
  if result.isNil:
    raiseGpuError("Failed to create GPU water pipeline")

proc createSkyPipeline(artist: var Artist3DState): GPUGraphicsPipeline =
  var colorTarget = GPUColorTargetDescription(
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    blend_state: GPUColorTargetBlendState(
      color_write_mask: (
        GPU_COLORCOMPONENT_R or GPU_COLORCOMPONENT_G or GPU_COLORCOMPONENT_B or
        GPU_COLORCOMPONENT_A
    ).GPUColorComponentFlags,
      enable_color_write_mask: true,
    ),
  )
  var targetInfo = GPUGraphicsPipelineTargetInfo(
    color_target_descriptions:
    cast[ptr UncheckedArray[GPUColorTargetDescription]](addr colorTarget),
    num_color_targets: 1,
    depth_stencil_format: GPU_TEXTUREFORMAT_D16_UNORM,
    has_depth_stencil_target: true,
  )
  var pipelineInfo = GpuGraphicsPipelineCreateInfo(
    vertex_shader: artist.skyVertexShader,
    fragment_shader: artist.skyFragmentShader,
    primitive_type: GPU_PRIMITIVETYPE_TRIANGLELIST,
    rasterizer_state: GPURasterizerState(
      fill_mode: GPU_FILLMODE_FILL,
      cull_mode: GPU_CULLMODE_NONE,
      front_face: GPU_FRONTFACE_CLOCKWISE,
    ),
    multisample_state: GPUMultisampleState(sample_count: GPU_SAMPLECOUNT_1),
    depth_stencil_state: GPUDepthStencilState(
      compare_op: GPU_COMPAREOP_ALWAYS,
      enable_depth_test: false,
      enable_depth_write: false,
    ),
    target_info: targetInfo,
  )
  result = createGpuGraphicsPipeline(artist.device, addr pipelineInfo)
  if result.isNil:
    raiseGpuError("Failed to create GPU sky pipeline")

proc createTrianglePipelines(artist: var Artist3DState) =
  artist.releasePipelines()
  artist.vertexShader =
    createShader(artist.device, "triangle.vert.spv", GPU_SHADERSTAGE_VERTEX)
  artist.fragmentShader =
    createShader(
      artist.device, "triangle.frag.spv", GPU_SHADERSTAGE_FRAGMENT, samplers = 1
    )
  artist.waterVertexShader =
    createShader(artist.device, "water.vert.spv", GPU_SHADERSTAGE_VERTEX, 2)
  artist.waterFragmentShader =
    createShader(artist.device, "water.frag.spv", GPU_SHADERSTAGE_FRAGMENT, 2)
  artist.skyVertexShader =
    createShader(artist.device, "sky.vert.spv", GPU_SHADERSTAGE_VERTEX)
  artist.skyFragmentShader =
    createShader(artist.device, "sky.frag.spv", GPU_SHADERSTAGE_FRAGMENT)
  artist.solidPipeline = artist.createTrianglePipeline(SolidMesh, true, true)
  artist.overlayPipeline = artist.createTrianglePipeline(SolidMesh, false, false)
  artist.wireframePipeline = artist.createTrianglePipeline(WireframeMesh, true, false)
  artist.overlayWireframePipeline = artist.createTrianglePipeline(
    WireframeMesh, false, false
  )
  artist.waterPipeline = artist.createWaterPipeline()
  artist.skyPipeline = artist.createSkyPipeline()

proc installArtist3DRenderer*(renderer: Renderer) =
  defaultRenderer = renderer

proc initWithRenderer(artist: var Artist3DState, renderer: Renderer) =
  artist.renderer = renderer
  artist.device = cast[GPUDevice](getPointerProperty(
    getRendererProperties(renderer), PROP_RENDERER_GPU_DEVICE_POINTER, nil
  ))
  if artist.device.isNil:
    raiseGpuError("SDL renderer is not the GPU renderer")
  artist.ensureSampler()
  artist.ensureWhiteTexture()
  artist.createTrianglePipelines()
  for meshID in artist.meshes.keys:
    artist.uploadMesh(meshID)
  for materialID in artist.materials.keys:
    artist.uploadMaterialTexture(materialID)

proc activeCamera*(artist: Artist3DState): cameras.Camera =
  if not artist.allCameras.hasKey(artist.activeCameraID):
    return
  result = artist.allCameras[artist.activeCameraID]

proc init*(T: typedesc[Artist3D], renderer: Renderer): T =
  new result.state
  result.state.defaultModel = Model.init(DefaultMeshID)
  result.state[].initWithRenderer(renderer)
  result.state.activeCameraID = DefaultCameraID
  result.state.allCameras[DefaultCameraID] = cameras.Camera(position: vec3(0, 0, -4))
  result.state.allCameras[DefaultCameraID].lookAt(vec3(0, 0, 0))

proc setVertices*(artist: Artist3D, meshID: MeshID, vertices: openArray[Vertex]) =
  if artist.state.isNil:
    return
  var mesh = artist.state.meshes.getOrDefault(meshID)
  mesh.vertices = @vertices
  mesh.verticesDirty = true
  artist.state.meshes[meshID] = mesh

proc setVertices*(artist: Artist3D, vertices: openArray[Vertex]) =
  artist.setVertices(DefaultMeshID, vertices)

proc setIndices*(artist: Artist3D, meshID: MeshID, indices: openArray[uint32]) =
  if artist.state.isNil:
    return
  var mesh = artist.state.meshes.getOrDefault(meshID)
  mesh.indices = @indices
  mesh.indicesDirty = true
  artist.state.meshes[meshID] = mesh

proc setIndices*(artist: Artist3D, indices: openArray[uint32]) =
  artist.setIndices(DefaultMeshID, indices)

proc setMesh*(
    artist: Artist3D,
    meshID: MeshID,
    vertices: openArray[Vertex],
    indices: openArray[uint32],
) =
  if artist.state.isNil:
    return
  var mesh = artist.state.meshes.getOrDefault(meshID)
  mesh.vertices = @vertices
  mesh.indices = @indices
  mesh.verticesDirty = true
  mesh.indicesDirty = true
  artist.state.meshes[meshID] = mesh

proc setMesh*(
    artist: Artist3D, vertices: openArray[Vertex], indices: openArray[uint32]
) =
  artist.setMesh(DefaultMeshID, vertices, indices)

proc setMaterial*(artist: Artist3D, material: Material) =
  if artist.state.isNil or material.id.len == 0:
    return
  var gpuMaterial = artist.state.materials.getOrDefault(material.id)
  let changed =
    gpuMaterial.material.texture != material.texture or
    gpuMaterial.material.useTexture != material.useTexture
  gpuMaterial.material = material
  gpuMaterial.textureDirty = gpuMaterial.textureDirty or changed or
      (material.useTexture and gpuMaterial.texture == nil)
  artist.state.materials[material.id] = gpuMaterial

proc material*(artist: Artist3D, id: string): Material =
  if artist.state.isNil or not artist.state.materials.hasKey(id):
    return Material(id: id, baseColor: vec3(1, 1, 1))
  artist.state.materials[id].material

proc vertices*(artist: Artist3D): var seq[Vertex] =
  doAssert not artist.state.isNil
  artist.state.meshes[DefaultMeshID].vertices

proc vertices*(artist: Artist3D, meshID: MeshID): var seq[Vertex] =
  doAssert not artist.state.isNil
  doAssert artist.state.meshes.hasKey(meshID)
  artist.state.meshes[meshID].vertices

proc indices*(artist: Artist3D): var seq[uint32] =
  doAssert not artist.state.isNil
  artist.state.meshes[DefaultMeshID].indices

proc indices*(artist: Artist3D, meshID: MeshID): var seq[uint32] =
  doAssert not artist.state.isNil
  doAssert artist.state.meshes.hasKey(meshID)
  artist.state.meshes[meshID].indices

proc markVerticesDirty*(artist: Artist3D, meshID: MeshID) =
  if artist.state.isNil:
    return
  if artist.state.meshes.hasKey(meshID):
    artist.state.meshes[meshID].verticesDirty = true

proc markVerticesDirty*(artist: Artist3D) =
  artist.markVerticesDirty(DefaultMeshID)

proc markIndicesDirty*(artist: Artist3D, meshID: MeshID) =
  if artist.state.isNil:
    return
  if artist.state.meshes.hasKey(meshID):
    artist.state.meshes[meshID].indicesDirty = true

proc markIndicesDirty*(artist: Artist3D) =
  artist.markIndicesDirty(DefaultMeshID)

proc markMeshDirty*(artist: Artist3D, meshID: MeshID) =
  if artist.state.isNil:
    return
  if artist.state.meshes.hasKey(meshID):
    artist.state.meshes[meshID].verticesDirty = true
    artist.state.meshes[meshID].indicesDirty = true

proc markMeshDirty*(artist: Artist3D) =
  artist.markMeshDirty(DefaultMeshID)

proc createPlaneMesh*(
    size = vec2(1'f32, 1'f32), subdivisions = 96
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let steps = max(subdivisions, 1)
  for z in 0 .. steps:
    for x in 0 .. steps:
      let
        u = x.float32 / steps.float32
        v = z.float32 / steps.float32
        position = vec3((u - 0.5'f32) * size.x, 0, (v - 0.5'f32) * size.y)
      result.vertices.add Vertex(position: position, normal: vec3(0, 1, 0),
          uv: vec2(u, v))
  for z in 0 ..< steps:
    for x in 0 ..< steps:
      let
        a = (z * (steps + 1) + x).uint32
        b = a + 1
        c = ((z + 1) * (steps + 1) + x).uint32
        d = c + 1
      result.indices.add a
      result.indices.add c
      result.indices.add b
      result.indices.add b
      result.indices.add c
      result.indices.add d

proc defaultModel*(artist: Artist3D): Model =
  if artist.state.isNil:
    return Model.init(DefaultMeshID)
  artist.state.defaultModel

proc `defaultModel=`*(artist: Artist3D, model: Model) =
  if artist.state.isNil:
    return
  artist.state.defaultModel = model

proc activeCamera*(artist: Artist3D): cameras.Camera =
  if artist.state.isNil:
    return
  artist.state[].activeCamera

proc `activeCamera=`*(artist: Artist3D, camera: cameras.Camera) =
  if artist.state.isNil:
    return
  artist.state.allCameras[artist.state.activeCameraID] = camera

proc setActiveCamera*(artist: Artist3D, id: string, camera: cameras.Camera) =
  if artist.state.isNil:
    return
  artist.state.allCameras[id] = camera
  artist.state.activeCameraID = id

proc textureFiltering*(artist: Artist3D): bool =
  if artist.state.isNil:
    return false
  artist.state.textureFiltering

proc `textureFiltering=`*(artist: Artist3D, filtering: bool) =
  if artist.state.isNil:
    return
  if artist.state.textureFiltering == filtering:
    return
  artist.state.textureFiltering = filtering
  if artist.state.samplerReady:
    releaseGpuSampler(artist.state.device, artist.state.sampler)
    artist.state.sampler = nil
    artist.state.samplerReady = false
    artist.state[].ensureSampler()

proc createRenderTarget(artist: var Artist3DState, width, height: uint32) =
  artist.releaseRenderTarget()

  var textureInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage:
    (GPU_TEXTUREUSAGE_COLOR_TARGET or GPU_TEXTUREUSAGE_SAMPLER).GPUTextureUsageFlags,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: GPU_SAMPLECOUNT_1,
  )
  artist.colorTexture = createGPUTexture(artist.device, addr textureInfo)
  if artist.colorTexture.isNil:
    raiseGpuError("Failed to create GPU color target")

  var depthTextureInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_2D,
    format: GPU_TEXTUREFORMAT_D16_UNORM,
    usage: GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET.GPUTextureUsageFlags,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: GPU_SAMPLECOUNT_1,
  )
  artist.depthTexture = createGPUTexture(artist.device, addr depthTextureInfo)
  if artist.depthTexture.isNil:
    artist.releaseRenderTarget()
    raiseGpuError("Failed to create GPU depth target")

  let props = createProperties()
  if props == 0:
    raiseGpuError("Failed to create texture properties")
  defer:
    destroyProperties(props)
  discard setNumberProperty(props, PROP_TEXTURE_CREATE_WIDTH_NUMBER, width.int64)
  discard setNumberProperty(props, PROP_TEXTURE_CREATE_HEIGHT_NUMBER, height.int64)
  discard setNumberProperty(
    props, PROP_TEXTURE_CREATE_FORMAT_NUMBER, PIXELFORMAT_RGBA32.int64
  )
  discard setNumberProperty(
    props, PROP_TEXTURE_CREATE_ACCESS_NUMBER, TEXTUREACCESS_STATIC.int64
  )
  discard setPointerProperty(
    props, PropTextureCreateGpuTexture, cast[pointer](artist.colorTexture)
  )
  artist.renderTexture = createTextureWithProperties(artist.renderer, props)
  if artist.renderTexture.isNil:
    artist.releaseRenderTarget()
    raiseGpuError("Failed to wrap GPU color target as SDL texture")

  artist.textureWidth = width
  artist.textureHeight = height

proc ensureReady(artist: var Artist3DState) =
  if artist.device.isNil:
    if defaultRenderer.isNil:
      return
    artist.initWithRenderer(defaultRenderer)

  var width, height: cint
  if not getRenderOutputSize(artist.renderer, width, height):
    raiseGpuError("Failed to get render output size")
  if width <= 0 or height <= 0:
    return
  if artist.colorTexture.isNil or artist.depthTexture.isNil or
      artist.textureWidth != width.uint32 or artist.textureHeight != height.uint32:
    artist.createRenderTarget(width.uint32, height.uint32)

proc `=destroy`*(artist: var Artist3D) =
  if not artist.state.isNil and not artist.state.device.isNil:
    artist.state[].releaseRenderTarget()
    artist.state[].releaseMeshBuffers()
    artist.state[].releaseMaterials()
    artist.state[].releasePipelines()

proc drawModel(
    state: var Artist3DState,
    pass: GPURenderPass,
    commandBuffer: GPUCommandBuffer,
    model: Model,
    extraTransform: Mat4,
) =
  if not state.meshes.hasKey(model.meshID):
    return
  let mesh = state.meshes[model.meshID]
  if mesh.vertexBuffer.isNil or mesh.indexBuffer.isNil or mesh.indices.len == 0:
    return

  let pipeline =
    case model.renderOptions.effect
    of WaterEffect:
      state.waterPipeline
    of StandardEffect:
      if not model.renderOptions.depthTest:
        case model.renderOptions.mode
        of SolidMesh: state.overlayPipeline
        of WireframeMesh: state.overlayWireframePipeline
      else:
        case model.renderOptions.mode
        of SolidMesh: state.solidPipeline
        of WireframeMesh: state.wireframePipeline
  if pipeline.isNil:
    return

  var binding = GpuBufferBinding(buffer: mesh.vertexBuffer, offset: 0)
  var indexBinding = GpuBufferBinding(buffer: mesh.indexBuffer, offset: 0)
  var uniforms = state.transformUniforms(extraTransform * model.transform)
  var lighting = state.lightingUniforms(model)
  var water = state.waterUniforms(model)
  var texture = state.whiteTexture
  if model.renderOptions.materialID.len > 0 and
      state.materials.hasKey(model.renderOptions.materialID):
    let material = state.materials[model.renderOptions.materialID]
    if material.texture != nil:
      texture = material.texture
  var samplerBinding = GpuTextureSamplerBinding(
    texture: texture,
    sampler: state.sampler,
  )
  if model.renderOptions.effect == StandardEffect and
      (texture.isNil or state.sampler.isNil):
    raiseGpuError("Missing GPU texture sampler binding")
  pushGPUVertexUniformData(
    commandBuffer, CameraUniformSlot, addr uniforms, sizeof(
        TransformUniforms).uint32
  )
  pushGPUFragmentUniformData(
    commandBuffer, 0, addr lighting, sizeof(LightingUniforms).uint32
  )
  if model.renderOptions.effect == WaterEffect:
    pushGPUVertexUniformData(
      commandBuffer, 1, addr water, sizeof(WaterUniforms).uint32
    )
    pushGPUFragmentUniformData(
      commandBuffer, 1, addr water, sizeof(WaterUniforms).uint32
    )
  bindGPUGraphicsPipeline(pass, pipeline)
  if model.renderOptions.effect == StandardEffect and state.samplerReady and
      texture != nil:
    bindGpuFragmentSamplers(pass, 0, addr samplerBinding, 1)
  bindGpuVertexBuffers(pass, 0, addr binding, 1)
  bindGpuIndexBuffer(pass, addr indexBinding, GPU_INDEXELEMENTSIZE_32BIT)
  drawGPUIndexedPrimitives(pass, mesh.indices.len.uint32, 1, 0, 0, 0)

proc drawSky(
    state: var Artist3DState,
    pass: GPURenderPass,
    commandBuffer: GPUCommandBuffer,
    sky: SkyRenderOptions,
) =
  if state.skyPipeline.isNil:
    return
  var uniforms = state.skyUniforms(sky)
  pushGPUVertexUniformData(
    commandBuffer, 0, addr uniforms, sizeof(SkyUniforms).uint32
  )
  pushGPUFragmentUniformData(
    commandBuffer, 0, addr uniforms, sizeof(SkyUniforms).uint32
  )
  bindGPUGraphicsPipeline(pass, state.skyPipeline)
  drawGPUPrimitives(pass, 3, 1, 0, 0)

proc render*(artist: Artist3D, models: openArray[Model],
    transform = identityMat4(), sky = SkyRenderOptions.init()) =
  if artist.state.isNil:
    return
  let state = artist.state
  state[].ensureReady()
  for model in models:
    state[].uploadMesh(model.meshID)
    if model.renderOptions.materialID.len > 0:
      state[].uploadMaterialTexture(model.renderOptions.materialID)
  if state.device.isNil or state.solidPipeline.isNil or
      state.overlayPipeline.isNil or state.wireframePipeline.isNil or
      state.overlayWireframePipeline.isNil or state.waterPipeline.isNil or
      state.skyPipeline.isNil or state.colorTexture.isNil:
    return

  discard flushRenderer(state.renderer)
  let commandBuffer = acquireGPUCommandBuffer(state.device)
  if commandBuffer.isNil:
    raiseGpuError("Failed to acquire GPU command buffer")

  var colorTargetInfo = GpuColorTargetInfo(
    texture: state.colorTexture,
    clear_color: FColor(r: 0.04, g: 0.05, b: 0.07, a: 1.0),
    load_op: GPU_LOADOP_CLEAR,
    store_op: GPU_STOREOP_STORE,
  )
  var depthTargetInfo = GpuDepthStencilTargetInfo(
    texture: state.depthTexture,
    clear_depth: 1.0,
    load_op: GPU_LOADOP_CLEAR,
    store_op: GPU_STOREOP_DONT_CARE,
    stencil_load_op: GPU_LOADOP_DONT_CARE,
    stencil_store_op: GPU_STOREOP_DONT_CARE,
  )
  let pass = beginGpuRenderPass(commandBuffer, addr colorTargetInfo, 1,
      addr depthTargetInfo)
  if pass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raiseGpuError("Failed to begin GPU render pass")

  state[].drawSky(pass, commandBuffer, sky)
  for model in models:
    if model.renderOptions.depthTest:
      state[].drawModel(pass, commandBuffer, model, transform)
  for model in models:
    if not model.renderOptions.depthTest:
      state[].drawModel(pass, commandBuffer, model, transform)
  endGPURenderPass(pass)

  if not submitGPUCommandBuffer(commandBuffer):
    raiseGpuError("Failed to submit GPU command buffer")

  var dst =
    FRect(x: 0, y: 0, w: state.textureWidth.cfloat,
        h: state.textureHeight.cfloat)
  discard renderTexture(state.renderer, state.renderTexture, nil, addr dst)

proc render*(artist: Artist3D, model: Model, transform = identityMat4()) =
  artist.render([model], transform)

proc render*(artist: Artist3D) =
  if artist.state.isNil:
    return
  artist.render(artist.state.defaultModel, identityMat4())
