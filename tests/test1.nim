import unittest

import ellipse/platform/SDL3

suite "SDL3 binding smoke tests":
  test "core constants are available":
    check SDL_INIT_VIDEO == 0x20'u32
    check SDL_EVENT_QUIT == 0x100'u32
    check SDL_EVENT_WINDOW_CLOSE_REQUESTED == 0x210'u32

  test "event layout exposes the type field":
    var event: SDL_Event
    event.`type` = SDL_EVENT_QUIT
    check event.`type` == SDL_EVENT_QUIT
