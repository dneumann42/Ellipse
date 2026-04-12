import os
import ellipse/platform/SDL3

type
  DemoState = object
    window: ptr SDL_Window
    renderer: ptr SDL_Renderer

proc sdlError(prefix: string): string =
  prefix & ": " & $SDL_GetError()

proc SDL_AppInit(appState: ptr pointer; argc: cint; argv: cstringArray): SDL_AppResult {.
  exportc,
  cdecl
.} =
  discard argc
  discard argv

  if not SDL_SetAppMetadata("Ellipse SDL3 Hello", "0.0.0", "dev.ellipse.tests.sdl3hello"):
    stderr.writeLine sdlError("SDL_SetAppMetadata failed")
    return SDL_APP_FAILURE

  if not SDL_Init(SDL_INIT_VIDEO):
    stderr.writeLine sdlError("SDL_Init failed")
    return SDL_APP_FAILURE

  let state = create(DemoState)
  state.window = SDL_CreateWindow("Ellipse SDL3 Hello", 800, 600, 0)
  if state.window.isNil:
    stderr.writeLine sdlError("SDL_CreateWindow failed")
    dealloc(state)
    SDL_Quit()
    return SDL_APP_FAILURE

  state.renderer = SDL_CreateRenderer(state.window, nil)
  if state.renderer.isNil:
    stderr.writeLine sdlError("SDL_CreateRenderer failed")
    SDL_DestroyWindow(state.window)
    dealloc(state)
    SDL_Quit()
    return SDL_APP_FAILURE

  if not SDL_SetRenderDrawColor(state.renderer, 24'u8, 34'u8, 48'u8, 255'u8):
    stderr.writeLine sdlError("SDL_SetRenderDrawColor failed")
    SDL_DestroyRenderer(state.renderer)
    SDL_DestroyWindow(state.window)
    dealloc(state)
    SDL_Quit()
    return SDL_APP_FAILURE

  if not SDL_RenderClear(state.renderer):
    stderr.writeLine sdlError("SDL_RenderClear failed")
    SDL_DestroyRenderer(state.renderer)
    SDL_DestroyWindow(state.window)
    dealloc(state)
    SDL_Quit()
    return SDL_APP_FAILURE

  if not SDL_RenderPresent(state.renderer):
    stderr.writeLine sdlError("SDL_RenderPresent failed")
    SDL_DestroyRenderer(state.renderer)
    SDL_DestroyWindow(state.window)
    dealloc(state)
    SDL_Quit()
    return SDL_APP_FAILURE

  appState[] = cast[pointer](state)
  SDL_APP_CONTINUE

proc SDL_AppIterate(appState: pointer): SDL_AppResult {.exportc, cdecl.} =
  let state = cast[ptr DemoState](appState)

  if not SDL_RenderClear(state.renderer):
    stderr.writeLine sdlError("SDL_RenderClear failed")
    return SDL_APP_FAILURE

  if not SDL_RenderPresent(state.renderer):
    stderr.writeLine sdlError("SDL_RenderPresent failed")
    return SDL_APP_FAILURE

  SDL_APP_CONTINUE

proc SDL_AppEvent(appState: pointer; event: ptr SDL_Event): SDL_AppResult {.exportc, cdecl.} =
  discard appState

  case event[].`type`
  of SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    SDL_APP_SUCCESS
  else:
    SDL_APP_CONTINUE

proc SDL_AppQuit(appState: pointer; result: SDL_AppResult) {.exportc, cdecl.} =
  discard result

  if not appState.isNil:
    let state = cast[ptr DemoState](appState)
    if not state.renderer.isNil:
      SDL_DestroyRenderer(state.renderer)
    if not state.window.isNil:
      SDL_DestroyWindow(state.window)
    dealloc(state)

  SDL_Quit()

when isMainModule:
  var args = newSeq[string](1 + paramCount())
  args[0] = getAppFilename()
  for i, value in commandLineParams():
    args[i + 1] = value

  var cArgs = newSeq[cstring](args.len)
  for i, value in args:
    cArgs[i] = value.cstring

  quit SDL_EnterAppMainCallbacks(
    cint(cArgs.len),
    cast[cstringArray](addr cArgs[0]),
    SDL_AppInit,
    SDL_AppIterate,
    SDL_AppEvent,
    SDL_AppQuit
  )
