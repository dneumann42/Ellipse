import std/[hashes, os, tables]

import sdl3
import sdl3_ttf

import errors

type
  ResourceId* = distinct string

  ResourceKind* = enum
    FontResource
    TextureResource
    AudioResource

  ResourceState* = enum
    ResourceMissing
    ResourceLoading
    ResourceReady
    ResourceFailed

  Resource* = ref object of RootObj
    id*: ResourceId
    path*: string
    state*: ResourceState
    error*: string

  FontResourceHandle* = ref object of Resource
    font: sdl3_ttf.Font
    size*: float32
    ascent*, descent*, lineHeight*: int

  TextureResourceHandle* = ref object of Resource
    texture*: Texture
    width*, height*: int
    pixels*: seq[uint8]

  AudioResourceHandle* = ref object of Resource
    spec*: AudioSpec
    data: ptr uint8
    len*: uint32

  ResourceLoadOptions* = object
    fontSize* = 18'f32

  ResourceManager* = object
    renderer: Renderer
    resources: Table[ResourceId, Resource]
    pending: Table[uint, ResourceId]
    queue: AsyncIOQueue
    nextRequest: uint

proc openFontIO(
    src: IOStream, closeio: bool, ptsize: cfloat
): sdl3_ttf.Font {.importc: "TTF_OpenFontIO", cdecl,
    dynlib: sdl3_ttf.TtfLibName.}

proc loadWAVIO(
    src: IOStream,
    closeio: bool,
    spec: ptr AudioSpec,
    audioBuf: var ptr uint8,
    audioLen: var uint32,
): bool {.importc: "SDL_LoadWAV_IO", cdecl, dynlib: sdl3.LibName.}

proc imgLoad(file: cstring): ptr Surface {.
  importc: "IMG_Load", cdecl, dynlib: "libSDL3_image.so"
.}

proc `$`*(id: ResourceId): string {.borrow.}
proc `==`*(a, b: ResourceId): bool {.borrow.}
proc hash*(id: ResourceId): Hash =
  hash($id)

proc resourceId*(id: string): ResourceId =
  ResourceId(id)

proc raiseResourceError(context: string) {.noreturn.} =
  let message = $sdl3.getError()
  if message.len == 0:
    raise ResourceError.newException(context)
  raise ResourceError.newException(context & ": " & message)

proc fail(resource: Resource, message: string) =
  resource.state = ResourceFailed
  resource.error = message

proc requireRenderer(manager: ResourceManager) =
  if manager.renderer == nil:
    raise ResourceError.newException("ResourceManager has no SDL renderer")

proc `=copy`*(manager: var ResourceManager, source: ResourceManager) {.error.}
proc clear*(manager: var ResourceManager)

proc `=destroy`*(manager: var ResourceManager) =
  try:
    manager.clear()
  except Exception:
    discard

proc kind*(resource: Resource): ResourceKind =
  if resource of FontResourceHandle:
    FontResource
  elif resource of TextureResourceHandle:
    TextureResource
  else:
    AudioResource

proc state*(manager: ResourceManager, id: ResourceId): ResourceState =
  let resource = manager.resources.getOrDefault(id)
  if resource == nil:
    ResourceMissing
  else:
    resource.state

proc loading*(manager: ResourceManager, id: ResourceId): bool =
  manager.state(id) == ResourceLoading

proc ready*(manager: ResourceManager, id: ResourceId): bool =
  manager.state(id) == ResourceReady

proc contains*(manager: ResourceManager, id: ResourceId): bool =
  manager.resources.hasKey(id)

proc error*(manager: ResourceManager, id: ResourceId): string =
  let resource = manager.resources.getOrDefault(id)
  if resource == nil:
    ""
  else:
    resource.error

proc close(resource: Resource) =
  if resource of FontResourceHandle:
    let font = FontResourceHandle(resource)
    if font.font != nil:
      sdl3_ttf.closeFont(font.font)
      font.font = nil
  elif resource of TextureResourceHandle:
    let texture = TextureResourceHandle(resource)
    if texture.texture != nil:
      destroyTexture(texture.texture)
      texture.texture = nil
  elif resource of AudioResourceHandle:
    let audio = AudioResourceHandle(resource)
    if audio.data != nil:
      sdlFree(audio.data)
      audio.data = nil
      audio.len = 0

