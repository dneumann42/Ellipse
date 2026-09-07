## SDL rendering backend for Nest fonts, images, clipping, and retained frames.

import std/[os, strutils, tables]
import sdl3, sdl3_ttf
import chroma as chromaColors
import nest except Event, update, draw
import nest/[coords, input, screen]
import nest/fallbackfonts
import ../aseprite
import ../rendering/canvas
import ../sdlLibraries
import state, fileDialogs

const
  MaxNestTextTextures = 2048
  DefaultFontPaths = [
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
  ]

proc imgLoad(file: cstring): ptr Surface {.
  importc: "IMG_Load", cdecl, dynlib: SdlImageLibName
.}
converter toChromaColor*(color: screen.Color): chromaColors.ColorRGBA =
  chromaColors.rgba(color.r, color.g, color.b, color.a)

converter toNestColor*(color: chromaColors.ColorRGBA): screen.Color =
  screen.color(color.r, color.g, color.b, color.a)

proc toSdlColor(color: chromaColors.ColorRGBA): sdl3.Color =
  sdl3.Color(r: color.r, g: color.g, b: color.b, a: color.a)

proc toFRect(r: coords.Rect): FRect =
  FRect(x: r.x.cfloat, y: r.y.cfloat, w: r.w.cfloat, h: r.h.cfloat)

proc setNestRenderDrawColor(color: screen.Color) =
  let rgba: chromaColors.ColorRGBA = color
  discard setRenderDrawColor(nestRenderer, rgba.r, rgba.g, rgba.b, rgba.a)

template withNestBlendMode(body: untyped) =
  var previousBlendMode {.gensym.}: BlendMode
  let hadPreviousBlendMode {.gensym.} =
    getRenderDrawBlendMode(nestRenderer, previousBlendMode)
  discard setRenderDrawBlendMode(nestRenderer, BLENDMODE_BLEND)
  body
  if hadPreviousBlendMode:
    discard setRenderDrawBlendMode(nestRenderer, previousBlendMode)

proc resolveNestFontPath(path: string): string =
  if path.len > 0 and fileExists(path):
    return path
  if path.len > 0:
    let lowerPath = path.toLowerAscii()
    for candidate in DefaultFontPaths:
      if candidate.toLowerAscii().contains(lowerPath) and fileExists(candidate):
        return candidate
  for candidate in DefaultFontPaths:
    if fileExists(candidate):
      return candidate

proc openNestFontIO(
    src: IOStream, closeio: bool, ptsize: cfloat
): sdl3_ttf.Font {.importc: "TTF_OpenFontIO", cdecl,
    dynlib: sdl3_ttf.TtfLibName.}

proc openNestFallbackFont(mono: bool, size: int): sdl3_ttf.Font =
  let bytes = if mono: fallbackMonoFont else: fallbackSansFont
  if bytes.len == 0:
    return nil
  let stream = ioFromConstMem(bytes[0].unsafeAddr, bytes.len.csize_t)
  if stream == nil:
    return nil
  openNestFontIO(stream, true, size.cfloat)

proc nestOpenFont(
    path: string, size: int, metrics: var screen.FontMetrics
): screen.Font {.nimcall.} =
  let resolved = resolveNestFontPath(path)
  let font =
    if resolved.len > 0:
      sdl3_ttf.openFont(cstring(resolved), size.cfloat)
    else:
      openNestFallbackFont(path == "nerd-monospace", size)
  if font == nil:
    return screen.Font(0)
  metrics.ascent = sdl3_ttf.getFontAscent(font)
  metrics.descent = sdl3_ttf.getFontDescent(font)
  metrics.lineHeight = sdl3_ttf.getFontLineSkip(font)
  nestFonts.add NestFontSlot(font: font, metrics: metrics)
  screen.Font(nestFonts.len)

proc nestFontPtr(font: screen.Font): sdl3_ttf.Font =
  let index = font.int - 1
  if index >= 0 and index < nestFonts.len:
    nestFonts[index].font
  else:
    nil

