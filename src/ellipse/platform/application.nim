import std/[macros]
import ../plugins
import ./SDL3
import ./SDL3ext

export macros, plugins, SDL3, SDL3ext

{.push raises: [].}

type
  AppConfig* = object
    appId*: string
    title*: string
    width*: int
    height*: int
    windowFlags*: WindowFlags

  Application*[T] = object
    config*: AppConfig
    pluginStates*: PluginStates
    messages*: PluginMessages
    scenes*: SceneStack
    quitRequested*: bool
    state*: T
    sdl: AppHandle
    window: WindowHandle
    renderer: RendererHandle

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
      gApplication.sdl = SDL3ext.init(INIT_VIDEO)
      gApplication.window = SDL3ext.createWindow(
        gApplication.config.title,
        gApplication.config.width,
        gApplication.config.height,
        gApplication.config.windowFlags
      )
      gApplication.renderer = SDL3ext.createRenderer(gApplication.window)
    except Error as err:
      flushStderr(err.msg)
      gApplication.destroyApplication()
      return appFailure

    generatePluginStateInitialize(gApplication.pluginStates)

    var
      scenes {.inject.} = gApplication.scenes
      pluginStates {.inject.} = gApplication.pluginStates
      messages {.inject.} = gApplication.messages
      window {.inject.} = raw(gApplication.window)
      renderer {.inject.} = raw(gApplication.renderer)
      quit {.inject.} = gApplication.quitRequested

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
      window {.inject.} = raw(app.window)
      renderer {.inject.} = raw(app.renderer)
      quit {.inject.} = app.quitRequested

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

    if not setRenderDrawColor(raw(app.renderer), 0'u8, 0'u8, 0'u8, 255'u8):
      flushStderr(sdlError("setRenderDrawColor failed"))
      return appFailure

    if not renderClear(raw(app.renderer)):
      flushStderr(sdlError("renderClear failed"))
      return appFailure

    block:
      var
        pluginStates {.inject.} = app.pluginStates
        messages {.inject.} = app.messages
        scenes {.inject.} = app.scenes
        window {.inject.} = raw(app.window)
        renderer {.inject.} = raw(app.renderer)
        quit {.inject.} = app.quitRequested

      withFields(app.state, app):
        try:
          generatePluginStep(draw)
        except CatchableError as err:
          reportException("application draw failed", err)
          return appFailure

      app.pluginStates = pluginStates
      app.messages = messages
      app.scenes = scenes
      app.quitRequested = quit

    if not renderPresent(raw(app.renderer)):
      flushStderr(sdlError("renderPresent failed"))
      return appFailure

    appContinue

  proc eventCallback(appState: pointer; event: ptr Event): AppResult {.cdecl.} =
    let app = cast[ref Application[T]](appState)

    case event[].`type`
    of EVENT_QUIT, EVENT_WINDOW_CLOSE_REQUESTED:
      app.quitRequested = true
      appSuccess
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
