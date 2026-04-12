{.passL: "-lSDL3".}

type
  InitFlags* = uint32
  WindowFlags* = uint64
  EventType* = uint32
  PixelFormat* = uint32
  PropertiesID* = uint32
  AudioFormat* = uint16
  AudioDeviceID* = uint32
  WindowID* = uint32
  KeyboardID* = uint32
  MouseID* = uint32
  Keycode* = uint32
  Keymod* = uint16
  MouseButtonFlags* = uint32

  Scancode* {.size: sizeof(cint), importc: "SDL_Scancode", header: "<SDL3/SDL_scancode.h>".} = enum
    scancodeUnknown = 0

  MouseWheelDirection* {.size: sizeof(cint), importc: "SDL_MouseWheelDirection", header: "<SDL3/SDL_mouse.h>".} = enum
    mouseWheelNormal = 0
    mouseWheelFlipped = 1

  TextureAccess* {.size: sizeof(cint), importc: "SDL_TextureAccess", header: "<SDL3/SDL_render.h>".} = enum
    textureAccessStatic = 0
    textureAccessStreaming = 1
    textureAccessTarget = 2

  AppResult* {.size: sizeof(cint), importc: "SDL_AppResult", header: "<SDL3/SDL_init.h>".} = enum
    appContinue = 0
    appSuccess = 1
    appFailure = 2

  Window* {.importc: "SDL_Window", header: "<SDL3/SDL_video.h>", incompleteStruct.} = object
  Renderer* {.importc: "SDL_Renderer", header: "<SDL3/SDL_render.h>", incompleteStruct.} = object
  Texture* {.importc: "SDL_Texture", header: "<SDL3/SDL_render.h>", incompleteStruct.} = object
  Surface* {.importc: "SDL_Surface", header: "<SDL3/SDL_surface.h>", incompleteStruct.} = object
  IOStream* {.importc: "SDL_IOStream", header: "<SDL3/SDL_iostream.h>", incompleteStruct.} = object
  AudioStream* {.importc: "SDL_AudioStream", header: "<SDL3/SDL_audio.h>", incompleteStruct.} = object

  Color* {.importc: "SDL_Color", header: "<SDL3/SDL_pixels.h>", bycopy.} = object
    r*, g*, b*, a*: uint8

  Palette* {.importc: "SDL_Palette", header: "<SDL3/SDL_pixels.h>", bycopy.} = object
    ncolors*: cint
    colors*: ptr Color
    version*: uint32
    refcount*: cint

  AudioSpec* {.importc: "SDL_AudioSpec", header: "<SDL3/SDL_audio.h>", bycopy.} = object
    format*: AudioFormat
    channels*: cint
    freq*: cint

  KeyboardEvent* {.importc: "SDL_KeyboardEvent", header: "<SDL3/SDL_events.h>", bycopy.} = object
    `type`*: EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: WindowID
    which*: KeyboardID
    scancode*: Scancode
    key*: Keycode
    `mod`*: Keymod
    raw*: uint16
    down*: bool
    repeat*: bool

  TextInputEvent* {.importc: "SDL_TextInputEvent", header: "<SDL3/SDL_events.h>", bycopy.} = object
    `type`*: EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: WindowID
    text*: cstring

  MouseMotionEvent* {.importc: "SDL_MouseMotionEvent", header: "<SDL3/SDL_events.h>", bycopy.} = object
    `type`*: EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: WindowID
    which*: MouseID
    state*: MouseButtonFlags
    x*: cfloat
    y*: cfloat
    xrel*: cfloat
    yrel*: cfloat

  MouseButtonEvent* {.importc: "SDL_MouseButtonEvent", header: "<SDL3/SDL_events.h>", bycopy.} = object
    `type`*: EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: WindowID
    which*: MouseID
    button*: uint8
    down*: bool
    clicks*: uint8
    padding1*: uint8
    x*: cfloat
    y*: cfloat

  MouseWheelEvent* {.importc: "SDL_MouseWheelEvent", header: "<SDL3/SDL_events.h>", bycopy.} = object
    `type`*: EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: WindowID
    which*: MouseID
    x*: cfloat
    y*: cfloat
    direction*: MouseWheelDirection
    mouse_x*: cfloat
    mouse_y*: cfloat
    integer_x*: cint
    integer_y*: cint

  Event* {.importc: "SDL_Event", header: "<SDL3/SDL_events.h>", union, bycopy.} = object
    `type`*: EventType
    key*: KeyboardEvent
    text*: TextInputEvent
    motion*: MouseMotionEvent
    button*: MouseButtonEvent
    wheel*: MouseWheelEvent
    padding*: array[128, byte]

  AppInitFunc* = proc(appState: ptr pointer; argc: cint; argv: cstringArray): AppResult {.cdecl.}
  AppIterateFunc* = proc(appState: pointer): AppResult {.cdecl.}
  AppEventFunc* = proc(appState: pointer; event: ptr Event): AppResult {.cdecl.}
  AppQuitFunc* = proc(appState: pointer; result: AppResult) {.cdecl.}