proc nestCloseFont(font: screen.Font) {.nimcall.} =
  let index = font.int - 1
  if index >= 0 and index < nestFonts.len and nestFonts[index].font != nil:
    sdl3_ttf.closeFont(nestFonts[index].font)
    nestFonts[index].font = nil

proc nestFontMetrics(font: screen.Font): screen.FontMetrics {.nimcall.} =
  let index = font.int - 1
  if index >= 0 and index < nestFonts.len:
    nestFonts[index].metrics
  else:
    screen.FontMetrics()

proc nestMeasureText(font: screen.Font, text: string): screen.TextExtent {.nimcall.} =
  let fontPtr = nestFontPtr(font)
  if fontPtr == nil or text.len == 0:
    return screen.TextExtent()
  var width, height: cint
  discard sdl3_ttf.getStringSize(fontPtr, cstring(text), 0, width, height)
  screen.TextExtent(w: width.int, h: height.int)

proc textCacheKey(font: screen.Font, text: string, fg: screen.Color): string =
  $font.int & "|" & $fg.r & "," & $fg.g & "," & $fg.b & "," & $fg.a & "|" & text

proc clearNestTextCache() =
  for slot in nestTextByKey.mvalues:
    if slot.texture != nil:
      destroyTexture(slot.texture)
      slot.texture = nil
  nestTextByKey.clear()

proc ensureNestTextureCache(width, height: int): bool =
  if nestRenderer == nil or width <= 0 or height <= 0:
    clearNestTextureCache()
    return false
  if nestCachedTexture != nil and nestCachedTextureWidth == width and
      nestCachedTextureHeight == height:
    return true
  clearNestTextureCache()
  nestCachedTexture = createTexture(
    nestRenderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_TARGET, width.cint, height.cint
  )
  if nestCachedTexture == nil:
    return false
  discard setTextureBlendMode(nestCachedTexture, BLENDMODE_BLEND)
  nestCachedTextureWidth = width
  nestCachedTextureHeight = height
  true

proc blitNestTextureCache() =
  if nestCachedTexture == nil:
    return
  var dst = FRect(
    x: 0,
    y: 0,
    w: nestCachedTextureWidth.cfloat,
    h: nestCachedTextureHeight.cfloat,
  )
  discard renderTexture(nestRenderer, nestCachedTexture, nil, addr dst)

proc cachedNestText(
    font: screen.Font, text: string, fg: screen.Color
): NestTextSlot =
  let key = textCacheKey(font, text, fg)
  if nestTextByKey.hasKey(key):
    return nestTextByKey[key]
  if nestTextByKey.len >= MaxNestTextTextures:
    clearNestTextCache()

  let fontPtr = nestFontPtr(font)
  if fontPtr == nil or nestRenderer == nil or text.len == 0:
    return
  let fgRgba: chromaColors.ColorRGBA = fg
  let surface = sdl3_ttf.renderTextBlended(fontPtr, cstring(text), 0,
      fgRgba.toSdlColor)
  if surface == nil:
    return
  defer:
    destroySurface(surface)
  let texture = createTextureFromSurface(nestRenderer, surface)
  if texture == nil:
    return
  discard setTextureBlendMode(texture, BLENDMODE_BLEND)
  result = NestTextSlot(texture: texture, extent: nestMeasureText(font, text))
  nestTextByKey[key] = result

proc nestDrawText(
    font: screen.Font, x, y: int, text: string, fg, bg: screen.Color
): screen.TextExtent {.nimcall.} =
  let cached = cachedNestText(font, text, fg)
  if cached.texture == nil:
    return screen.TextExtent()
  result = cached.extent
  if bg.a != 0 and result.w > 0 and result.h > 0:
    var bgRect = FRect(x: x.cfloat, y: y.cfloat, w: result.w.cfloat,
        h: result.h.cfloat)
    setNestRenderDrawColor(bg)
    withNestBlendMode:
      discard renderFillRect(nestRenderer, addr bgRect)
  var dst = FRect(x: x.cfloat, y: y.cfloat, w: result.w.cfloat,
      h: result.h.cfloat)
  discard renderTexture(nestRenderer, cached.texture, nil, addr dst)

