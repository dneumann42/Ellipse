import std/math

import ../platform/SDL3gpu
import ../platform/SDL3gpuext
import ./artist2D

type
  CanvasError* = object of CatchableError

  RenderCanvasId* = string

  CanvasScaleMode* = enum
    csmContain,
    csmStretch,
    csmInteger

  RenderCanvasConfig* = object
    id*: RenderCanvasId
    width*: int
    height*: int
    destRect*: Rect
    scaleMode*: CanvasScaleMode
    filterMode*: TextureFilterMode
    layer*: int
    clearColor*: FColor

  CanvasCompositeRect* = object
    x*, y*, w*, h*: cfloat

  RenderCanvas = ref object
    config: RenderCanvasConfig
    texture: GPUTextureHandle
    artist: Artist2D

  CanvasManager* = object
    device: GPUDeviceHandle
    artistConfig: Artist2DConfig
    canvases: seq[RenderCanvas]
    sortedIndices: seq[int]
    activeCanvasIndex: int

const
  canvasTextureFormat = GPU_TEXTUREFORMAT_R8G8B8A8_UNORM

proc resolveCanvasTargetRect*(
  config: RenderCanvasConfig;
  targetWidth: uint32;
  targetHeight: uint32
): Rect =
  if config.destRect.w > 0 and config.destRect.h > 0:
    return config.destRect
  Rect(x: 0, y: 0, w: cint(max(targetWidth, 1'u32)), h: cint(max(targetHeight, 1'u32)))

proc initCanvasManager*(
  device: GPUDeviceHandle,
  artistConfig: Artist2DConfig
): CanvasManager =
  result.device = device
  result.artistConfig = artistConfig
  result.activeCanvasIndex = -1

proc validateRenderCanvasConfig*(config: RenderCanvasConfig) =
  if config.id.len <= 0:
    raise newException(CanvasError, "Canvas id must not be empty")
  if config.width <= 0 or config.height <= 0:
    raise newException(CanvasError, "Canvas dimensions must be positive")
  if config.destRect.w < 0 or config.destRect.h < 0:
    raise newException(CanvasError, "Canvas destination rect must be positive")

proc hasCanvas*(manager: CanvasManager; id: string): bool =
  for canvas in manager.canvases:
    if canvas.config.id == id:
      return true

proc requireCanvasIndex(manager: CanvasManager; id: string): int =
  for i, canvas in manager.canvases:
    if canvas.config.id == id:
      return i
  raise newException(CanvasError, "Unknown canvas id: " & id)

proc canvasConfig*(manager: CanvasManager; id: string): RenderCanvasConfig =
  manager.canvases[manager.requireCanvasIndex(id)].config

proc setCanvasScaleMode*(
  manager: var CanvasManager;
  id: string;
  scaleMode: CanvasScaleMode
) =
  let index = manager.requireCanvasIndex(id)
  manager.canvases[index].config.scaleMode = scaleMode

proc setCanvasFilterMode*(
  manager: var CanvasManager;
  id: string;
  filterMode: TextureFilterMode
) =
  let index = manager.requireCanvasIndex(id)
  manager.canvases[index].config.filterMode = filterMode

proc sortedCanvasIndicesByLayer*(configs: openArray[RenderCanvasConfig]): seq[int] =
  result = newSeq[int](configs.len)
  for i in 0 ..< configs.len:
    result[i] = i

  for i in 1 ..< result.len:
    let current = result[i]
    let currentLayer = configs[current].layer
    var j = i
    while j > 0 and configs[result[j - 1]].layer > currentLayer:
      result[j] = result[j - 1]
      dec j
    result[j] = current

