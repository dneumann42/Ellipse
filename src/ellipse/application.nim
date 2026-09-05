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

  BenchmarkState = object
    targetFrames, frameCount: int
    updateSeconds, drawSeconds, uiSeconds, presentSeconds: float64
    frameSeconds, frameIntervalSeconds: float64
    fullUiFrames, cachedUiFrames, uiDueFrames, nestEveryFrameFrames: int

  LoopState = object
    frequency, frameStepCounters: uint64
    previousTime, nextFrameCounter: uint64
    firstFrame: bool
    blockedMouseButtons: array[256, bool]
    screenshotRequested: bool
    autoScreenshotAt, lastRenderSettingsPoll: uint64
    screenshotFrames: seq[int]
    reportedRenderSettingsError: string
    benchmark: BenchmarkState

  FrameMarkers = object
    frameStart, updateStart, drawStart, uiStart, presentStart: uint64

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

proc initApplication(config: ApplicationConfig): Application =
  result.window = createWindow(
    cstring(config.appname),
    config.width.cint,
    config.height.cint,
    WINDOW_RESIZABLE or WINDOW_HIGH_PIXEL_DENSITY,
  )
  if result.window.isNil:
    raiseSdlError("Failed to create window")
  checkSdl showWindow(result.window), "Failed to show window"
  discard startTextInput(result.window)
  result.renderer = sdl3.createRenderer(result.window, cstring"gpu")
  if result.renderer.isNil:
    raiseSdlError("Failed to create renderer")
  checkSdl setRenderVSync(result.renderer, 0), "Failed to disable vsync"
  installArtist3DRenderer(result.renderer)
  installCanvasRenderer(result.renderer)
  nestDriver.installNestDriver(result.window, result.renderer)

proc parseEnvironmentInt(name: string, fallback = 0): int =
  let value = getEnv(name)
  if value.len == 0:
    return fallback
  try:
    parseInt(value)
  except ValueError:
    debugEcho "Ignoring invalid ", name, ": ", value
    fallback

proc initLoopState(): LoopState =
  result.frequency = getPerformanceFrequency()
  result.frameStepCounters =
    countersForSeconds(FixedUpdateSeconds, result.frequency)
  result.previousTime = getPerformanceCounter()
  result.nextFrameCounter = result.previousTime + result.frameStepCounters
  result.firstFrame = true
  let screenshotDelay = parseEnvironmentInt("ELLIPSE_SCREENSHOT_AFTER_MS")
  if screenshotDelay > 0:
    result.autoScreenshotAt = sdl3.getTicks() + screenshotDelay.uint64
  result.benchmark.targetFrames =
    max(parseEnvironmentInt("ELLIPSE_BENCH_FRAMES"), 0)
  for item in getEnv("ELLIPSE_SCREENSHOT_FRAMES").split(','):
    let value = item.strip()
    if value.len > 0:
      try:
        result.screenshotFrames.add parseInt(value)
      except ValueError:
        debugEcho "Ignoring invalid ELLIPSE_SCREENSHOT_FRAMES item: ", value

proc beginFrame(state: var LoopState): tuple[started: uint64, dt: float64] =
  let now = getPerformanceCounter()
  result.started = now
  result.dt = min(secondsBetween(state.previousTime, now, state.frequency),
    MaxDeltaTime)
  currentFrameDeltaSecondsValue = result.dt
  state.previousTime = now

proc pollRenderSettings(state: var LoopState, loader: var RenderSettingsLoader,
    artist: Artist3D) =
  let now = sdl3.getTicks()
  if state.lastRenderSettingsPoll != 0 and
      now - state.lastRenderSettingsPoll < 500:
    return
  state.lastRenderSettingsPoll = now
  if loader.poll():
    artist.renderSettings = loader.settings
    state.reportedRenderSettingsError = ""
    requestFrameAfter(0)
  elif loader.lastError.len > 0 and
      loader.lastError != state.reportedRenderSettingsError:
    debugEcho "Could not reload ", loader.path, ": ", loader.lastError
    state.reportedRenderSettingsError = loader.lastError

