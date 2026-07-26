import std/[os, strformat, tables]

import sdl3, vmath

import cameras
import ../errors

const
  DefaultCameraID* = "default"
  DefaultMeshID* = "default"
const
  CameraUniformSlot = 0'u32
  DefaultFovY = 70'f32
  DefaultNearPlane = 0.1'f32
  DefaultFarPlane = 100'f32

type Vertex* = object
  uv*: IVec2
  position*, normal*: Vec3

type
  MeshID* = string

  Model* = object
    meshID*: MeshID
    transform*: Mat4

  Mesh = object
    vertexBuffer, indexBuffer: GPUBuffer
    vertexBufferSize, indexBufferSize: uint32
    vertices: seq[Vertex]
    indices: seq[uint32]
    verticesDirty, indicesDirty: bool

  TransformUniforms = object
    modelViewProjection: Mat4

type
  Artist3DState = object
    renderer: Renderer
    device: GPUDevice
    pipeline: GPUGraphicsPipeline
    vertexShader: GPUShader
    fragmentShader: GPUShader
    meshes: Table[MeshID, Mesh]
    defaultModel: Model
    colorTexture: GPUTexture
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

  GpuBufferBinding {.bycopy.} = object
    buffer: GPUBuffer
    offset: uint32

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

proc beginGpuRenderPass(
  commandBuffer: GPUCommandBuffer,
  colorTargetInfos: ptr GpuColorTargetInfo,
  numColorTargets: uint32,
  depthStencilTargetInfo: ptr GPUDepthStencilTargetInfo,
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

proc `=copy`*(artist: var Artist3D, source: Artist3D) {.error.}

proc activeCamera*(artist: Artist3DState): cameras.Camera
proc uploadMesh(artist: var Artist3DState, meshID: MeshID)

proc raiseGpuError(context: string) {.noreturn.} =
  raise SDLException.newException(context & ": " & $sdl3.getError())

proc shaderPath(name: string): string =
  currentSourcePath().parentDir.parentDir.parentDir.parentDir / "build" / "shaders" /
    name

proc loadShaderCode(name: string): string =
  let path = shaderPath(name)
  if not fileExists(path):
    raiseGpuError(&"Missing shader {path}; run `nimble shaders`")
  result = readFile(path)
  if result.len == 0:
    raiseGpuError(&"Shader {path} is empty")

proc createShader(device: GPUDevice, name: string, stage: GPUShaderStage): GPUShader =
  let code = loadShaderCode(name)
  var info = GPUShaderCreateInfo(
    code_size: code.len.csize_t,
    code: cast[ptr UncheckedArray[uint8]](unsafeAddr code[0]),
    entrypoint: cstring"main",
    format: GPU_SHADERFORMAT_SPIRV.GPUShaderFormat,
    stage: stage,
    num_uniform_buffers: (if stage == GPU_SHADERSTAGE_VERTEX: 1'u32 else: 0'u32),
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

proc init*(T: typedesc[Model], meshID: MeshID, transform = identityMat4()): T =
  T(meshID: meshID, transform: transform)

proc viewProjection(artist: Artist3DState): Mat4 =
  let aspect =
    if artist.textureHeight == 0:
      1'f32
    else:
      artist.textureWidth.float32 / artist.textureHeight.float32
  let projection =
    forwardPerspective(DefaultFovY, aspect, DefaultNearPlane, DefaultFarPlane)
  projection * artist.activeCamera.viewMatrix

proc transformUniforms(artist: Artist3DState, modelTransform: Mat4): TransformUniforms =
  result.modelViewProjection = artist.viewProjection * modelTransform

proc releaseRenderTarget(artist: var Artist3DState) =
  if not artist.renderTexture.isNil:
    destroyTexture(artist.renderTexture)
    artist.renderTexture = nil
  if not artist.colorTexture.isNil:
    releaseGPUTexture(artist.device, artist.colorTexture)
    artist.colorTexture = nil
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

proc createMeshBuffer(
    artist: var Artist3DState, usage: GPUBufferUsageFlags, size: uint32, context: string
): GPUBuffer =
  var info = GPUBufferCreateInfo(usage: usage, size: size)
  result = createGPUBuffer(artist.device, addr info)
  if result.isNil:
    raiseGpuError(context)

proc ensureVertexBuffer(artist: var Artist3DState, mesh: var Mesh, bufferSize: uint32) =
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

proc ensureIndexBuffer(artist: var Artist3DState, mesh: var Mesh, bufferSize: uint32) =
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
    GPUTransferBufferCreateInfo(usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD, size: bufferSize)
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

proc createTrianglePipeline(artist: var Artist3DState) =
  artist.vertexShader =
    createShader(artist.device, "triangle.vert.spv", GPU_SHADERSTAGE_VERTEX)
  artist.fragmentShader =
    createShader(artist.device, "triangle.frag.spv", GPU_SHADERSTAGE_FRAGMENT)

  var vertexBuffers = [
    GPUVertexBufferDescription(
      slot: 0, pitch: sizeof(Vertex).uint32, input_rate: GPU_VERTEXINPUTRATE_VERTEX
    )
  ]
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: GPU_VERTEXELEMENTFORMAT_FLOAT3,
      offset: offsetof(Vertex, position).uint32,
    )
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
      fill_mode: GPU_FILLMODE_FILL,
      cull_mode: GPU_CULLMODE_NONE,
      front_face: GPU_FRONTFACE_COUNTER_CLOCKWISE,
    ),
    multisample_state: GPUMultisampleState(sample_count: GPU_SAMPLECOUNT_1),
    target_info: targetInfo,
  )
  artist.pipeline = createGpuGraphicsPipeline(artist.device, addr pipelineInfo)
  if artist.pipeline.isNil:
    raiseGpuError("Failed to create GPU graphics pipeline")

