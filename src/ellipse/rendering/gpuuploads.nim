import ../platform/SDL3
import ../platform/SDL3gpu
import ../platform/SDL3gpuext

type
  UploadError* = object of CatchableError

# This module contains the reusable staging/upload flow used by SDL_gpu:
# create a transfer buffer, copy CPU data into it, submit a copy pass, and
# wait until the resulting GPU resource is ready for rendering.

proc require(condition: bool; message: string) =
  if not condition:
    raise newException(UploadError, message & ": " & $getError())

proc uploadBufferData*(
  device: GPUDeviceHandle,
  target: GPUBufferHandle,
  data: pointer,
  size: int,
  label: string = "buffer upload"
) =
  ## Uploads CPU-side bytes into a GPU buffer using a temporary transfer buffer.
  ## Extend here if you want transfer-buffer pooling or frequent dynamic buffer
  ## streaming without allocating a fresh staging buffer per upload.
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
    raise newException(UploadError, "beginGPUCopyPass failed for " & label & ": " & $getError())

  var source = GPUTransferBufferLocation(transfer_buffer: raw(transferBuffer), offset: 0)
  var destination = GPUBufferRegion(buffer: raw(target), offset: 0, size: uint32(size))
  uploadToGPUBuffer(copyPass, addr source, addr destination, false)
  endGPUCopyPass(copyPass)
  require(submitGPUCommandBuffer(commandBuffer), "submitGPUCommandBuffer failed for " & label)
  waitForGPUIdle(device)

proc uploadTexture2DData*(
  device: GPUDeviceHandle,
  texture: GPUTextureHandle,
  width: int,
  height: int,
  pixels: openArray[uint8],
  label: string = "texture upload"
) =
  ## Uploads tightly packed texels into a 2D texture.
  ## Extend here for partial region uploads, mip chains, texture arrays, or
  ## a readback/debug path built on the same transfer-buffer pattern.
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
    raise newException(UploadError, "beginGPUCopyPass failed for " & label & ": " & $getError())

  var source = GPUTextureTransferInfo(
    transfer_buffer: raw(transferBuffer),
    offset: 0,
    pixels_per_row: uint32(width),
    rows_per_layer: uint32(height)
  )
  var destination = GPUTextureRegion(
    texture: raw(texture),
    mip_level: 0,
    layer: 0,
    x: 0,
    y: 0,
    z: 0,
    w: uint32(width),
    h: uint32(height),
    d: 1
  )
  uploadToGPUTexture(copyPass, addr source, addr destination, false)
  endGPUCopyPass(copyPass)
  require(submitGPUCommandBuffer(commandBuffer), "submitGPUCommandBuffer failed for " & label)
  waitForGPUIdle(device)