proc canvasCompositeRect*(
  config: RenderCanvasConfig;
  targetWidth: uint32;
  targetHeight: uint32
): CanvasCompositeRect =
  let targetRect = config.resolveCanvasTargetRect(targetWidth, targetHeight)
  let destW = max(targetRect.w, 1).cfloat
  let destH = max(targetRect.h, 1).cfloat
  let sourceW = max(config.width, 1).cfloat
  let sourceH = max(config.height, 1).cfloat

  case config.scaleMode
  of csmStretch:
    result = CanvasCompositeRect(
      x: targetRect.x.cfloat,
      y: targetRect.y.cfloat,
      w: destW,
      h: destH
    )
  of csmContain, csmInteger:
    let containScale = min(destW / sourceW, destH / sourceH)
    let resolvedScale =
      if config.scaleMode == csmContain or containScale < 1'f32:
        containScale
      else:
        max(1'f32, floor(containScale))

    let scaledW = sourceW * resolvedScale
    let scaledH = sourceH * resolvedScale
    result = CanvasCompositeRect(
      x: targetRect.x.cfloat + (destW - scaledW) * 0.5'f32,
      y: targetRect.y.cfloat + (destH - scaledH) * 0.5'f32,
      w: scaledW,
      h: scaledH
    )

proc registerCanvas*(manager: var CanvasManager; config: RenderCanvasConfig) =
  config.validateRenderCanvasConfig()
  if manager.hasCanvas(config.id):
    raise newException(CanvasError, "Duplicate canvas id: " & config.id)

  var canvas: RenderCanvas
  new(canvas)
  canvas.config = config
  canvas.texture = createRenderTargetTexture(manager.device, config.width, config.height)
  canvas.artist = initArtist2D(manager.device, canvasTextureFormat, manager.artistConfig)
  manager.canvases.add(canvas)

proc beginFrame*(manager: var CanvasManager) =
  manager.activeCanvasIndex = -1
  for canvas in manager.canvases.mitems:
    beginFrame(canvas.artist)

proc clearCanvases*(manager: var CanvasManager; commandBuffer: ptr GPUCommandBuffer) =
  for canvas in manager.canvases.mitems:
    render(
      canvas.artist,
      commandBuffer,
      raw(canvas.texture),
      uint32(canvas.config.width),
      uint32(canvas.config.height),
      canvas.config.clearColor,
      renderTargetClear
    )

proc sortForRendering*(manager: var CanvasManager) =
  var configs = newSeqOfCap[RenderCanvasConfig](manager.canvases.len)
  for canvas in manager.canvases:
    configs.add(canvas.config)
  manager.sortedIndices = sortedCanvasIndicesByLayer(configs)

proc renderCanvases*(manager: var CanvasManager; commandBuffer: ptr GPUCommandBuffer) =
  for index in manager.sortedIndices:
    let canvas = manager.canvases[index]
    render(
      canvas.artist,
      commandBuffer,
      raw(canvas.texture),
      uint32(canvas.config.width),
      uint32(canvas.config.height),
      canvas.config.clearColor,
      renderTargetLoad
    )

proc composeCanvases*(
  manager: CanvasManager;
  artist: var Artist2D;
  targetWidth: uint32;
  targetHeight: uint32
) =
  for index in manager.sortedIndices:
    let canvas = manager.canvases[index]
    let rect = canvas.config.canvasCompositeRect(targetWidth, targetHeight)
    var sprite = initSprite2D()
    sprite.position = [rect.x, rect.y]
    sprite.size = [rect.w, rect.h]
    sprite.origin = [0'f32, 0'f32]
    sprite.texture = raw(canvas.texture)
    sprite.filterMode = canvas.config.filterMode
    sprite.hasFilterOverride = true
    discard drawSprite(artist, sprite)

proc currentArtistPtr*(
  manager: var CanvasManager;
  defaultArtist: ptr Artist2D
): ptr Artist2D =
  if manager.activeCanvasIndex < 0:
    return defaultArtist
  addr manager.canvases[manager.activeCanvasIndex].artist

template withCanvas*(
  manager: var CanvasManager;
  defaultArtist: var Artist2D;
  id: string;
  body: untyped
) =
  block:
    bind requireCanvasIndex
    bind currentArtistPtr
    let previousCanvasIndex = manager.activeCanvasIndex
    manager.activeCanvasIndex = manager.requireCanvasIndex(id)
    template artist: untyped {.inject, used.} =
      currentArtistPtr(manager, addr defaultArtist)[]
    try:
      body
    finally:
      manager.activeCanvasIndex = previousCanvasIndex
