import std/[macros, strutils]
import ../plugins
import ./SDL3
import ./SDL3gpu
import ./SDL3gpuext
import ../rendering/[artist2D, canvases, gpucontext]

export macros, plugins, SDL3, SDL3gpu, SDL3gpuext, artist2D, canvases, gpucontext

{.push raises: [].}

const
  appOverlaySpriteBudget = 256

type
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
    maxTextureSlots*: int
    clearColor*: FColor

  Application*[T] = object
    config*: AppConfig
    pluginStates*: PluginStates
    messages*: PluginMessages
    scenes*: SceneStack
    quitRequested*: bool
    state*: T
    context*: GPUWindowContext
    artist*: Artist2D
    canvasManager*: CanvasManager
    fpsText: string
    fps*: cfloat
    lastCounter: uint64

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

proc destroyApplication[T](app: ref Application[T]) =
  if app.isNil:
    return
  reset(app[])

template generateApplication[T](cfg: AppConfig, initialState: T): untyped =
  var gApplication {.global.}: ref Application[T]

  proc appInitCallback(
    appState: ptr pointer,
    argc: cint,
    argv: cstringArray
  ): AppResult {.cdecl.} =
    discard argc
    discard argv

    new(gApplication)
    gApplication[] = Application[T](
      config: cfg,
      messages: PluginMessages.init(),
      scenes: SceneStack.new(),
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
      gApplication.artist = initArtist2D(
        gApplication.context.device,
        getGPUSwapchainTextureFormat(gApplication.context.claim),
        artistConfig
      )
      gApplication.canvasManager = initCanvasManager(gApplication.context.device, artistConfig)
      gApplication.lastCounter = getPerformanceCounter()
      gApplication.fpsText = "FPS: --"
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
      quit {.inject.} = gApplication.quitRequested
    template window: untyped {.inject, used.} = raw(gApplication.context.window)
    template device: untyped {.inject, used.} = raw(gApplication.context.device)
    template canvases: untyped {.inject, used.} = gApplication.canvasManager
    template artist: untyped {.inject, used.} =
      currentArtistPtr(gApplication.canvasManager, addr gApplication.artist)[]

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
    gApplication.quitRequested = quit

    appContinue

  proc iterateCallback(appState: pointer): AppResult {.cdecl.} =
    let app = cast[ref Application[T]](appState)

    var
      scenes {.inject.} = app.scenes
      pluginStates {.inject.} = app.pluginStates
      messages {.inject.} = app.messages
      quit {.inject.} = app.quitRequested
    template window: untyped {.inject, used.} = raw(app.context.window)
    template device: untyped {.inject, used.} = raw(app.context.device)
    template canvases: untyped {.inject, used.} = app.canvasManager
    template artist: untyped {.inject, used.} =
      currentArtistPtr(app.canvasManager, addr app.artist)[]

    scenes.startFrame()
    scenes.handlePushed()

    withFields(app.state, app):
      try:
        generatePluginStep(loadScene)
        generateListenStep(messages)
        generatePluginStep(update)
        generatePluginStep(alwaysUpdate)
      except CatchableError as err:
        reportException("application update failed", err)
        return appFailure

    app.scenes = scenes
    app.pluginStates = pluginStates
    app.messages = messages
    app.quitRequested = quit

    if app.quitRequested:
      return appSuccess

    let counter = getPerformanceCounter()
    if app.lastCounter != 0:
      let delta = counter - app.lastCounter
      if delta > 0:
        app.fps = getPerformanceFrequency().cfloat / delta.cfloat
        app.fpsText = "FPS: " & formatFloat(app.fps, ffDecimal, 1)
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

    beginFrame(app.artist)
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
        scenes {.inject.} = app.scenes
        quit {.inject.} = app.quitRequested
      template window: untyped {.inject, used.} = raw(app.context.window)
      template device: untyped {.inject, used.} = raw(app.context.device)
      template canvases: untyped {.inject, used.} = app.canvasManager
      template artist: untyped {.inject, used.} =
        currentArtistPtr(app.canvasManager, addr app.artist)[]
      template swapchainWidth: untyped {.inject, used.} = swapchainWidth
      template swapchainHeight: untyped {.inject, used.} = swapchainHeight

      withFields(app.state, app):
        try:
          generatePluginStep(draw)
        except CatchableError as err:
          reportException("application draw failed", err)
          discard cancelGPUCommandBuffer(commandBuffer)
          return appFailure

      app.pluginStates = pluginStates
      app.messages = messages
      app.scenes = scenes
      app.quitRequested = quit

    try:
      sortForRendering(app.canvasManager)
      renderCanvases(app.canvasManager, commandBuffer)
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
        if app.config.clearColor == default(FColor):
          FColor(r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        else:
          app.config.clearColor
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
    let app = cast[ref Application[T]](appState)

    case event[].`type`
    of EVENT_QUIT, EVENT_WINDOW_CLOSE_REQUESTED:
      app.quitRequested = true
      appSuccess
    of EVENT_KEY_DOWN:
      app.messages.send(KeyDownMessage(
        keycode: event[].key.key,
        scancode: event[].key.scancode,
        repeat: event[].key.repeat
      ))
      appContinue
    else:
      appContinue

  proc quitCallback(appState: pointer; result: AppResult) {.cdecl.} =
    discard result

    let app =
      if appState.isNil:
        gApplication
      else:
        cast[ref Application[T]](appState)

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

template startApplication*[T](config: AppConfig, initialState: T): untyped =
  generateApplication(config, initialState)
