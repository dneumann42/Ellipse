import std/[os, osproc, streams, strutils, tables]

import sdl3
import sdl3_ttf
import chroma as chromaColors
import plugnim
import nest except Event, update, draw
import nest/[coords, input, screen]
export plugnim
export nest except Event, update, draw

import rendering/artist3D
import errors

type
  NestFontSlot = object
    font: sdl3_ttf.Font
    metrics: screen.FontMetrics

  ApplicationConfig* = object
    appname*, appversion*: string
    width* = 1280
    height* = 720

const
  MaxDeltaTime = 0.25'f64
  DefaultFontPaths = [
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
  ]

var
  nestRenderer: Renderer
  nestWindow: Window
  nestFonts: seq[NestFontSlot]
  nestPickedFiles: Table[WidgetID, string]
  nestFilePickerErrors: Table[WidgetID, string]
  nestFallbackFilePickers: Table[WidgetID, osproc.Process]

type Application* = object
  window: Window
  renderer: Renderer

proc `=copy`*(app: var Application, source: Application) {.error.}
proc `=destroy`*(app: var Application) =
  if not app.renderer.isNil:
    destroyRenderer app.renderer
    app.renderer = nil
  if not app.window.isNil:
    destroyWindow app.window
    app.window = nil
  for slot in nestFonts.mitems:
    if slot.font != nil:
      sdl3_ttf.closeFont(slot.font)
      slot.font = nil
  if nestFonts.len > 0:
    nestFonts.setLen(0)
  if nestRenderer == app.renderer:
    nestRenderer = nil
  if nestWindow == app.window:
    nestWindow = nil

proc raiseError(context: string) {.noreturn.} =
  raise SDLException.newException(context & ": " & $sdl3.getError())

template attempt(succ: bool, context: string) =
  if not succ:
    raiseError(context)

proc secondsBetween(startCounter, endCounter, frequency: uint64): float64 =
  float64(endCounter - startCounter) / float64(frequency)

proc configureSdlVideoDriver() =
  if getEnv("SDL_VIDEO_DRIVER").len == 0 and getEnv("SDL_VIDEODRIVER").len == 0 and
      getEnv("WAYLAND_DISPLAY").len > 0:
    discard setHint("SDL_VIDEO_DRIVER", "wayland")

proc closeNestFallbackFilePicker(id: WidgetID) =
  if nestFallbackFilePickers.hasKey(id):
    nestFallbackFilePickers[id].close()
    nestFallbackFilePickers.del id

proc startNestFallbackFilePicker(id: WidgetID, defaultLocation: string): bool =
  if nestFallbackFilePickers.hasKey(id) and nestFallbackFilePickers[id].running:
    return true
  closeNestFallbackFilePicker(id)

  try:
    let zenity = findExe("zenity")
    if zenity.len > 0:
      echo "file picker fallback: zenity"
      var args = @["--file-selection"]
      if defaultLocation.len > 0:
        args.add "--filename=" & defaultLocation
      nestFallbackFilePickers[id] = startProcess(
        zenity, args = args, options = {poStdErrToStdOut}
      )
      return true

    let kdialog = findExe("kdialog")
    if kdialog.len > 0:
      echo "file picker fallback: kdialog"
      var args = @["--getopenfilename"]
      if defaultLocation.len > 0:
        args.add defaultLocation
      nestFallbackFilePickers[id] = startProcess(
        kdialog, args = args, options = {poStdErrToStdOut}
      )
      return true

    let yad = findExe("yad")
    if yad.len > 0:
      echo "file picker fallback: yad"
      var args = @["--file-selection"]
      if defaultLocation.len > 0:
        args.add "--filename=" & defaultLocation
      nestFallbackFilePickers[id] = startProcess(
        yad, args = args, options = {poStdErrToStdOut}
      )
      return true

    nestFilePickerErrors[id] =
      "SDL file picker returned no selection and no fallback file picker was found"
  except CatchableError as error:
    nestFilePickerErrors[id] = error.msg
  if nestFilePickerErrors.getOrDefault(id).len > 0:
    echo "file picker error: ", nestFilePickerErrors[id]
  false

