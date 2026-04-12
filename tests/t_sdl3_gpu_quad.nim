import std/[os, strformat]

import ellipse/platform/SDL3
import ellipse/platform/SDL3gpu
import ellipse/platform/SDL3ext
import ellipse/platform/SDL3gpuext

type
  DemoError = object of CatchableError

  Vertex = object
    position: array[2, cfloat]
    uv: array[2, cfloat]

  DemoState = object
    sdl: AppHandle
    window: WindowHandle
    claim: GPUWindowClaimHandle
    device: GPUDeviceHandle
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

proc require(condition: bool; message: string) =
  if not condition:
    raise newException(DemoError, message & ": " & $getError())

proc shaderPath(name: string): string =
  shaderDir / name

proc loadShaderCode(path: string): string =
  if not fileExists(path):
    raise newException(
      DemoError,
      &"Missing shader binary '{path}'. Run `nimble build_gpu_shaders` first."
    )
  readFile(path)

proc createShader(
  device: GPUDeviceHandle,
  path: string,
  stage: GPUShaderStage,
  numSamplers: uint32
): GPUShaderHandle =
  let code = loadShaderCode(path)
  let createInfo = GPUShaderCreateInfo(
    code_size: csize_t(code.len),
    code: cast[ptr uint8](unsafeAddr code[0]),
    entrypoint: "main",
    format: GPU_SHADERFORMAT_SPIRV,
    stage: stage,
    num_samplers: numSamplers,
    num_storage_textures: 0,
    num_storage_buffers: 0,
    num_uniform_buffers: 0,
    props: 0
  )
  try:
    result = createGPUShader(device, createInfo)
  except SDL3gpuext.Error as err:
    raise newException(DemoError, &"createGPUShader failed for '{path}': " & err.msg)

proc quadVertices(): array[6, Vertex] =
  [
    Vertex(position: [-0.6'f32, -0.6'f32], uv: [0.0'f32, 1.0'f32]),
    Vertex(position: [ 0.6'f32, -0.6'f32], uv: [1.0'f32, 1.0'f32]),
    Vertex(position: [ 0.6'f32,  0.6'f32], uv: [1.0'f32, 0.0'f32]),
    Vertex(position: [-0.6'f32, -0.6'f32], uv: [0.0'f32, 1.0'f32]),
    Vertex(position: [ 0.6'f32,  0.6'f32], uv: [1.0'f32, 0.0'f32]),
    Vertex(position: [-0.6'f32,  0.6'f32], uv: [0.0'f32, 0.0'f32])
  ]

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

proc uploadBytes(device: GPUDeviceHandle; target: GPUBufferHandle; data: pointer; size: int) =
  let transferInfo = GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(size),
    props: 0
  )
  let transferBuffer = createGPUTransferBuffer(device, transferInfo)

  let mapped = mapGPUTransferBuffer(device, transferBuffer, false)
  copyMem(mapped, data, size)
  unmapGPUTransferBuffer(device, transferBuffer)

  let commandBuffer = acquireGPUCommandBuffer(device)
  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(DemoError, "beginGPUCopyPass failed for vertex upload: " & $getError())

  var source = GPUTransferBufferLocation(transfer_buffer: raw(transferBuffer), offset: 0)
  var destination = GPUBufferRegion(buffer: raw(target), offset: 0, size: uint32(size))
  uploadToGPUBuffer(copyPass, addr source, addr destination, false)
  endGPUCopyPass(copyPass)
  require(submitGPUCommandBuffer(commandBuffer), "submitGPUCommandBuffer failed for vertex upload")
  waitForGPUIdle(device)

