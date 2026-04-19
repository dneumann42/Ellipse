import std/[macros, strutils]
import ../plugins
import SDL3
import SDL3gpu
import SDL3gpuext
import SDL3ttfext
import ../gui
import ../resources

import ../rendering/[artist2D, artist3D, canvases, gpucontext]
import ../inputs

export macros, plugins, SDL3, SDL3gpu, SDL3gpuext, gui, artist2D, artist3D, canvases, gpucontext, inputs

{.push raises: [].}

const
  appOverlaySpriteBudget = 256
  defaultGuiSupersampleScale = 4
  guiCanvasId = "__ellipse.gui"

type
  NoAction* = enum
    noAction

  KeyDownMessage* = object
    keycode*: Keycode
    scancode*: Scancode
    repeat*: bool

  AppConfig* = object
    appId*: string
    title*: string
    width*: int
    height*: int
    windowFlags*: WindowFlags
    resizable*: bool
    shaderFormat*: GPUShaderFormat
    driverName*: cstring
    debugMode*: bool
    maxSprites*: int
    max3DQuads*: int
    maxTextureSlots*: int
    clearColor*: FColor
    defaultFontPath*: string
    defaultFontSize*: cfloat

  Application*[T, A] = object
    config*: AppConfig
    pluginStates*: PluginStates
    messages*: PluginMessages
    scenes*: SceneStack
    resources*: Resources
    inputs*: Input[A]
    quitRequested*: bool
    state*: T
    context*: GPUWindowContext
    ttf*: TTFAppHandle
    artist*: Artist2D
    artist3D*: Artist3D
    canvasManager*: CanvasManager
    gui*: GuiContext
    fpsText: string
    fps*: cfloat
    lastCounter: uint64
    deltaSeconds*: float

template sdlError(prefix: string): string =
  prefix & ": " & $getError()

var cstderr {.importc: "stderr", header: "<stdio.h>".}: pointer

proc fputs(s: cstring, stream: pointer): cint {.
  importc,
  header: "<stdio.h>",
  discardable
.}

proc flushStderr(message: string) =
  discard fputs((message & '\n').cstring, cstderr)

macro withFields*(o: typed, self, blk: untyped) =
  var bindings = nnkStmtList.newTree()
  var rebindings = nnkStmtList.newTree()
  let t = o.getTypeImpl()

  for binding in t[2]:
    let defs = binding[0]
    let id = ident(defs.repr)
    bindings.add quote do:
      var `id` {.inject.} = `self`.state.`id`
    rebindings.add quote do:
      `self`.state.`id` = `id`

  result = quote do:
    block:
      `bindings`
      `blk`
      `rebindings`

proc reportException(context: string; err: ref CatchableError) =
  flushStderr(context & ": " & err.msg)
  let trace = err.getStackTrace()
  if trace.len > 0:
    flushStderr(trace)

proc destroyApplication[T, A](app: ref Application[T, A]) =
  if app.isNil:
    return
  if not raw(app.context.device).isNil:
    app.artist.releaseCachedTextTextures()
  reset(app[])

proc normalizedWindowPosition[T, A](
  app: ref Application[T, A];
  x: cfloat;
  y: cfloat
): tuple[x, y: int] =
  var logicalWidth: cint
  var logicalHeight: cint
  var pixelWidth: cint
  var pixelHeight: cint

  if getWindowSize(raw(app.context.window), addr logicalWidth, addr logicalHeight) and
      getWindowSizeInPixels(raw(app.context.window), addr pixelWidth, addr pixelHeight) and
      logicalWidth > 0 and logicalHeight > 0 and pixelWidth > 0 and pixelHeight > 0:
    return (
      x: int(x.float * pixelWidth.float / logicalWidth.float),
      y: int(y.float * pixelHeight.float / logicalHeight.float)
    )

  (x: int(x), y: int(y))

