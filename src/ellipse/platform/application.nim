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

  AppState*[T] = object
    config*: AppConfig
    sdl*: AppHandle
    window*: WindowHandle
    renderer*: RendererHandle
    pluginStates*: PluginStates
    messages*: PluginMessages
    scenes*: SceneStack
    quitRequested*: bool
    state*: T

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

proc destroyAppState[T](state: ref AppState[T]) =
  if state.isNil:
    return
  reset(state[])

template generateApplication[T](cfg: AppConfig, initialState: T): untyped =
  var gAppState {.global.}: ref AppState[T]

  proc appInitCallback(
    appState: ptr pointer,
    argc: cint,
    argv: cstringArray
  ): AppResult {.cdecl, gcsafe.} =
    discard argc
    discard argv

    new(gAppState)
    gAppState[] = AppState[T](
      config: cfg,
      messages: PluginMessages.init(),
      scenes: SceneStack.new(),
      state: initialState
    )

    appState[] = cast[pointer](gAppState)

    if not setAppMetadata(
      gAppState.config.title.cstring,
      "0.0.0",
      gAppState.config.appId.cstring
    ):
      flushStderr(sdlError("setAppMetadata failed"))
      gAppState.destroyAppState()
      return appFailure

    try:
      gAppState.sdl = init(INIT_VIDEO)
      gAppState.window = createWindow(
        gAppState.config.title,
        gAppState.config.width,
        gAppState.config.height,
        gAppState.config.windowFlags
      )
      gAppState.renderer = createRenderer(gAppState.window)
    except Error as err:
      flushStderr(err.msg)
      gAppState.destroyAppState()
      return appFailure

    generatePluginStateInitialize(gAppState.pluginStates)

    var
      scenes {.inject.} = gAppState.scenes
      pluginStates {.inject.} = gAppState.pluginStates
      messages {.inject.} = gAppState.messages
      window {.inject.} = raw(gAppState.window)
      renderer {.inject.} = raw(gAppState.renderer)
      quit {.inject.} = gAppState.quitRequested

    withFields(gAppState.state, gAppState):
      try:
        generatePluginStep(load)
      except CatchableError as err:
        reportException("application load failed", err)
        gAppState.destroyAppState()
        return appFailure

    gAppState.scenes = scenes
    gAppState.pluginStates = pluginStates
    gAppState.messages = messages
    gAppState.quitRequested = quit

    appContinue

  proc iterateCallback(appState: pointer): AppResult {.cdecl, gcsafe.} =
    let state = cast[ref AppState[T]](appState)

    var
      scenes {.inject.} = state.scenes
      pluginStates {.inject.} = state.pluginStates
      messages {.inject.} = state.messages
      window {.inject.} = raw(state.window)
      renderer {.inject.} = raw(state.renderer)
      quit {.inject.} = state.quitRequested

    scenes.startFrame()
    scenes.handlePushed()

    withFields(state.state, state):
      try:
        generatePluginStep(loadScene)
        generateListenStep(messages)
        generatePluginStep(update)
        generatePluginStep(alwaysUpdate)
      except CatchableError as err:
        reportException("application update failed", err)
        return appFailure

    state.scenes = scenes
    state.pluginStates = pluginStates
    state.messages = messages
    state.quitRequested = quit

    if state.quitRequested:
      return appSuccess

    if not setRenderDrawColor(raw(state.renderer), 0'u8, 0'u8, 0'u8, 255'u8):
      flushStderr(sdlError("setRenderDrawColor failed"))
      return appFailure

    if not renderClear(raw(state.renderer)):
      flushStderr(sdlError("renderClear failed"))
      return appFailure

    var
      pluginStates {.inject.} = state.pluginStates
      messages {.inject.} = state.messages
      scenes {.inject.} = state.scenes
      window {.inject.} = raw(state.window)
      renderer {.inject.} = raw(state.renderer)
      quit {.inject.} = state.quitRequested

    withFields(state.state, state):
      try:
        generatePluginStep(draw)
      except CatchableError as err:
        reportException("application draw failed", err)
        return appFailure

    state.pluginStates = pluginStates
    state.messages = messages
    state.scenes = scenes
    state.quitRequested = quit

    if not renderPresent(raw(state.renderer)):
      flushStderr(sdlError("renderPresent failed"))
      return appFailure

    appContinue

  proc eventCallback(appState: pointer; event: ptr Event): AppResult {.cdecl, gcsafe.} =
    let state = cast[ref AppState[T]](appState)

    case event[].`type`
    of EVENT_QUIT, EVENT_WINDOW_CLOSE_REQUESTED:
      state.quitRequested = true
      appSuccess
    else:
      appContinue

  proc quitCallback(appState: pointer; result: AppResult) {.cdecl, gcsafe.} =
    discard result

    let state =
      if appState.isNil:
        gAppState
      else:
        cast[ref AppState[T]](appState)

    state.destroyAppState()
    gAppState = nil

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
