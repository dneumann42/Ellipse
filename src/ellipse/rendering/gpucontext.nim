import ../platform/SDL3
import ../platform/SDL3gpu
import ../platform/SDL3ext
import ../platform/SDL3gpuext

export SDL3, SDL3ext, SDL3gpuext

type
  GPUWindowConfig* = object
    appId*: string
    title*: string
    width*: int
    height*: int
    windowFlags*: WindowFlags
    shaderFormat*: GPUShaderFormat
    driverName*: cstring
    debugMode*: bool

  GPUWindowContext* = object
    sdl*: AppHandle
    window*: WindowHandle
    device*: GPUDeviceHandle
    claim*: GPUWindowClaimHandle

# This module owns the generic SDL + GPU bootstrap every SDL3 GPU application
# needs: initialize SDL, create a window, create a GPU device, and claim the
# window for swapchain rendering.

proc initGPUWindowContext*(config: GPUWindowConfig): GPUWindowContext =
  ## Creates the owned SDL, window, GPU device, and claimed swapchain context.
  ## Extend here if future applications need different GPU drivers, device
  ## create flags, or shared engine-wide window defaults.
  if not setAppMetadata(
    config.title.cstring,
    "0.0.0",
    config.appId.cstring
  ):
    raise newException(SDL3gpuext.Error, "setAppMetadata failed: " & $getError())

  result.sdl = SDL3ext.init(INIT_VIDEO)
  result.window = SDL3ext.createWindow(
    config.title,
    config.width,
    config.height,
    config.windowFlags
  )
  result.device = SDL3gpuext.createGPUDevice(
    config.shaderFormat,
    config.debugMode,
    config.driverName
  )
  result.claim = SDL3gpuext.claimWindowForGPUDevice(result.device, result.window)
