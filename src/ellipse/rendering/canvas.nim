## Lightweight render surfaces. Fixed canvases render at a permanent logical
## resolution and are letterboxed when presented.

import std/os

import sdl3

proc imgSavePng(surface: ptr Surface, file: cstring): bool {.
  importc: "IMG_SavePNG", cdecl, dynlib: "libSDL3_image.so"
.}

proc dumpRendererScreenshot*(renderer: Renderer,
    path: string): bool {.discardable.} =
  ## Save the renderer's current output as a PNG image.
  if renderer == nil or path.len == 0:
    return false
  createDir(path.parentDir)
  let surface = renderReadPixels(renderer, nil)
  if surface == nil:
    debugEcho "Failed to read renderer pixels for screenshot: ", $sdl3.getError()
    return false
  defer:
    destroySurface(surface)
  result = imgSavePng(surface, cstring(path))
  if not result:
    debugEcho "Failed to save screenshot ", path, ": ", $sdl3.getError()

type
  CanvasSize* = enum
    Fixed, Window

  CanvasFilter* = enum
    Nearest, Linear

  Canvas* = object
    sizeMode*: CanvasSize
    filter: CanvasFilter
    width*, height*: int
    renderWidth*, renderHeight*: int
    texture: Texture
    resizeChangedAt: uint64

const ResizeSettleMs = 120'u64

var canvasRenderer: Renderer

proc installCanvasRenderer*(renderer: Renderer) =
  canvasRenderer = renderer

proc initCanvas*(width, height: int, filter = Linear): Canvas =
  ## Creates a fixed-resolution canvas. GPU storage is allocated lazily, after
  ## the application renderer exists, so client applications never handle SDL.
  result.sizeMode = Fixed
  result.filter = filter
  result.width = max(width, 1)
  result.height = max(height, 1)
  result.renderWidth = result.width
  result.renderHeight = result.height

proc initWindowCanvas*(): Canvas =
  Canvas(sizeMode: Window, filter: Linear)

proc filterMode*(canvas: Canvas): CanvasFilter = canvas.filter

proc `filterMode=`*(canvas: var Canvas, filter: CanvasFilter) =
  canvas.filter = filter
  if canvas.texture != nil:
    discard setTextureScaleMode(canvas.texture, if filter == Nearest:
      SCALEMODE_NEAREST else: SCALEMODE_LINEAR)

proc destroy*(canvas: var Canvas) =
  if canvas.texture != nil:
    destroyTexture(canvas.texture)
    canvas.texture = nil

proc ensureTexture(canvas: var Canvas) =
  if canvas.sizeMode != Fixed or canvas.texture != nil or canvasRenderer == nil:
    return
  canvas.texture = createTexture(canvasRenderer, PIXELFORMAT_RGBA32,
    TEXTUREACCESS_TARGET, canvas.width.cint, canvas.height.cint)
  if canvas.texture != nil:
    discard setTextureBlendMode(canvas.texture, BLENDMODE_BLEND)
    canvas.filterMode = canvas.filter

proc syncSize*(canvas: var Canvas) =
  if canvas.sizeMode != Window:
    return
  var width, height: cint
  if canvasRenderer == nil or not getRenderOutputSize(canvasRenderer, width, height) or width <= 0 or height <= 0:
    return
  let newWidth = width.int
  let newHeight = height.int
  if canvas.width != newWidth or canvas.height != newHeight:
    canvas.width = newWidth
    canvas.height = newHeight
    canvas.resizeChangedAt = getTicks()
  # Preserve the old 3D target during a live resize, then rebuild once settled.
  if canvas.renderWidth == 0 or canvas.renderHeight == 0 or
      getTicks() - canvas.resizeChangedAt >= ResizeSettleMs:
    canvas.renderWidth = canvas.width
    canvas.renderHeight = canvas.height

proc begin*(canvas: var Canvas,
    r = 0'u8, g = 0'u8, b = 0'u8, a = 255'u8) =
  canvas.syncSize()
  canvas.ensureTexture()
  if canvasRenderer == nil:
    return
  discard setRenderTarget(canvasRenderer, canvas.texture)
  if canvas.sizeMode == Fixed:
    discard setRenderDrawColor(canvasRenderer, r, g, b, a)
    discard renderClear(canvasRenderer)

proc letterboxRect(canvas: Canvas): FRect =
  var outputWidth, outputHeight: cint
  if canvasRenderer == nil or not getRenderOutputSize(canvasRenderer, outputWidth, outputHeight) or
      outputWidth <= 0 or outputHeight <= 0 or canvas.width <= 0 or canvas.height <= 0:
    return
  let scale = min(outputWidth.float32 / canvas.width.float32,
      outputHeight.float32 / canvas.height.float32)
  result.w = canvas.width.float32 * scale
  result.h = canvas.height.float32 * scale
  result.x = (outputWidth.float32 - result.w) * 0.5'f32
  result.y = (outputHeight.float32 - result.h) * 0.5'f32

proc finish*(canvas: var Canvas) =
  if canvas.sizeMode != Fixed or canvas.texture == nil or canvasRenderer == nil:
    return
  discard setRenderTarget(canvasRenderer, nil)
  var destination = canvas.letterboxRect()
  discard renderTexture(canvasRenderer, canvas.texture, nil, addr destination)

proc mapWindowPoint*(canvas: Canvas, x, y: cfloat): tuple[x, y: cfloat] =
  if canvas.sizeMode != Fixed:
    return (x, y)
  let rect = canvas.letterboxRect()
  if rect.w <= 0 or rect.h <= 0:
    return (x, y)
  ((x - rect.x) * canvas.width.cfloat / rect.w,
    (y - rect.y) * canvas.height.cfloat / rect.h)
