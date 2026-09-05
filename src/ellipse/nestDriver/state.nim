## Shared state and frame scheduling for the SDL-backed Nest driver.

import std/[osproc, tables]
import sdl3, sdl3_ttf, plugnim
import nest except Event, update, draw
import nest/screen
import ../rendering/canvas

type
  NestFontSlot* = object
    font*: sdl3_ttf.Font
    metrics*: screen.FontMetrics

  NestImageSlot* = object
    texture*: Texture
    path*: string
    width*, height*: int
    externalID*: string

  NestExternalTexture* = object
    texture*: Texture
    width*, height*: int

  NestTextSlot* = object
    texture*: Texture
    extent*: screen.TextExtent

  NestClipState* = object
    enabled*: bool
    rect*: sdl3.Rect

  NestDynamicText* = object
    text*: string
    fontName*: string
    fg*: screen.Color
    bg*: screen.Color
var
  nestRenderer*: Renderer
  nestWindow*: Window
  nestFonts*: seq[NestFontSlot]
  nestImages*: seq[NestImageSlot]
  nestImageByPath*: Table[string, screen.Image]
  nestExternalTextures*: Table[string, NestExternalTexture]
  nestTextByKey*: Table[string, NestTextSlot]
  nestPickedFiles*: Table[WidgetID, string]
  nestFilePickerErrors*: Table[WidgetID, string]
  nestFallbackFilePickers*: Table[WidgetID, osproc.Process]
  nestCachedDrawCommands*: seq[screen.DrawCommand]
  nestCachedTexture*: Texture
  nestCachedTextureWidth*: int
  nestCachedTextureHeight*: int
  nestClipStack*: seq[NestClipState]
  nestCurrentClip*: NestClipState
  nestDynamicTexts*: Table[WidgetID, NestDynamicText]
  hasApplicationRedraw*: bool
  applicationRedrawCounter*: uint64
  nestEveryFrameRequested*: bool
  nestCanvas*: ptr Canvas
proc countersForMilliseconds(milliseconds: int): uint64 =
  let frequency = getPerformanceFrequency()
  max(uint64(max(milliseconds, 0).float64 / 1000.0 * frequency.float64), 1'u64)

proc clearNestTextureCache*() =
  if nestCachedTexture != nil:
    destroyTexture(nestCachedTexture)
    nestCachedTexture = nil
  nestCachedTextureWidth = 0
  nestCachedTextureHeight = 0

proc clearNestUi*(ui: var UI) =
  ## Discard the current widget tree and both forms of cached UI rendering.
  ## Scene transitions use this when the next scene has no UI of its own.
  ui.reset()
  ui.markAllDirty()
  ui.requestRedrawAfter(0)
  nestCachedDrawCommands.setLen(0)
  clearNestTextureCache()

proc setNestCanvas*(canvas: var Canvas) =
  nestCanvas = addr canvas

proc setNestExternalTexture*(id: string, texture: Texture, width, height: int) =
  ## Makes a renderer-owned texture available to Nest's normal image widget.
  ## The caller retains ownership; this registry never destroys the texture.
  if id.len == 0: return
  if texture == nil or width <= 0 or height <= 0:
    nestExternalTextures.del(id)
  else:
    nestExternalTextures[id] = NestExternalTexture(texture: texture,
      width: width, height: height)

proc prepareNestCanvas*(ui: var UI) =
  if nestCanvas == nil:
    return
  nestCanvas[].begin(0, 0, 0, 0)
  if ui.windowWidth != nestCanvas[].width or ui.windowHeight != nestCanvas[].height:
    ui.resizeWindow(nestCanvas[].width, nestCanvas[].height)
    ui.markAllDirty()
    clearNestTextureCache()

proc finishNestCanvas*() =
  if nestCanvas != nil:
    nestCanvas[].finish()

proc nestEventPoint*(x, y: cfloat): tuple[x, y: cfloat] =
  if nestCanvas == nil:
    return (x, y)
  nestCanvas[].mapWindowPoint(x, y)

proc requestFrameAfter*(ms: int) =
  let
    frequency = getPerformanceFrequency()
    delayCounters = countersForMilliseconds(ms)
    counter = getPerformanceCounter() + delayCounters
  if not hasApplicationRedraw or counter < applicationRedrawCounter:
    applicationRedrawCounter = counter
  hasApplicationRedraw = true

proc setNestDynamicText*(
    id: WidgetID,
    text: string,
    fontName = "font",
    fg = screen.color(0, 0, 0, 0),
    bg = screen.color(0, 0, 0, 0),
) =
  if id == InvalidWidgetID or text.len == 0:
    nestDynamicTexts.del(id)
    return
  nestDynamicTexts[id] = NestDynamicText(text: text, fontName: fontName, fg: fg, bg: bg)

proc clearNestDynamicText*(id: WidgetID) =
  nestDynamicTexts.del(id)

proc pluginSetNestDynamicText(id: uint64, text: cstring) {.cdecl.} =
  if text.isNil or ($text).len == 0:
    nestDynamicTexts.del(WidgetID(id))
    return
  nestDynamicTexts[WidgetID(id)] = NestDynamicText(text: $text,
      fontName: "font")

proc requestFrame*() =
  requestFrameAfter(0)

proc requestNestEveryFrame*() =
  nestEveryFrameRequested = true
  requestFrameAfter(0)

proc stopNestEveryFrame*() =
  nestEveryFrameRequested = false
proc installNestPluginCallbacks*() =
  plugnimSetWidgetTextCallback = pluginSetNestDynamicText

proc consumeNestEveryFrameRequest*(): bool =
  result = nestEveryFrameRequested
  nestEveryFrameRequested = false

proc consumeApplicationRedraw*(counter: uint64): bool =
  result = hasApplicationRedraw and applicationRedrawCounter <= counter
  if result:
    hasApplicationRedraw = false

proc hasCachedNestFrame*(): bool =
  nestCachedDrawCommands.len > 0
proc releaseNestDriver*() =
  for process in nestFallbackFilePickers.mvalues:
    if process.running:
      process.terminate()
    process.close()
  nestFallbackFilePickers.clear()
  for slot in nestTextByKey.mvalues:
    if slot.texture != nil:
      destroyTexture(slot.texture)
      slot.texture = nil
  nestTextByKey.clear()
  for slot in nestImages.mitems:
    if slot.texture != nil and slot.externalID.len == 0:
      destroyTexture(slot.texture)
      slot.texture = nil
  nestImages.setLen(0)
  nestImageByPath.clear()
  nestExternalTextures.clear()
  if nestCachedTexture != nil:
    destroyTexture(nestCachedTexture)
    nestCachedTexture = nil
  nestCachedTextureWidth = 0
  nestCachedTextureHeight = 0
  for slot in nestFonts.mitems:
    if slot.font != nil:
      sdl3_ttf.closeFont(slot.font)
      slot.font = nil
  nestFonts.setLen(0)
  nestPickedFiles.clear()
  nestFilePickerErrors.clear()
  nestCachedDrawCommands.setLen(0)
  nestClipStack.setLen(0)
  nestCurrentClip = NestClipState()
  nestDynamicTexts.clear()
  nestCanvas = nil
  nestRenderer = nil
  nestWindow = nil

