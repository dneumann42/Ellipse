{.passL: "-lSDL3".}

import ./SDL3

type
  GPUShaderFormat* = uint32
  GPUTextureUsageFlags* = uint32
  GPUBufferUsageFlags* = uint32
  GPUColorComponentFlags* = uint8
  GPUTextureFormat* = uint32

  GPUTransferBufferUsage* {.size: sizeof(cint), importc: "SDL_GPUTransferBufferUsage", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuTransferBufferUsageUpload = 0
    gpuTransferBufferUsageDownload = 1

  GPUTextureType* {.size: sizeof(cint), importc: "SDL_GPUTextureType", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuTextureType2D = 0
    gpuTextureType2DArray = 1
    gpuTextureType3D = 2
    gpuTextureTypeCube = 3
    gpuTextureTypeCubeArray = 4

  GPUShaderStage* {.size: sizeof(cint), importc: "SDL_GPUShaderStage", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuShaderStageVertex = 0
    gpuShaderStageFragment = 1

  GPUVertexElementFormat* {.size: sizeof(cint), importc: "SDL_GPUVertexElementFormat", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuVertexElementFormatInvalid = 0
    gpuVertexElementFormatInt = 1
    gpuVertexElementFormatInt2 = 2
    gpuVertexElementFormatInt3 = 3
    gpuVertexElementFormatInt4 = 4
    gpuVertexElementFormatUInt = 5
    gpuVertexElementFormatUInt2 = 6
    gpuVertexElementFormatUInt3 = 7
    gpuVertexElementFormatUInt4 = 8
    gpuVertexElementFormatFloat = 9
    gpuVertexElementFormatFloat2 = 10
    gpuVertexElementFormatFloat3 = 11
    gpuVertexElementFormatFloat4 = 12

  GPUVertexInputRate* {.size: sizeof(cint), importc: "SDL_GPUVertexInputRate", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuVertexInputRateVertex = 0
    gpuVertexInputRateInstance = 1

  GPUPrimitiveType* {.size: sizeof(cint), importc: "SDL_GPUPrimitiveType", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuPrimitiveTypeTriangleList = 0
    gpuPrimitiveTypeTriangleStrip = 1
    gpuPrimitiveTypeLineList = 2
    gpuPrimitiveTypeLineStrip = 3
    gpuPrimitiveTypePointList = 4

  GPULoadOp* {.size: sizeof(cint), importc: "SDL_GPULoadOp", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuLoadOpLoad = 0
    gpuLoadOpClear = 1
    gpuLoadOpDontCare = 2

  GPUStoreOp* {.size: sizeof(cint), importc: "SDL_GPUStoreOp", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuStoreOpStore = 0
    gpuStoreOpDontCare = 1
    gpuStoreOpResolve = 2
    gpuStoreOpResolveAndStore = 3

  GPUFilter* {.size: sizeof(cint), importc: "SDL_GPUFilter", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuFilterNearest = 0
    gpuFilterLinear = 1

  GPUSamplerMipmapMode* {.size: sizeof(cint), importc: "SDL_GPUSamplerMipmapMode", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuSamplerMipmapModeNearest = 0
    gpuSamplerMipmapModeLinear = 1

  GPUSamplerAddressMode* {.size: sizeof(cint), importc: "SDL_GPUSamplerAddressMode", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuSamplerAddressModeRepeat = 0
    gpuSamplerAddressModeMirroredRepeat = 1
    gpuSamplerAddressModeClampToEdge = 2

  GPUFillMode* {.size: sizeof(cint), importc: "SDL_GPUFillMode", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuFillModeFill = 0
    gpuFillModeLine = 1

  GPUCullMode* {.size: sizeof(cint), importc: "SDL_GPUCullMode", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuCullModeNone = 0
    gpuCullModeFront = 1
    gpuCullModeBack = 2

  GPUFrontFace* {.size: sizeof(cint), importc: "SDL_GPUFrontFace", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuFrontFaceCounterClockwise = 0
    gpuFrontFaceClockwise = 1

  GPUCompareOp* {.size: sizeof(cint), importc: "SDL_GPUCompareOp", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuCompareOpInvalid = 0
    gpuCompareOpNever = 1
    gpuCompareOpLess = 2
    gpuCompareOpEqual = 3
    gpuCompareOpLessOrEqual = 4
    gpuCompareOpGreater = 5
    gpuCompareOpNotEqual = 6
    gpuCompareOpGreaterOrEqual = 7
    gpuCompareOpAlways = 8

  GPUIndexElementSize* {.size: sizeof(cint), importc: "SDL_GPUIndexElementSize", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuIndexElementSize16Bit = 0
    gpuIndexElementSize32Bit = 1

  GPUBlendOp* {.size: sizeof(cint), importc: "SDL_GPUBlendOp", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuBlendOpInvalid = 0
    gpuBlendOpAdd = 1
    gpuBlendOpSubtract = 2
    gpuBlendOpReverseSubtract = 3
    gpuBlendOpMin = 4
    gpuBlendOpMax = 5

  GPUBlendFactor* {.size: sizeof(cint), importc: "SDL_GPUBlendFactor", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuBlendFactorInvalid = 0
    gpuBlendFactorZero = 1
    gpuBlendFactorOne = 2
    gpuBlendFactorSrcColor = 3
    gpuBlendFactorOneMinusSrcColor = 4
    gpuBlendFactorDstColor = 5
    gpuBlendFactorOneMinusDstColor = 6
    gpuBlendFactorSrcAlpha = 7
    gpuBlendFactorOneMinusSrcAlpha = 8
    gpuBlendFactorDstAlpha = 9
    gpuBlendFactorOneMinusDstAlpha = 10
    gpuBlendFactorConstantColor = 11
    gpuBlendFactorOneMinusConstantColor = 12
    gpuBlendFactorSrcAlphaSaturate = 13

  GPUSampleCount* {.size: sizeof(cint), importc: "SDL_GPUSampleCount", header: "<SDL3/SDL_gpu.h>".} = enum
    gpuSampleCount1 = 0
    gpuSampleCount2 = 1
    gpuSampleCount4 = 2
    gpuSampleCount8 = 3

  GPUDevice* {.importc: "SDL_GPUDevice", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUBuffer* {.importc: "SDL_GPUBuffer", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUTransferBuffer* {.importc: "SDL_GPUTransferBuffer", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUTexture* {.importc: "SDL_GPUTexture", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUSampler* {.importc: "SDL_GPUSampler", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUShader* {.importc: "SDL_GPUShader", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUGraphicsPipeline* {.importc: "SDL_GPUGraphicsPipeline", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUCommandBuffer* {.importc: "SDL_GPUCommandBuffer", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPURenderPass* {.importc: "SDL_GPURenderPass", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUCopyPass* {.importc: "SDL_GPUCopyPass", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object
  GPUFence* {.importc: "SDL_GPUFence", header: "<SDL3/SDL_gpu.h>", incompleteStruct.} = object

  FColor* {.importc: "SDL_FColor", header: "<SDL3/SDL_pixels.h>", bycopy.} = object
    r*, g*, b*, a*: cfloat

  Rect* {.importc: "SDL_Rect", header: "<SDL3/SDL_rect.h>", bycopy.} = object
    x*, y*, w*, h*: cint

  GPUSamplerCreateInfo* {.importc: "SDL_GPUSamplerCreateInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    min_filter*: GPUFilter
    mag_filter*: GPUFilter
    mipmap_mode*: GPUSamplerMipmapMode
    address_mode_u*: GPUSamplerAddressMode
    address_mode_v*: GPUSamplerAddressMode
    address_mode_w*: GPUSamplerAddressMode
    mip_lod_bias*: cfloat
    max_anisotropy*: cfloat
    compare_op*: GPUCompareOp
    min_lod*: cfloat
    max_lod*: cfloat
    enable_anisotropy*: bool
    enable_compare*: bool
    padding1*: uint8
    padding2*: uint8
    props*: PropertiesID

  GPUVertexBufferDescription* {.importc: "SDL_GPUVertexBufferDescription", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    slot*: uint32
    pitch*: uint32
    input_rate*: GPUVertexInputRate
    instance_step_rate*: uint32

  GPUVertexAttribute* {.importc: "SDL_GPUVertexAttribute", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    location*: uint32
    buffer_slot*: uint32
    format*: GPUVertexElementFormat
    offset*: uint32

  GPUVertexInputState* {.importc: "SDL_GPUVertexInputState", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    vertex_buffer_descriptions*: ptr GPUVertexBufferDescription
    num_vertex_buffers*: uint32
    vertex_attributes*: ptr GPUVertexAttribute
    num_vertex_attributes*: uint32

  GPUShaderCreateInfo* {.importc: "SDL_GPUShaderCreateInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    code_size*: csize_t
    code*: ptr uint8
    entrypoint*: cstring
    format*: GPUShaderFormat
    stage*: GPUShaderStage
    num_samplers*: uint32
    num_storage_textures*: uint32
    num_storage_buffers*: uint32
    num_uniform_buffers*: uint32
    props*: PropertiesID

  GPUTextureCreateInfo* {.importc: "SDL_GPUTextureCreateInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    `type`*: GPUTextureType
    format*: GPUTextureFormat
    usage*: GPUTextureUsageFlags
    width*: uint32
    height*: uint32
    layer_count_or_depth*: uint32
    num_levels*: uint32
    sample_count*: GPUSampleCount
    props*: PropertiesID

  GPUBufferCreateInfo* {.importc: "SDL_GPUBufferCreateInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    usage*: GPUBufferUsageFlags
    size*: uint32
    props*: PropertiesID

  GPUTransferBufferCreateInfo* {.importc: "SDL_GPUTransferBufferCreateInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    usage*: GPUTransferBufferUsage
    size*: uint32
    props*: PropertiesID

  GPURasterizerState* {.importc: "SDL_GPURasterizerState", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    fill_mode*: GPUFillMode
    cull_mode*: GPUCullMode
    front_face*: GPUFrontFace
    depth_bias_constant_factor*: cfloat
    depth_bias_clamp*: cfloat
    depth_bias_slope_factor*: cfloat
    enable_depth_bias*: bool
    enable_depth_clip*: bool
    padding1*: uint8
    padding2*: uint8

  GPUMultisampleState* {.importc: "SDL_GPUMultisampleState", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    sample_count*: GPUSampleCount
    sample_mask*: uint32
    enable_mask*: bool
    enable_alpha_to_coverage*: bool
    padding2*: uint8
    padding3*: uint8

  GPUStencilOpState* {.importc: "SDL_GPUStencilOpState", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    fail_op*: cint
    pass_op*: cint
    depth_fail_op*: cint
    compare_op*: GPUCompareOp

  GPUDepthStencilState* {.importc: "SDL_GPUDepthStencilState", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    compare_op*: GPUCompareOp
    back_stencil_state*: GPUStencilOpState
    front_stencil_state*: GPUStencilOpState
    compare_mask*: uint8
    write_mask*: uint8
    enable_depth_test*: bool
    enable_depth_write*: bool
    enable_stencil_test*: bool
    padding1*: uint8
    padding2*: uint8
    padding3*: uint8

  GPUColorTargetBlendState* {.importc: "SDL_GPUColorTargetBlendState", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    src_color_blendfactor*: cint
    dst_color_blendfactor*: cint
    color_blend_op*: cint
    src_alpha_blendfactor*: cint
    dst_alpha_blendfactor*: cint
    alpha_blend_op*: cint
    color_write_mask*: GPUColorComponentFlags
    enable_blend*: bool
    enable_color_write_mask*: bool
    padding1*: uint8
    padding2*: uint8

  GPUColorTargetDescription* {.importc: "SDL_GPUColorTargetDescription", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    format*: GPUTextureFormat
    blend_state*: GPUColorTargetBlendState

  GPUGraphicsPipelineTargetInfo* {.importc: "SDL_GPUGraphicsPipelineTargetInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    color_target_descriptions*: ptr GPUColorTargetDescription
    num_color_targets*: uint32
    depth_stencil_format*: GPUTextureFormat
    has_depth_stencil_target*: bool
    padding1*: uint8
    padding2*: uint8
    padding3*: uint8

  GPUGraphicsPipelineCreateInfo* {.importc: "SDL_GPUGraphicsPipelineCreateInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    vertex_shader*: ptr GPUShader
    fragment_shader*: ptr GPUShader
    vertex_input_state*: GPUVertexInputState
    primitive_type*: GPUPrimitiveType
    rasterizer_state*: GPURasterizerState
    multisample_state*: GPUMultisampleState
    depth_stencil_state*: GPUDepthStencilState
    target_info*: GPUGraphicsPipelineTargetInfo
    props*: PropertiesID

  GPUTextureTransferInfo* {.importc: "SDL_GPUTextureTransferInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    transfer_buffer*: ptr GPUTransferBuffer
    offset*: uint32
    pixels_per_row*: uint32
    rows_per_layer*: uint32

  GPUTransferBufferLocation* {.importc: "SDL_GPUTransferBufferLocation", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    transfer_buffer*: ptr GPUTransferBuffer
    offset*: uint32

  GPUTextureRegion* {.importc: "SDL_GPUTextureRegion", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    texture*: ptr GPUTexture
    mip_level*: uint32
    layer*: uint32
    x*: uint32
    y*: uint32
    z*: uint32
    w*: uint32
    h*: uint32
    d*: uint32

  GPUBufferRegion* {.importc: "SDL_GPUBufferRegion", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    buffer*: ptr GPUBuffer
    offset*: uint32
    size*: uint32

  GPUBufferBinding* {.importc: "SDL_GPUBufferBinding", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    buffer*: ptr GPUBuffer
    offset*: uint32

  GPUTextureSamplerBinding* {.importc: "SDL_GPUTextureSamplerBinding", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    texture*: ptr GPUTexture
    sampler*: ptr GPUSampler

  GPUColorTargetInfo* {.importc: "SDL_GPUColorTargetInfo", header: "<SDL3/SDL_gpu.h>", bycopy.} = object
    texture*: ptr GPUTexture
    mip_level*: uint32
    layer_or_depth_plane*: uint32
    clear_color*: FColor
    load_op*: GPULoadOp
    store_op*: GPUStoreOp
    resolve_texture*: ptr GPUTexture
    resolve_mip_level*: uint32
    resolve_layer*: uint32
    cycle*: bool
    cycle_resolve_texture*: bool
    padding1*: uint8
    padding2*: uint8

const
  GPU_TEXTUREFORMAT_INVALID* = 0'u32
  GPU_TEXTUREFORMAT_A8_UNORM* = 1'u32
  GPU_TEXTUREFORMAT_R8_UNORM* = 2'u32
  GPU_TEXTUREFORMAT_R8G8_UNORM* = 3'u32
  GPU_TEXTUREFORMAT_R8G8B8A8_UNORM* = 4'u32
  GPU_TEXTUREFORMAT_R16_UNORM* = 5'u32
  GPU_TEXTUREFORMAT_B8G8R8A8_UNORM* = 12'u32

  GPU_SHADERFORMAT_INVALID* = 0'u32
  GPU_SHADERFORMAT_PRIVATE* = 1'u32 shl 0
  GPU_SHADERFORMAT_SPIRV* = 1'u32 shl 1
  GPU_SHADERFORMAT_DXBC* = 1'u32 shl 2
  GPU_SHADERFORMAT_DXIL* = 1'u32 shl 3
  GPU_SHADERFORMAT_MSL* = 1'u32 shl 4
  GPU_SHADERFORMAT_METALLIB* = 1'u32 shl 5

  GPU_TEXTUREUSAGE_SAMPLER* = 1'u32 shl 0
  GPU_TEXTUREUSAGE_COLOR_TARGET* = 1'u32 shl 1
  GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET* = 1'u32 shl 2
  GPU_TEXTUREUSAGE_GRAPHICS_STORAGE_READ* = 1'u32 shl 3
  GPU_TEXTUREUSAGE_COMPUTE_STORAGE_READ* = 1'u32 shl 4
  GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE* = 1'u32 shl 5
  GPU_TEXTUREUSAGE_COMPUTE_STORAGE_SIMULTANEOUS_READ_WRITE* = 1'u32 shl 6

  GPU_BUFFERUSAGE_VERTEX* = 1'u32 shl 0
  GPU_BUFFERUSAGE_INDEX* = 1'u32 shl 1
  GPU_BUFFERUSAGE_INDIRECT* = 1'u32 shl 2
  GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ* = 1'u32 shl 3
  GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ* = 1'u32 shl 4
  GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE* = 1'u32 shl 5

  GPU_COLORCOMPONENT_R* = 1'u8 shl 0
  GPU_COLORCOMPONENT_G* = 1'u8 shl 1
  GPU_COLORCOMPONENT_B* = 1'u8 shl 2
  GPU_COLORCOMPONENT_A* = 1'u8 shl 3

proc createGPUDevice*(
  formatFlags: GPUShaderFormat,
  debugMode: bool,
  name: cstring
): ptr GPUDevice {.
  importc: "SDL_CreateGPUDevice",
  header: "<SDL3/SDL_gpu.h>"
.}

proc destroyGPUDevice*(device: ptr GPUDevice) {.
  importc: "SDL_DestroyGPUDevice",
  header: "<SDL3/SDL_gpu.h>"
.}

proc claimWindowForGPUDevice*(device: ptr GPUDevice; window: ptr Window): bool {.
  importc: "SDL_ClaimWindowForGPUDevice",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseWindowFromGPUDevice*(device: ptr GPUDevice; window: ptr Window) {.
  importc: "SDL_ReleaseWindowFromGPUDevice",
  header: "<SDL3/SDL_gpu.h>"
.}

proc getGPUSwapchainTextureFormat*(device: ptr GPUDevice; window: ptr Window): GPUTextureFormat {.
  importc: "SDL_GetGPUSwapchainTextureFormat",
  header: "<SDL3/SDL_gpu.h>"
.}

proc getGPUTextureFormatFromPixelFormat*(format: PixelFormat): GPUTextureFormat {.
  importc: "SDL_GetGPUTextureFormatFromPixelFormat",
  header: "<SDL3/SDL_gpu.h>"
.}

proc createGPUShader*(device: ptr GPUDevice; createInfo: ptr GPUShaderCreateInfo): ptr GPUShader {.
  importc: "SDL_CreateGPUShader",
  header: "<SDL3/SDL_gpu.h>"
.}

proc createGPUTexture*(device: ptr GPUDevice; createInfo: ptr GPUTextureCreateInfo): ptr GPUTexture {.
  importc: "SDL_CreateGPUTexture",
  header: "<SDL3/SDL_gpu.h>"
.}

proc createGPUBuffer*(device: ptr GPUDevice; createInfo: ptr GPUBufferCreateInfo): ptr GPUBuffer {.
  importc: "SDL_CreateGPUBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc createGPUTransferBuffer*(device: ptr GPUDevice; createInfo: ptr GPUTransferBufferCreateInfo): ptr GPUTransferBuffer {.
  importc: "SDL_CreateGPUTransferBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc createGPUSampler*(device: ptr GPUDevice; createInfo: ptr GPUSamplerCreateInfo): ptr GPUSampler {.
  importc: "SDL_CreateGPUSampler",
  header: "<SDL3/SDL_gpu.h>"
.}

proc createGPUGraphicsPipeline*(device: ptr GPUDevice; createInfo: ptr GPUGraphicsPipelineCreateInfo): ptr GPUGraphicsPipeline {.
  importc: "SDL_CreateGPUGraphicsPipeline",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseGPUTexture*(device: ptr GPUDevice; texture: ptr GPUTexture) {.
  importc: "SDL_ReleaseGPUTexture",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseGPUSampler*(device: ptr GPUDevice; sampler: ptr GPUSampler) {.
  importc: "SDL_ReleaseGPUSampler",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseGPUBuffer*(device: ptr GPUDevice; buffer: ptr GPUBuffer) {.
  importc: "SDL_ReleaseGPUBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseGPUTransferBuffer*(device: ptr GPUDevice; transferBuffer: ptr GPUTransferBuffer) {.
  importc: "SDL_ReleaseGPUTransferBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseGPUShader*(device: ptr GPUDevice; shader: ptr GPUShader) {.
  importc: "SDL_ReleaseGPUShader",
  header: "<SDL3/SDL_gpu.h>"
.}

proc releaseGPUGraphicsPipeline*(device: ptr GPUDevice; pipeline: ptr GPUGraphicsPipeline) {.
  importc: "SDL_ReleaseGPUGraphicsPipeline",
  header: "<SDL3/SDL_gpu.h>"
.}

proc acquireGPUCommandBuffer*(device: ptr GPUDevice): ptr GPUCommandBuffer {.
  importc: "SDL_AcquireGPUCommandBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc beginGPURenderPass*(
  commandBuffer: ptr GPUCommandBuffer,
  colorTargetInfos: ptr GPUColorTargetInfo,
  numColorTargets: uint32,
  depthStencilTargetInfo: pointer
): ptr GPURenderPass {.
  importc: "SDL_BeginGPURenderPass",
  header: "<SDL3/SDL_gpu.h>"
.}

proc bindGPUGraphicsPipeline*(renderPass: ptr GPURenderPass; pipeline: ptr GPUGraphicsPipeline) {.
  importc: "SDL_BindGPUGraphicsPipeline",
  header: "<SDL3/SDL_gpu.h>"
.}

proc setGPUScissor*(renderPass: ptr GPURenderPass; scissor: ptr Rect) {.
  importc: "SDL_SetGPUScissor",
  header: "<SDL3/SDL_gpu.h>"
.}

proc bindGPUVertexBuffers*(
  renderPass: ptr GPURenderPass,
  firstSlot: uint32,
  bindings: ptr GPUBufferBinding,
  numBindings: uint32
) {.
  importc: "SDL_BindGPUVertexBuffers",
  header: "<SDL3/SDL_gpu.h>"
.}

proc bindGPUIndexBuffer*(
  renderPass: ptr GPURenderPass,
  binding: ptr GPUBufferBinding,
  indexElementSize: GPUIndexElementSize
) {.
  importc: "SDL_BindGPUIndexBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc bindGPUFragmentSamplers*(
  renderPass: ptr GPURenderPass,
  firstSlot: uint32,
  bindings: ptr GPUTextureSamplerBinding,
  numBindings: uint32
) {.
  importc: "SDL_BindGPUFragmentSamplers",
  header: "<SDL3/SDL_gpu.h>"
.}

proc drawGPUPrimitives*(
  renderPass: ptr GPURenderPass,
  numVertices: uint32,
  numInstances: uint32,
  firstVertex: uint32,
  firstInstance: uint32
) {.
  importc: "SDL_DrawGPUPrimitives",
  header: "<SDL3/SDL_gpu.h>"
.}

proc drawGPUIndexedPrimitives*(
  renderPass: ptr GPURenderPass,
  numIndices: uint32,
  numInstances: uint32,
  firstIndex: uint32,
  vertexOffset: cint,
  firstInstance: uint32
) {.
  importc: "SDL_DrawGPUIndexedPrimitives",
  header: "<SDL3/SDL_gpu.h>"
.}

proc endGPURenderPass*(renderPass: ptr GPURenderPass) {.
  importc: "SDL_EndGPURenderPass",
  header: "<SDL3/SDL_gpu.h>"
.}

proc pushGPUVertexUniformData*(
  commandBuffer: ptr GPUCommandBuffer,
  slotIndex: uint32,
  data: pointer,
  length: uint32
) {.
  importc: "SDL_PushGPUVertexUniformData",
  header: "<SDL3/SDL_gpu.h>"
.}

proc pushGPUFragmentUniformData*(
  commandBuffer: ptr GPUCommandBuffer,
  slotIndex: uint32,
  data: pointer,
  length: uint32
) {.
  importc: "SDL_PushGPUFragmentUniformData",
  header: "<SDL3/SDL_gpu.h>"
.}

proc mapGPUTransferBuffer*(
  device: ptr GPUDevice,
  transferBuffer: ptr GPUTransferBuffer,
  cycle: bool
): pointer {.
  importc: "SDL_MapGPUTransferBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc unmapGPUTransferBuffer*(device: ptr GPUDevice; transferBuffer: ptr GPUTransferBuffer) {.
  importc: "SDL_UnmapGPUTransferBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc beginGPUCopyPass*(commandBuffer: ptr GPUCommandBuffer): ptr GPUCopyPass {.
  importc: "SDL_BeginGPUCopyPass",
  header: "<SDL3/SDL_gpu.h>"
.}

proc uploadToGPUTexture*(
  copyPass: ptr GPUCopyPass,
  source: ptr GPUTextureTransferInfo,
  destination: ptr GPUTextureRegion,
  cycle: bool
) {.
  importc: "SDL_UploadToGPUTexture",
  header: "<SDL3/SDL_gpu.h>"
.}

proc uploadToGPUBuffer*(
  copyPass: ptr GPUCopyPass,
  source: ptr GPUTransferBufferLocation,
  destination: ptr GPUBufferRegion,
  cycle: bool
) {.
  importc: "SDL_UploadToGPUBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc endGPUCopyPass*(copyPass: ptr GPUCopyPass) {.
  importc: "SDL_EndGPUCopyPass",
  header: "<SDL3/SDL_gpu.h>"
.}

proc waitAndAcquireGPUSwapchainTexture*(
  commandBuffer: ptr GPUCommandBuffer,
  window: ptr Window,
  swapchainTexture: ptr ptr GPUTexture,
  swapchainTextureWidth: ptr uint32,
  swapchainTextureHeight: ptr uint32
): bool {.
  importc: "SDL_WaitAndAcquireGPUSwapchainTexture",
  header: "<SDL3/SDL_gpu.h>"
.}

proc submitGPUCommandBuffer*(commandBuffer: ptr GPUCommandBuffer): bool {.
  importc: "SDL_SubmitGPUCommandBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc cancelGPUCommandBuffer*(commandBuffer: ptr GPUCommandBuffer): bool {.
  importc: "SDL_CancelGPUCommandBuffer",
  header: "<SDL3/SDL_gpu.h>"
.}

proc waitForGPUIdle*(device: ptr GPUDevice): bool {.
  importc: "SDL_WaitForGPUIdle",
  header: "<SDL3/SDL_gpu.h>"
.}
