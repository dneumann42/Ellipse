import std/[hashes, tables]

import sdl3

type
  InputId* = string

  InputSourceKind* = enum
    InputKeyboard, InputMouseButton, InputGamepadButton

  InputSource* = object
    case kind*: InputSourceKind
    of InputKeyboard:
      scancode*: Scancode
    of InputMouseButton:
      mouseButton*: uint8
    of InputGamepadButton:
      gamepadButton*: GamepadButton

  InputBinding* = object
    id*: InputId
    source*: InputSource

  InputButtonState* = object
    down*, pressed*, released*: bool

  DoubleClickState = object
    waiting: bool
    elapsed: float64

  InputMap* = object
    bindings: Table[InputId, seq[InputSource]]
    sourceDown: Table[InputSource, bool]
    states: Table[InputId, InputButtonState]
    doubleClicks: Table[InputId, DoubleClickState]
    textInput, textEditing: string
    mouseX*, mouseY*: int
    mouseDeltaX*, mouseDeltaY*: float32
    mouseWheelX*, mouseWheelY*: float32

func hash*(source: InputSource): Hash =
  result = hash(source.kind)
  case source.kind
  of InputKeyboard:
    result = result !& hash(source.scancode.int)
  of InputMouseButton:
    result = result !& hash(source.mouseButton)
  of InputGamepadButton:
    result = result !& hash(source.gamepadButton.int)
  result = !$result

func `==`*(a, b: InputSource): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of InputKeyboard:
    a.scancode == b.scancode
  of InputMouseButton:
    a.mouseButton == b.mouseButton
  of InputGamepadButton:
    a.gamepadButton == b.gamepadButton

func key*(scancode: Scancode): InputSource =
  InputSource(kind: InputKeyboard, scancode: scancode)

func mouseButton*(button: uint8): InputSource =
  InputSource(kind: InputMouseButton, mouseButton: button)

func gamepadButton*(button: GamepadButton): InputSource =
  InputSource(kind: InputGamepadButton, gamepadButton: button)

func binding*(id: InputId, source: InputSource): InputBinding =
  InputBinding(id: id, source: source)

proc init*(T: typedesc[InputMap]): T =
  T(
    bindings: initTable[InputId, seq[InputSource]](),
    sourceDown: initTable[InputSource, bool](),
    states: initTable[InputId, InputButtonState](),
  )

const DefaultDoubleClickInterval* = 0.35

proc clearBindings*(inputs: var InputMap) =
  inputs.bindings.clear()
  inputs.sourceDown.clear()
  inputs.states.clear()

proc addBinding*(inputs: var InputMap, id: InputId, source: InputSource) =
  for existing in inputs.bindings.getOrDefault(id, @[]):
    if existing == source:
      return
  inputs.bindings.mgetOrPut(id, @[]).add source
  discard inputs.states.mgetOrPut(id, InputButtonState())

proc addBinding*(inputs: var InputMap, binding: InputBinding) =
  inputs.addBinding(binding.id, binding.source)

proc addBindings*(inputs: var InputMap, bindings: openArray[InputBinding]) =
  for binding in bindings:
    inputs.addBinding(binding)

template bindings*(inputs: var InputMap, body: untyped) =
  block:
    template action(id: string, source: InputSource) =
      inputs.addBinding(id, source)
    body

proc unbind*(inputs: var InputMap, id: InputId) =
  inputs.bindings.del id
  inputs.states.del id

proc unbind*(inputs: var InputMap, id: InputId, source: InputSource) =
  if not inputs.bindings.hasKey(id):
    return
  var kept: seq[InputSource]
  for existing in inputs.bindings[id]:
    if existing != source:
      kept.add existing
  if kept.len == 0:
    inputs.unbind(id)
  else:
    inputs.bindings[id] = kept

proc actionDown(inputs: InputMap, id: InputId): bool =
  if not inputs.bindings.hasKey(id):
    return false
  for source in inputs.bindings[id]:
    if inputs.sourceDown.getOrDefault(source, false):
      return true

proc updateAction(inputs: var InputMap, id: InputId) =
  let
    wasDown = inputs.states.getOrDefault(id).down
    isDown = inputs.actionDown(id)
  inputs.states[id] = InputButtonState(
    down: isDown,
    pressed: (not wasDown) and isDown,
    released: wasDown and (not isDown),
  )

proc updateActionsForSource(inputs: var InputMap, source: InputSource) =
  for id, sources in inputs.bindings:
    for bound in sources:
      if bound == source:
        inputs.updateAction(id)
        break

proc setSourceDown(inputs: var InputMap, source: InputSource, isDown: bool) =
  let wasDown = inputs.sourceDown.getOrDefault(source, false)
  if wasDown == isDown:
    return
  inputs.sourceDown[source] = isDown
  inputs.updateActionsForSource(source)