proc installArtist3DRenderer*(renderer: Renderer) =
  defaultRenderer = renderer

proc initWithRenderer(artist: var Artist3DState, renderer: Renderer) =
  artist.renderer = renderer
  artist.device = cast[GPUDevice](getPointerProperty(
    getRendererProperties(renderer), PROP_RENDERER_GPU_DEVICE_POINTER, nil
  ))
  if artist.device.isNil:
    raiseGpuError("SDL renderer is not the GPU renderer")
  artist.createTrianglePipeline()
  for meshID in artist.meshes.keys:
    artist.uploadMesh(meshID)

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
  if artist.colorTexture.isNil or artist.textureWidth != width.uint32 or
      artist.textureHeight != height.uint32:
    artist.createRenderTarget(width.uint32, height.uint32)

proc `=destroy`*(artist: var Artist3D) =
  if not artist.state.isNil and not artist.state.device.isNil:
    artist.state[].releaseRenderTarget()
    artist.state[].releaseMeshBuffers()

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

  var binding = GpuBufferBinding(buffer: mesh.vertexBuffer, offset: 0)
  var indexBinding = GpuBufferBinding(buffer: mesh.indexBuffer, offset: 0)
  var uniforms = state.transformUniforms(extraTransform * model.transform)
  pushGPUVertexUniformData(
    commandBuffer, CameraUniformSlot, addr uniforms, sizeof(TransformUniforms).uint32
  )
  bindGpuVertexBuffers(pass, 0, addr binding, 1)
  bindGpuIndexBuffer(pass, addr indexBinding, GPU_INDEXELEMENTSIZE_32BIT)
  drawGPUIndexedPrimitives(pass, mesh.indices.len.uint32, 1, 0, 0, 0)

proc render*(artist: Artist3D, models: openArray[Model], transform = identityMat4()) =
  if artist.state.isNil:
    return
  let state = artist.state
  state[].ensureReady()
  for model in models:
    state[].uploadMesh(model.meshID)
  if state.device.isNil or state.pipeline.isNil or state.colorTexture.isNil:
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
  let pass = beginGpuRenderPass(commandBuffer, addr colorTargetInfo, 1, nil)
  if pass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raiseGpuError("Failed to begin GPU render pass")

  bindGPUGraphicsPipeline(pass, state.pipeline)
  for model in models:
    state[].drawModel(pass, commandBuffer, model, transform)
  endGPURenderPass(pass)

  if not submitGPUCommandBuffer(commandBuffer):
    raiseGpuError("Failed to submit GPU command buffer")

  var dst =
    FRect(x: 0, y: 0, w: state.textureWidth.cfloat, h: state.textureHeight.cfloat)
  discard renderTexture(state.renderer, state.renderTexture, nil, addr dst)

proc render*(artist: Artist3D, model: Model, transform = identityMat4()) =
  artist.render([model], transform)

proc render*(artist: Artist3D) =
  if artist.state.isNil:
    return
  artist.render(artist.state.defaultModel, identityMat4())