const
  INIT_VIDEO* = 0x00000020'u32
  INIT_AUDIO* = 0x00000010'u32

  WINDOW_RESIZABLE* = 0x0000000000000020'u64

  EVENT_QUIT* = 0x00000100'u32
  EVENT_KEY_DOWN* = 0x00000300'u32
  EVENT_KEY_UP* = 0x00000301'u32
  EVENT_TEXT_INPUT* = 0x00000303'u32
  EVENT_MOUSE_MOTION* = 0x00000400'u32
  EVENT_MOUSE_BUTTON_DOWN* = 0x00000401'u32
  EVENT_MOUSE_BUTTON_UP* = 0x00000402'u32
  EVENT_MOUSE_WHEEL* = 0x00000403'u32
  EVENT_WINDOW_CLOSE_REQUESTED* = 0x00000210'u32

  PIXELFORMAT_UNKNOWN* = 0x00000000'u32
  PIXELFORMAT_RGBA8888* = 0x16462004'u32

  AUDIO_DEVICE_DEFAULT_PLAYBACK* = 0xFFFFFFFF'u32
  AUDIO_DEVICE_DEFAULT_RECORDING* = 0xFFFFFFFE'u32
  AUDIO_S16LE* = 0x8010'u16
  SDLK_1* = 0x00000031'u32
  SDLK_2* = 0x00000032'u32
  SDLK_3* = 0x00000033'u32
  SDLK_4* = 0x00000034'u32
  SCANCODE_1* = 30
  SCANCODE_2* = 31
  SCANCODE_3* = 32
  SCANCODE_4* = 33
  SCANCODE_RETURN* = 40
  SCANCODE_BACKSPACE* = 42
  SCANCODE_TAB* = 43
  BUTTON_LEFT* = 1'u8
  BUTTON_RIGHT* = 3'u8

proc setAppMetadata*(
  appName: cstring,
  appVersion: cstring,
  appIdentifier: cstring
): bool {.importc: "SDL_SetAppMetadata", header: "<SDL3/SDL_init.h>".}

proc init*(flags: InitFlags): bool {.
  importc: "SDL_Init",
  header: "<SDL3/SDL_init.h>"
.}

proc quit*() {.
  importc: "SDL_Quit",
  header: "<SDL3/SDL_init.h>"
.}

proc createWindow*(
  title: cstring,
  w: cint,
  h: cint,
  flags: WindowFlags
): ptr Window {.
  importc: "SDL_CreateWindow",
  header: "<SDL3/SDL_video.h>"
.}

proc getWindowSizeInPixels*(
  window: ptr Window,
  w: ptr cint,
  h: ptr cint
): bool {.
  importc: "SDL_GetWindowSizeInPixels",
  header: "<SDL3/SDL_video.h>"
.}

proc getWindowSize*(
  window: ptr Window,
  w: ptr cint,
  h: ptr cint
): bool {.
  importc: "SDL_GetWindowSize",
  header: "<SDL3/SDL_video.h>"
.}

proc destroyWindow*(window: ptr Window) {.
  importc: "SDL_DestroyWindow",
  header: "<SDL3/SDL_video.h>"
.}

proc createRenderer*(
  window: ptr Window,
  name: cstring
): ptr Renderer {.
  importc: "SDL_CreateRenderer",
  header: "<SDL3/SDL_render.h>"
.}

proc destroyRenderer*(renderer: ptr Renderer) {.
  importc: "SDL_DestroyRenderer",
  header: "<SDL3/SDL_render.h>"
.}

proc createTexture*(
  renderer: ptr Renderer,
  format: PixelFormat,
  access: TextureAccess,
  w: cint,
  h: cint
): ptr Texture {.
  importc: "SDL_CreateTexture",
  header: "<SDL3/SDL_render.h>"
.}

proc createTextureFromSurface*(
  renderer: ptr Renderer,
  surface: ptr Surface
): ptr Texture {.
  importc: "SDL_CreateTextureFromSurface",
  header: "<SDL3/SDL_render.h>"
.}

proc createTextureWithProperties*(
  renderer: ptr Renderer,
  props: PropertiesID
): ptr Texture {.
  importc: "SDL_CreateTextureWithProperties",
  header: "<SDL3/SDL_render.h>"
.}

proc destroyTexture*(texture: ptr Texture) {.
  importc: "SDL_DestroyTexture",
  header: "<SDL3/SDL_render.h>"
.}