proc pollNestFallbackFilePickers() =
  var finished: seq[WidgetID]
  for id, process in nestFallbackFilePickers.mpairs:
    if process.running:
      continue
    let output = process.outputStream.readAll.strip
    let exitCode = process.peekExitCode()
    process.close()
    finished.add id
    if exitCode == 0 and output.len > 0:
      nestPickedFiles[id] = output.splitLines()[0]
      nestFilePickerErrors.del id
      echo "file picked: ", nestPickedFiles[id]
    elif exitCode != 0 and output.len > 0:
      nestFilePickerErrors[id] = output
      echo "file picker error: ", nestFilePickerErrors[id]
  for id in finished:
    nestFallbackFilePickers.del id

proc nestOpenFile(id: WidgetID, defaultLocation: cstring): bool {.cdecl.} =
  try:
    nestFilePickerErrors.del id
    var completed = false
    var selected = false
    echo "file picker requested"
    dialogs.showOpenFileDialog(
      proc(result: dialogs.FileDialogResult) =
        completed = true
        selected = not result.canceled and result.paths.len > 0
        if selected:
          nestPickedFiles[id] = result.paths[0]
      ,
      defaultLocation = $defaultLocation,
      allowMany = false,
      window = nestWindow,
    )
    let dialogError = dialogs.dialogError()
    if dialogError.len > 0:
      nestFilePickerErrors[id] = dialogError
    if selected:
      return true
    if completed and nestFilePickerErrors.getOrDefault(id).len == 0:
      return startNestFallbackFilePicker(id, $defaultLocation)
    result = nestFilePickerErrors.getOrDefault(id).len == 0
    if not result:
      echo "file picker error: ", nestFilePickerErrors[id]
  except CatchableError as error:
    nestFilePickerErrors[id] = error.msg
    echo "file picker error: ", nestFilePickerErrors[id]
    result = false

proc nestFileValue(id: WidgetID): cstring {.cdecl.} =
  if nestPickedFiles.hasKey(id):
    nestPickedFiles[id].cstring
  else:
    cstring""

proc nestFileError(id: WidgetID): cstring {.cdecl.} =
  let dialogError = dialogs.dialogError()
  if dialogError.len > 0:
    nestFilePickerErrors[id] = dialogError
  if nestFilePickerErrors.hasKey(id):
    nestFilePickerErrors[id].cstring
  else:
    cstring""

proc nestClearFile(id: WidgetID) {.cdecl.} =
  nestPickedFiles.del id
  nestFilePickerErrors.del id