proc clear*(manager: var ResourceManager, id: ResourceId) =
  let resource = manager.resources.getOrDefault(id)
  if resource != nil:
    resource.close()
  var removed: seq[uint]
  for token, pendingId in manager.pending.pairs:
    if pendingId == id:
      removed.add token
  for token in removed:
    manager.pending.del token
  manager.resources.del id

proc clear*(manager: var ResourceManager) =
  for resource in manager.resources.values:
    resource.close()
  manager.resources.clear()
  if manager.queue != nil:
    destroyAsyncIOQueue(manager.queue)
    manager.queue = nil
  manager.pending.clear()

proc newResourceManager*(renderer: Renderer): ResourceManager =
  ResourceManager(renderer: renderer)

proc readBytes(path: string): tuple[data: pointer, len: csize_t] =
  result.data = loadFile(cstring(path), result.len)
  if result.data == nil:
    raiseResourceError("Failed to load resource " & path)

proc ioFromBytes(data: pointer, len: csize_t): IOStream =
  result = ioFromConstMem(data, len)
  if result == nil:
    raiseResourceError("Failed to open resource memory")

proc textureFromSurface(manager: ResourceManager, path: string,
    surface: ptr Surface): Texture =
  manager.requireRenderer()
  result = createTextureFromSurface(manager.renderer, surface)
  if result == nil:
    raiseResourceError("Failed to create texture " & path)
  discard setTextureBlendMode(result, BLENDMODE_BLEND)

proc copySurfacePixels(surface: ptr Surface): seq[uint8] =
  let bytesPerRow = surface.w.int * 4
  result = newSeq[uint8](bytesPerRow * surface.h.int)
  for y in 0 ..< surface.h.int:
    let srcOffset = y * surface.pitch.int
    let dstOffset = y * bytesPerRow
    copyMem(addr result[dstOffset], addr surface.pixels[srcOffset], bytesPerRow)

proc loadFontFromBytes(id: ResourceId, path: string, data: pointer,
    len: csize_t, size: float32): FontResourceHandle =
  let io = ioFromBytes(data, len)
  let font = openFontIO(io, true, size.cfloat)
  if font == nil:
    raiseResourceError("Failed to load font " & path)
  result = FontResourceHandle(
    id: id,
    path: path,
    state: ResourceReady,
    font: font,
    size: size,
    ascent: sdl3_ttf.getFontAscent(font).int,
    descent: sdl3_ttf.getFontDescent(font).int,
    lineHeight: sdl3_ttf.getFontLineSkip(font).int,
  )

proc loadTextureFromBytes(manager: ResourceManager, id: ResourceId,
    path: string, data: pointer, len: csize_t): TextureResourceHandle =
  let io = ioFromBytes(data, len)
  let surface = loadBMP_IO(io, true)
  if surface == nil:
    raiseResourceError("Failed to load texture " & path)
  defer:
    destroySurface(surface)
  let converted = convertSurface(surface, PIXELFORMAT_RGBA32)
  if converted == nil:
    raiseResourceError("Failed to convert texture " & path)
  defer:
    destroySurface(converted)
  let texture = manager.textureFromSurface(path, converted)
  result = TextureResourceHandle(
    id: id,
    path: path,
    state: ResourceReady,
    texture: texture,
    width: converted.w.int,
    height: converted.h.int,
    pixels: converted.copySurfacePixels(),
  )

proc loadImageTexture(manager: ResourceManager, id: ResourceId,
    path: string): TextureResourceHandle =
  let surface = imgLoad(cstring(path))
  if surface == nil:
    raiseResourceError("Failed to load texture " & path)
  defer:
    destroySurface(surface)
  let converted = convertSurface(surface, PIXELFORMAT_RGBA32)
  if converted == nil:
    raiseResourceError("Failed to convert texture " & path)
  defer:
    destroySurface(converted)
  let texture = manager.textureFromSurface(path, converted)
  TextureResourceHandle(
    id: id,
    path: path,
    state: ResourceReady,
    texture: texture,
    width: converted.w.int,
    height: converted.h.int,
    pixels: converted.copySurfacePixels(),
  )