proc currentGuiSize[T, A](app: ref Application[T, A]): tuple[w, h: int] =
  var pixelWidth: cint
  var pixelHeight: cint
  if getWindowSizeInPixels(raw(app.context.window), addr pixelWidth, addr pixelHeight) and
      pixelWidth > 0 and pixelHeight > 0:
    return (w: pixelWidth.int, h: pixelHeight.int)

  (
    w: max(app.config.width, 1),
    h: max(app.config.height, 1)
  )

template generateApplication[T, A](cfg: AppConfig, initialState: T, initialInputs: Input[A]): untyped =
  var gApplication {.global.}: ref Application[T, A]

  proc appInitCallback(
    appState: ptr pointer,
    argc: cint,
    argv: cstringArray
  ): AppResult {.cdecl.} =
    discard argc
    discard argv

    new(gApplication)
    gApplication[] = Application[T, A](
      config: cfg,
      messages: PluginMessages.init(),
      scenes: SceneStack.new(),
      inputs: initialInputs,
      state: initialState
    )

    appState[] = cast[pointer](gApplication)

    if not setAppMetadata(
      gApplication.config.title.cstring,
      "0.0.0",
      gApplication.config.appId.cstring
    ):
      flushStderr(sdlError("setAppMetadata failed"))
      gApplication.destroyApplication()
      return appFailure

    try:
      let artistConfig = Artist2DConfig(
        maxSprites:
          if gApplication.config.maxSprites > 0:
            gApplication.config.maxSprites + appOverlaySpriteBudget
          else:
            100_000 + appOverlaySpriteBudget,
        maxTextureSlots:
          if gApplication.config.maxTextureSlots > 0:
            gApplication.config.maxTextureSlots
          else:
            8
      )
      gApplication.context = initGPUWindowContext(
        GPUWindowConfig(
          appId: gApplication.config.appId,
          title: gApplication.config.title,
          width: gApplication.config.width,
          height: gApplication.config.height,
          windowFlags: gApplication.config.windowFlags,
          resizable: gApplication.config.resizable,
          shaderFormat:
            if gApplication.config.shaderFormat != 0:
              gApplication.config.shaderFormat
            else:
              GPU_SHADERFORMAT_SPIRV,
          driverName:
            if not gApplication.config.driverName.isNil:
              gApplication.config.driverName
            else:
              "vulkan",
          debugMode: gApplication.config.debugMode
        )
      )
      gApplication.ttf = TTFAppHandle.init()
      gApplication.artist = initArtist2D(
        gApplication.context.device,
        getGPUSwapchainTextureFormat(gApplication.context.claim),
        Artist2DConfig(
          maxSprites: artistConfig.maxSprites,
          maxTextureSlots: artistConfig.maxTextureSlots,
          vertexShaderPath: artistConfig.vertexShaderPath,
          fragmentShaderPath: artistConfig.fragmentShaderPath,
          samplerInfo: artistConfig.samplerInfo,
          defaultFontPath: gApplication.config.defaultFontPath,
          defaultFontSize: gApplication.config.defaultFontSize
        )
      )
      gApplication.artist3D = initArtist3D(
        gApplication.context.device,
        getGPUSwapchainTextureFormat(gApplication.context.claim),
        Artist3DConfig(
          maxQuads:
            if gApplication.config.max3DQuads > 0:
              gApplication.config.max3DQuads
            else:
              20_000,
          maxTextureSlots: artistConfig.maxTextureSlots
        )
      )
      gApplication.canvasManager = initCanvasManager(
        gApplication.context.device,
        Artist2DConfig(
          maxSprites: artistConfig.maxSprites,
          maxTextureSlots: artistConfig.maxTextureSlots,
          vertexShaderPath: artistConfig.vertexShaderPath,
          fragmentShaderPath: artistConfig.fragmentShaderPath,
          samplerInfo: artistConfig.samplerInfo,
          defaultFontPath: gApplication.config.defaultFontPath,
          defaultFontSize: gApplication.config.defaultFontSize
        )
      )
      registerCanvas(gApplication.canvasManager, RenderCanvasConfig(
        id: guiCanvasId,
        width: gApplication.config.width * defaultGuiSupersampleScale,
        height: gApplication.config.height * defaultGuiSupersampleScale,
        scaleMode: csmStretch,
        filterMode: tfLinear,
        layer: high(int),
        clearColor: FColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
      ))
      gApplication.gui = initGuiContext()
      gApplication.lastCounter = getPerformanceCounter()
      gApplication.deltaSeconds = 1.0 / 60.0
      gApplication.fpsText = "FPS: --"
      if not startTextInput(raw(gApplication.context.window)):
        raise newException(CatchableError, sdlError("startTextInput failed"))
    except SDL3gpuext.Error as err:
      flushStderr(err.msg)
      gApplication.destroyApplication()
      return appFailure
    except CatchableError as err:
      reportException("application init failed", err)
      gApplication.destroyApplication()
      return appFailure

    generatePluginStateInitialize(gApplication.pluginStates)

    var
      scenes {.inject.} = gApplication.scenes
      pluginStates {.inject.} = gApplication.pluginStates
      messages {.inject.} = gApplication.messages
      resources {.inject.} = gApplication.resources
      inputs {.inject.} = gApplication.inputs
      quit {.inject.} = gApplication.quitRequested
    template window: untyped {.inject, used.} = raw(gApplication.context.window)
    template device: untyped {.inject, used.} = raw(gApplication.context.device)
    template canvases: untyped {.inject, used.} = gApplication.canvasManager
    template artist: untyped {.inject, used.} =
      currentArtistPtr(gApplication.canvasManager, addr gApplication.artist)[]
    template artist3D: untyped {.inject, used.} = gApplication.artist3D

    withFields(gApplication.state, gApplication):
      try:
        generatePluginStep(load)
      except CatchableError as err:
        reportException("application load failed", err)
        gApplication.destroyApplication()
        return appFailure

    gApplication.scenes = scenes
    gApplication.pluginStates = pluginStates
    gApplication.messages = messages
    gApplication.resources = resources
    gApplication.inputs = inputs
    gApplication.quitRequested = quit

    appContinue

  proc iterateCallback(appState: pointer): AppResult {.cdecl.} =
    let app = cast[ref Application[T, A]](appState)
    defer:
      app.gui.clearTransientInput()

    var
      scenes {.inject.} = app.scenes
      pluginStates {.inject.} = app.pluginStates
      messages {.inject.} = app.messages
      resources {.inject.} = app.resources
      inputs {.inject.} = app.inputs
      quit {.inject.} = app.quitRequested
    template window: untyped {.inject, used.} = raw(app.context.window)
    template device: untyped {.inject, used.} = raw(app.context.device)
    template canvases: untyped {.inject, used.} = app.canvasManager
    template artist: untyped {.inject, used.} =
      currentArtistPtr(app.canvasManager, addr app.artist)[]
    template artist3D: untyped {.inject, used.} = app.artist3D
    template deltaSeconds: untyped {.inject, used.} = app.deltaSeconds

    let guiSize = app.currentGuiSize()
    scenes.startFrame()
    scenes.handlePushed()
    app.gui.beginFrame(app.artist)

    withFields(app.state, app):
      try:
        generatePluginStep(loadScene)
        generateListenStep(messages)
        template ui: untyped {.inject, used.} = app.gui.ui
        template guiWidth: untyped {.inject, used.} = guiSize.w
        template guiHeight: untyped {.inject, used.} = guiSize.h
        generatePluginStep(update)
        generatePluginStep(alwaysUpdate)
      except CatchableError as err:
        reportException("application update failed", err)
        return appFailure

    if scenes.sceneChanged():
      app.gui.beginFrame(app.artist)

    app.gui.update(guiSize.w, guiSize.h, app.deltaSeconds)

    app.scenes = scenes
    app.pluginStates = pluginStates
    app.messages = messages
    app.resources = resources
    app.inputs = inputs
    app.inputs.lateUpdate()
    app.quitRequested = quit

    if app.quitRequested:
      return appSuccess

    let counter = getPerformanceCounter()
    if app.lastCounter != 0:
      let delta = counter - app.lastCounter
      if delta > 0:
        app.fps = getPerformanceFrequency().cfloat / delta.cfloat
        app.fpsText = "FPS: " & formatFloat(app.fps, ffDecimal, 1)
        app.deltaSeconds = delta.float / getPerformanceFrequency().float
    app.lastCounter = counter

    let commandBuffer =
      try:
        acquireGPUCommandBuffer(app.context.device)
      except SDL3gpuext.Error as err:
        flushStderr(err.msg)
        return appFailure

    var swapchainTexture: ptr GPUTexture
    var swapchainWidth: uint32
    var swapchainHeight: uint32
    if not waitAndAcquireGPUSwapchainTexture(
      commandBuffer,
      raw(app.context.window),
      addr swapchainTexture,
      addr swapchainWidth,
      addr swapchainHeight
    ):
      flushStderr(sdlError("waitAndAcquireGPUSwapchainTexture failed"))
      discard cancelGPUCommandBuffer(commandBuffer)
      return appFailure

    if swapchainTexture.isNil:
      return if submitGPUCommandBuffer(commandBuffer): appContinue else: appFailure

    try:
      resizeCanvas(
        app.canvasManager,
        guiCanvasId,
        swapchainWidth.int * defaultGuiSupersampleScale,
        swapchainHeight.int * defaultGuiSupersampleScale
      )
    except CatchableError as err:
      reportException("application canvas resize failed", err)
      discard cancelGPUCommandBuffer(commandBuffer)
      return appFailure

    beginFrame(app.artist)
    beginFrame(app.artist3D)
    beginFrame(app.canvasManager)
    try:
      clearCanvases(app.canvasManager, commandBuffer)
    except CatchableError as err:
      reportException("application canvas clear failed", err)
      discard cancelGPUCommandBuffer(commandBuffer)
      return appFailure

    block:
      var
        pluginStates {.inject.} = app.pluginStates
        messages {.inject.} = app.messages
        resources {.inject.} = app.resources
        inputs {.inject.} = app.inputs
        scenes {.inject.} = app.scenes
        quit {.inject.} = app.quitRequested
      template window: untyped {.inject, used.} = raw(app.context.window)
      template device: untyped {.inject, used.} = raw(app.context.device)
      template canvases: untyped {.inject, used.} = app.canvasManager
      template artist: untyped {.inject, used.} =
        currentArtistPtr(app.canvasManager, addr app.artist)[]
      template artist3D: untyped {.inject, used.} = app.artist3D
      template swapchainWidth: untyped {.inject, used.} = swapchainWidth
      template swapchainHeight: untyped {.inject, used.} = swapchainHeight

      withFields(app.state, app):
        try:
          generatePluginStep(draw3D)
          generatePluginStep(draw)
        except CatchableError as err:
          reportException("application draw failed", err)
          discard cancelGPUCommandBuffer(commandBuffer)
          return appFailure

      app.pluginStates = pluginStates
      app.messages = messages
      app.resources = resources
      app.inputs = inputs
      app.scenes = scenes
      app.quitRequested = quit

    try:
      sortForRendering(app.canvasManager)
      withCanvas(app.canvasManager, app.artist, guiCanvasId):
        app.gui.draw(
          artist,
          swapchainWidth.int,
          swapchainHeight.int,
          defaultGuiSupersampleScale.cfloat
        )
      renderCanvases(app.canvasManager, commandBuffer)
      render(
        app.artist3D,
        commandBuffer,
        swapchainTexture,
        swapchainWidth,
        swapchainHeight,
        if app.config.clearColor == default(FColor):
          FColor(r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        else:
          app.config.clearColor
      )
      composeCanvases(app.canvasManager, app.artist, swapchainWidth, swapchainHeight)
      discard drawText(
        app.artist,
        app.fpsText,
        [14'f32, 14'f32],
        [0'f32, 0'f32, 0'f32, 0.9'f32],
        2'f32
      )
      discard drawText(
        app.artist,
        app.fpsText,
        [12'f32, 12'f32],
        [1'f32, 0.95'f32, 0.35'f32, 1'f32],
        2'f32
      )
      render(
        app.artist,
        commandBuffer,
        swapchainTexture,
        swapchainWidth,
        swapchainHeight,
        (if app.config.clearColor == default(FColor):
          FColor(r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        else:
          app.config.clearColor),
        renderTargetLoad
      )
    except CatchableError as err:
      reportException("application render failed", err)
      discard cancelGPUCommandBuffer(commandBuffer)
      return appFailure

    if not submitGPUCommandBuffer(commandBuffer):
      flushStderr(sdlError("submitGPUCommandBuffer failed"))
      return appFailure

    appContinue

  proc eventCallback(appState: pointer; event: ptr Event): AppResult {.cdecl.} =
    let app = cast[ref Application[T, A]](appState)

    case event[].`type`
    of EVENT_QUIT, EVENT_WINDOW_CLOSE_REQUESTED:
      app.quitRequested = true
      appSuccess
    of EVENT_KEY_DOWN:
      case event[].key.scancode
      of SCANCODE_BACKSPACE:
        app.gui.pressBackspace()
      of SCANCODE_RETURN:
        app.gui.pressEnter()
      of SCANCODE_TAB:
        app.gui.pressTab()
      of SCANCODE_LSHIFT, SCANCODE_RSHIFT:
        app.gui.setShiftDown(true)
      else:
        discard
      app.inputs.handleKeyDown(
        event[].key.key,
        event[].key.scancode,
        event[].key.repeat
      )
      appContinue
    of EVENT_KEY_UP:
      case event[].key.scancode
      of SCANCODE_LSHIFT, SCANCODE_RSHIFT:
        app.gui.setShiftDown(false)
      else:
        discard
      app.inputs.handleKeyUp(event[].key.key, event[].key.scancode)
      appContinue
    of EVENT_TEXT_INPUT:
      if not event[].text.text.isNil:
        app.gui.appendTextInput($event[].text.text)
      appContinue
    of EVENT_MOUSE_MOTION:
      let pos = app.normalizedWindowPosition(event[].motion.x, event[].motion.y)
      app.gui.setMousePosition(pos.x, pos.y)
      appContinue
    of EVENT_MOUSE_BUTTON_DOWN, EVENT_MOUSE_BUTTON_UP:
      let pos = app.normalizedWindowPosition(event[].button.x, event[].button.y)
      app.gui.setMousePosition(pos.x, pos.y)
      case event[].button.button
      of BUTTON_LEFT:
        app.gui.setActionButton(event[].button.down)
      of BUTTON_RIGHT:
        app.gui.setDragButton(event[].button.down)
      else:
        discard
      appContinue
    of EVENT_MOUSE_WHEEL:
      let pos = app.normalizedWindowPosition(event[].wheel.mouse_x, event[].wheel.mouse_y)
      app.gui.setMousePosition(pos.x, pos.y)
      let scrollY =
        if event[].wheel.direction == mouseWheelFlipped:
          -event[].wheel.y.float
        else:
          event[].wheel.y.float
      app.gui.addScroll(scrollY * 24.0)
      appContinue
    else:
      appContinue

  proc quitCallback(appState: pointer; result: AppResult) {.cdecl.} =
    discard result

    let app =
      if appState.isNil:
        gApplication
      else:
        cast[ref Application[T, A]](appState)

    if not app.isNil and not raw(app.context.window).isNil:
      discard stopTextInput(raw(app.context.window))

    app.destroyApplication()
    gApplication = nil

  discard enterAppMainCallbacks(
    0,
    nil,
    appInitCallback,
    iterateCallback,
    eventCallback,
    quitCallback
  )

template startApplication*[T, A](config: AppConfig, initialState: T, inputs: Input[A]): untyped =
  generateApplication(config, initialState, inputs)

template startApplication*[T](config: AppConfig, initialState: T): untyped =
  generateApplication(config, initialState, binder[NoAction]().build())