proc nestFillRect(r: coords.Rect, color: screen.Color) {.nimcall.} =
  if nestRenderer == nil:
    return
  setNestRenderDrawColor(color)
  var rect = r.toFRect()
  withNestBlendMode:
    discard renderFillRect(nestRenderer, addr rect)

proc nestFillRoundedRect(
    r: coords.Rect, radii: screen.CornerRadii, color: screen.Color
) {.nimcall.} =
  screen.fillRoundedRect(r, radii, color)

proc nestLineRect(r: coords.Rect, color: screen.Color) {.nimcall.} =
  if nestRenderer == nil:
    return
  setNestRenderDrawColor(color)
  var rect = r.toFRect()
  withNestBlendMode:
    discard renderRect(nestRenderer, addr rect)

proc nestLineRoundedRect(
    r: coords.Rect, radii: screen.CornerRadii, color: screen.Color
) {.nimcall.} =
  screen.lineRoundedRect(r, radii, color)

proc nestDrawLine(x1, y1, x2, y2: int, color: screen.Color) {.nimcall.} =
  if nestRenderer == nil:
    return
  setNestRenderDrawColor(color)
  withNestBlendMode:
    discard renderLine(nestRenderer, x1.cfloat, y1.cfloat, x2.cfloat, y2.cfloat)

proc nestDrawPoint(x, y: int, color: screen.Color) {.nimcall.} =
  if nestRenderer == nil:
    return
  setNestRenderDrawColor(color)
  withNestBlendMode:
    discard renderPoint(nestRenderer, x.cfloat, y.cfloat)

proc nestLoadImage(path: string): screen.Image {.nimcall.} =
  if path.len == 0:
    return screen.Image(0)
  if nestRenderer == nil:
    return screen.Image(0)
  if nestImageByPath.hasKey(path):
    return nestImageByPath[path]

  if nestExternalTextures.hasKey(path):
    let external = nestExternalTextures[path]
    nestImages.add NestImageSlot(texture: external.texture, path: path,
      width: external.width, height: external.height, externalID: path)
    result = screen.Image(nestImages.len)
    nestImageByPath[path] = result
    return

  var asepritePixels: seq[uint8]
  let surface =
    if path.splitFile.ext == ".aseprite":
      let sprite = loadAseprite(path)
      asepritePixels = sprite.renderFrameRgba()
      createSurfaceFrom(
        sprite.width.cint,
        sprite.height.cint,
        PIXELFORMAT_RGBA32,
        unsafeAddr asepritePixels[0],
        (sprite.width.int * 4).cint,
      )
    else:
      imgLoad(cstring(path))
  if surface == nil:
    debugEcho "Nest image load failed: ", path
    return screen.Image(0)
  defer:
    destroySurface(surface)

  let texture = createTextureFromSurface(nestRenderer, surface)
  if texture == nil:
    debugEcho "Nest image texture creation failed: ", path
    return screen.Image(0)

  discard setTextureBlendMode(texture, BLENDMODE_BLEND)
  var width, height: cfloat
  if not getTextureSize(texture, width, height):
    debugEcho "Nest image size failed: ", path
    destroyTexture(texture)
    return screen.Image(0)
  nestImages.add NestImageSlot(texture: texture, path: path, width: width.int,
      height: height.int)
  result = screen.Image(nestImages.len)
  nestImageByPath[path] = result