proc translateNestScancode(scancode: Scancode): input.KeyCode =
  case scancode
  of SCANCODE_A: KeyA
  of SCANCODE_B: KeyB
  of SCANCODE_C: KeyC
  of SCANCODE_D: KeyD
  of SCANCODE_E: KeyE
  of SCANCODE_F: KeyF
  of SCANCODE_G: KeyG
  of SCANCODE_H: KeyH
  of SCANCODE_I: KeyI
  of SCANCODE_J: KeyJ
  of SCANCODE_K: KeyK
  of SCANCODE_L: KeyL
  of SCANCODE_M: KeyM
  of SCANCODE_N: KeyN
  of SCANCODE_O: KeyO
  of SCANCODE_P: KeyP
  of SCANCODE_Q: KeyQ
  of SCANCODE_R: KeyR
  of SCANCODE_S: KeyS
  of SCANCODE_T: KeyT
  of SCANCODE_U: KeyU
  of SCANCODE_V: KeyV
  of SCANCODE_W: KeyW
  of SCANCODE_X: KeyX
  of SCANCODE_Y: KeyY
  of SCANCODE_Z: KeyZ
  of SCANCODE_1: Key1
  of SCANCODE_2: Key2
  of SCANCODE_3: Key3
  of SCANCODE_4: Key4
  of SCANCODE_5: Key5
  of SCANCODE_6: Key6
  of SCANCODE_7: Key7
  of SCANCODE_8: Key8
  of SCANCODE_9: Key9
  of SCANCODE_0: Key0
  of SCANCODE_F1: KeyF1
  of SCANCODE_F2: KeyF2
  of SCANCODE_F3: KeyF3
  of SCANCODE_F4: KeyF4
  of SCANCODE_F5: KeyF5
  of SCANCODE_F6: KeyF6
  of SCANCODE_F7: KeyF7
  of SCANCODE_F8: KeyF8
  of SCANCODE_F9: KeyF9
  of SCANCODE_F10: KeyF10
  of SCANCODE_F11: KeyF11
  of SCANCODE_F12: KeyF12
  of SCANCODE_RETURN: KeyEnter
  of SCANCODE_SPACE: KeySpace
  of SCANCODE_ESCAPE: KeyEsc
  of SCANCODE_TAB: KeyTab
  of SCANCODE_BACKSPACE: KeyBackspace
  of SCANCODE_DELETE: KeyDelete
  of SCANCODE_INSERT: KeyInsert
  of SCANCODE_LEFT: KeyLeft
  of SCANCODE_RIGHT: KeyRight
  of SCANCODE_UP: KeyUp
  of SCANCODE_DOWN: KeyDown
  of SCANCODE_PAGEUP: KeyPageUp
  of SCANCODE_PAGEDOWN: KeyPageDown
  of SCANCODE_HOME: KeyHome
  of SCANCODE_END: KeyEnd
  of SCANCODE_CAPSLOCK: KeyCapslock
  of SCANCODE_COMMA: KeyComma
  of SCANCODE_PERIOD: KeyPeriod
  of SCANCODE_SLASH: KeySlash
  of SCANCODE_MINUS: KeyMinus
  of SCANCODE_EQUALS: KeyEqual
  of SCANCODE_KP_MINUS: KeyMinus
  of SCANCODE_KP_PLUS: KeyPlus
  of SCANCODE_KP_EQUALS: KeyEqual
  else: KeyNone

proc translateNestKeycode(keycode: int32): input.KeyCode =
  case keycode
  of SDLK_MINUS.int32, SDLK_KP_MINUS.int32: KeyMinus
  of SDLK_EQUALS.int32, SDLK_KP_EQUALS.int32: KeyEqual
  of SDLK_PLUS.int32, SDLK_KP_PLUS.int32: KeyPlus
  else: KeyNone

proc translateNestMods(keymod: Keymod): set[input.Modifier] =
  let flags = keymod.uint32
  if (flags and KMOD_SHIFT) != 0:
    result.incl ShiftPressed
  if (flags and KMOD_CTRL) != 0:
    result.incl CtrlPressed
  if (flags and KMOD_ALT) != 0:
    result.incl AltPressed
  if (flags and KMOD_GUI) != 0:
    result.incl GuiPressed

proc nestIO(): IO =
  IO(
    files: FileIO(
      openFile: nestOpenFile,
      fileValue: nestFileValue,
      fileError: nestFileError,
      clearFile: nestClearFile,
    )
  )

template update(dt: float64) =
  generatePluginFunctionCalls(update)

template draw(rendererArg: Renderer) =
  let renderer {.inject.}: Renderer = rendererArg
  attempt setRenderDrawColor(renderer, 12, 14, 18, 255), "Failed to set draw color"
  attempt renderClear(renderer), "Failed to clear renderer"
  generatePluginFunctionCalls(draw)

template nestEvent(event: sdl3.Event) =
  generatePluginFunctionCalls(nestEvent)

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

proc nestOpenFont(
    path: string, size: int, metrics: var screen.FontMetrics
): screen.Font {.nimcall.} =
  let resolved = resolveNestFontPath(path)
  if resolved.len == 0:
    return screen.Font(0)
  let font = sdl3_ttf.openFont(cstring(resolved), size.cfloat)
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

