import std/[macros]
import ../plugins
import ./SDL3

export macros, plugins, SDL3

{.push raises: [].}

type
  AppConfig* = object
    appId*: string
    title*: string
    width*: int
    height*: int
    windowFlags*: SDL_WindowFlags

  AppState*[T] = object
    config*: AppConfig
    window*: ptr SDL_Window
    renderer*: ptr SDL_Renderer
    pluginStates*: PluginStates
    messages*: PluginMessages
    scenes*: SceneStack
    quitRequested*: bool
    state*: T

template sdlError(prefix: string): string =
  prefix & ": " & $SDL_GetError()

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

  if not state.renderer.isNil:
    SDL_DestroyRenderer(state.renderer)
    state.renderer = nil

  if not state.window.isNil:
    SDL_DestroyWindow(state.window)
    state.window = nil

  SDL_Quit()

template generateApplication[T](cfg: AppConfig, initialState: T): untyped =
  var gAppState {.global.}: ref AppState[T]

  proc SDL_AppInit(
    appState: ptr pointer,
    argc: cint,
    argv: cstringArray
  ): SDL_AppResult {.cdecl, gcsafe.} =
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

    if not SDL_SetAppMetadata(
      gAppState.config.title.cstring,
      "0.0.0",
      gAppState.config.appId.cstring
    ):
      flushStderr(sdlError("SDL_SetAppMetadata failed"))
      gAppState.destroyAppState()
      return SDL_APP_FAILURE

    if not SDL_Init(SDL_INIT_VIDEO):
      flushStderr(sdlError("SDL_Init failed"))
      gAppState.destroyAppState()
      return SDL_APP_FAILURE

    gAppState.window = SDL_CreateWindow(
      gAppState.config.title.cstring,
      cint(gAppState.config.width),
      cint(gAppState.config.height),
      gAppState.config.windowFlags
    )
    if gAppState.window.isNil:
      flushStderr(sdlError("SDL_CreateWindow failed"))
      gAppState.destroyAppState()
      return SDL_APP_FAILURE

    gAppState.renderer = SDL_CreateRenderer(gAppState.window, nil)
    if gAppState.renderer.isNil:
      flushStderr(sdlError("SDL_CreateRenderer failed"))
      gAppState.destroyAppState()
      return SDL_APP_FAILURE

    generatePluginStateInitialize(gAppState.pluginStates)

    var
      scenes {.inject.} = gAppState.scenes
      pluginStates {.inject.} = gAppState.pluginStates
      messages {.inject.} = gAppState.messages
      window {.inject.} = gAppState.window
      renderer {.inject.} = gAppState.renderer
      quit {.inject.} = gAppState.quitRequested

    withFields(gAppState.state, gAppState):
      try:
        generatePluginStep(load)
      except CatchableError as err:
        reportException("application load failed", err)
        gAppState.destroyAppState()
        return SDL_APP_FAILURE

    gAppState.scenes = scenes
    gAppState.pluginStates = pluginStates
    gAppState.messages = messages
    gAppState.quitRequested = quit

    SDL_APP_CONTINUE

  proc SDL_AppIterate(appState: pointer): SDL_AppResult {.cdecl, gcsafe.} =
    let state = cast[ref AppState[T]](appState)

    var
      scenes {.inject.} = state.scenes
      pluginStates {.inject.} = state.pluginStates
      messages {.inject.} = state.messages
      window {.inject.} = state.window
      renderer {.inject.} = state.renderer
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
        return SDL_APP_FAILURE

    state.scenes = scenes
    state.pluginStates = pluginStates
    state.messages = messages
    state.quitRequested = quit

    if state.quitRequested:
      return SDL_APP_SUCCESS

    if not SDL_SetRenderDrawColor(state.renderer, 0'u8, 0'u8, 0'u8, 255'u8):
      flushStderr(sdlError("SDL_SetRenderDrawColor failed"))
      return SDL_APP_FAILURE

    if not SDL_RenderClear(state.renderer):
      flushStderr(sdlError("SDL_RenderClear failed"))
      return SDL_APP_FAILURE

    var
      pluginStates {.inject.} = state.pluginStates
      messages {.inject.} = state.messages
      scenes {.inject.} = state.scenes
      window {.inject.} = state.window
      renderer {.inject.} = state.renderer
      quit {.inject.} = state.quitRequested

    withFields(state.state, state):
      try:
        generatePluginStep(draw)
      except CatchableError as err:
        reportException("application draw failed", err)
        return SDL_APP_FAILURE

    state.pluginStates = pluginStates
    state.messages = messages
    state.scenes = scenes
    state.quitRequested = quit

    if not SDL_RenderPresent(state.renderer):
      flushStderr(sdlError("SDL_RenderPresent failed"))
      return SDL_APP_FAILURE

    SDL_APP_CONTINUE

  proc SDL_AppEvent(appState: pointer; event: ptr SDL_Event): SDL_AppResult {.cdecl, gcsafe.} =
    let state = cast[ref AppState[T]](appState)

    case event[].`type`
    of SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      state.quitRequested = true
      SDL_APP_SUCCESS
    else:
      SDL_APP_CONTINUE

  proc SDL_AppQuit(appState: pointer; result: SDL_AppResult) {.cdecl, gcsafe.} =
    discard result

    let state =
      if appState.isNil:
        gAppState
      else:
        cast[ref AppState[T]](appState)

    state.destroyAppState()
    gAppState = nil

  discard SDL_EnterAppMainCallbacks(
    0,
    nil,
    SDL_AppInit,
    SDL_AppIterate,
    SDL_AppEvent,
    SDL_AppQuit
  )

template startApplication*[T](config: AppConfig, initialState: T): untyped =
  generateApplication(config, initialState)
