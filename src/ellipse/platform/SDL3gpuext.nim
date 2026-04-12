import std/[strformat]
import ./SDL3
import ./SDL3ext
import ./SDL3gpu

type
  Error* = object of CatchableError

  NoMeta = object

  GPUDeviceResource* = object
  GPUWindowClaimResource* = object
  GPUBufferResource* = object
  GPUTransferBufferResource* = object
  GPUTextureResource* = object
  GPUSamplerResource* = object
  GPUShaderResource* = object
  GPUGraphicsPipelineResource* = object

  Handle*[Resource, RawHandle, Meta = NoMeta] = object
    handle: RawHandle
    meta: Meta

  GPUDeviceHandle* = Handle[GPUDeviceResource, ptr GPUDevice]
  GPUWindowClaimHandle* = Handle[GPUWindowClaimResource, ptr Window, ptr GPUDevice]
  GPUBufferHandle* = Handle[GPUBufferResource, ptr GPUBuffer, ptr GPUDevice]
  GPUTransferBufferHandle* = Handle[GPUTransferBufferResource, ptr GPUTransferBuffer, ptr GPUDevice]
  GPUTextureHandle* = Handle[GPUTextureResource, ptr GPUTexture, ptr GPUDevice]
  GPUSamplerHandle* = Handle[GPUSamplerResource, ptr GPUSampler, ptr GPUDevice]
  GPUShaderHandle* = Handle[GPUShaderResource, ptr GPUShader, ptr GPUDevice]
  GPUGraphicsPipelineHandle* = Handle[GPUGraphicsPipelineResource, ptr GPUGraphicsPipeline, ptr GPUDevice]

template failure(prefix: string): untyped =
  raise newException(Error, prefix & ": " & $getError())

proc isValid(_: typedesc[GPUDeviceResource]; handle: ptr GPUDevice; meta: NoMeta): bool =
  discard meta
  not handle.isNil

