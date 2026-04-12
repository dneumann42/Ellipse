import os

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

task build_gpu_shaders, "Compile Vulkan SPIR-V shaders for the SDL3 GPU demo":
  createDir("tests/assets/gpu")
  exec "glslangValidator -V -S vert -o tests/assets/gpu/quad.vert.spv tests/assets/gpu/quad.vert"
  exec "glslangValidator -V -S frag -o tests/assets/gpu/quad.frag.spv tests/assets/gpu/quad.frag"

task test_sdl3_gpu_demo, "Run the manual SDL3 GPU quad demo":
  createDir("tests/assets/gpu")
  exec "glslangValidator -V -S vert -o tests/assets/gpu/quad.vert.spv tests/assets/gpu/quad.vert"
  exec "glslangValidator -V -S frag -o tests/assets/gpu/quad.frag.spv tests/assets/gpu/quad.frag"
  exec "nim c -r tests/t_sdl3_gpu_quad.nim"
