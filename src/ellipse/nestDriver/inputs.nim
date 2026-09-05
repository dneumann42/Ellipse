## SDL-to-Nest event translation and input ownership.

import sdl3
import nest except Event, update, draw
import nest/input
import ../rendering/canvas
import state

proc translateNestScancode(scancode: Scancode): input.KeyCode =
  case scancode
  of SCANCODE_A: KeyA
  of SCANCODE_B: KeyB
  of SCANCODE_C: KeyC
  of SCANCODE_D: KeyD
  of SCANCODE_E: KeyE
  of SCANCODE_F: KeyF
  of SCANCODE_G: KeyG
  of SCANCODE_H: KeyH
  of SCANCODE_I: KeyI
  of SCANCODE_J: KeyJ
  of SCANCODE_K: KeyK
  of SCANCODE_L: KeyL
  of SCANCODE_M: KeyM
  of SCANCODE_N: KeyN
  of SCANCODE_O: KeyO
  of SCANCODE_P: KeyP
  of SCANCODE_Q: KeyQ
  of SCANCODE_R: KeyR
  of SCANCODE_S: KeyS
  of SCANCODE_T: KeyT
  of SCANCODE_U: KeyU
  of SCANCODE_V: KeyV
  of SCANCODE_W: KeyW
  of SCANCODE_X: KeyX
  of SCANCODE_Y: KeyY
  of SCANCODE_Z: KeyZ
  of SCANCODE_1: Key1
  of SCANCODE_2: Key2
  of SCANCODE_3: Key3
  of SCANCODE_4: Key4
  of SCANCODE_5: Key5
  of SCANCODE_6: Key6
  of SCANCODE_7: Key7
  of SCANCODE_8: Key8
  of SCANCODE_9: Key9
  of SCANCODE_0: Key0
  of SCANCODE_F1: KeyF1
  of SCANCODE_F2: KeyF2
  of SCANCODE_F3: KeyF3
  of SCANCODE_F4: KeyF4
  of SCANCODE_F5: KeyF5
  of SCANCODE_F6: KeyF6
  of SCANCODE_F7: KeyF7
  of SCANCODE_F8: KeyF8
  of SCANCODE_F9: KeyF9
  of SCANCODE_F10: KeyF10
  of SCANCODE_F11: KeyF11
  of SCANCODE_F12: KeyF12
  of SCANCODE_RETURN: KeyEnter
  of SCANCODE_SPACE: KeySpace
  of SCANCODE_ESCAPE: KeyEsc
  of SCANCODE_TAB: KeyTab
  of SCANCODE_BACKSPACE: KeyBackspace
  of SCANCODE_DELETE: KeyDelete
  of SCANCODE_INSERT: KeyInsert
  of SCANCODE_LEFT: KeyLeft
  of SCANCODE_RIGHT: KeyRight
  of SCANCODE_UP: KeyUp
  of SCANCODE_DOWN: KeyDown
  of SCANCODE_PAGEUP: KeyPageUp
  of SCANCODE_PAGEDOWN: KeyPageDown
  of SCANCODE_HOME: KeyHome
  of SCANCODE_END: KeyEnd
  of SCANCODE_CAPSLOCK: KeyCapslock
  of SCANCODE_COMMA: KeyComma
  of SCANCODE_PERIOD: KeyPeriod
  of SCANCODE_SLASH: KeySlash
  of SCANCODE_MINUS: KeyMinus
  of SCANCODE_EQUALS: KeyEqual
  of SCANCODE_KP_MINUS: KeyMinus
  of SCANCODE_KP_PLUS: KeyPlus
  of SCANCODE_KP_EQUALS: KeyEqual
  else: KeyNone

proc translateNestKeycode(keycode: int32): input.KeyCode =
  case keycode
  of SDLK_MINUS.int32, SDLK_KP_MINUS.int32: KeyMinus
  of SDLK_EQUALS.int32, SDLK_KP_EQUALS.int32: KeyEqual
  of SDLK_PLUS.int32, SDLK_KP_PLUS.int32: KeyPlus
  else: KeyNone

proc translateNestMods(keymod: Keymod): set[input.Modifier] =
  let flags = keymod.uint32
  if (flags and KMOD_SHIFT) != 0:
    result.incl ShiftPressed
  if (flags and KMOD_CTRL) != 0:
    result.incl CtrlPressed
  if (flags and KMOD_ALT) != 0:
    result.incl AltPressed
  if (flags and KMOD_GUI) != 0:
    result.incl GuiPressed
proc createNest*(width = 1280, height = 720): UI =
  result = UI.init()
  result.initContext(width, height)
  result.loadFont("font", "", 18)

