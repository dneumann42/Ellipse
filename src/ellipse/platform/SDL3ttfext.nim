import std/[strformat]

import ./SDL3
import ./SDL3ttf

type
  Error* = object of CatchableError

  NoMeta = object

  TTFAppResource* = object
  TTFFontResource* = object

  Handle*[Resource, RawHandle, Meta = NoMeta] = object
    handle: RawHandle
    meta: Meta

  TTFAppHandle* = Handle[TTFAppResource, bool]
  TTFFontHandle* = Handle[TTFFontResource, ptr TTF_Font]

template failure(prefix: string): untyped =
  raise newException(Error, prefix & ": " & $getError())

proc isValid(_: typedesc[TTFAppResource]; handle: bool; meta: NoMeta): bool =
  discard meta
  handle

proc isValid(_: typedesc[TTFFontResource]; handle: ptr TTF_Font; meta: NoMeta): bool =
  discard meta
  not handle.isNil

proc release(_: typedesc[TTFAppResource]; handle: bool; meta: var NoMeta) =
  discard handle
  quitTTF()
  meta = default(NoMeta)

proc release(_: typedesc[TTFFontResource]; handle: ptr TTF_Font; meta: var NoMeta) =
  discard meta
  closeFont(handle)

proc `=copy`*[Resource, RawHandle, Meta](dest: var Handle[Resource, RawHandle, Meta]; src: Handle[Resource, RawHandle, Meta]) {.error.}

proc `=destroy`*[Resource, RawHandle, Meta](value: var Handle[Resource, RawHandle, Meta]) =
  if isValid(Resource, value.handle, value.meta):
    release(Resource, value.handle, value.meta)
    value.handle = default(RawHandle)
    value.meta = default(Meta)

proc raw*[Resource, RawHandle, Meta](value: Handle[Resource, RawHandle, Meta]): RawHandle =
  value.handle

proc init*(_: typedesc[TTFAppHandle]): TTFAppHandle =
  if not initTTF():
    failure("TTF_Init failed")
  result.handle = true

proc openFont*(path: string; pointSize: cfloat): TTFFontHandle =
  result.handle = SDL3ttf.openFont(path.cstring, pointSize)
  if result.handle.isNil:
    failure(&"TTF_OpenFont failed for '{path}'")

proc setSize*(font: TTFFontHandle; pointSize: cfloat) =
  if not setFontSize(raw(font), pointSize):
    failure("TTF_SetFontSize failed")

proc fontHeight*(font: TTFFontHandle): int =
  int(getFontHeight(raw(font)))

proc stringSize*(font: TTFFontHandle; text: string): tuple[w, h: int] =
  var w: cint
  var h: cint
  if not getStringSize(raw(font), text.cstring, 0, addr w, addr h):
    failure("TTF_GetStringSize failed")
  (w: int(w), h: int(h))

proc renderTextBlended*(font: TTFFontHandle; text: string; color: Color): ptr Surface =
  result = SDL3ttf.renderTextBlended(raw(font), text.cstring, 0, color)
  if result.isNil:
    failure("TTF_RenderText_Blended failed")
