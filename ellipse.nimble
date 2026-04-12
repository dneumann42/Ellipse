# Package

version       = "0.0.0"
author        = "dneumann42"
description   = "A game engine for Ellipse"
license       = "Proprietary"
srcDir        = "src"


# Dependencies

requires "nim >= 2.2.8"

task test, "Run automated tests":
  exec "nim c -r tests/test1.nim"

task test_sdl3_demo, "Run the manual SDL3 callback hello-world demo test":
  exec "nim c -r tests/t_sdl3_hello.nim"