proc handleNestEvent*(ui: var UI, event: sdl3.Event): bool =
  let eventType = uint32(event.common.`type`)
  if eventType == uint32(EVENT_WINDOW_RESIZED):
    if nestCanvas == nil or nestCanvas[].sizeMode == Window:
      ui.resizeWindow(event.window.data1, event.window.data2)
      ui.markAllDirty()
      ui.requestRedrawAfter(0)
      clearNestTextureCache()
    return true
  elif eventType == uint32(EVENT_MOUSE_MOTION):
    let
      point = nestEventPoint(event.motion.x, event.motion.y)
      x = point.x.int
      y = point.y.int
      overInteractiveBeforeMove = ui.pointerOverInteractive(x, y)
      widgetActive = ui.hasPendingWidgetEvents()
    ui.mouseMove(x, y)
    if overInteractiveBeforeMove or widgetActive:
      ui.requestRedrawAfter(0)
      return true
    return false
  elif eventType == uint32(EVENT_MOUSE_BUTTON_DOWN) and
      event.button.button == BUTTON_LEFT:
    let point = nestEventPoint(event.button.x, event.button.y)
    ui.mouseMove(point.x.int, point.y.int)
    ui.mouseDown()
    ui.requestRedrawAfter(0)
    return true
  elif eventType == uint32(EVENT_MOUSE_BUTTON_UP) and event.button.button == BUTTON_LEFT:
    let point = nestEventPoint(event.button.x, event.button.y)
    ui.mouseMove(point.x.int, point.y.int)
    ui.mouseUp()
    ui.requestRedrawAfter(0)
    return true
  elif eventType == uint32(EVENT_MOUSE_BUTTON_DOWN) and
      event.button.button == BUTTON_MIDDLE:
    let point = nestEventPoint(event.button.x, event.button.y)
    ui.mouseMove(point.x.int, point.y.int)
    ui.mouseMiddleDown()
    ui.requestRedrawAfter(0)
    return true
  elif eventType == uint32(EVENT_MOUSE_BUTTON_UP) and
      event.button.button == BUTTON_MIDDLE:
    let point = nestEventPoint(event.button.x, event.button.y)
    ui.mouseMove(point.x.int, point.y.int)
    ui.mouseMiddleUp()
    ui.requestRedrawAfter(0)
    return true
  elif eventType == uint32(EVENT_MOUSE_BUTTON_DOWN) and
      event.button.button == BUTTON_RIGHT:
    let point = nestEventPoint(event.button.x, event.button.y)
    ui.mouseMove(point.x.int, point.y.int)
    ui.mouseRightDown()
    ui.requestRedrawAfter(0)
    return true
  elif eventType == uint32(EVENT_MOUSE_WHEEL):
    let point = nestEventPoint(event.wheel.mouse_x, event.wheel.mouse_y)
    ui.mouseMove(point.x.int, point.y.int)
    ui.mouseWheel(event.wheel.x.float64, event.wheel.y.float64)
    ui.requestRedrawAfter(0)
    return true
  elif eventType == uint32(EVENT_KEY_DOWN):
    if event.key.repeat:
      return false
    var key = translateNestScancode(event.key.scancode)
    if key == KeyNone:
      key = translateNestKeycode(event.key.key.int32)
    if key != KeyNone:
      ui.keyDown(key, translateNestMods(event.key.`mod`))
      ui.requestRedrawAfter(0)
      return true
  elif eventType == uint32(EVENT_TEXT_INPUT):
    if event.text.text != nil:
      ui.textInput($event.text.text)
      ui.requestRedrawAfter(0)
      return true
  false

proc anyBlockedMouseButton(blockedButtons: array[256, bool]): bool =
  for blocked in blockedButtons:
    if blocked:
      return true

proc nestBlocksKeyboardInputEvent(ui: UI, event: sdl3.Event): bool =
  let eventType = uint32(event.common.`type`)
  ui.wantsTextInput() and (
    eventType == uint32(EVENT_KEY_DOWN) or
    eventType == uint32(EVENT_KEY_UP) or
    eventType == uint32(EVENT_TEXT_INPUT) or
    eventType == uint32(EVENT_TEXT_EDITING)
  )

proc nestBlocksInputEvent*(
    ui: UI, event: sdl3.Event, blockedButtons: var array[256, bool]
): bool =
  let eventType = uint32(event.common.`type`)
  if nestBlocksKeyboardInputEvent(ui, event):
    return true
  if eventType == uint32(EVENT_MOUSE_BUTTON_DOWN):
    let button = event.button.button.int
    if button >= blockedButtons.low and button <= blockedButtons.high:
      result = ui.pointerInputBlocked(event.button.x.int, event.button.y.int)
      if result:
        blockedButtons[button] = true
  elif eventType == uint32(EVENT_MOUSE_BUTTON_UP):
    let button = event.button.button.int
    if button >= blockedButtons.low and button <= blockedButtons.high:
      result = blockedButtons[button]
      blockedButtons[button] = false
  elif eventType == uint32(EVENT_MOUSE_MOTION):
    result = anyBlockedMouseButton(blockedButtons)
  elif eventType == uint32(EVENT_MOUSE_WHEEL):
    result = ui.pointerInputBlocked(event.wheel.mouse_x.int,
        event.wheel.mouse_y.int)