proc nestFreeImage(image: screen.Image) {.nimcall.} =
  let index = image.int - 1
  if index >= 0 and index < nestImages.len and nestImages[index].texture != nil:
    if nestImages[index].path.len > 0:
      nestImageByPath.del nestImages[index].path
    if nestImages[index].externalID.len == 0:
      destroyTexture(nestImages[index].texture)
    nestImages[index].texture = nil

proc nestDrawImage(image: screen.Image, src, dst: coords.Rect) {.nimcall.} =
  let index = image.int - 1
  if nestRenderer == nil or index < 0 or index >= nestImages.len:
    return
  let texture =
    if nestImages[index].externalID.len > 0:
      nestExternalTextures.getOrDefault(nestImages[index].externalID).texture
    else:
      nestImages[index].texture
  if texture == nil:
    return
  var source = src.toFRect()
  var target = dst.toFRect()
  discard renderTexture(nestRenderer, texture, addr source, addr target)

proc nestImageSize(image: screen.Image): screen.TextExtent {.nimcall.} =
  let index = image.int - 1
  if index >= 0 and index < nestImages.len:
    screen.TextExtent(w: nestImages[index].width, h: nestImages[index].height)
  else:
    screen.TextExtent()

proc nestMeasureImage(path: string): screen.TextExtent {.nimcall.} =
  let image = nestLoadImage(path)
  if image.int == 0:
    return screen.TextExtent()
  nestImageSize(image)

proc applyNestClipState() =
  if nestRenderer == nil:
    return
  if nestCurrentClip.enabled:
    discard setRenderClipRect(nestRenderer, addr nestCurrentClip.rect)
  else:
    discard setRenderClipRect(nestRenderer, nil)

proc nestClearClipRect() {.nimcall.} =
  nestCurrentClip = NestClipState()
  applyNestClipState()

proc nestSaveState() {.nimcall.} =
  nestClipStack.add nestCurrentClip

proc nestRestoreState() {.nimcall.} =
  if nestClipStack.len == 0:
    return
  nestCurrentClip = nestClipStack[^1]
  nestClipStack.setLen(nestClipStack.len - 1)
  applyNestClipState()

proc nestSetClipRect(r: coords.Rect) {.nimcall.} =
  nestCurrentClip = NestClipState(
    enabled: true,
    rect: sdl3.Rect(x: r.x.cint, y: r.y.cint, w: r.w.cint, h: r.h.cint),
  )
  applyNestClipState()

proc nestSetWindowTitle(title: string) {.nimcall.} =
  if nestWindow != nil:
    discard sdl3.setWindowTitle(nestWindow, cstring(title))

proc installNestDriver*(window: Window, renderer: Renderer) =
  nestWindow = window
  nestRenderer = renderer
  nestClipStack.setLen(0)
  nestCurrentClip = NestClipState()
  applyNestClipState()
  input.inputRelays.getTicks = proc(): int =
    sdl3.getTicks().int
  input.inputRelays.sleep = proc(ms: int) =
    sdl3.delay(max(ms, 0).uint32)
  windowRelays = WindowRelays(
    createWindow: proc(layout: var ScreenLayout) =
    discard,
    refresh: proc() =
    discard,
    saveState: nestSaveState,
    restoreState: nestRestoreState,
    setClipRect: nestSetClipRect,
    setCursor: proc(c: CursorKind) =
    discard,
    setWindowTitle: nestSetWindowTitle,
  )
  fontRelays = FontRelays(
    openFont: nestOpenFont,
    closeFont: nestCloseFont,
    getFontMetrics: nestFontMetrics,
    measureText: nestMeasureText,
    drawText: nestDrawText,
  )
  drawRelays = DrawRelays(
    fillRect: nestFillRect,
    lineRect: nestLineRect,
    drawLine: nestDrawLine,
    drawPoint: nestDrawPoint,
    loadImage: nestLoadImage,
    freeImage: nestFreeImage,
    drawImage: nestDrawImage,
    imageSize: nestImageSize,
  )