proc uploadTexture(device: GPUDeviceHandle; texture: GPUTextureHandle; size: int; pixels: seq[uint8]) =
  let transferInfo = GPUTransferBufferCreateInfo(
    usage: gpuTransferBufferUsageUpload,
    size: uint32(pixels.len),
    props: 0
  )
  let transferBuffer = createGPUTransferBuffer(device, transferInfo)

  let mapped = mapGPUTransferBuffer(device, transferBuffer, false)
  copyMem(mapped, unsafeAddr pixels[0], pixels.len)
  unmapGPUTransferBuffer(device, transferBuffer)

  let commandBuffer = acquireGPUCommandBuffer(device)
  let copyPass = beginGPUCopyPass(commandBuffer)
  if copyPass.isNil:
    discard cancelGPUCommandBuffer(commandBuffer)
    raise newException(DemoError, "beginGPUCopyPass failed for texture upload: " & $getError())

  var source = GPUTextureTransferInfo(
    transfer_buffer: raw(transferBuffer),
    offset: 0,
    pixels_per_row: uint32(size),
    rows_per_layer: uint32(size)
  )
  var destination = GPUTextureRegion(
    texture: raw(texture),
    mip_level: 0,
    layer: 0,
    x: 0,
    y: 0,
    z: 0,
    w: uint32(size),
    h: uint32(size),
    d: 1
  )
  uploadToGPUTexture(copyPass, addr source, addr destination, false)
  endGPUCopyPass(copyPass)
  require(submitGPUCommandBuffer(commandBuffer), "submitGPUCommandBuffer failed for texture upload")
  waitForGPUIdle(device)

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

  let swapchainFormat = getGPUSwapchainTextureFormat(state.claim)
  var colorTarget = GPUColorTargetDescription(
    format: swapchainFormat,
    blend_state: GPUColorTargetBlendState(
      color_write_mask: GPU_COLORCOMPONENT_R or GPU_COLORCOMPONENT_G or GPU_COLORCOMPONENT_B or GPU_COLORCOMPONENT_A,
      enable_blend: false,
      enable_color_write_mask: true
    )
  )

  var pipelineInfo = GPUGraphicsPipelineCreateInfo(
    vertex_shader: raw(state.vertexShader),
    fragment_shader: raw(state.fragmentShader),
    vertex_input_state: GPUVertexInputState(
      vertex_buffer_descriptions: addr vertexBufferDesc,
      num_vertex_buffers: 1,
      vertex_attributes: addr vertexAttributes[0],
      num_vertex_attributes: uint32(vertexAttributes.len)
    ),
    primitive_type: gpuPrimitiveTypeTriangleList,
    rasterizer_state: GPURasterizerState(
      fill_mode: gpuFillModeFill,
      cull_mode: gpuCullModeNone,
      front_face: gpuFrontFaceCounterClockwise,
      enable_depth_bias: false,
      enable_depth_clip: true
    ),
    multisample_state: GPUMultisampleState(
      sample_count: gpuSampleCount1,
      sample_mask: 0,
      enable_mask: false,
      enable_alpha_to_coverage: false
    ),
    depth_stencil_state: GPUDepthStencilState(
      compare_op: gpuCompareOpInvalid,
      enable_depth_test: false,
      enable_depth_write: false,
      enable_stencil_test: false
    ),
    target_info: GPUGraphicsPipelineTargetInfo(
      color_target_descriptions: addr colorTarget,
      num_color_targets: 1,
      depth_stencil_format: 0,
      has_depth_stencil_target: false
    ),
    props: 0
  )

  state.pipeline = createGPUGraphicsPipeline(state.device, pipelineInfo)

proc initializeResources(state: var DemoState) =
  state.vertexShader = createShader(state.device, shaderPath("quad.vert.spv"), gpuShaderStageVertex, 0)
  state.fragmentShader = createShader(state.device, shaderPath("quad.frag.spv"), gpuShaderStageFragment, 1)

  let bufferInfo = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX,
    size: uint32(sizeof(quadVertices())),
    props: 0
  )
  state.vertexBuffer = createGPUBuffer(state.device, bufferInfo)

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
  state.texture = createGPUTexture(state.device, textureInfo)

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
  state.sampler = createGPUSampler(state.device, samplerInfo)

  let vertices = quadVertices()
  uploadBytes(
    state.device,
    state.vertexBuffer,
    unsafeAddr vertices[0],
    sizeof(vertices)
  )

  let pixels = checkerPixels(checkerSize)
  uploadTexture(state.device, state.texture, checkerSize, pixels)
  createPipeline(state)

proc cleanup(state: var DemoState) =
  if not raw(state.device).isNil:
    try:
      waitForGPUIdle(state.device)
    except SDL3gpuext.Error:
      discard
  var oldState = move(state)
  state = default(DemoState)
  discard oldState

proc appInitCallback(appState: ptr pointer; argc: cint; argv: cstringArray): AppResult {.cdecl.} =
  discard argc
  discard argv
  appState[] = addr gDemo
  gDemo = default(DemoState)

  if not setAppMetadata(
    "Ellipse SDL3 GPU Quad",
    "0.0.0",
    "dev.ellipse.tests.sdl3gpuquad"
  ):
    echo "setAppMetadata failed: ", getError()
    return appFailure

  try:
    gDemo.sdl = SDL3ext.init(INIT_VIDEO)
    gDemo.window = SDL3ext.createWindow("Ellipse SDL3 GPU Quad", windowWidth, windowHeight, 0)
    gDemo.device = SDL3gpuext.createGPUDevice(GPU_SHADERFORMAT_SPIRV, true, "vulkan")
    gDemo.claim = SDL3gpuext.claimWindowForGPUDevice(gDemo.device, gDemo.window)
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
      acquireGPUCommandBuffer(gDemo.device)
    except SDL3gpuext.Error as err:
      echo err.msg
      return appFailure

  var swapchainTexture: ptr GPUTexture
  var swapchainWidth: uint32
  var swapchainHeight: uint32
  if not waitAndAcquireGPUSwapchainTexture(
    commandBuffer,
    raw(gDemo.window),
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
