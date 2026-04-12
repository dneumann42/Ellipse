import ../platform/SDL3gpu
import ../platform/SDL3gpuext

# This module builds a baseline textured graphics pipeline for apps that render
# sampled geometry into the window swapchain.

proc createColorTargetDescription(
  swapchainFormat: GPUTextureFormat,
  enableBlend: bool
): GPUColorTargetDescription =
  result = GPUColorTargetDescription(
    format: swapchainFormat,
    blend_state: GPUColorTargetBlendState(
      src_color_blendfactor: gpuBlendFactorSrcAlpha.cint,
      dst_color_blendfactor: gpuBlendFactorOneMinusSrcAlpha.cint,
      color_blend_op: gpuBlendOpAdd.cint,
      src_alpha_blendfactor: gpuBlendFactorOne.cint,
      dst_alpha_blendfactor: gpuBlendFactorOneMinusSrcAlpha.cint,
      alpha_blend_op: gpuBlendOpAdd.cint,
      color_write_mask: GPU_COLORCOMPONENT_R or GPU_COLORCOMPONENT_G or GPU_COLORCOMPONENT_B or GPU_COLORCOMPONENT_A,
      enable_blend: enableBlend,
      enable_color_write_mask: true
    )
  )

proc createTexturedPipeline*(
  device: GPUDeviceHandle,
  swapchainFormat: GPUTextureFormat,
  vertexShader: GPUShaderHandle,
  fragmentShader: GPUShaderHandle,
  vertexBufferDescriptions: ptr GPUVertexBufferDescription,
  numVertexBuffers: uint32,
  vertexAttributes: ptr GPUVertexAttribute,
  numVertexAttributes: uint32
): GPUGraphicsPipelineHandle =
  ## Creates a simple textured pipeline with one color target, no blending, and
  ## no depth buffer.
  ## Extend here for alpha blending, depth/stencil, multiple materials, or
  ## alternate rasterizer/depth modes shared across many applications.
  var colorTarget = createColorTargetDescription(swapchainFormat, false)

  let pipelineInfo = GPUGraphicsPipelineCreateInfo(
    vertex_shader: raw(vertexShader),
    fragment_shader: raw(fragmentShader),
    vertex_input_state: GPUVertexInputState(
      vertex_buffer_descriptions: vertexBufferDescriptions,
      num_vertex_buffers: numVertexBuffers,
      vertex_attributes: vertexAttributes,
      num_vertex_attributes: numVertexAttributes
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

  createGPUGraphicsPipeline(device, pipelineInfo)

proc createAlphaBlendedTexturedPipeline*(
  device: GPUDeviceHandle,
  swapchainFormat: GPUTextureFormat,
  vertexShader: GPUShaderHandle,
  fragmentShader: GPUShaderHandle,
  vertexBufferDescriptions: ptr GPUVertexBufferDescription,
  numVertexBuffers: uint32,
  vertexAttributes: ptr GPUVertexAttribute,
  numVertexAttributes: uint32
): GPUGraphicsPipelineHandle =
  ## Creates a textured pipeline with standard sprite alpha blending.
  var colorTarget = createColorTargetDescription(swapchainFormat, true)

  let pipelineInfo = GPUGraphicsPipelineCreateInfo(
    vertex_shader: raw(vertexShader),
    fragment_shader: raw(fragmentShader),
    vertex_input_state: GPUVertexInputState(
      vertex_buffer_descriptions: vertexBufferDescriptions,
      num_vertex_buffers: numVertexBuffers,
      vertex_attributes: vertexAttributes,
      num_vertex_attributes: numVertexAttributes
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

  createGPUGraphicsPipeline(device, pipelineInfo)