proc replayDrawCommands*(commands: openArray[screen.DrawCommand]) =
  nestClipStack.setLen(0)
  nestClearClipRect()
  for command in commands:
    case command.kind
    of SaveState:
      nestSaveState()
    of RestoreState:
      nestRestoreState()
    of SetClipRect:
      nestSetClipRect(command.rect)
    of FillRect:
      nestFillRect(command.rect, command.color)
    of FillRoundedRect:
      nestFillRoundedRect(
        command.roundedRect,
        command.roundedRadii,
        command.roundedColor,
      )
    of LineRect:
      nestLineRect(command.rect, command.color)
    of LineRoundedRect:
      nestLineRoundedRect(
        command.roundedRect,
        command.roundedRadii,
        command.roundedColor,
      )
    of DrawLine:
      nestDrawLine(command.x1, command.y1, command.x2, command.y2,
          command.lineColor)
    of DrawPoint:
      nestDrawPoint(command.x, command.y, command.pointColor)
    of DrawText:
      discard nestDrawText(
        command.font,
        command.textX,
        command.textY,
        command.text,
        command.fg,
        command.bg,
      )
    of DrawImage:
      if command.imagePath.len > 0:
        let image = nestLoadImage(command.imagePath)
        if image.int != 0:
          nestDrawImage(image, command.src, command.dst)
      else:
        nestDrawImage(command.image, command.src, command.dst)
  nestClipStack.setLen(0)
  nestClearClipRect()

template renderNest*(ui: var UI, body: untyped) =
  prepareNestCanvas(ui)
  ui.setDrawTicks(sdl3.getTicks().int)
  var drawCommands {.inject.}: seq[screen.DrawCommand]
  ui.setDrawCommandRelays(addr drawCommands, nestMeasureText, nestMeasureImage)
  pollNestFallbackFilePickers()
  var io {.inject.} = nestIO()
  ui.setIO(io)
  body
  ui.setDrawCommandRelays(nil, nil, nil)
  ui.setIO(IO())
  if ui.redrewFrame():
    nestCachedDrawCommands = drawCommands
    if ensureNestTextureCache(ui.windowWidth, ui.windowHeight):
      let previousTarget = getRenderTarget(nestRenderer)
      discard setRenderTarget(nestRenderer, nestCachedTexture)
      discard setRenderDrawColor(nestRenderer, 0, 0, 0, 0)
      discard renderClear(nestRenderer)
      replayDrawCommands(nestCachedDrawCommands)
      discard setRenderTarget(nestRenderer, previousTarget)
      blitNestTextureCache()
    else:
      replayDrawCommands(nestCachedDrawCommands)
  else:
    if nestCachedTexture != nil:
      blitNestTextureCache()
    else:
      replayDrawCommands(nestCachedDrawCommands)
  finishNestCanvas()

proc renderCachedNest*() =
  if nestCanvas != nil:
    # The UI dimensions were synchronized by the previous full UI frame.
    nestCanvas[].begin(0, 0, 0, 0)
  if nestCachedTexture != nil:
    blitNestTextureCache()
  else:
    replayDrawCommands(nestCachedDrawCommands)
  finishNestCanvas()

proc renderNestDynamicTexts*(ui: UI) =
  if nestDynamicTexts.len == 0:
    return
  nestClearClipRect()
  for id, item in nestDynamicTexts.pairs:
    let frame = ui.widgetFrame(id)
    if not frame.ok:
      continue
    let fg =
      if item.fg.a == 0:
        ui.palette.textColor
      else:
        item.fg
    let extent = nestMeasureText(ui.font(item.fontName), item.text)
    let
      textX = frame.frame.x.toInt +
        max((frame.frame.width.toInt - extent.w) div 2, 0)
      textY = frame.frame.y.toInt +
        max((frame.frame.height.toInt - extent.h) div 2, 0)
    discard nestDrawText(
      ui.font(item.fontName),
      textX,
      textY,
      item.text,
      fg,
      item.bg,
    )