proc maskKeyboardInput*(inputs: var InputMap) =
  var maskedSources: seq[InputSource]
  for source, isDown in inputs.sourceDown.pairs:
    if source.kind == InputKeyboard and isDown:
      maskedSources.add source
  for source in maskedSources:
    inputs.setSourceDown(source, false)

proc handleEvent*(inputs: var InputMap, event: sdl3.Event) =
  let eventType = uint32(event.common.`type`)
  if eventType == uint32(EVENT_KEY_DOWN):
    if not event.key.repeat:
      inputs.setSourceDown(key(event.key.scancode), true)
  elif eventType == uint32(EVENT_KEY_UP):
    inputs.setSourceDown(key(event.key.scancode), false)
  elif eventType == uint32(EVENT_MOUSE_BUTTON_DOWN):
    inputs.mouseX = event.button.x.int
    inputs.mouseY = event.button.y.int
    inputs.setSourceDown(mouseButton(event.button.button), true)
  elif eventType == uint32(EVENT_MOUSE_BUTTON_UP):
    inputs.mouseX = event.button.x.int
    inputs.mouseY = event.button.y.int
    inputs.setSourceDown(mouseButton(event.button.button), false)
  elif eventType == uint32(EVENT_MOUSE_MOTION):
    inputs.mouseX = event.motion.x.int
    inputs.mouseY = event.motion.y.int
    inputs.mouseDeltaX += event.motion.xrel.float32
    inputs.mouseDeltaY += event.motion.yrel.float32
  elif eventType == uint32(EVENT_MOUSE_WHEEL):
    inputs.mouseWheelX += event.wheel.x.float32
    inputs.mouseWheelY += event.wheel.y.float32
    inputs.mouseX = event.wheel.mouse_x.int
    inputs.mouseY = event.wheel.mouse_y.int
  elif eventType == uint32(EVENT_GAMEPAD_BUTTON_DOWN):
    inputs.setSourceDown(gamepadButton(GamepadButton(event.gbutton.button)), true)
  elif eventType == uint32(EVENT_GAMEPAD_BUTTON_UP):
    inputs.setSourceDown(gamepadButton(GamepadButton(event.gbutton.button)), false)
  elif eventType == uint32(EVENT_TEXT_INPUT):
    if not event.text.text.isNil:
      inputs.textInput.add $event.text.text
  elif eventType == uint32(EVENT_TEXT_EDITING):
    inputs.textEditing =
      if event.edit.text.isNil:
        ""
      else:
        $event.edit.text

proc finishFrame*(inputs: var InputMap) =
  for state in inputs.states.mvalues:
    state.pressed = false
    state.released = false
  inputs.textInput.setLen 0
  inputs.textEditing.setLen 0
  inputs.mouseDeltaX = 0
  inputs.mouseDeltaY = 0
  inputs.mouseWheelX = 0
  inputs.mouseWheelY = 0

proc advanceTime*(inputs: var InputMap, dt: float64) =
  ## Advances gesture timers. Call once per frame before querying gestures.
  for state in inputs.doubleClicks.mvalues:
    if state.waiting:
      state.elapsed += max(dt, 0.0)

proc doubleClicked*(inputs: var InputMap, id: InputId,
    interval = DefaultDoubleClickInterval): bool =
  ## True on the second press of an action within `interval` seconds.
  ## The interval is supplied per query so different actions can use the
  ## timing that fits their interaction without maintaining separate maps.
  if not inputs.states.getOrDefault(id).pressed:
    return false
  var state = inputs.doubleClicks.getOrDefault(id)
  result = state.waiting and state.elapsed <= max(interval, 0.0)
  state.waiting = not result
  state.elapsed = 0.0
  inputs.doubleClicks[id] = state

proc down*(inputs: InputMap, id: InputId): bool =
  inputs.states.getOrDefault(id).down

proc anyDown*(inputs: InputMap): bool =
  for state in inputs.states.values:
    if state.down:
      return true

proc pressed*(inputs: InputMap, id: InputId): bool =
  inputs.states.getOrDefault(id).pressed

proc released*(inputs: InputMap, id: InputId): bool =
  inputs.states.getOrDefault(id).released

proc up*(inputs: InputMap, id: InputId): bool =
  not inputs.down(id)

proc typedInput*(inputs: InputMap): string =
  inputs.textInput

proc editingInput*(inputs: InputMap): string =
  inputs.textEditing

proc consumeTypedInput*(inputs: var InputMap): string =
  result = inputs.textInput
  inputs.textInput.setLen 0

proc consumeEditingInput*(inputs: var InputMap): string =
  result = inputs.textEditing
  inputs.textEditing.setLen 0

proc sources*(inputs: InputMap, id: InputId): seq[InputSource] =
  inputs.bindings.getOrDefault(id, @[])
