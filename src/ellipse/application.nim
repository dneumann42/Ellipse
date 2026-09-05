import std/[os, strutils]
import sdl3, sdl3_ttf, plugnim
import nest except Event, update, draw

export plugnim
export nest except Event, update, draw

import rendering/[artist3D, canvas]
import renderSettings
import errors, nestDriver, scenes
import inputs as ellipseInputs
import resources as ellipseResources

export nestDriver

type
  ApplicationConfig* = object
    appname*, appversion*: string
    width* = 1280
    height* = 720
    renderSettingsPath* = RenderSettingsPath

  Application* = object
    window: Window
    renderer: Renderer

const
  MaxDeltaTime = 0.25'f64
  TargetUpdateHz = 60.0'f64
  FixedUpdateSeconds* = 1.0'f64 / TargetUpdateHz

var currentFrameDeltaSecondsValue = FixedUpdateSeconds

proc `=copy`*(app: var Application, source: Application) {.error.}
proc `=destroy`*(app: var Application) =
  releaseNestDriver()
  if not app.renderer.isNil:
    destroyRenderer app.renderer
    app.renderer = nil
  if not app.window.isNil:
    destroyWindow app.window
    app.window = nil

proc secondsBetween(startCounter, endCounter, frequency: uint64): float64 =
  float64(endCounter - startCounter) / float64(frequency)

