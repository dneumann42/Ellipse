import std/[strformat]
import ./SDL3

type
  Error* = object of CatchableError

  NoMeta = object

  AppResource* = object
  WindowResource* = object
  RendererResource* = object
  TextureResource* = object
  SurfaceResource* = object
  PaletteResource* = object
  PropertiesResource* = object
  IOStreamResource* = object
  AudioDeviceResource* = object
  AudioStreamResource* = object
  AudioBufferResource* = object

  AppMeta = object
    initialized: bool

  AudioBufferMeta = object
    spec: AudioSpec
    len: uint32

  Handle*[Resource, RawHandle, Meta = NoMeta] = object
    handle: RawHandle
    meta: Meta

  AppHandle* = Handle[AppResource, InitFlags, AppMeta]
  WindowHandle* = Handle[WindowResource, ptr Window]
  RendererHandle* = Handle[RendererResource, ptr Renderer]
  TextureHandle* = Handle[TextureResource, ptr Texture]
  SurfaceHandle* = Handle[SurfaceResource, ptr Surface]
  PaletteHandle* = Handle[PaletteResource, ptr Palette]
  PropertiesHandle* = Handle[PropertiesResource, PropertiesID]
  IOStreamHandle* = Handle[IOStreamResource, ptr IOStream]
  AudioDeviceHandle* = Handle[AudioDeviceResource, AudioDeviceID]
  AudioStreamHandle* = Handle[AudioStreamResource, ptr AudioStream]
  AudioBufferHandle* = Handle[AudioBufferResource, ptr UncheckedArray[uint8], AudioBufferMeta]

template failure(prefix: string): untyped =
  raise newException(Error, prefix & ": " & $getError())

proc isValid(_: typedesc[AppResource]; handle: InitFlags; meta: AppMeta): bool =
  meta.initialized

proc isValid(_: typedesc[WindowResource]; handle: ptr Window; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[RendererResource]; handle: ptr Renderer; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[TextureResource]; handle: ptr Texture; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[SurfaceResource]; handle: ptr Surface; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[PaletteResource]; handle: ptr Palette; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[PropertiesResource]; handle: PropertiesID; meta: NoMeta): bool =
  handle != 0

proc isValid(_: typedesc[IOStreamResource]; handle: ptr IOStream; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[AudioDeviceResource]; handle: AudioDeviceID; meta: NoMeta): bool =
  handle != 0

proc isValid(_: typedesc[AudioStreamResource]; handle: ptr AudioStream; meta: NoMeta): bool =
  not handle.isNil

proc isValid(_: typedesc[AudioBufferResource]; handle: ptr UncheckedArray[uint8]; meta: AudioBufferMeta): bool =
  not handle.isNil

proc release(_: typedesc[AppResource]; handle: InitFlags; meta: var AppMeta) =
  discard handle
  quit()
  meta.initialized = false

proc release(_: typedesc[WindowResource]; handle: ptr Window; meta: var NoMeta) =
  discard meta
  destroyWindow(handle)

proc release(_: typedesc[RendererResource]; handle: ptr Renderer; meta: var NoMeta) =
  discard meta
  destroyRenderer(handle)

proc release(_: typedesc[TextureResource]; handle: ptr Texture; meta: var NoMeta) =
  discard meta
  destroyTexture(handle)

proc release(_: typedesc[SurfaceResource]; handle: ptr Surface; meta: var NoMeta) =
  discard meta
  destroySurface(handle)

proc release(_: typedesc[PaletteResource]; handle: ptr Palette; meta: var NoMeta) =
  discard meta
  destroyPalette(handle)

proc release(_: typedesc[PropertiesResource]; handle: PropertiesID; meta: var NoMeta) =
  discard meta
  destroyProperties(handle)

proc release(_: typedesc[IOStreamResource]; handle: ptr IOStream; meta: var NoMeta) =
  discard closeIO(handle)
  discard meta

proc release(_: typedesc[AudioDeviceResource]; handle: AudioDeviceID; meta: var NoMeta) =
  discard meta
  closeAudioDevice(handle)

proc release(_: typedesc[AudioStreamResource]; handle: ptr AudioStream; meta: var NoMeta) =
  discard meta
  destroyAudioStream(handle)

proc release(_: typedesc[AudioBufferResource]; handle: ptr UncheckedArray[uint8]; meta: var AudioBufferMeta) =
  free(cast[pointer](handle))
  meta = default(AudioBufferMeta)

proc `=copy`*[Resource, RawHandle, Meta](dest: var Handle[Resource, RawHandle, Meta]; src: Handle[Resource, RawHandle, Meta]) {.error.}

proc `=destroy`*[Resource, RawHandle, Meta](value: var Handle[Resource, RawHandle, Meta]) =
  if isValid(Resource, value.handle, value.meta):
    release(Resource, value.handle, value.meta)
    value.handle = default(RawHandle)
    value.meta = default(Meta)

proc raw*[Resource, RawHandle, Meta](value: Handle[Resource, RawHandle, Meta]): RawHandle =
  value.handle

proc spec*(buffer: AudioBufferHandle): AudioSpec =
  buffer.meta.spec

proc len*(buffer: AudioBufferHandle): uint32 =
  buffer.meta.len

proc init*(flags: InitFlags): AppHandle =
  if not SDL3.init(flags):
    failure("init failed")
  result.handle = flags
  result.meta.initialized = true

proc createWindow*(
  title: string,
  width: int,
  height: int,
  flags: WindowFlags = 0
): WindowHandle =
  result.handle = SDL3.createWindow(title.cstring, cint(width), cint(height), flags)
  if result.handle.isNil:
    failure("createWindow failed")

