import std/[tables, options]

import platform/SDL3

type
  KeyInputBinding* = object
    keycode*: Keycode
    scancode*: Scancode
    repeat*: bool
  
  GamepadInputBinding* = object

  InputBinding* = object
    key*: Option[KeyInputBinding]
    btn*: Option[GamepadInputBinding]

  InputActionState* = object
    pressed*: bool
    down*: bool
    released*: bool

  Input*[A: enum] = object
    bindings*: Table[A, InputBinding]
    states*: Table[A, InputActionState]

  InputBinder*[A: enum] = ref object
    input: Input[A]

proc key*(sc: Scancode, repeat = false): KeyInputBinding =
  KeyInputBinding(scancode: sc, repeat: repeat)

proc binder*[A: enum](): InputBinder[A] =
  result = InputBinder[A](input: Input[A]())

proc add*[A: enum](ib: InputBinder[A], action: A, k: KeyInputBinding): InputBinder[A] =
  var binding =
    if ib.input.bindings.hasKey(action):
      ib.input.bindings[action]
    else:
      default(InputBinding)
  binding.key = some(k)
  ib.input.bindings[action] = binding
  ib

proc add*[A: enum](ib: InputBinder[A], action: A, btn: GamepadInputBinding): InputBinder[A] =
  var binding =
    if ib.input.bindings.hasKey(action):
      ib.input.bindings[action]
    else:
      default(InputBinding)
  binding.btn = some(btn)
  ib.input.bindings[action] = binding
  ib

proc build*[A: enum](ib: InputBinder[A]): Input[A] =
  result = ib.input

proc stateFor[A: enum](input: Input[A]; action: A): InputActionState =
  if input.states.hasKey(action):
    input.states[action]
  else:
    default(InputActionState)

proc pressed*[A: enum](input: Input[A]; action: A): bool =
  input.stateFor(action).pressed

proc pressed*[A: enum](action: A; input: Input[A]): bool =
  input.pressed(action)

proc down*[A: enum](input: Input[A]; action: A): bool =
  input.stateFor(action).down

proc down*[A: enum](action: A; input: Input[A]): bool =
  input.down(action)

proc released*[A: enum](input: Input[A]; action: A): bool =
  input.stateFor(action).released

proc released*[A: enum](action: A; input: Input[A]): bool =
  input.released(action)

proc up*[A: enum](input: Input[A]; action: A): bool =
  not input.down(action)

proc up*[A: enum](action: A; input: Input[A]): bool =
  input.up(action)

proc matches(binding: KeyInputBinding; keycode: Keycode; scancode: Scancode): bool =
  binding.scancode == scancode or (binding.keycode != 0'u32 and binding.keycode == keycode)

proc handleKeyDown*[A: enum](
  input: var Input[A];
  keycode: Keycode;
  scancode: Scancode;
  repeat: bool
) =
  for action, binding in input.bindings.pairs:
    if binding.key.isNone:
      continue
    let keyBinding = binding.key.get()
    if not keyBinding.matches(keycode, scancode):
      continue
    if repeat and not keyBinding.repeat:
      continue

    var state = input.stateFor(action)
    if not state.down or keyBinding.repeat:
      state.pressed = true
    state.down = true
    state.released = false
    input.states[action] = state

proc handleKeyUp*[A: enum](
  input: var Input[A];
  keycode: Keycode;
  scancode: Scancode
) =
  for action, binding in input.bindings.pairs:
    if binding.key.isNone:
      continue
    let keyBinding = binding.key.get()
    if not keyBinding.matches(keycode, scancode):
      continue

    var state = input.stateFor(action)
    if state.down:
      state.released = true
    state.down = false
    state.pressed = false
    input.states[action] = state

proc lateUpdate*[A: enum](input: var Input[A]) =
  for action in input.states.keys:
    var state = input.states[action]
    state.pressed = false
    state.released = false
    input.states[action] = state
