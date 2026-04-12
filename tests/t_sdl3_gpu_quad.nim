import std/[os]

import ellipse/platform/SDL3
import ellipse/platform/SDL3gpu
import ellipse/platform/SDL3gpuext
import ellipse/rendering/[gpucontext, gpupipelines, gpushaders, gpuuploads]

type
  DemoError = object of CatchableError

  # This vertex layout belongs to the demo because it matches this sample's
  # concrete shaders and geometry. Other applications can define their own.
  Vertex = object
    position: array[2, cfloat]
    uv: array[2, cfloat]

  # This state is deliberately sample-specific: one window context plus the
  # resources needed to draw a single checkerboard-textured quad.
  DemoState = object
    context: GPUWindowContext
    vertexBuffer: GPUBufferHandle
    texture: GPUTextureHandle
    sampler: GPUSamplerHandle
    vertexShader: GPUShaderHandle
    fragmentShader: GPUShaderHandle
    pipeline: GPUGraphicsPipelineHandle
    quitRequested: bool

const
  windowWidth = 960
  windowHeight = 540
  checkerSize = 128
  shaderDir = currentSourcePath.parentDir / "assets" / "gpu"

var gDemo: DemoState

# Asset lookup stays in the demo because the file layout is sample-specific.
proc shaderPath(name: string): string =
  shaderDir / name

# This quad geometry is the concrete mesh for this sample. More general mesh
# builders can be added later without changing the reusable rendering modules.
proc quadVertices(): array[6, Vertex] =
  [
    Vertex(position: [-0.6'f32, -0.6'f32], uv: [0.0'f32, 1.0'f32]),
    Vertex(position: [ 0.6'f32, -0.6'f32], uv: [1.0'f32, 1.0'f32]),
    Vertex(position: [ 0.6'f32,  0.6'f32], uv: [1.0'f32, 0.0'f32]),
    Vertex(position: [-0.6'f32, -0.6'f32], uv: [0.0'f32, 1.0'f32]),
    Vertex(position: [ 0.6'f32,  0.6'f32], uv: [1.0'f32, 0.0'f32]),
    Vertex(position: [-0.6'f32,  0.6'f32], uv: [0.0'f32, 0.0'f32])
  ]

# The checkerboard is also demo-specific. Another app might load files, render
# to textures, or generate very different procedural content.
proc checkerPixels(size: int): seq[uint8] =
  result = newSeq[uint8](size * size * 4)
  let cellSize = max(1, size div 8)
  for y in 0 ..< size:
    for x in 0 ..< size:
      let checkerOn = ((x div cellSize) + (y div cellSize)) mod 2 == 0
      let color =
        if checkerOn:
          [uint8(230), uint8(230), uint8(230), uint8(255)]
        else:
          [uint8(35), uint8(35), uint8(35), uint8(255)]
      let offset = (y * size + x) * 4
      result[offset + 0] = color[0]
      result[offset + 1] = color[1]
      result[offset + 2] = color[2]
      result[offset + 3] = color[3]

# The pipeline helper is generic, but the vertex layout remains here because it
# is tied to the `Vertex` type and the sample's shader inputs.
proc createPipeline(state: var DemoState) =
  var vertexBufferDesc = GPUVertexBufferDescription(
    slot: 0,
    pitch: uint32(sizeof(Vertex)),
    input_rate: gpuVertexInputRateVertex,
    instance_step_rate: 0
  )
  var vertexAttributes = [
    GPUVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(Vertex, position))
    ),
    GPUVertexAttribute(
      location: 1,
      buffer_slot: 0,
      format: gpuVertexElementFormatFloat2,
      offset: uint32(offsetof(Vertex, uv))
    )
  ]

  state.pipeline = createTexturedPipeline(
    state.context.device,
    getGPUSwapchainTextureFormat(state.context.claim),
    state.vertexShader,
    state.fragmentShader,
    addr vertexBufferDesc,
    1,
    addr vertexAttributes[0],
    uint32(vertexAttributes.len)
  )