proc captureScreenshots(state: var LoopState, renderer: Renderer,
    appname: string) =
  if state.benchmark.frameCount in state.screenshotFrames:
    let path = screenshotName(appname & "-frame-" & $state.benchmark.frameCount)
    if dumpRendererScreenshot(renderer, path):
      echo "Saved screenshot: ", path
  if state.screenshotRequested:
    let path = screenshotName(appname)
    if dumpRendererScreenshot(renderer, path):
      debugEcho "Saved screenshot: ", path
    state.screenshotRequested = false

proc recordBenchmark(state: var LoopState, markers: FrameMarkers, dt: float64,
    running: var bool) =
  var benchmark = addr state.benchmark
  if benchmark.targetFrames <= 0 or state.firstFrame:
    return
  let frameEnd = getPerformanceCounter()
  inc benchmark.frameCount
  benchmark.updateSeconds += secondsBetween(
    markers.updateStart, markers.drawStart, state.frequency)
  benchmark.drawSeconds += secondsBetween(
    markers.drawStart, markers.uiStart, state.frequency)
  benchmark.uiSeconds += secondsBetween(
    markers.uiStart, markers.presentStart, state.frequency)
  benchmark.presentSeconds += secondsBetween(
    markers.presentStart, frameEnd, state.frequency)
  benchmark.frameSeconds += secondsBetween(
    markers.frameStart, frameEnd, state.frequency)
  benchmark.frameIntervalSeconds += dt
  if benchmark.frameCount < benchmark.targetFrames:
    return
  let count = benchmark.frameCount.float64
  echo "bench frames: ", benchmark.frameCount
  echo "bench fps: ", count / benchmark.frameSeconds
  echo "bench cadence fps: ", count / benchmark.frameIntervalSeconds
  echo "bench fixed update hz: ", 1.0 / FixedUpdateSeconds
  echo "bench full ui frames: ", benchmark.fullUiFrames
  echo "bench cached ui frames: ", benchmark.cachedUiFrames
  echo "bench ui due frames: ", benchmark.uiDueFrames
  echo "bench nest every frame frames: ", benchmark.nestEveryFrameFrames
  echo "bench update ms: ", benchmark.updateSeconds * 1000 / count
  echo "bench draw ms: ", benchmark.drawSeconds * 1000 / count
  echo "bench ui ms: ", benchmark.uiSeconds * 1000 / count
  echo "bench present ms: ", benchmark.presentSeconds * 1000 / count
  running = false

proc finishFrame(state: var LoopState, running: bool) =
  state.firstFrame = false
  if not running:
    return
  sleepUntilCounter(state.nextFrameCounter, state.frequency)
  let now = getPerformanceCounter()
  while state.nextFrameCounter <= now:
    state.nextFrameCounter += state.frameStepCounters

template runUpdates(dt: float64, sceneStack: var SceneStack, gui: UI,
    paused: bool) =
  generatePluginFunctionCalls(earlyUpdate)
  if sceneStack.handleLoads():
    gui.clearNestUI()
  generatePluginFunctionCalls(constantUpdate)
  if not paused:
    generatePluginFunctionCalls(update)
    generatePluginFunctionCalls(lateUpdate)

template runDraw(rendererArg: Renderer) =
  let renderer {.inject.}: Renderer = rendererArg
  checkSdl setRenderDrawColor(renderer, 12, 14, 18, 255), "Failed to set draw color"
  checkSdl renderClear(renderer), "Failed to clear renderer"
  generatePluginFunctionCalls(draw)

template nestEvent(event: sdl3.Event) =
  generatePluginFunctionCalls(nestEvent)