proc loadAudioFromBytes(id: ResourceId, path: string, data: pointer,
    len: csize_t): AudioResourceHandle =
  let io = ioFromBytes(data, len)
  var
    spec: AudioSpec
    audio: ptr uint8
    audioLen: uint32
  if not loadWAVIO(io, true, addr spec, audio, audioLen):
    raiseResourceError("Failed to load audio " & path)
  AudioResourceHandle(
    id: id,
    path: path,
    state: ResourceReady,
    spec: spec,
    data: audio,
    len: audioLen,
  )

proc addFont*(manager: var ResourceManager, id: ResourceId, path: string,
    size = 18'f32): FontResourceHandle =
  let bytes = readBytes(path)
  defer:
    sdlFree(bytes.data)
  result = loadFontFromBytes(id, path, bytes.data, bytes.len, size)
  manager.clear(id)
  manager.resources[id] = result

proc addTexture*(manager: var ResourceManager, id: ResourceId,
    path: string): TextureResourceHandle =
  if path.splitFile.ext != ".bmp":
    result = manager.loadImageTexture(id, path)
    manager.clear(id)
    manager.resources[id] = result
    return
  let bytes = readBytes(path)
  defer:
    sdlFree(bytes.data)
  result = manager.loadTextureFromBytes(id, path, bytes.data, bytes.len)
  manager.clear(id)
  manager.resources[id] = result

proc addAudio*(manager: var ResourceManager, id: ResourceId,
    path: string): AudioResourceHandle =
  let bytes = readBytes(path)
  defer:
    sdlFree(bytes.data)
  result = loadAudioFromBytes(id, path, bytes.data, bytes.len)
  manager.clear(id)
  manager.resources[id] = result

proc add*(manager: var ResourceManager, id: ResourceId, path: string,
    kind: typedesc[FontResourceHandle], size = 18'f32): FontResourceHandle =
  manager.addFont(id, path, size)

proc add*(manager: var ResourceManager, id: ResourceId, path: string,
    kind: typedesc[TextureResourceHandle]): TextureResourceHandle =
  manager.addTexture(id, path)

proc add*(manager: var ResourceManager, id: ResourceId, path: string,
    kind: typedesc[AudioResourceHandle]): AudioResourceHandle =
  manager.addAudio(id, path)

proc putPending(manager: var ResourceManager, id: ResourceId,
    resource: Resource) =
  manager.clear(id)
  resource.state = ResourceLoading
  manager.resources[id] = resource
  if manager.queue == nil:
    manager.queue = createAsyncIOQueue()
    if manager.queue == nil:
      raiseResourceError("Failed to create async resource queue")
  inc manager.nextRequest
  if manager.nextRequest == 0:
    inc manager.nextRequest
  let token = manager.nextRequest
  manager.pending[token] = id
  if not loadFileAsync(cstring(resource.path), manager.queue, cast[pointer](token)):
    manager.pending.del token
    raiseResourceError("Failed to queue async resource " & resource.path)

proc addAsync*(manager: var ResourceManager, id: ResourceId, path: string,
    kind: typedesc[FontResourceHandle], size = 18'f32) =
  manager.putPending(
    id,
    FontResourceHandle(id: id, path: path, size: size),
  )

proc addAsync*(manager: var ResourceManager, id: ResourceId, path: string,
    kind: typedesc[TextureResourceHandle]) =
  manager.putPending(id, TextureResourceHandle(id: id, path: path))

proc addAsync*(manager: var ResourceManager, id: ResourceId, path: string,
    kind: typedesc[AudioResourceHandle]) =
  manager.putPending(id, AudioResourceHandle(id: id, path: path))

proc finishAsync(manager: var ResourceManager, resource: Resource,
    outcome: AsyncIOOutcome) =
  if outcome.result != IOComplete:
    resource.fail("Failed to load resource " & resource.path)
    return
  try:
    let loaded =
      if resource of FontResourceHandle:
        loadFontFromBytes(
          resource.id,
          resource.path,
          outcome.buffer,
          outcome.bytesTransferred.csize_t,
          FontResourceHandle(resource).size,
        )
      elif resource of TextureResourceHandle:
        manager.loadTextureFromBytes(
          resource.id,
          resource.path,
          outcome.buffer,
          outcome.bytesTransferred.csize_t,
        )
      else:
        loadAudioFromBytes(
          resource.id,
          resource.path,
          outcome.buffer,
          outcome.bytesTransferred.csize_t,
        )
    manager.resources[resource.id] = loaded
  except CatchableError as error:
    resource.fail(error.msg)

proc poll*(manager: var ResourceManager) =
  if manager.queue == nil:
    return
  var outcome: AsyncIOOutcome
  while getAsyncIOResult(manager.queue, outcome):
    let token = cast[uint](outcome.userdata)
    let known = manager.pending.hasKey(token)
    let id = manager.pending.getOrDefault(token)
    if known:
      manager.pending.del token
    let resource = manager.resources.getOrDefault(id)
    if known and resource != nil:
      manager.finishAsync(resource, outcome)
    if outcome.buffer != nil:
      sdlFree(outcome.buffer)

proc get*(manager: ResourceManager, id: ResourceId): Resource =
  result = manager.resources.getOrDefault(id)
  if result == nil:
    raise KeyError.newException("Missing resource " & $id)
  if result.state == ResourceFailed:
    raise ResourceError.newException(result.error)
  if result.state == ResourceLoading:
    raise ResourceError.newException("Resource still loading " & $id)

proc get*(manager: ResourceManager, id: ResourceId,
    kind: typedesc[FontResourceHandle]): FontResourceHandle =
  let resource = manager.get(id)
  if not (resource of FontResourceHandle):
    raise ResourceError.newException("Resource " & $id & " is not a font")
  FontResourceHandle(resource)

proc get*(manager: ResourceManager, id: ResourceId,
    kind: typedesc[TextureResourceHandle]): TextureResourceHandle =
  let resource = manager.get(id)
  if not (resource of TextureResourceHandle):
    raise ResourceError.newException("Resource " & $id & " is not a texture")
  TextureResourceHandle(resource)

proc get*(manager: ResourceManager, id: ResourceId,
    kind: typedesc[AudioResourceHandle]): AudioResourceHandle =
  let resource = manager.get(id)
  if not (resource of AudioResourceHandle):
    raise ResourceError.newException("Resource " & $id & " is not audio")
  AudioResourceHandle(resource)

proc render*(texture: TextureResourceHandle, renderer: Renderer, x, y: float32) =
  if texture == nil or texture.texture == nil:
    return
  var dst = FRect(
    x: x.cfloat,
    y: y.cfloat,
    w: texture.width.cfloat,
    h: texture.height.cfloat,
  )
  discard renderTexture(renderer, texture.texture, nil, addr dst)

proc render*(texture: TextureResourceHandle, renderer: Renderer, src, dst: FRect) =
  if texture == nil or texture.texture == nil:
    return
  var source = src
  var target = dst
  discard renderTexture(renderer, texture.texture, addr source, addr target)

proc play*(audio: AudioResourceHandle, gain = 1'f32): AudioStream =
  if audio == nil or audio.data == nil or audio.len == 0:
    return nil
  result = openAudioDeviceStream(
    AUDIO_DEVICE_DEFAULT_PLAYBACK,
    audio.spec,
    nil,
    nil,
  )
  if result == nil:
    raiseResourceError("Failed to open audio stream")
  discard setAudioStreamGain(result, gain.cfloat)
  if not putAudioStreamData(result, audio.data, audio.len.cint):
    destroyAudioStream(result)
    raiseResourceError("Failed to queue audio")
  discard flushAudioStream(result)
  discard resumeAudioStreamDevice(result)