proc countersForSeconds(seconds: float64, frequency: uint64): uint64 =
  max(uint64(seconds * frequency.float64), 1'u64)

proc currentFrameDeltaSeconds*(): float64 =
  currentFrameDeltaSecondsValue

proc sleepUntilCounter(target, frequency: uint64) =
  while true:
    let now = getPerformanceCounter()
    if now >= target:
      break
    let remaining = secondsBetween(now, target, frequency)
    if remaining > 0.003:
      sdl3.delay(uint32(max((remaining * 1000.0).int - 1, 1)))
    elif remaining > 0.001:
      sdl3.delay(0)

proc screenshotName(appname: string): string =
  let safeName =
    if appname.len == 0:
      "ellipse"
    else:
      appname.multiReplace((" ", "_"), ("/", "_"), ("\\", "_"))
  getCurrentDir() / "data" / "screenshots" / (safeName & "-" & $sdl3.getTicks() & ".png")

proc configureSdlVideoDriver() =
  if (
    getEnv("SDL_VIDEO_DRIVER").len == 0 and getEnv("SDL_VIDEODRIVER").len == 0 and
    getEnv("WAYLAND_DISPLAY").len > 0
  ):
    discard setHint("SDL_VIDEO_DRIVER", "wayland")

template update(dt: float64, sceneStack: var SceneStack) =
  generatePluginFunctionCalls(earlyUpdate)
  sceneStack.handleLoads()
  generatePluginFunctionCalls(update)
  generatePluginFunctionCalls(lateUpdate)

template draw(rendererArg: Renderer) =
  let renderer {.inject.}: Renderer = rendererArg
  checkSdl setRenderDrawColor(renderer, 12, 14, 18, 255), "Failed to set draw color"
  checkSdl renderClear(renderer), "Failed to clear renderer"
  generatePluginFunctionCalls(draw)

template nestEvent(event: sdl3.Event) =
  generatePluginFunctionCalls(nestEvent)

template buildApplication*(appConfig: ApplicationConfig, blk: untyped) =
  generatePluginContext()
  loadDynamicPlugins()
  proc start() =
    configureSdlVideoDriver()
    if not sdl3.init(INIT_VIDEO or INIT_AUDIO or INIT_GAMEPAD):
      raiseSdlError("Failed to initialize SDL")
    if not sdl3_ttf.init():
      raiseSdlError("Failed to initialize SDL_ttf")
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
      raiseSdlError("Failed to create window")
    checkSdl showWindow(app.window), "Failed to show window"
    discard startTextInput(app.window)
    app.renderer = sdl3.createRenderer(app.window, cstring"gpu")
    if app.renderer.isNil:
      raiseSdlError("Failed to create renderer")
    checkSdl setRenderVSync(app.renderer, 0), "Failed to disable vsync"
    installArtist3DRenderer(app.renderer)
    installCanvasRenderer(app.renderer)
    nestDriver.installNestDriver(app.window, app.renderer)

    var gui {.inject.} = createNest()
    installNestPluginCallbacks()
    var artist {.inject.} = Artist3D.init(app.renderer)
    var renderSettingsLoader = RenderSettingsLoader.init(appConfig.renderSettingsPath)
    artist.renderSettings = renderSettingsLoader.settings
    var inputs {.inject.} = InputMap.init()
    var resources {.inject.} = ellipseResources.newResourceManager(app.renderer)

    var
      sceneStack {.inject.} = SceneStack.init()

    sceneStack.loadSceneStackState()

    blk
    generatePluginFunctionCalls(load)

    let frequency = getPerformanceFrequency()
    let frameStepCounters = countersForSeconds(FixedUpdateSeconds, frequency)

    var
      running {.inject.} = true
      previousTime = getPerformanceCounter()
      nextFrameCounter = previousTime + frameStepCounters
      sdlEvent: sdl3.Event
      firstFrame = true
      blockedMouseButtons: array[256, bool]
      screenshotRequested = false
      autoScreenshotAt = 0'u64
      benchFrames = 0
      benchFrameCount = 0
      benchUpdateSeconds = 0.0
      benchDrawSeconds = 0.0
      benchUiSeconds = 0.0
      benchPresentSeconds = 0.0
      benchFrameSeconds = 0.0
      benchFrameIntervalSeconds = 0.0
      benchFullUiFrames = 0
      benchCachedUiFrames = 0
      benchUiDueFrames = 0
      benchNestEveryFrameFrames = 0
      lastRenderSettingsPoll = 0'u64
      reportedRenderSettingsError = ""

    let autoScreenshotDelay = getEnv("ELLIPSE_SCREENSHOT_AFTER_MS")
    if autoScreenshotDelay.len > 0:
      try:
        autoScreenshotAt = sdl3.getTicks() + parseInt(
            autoScreenshotDelay).uint64
      except ValueError:
        debugEcho "Ignoring invalid ELLIPSE_SCREENSHOT_AFTER_MS: ", autoScreenshotDelay
    let benchFramesValue = getEnv("ELLIPSE_BENCH_FRAMES")
    if benchFramesValue.len > 0:
      try:
        benchFrames = max(parseInt(benchFramesValue), 0)
      except ValueError:
        debugEcho "Ignoring invalid ELLIPSE_BENCH_FRAMES: ", benchFramesValue
    var screenshotFrames: seq[int]
    for item in getEnv("ELLIPSE_SCREENSHOT_FRAMES").split(','):
      let value = item.strip()
      if value.len > 0:
        try:
          screenshotFrames.add parseInt(value)
        except ValueError:
          debugEcho "Ignoring invalid ELLIPSE_SCREENSHOT_FRAMES item: ", value
    while running:
      gui.beginInputFrame()
      sceneStack.handlePushed()

      var nestInputDue = false
      while pollEvent(sdlEvent):
        if sdlEvent.`type` == EVENT_QUIT:
          running = false
        elif sdlEvent.`type` == EVENT_KEY_DOWN and
            sdlEvent.key.scancode == SCANCODE_F12 and
            (sdlEvent.key.`mod`.uint32 and KMOD_CTRL) != 0:
          screenshotRequested = true
          requestFrameAfter(0)
        nestInputDue = handleNestEvent(gui, sdlEvent) or nestInputDue
        if not nestBlocksInputEvent(gui, sdlEvent, blockedMouseButtons):
          inputs.handleEvent(sdlEvent)
        let event {.inject.} = sdlEvent
        generatePluginFunctionCalls(event)

      if not running:
        gui.finishInputFrame()
        break

      discard pollDynamicPluginWatchers()
      let
        buildStarted = processDynamicPluginReloads()
        buildFinished = pollDynamicPluginBuilds()
      discard hasActiveDynamicPluginBuilds()
      if autoScreenshotAt > 0 and sdl3.getTicks() >= autoScreenshotAt:
        screenshotRequested = true
        autoScreenshotAt = 0
      if buildStarted or buildFinished:
        gui.markAllDirty()
      let
        pluginFrameRequested = consumeRuntimeFrameRequest()
        nestEveryFrame = consumeNestEveryFrameRequest()
      var forceNestUiRedraw = buildStarted or buildFinished
      let appRedrawDue = consumeApplicationRedraw(getPerformanceCounter())

      if hasReadyDynamicPluginReloads():
        generatePluginFunctionCalls(preReload)
        if activateReadyDynamicPluginReloads():
          generatePluginFunctionCalls(afterReload)
          gui.markAllDirty()
          forceNestUiRedraw = true

      var frameStart = getPerformanceCounter()
      let actualFrameDt = min(
        secondsBetween(previousTime, frameStart, frequency), MaxDeltaTime
      )
      currentFrameDeltaSecondsValue = actualFrameDt
      previousTime = frameStart
      let dt {.inject.} = actualFrameDt
      let renderSettingsNow = sdl3.getTicks()
      if lastRenderSettingsPoll == 0 or
          renderSettingsNow - lastRenderSettingsPoll >= 500:
        lastRenderSettingsPoll = renderSettingsNow
        if renderSettingsLoader.poll():
          artist.renderSettings = renderSettingsLoader.settings
          reportedRenderSettingsError = ""
          requestFrameAfter(0)
        elif renderSettingsLoader.lastError.len > 0 and
            renderSettingsLoader.lastError != reportedRenderSettingsError:
          debugEcho "Could not reload ", renderSettingsLoader.path, ": ",
            renderSettingsLoader.lastError
          reportedRenderSettingsError = renderSettingsLoader.lastError
      resources.poll()
      if gui.wantsTextInput():
        inputs.maskKeyboardInput()
      let benchFrameStart = getPerformanceCounter()
      let benchUpdateStart = benchFrameStart
      update(dt, sceneStack)
      sceneStack.handleUnloads()

      let benchDrawStart = getPerformanceCounter()
      draw(app.renderer)
      let benchUiStart = getPerformanceCounter()
      let uiDue = gui.redrawDelayMs() == 0
      let renderNestUi =
        firstFrame or not hasCachedNestFrame() or nestInputDue or
            uiDue or nestEveryFrame or pluginFrameRequested or appRedrawDue or
            forceNestUiRedraw
      if benchFrames > 0 and not firstFrame:
        if uiDue:
          inc benchUiDueFrames
        if nestEveryFrame or nestInputDue:
          inc benchNestEveryFrameFrames
      if renderNestUi:
        if uiDue:
          gui.clearRedrawRequest()
        renderNest(gui):
          generatePluginFunctionCalls(ui)
        if benchFrames > 0 and not firstFrame:
          inc benchFullUiFrames
      else:
        renderCachedNest()
        if benchFrames > 0 and not firstFrame:
          inc benchCachedUiFrames
      generatePluginFunctionCalls(postUi)

      discard gui.drawRealtime()
      renderNestDynamicTexts(gui)
      let benchPresentStart = getPerformanceCounter()
      if benchFrameCount in screenshotFrames:
        let path = screenshotName(appConfig.appname & "-frame-" &
            $benchFrameCount)
        if dumpRendererScreenshot(app.renderer, path):
          echo "Saved screenshot: ", path
      if screenshotRequested:
        let path = screenshotName(appConfig.appname)
        if dumpRendererScreenshot(app.renderer, path):
          debugEcho "Saved screenshot: ", path
        screenshotRequested = false
      checkSdl renderPresent(app.renderer), "Failed to present renderer"
      let benchFrameEnd = getPerformanceCounter()
      if benchFrames > 0 and not firstFrame:
        inc benchFrameCount
        benchUpdateSeconds += secondsBetween(
          benchUpdateStart, benchDrawStart, frequency
        )
        benchDrawSeconds += secondsBetween(benchDrawStart, benchUiStart, frequency)
        benchUiSeconds += secondsBetween(benchUiStart, benchPresentStart, frequency)
        benchPresentSeconds += secondsBetween(
          benchPresentStart, benchFrameEnd, frequency
        )
        benchFrameSeconds += secondsBetween(benchFrameStart, benchFrameEnd, frequency)
        benchFrameIntervalSeconds += actualFrameDt
        if benchFrameCount >= benchFrames:
          let count = benchFrameCount.float64
          echo "bench frames: ", benchFrameCount
          echo "bench fps: ", count / benchFrameSeconds
          echo "bench cadence fps: ", count / benchFrameIntervalSeconds
          echo "bench fixed update hz: ", 1.0 / FixedUpdateSeconds
          echo "bench full ui frames: ", benchFullUiFrames
          echo "bench cached ui frames: ", benchCachedUiFrames
          echo "bench ui due frames: ", benchUiDueFrames
          echo "bench nest every frame frames: ", benchNestEveryFrameFrames
          echo "bench update ms: ", benchUpdateSeconds * 1000 / count
          echo "bench draw ms: ", benchDrawSeconds * 1000 / count
          echo "bench ui ms: ", benchUiSeconds * 1000 / count
          echo "bench present ms: ", benchPresentSeconds * 1000 / count
          running = false
      gui.finishInputFrame()
      inputs.finishFrame()
      firstFrame = false
      if running:
        sleepUntilCounter(nextFrameCounter, frequency)
        let now = getPerformanceCounter()
        while nextFrameCounter <= now:
          nextFrameCounter += frameStepCounters