template runUi(gui: var UI) =
  ## UI declarations are application control flow and must remain responsive
  ## while simulation updates are paused.
  if gui.redrawDelayMs() == 0:
    gui.clearRedrawRequest()
  renderNest(gui):
    generatePluginFunctionCalls(ui)
  generatePluginFunctionCalls(postUi)

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

    var app = initApplication(appConfig)

    var gui {.inject.} = createNest()
    installNestPluginCallbacks()
    var artist {.inject.} = Artist3D.init(app.renderer)
    var renderSettingsLoader = RenderSettingsLoader.init(appConfig.renderSettingsPath)
    artist.renderSettings = renderSettingsLoader.settings
    var inputs {.inject.} = InputMap.init()
    var resources {.inject.} = ellipseResources.newResourceManager(app.renderer)

    var
      sceneStack {.inject.} = SceneStack.init()
      running {.inject.} = true
      paused {.inject.} = false

    sceneStack.loadSceneStackState()

    blk
    generatePluginFunctionCalls(load)

    var loopState = initLoopState()

    proc processEvents(): bool =
      var sdlEvent: sdl3.Event
      while pollEvent(sdlEvent):
        if sdlEvent.`type` == EVENT_QUIT:
          running = false
        elif sdlEvent.`type` == EVENT_KEY_DOWN and
            sdlEvent.key.scancode == SCANCODE_F12 and
            (sdlEvent.key.`mod`.uint32 and KMOD_CTRL) != 0:
          loopState.screenshotRequested = true
          requestFrameAfter(0)
        result = handleNestEvent(gui, sdlEvent) or result
        if not nestBlocksInputEvent(
            gui, sdlEvent, loopState.blockedMouseButtons):
          inputs.handleEvent(sdlEvent)
        let event {.inject.} = sdlEvent
        generatePluginFunctionCalls(event)

    proc maintainRuntime(nestInputDue: bool) =
      discard pollDynamicPluginWatchers()
      let
        buildStarted = processDynamicPluginReloads()
        buildFinished = pollDynamicPluginBuilds()
      discard hasActiveDynamicPluginBuilds()
      if loopState.autoScreenshotAt > 0 and
          sdl3.getTicks() >= loopState.autoScreenshotAt:
        loopState.screenshotRequested = true
        loopState.autoScreenshotAt = 0
      if buildStarted or buildFinished:
        gui.markAllDirty()
      discard consumeRuntimeFrameRequest()
      let nestEveryFrame = consumeNestEveryFrameRequest()
      discard consumeApplicationRedraw(getPerformanceCounter())
      if loopState.benchmark.targetFrames > 0 and not loopState.firstFrame:
        if gui.redrawDelayMs() == 0:
          inc loopState.benchmark.uiDueFrames
        if nestEveryFrame or nestInputDue:
          inc loopState.benchmark.nestEveryFrameFrames
      if hasReadyDynamicPluginReloads():
        generatePluginFunctionCalls(preReload)
        if activateReadyDynamicPluginReloads():
          generatePluginFunctionCalls(afterReload)
          gui.markAllDirty()

    while running:
      gui.beginInputFrame()
      sceneStack.handlePushed()
      let nestInputDue = processEvents()
      if not running:
        gui.finishInputFrame()
        break
      maintainRuntime(nestInputDue)

      let frame = loopState.beginFrame()
      let dt {.inject.} = frame.dt
      loopState.pollRenderSettings(renderSettingsLoader, artist)
      resources.poll()
      if gui.wantsTextInput():
        inputs.maskKeyboardInput()
      var markers = FrameMarkers(
        frameStart: frame.started,
        updateStart: getPerformanceCounter(),
      )
      runUpdates(dt, sceneStack, gui, paused)
      sceneStack.handleUnloads()

      markers.drawStart = getPerformanceCounter()
      runDraw(app.renderer)
      markers.uiStart = getPerformanceCounter()
      runUi(gui)
      if loopState.benchmark.targetFrames > 0 and not loopState.firstFrame:
        inc loopState.benchmark.fullUiFrames

      discard gui.drawRealtime()
      renderNestDynamicTexts(gui)
      markers.presentStart = getPerformanceCounter()
      loopState.captureScreenshots(app.renderer, appConfig.appname)
      checkSdl renderPresent(app.renderer), "Failed to present renderer"
      loopState.recordBenchmark(markers, dt, running)
      gui.finishInputFrame()
      inputs.finishFrame()
      loopState.finishFrame(running)
