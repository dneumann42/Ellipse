import sdl3
import plugnim
export plugnim

import errors

const
  MaxDeltaTime = 0.25'f64
  TargetFps = 60.0'f64
  TargetFrameTime = 1.0'f64 / TargetFps
  SecondsToNanoseconds = 1_000_000_000.0'f64

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

proc raiseError(context: string) {.noreturn.} =
  raise SDLException.newException(context & ": " & $sdl3.getError())

template attempt(succ: bool, context: string) =
  if not succ:
    raiseError(context)

proc secondsBetween(startCounter, endCounter, frequency: uint64): float64 =
  float64(endCounter - startCounter) / float64(frequency)

template update(dt: float64) =
  generatePluginFunctionCalls(update)

template draw(renderer: Renderer) =
  attempt setRenderDrawColor(renderer, 12, 14, 18, 255), "Failed to set draw color"
  attempt renderClear(renderer), "Failed to clear renderer"
  generatePluginFunctionCalls(draw)
  attempt renderPresent(renderer), "Failed to present renderer"

template sdlApplication(events, step) =
  let frequency = getPerformanceFrequency()
  var
    running {.inject.} = true
    previousTime = getPerformanceCounter()
    event: Event
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
    let elapsed = secondsBetween(frameStart, getPerformanceCounter(), frequency)
    if elapsed < TargetFrameTime:
      delayPrecise(uint64((TargetFrameTime - elapsed) * SecondsToNanoseconds))

template buildApplication*() =
  generatePluginContext()
  proc start() =
    if not sdl3.init(INIT_VIDEO or INIT_AUDIO or INIT_GAMEPAD):
      raiseError("Failed to initialize SDL")
    defer:
      sdl3.quit()

    var app = Application()
    app.window =
      createWindow("Ellipse", 1280, 720, WINDOW_RESIZABLE or WINDOW_HIGH_PIXEL_DENSITY)
    if app.window.isNil:
      raiseError("Failed to create window")
    app.renderer = sdl3.createRenderer(app.window, nil)
    if app.renderer.isNil:
      raiseError("Failed to create renderer")
    attempt setRenderVSync(app.renderer, 1), "Failed to enable vsync"

    generatePluginFunctionCalls(load)

    sdlApplication:
      discard
    do:
      update(dt)
      draw(app.renderer)
