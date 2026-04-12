{.passL: "-lSDL3".}

type
  SDL_InitFlags* = uint32
  SDL_WindowFlags* = uint64
  SDL_EventType* = uint32

  SDL_AppResult* {.size: sizeof(cint), importc: "SDL_AppResult", header: "<SDL3/SDL_init.h>".} = enum
    SDL_APP_CONTINUE = 0
    SDL_APP_SUCCESS = 1
    SDL_APP_FAILURE = 2

  SDL_Window* {.importc: "SDL_Window", header: "<SDL3/SDL_video.h>", incompleteStruct.} = object
  SDL_Renderer* {.importc: "SDL_Renderer", header: "<SDL3/SDL_render.h>", incompleteStruct.} = object

  SDL_Event* {.importc: "SDL_Event", header: "<SDL3/SDL_events.h>", union, bycopy.} = object
    `type`*: SDL_EventType
    padding*: array[128, byte]

  SDL_AppInitFunc* = proc(appState: ptr pointer; argc: cint; argv: cstringArray): SDL_AppResult {.cdecl.}
  SDL_AppIterateFunc* = proc(appState: pointer): SDL_AppResult {.cdecl.}
  SDL_AppEventFunc* = proc(appState: pointer; event: ptr SDL_Event): SDL_AppResult {.cdecl.}
  SDL_AppQuitFunc* = proc(appState: pointer; result: SDL_AppResult) {.cdecl.}

const
  SDL_INIT_VIDEO* = 0x00000020'u32

  SDL_EVENT_QUIT* = 0x00000100'u32
  SDL_EVENT_WINDOW_CLOSE_REQUESTED* = 0x00000210'u32

proc SDL_SetAppMetadata*(
  appName: cstring,
  appVersion: cstring,
  appIdentifier: cstring
): bool {.importc, header: "<SDL3/SDL_init.h>".}

proc SDL_Init*(flags: SDL_InitFlags): bool {.
  importc: "SDL_Init",
  header: "<SDL3/SDL_init.h>"
.}

proc SDL_Quit*() {.
  importc: "SDL_Quit",
  header: "<SDL3/SDL_init.h>"
.}

proc SDL_CreateWindow*(
  title: cstring,
  w: cint,
  h: cint,
  flags: SDL_WindowFlags
): ptr SDL_Window {.
  importc: "SDL_CreateWindow",
  header: "<SDL3/SDL_video.h>"
.}

proc SDL_DestroyWindow*(window: ptr SDL_Window) {.
  importc: "SDL_DestroyWindow",
  header: "<SDL3/SDL_video.h>"
.}

proc SDL_CreateRenderer*(
  window: ptr SDL_Window,
  name: cstring
): ptr SDL_Renderer {.
  importc: "SDL_CreateRenderer",
  header: "<SDL3/SDL_render.h>"
.}

proc SDL_DestroyRenderer*(renderer: ptr SDL_Renderer) {.
  importc: "SDL_DestroyRenderer",
  header: "<SDL3/SDL_render.h>"
.}

proc SDL_SetRenderDrawColor*(
  renderer: ptr SDL_Renderer,
  r, g, b, a: uint8
): bool {.
  importc: "SDL_SetRenderDrawColor",
  header: "<SDL3/SDL_render.h>"
.}

proc SDL_RenderClear*(renderer: ptr SDL_Renderer): bool {.
  importc: "SDL_RenderClear",
  header: "<SDL3/SDL_render.h>"
.}

proc SDL_RenderPresent*(renderer: ptr SDL_Renderer): bool {.
  importc: "SDL_RenderPresent",
  header: "<SDL3/SDL_render.h>"
.}

proc SDL_GetError*(): cstring {.
  importc: "SDL_GetError",
  header: "<SDL3/SDL_error.h>"
.}

proc SDL_EnterAppMainCallbacks*(
  argc: cint,
  argv: cstringArray,
  appInit: SDL_AppInitFunc,
  appIterate: SDL_AppIterateFunc,
  appEvent: SDL_AppEventFunc,
  appQuit: SDL_AppQuitFunc
): cint {.
  importc: "SDL_EnterAppMainCallbacks",
  header: "<SDL3/SDL_main.h>"
.}