proc initializeResources(state: var DemoState) =
  # The demo chooses which shaders and resources to create; the rendering
  # modules only supply the generic mechanics.
  try:
    state.vertexShader = createShaderFromFile(
      state.context.device,
      shaderPath("quad.vert.spv"),
      gpuShaderStageVertex,
      0
    )
    state.fragmentShader = createShaderFromFile(
      state.context.device,
      shaderPath("quad.frag.spv"),
      gpuShaderStageFragment,
      1
    )
  except ShaderLoadError as err:
    raise newException(DemoError, err.msg)

  let bufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX,
    size: uint32(sizeof(quadVertices())),
    props: 0
  )
  state.vertexBuffer = createGPUBuffer(state.context.device, bufferInfo)

  let textureInfo = GPUTextureCreateInfo(
    `type`: gpuTextureType2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER,
    width: checkerSize.uint32,
    height: checkerSize.uint32,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: gpuSampleCount1,
    props: 0
  )
  state.texture = createGPUTexture(state.context.device, textureInfo)

  let samplerInfo = GPUSamplerCreateInfo(
    min_filter: gpuFilterNearest,
    mag_filter: gpuFilterNearest,
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
  state.sampler = createGPUSampler(state.context.device, samplerInfo)

  let vertices = quadVertices()
  try:
    uploadBufferData(
      state.context.device,
      state.vertexBuffer,
      unsafeAddr vertices[0],
      sizeof(vertices),
      "quad vertex upload"
    )
  except UploadError as err:
    raise newException(DemoError, err.msg)

  let pixels = checkerPixels(checkerSize)
  try:
    uploadTexture2DData(
      state.context.device,
      state.texture,
      checkerSize,
      checkerSize,
      pixels,
      "checkerboard texture upload"
    )
  except UploadError as err:
    raise newException(DemoError, err.msg)

  createPipeline(state)

proc cleanup(state: var DemoState) =
  if not raw(state.context.device).isNil:
    try:
      waitForGPUIdle(state.context.device)
    except SDL3gpuext.Error:
      discard
  var oldState = move(state)
  state = default(DemoState)
  discard oldState

# The SDL callback shell remains in the test because it is application logic,
# not generic engine code. Another app can reuse the rendering modules with a
# completely different state model and frame loop.
proc appInitCallback(appState: ptr pointer; argc: cint; argv: cstringArray): AppResult {.cdecl.} =
  discard argc
  discard argv
  appState[] = addr gDemo
  gDemo = default(DemoState)

  try:
    gDemo.context = initGPUWindowContext(
      GPUWindowConfig(
        appId: "dev.ellipse.tests.sdl3gpuquad",
        title: "Ellipse SDL3 GPU Quad",
        width: windowWidth,
        height: windowHeight,
        windowFlags: 0,
        shaderFormat: GPU_SHADERFORMAT_SPIRV,
        driverName: "vulkan",
        debugMode: true
      )
    )
    initializeResources(gDemo)
    return appContinue
  except CatchableError as err:
    echo err.msg
    cleanup(gDemo)
    return appFailure

proc iterateCallback(appState: pointer): AppResult {.cdecl.} =
  discard appState
  if gDemo.quitRequested:
    return appSuccess

  let commandBuffer =
    try:
      acquireGPUCommandBuffer(gDemo.context.device)
    except SDL3gpuext.Error as err:
      echo err.msg
      return appFailure

  var swapchainTexture: ptr GPUTexture
  var swapchainWidth: uint32
  var swapchainHeight: uint32
  if not waitAndAcquireGPUSwapchainTexture(
    commandBuffer,
    raw(gDemo.context.window),
    addr swapchainTexture,
    addr swapchainWidth,
    addr swapchainHeight
  ):
    echo "waitAndAcquireGPUSwapchainTexture failed: ", getError()
    discard cancelGPUCommandBuffer(commandBuffer)
    return appFailure

  if swapchainTexture.isNil:
    return if submitGPUCommandBuffer(commandBuffer): appContinue else: appFailure

  var colorTarget = GPUColorTargetInfo(
    texture: swapchainTexture,
    mip_level: 0,
    layer_or_depth_plane: 0,
    clear_color: FColor(r: 0.08, g: 0.10, b: 0.13, a: 1.0),
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
    echo "beginGPURenderPass failed: ", getError()
    discard cancelGPUCommandBuffer(commandBuffer)
    return appFailure

  var vertexBinding = GPUBufferBinding(buffer: raw(gDemo.vertexBuffer), offset: 0)
  var textureBinding = GPUTextureSamplerBinding(texture: raw(gDemo.texture), sampler: raw(gDemo.sampler))

  bindGPUGraphicsPipeline(renderPass, raw(gDemo.pipeline))
  bindGPUVertexBuffers(renderPass, 0, addr vertexBinding, 1)
  bindGPUFragmentSamplers(renderPass, 0, addr textureBinding, 1)

  # Extend here for more rendering:
  # - push per-draw uniforms before the pass to add transforms or tinting
  # - swap this to indexed draws once you introduce shared meshes
  # - batch multiple quads by streaming one larger vertex buffer each frame
  # - split texture/sampler/material state so many draws can reuse one pipeline
  drawGPUPrimitives(renderPass, 6, 1, 0, 0)
  endGPURenderPass(renderPass)

  # A camera/projection path can keep this exact render loop and only change
  # the shader interface plus the data pushed to uniform slots.
  if not submitGPUCommandBuffer(commandBuffer):
    echo "submitGPUCommandBuffer failed: ", getError()
    return appFailure

  appContinue

proc eventCallback(appState: pointer; event: ptr Event): AppResult {.cdecl.} =
  discard appState
  case event[].`type`
  of EVENT_QUIT, EVENT_WINDOW_CLOSE_REQUESTED:
    gDemo.quitRequested = true
    appSuccess
  else:
    appContinue

proc quitCallback(appState: pointer; result: AppResult) {.cdecl.} =
  discard appState
  discard result
  cleanup(gDemo)

when isMainModule:
  discard enterAppMainCallbacks(
    0,
    nil,
    appInitCallback,
    iterateCallback,
    eventCallback,
    quitCallback
  )
