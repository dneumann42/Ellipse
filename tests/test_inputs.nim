import std/unittest

import sdl3
import ellipse/inputs

proc mouseButtonEvent(eventType: uint32): Event =
  result.common.`type` = eventType
  result.button.button = BUTTON_LEFT

suite "input gestures":
  test "double click respects a tunable interval":
    var inputs = InputMap.init()
    inputs.addBinding("primary", mouseButton(BUTTON_LEFT))

    inputs.handleEvent(mouseButtonEvent(uint32(EVENT_MOUSE_BUTTON_DOWN)))
    check not inputs.doubleClicked("primary", interval = 0.2)
    inputs.handleEvent(mouseButtonEvent(uint32(EVENT_MOUSE_BUTTON_UP)))
    inputs.finishFrame()
    inputs.advanceTime(0.19)
    inputs.handleEvent(mouseButtonEvent(uint32(EVENT_MOUSE_BUTTON_DOWN)))
    check inputs.doubleClicked("primary", interval = 0.2)

    inputs.handleEvent(mouseButtonEvent(uint32(EVENT_MOUSE_BUTTON_UP)))
    inputs.finishFrame()
    inputs.advanceTime(0.21)
    inputs.handleEvent(mouseButtonEvent(uint32(EVENT_MOUSE_BUTTON_DOWN)))
    check not inputs.doubleClicked("primary", interval = 0.2)
