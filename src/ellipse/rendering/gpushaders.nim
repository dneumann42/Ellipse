import std/[os, strformat]
import ../platform/SDL3gpu
import ../platform/SDL3gpuext

type
  ShaderLoadError* = object of CatchableError

# This module handles the reusable part of shader setup: reading compiled
# binaries and creating owned SDL_gpu shader handles from them.

proc loadShaderCode*(path: string): string =
  ## Reads a compiled shader binary from disk.
  ## Extend here if you want search paths, caching, hot reload, or driver-based
  ## backend selection between SPIR-V, MSL, DXIL, and other formats.
  if not fileExists(path):
    raise newException(
      ShaderLoadError,
      &"Missing shader binary '{path}'. Run `nimble build_gpu_shaders` first."
    )
  readFile(path)

proc createShaderFromFile*(
  device: GPUDeviceHandle,
  path: string,
  stage: GPUShaderStage,
  numSamplers: uint32,
  numUniformBuffers: uint32 = 0,
  entrypoint: cstring = "main",
  format: GPUShaderFormat = GPU_SHADERFORMAT_SPIRV
): GPUShaderHandle =
  ## Loads one compiled shader file and turns it into an owned GPU shader.
  ## Extend here if you later want automatic resource counts from shader
  ## reflection instead of passing sampler/uniform counts manually.
  let code = loadShaderCode(path)
  let createInfo = GPUShaderCreateInfo(
    code_size: csize_t(code.len),
    code: cast[ptr uint8](unsafeAddr code[0]),
    entrypoint: entrypoint,
    format: format,
    stage: stage,
    num_samplers: numSamplers,
    num_storage_textures: 0,
    num_storage_buffers: 0,
    num_uniform_buffers: numUniformBuffers,
    props: 0
  )

  try:
    result = createGPUShader(device, createInfo)
  except SDL3gpuext.Error as err:
    raise newException(ShaderLoadError, &"createGPUShader failed for '{path}': " & err.msg)
