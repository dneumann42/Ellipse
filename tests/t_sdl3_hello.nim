import os
import ellipse/platform/SDL3
import ellipse/platform/SDL3ext

type
  DemoState = object
    sdl: AppHandle
    window: WindowHandle
    renderer: RendererHandle

var gState: ref DemoState

proc appInitCallback(appState: ptr pointer; argc: cint; argv: cstringArray): AppResult {.
  exportc,
  cdecl
.} =
  discard argc
  discard argv

  if not setAppMetadata("Ellipse SDL3 Hello", "0.0.0", "dev.ellipse.tests.sdl3hello"):
    stderr.writeLine "setAppMetadata failed: " & $getError()
    return appFailure

  try:
    new(gState)
    gState.sdl = SDL3ext.init(INIT_VIDEO)
    gState.window = SDL3ext.createWindow("Ellipse SDL3 Hello", 800, 600)
    gState.renderer = SDL3ext.createRenderer(gState.window)
  except Error as err:
    stderr.writeLine err.msg
    gState = nil
    return appFailure

  if not setRenderDrawColor(raw(gState.renderer), 24'u8, 34'u8, 48'u8, 255'u8):
    stderr.writeLine "setRenderDrawColor failed: " & $getError()
    gState = nil
    return appFailure

  if not renderClear(raw(gState.renderer)):
    stderr.writeLine "renderClear failed: " & $getError()
    gState = nil
    return appFailure

  if not renderPresent(raw(gState.renderer)):
    stderr.writeLine "renderPresent failed: " & $getError()
    gState = nil
    return appFailure

  appState[] = cast[pointer](gState)
  appContinue

proc iterateCallback(appState: pointer): AppResult {.exportc, cdecl.} =
  let state = cast[ref DemoState](appState)

  if not renderClear(raw(state.renderer)):
    stderr.writeLine "renderClear failed: " & $getError()
    return appFailure

  if not renderPresent(raw(state.renderer)):
    stderr.writeLine "renderPresent failed: " & $getError()
    return appFailure

  appContinue

proc eventCallback(appState: pointer; event: ptr Event): AppResult {.exportc, cdecl.} =
  discard appState

  case event[].`type`
  of EVENT_QUIT, EVENT_WINDOW_CLOSE_REQUESTED:
    appSuccess
  else:
    appContinue

proc quitCallback(appState: pointer; result: AppResult) {.exportc, cdecl.} =
  discard result

  if appState.isNil:
    gState = nil
  else:
    let state = cast[ref DemoState](appState)
    reset(state[])
    gState = nil

when isMainModule:
  var args = newSeq[string](1 + paramCount())
  args[0] = getAppFilename()
  for i, value in commandLineParams():
    args[i + 1] = value

  var cArgs = newSeq[cstring](args.len)
  for i, value in args:
    cArgs[i] = value.cstring

  system.quit enterAppMainCallbacks(
    cint(cArgs.len),
    cast[cstringArray](addr cArgs[0]),
    appInitCallback,
    iterateCallback,
    eventCallback,
    quitCallback
  )
