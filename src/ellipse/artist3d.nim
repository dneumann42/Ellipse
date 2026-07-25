import std/[os, strformat]

import sdl3
import vmath

import errors

type Vertex* = object
  uv*: IVec2
  position*, normal*: Vec3

const TriangleVertices = [
  Vertex(position: vec3(-1, 1, 0)),
  Vertex(position: vec3(1, 1, 0)),
  Vertex(position: vec3(0, -1, 0)),
]

const TriangleIndices = [0, 1, 2]

type
  Artist3DState = object
    renderer: Renderer
    device: GPUDevice
    pipeline: GPUGraphicsPipeline
    vertexShader: GPUShader
    fragmentShader: GPUShader
    vertexBuffer: GPUBuffer
    colorTexture: GPUTexture
    renderTexture: Texture
    textureWidth, textureHeight: uint32

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

proc init*(T: typedesc[Artist3D]): T =
  new result.state

proc `=copy`*(artist: var Artist3D, source: Artist3D) {.error.}

proc raiseGpuError(context: string) {.noreturn.} =
  raise SDLException.newException(context & ": " & $sdl3.getError())

proc shaderPath(name: string): string =
  currentSourcePath().parentDir.parentDir.parentDir / "build" / "shaders" / name

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
  )
  result = createGPUShader(device, addr info)
  if result.isNil:
    raiseGpuError("Failed to create GPU shader")

proc releaseRenderTarget(artist: var Artist3DState) =
  if not artist.renderTexture.isNil:
    destroyTexture(artist.renderTexture)
    artist.renderTexture = nil
  if not artist.colorTexture.isNil:
    releaseGPUTexture(artist.device, artist.colorTexture)
    artist.colorTexture = nil
  artist.textureWidth = 0
  artist.textureHeight = 0

proc uploadTriangleVertices(artist: var Artist3DState) =
  let bufferSize = uint32(sizeof(TriangleVertices))
  var vertexInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX.GPUBufferUsageFlags, size: bufferSize
  )
  artist.vertexBuffer = createGPUBuffer(artist.device, addr vertexInfo)
  if artist.vertexBuffer.isNil:
    raiseGpuError("Failed to create GPU vertex buffer")

  var transferInfo =
    GPUTransferBufferCreateInfo(usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD, size: bufferSize)
  let transferBuffer = createGPUTransferBuffer(artist.device, addr transferInfo)
  if transferBuffer.isNil:
    raiseGpuError("Failed to create GPU transfer buffer")

  let mapped = mapGPUTransferBuffer(artist.device, transferBuffer, false)
  if mapped.isNil:
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to map GPU transfer buffer")
  copyMem(mapped, unsafeAddr TriangleVertices[0], bufferSize)
  unmapGPUTransferBuffer(artist.device, transferBuffer)

  let commandBuffer = acquireGPUCommandBuffer(artist.device)
  if commandBuffer.isNil:
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to acquire GPU command buffer")

  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to begin GPU copy pass")

  var source = GpuTransferBufferLocation(transfer_buffer: transferBuffer, offset: 0)
  var destination =
    GpuBufferRegion(buffer: artist.vertexBuffer, offset: 0, size: bufferSize)
  uploadToGpuBuffer(copyPass, addr source, addr destination, false)
  endGPUCopyPass(copyPass)

  if not submitGPUCommandBuffer(commandBuffer):
    releaseGPUTransferBuffer(artist.device, transferBuffer)
    raiseGpuError("Failed to submit GPU vertex upload")
  discard waitForGPUIdle(artist.device)
  releaseGPUTransferBuffer(artist.device, transferBuffer)

proc createTrianglePipeline(artist: var Artist3DState) =
  artist.vertexShader =
    createShader(artist.device, "triangle.vert.spv", GPU_SHADERSTAGE_VERTEX)
  artist.fragmentShader =
    createShader(artist.device, "triangle.frag.spv", GPU_SHADERSTAGE_FRAGMENT)
  artist.uploadTriangleVertices()

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

proc init*(T: typedesc[Artist3D], renderer: Renderer): T =
  new result.state
  result.state[].initWithRenderer(renderer)

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
  discard

proc render*(artist: Artist3D) =
  if artist.state.isNil:
    return
  let state = artist.state
  state[].ensureReady()
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

  var binding = GpuBufferBinding(buffer: state.vertexBuffer, offset: 0)
  bindGPUGraphicsPipeline(pass, state.pipeline)
  bindGpuVertexBuffers(pass, 0, addr binding, 1)
  drawGPUPrimitives(pass, TriangleIndices.len.uint32, 1, 0, 0)
  endGPURenderPass(pass)

  if not submitGPUCommandBuffer(commandBuffer):
    raiseGpuError("Failed to submit GPU command buffer")
  discard waitForGPUIdle(state[].device)

  var dst =
    FRect(x: 0, y: 0, w: state.textureWidth.cfloat, h: state.textureHeight.cfloat)
  discard renderTexture(state.renderer, state.renderTexture, nil, addr dst)