proc nestDrawText(
    font: screen.Font, x, y: int, text: string, fg, bg: screen.Color
): screen.TextExtent {.nimcall.} =
  let fontPtr = nestFontPtr(font)
  if fontPtr == nil or nestRenderer == nil or text.len == 0:
    return screen.TextExtent()
  let fgRgba: chromaColors.ColorRGBA = fg
  let surface = sdl3_ttf.renderTextBlended(fontPtr, cstring(text), 0, fgRgba.toSdlColor)
  if surface == nil:
    return screen.TextExtent()
  let texture = createTextureFromSurface(nestRenderer, surface)
  if texture == nil:
    destroySurface(surface)
    return screen.TextExtent()
  discard setTextureBlendMode(texture, BLENDMODE_BLEND)
  result = nestMeasureText(font, text)
  if bg.a != 0 and result.w > 0 and result.h > 0:
    var bgRect = FRect(x: x.cfloat, y: y.cfloat, w: result.w.cfloat, h: result.h.cfloat)
    setNestRenderDrawColor(bg)
    withNestBlendMode:
      discard renderFillRect(nestRenderer, addr bgRect)
  var dst = FRect(x: x.cfloat, y: y.cfloat, w: result.w.cfloat, h: result.h.cfloat)
  discard renderTexture(nestRenderer, texture, nil, addr dst)
  destroyTexture(texture)
  destroySurface(surface)

proc nestFillRect(r: coords.Rect, color: screen.Color) {.nimcall.} =
  if nestRenderer == nil:
    return
  setNestRenderDrawColor(color)
  var rect = r.toFRect()
  withNestBlendMode:
    discard renderFillRect(nestRenderer, addr rect)

proc nestLineRect(r: coords.Rect, color: screen.Color) {.nimcall.} =
  if nestRenderer == nil:
    return
  setNestRenderDrawColor(color)
  var rect = r.toFRect()
  withNestBlendMode:
    discard renderRect(nestRenderer, addr rect)

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
  screen.Image(0)

proc nestFreeImage(image: screen.Image) {.nimcall.} =
  discard

proc nestDrawImage(image: screen.Image, src, dst: coords.Rect) {.nimcall.} =
  discard

proc nestImageSize(image: screen.Image): screen.TextExtent {.nimcall.} =
  screen.TextExtent()

proc nestSetClipRect(r: coords.Rect) {.nimcall.} =
  if nestRenderer == nil:
    return
  var rect = sdl3.Rect(x: r.x.cint, y: r.y.cint, w: r.w.cint, h: r.h.cint)
  discard setRenderClipRect(nestRenderer, addr rect)

proc nestClearClipRect() {.nimcall.} =
  if nestRenderer != nil:
    discard setRenderClipRect(nestRenderer, nil)

proc nestSetWindowTitle(title: string) {.nimcall.} =
  if nestWindow != nil:
    discard sdl3.setWindowTitle(nestWindow, cstring(title))