proc isValid(_: typedesc[GPUWindowClaimResource]; handle: ptr Window; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc isValid(_: typedesc[GPUBufferResource]; handle: ptr GPUBuffer; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc isValid(_: typedesc[GPUTransferBufferResource]; handle: ptr GPUTransferBuffer; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc isValid(_: typedesc[GPUTextureResource]; handle: ptr GPUTexture; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc isValid(_: typedesc[GPUSamplerResource]; handle: ptr GPUSampler; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc isValid(_: typedesc[GPUShaderResource]; handle: ptr GPUShader; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc isValid(_: typedesc[GPUGraphicsPipelineResource]; handle: ptr GPUGraphicsPipeline; meta: ptr GPUDevice): bool =
  not handle.isNil and not meta.isNil

proc release(_: typedesc[GPUDeviceResource]; handle: ptr GPUDevice; meta: var NoMeta) =
  discard meta
  destroyGPUDevice(handle)

proc release(_: typedesc[GPUWindowClaimResource]; handle: ptr Window; meta: var ptr GPUDevice) =
  releaseWindowFromGPUDevice(meta, handle)
  meta = nil

proc release(_: typedesc[GPUBufferResource]; handle: ptr GPUBuffer; meta: var ptr GPUDevice) =
  releaseGPUBuffer(meta, handle)
  meta = nil

proc release(_: typedesc[GPUTransferBufferResource]; handle: ptr GPUTransferBuffer; meta: var ptr GPUDevice) =
  releaseGPUTransferBuffer(meta, handle)
  meta = nil

proc release(_: typedesc[GPUTextureResource]; handle: ptr GPUTexture; meta: var ptr GPUDevice) =
  releaseGPUTexture(meta, handle)
  meta = nil

proc release(_: typedesc[GPUSamplerResource]; handle: ptr GPUSampler; meta: var ptr GPUDevice) =
  releaseGPUSampler(meta, handle)
  meta = nil

proc release(_: typedesc[GPUShaderResource]; handle: ptr GPUShader; meta: var ptr GPUDevice) =
  releaseGPUShader(meta, handle)
  meta = nil

proc release(_: typedesc[GPUGraphicsPipelineResource]; handle: ptr GPUGraphicsPipeline; meta: var ptr GPUDevice) =
  releaseGPUGraphicsPipeline(meta, handle)
  meta = nil

proc `=copy`*[Resource, RawHandle, Meta](dest: var Handle[Resource, RawHandle, Meta]; src: Handle[Resource, RawHandle, Meta]) {.error.}

proc `=destroy`*[Resource, RawHandle, Meta](value: var Handle[Resource, RawHandle, Meta]) =
  if isValid(Resource, value.handle, value.meta):
    release(Resource, value.handle, value.meta)
    value.handle = default(RawHandle)
    value.meta = default(Meta)

proc raw*[Resource, RawHandle, Meta](value: Handle[Resource, RawHandle, Meta]): RawHandle =
  value.handle

proc device*[Resource, RawHandle](value: Handle[Resource, RawHandle, ptr GPUDevice]): ptr GPUDevice =
  value.meta

proc createGPUDevice*(
  formatFlags: GPUShaderFormat,
  debugMode: bool = true,
  name: cstring = nil
): GPUDeviceHandle =
  result.handle = SDL3gpu.createGPUDevice(formatFlags, debugMode, name)
  if result.handle.isNil:
    failure("createGPUDevice failed")

proc claimWindowForGPUDevice*(device: ptr GPUDevice; window: ptr Window): GPUWindowClaimHandle =
  if not SDL3gpu.claimWindowForGPUDevice(device, window):
    failure("claimWindowForGPUDevice failed")
  result.handle = window
  result.meta = device

proc claimWindowForGPUDevice*(device: GPUDeviceHandle; window: ptr Window): GPUWindowClaimHandle =
  claimWindowForGPUDevice(raw(device), window)

proc claimWindowForGPUDevice*(device: GPUDeviceHandle; window: WindowHandle): GPUWindowClaimHandle =
  claimWindowForGPUDevice(raw(device), raw(window))

proc getGPUSwapchainTextureFormat*(device: GPUDeviceHandle; window: ptr Window): GPUTextureFormat =
  SDL3gpu.getGPUSwapchainTextureFormat(raw(device), window)

proc getGPUSwapchainTextureFormat*(device: GPUDeviceHandle; window: WindowHandle): GPUTextureFormat =
  getGPUSwapchainTextureFormat(device, raw(window))

proc getGPUSwapchainTextureFormat*(claim: GPUWindowClaimHandle): GPUTextureFormat =
  SDL3gpu.getGPUSwapchainTextureFormat(claim.meta, claim.handle)

proc createGPUShader*(device: ptr GPUDevice; createInfo: GPUShaderCreateInfo): GPUShaderHandle =
  var mutableCreateInfo = createInfo
  result.handle = SDL3gpu.createGPUShader(device, addr mutableCreateInfo)
  if result.handle.isNil:
    failure("createGPUShader failed")
  result.meta = device

proc createGPUShader*(device: GPUDeviceHandle; createInfo: GPUShaderCreateInfo): GPUShaderHandle =
  createGPUShader(raw(device), createInfo)

proc createGPUTexture*(device: ptr GPUDevice; createInfo: GPUTextureCreateInfo): GPUTextureHandle =
  var mutableCreateInfo = createInfo
  result.handle = SDL3gpu.createGPUTexture(device, addr mutableCreateInfo)
  if result.handle.isNil:
    failure("createGPUTexture failed")
  result.meta = device

proc createGPUTexture*(device: GPUDeviceHandle; createInfo: GPUTextureCreateInfo): GPUTextureHandle =
  createGPUTexture(raw(device), createInfo)

proc createGPUBuffer*(device: ptr GPUDevice; createInfo: GPUBufferCreateInfo): GPUBufferHandle =
  var mutableCreateInfo = createInfo
  result.handle = SDL3gpu.createGPUBuffer(device, addr mutableCreateInfo)
  if result.handle.isNil:
    failure("createGPUBuffer failed")
  result.meta = device

proc createGPUBuffer*(device: GPUDeviceHandle; createInfo: GPUBufferCreateInfo): GPUBufferHandle =
  createGPUBuffer(raw(device), createInfo)

proc createGPUTransferBuffer*(device: ptr GPUDevice; createInfo: GPUTransferBufferCreateInfo): GPUTransferBufferHandle =
  var mutableCreateInfo = createInfo
  result.handle = SDL3gpu.createGPUTransferBuffer(device, addr mutableCreateInfo)
  if result.handle.isNil:
    failure("createGPUTransferBuffer failed")
  result.meta = device

proc createGPUTransferBuffer*(device: GPUDeviceHandle; createInfo: GPUTransferBufferCreateInfo): GPUTransferBufferHandle =
  createGPUTransferBuffer(raw(device), createInfo)

proc createGPUSampler*(device: ptr GPUDevice; createInfo: GPUSamplerCreateInfo): GPUSamplerHandle =
  var mutableCreateInfo = createInfo
  result.handle = SDL3gpu.createGPUSampler(device, addr mutableCreateInfo)
  if result.handle.isNil:
    failure("createGPUSampler failed")
  result.meta = device

proc createGPUSampler*(device: GPUDeviceHandle; createInfo: GPUSamplerCreateInfo): GPUSamplerHandle =
  createGPUSampler(raw(device), createInfo)

proc createGPUGraphicsPipeline*(device: ptr GPUDevice; createInfo: GPUGraphicsPipelineCreateInfo): GPUGraphicsPipelineHandle =
  var mutableCreateInfo = createInfo
  result.handle = SDL3gpu.createGPUGraphicsPipeline(device, addr mutableCreateInfo)
  if result.handle.isNil:
    failure("createGPUGraphicsPipeline failed")
  result.meta = device

proc createGPUGraphicsPipeline*(device: GPUDeviceHandle; createInfo: GPUGraphicsPipelineCreateInfo): GPUGraphicsPipelineHandle =
  createGPUGraphicsPipeline(raw(device), createInfo)

proc acquireGPUCommandBuffer*(device: GPUDeviceHandle): ptr GPUCommandBuffer =
  result = SDL3gpu.acquireGPUCommandBuffer(raw(device))
  if result.isNil:
    failure("acquireGPUCommandBuffer failed")

proc waitForGPUIdle*(device: GPUDeviceHandle) =
  if not SDL3gpu.waitForGPUIdle(raw(device)):
    failure("waitForGPUIdle failed")

proc mapGPUTransferBuffer*(
  device: GPUDeviceHandle,
  transferBuffer: GPUTransferBufferHandle,
  cycle: bool = false
): pointer =
  result = SDL3gpu.mapGPUTransferBuffer(raw(device), raw(transferBuffer), cycle)
  if result.isNil:
    failure("mapGPUTransferBuffer failed")

proc unmapGPUTransferBuffer*(device: GPUDeviceHandle; transferBuffer: GPUTransferBufferHandle) =
  SDL3gpu.unmapGPUTransferBuffer(raw(device), raw(transferBuffer))
