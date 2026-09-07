import std/[os, strformat, strutils, tables]

import sdl3, vmath

import cameras
import canvas
import ../errors
import ../renderSettings
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
  MeshData* = object
    ## CPU-side geometry accepted by `setMesh` and `createModel`.
    vertices*: seq[Vertex]
    indices*: seq[uint32]

  UvRegion* = object
    ## Normalized origin and size of a region within a texture atlas.
    origin*, size*: Vec2

type
  MeshID* = string

  MeshRenderMode* = enum
    SolidMesh, WireframeMesh

  RenderEffect* = enum
    StandardEffect, WaterEffect

  RenderTarget* = enum
    ## Live textures produced for each frame of the 3D renderer.
    SceneColorTarget, DepthTarget, AmbientOcclusionTarget, CompositeTarget

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
    skybox*: TextureResourceHandle
    exposure*: float32
    useSkybox*: bool

  SsaoOptions* = object
    enabled*: bool
    radius*: float32
    strength*: float32
    bias*: float32

  RenderOptions* = object
    effect*: RenderEffect
    mode*: MeshRenderMode
    depthTest*: bool
    depthWrite*: bool
    baseColor*: Vec3
    materialID*: string
    uvRegion*: UvRegion
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

  GpuSkybox = object
    source: TextureResourceHandle
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
    lightingPadding0: Vec2
    lightDirection: Vec3
    ambientStrength: float32
    lightColor: Vec3
    diffuseStrength: float32
    specularColor: Vec3
    shininess: float32
    uvRegion: Vec4

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
    cameraRotation: Mat4
    viewportScale: Vec4
    horizonExposure: Vec4
    zenithUseSkybox: Vec4
    groundColor: Vec4

  DepthFogUniforms = object
    cameraPosition: Vec3
    fogLimit: float32

  SsaoUniforms = object
    resolutionRadius: Vec4
    projection: Vec4
    strengthBias: Vec4

type
  Artist3DState = object
    renderer: Renderer
    device: GPUDevice
    solidPipeline, overlayPipeline, wireframePipeline,
      overlayWireframePipeline: GPUGraphicsPipeline
    waterPipeline, skyPipeline, depthPipeline, ssaoPipeline, compositePipeline,
      depthPreviewPipeline: GPUGraphicsPipeline
    vertexShader, waterVertexShader, skyVertexShader,
      fullscreenVertexShader: GPUShader
    fragmentShader, waterFragmentShader, skyFragmentShader,
      ssaoFragmentShader: GPUShader
    compositeFragmentShader, depthPreviewFragmentShader, depthFragmentShader: GPUShader
    meshes: Table[MeshID, Mesh]
    materials: Table[string, GpuMaterial]
    sampler: pointer
    samplerReady: bool
    nearestSampler, linearSampler: pointer
    nearestSamplerReady, linearSamplerReady: bool
    textureFiltering*: bool
    whiteTexture: GPUTexture
    whiteCubeTexture: GPUTexture
    skybox: GpuSkybox
    defaultModel: Model
    colorTexture, depthTexture, multisampleColorTexture,
      multisampleDepthTexture, depthDataTexture, ssaoTexture,
      compositeTexture, depthPreviewTexture: GPUTexture
    renderTexture, ssaoRenderTexture, compositeRenderTexture,
      depthPreviewRenderTexture: Texture
    textureWidth, textureHeight: uint32
    sampleCount: GPUSampleCount
    ssao: SsaoOptions
    renderSettings: RenderSettings
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
  let packagedPath = getAppDir() / "shaders" / name
  if packagedPath.fileExists:
    packagedPath
  else:
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
  let
    stem = if name.endsWith(".spv"): name[0 ..< name.len - 4] else: name
    availableFormats = getGPUShaderFormats(device)
  var
    shaderName: string
    shaderFormat: GPUShaderFormat
  if (availableFormats and GPU_SHADERFORMAT_DXIL.GPUShaderFormat) != 0:
    shaderName = stem & ".dxil"
    shaderFormat = GPU_SHADERFORMAT_DXIL.GPUShaderFormat
  elif (availableFormats and GPU_SHADERFORMAT_SPIRV.GPUShaderFormat) != 0:
    shaderName = stem & ".spv"
    shaderFormat = GPU_SHADERFORMAT_SPIRV.GPUShaderFormat
  else:
    raiseGpuError(
      &"No packaged shader format supports GPU formats {availableFormats}"
    )

  let code = loadShaderCode(shaderName)
  var info = GPUShaderCreateInfo(
    code_size: code.len.csize_t,
    code: cast[ptr UncheckedArray[uint8]](unsafeAddr code[0]),
    entrypoint: cstring"main",
    format: shaderFormat,
    stage: stage,
    num_samplers: samplers,
    num_uniform_buffers: uniformBuffers,
  )
  result = createGPUShader(device, addr info)
  if result.isNil:
    raiseGpuError("Failed to create GPU shader " & shaderName)

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

proc init*(T: typedesc[UvRegion], origin = vec2(0'f32, 0'f32),
    size = vec2(1'f32, 1'f32)): T =
  ## Creates a normalized texture region. The default selects the full texture.
  T(origin: origin, size: size)