proc createRenderer*(window: ptr Window; name: cstring = nil): RendererHandle =
  result.handle = SDL3.createRenderer(window, name)
  if result.handle.isNil:
    failure("createRenderer failed")

proc createRenderer*(window: WindowHandle; name: cstring = nil): RendererHandle =
  createRenderer(raw(window), name)

proc createTexture*(
  renderer: ptr Renderer,
  format: PixelFormat,
  access: TextureAccess,
  width: int,
  height: int
): TextureHandle =
  result.handle = SDL3.createTexture(renderer, format, access, cint(width), cint(height))
  if result.handle.isNil:
    failure("createTexture failed")

proc createTexture*(
  renderer: RendererHandle,
  format: PixelFormat,
  access: TextureAccess,
  width: int,
  height: int
): TextureHandle =
  createTexture(raw(renderer), format, access, width, height)

proc createTextureFromSurface*(renderer: ptr Renderer; surface: ptr Surface): TextureHandle =
  result.handle = SDL3.createTextureFromSurface(renderer, surface)
  if result.handle.isNil:
    failure("createTextureFromSurface failed")

proc createTextureFromSurface*(renderer: RendererHandle; surface: SurfaceHandle): TextureHandle =
  createTextureFromSurface(raw(renderer), raw(surface))

proc createTextureWithProperties*(renderer: ptr Renderer; props: PropertiesID): TextureHandle =
  result.handle = SDL3.createTextureWithProperties(renderer, props)
  if result.handle.isNil:
    failure("createTextureWithProperties failed")

proc createTextureWithProperties*(renderer: RendererHandle; props: PropertiesHandle): TextureHandle =
  createTextureWithProperties(raw(renderer), raw(props))

proc createSurface*(width: int; height: int; format: PixelFormat): SurfaceHandle =
  result.handle = SDL3.createSurface(cint(width), cint(height), format)
  if result.handle.isNil:
    failure("createSurface failed")

proc lockSurface*(surface: ptr Surface) =
  if not SDL3.lockSurface(surface):
    failure("lockSurface failed")

proc lockSurface*(surface: SurfaceHandle) =
  lockSurface(raw(surface))

proc unlockSurface*(surface: ptr Surface) =
  SDL3.unlockSurface(surface)

proc unlockSurface*(surface: SurfaceHandle) =
  unlockSurface(raw(surface))

proc convertSurface*(surface: ptr Surface; format: PixelFormat): SurfaceHandle =
  result.handle = SDL3.convertSurface(surface, format)
  if result.handle.isNil:
    failure("convertSurface failed")

proc convertSurface*(surface: SurfaceHandle; format: PixelFormat): SurfaceHandle =
  convertSurface(raw(surface), format)

proc loadSurface*(path: string): SurfaceHandle =
  result.handle = SDL3.loadSurface(path.cstring)
  if result.handle.isNil:
    failure(&"loadSurface failed for '{path}'")

proc loadPng*(path: string): SurfaceHandle =
  result.handle = SDL3.loadPng(path.cstring)
  if result.handle.isNil:
    failure(&"loadPng failed for '{path}'")

proc savePng*(surface: ptr Surface; path: string) =
  if not SDL3.savePng(surface, path.cstring):
    failure(&"savePng failed for '{path}'")

proc savePng*(surface: SurfaceHandle; path: string) =
  savePng(raw(surface), path)

proc loadBmp*(path: string): SurfaceHandle =
  result.handle = SDL3.loadBmp(path.cstring)
  if result.handle.isNil:
    failure(&"loadBmp failed for '{path}'")

proc createPalette*(ncolors: int): PaletteHandle =
  result.handle = SDL3.createPalette(cint(ncolors))
  if result.handle.isNil:
    failure("createPalette failed")

proc createProperties*(): PropertiesHandle =
  result.handle = SDL3.createProperties()
  if result.handle == 0:
    failure("createProperties failed")

proc openIOFromFile*(path: string; mode: string): IOStreamHandle =
  result.handle = ioFromFile(path.cstring, mode.cstring)
  if result.handle.isNil:
    failure(&"ioFromFile failed for '{path}'")

proc openAudioDevice*(deviceId: AudioDeviceID; spec: ptr AudioSpec = nil): AudioDeviceHandle =
  result.handle = SDL3.openAudioDevice(deviceId, spec)
  if result.handle == 0:
    failure("openAudioDevice failed")

proc openAudioDevice*(deviceId: AudioDeviceID; spec: AudioSpec): AudioDeviceHandle =
  var mutableSpec = spec
  openAudioDevice(deviceId, addr mutableSpec)

proc createAudioStream*(srcSpec, dstSpec: ptr AudioSpec): AudioStreamHandle =
  result.handle = SDL3.createAudioStream(srcSpec, dstSpec)
  if result.handle.isNil:
    failure("createAudioStream failed")

proc createAudioStream*(srcSpec, dstSpec: AudioSpec): AudioStreamHandle =
  var mutableSrc = srcSpec
  var mutableDst = dstSpec
  createAudioStream(addr mutableSrc, addr mutableDst)

proc loadWav*(path: string): AudioBufferHandle =
  var buf: ptr uint8
  if not SDL3.loadWav(path.cstring, addr result.meta.spec, addr buf, addr result.meta.len):
    failure(&"loadWav failed for '{path}'")
  result.handle = cast[ptr UncheckedArray[uint8]](buf)