proc installNestDriver*(app: Application) =
  nestWindow = app.window
  nestRenderer = app.renderer
  windowRelays = WindowRelays(
    createWindow: proc(layout: var ScreenLayout) =
      discard,
    refresh: proc() =
      discard,
    saveState: proc() =
      discard,
    restoreState: proc() =
      nestClearClipRect(),
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

proc createNest*(width = 1280, height = 720): UI =
  result = UI.init()
  result.initContext(width, height)
  result.loadFont("font", "", 18)

proc handleNestEvent*(ui: var UI, event: sdl3.Event) =
  let eventType = uint32(event.common.`type`)
  if eventType == uint32(EVENT_WINDOW_RESIZED):
    ui.resizeWindow(event.window.data1, event.window.data2)
    ui.markAllDirty()
  elif eventType == uint32(EVENT_MOUSE_MOTION):
    ui.mouseMove(event.motion.x.int, event.motion.y.int)
  elif eventType == uint32(EVENT_MOUSE_BUTTON_DOWN) and
      event.button.button == BUTTON_LEFT:
    ui.mouseMove(event.button.x.int, event.button.y.int)
    ui.mouseDown()
    ui.requestRedrawAfter(0)
  elif eventType == uint32(EVENT_MOUSE_BUTTON_UP) and event.button.button == BUTTON_LEFT:
    ui.mouseMove(event.button.x.int, event.button.y.int)
    ui.mouseUp()
    ui.requestRedrawAfter(0)
  elif eventType == uint32(EVENT_MOUSE_WHEEL):
    ui.mouseMove(event.wheel.mouse_x.int, event.wheel.mouse_y.int)
    ui.mouseWheel(event.wheel.x.float64, event.wheel.y.float64)
    ui.requestRedrawAfter(0)
  elif eventType == uint32(EVENT_KEY_DOWN):
    var key = translateNestScancode(event.key.scancode)
    if key == KeyNone:
      key = translateNestKeycode(event.key.key.int32)
    if key != KeyNone:
      ui.keyDown(key, translateNestMods(event.key.`mod`))
      ui.requestRedrawAfter(0)
  elif eventType == uint32(EVENT_TEXT_INPUT):
    if event.text.text != nil:
      ui.textInput($event.text.text)
      ui.requestRedrawAfter(0)

proc replayDrawCommands*(commands: openArray[screen.DrawCommand]) =
  for command in commands:
    case command.kind
    of SaveState:
      discard
    of RestoreState:
      nestClearClipRect()
    of SetClipRect:
      nestSetClipRect(command.rect)
    of FillRect:
      nestFillRect(command.rect, command.color)
    of LineRect:
      nestLineRect(command.rect, command.color)
    of DrawLine:
      nestDrawLine(command.x1, command.y1, command.x2, command.y2, command.lineColor)
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
      nestDrawImage(command.image, command.src, command.dst)

template renderNest*(ui: var UI, body: untyped) =
  ui.beginInputFrame()
  ui.setDrawTicks(sdl3.getTicks().int)
  ui.markAllDirty()
  var drawCommands {.inject.}: seq[screen.DrawCommand]
  ui.setDrawCommandRelays(addr drawCommands, nestMeasureText)
  pollNestFallbackFilePickers()
  var io {.inject.} = nestIO()
  ui.setIO(io)
  body
  ui.setDrawCommandRelays(nil, nil)
  ui.setIO(IO())
  replayDrawCommands(drawCommands)
  ui.finishInputFrame()

template sdlApplication(events, step) =
  let frequency = getPerformanceFrequency()
  var
    running {.inject.} = true
    previousTime = getPerformanceCounter()
    event: sdl3.Event
  while running:
    let frameStart = getPerformanceCounter()
    let dt {.inject.} =
      min(secondsBetween(previousTime, frameStart, frequency), MaxDeltaTime)
    previousTime = frameStart
    while pollEvent(event):
      if event.`type` == EVENT_QUIT:
        running = false
      let event {.inject.} = event
      events
    if not running:
      break
    step

template buildApplication*(appConfig: ApplicationConfig) =
  generatePluginContext()
  loadDynamicPlugins()
  proc start() =
    configureSdlVideoDriver()
    if not sdl3.init(INIT_VIDEO or INIT_AUDIO or INIT_GAMEPAD):
      raiseError("Failed to initialize SDL")
    if not sdl3_ttf.init():
      raiseError("Failed to initialize SDL_ttf")
    defer:
      sdl3_ttf.quit()
      sdl3.quit()

    var app = Application()
    app.window = createWindow(
      cstring(appConfig.appname),
      appConfig.width.cint,
      appConfig.height.cint,
      WINDOW_RESIZABLE or WINDOW_HIGH_PIXEL_DENSITY,
    )
    if app.window.isNil:
      raiseError("Failed to create window")
    attempt showWindow(app.window), "Failed to show window"
    discard startTextInput(app.window)
    app.renderer = sdl3.createRenderer(app.window, cstring"gpu")
    if app.renderer.isNil:
      raiseError("Failed to create renderer")
    attempt setRenderVSync(app.renderer, 0), "Failed to disable vsync"
    installArtist3DRenderer(app.renderer)
    app.installNestDriver()

    var gui {.inject.} = createNest()
    var artist {.inject.} = Artist3D.init(app.renderer)

    generatePluginFunctionCalls(load)
    sdlApplication:
      generatePluginFunctionCalls(event)
      handleNestEvent(gui, event)
    do:
      update(dt)
      draw(app.renderer)
      renderNest(gui):
        generatePluginFunctionCalls(ui)
      attempt renderPresent(app.renderer), "Failed to present renderer"
      delay(16)
