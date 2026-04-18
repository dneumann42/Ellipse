import unittest

import ellipse/inputs
import ellipse/platform/SDL3

type
  TestAction = enum
    Jump
    Fire

suite "inputs":
  test "key down sets pressed and down":
    var input = binder[TestAction]()
      .add(Jump, key(SCANCODE_W))
      .build()

    input.handleKeyDown(0'u32, SCANCODE_W, false)

    check Jump.pressed(input)
    check Jump.down(input)
    check not Jump.released(input)
    check not Jump.up(input)

  test "late update clears transient pressed state":
    var input = binder[TestAction]()
      .add(Jump, key(SCANCODE_W))
      .build()

    input.handleKeyDown(0'u32, SCANCODE_W, false)
    input.lateUpdate()

    check not Jump.pressed(input)
    check Jump.down(input)
    check not Jump.released(input)

  test "key up sets released and clears down":
    var input = binder[TestAction]()
      .add(Jump, key(SCANCODE_W))
      .build()

    input.handleKeyDown(0'u32, SCANCODE_W, false)
    input.lateUpdate()
    input.handleKeyUp(0'u32, SCANCODE_W)

    check not Jump.pressed(input)
    check not Jump.down(input)
    check Jump.released(input)
    check Jump.up(input)

  test "repeat keydown is ignored unless binding allows repeat":
    var input = binder[TestAction]()
      .add(Jump, key(SCANCODE_W))
      .add(Fire, key(SCANCODE_A, repeat = true))
      .build()

    input.handleKeyDown(0'u32, SCANCODE_W, false)
    input.handleKeyDown(0'u32, SCANCODE_A, false)
    input.lateUpdate()
    input.handleKeyDown(0'u32, SCANCODE_W, true)
    input.handleKeyDown(0'u32, SCANCODE_A, true)

    check not Jump.pressed(input)
    check Jump.down(input)
    check Fire.pressed(input)
    check Fire.down(input)