proc atlasRegion*(columns, rows, column, row: int,
    inset = vec2(0'f32, 0'f32)): UvRegion =
  ## Selects one cell from a uniform atlas. `inset` is normalized within a cell.
  if columns <= 0 or rows <= 0:
    raise newException(ValueError, "atlas dimensions must be positive")
  if column < 0 or column >= columns or row < 0 or row >= rows:
    raise newException(ValueError, "atlas cell is outside the atlas")
  let
    cellSize = vec2(1'f32 / columns.float32, 1'f32 / rows.float32)
    safeInset = vec2(
      clamp(inset.x, 0'f32, 0.499'f32),
      clamp(inset.y, 0'f32, 0.499'f32),
    )
  UvRegion(
    origin: vec2(column.float32, row.float32) * cellSize +
      safeInset * cellSize,
    size: cellSize * (vec2(1'f32, 1'f32) - safeInset * 2'f32),
  )

proc atlasRegionPixels*(textureSize, origin, size: Vec2,
    insetPixels = vec2(0'f32, 0'f32)): UvRegion =
  ## Selects a pixel rectangle and optionally pulls its edges inward to avoid
  ## sampling neighbouring atlas cells when texture filtering is enabled.
  if textureSize.x <= 0 or textureSize.y <= 0 or size.x <= 0 or size.y <= 0:
    raise newException(ValueError, "texture and region sizes must be positive")
  let inset = vec2(
    clamp(insetPixels.x, 0'f32, size.x * 0.499'f32),
    clamp(insetPixels.y, 0'f32, size.y * 0.499'f32),
  )
  UvRegion(
    origin: (origin + inset) / textureSize,
    size: (size - inset * 2'f32) / textureSize,
  )

func remap*(region: UvRegion, uv: Vec2): Vec2 =
  ## Maps mesh-local UV coordinates into a normalized atlas region.
  region.origin + uv * region.size

proc init*(T: typedesc[Material], id: string,
    texture: TextureResourceHandle = nil,
    baseColor = vec3(1'f32, 1'f32, 1'f32),
    useTexture = true, textureSampling = Single,
    atlasColumns = 1, atlasRows = 1,
    specularStrength = DefaultSpecularStrength): T =
  ## Creates a material with useful textured-model defaults.
  T(
    id: id,
    texture: texture,
    baseColor: baseColor,
    useTexture: useTexture and texture != nil,
    textureSampling: textureSampling,
    atlasColumns: max(atlasColumns, 1),
    atlasRows: max(atlasRows, 1),
    specularStrength: max(specularStrength, 0'f32),
  )

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
    skybox: TextureResourceHandle = nil,
    exposure = 1'f32,
    useSkybox = false,
): T =
  T(
    horizonColor: horizonColor,
    zenithColor: zenithColor,
    groundColor: groundColor,
    skybox: skybox,
    exposure: exposure,
    useSkybox: useSkybox and skybox != nil,
  )

proc init*(
    T: typedesc[SsaoOptions],
    enabled = true,
    radius = 3.2'f32,
    strength = 1.15'f32,
    bias = 0.012'f32,
): T =
  ## Tuned defaults for a subtle, stable contact-shadow pass.
  T(enabled: enabled, radius: max(radius, 0.1'f32),
    strength: clamp(strength, 0'f32, 3'f32), bias: max(bias, 0'f32))

proc init*(
    T: typedesc[RenderOptions],
    mode = SolidMesh,
    depthTest = true,
    depthWrite = true,
    baseColor = vec3(0.9'f32, 0.52'f32, 0.22'f32),
    materialID = "",
    uvRegion = UvRegion.init(),
    fog = FogRenderOptions.init(),
): T =
  T(
    effect: StandardEffect,
    mode: mode,
    depthTest: depthTest,
    depthWrite: depthWrite,
    baseColor: baseColor,
    materialID: materialID,
    uvRegion: uvRegion,
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
  let projection = forwardPerspective(
    artist.renderSettings.camera.fieldOfView,
    aspect,
    artist.renderSettings.camera.nearPlane,
    artist.renderSettings.camera.farPlane,
  )
  projection * artist.activeCamera.viewMatrix

proc skyViewportScale(artist: Artist3DState): Vec4 =
  let aspect =
    if artist.textureHeight == 0:
      1'f32
    else:
      artist.textureWidth.float32 / artist.textureHeight.float32
  let tanHalfFov = tan(artist.renderSettings.camera.fieldOfView *
    PI.float32 / 360'f32)
  vec4(tanHalfFov * aspect, tanHalfFov, 0, 0)

proc transformUniforms(artist: Artist3DState,
    modelTransform: Mat4): TransformUniforms =
  result.model = modelTransform
  result.modelViewProjection = artist.viewProjection * modelTransform

proc lightingUniforms(artist: Artist3DState, model: Model): LightingUniforms =
  let settings = artist.renderSettings
  result.cameraPosition = artist.activeCamera.position
  result.baseColor = model.renderOptions.baseColor
  var fog = model.renderOptions.fog
  if fog == FogRenderOptions.init():
    fog = FogRenderOptions.init(
      nearColor = settings.environment.fogNearColor,
      farColor = settings.environment.fogFarColor,
      density = settings.environment.fogDensity,
      falloff = settings.environment.fogFalloff,
      limit = settings.environment.fogLimit,
    )
  result.fogNearColor = fog.nearColor
  result.fogFarColor = fog.farColor
  result.fogDensity = max(fog.density, 0'f32)
  result.fogFalloff = max(fog.falloff, 0.001'f32)
  result.fogLimit = max(fog.limit, 0.001'f32)
  result.specularStrength = settings.lighting.defaultSpecularStrength
  result.lightDirection = settings.lighting.direction
  result.ambientStrength = settings.lighting.ambientStrength
  result.lightColor = settings.lighting.color
  result.diffuseStrength = settings.lighting.diffuseStrength
  result.specularColor = settings.lighting.specularColor
  result.shininess = settings.lighting.shininess
  var uvRegion = model.renderOptions.uvRegion
  if uvRegion.size.x <= 0 or uvRegion.size.y <= 0:
    uvRegion = UvRegion.init()
  result.uvRegion = vec4(
    uvRegion.origin.x, uvRegion.origin.y, uvRegion.size.x, uvRegion.size.y)
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
  result.cameraRotation = mat4(normalize(artist.activeCamera.orientation))
  result.viewportScale = artist.skyViewportScale()
  result.horizonExposure = vec4(
    sky.horizonColor.x, sky.horizonColor.y, sky.horizonColor.z,
    max(sky.exposure, 0'f32),
  )
  result.zenithUseSkybox = vec4(
    sky.zenithColor.x, sky.zenithColor.y, sky.zenithColor.z,
    if sky.useSkybox and sky.skybox != nil: 1'f32 else: 0'f32,
  )
  result.groundColor = vec4(sky.groundColor.x, sky.groundColor.y,
      sky.groundColor.z, 0)

proc releaseRenderTarget(artist: var Artist3DState) =
  if not artist.renderTexture.isNil:
    destroyTexture(artist.renderTexture)
    artist.renderTexture = nil
  if not artist.ssaoRenderTexture.isNil:
    destroyTexture(artist.ssaoRenderTexture)
    artist.ssaoRenderTexture = nil
  if not artist.compositeRenderTexture.isNil:
    destroyTexture(artist.compositeRenderTexture)
    artist.compositeRenderTexture = nil
  if not artist.depthPreviewRenderTexture.isNil:
    destroyTexture(artist.depthPreviewRenderTexture)
    artist.depthPreviewRenderTexture = nil
  if not artist.colorTexture.isNil:
    releaseGPUTexture(artist.device, artist.colorTexture)
    artist.colorTexture = nil
  if not artist.depthTexture.isNil:
    releaseGPUTexture(artist.device, artist.depthTexture)
    artist.depthTexture = nil
  if not artist.multisampleColorTexture.isNil:
    releaseGPUTexture(artist.device, artist.multisampleColorTexture)
    artist.multisampleColorTexture = nil
  if not artist.multisampleDepthTexture.isNil:
    releaseGPUTexture(artist.device, artist.multisampleDepthTexture)
    artist.multisampleDepthTexture = nil
  if not artist.depthDataTexture.isNil:
    releaseGPUTexture(artist.device, artist.depthDataTexture)
    artist.depthDataTexture = nil
  if not artist.ssaoTexture.isNil:
    releaseGPUTexture(artist.device, artist.ssaoTexture)
    artist.ssaoTexture = nil
  if not artist.compositeTexture.isNil:
    releaseGPUTexture(artist.device, artist.compositeTexture)
    artist.compositeTexture = nil
  if not artist.depthPreviewTexture.isNil:
    releaseGPUTexture(artist.device, artist.depthPreviewTexture)
    artist.depthPreviewTexture = nil
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
  if artist.whiteCubeTexture != nil:
    releaseGPUTexture(artist.device, artist.whiteCubeTexture)
    artist.whiteCubeTexture = nil
  if artist.skybox.texture != nil:
    releaseGPUTexture(artist.device, artist.skybox.texture)
    artist.skybox.texture = nil
  artist.skybox = GpuSkybox()
  if artist.samplerReady:
    releaseGpuSampler(artist.device, artist.sampler)
    artist.sampler = nil
    artist.samplerReady = false
  if artist.nearestSamplerReady:
    releaseGpuSampler(artist.device, artist.nearestSampler)
    artist.nearestSampler = nil
    artist.nearestSamplerReady = false
  if artist.linearSamplerReady:
    releaseGpuSampler(artist.device, artist.linearSampler)
    artist.linearSampler = nil
    artist.linearSamplerReady = false

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
  if not artist.depthPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.depthPipeline)
    artist.depthPipeline = nil
  if not artist.ssaoPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.ssaoPipeline)
    artist.ssaoPipeline = nil
  if not artist.compositePipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.compositePipeline)
    artist.compositePipeline = nil
  if not artist.depthPreviewPipeline.isNil:
    releaseGPUGraphicsPipeline(artist.device, artist.depthPreviewPipeline)
    artist.depthPreviewPipeline = nil

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

proc createSampledCubeTexture(
    artist: var Artist3DState, size: uint32, context: string
): GPUTexture =
  var textureInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_CUBE,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER.GPUTextureUsageFlags,
    width: size,
    height: size,
    layer_count_or_depth: 6,
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
    layer = 0'u32,
    cycle = true,
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
    layer: layer,
    x: 0,
    y: 0,
    z: 0,
    w: width,
    h: height,
    d: 1,
  )
  uploadToGpuTexture(copyPass, addr source, addr destination, cycle)
  endGPUCopyPass(copyPass)
  transferBuffer

proc uploadTexturePixels(
    artist: var Artist3DState,
    texture: GPUTexture,
    pixels: var seq[uint8],
    width, height: uint32,
    context: string,
    layer = 0'u32,
    cycle = true,
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
    layer,
    cycle,
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

proc ensureTextureSampler(artist: var Artist3DState, filter: TextureFilter) =
  if artist.device.isNil:
    return
  let ready = if filter == Nearest:
    artist.nearestSamplerReady else: artist.linearSamplerReady
  if ready:
    return
  let mode = if filter == Nearest: GPU_FILTER_NEAREST else: GPU_FILTER_LINEAR
  let mipmapMode = if filter == Nearest:
    GPU_SAMPLERMIPMAPMODE_NEAREST else: GPU_SAMPLERMIPMAPMODE_LINEAR
  var samplerInfo = GPUSamplerCreateInfo(
    min_filter: mode, mag_filter: mode, mipmap_mode: mipmapMode,
    address_mode_u: GPU_SAMPLERADDRESSMODE_REPEAT,
    address_mode_v: GPU_SAMPLERADDRESSMODE_REPEAT,
    address_mode_w: GPU_SAMPLERADDRESSMODE_REPEAT,
  )
  let sampler = createGpuSampler(artist.device, addr samplerInfo)
  if sampler.isNil:
    raiseGpuError("Failed to create texture sampler")
  if filter == Nearest:
    artist.nearestSampler = sampler
    artist.nearestSamplerReady = true
  else:
    artist.linearSampler = sampler
    artist.linearSamplerReady = true

proc textureSampler(artist: Artist3DState, filter: TextureFilter): pointer =
  if filter == Nearest: artist.nearestSampler else: artist.linearSampler

proc ensureWhiteTexture(artist: var Artist3DState) =
  if artist.device.isNil or artist.whiteTexture != nil:
    return
  artist.whiteTexture = artist.createSampledTexture(1, 1,
      "Failed to create default texture")
  var pixels = @[255'u8, 255, 255, 255]
  artist.uploadTexturePixels(artist.whiteTexture, pixels, 1, 1, "default texture")

proc ensureWhiteCubeTexture(artist: var Artist3DState) =
  if artist.device.isNil or artist.whiteCubeTexture != nil:
    return
  artist.whiteCubeTexture = artist.createSampledCubeTexture(1,
      "Failed to create default skybox texture")
  for layer in 0'u32 .. 5'u32:
    var pixels = @[255'u8, 255, 255, 255]
    artist.uploadTexturePixels(
      artist.whiteCubeTexture, pixels, 1, 1, "default skybox texture", layer,
      layer == 0'u32
    )

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

proc uploadSkyboxTexture(artist: var Artist3DState,
    source: TextureResourceHandle) =
  if artist.device.isNil:
    return
  if artist.skybox.source != source:
    if artist.skybox.texture != nil:
      releaseGPUTexture(artist.device, artist.skybox.texture)
    artist.skybox = GpuSkybox(source: source, textureDirty: true)
  if not artist.skybox.textureDirty:
    return
  if source == nil or source.pixels.len == 0 or source.width <= 0 or
      source.height <= 0:
    artist.skybox.textureDirty = false
    return

  let faceSize = min(source.width div 4, source.height div 3)
  if faceSize <= 0:
    artist.skybox.textureDirty = false
    return

  artist.skybox.texture = artist.createSampledCubeTexture(
    faceSize.uint32,
    "Failed to create skybox texture",
  )
  let cells = [
    (x: 2, y: 1), # +X
    (x: 0, y: 1), # -X
    (x: 1, y: 0), # +Y
    (x: 1, y: 2), # -Y
    (x: 1, y: 1), # +Z
    (x: 3, y: 1), # -Z
  ]
  for layer, cell in cells:
    var pixels = newSeq[uint8](faceSize * faceSize * 4)
    for y in 0 ..< faceSize:
      for x in 0 ..< faceSize:
        let
          sourceX = cell.x * faceSize + x
          sourceY = cell.y * faceSize + y
          sourceIndex = (sourceY * source.width + sourceX) * 4
          destinationIndex = (y * faceSize + x) * 4
        pixels[destinationIndex + 0] = source.pixels[sourceIndex + 0]
        pixels[destinationIndex + 1] = source.pixels[sourceIndex + 1]
        pixels[destinationIndex + 2] = source.pixels[sourceIndex + 2]
        pixels[destinationIndex + 3] = source.pixels[sourceIndex + 3]
    artist.uploadTexturePixels(
      artist.skybox.texture,
      pixels,
      faceSize.uint32,
      faceSize.uint32,
      "skybox texture",
      layer.uint32,
      layer == 0,
    )
  artist.skybox.textureWidth = faceSize.uint32
  artist.skybox.textureHeight = faceSize.uint32
  artist.skybox.textureDirty = false

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
    artist: var Artist3DState, mode: MeshRenderMode, depthTest, depthWrite: bool,
    fragmentShader: GPUShader = nil,
    sampleCount = GPU_SAMPLECOUNT_1,
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
    vertex_shader: artist.vertexShader,
    fragment_shader: if fragmentShader.isNil: artist.fragmentShader else: fragmentShader,
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
    multisample_state: GPUMultisampleState(sample_count: sampleCount),
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
    multisample_state: GPUMultisampleState(sample_count: artist.sampleCount),
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
    multisample_state: GPUMultisampleState(sample_count: artist.sampleCount),
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

proc createPostProcessPipeline(artist: var Artist3DState,
    fragmentShader: GPUShader): GPUGraphicsPipeline =
  var colorTarget = GPUColorTargetDescription(
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    blend_state: GPUColorTargetBlendState(
      color_write_mask: (GPU_COLORCOMPONENT_R or GPU_COLORCOMPONENT_G or
        GPU_COLORCOMPONENT_B or GPU_COLORCOMPONENT_A).GPUColorComponentFlags,
      enable_color_write_mask: true,
    ),
  )
  var targetInfo = GPUGraphicsPipelineTargetInfo(
    color_target_descriptions: cast[ptr UncheckedArray[
        GPUColorTargetDescription]](
      addr colorTarget),
    num_color_targets: 1,
  )
  var pipelineInfo = GpuGraphicsPipelineCreateInfo(
    vertex_shader: artist.fullscreenVertexShader,
    fragment_shader: fragmentShader,
    primitive_type: GPU_PRIMITIVETYPE_TRIANGLELIST,
    rasterizer_state: GPURasterizerState(
      fill_mode: GPU_FILLMODE_FILL, cull_mode: GPU_CULLMODE_NONE,
      front_face: GPU_FRONTFACE_CLOCKWISE,
    ),
    multisample_state: GPUMultisampleState(sample_count: GPU_SAMPLECOUNT_1),
    target_info: targetInfo,
  )
  result = createGpuGraphicsPipeline(artist.device, addr pipelineInfo)
  if result.isNil:
    raiseGpuError("Failed to create GPU post-process pipeline")

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
    createShader(artist.device, "water.frag.spv", GPU_SHADERSTAGE_FRAGMENT, 2,
      samplers = 1)
  artist.skyVertexShader =
    createShader(artist.device, "sky.vert.spv", GPU_SHADERSTAGE_VERTEX)
  artist.skyFragmentShader =
    createShader(artist.device, "sky.frag.spv", GPU_SHADERSTAGE_FRAGMENT,
        samplers = 1)
  artist.fullscreenVertexShader = createShader(artist.device,
      "fullscreen.vert.spv", GPU_SHADERSTAGE_VERTEX, uniformBuffers = 0)
  artist.ssaoFragmentShader = createShader(artist.device, "ssao.frag.spv",
      GPU_SHADERSTAGE_FRAGMENT, samplers = 1)
  artist.compositeFragmentShader = createShader(artist.device,
      "composite.frag.spv", GPU_SHADERSTAGE_FRAGMENT, uniformBuffers = 0,
      samplers = 2)
  artist.depthPreviewFragmentShader = createShader(artist.device,
      "depthPreview.frag.spv", GPU_SHADERSTAGE_FRAGMENT, samplers = 1)
  artist.depthFragmentShader = createShader(artist.device, "depth.frag.spv",
      GPU_SHADERSTAGE_FRAGMENT)
  artist.solidPipeline = artist.createTrianglePipeline(
    SolidMesh, true, true, sampleCount = artist.sampleCount)
  artist.overlayPipeline = artist.createTrianglePipeline(
    SolidMesh, false, false, sampleCount = artist.sampleCount)
  artist.wireframePipeline = artist.createTrianglePipeline(
    WireframeMesh, true, false, sampleCount = artist.sampleCount)
  artist.overlayWireframePipeline = artist.createTrianglePipeline(
    WireframeMesh, false, false, sampleCount = artist.sampleCount
  )
  artist.waterPipeline = artist.createWaterPipeline()
  artist.skyPipeline = artist.createSkyPipeline()
  artist.depthPipeline = artist.createTrianglePipeline(SolidMesh, true, true,
    artist.depthFragmentShader)
  artist.ssaoPipeline = artist.createPostProcessPipeline(
      artist.ssaoFragmentShader)
  artist.compositePipeline = artist.createPostProcessPipeline(
    artist.compositeFragmentShader)
  artist.depthPreviewPipeline = artist.createPostProcessPipeline(
    artist.depthPreviewFragmentShader)

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
  artist.ensureTextureSampler(Nearest)
  artist.ensureTextureSampler(Linear)
  artist.ensureWhiteTexture()
  artist.ensureWhiteCubeTexture()
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
  result.state.renderSettings = RenderSettings.init()
  result.state.sampleCount = GPU_SAMPLECOUNT_1
  result.state.ssao = SsaoOptions.init(
    enabled = result.state.renderSettings.ssao.enabled,
    radius = result.state.renderSettings.ssao.radius,
    strength = result.state.renderSettings.ssao.strength,
    bias = result.state.renderSettings.ssao.bias,
  )
  result.state.textureFiltering = result.state.renderSettings.textureFiltering
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

proc setMesh*(artist: Artist3D, meshID: MeshID, mesh: MeshData) =
  ## Uploads a self-contained mesh description under a reusable identifier.
  artist.setMesh(meshID, mesh.vertices, mesh.indices)

proc setMesh*(artist: Artist3D, mesh: MeshData) =
  artist.setMesh(DefaultMeshID, mesh)

proc createModel*(artist: Artist3D, meshID: MeshID, mesh: MeshData,
    materialID = "", transform = identityMat4(),
    uvRegion = UvRegion.init()): Model =
  ## Registers geometry and returns a render-ready model in one operation.
  artist.setMesh(meshID, mesh)
  Model.init(meshID, transform, RenderOptions.init(
    materialID = materialID, uvRegion = uvRegion))

proc model*(artist: Artist3D, meshID: MeshID, materialID = "",
    transform = identityMat4(), uvRegion = UvRegion.init()): Model =
  ## Creates another instance of geometry already registered with the artist.
  discard artist
  Model.init(meshID, transform, RenderOptions.init(
    materialID = materialID, uvRegion = uvRegion))

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

proc withUvRegion*(model: Model, region: UvRegion): Model =
  ## Returns a copy of a model sampling the requested atlas region.
  result = model
  result.renderOptions.uvRegion = region

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

proc renderSettings*(artist: Artist3D): RenderSettings =
  if artist.state.isNil:
    return RenderSettings.init()
  artist.state.renderSettings

proc `renderSettings=`*(artist: Artist3D, settings: RenderSettings) =
  if artist.state.isNil:
    return
  let requestedSampleCount = case settings.antialiasing
    of AntialiasingMode.Disabled: GPU_SAMPLECOUNT_1
    of AntialiasingMode.Msaa2x: GPU_SAMPLECOUNT_2
    of AntialiasingMode.Msaa4x: GPU_SAMPLECOUNT_4
    of AntialiasingMode.Msaa8x: GPU_SAMPLECOUNT_8
  var sampleCount = requestedSampleCount
  if not artist.state.device.isNil:
    while sampleCount > GPU_SAMPLECOUNT_1 and
        (not gPUTextureSupportsSampleCount(artist.state.device,
          GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sampleCount) or
         not gPUTextureSupportsSampleCount(artist.state.device,
          GPU_TEXTUREFORMAT_D16_UNORM, sampleCount)):
      sampleCount = GPUSampleCount(sampleCount.ord - 1)
  let antialiasingChanged = sampleCount != artist.state.sampleCount
  artist.state.renderSettings = settings
  artist.state.ssao = SsaoOptions.init(
    enabled = settings.ssao.enabled,
    radius = settings.ssao.radius,
    strength = settings.ssao.strength,
    bias = settings.ssao.bias,
  )
  artist.textureFiltering = settings.textureFiltering
  if antialiasingChanged:
    artist.state.sampleCount = sampleCount
    artist.state[].releaseRenderTarget()
    if not artist.state.device.isNil:
      artist.state[].createTrianglePipelines()

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
    usage: (GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET or
      GPU_TEXTUREUSAGE_SAMPLER).GPUTextureUsageFlags,
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

  if artist.sampleCount != GPU_SAMPLECOUNT_1:
    var multisampleColorInfo = textureInfo
    multisampleColorInfo.usage = GPU_TEXTUREUSAGE_COLOR_TARGET.GPUTextureUsageFlags
    multisampleColorInfo.sample_count = artist.sampleCount
    artist.multisampleColorTexture = createGPUTexture(
      artist.device, addr multisampleColorInfo)
    var multisampleDepthInfo = depthTextureInfo
    multisampleDepthInfo.usage =
      GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET.GPUTextureUsageFlags
    multisampleDepthInfo.sample_count = artist.sampleCount
    artist.multisampleDepthTexture = createGPUTexture(
      artist.device, addr multisampleDepthInfo)
    if artist.multisampleColorTexture.isNil or
        artist.multisampleDepthTexture.isNil:
      artist.releaseRenderTarget()
      raiseGpuError("Failed to create multisample GPU targets")

  artist.ssaoTexture = createGPUTexture(artist.device, addr textureInfo)
  artist.compositeTexture = createGPUTexture(artist.device, addr textureInfo)
  artist.depthPreviewTexture = createGPUTexture(artist.device, addr textureInfo)
  artist.depthDataTexture = createGPUTexture(artist.device, addr textureInfo)
  if artist.ssaoTexture.isNil or artist.compositeTexture.isNil or
      artist.depthDataTexture.isNil or
      artist.depthPreviewTexture.isNil:
    artist.releaseRenderTarget()
    raiseGpuError("Failed to create GPU post-process target")

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
  discard setPointerProperty(props, PropTextureCreateGpuTexture, cast[pointer](
      artist.colorTexture))
  artist.renderTexture = createTextureWithProperties(artist.renderer, props)
  discard setPointerProperty(props, PropTextureCreateGpuTexture, cast[pointer](
      artist.ssaoTexture))
  artist.ssaoRenderTexture = createTextureWithProperties(artist.renderer, props)
  discard setPointerProperty(props, PropTextureCreateGpuTexture, cast[pointer](
      artist.compositeTexture))
  artist.compositeRenderTexture = createTextureWithProperties(artist.renderer, props)
  discard setPointerProperty(props, PropTextureCreateGpuTexture, cast[pointer](
      artist.depthPreviewTexture))
  artist.depthPreviewRenderTexture = createTextureWithProperties(
      artist.renderer, props)
  if artist.renderTexture.isNil or artist.ssaoRenderTexture.isNil or
      artist.compositeRenderTexture.isNil or
          artist.depthPreviewRenderTexture.isNil:
    artist.releaseRenderTarget()
    raiseGpuError("Failed to wrap GPU target as SDL texture")

  artist.textureWidth = width
  artist.textureHeight = height

proc ensureReady(artist: var Artist3DState, width, height: uint32) =
  if artist.device.isNil:
    if defaultRenderer.isNil:
      return
    artist.initWithRenderer(defaultRenderer)
  if artist.colorTexture.isNil or artist.depthTexture.isNil or
      (artist.sampleCount != GPU_SAMPLECOUNT_1 and
       (artist.multisampleColorTexture.isNil or
        artist.multisampleDepthTexture.isNil)) or
      artist.ssaoTexture.isNil or artist.compositeTexture.isNil or
      artist.depthDataTexture.isNil or
      artist.depthPreviewTexture.isNil or
      artist.textureWidth != width or artist.textureHeight != height:
    artist.createRenderTarget(width, height)

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
  var sampler = state.sampler
  if model.renderOptions.materialID.len > 0 and
      state.materials.hasKey(model.renderOptions.materialID):
    let source = state.materials[model.renderOptions.materialID].material.texture
    if source != nil:
      sampler = state.textureSampler(source.filterMode)
  var samplerBinding = GpuTextureSamplerBinding(
    texture: texture,
    sampler: sampler,
  )
  if model.renderOptions.effect == StandardEffect and
      (texture.isNil or sampler.isNil):
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
  if model.renderOptions.effect in {StandardEffect, WaterEffect} and
      sampler != nil and texture != nil:
    bindGpuFragmentSamplers(pass, 0, addr samplerBinding, 1)
  bindGpuVertexBuffers(pass, 0, addr binding, 1)
  bindGpuIndexBuffer(pass, addr indexBinding, GPU_INDEXELEMENTSIZE_32BIT)
  drawGPUIndexedPrimitives(pass, mesh.indices.len.uint32, 1, 0, 0, 0)

proc drawDepthModel(state: var Artist3DState, pass: GPURenderPass,
    commandBuffer: GPUCommandBuffer, model: Model, extraTransform: Mat4) =
  ## The hardware D16 attachment remains the visibility buffer. This pass
  ## writes its linearized result to an RGBA target, which is reliable to
  ## sample and inspect on every supported SDL GPU backend.
  if model.renderOptions.effect != StandardEffect or not model.renderOptions.depthTest or
      not state.meshes.hasKey(model.meshID) or state.depthPipeline.isNil:
    return
  let mesh = state.meshes[model.meshID]
  if mesh.vertexBuffer.isNil or mesh.indexBuffer.isNil or mesh.indices.len == 0:
    return
  var binding = GpuBufferBinding(buffer: mesh.vertexBuffer, offset: 0)
  var indexBinding = GpuBufferBinding(buffer: mesh.indexBuffer, offset: 0)
  var uniforms = state.transformUniforms(extraTransform * model.transform)
  let lighting = state.lightingUniforms(model)
  var depthFog = DepthFogUniforms(
    cameraPosition: lighting.cameraPosition,
    fogLimit: lighting.fogLimit,
  )
  pushGPUVertexUniformData(commandBuffer, CameraUniformSlot, addr uniforms,
    sizeof(TransformUniforms).uint32)
  pushGPUFragmentUniformData(commandBuffer, 0, addr depthFog,
    sizeof(DepthFogUniforms).uint32)
  bindGPUGraphicsPipeline(pass, state.depthPipeline)
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
  let texture =
    if sky.useSkybox and state.skybox.texture != nil:
      state.skybox.texture
    else:
      state.whiteCubeTexture
  var samplerBinding = GpuTextureSamplerBinding(
    texture: texture,
    sampler: state.sampler,
  )
  pushGPUVertexUniformData(
    commandBuffer, 0, addr uniforms, sizeof(SkyUniforms).uint32
  )
  pushGPUFragmentUniformData(
    commandBuffer, 0, addr uniforms, sizeof(SkyUniforms).uint32
  )
  bindGPUGraphicsPipeline(pass, state.skyPipeline)
  if state.samplerReady and texture != nil:
    bindGpuFragmentSamplers(pass, 0, addr samplerBinding, 1)
  drawGPUPrimitives(pass, 3, 1, 0, 0)

proc drawPostProcess(state: var Artist3DState, pass: GPURenderPass,
    commandBuffer: GPUCommandBuffer, pipeline: GPUGraphicsPipeline,
    textures: openArray[GPUTexture], uniforms: pointer = nil,
    uniformSize = 0'u32) =
  if pipeline.isNil or textures.len == 0 or state.sampler.isNil:
    return
  var bindings: array[2, GpuTextureSamplerBinding]
  for i, texture in textures:
    bindings[i] = GpuTextureSamplerBinding(texture: texture,
        sampler: state.sampler)
  if uniforms != nil and uniformSize > 0:
    pushGPUFragmentUniformData(commandBuffer, 0, uniforms, uniformSize)
  bindGPUGraphicsPipeline(pass, pipeline)
  bindGpuFragmentSamplers(pass, 0, addr bindings[0], textures.len.uint32)
  drawGPUPrimitives(pass, 3, 1, 0, 0)

proc runPostProcessPass(state: var Artist3DState,
    commandBuffer: GPUCommandBuffer, output: GPUTexture, pipeline: GPUGraphicsPipeline,
        inputs: openArray[GPUTexture],
    uniforms: pointer = nil, uniformSize = 0'u32) =
  var target = GpuColorTargetInfo(texture: output,
    load_op: GPU_LOADOP_DONT_CARE, store_op: GPU_STOREOP_STORE)
  let pass = beginGpuRenderPass(commandBuffer, addr target, 1, nil)
  if pass.isNil:
    raiseGpuError("Failed to begin GPU post-process pass")
  state.drawPostProcess(pass, commandBuffer, pipeline, inputs, uniforms, uniformSize)
  endGPURenderPass(pass)

proc render*(artist: Artist3D, models: openArray[Model],
    transform = identityMat4(), sky = SkyRenderOptions.init(),
    canvas: ptr Canvas = nil) =
  if artist.state.isNil:
    return
  let state = artist.state
  var activeSky = sky
  if sky == SkyRenderOptions.init():
    activeSky = SkyRenderOptions.init(
      horizonColor = state.renderSettings.environment.skyHorizonColor,
      zenithColor = state.renderSettings.environment.skyZenithColor,
      groundColor = state.renderSettings.environment.skyGroundColor,
      exposure = state.renderSettings.environment.skyExposure,
    )
  var destinationWidth, destinationHeight: int
  if canvas != nil:
    canvas[].syncSize()
    destinationWidth = canvas[].width
    destinationHeight = canvas[].height
    state[].ensureReady(canvas[].renderWidth.uint32, canvas[].renderHeight.uint32)
  else:
    var width, height: cint
    if not getRenderOutputSize(state.renderer, width, height) or width <= 0 or
        height <= 0:
      return
    destinationWidth = width.int
    destinationHeight = height.int
    state[].ensureReady(width.uint32, height.uint32)
  for model in models:
    state[].uploadMesh(model.meshID)
    if model.renderOptions.materialID.len > 0:
      state[].uploadMaterialTexture(model.renderOptions.materialID)
      if state[].materials.hasKey(model.renderOptions.materialID):
        let source = state[].materials[model.renderOptions.materialID].material.texture
        if source != nil:
          state[].ensureTextureSampler(source.filterMode)
  if activeSky.useSkybox and activeSky.skybox != nil:
    state[].uploadSkyboxTexture(activeSky.skybox)
  if state.device.isNil or state.solidPipeline.isNil or
      state.overlayPipeline.isNil or state.wireframePipeline.isNil or
      state.overlayWireframePipeline.isNil or state.waterPipeline.isNil or
      state.skyPipeline.isNil or state.depthPipeline.isNil or state.ssaoPipeline.isNil or
      state.compositePipeline.isNil or state.depthPreviewPipeline.isNil or
      state.colorTexture.isNil:
    return

  discard flushRenderer(state.renderer)
  let commandBuffer = acquireGPUCommandBuffer(state.device)
  if commandBuffer.isNil:
    raiseGpuError("Failed to acquire GPU command buffer")

  let multisampling = state.sampleCount != GPU_SAMPLECOUNT_1
  var colorTargetInfo = GpuColorTargetInfo(
    texture: if multisampling: state.multisampleColorTexture else: state.colorTexture,
    clear_color: FColor(
      r: state.renderSettings.clearColor.x,
      g: state.renderSettings.clearColor.y,
      b: state.renderSettings.clearColor.z,
      a: 1.0,
    ),
    load_op: GPU_LOADOP_CLEAR,
    store_op: if multisampling: GPU_STOREOP_RESOLVE else: GPU_STOREOP_STORE,
    resolve_texture: if multisampling: state.colorTexture else: nil,
  )
  var depthTargetInfo = GpuDepthStencilTargetInfo(
    texture: if multisampling: state.multisampleDepthTexture else: state.depthTexture,
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

  state[].drawSky(pass, commandBuffer, activeSky)
  for model in models:
    if model.renderOptions.depthTest:
      state[].drawModel(pass, commandBuffer, model, transform)
  for model in models:
    if not model.renderOptions.depthTest:
      state[].drawModel(pass, commandBuffer, model, transform)
  endGPURenderPass(pass)

  var ssaoUniforms = SsaoUniforms(
    resolutionRadius: vec4(state.textureWidth.float32,
      state.textureHeight.float32,
      state.ssao.radius, 0),
    projection: vec4(state.renderSettings.camera.nearPlane,
      state.renderSettings.camera.farPlane, 0, 0),
    strengthBias: vec4(state.ssao.strength, state.ssao.bias, 0, 0),
  )
  var depthColorTarget = GpuColorTargetInfo(texture: state.depthDataTexture,
    # Packed representation of a depth value just below 1.0 (far plane).
    clear_color: FColor(r: 0.75, g: 0.996, b: 0.996, a: 0.996), load_op: GPU_LOADOP_CLEAR,
    store_op: GPU_STOREOP_STORE)
  var depthOnlyTarget = GpuDepthStencilTargetInfo(texture: state.depthTexture,
    clear_depth: 1.0, load_op: GPU_LOADOP_CLEAR, store_op: GPU_STOREOP_DONT_CARE,
    stencil_load_op: GPU_LOADOP_DONT_CARE, stencil_store_op: GPU_STOREOP_DONT_CARE)
  let depthPass = beginGpuRenderPass(commandBuffer, addr depthColorTarget, 1,
    addr depthOnlyTarget)
  if depthPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raiseGpuError("Failed to begin GPU depth-color pass")
  for model in models:
    state[].drawDepthModel(depthPass, commandBuffer, model, transform)
  endGPURenderPass(depthPass)
  state[].runPostProcessPass(commandBuffer, state.depthPreviewTexture,
    state.depthPreviewPipeline, [state.depthDataTexture])
  if state.ssao.enabled:
    state[].runPostProcessPass(commandBuffer, state.ssaoTexture,
      state.ssaoPipeline,
      [state.depthDataTexture], addr ssaoUniforms, sizeof(SsaoUniforms).uint32)
  else:
    # The composite pass accepts white as an occlusion texture; this keeps the
    # target graph stable while SSAO is switched off.
    state[].runPostProcessPass(commandBuffer, state.ssaoTexture,
      state.compositePipeline, [state.whiteTexture, state.whiteTexture])
  state[].runPostProcessPass(commandBuffer, state.compositeTexture,
    state.compositePipeline, [state.colorTexture, state.ssaoTexture])

  if not submitGPUCommandBuffer(commandBuffer):
    raiseGpuError("Failed to submit GPU command buffer")

  var dst =
    FRect(x: 0, y: 0, w: destinationWidth.cfloat,
        h: destinationHeight.cfloat)
  discard renderTexture(state.renderer, state.compositeRenderTexture, nil, addr dst)

proc ssaoOptions*(artist: Artist3D): SsaoOptions =
  if artist.state.isNil: return SsaoOptions.init(enabled = false)
  artist.state.ssao

proc `ssaoOptions=`*(artist: Artist3D, options: SsaoOptions) =
  if artist.state.isNil: return
  artist.state.ssao = SsaoOptions.init(options.enabled, options.radius,
    options.strength, options.bias)

proc renderTarget*(artist: Artist3D, target: RenderTarget): Texture =
  ## SDL texture for a live render target; nil until the first render.
  if artist.state.isNil: return nil
  case target
  of SceneColorTarget: artist.state.renderTexture
  of DepthTarget: artist.state.depthPreviewRenderTexture
  of AmbientOcclusionTarget: artist.state.ssaoRenderTexture
  of CompositeTarget: artist.state.compositeRenderTexture

proc renderTargetSize*(artist: Artist3D): tuple[width, height: int] =
  if artist.state.isNil: return (0, 0)
  (artist.state.textureWidth.int, artist.state.textureHeight.int)

proc render*(artist: Artist3D, model: Model, transform = identityMat4()) =
  artist.render([model], transform)

proc render*(artist: Artist3D) =
  if artist.state.isNil:
    return
  artist.render(artist.state.defaultModel, identityMat4())