proc createSurface*(
  width: cint,
  height: cint,
  format: PixelFormat
): ptr Surface {.
  importc: "SDL_CreateSurface",
  header: "<SDL3/SDL_surface.h>"
.}

proc destroySurface*(surface: ptr Surface) {.
  importc: "SDL_DestroySurface",
  header: "<SDL3/SDL_surface.h>"
.}

proc loadSurface*(file: cstring): ptr Surface {.
  importc: "SDL_LoadSurface",
  header: "<SDL3/SDL_surface.h>"
.}

proc loadBmp*(file: cstring): ptr Surface {.
  importc: "SDL_LoadBMP",
  header: "<SDL3/SDL_surface.h>"
.}

proc createPalette*(ncolors: cint): ptr Palette {.
  importc: "SDL_CreatePalette",
  header: "<SDL3/SDL_pixels.h>"
.}

proc destroyPalette*(palette: ptr Palette) {.
  importc: "SDL_DestroyPalette",
  header: "<SDL3/SDL_pixels.h>"
.}

proc createProperties*(): PropertiesID {.
  importc: "SDL_CreateProperties",
  header: "<SDL3/SDL_properties.h>"
.}

proc destroyProperties*(props: PropertiesID) {.
  importc: "SDL_DestroyProperties",
  header: "<SDL3/SDL_properties.h>"
.}

proc ioFromFile*(file: cstring, mode: cstring): ptr IOStream {.
  importc: "SDL_IOFromFile",
  header: "<SDL3/SDL_iostream.h>"
.}

proc closeIO*(context: ptr IOStream): bool {.
  importc: "SDL_CloseIO",
  header: "<SDL3/SDL_iostream.h>"
.}

proc openAudioDevice*(
  devid: AudioDeviceID,
  spec: ptr AudioSpec
): AudioDeviceID {.
  importc: "SDL_OpenAudioDevice",
  header: "<SDL3/SDL_audio.h>"
.}

proc closeAudioDevice*(devid: AudioDeviceID) {.
  importc: "SDL_CloseAudioDevice",
  header: "<SDL3/SDL_audio.h>"
.}

proc createAudioStream*(
  srcSpec: ptr AudioSpec,
  dstSpec: ptr AudioSpec
): ptr AudioStream {.
  importc: "SDL_CreateAudioStream",
  header: "<SDL3/SDL_audio.h>"
.}

proc destroyAudioStream*(stream: ptr AudioStream) {.
  importc: "SDL_DestroyAudioStream",
  header: "<SDL3/SDL_audio.h>"
.}

proc loadWav*(
  path: cstring,
  spec: ptr AudioSpec,
  audioBuf: ptr ptr uint8,
  audioLen: ptr uint32
): bool {.
  importc: "SDL_LoadWAV",
  header: "<SDL3/SDL_audio.h>"
.}

proc setRenderDrawColor*(
  renderer: ptr Renderer,
  r, g, b, a: uint8
): bool {.
  importc: "SDL_SetRenderDrawColor",
  header: "<SDL3/SDL_render.h>"
.}

proc renderClear*(renderer: ptr Renderer): bool {.
  importc: "SDL_RenderClear",
  header: "<SDL3/SDL_render.h>"
.}

proc renderPresent*(renderer: ptr Renderer): bool {.
  importc: "SDL_RenderPresent",
  header: "<SDL3/SDL_render.h>"
.}

proc getPerformanceCounter*(): uint64 {.
  importc: "SDL_GetPerformanceCounter",
  header: "<SDL3/SDL_timer.h>"
.}

proc getPerformanceFrequency*(): uint64 {.
  importc: "SDL_GetPerformanceFrequency",
  header: "<SDL3/SDL_timer.h>"
.}

proc getError*(): cstring {.
  importc: "SDL_GetError",
  header: "<SDL3/SDL_error.h>"
.}

proc startTextInput*(window: ptr Window): bool {.
  importc: "SDL_StartTextInput",
  header: "<SDL3/SDL_keyboard.h>"
.}

proc stopTextInput*(window: ptr Window): bool {.
  importc: "SDL_StopTextInput",
  header: "<SDL3/SDL_keyboard.h>"
.}

proc free*(mem: pointer) {.
  importc: "SDL_free",
  header: "<SDL3/SDL_stdinc.h>"
.}

proc enterAppMainCallbacks*(
  argc: cint,
  argv: cstringArray,
  appInit: AppInitFunc,
  appIterate: AppIterateFunc,
  appEvent: AppEventFunc,
  appQuit: AppQuitFunc
): cint {.
  importc: "SDL_EnterAppMainCallbacks",
  header: "<SDL3/SDL_main.h>"
.}
