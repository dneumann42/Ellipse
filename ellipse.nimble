import os

# Package

version       = "0.0.0"
author        = "dneumann42"
description   = "A game engine for Ellipse"
license       = "Proprietary"
srcDir        = "src"


# Dependencies

requires "nim >= 2.2.8"
requires "shui >= 0.1.0"
requires "toml_serialization >= 0.2.18"
requires "vmath >= 2.0.1"

task test, "Run automated tests":
  exec "nim c -r tests/test1.nim"
  exec "nim c -r tests/t_atlas.nim"
  exec "nim c -r tests/t_gridlighting.nim"
  exec "nim c -r tests/t_shadowmapping.nim"
  exec "nim c -r tests/t_inputs.nim"

task test_sdl3_demo, "Run the manual SDL3 callback hello-world demo test":
  exec "nim c -r tests/t_sdl3_hello.nim"

task build_gpu_shaders, "Compile Vulkan SPIR-V shaders for the SDL3 GPU demo":
  exec "mkdir -p src/ellipse/rendering/shaders"
  exec "mkdir -p tests/assets/gpu"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/primitives.vert.spv src/ellipse/rendering/shaders/primitives.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/primitives.frag.spv src/ellipse/rendering/shaders/primitives.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/sprites.vert.spv src/ellipse/rendering/shaders/sprites.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/sprites.frag.spv src/ellipse/rendering/shaders/sprites.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/solid3d.vert.spv src/ellipse/rendering/shaders/solid3d.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/solid3d.frag.spv src/ellipse/rendering/shaders/solid3d.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/shadow3d.vert.spv src/ellipse/rendering/shaders/shadow3d.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/shadow3d.frag.spv src/ellipse/rendering/shaders/shadow3d.frag"
  exec "glslangValidator -V -S vert -o tests/assets/gpu/quad.vert.spv tests/assets/gpu/quad.vert"
  exec "glslangValidator -V -S frag -o tests/assets/gpu/quad.frag.spv tests/assets/gpu/quad.frag"
  exec "glslangValidator -V -S vert -o tests/assets/gpu/sprites.vert.spv tests/assets/gpu/sprites.vert"
  exec "glslangValidator -V -S frag -o tests/assets/gpu/sprites.frag.spv tests/assets/gpu/sprites.frag"

task test_sdl3_gpu_demo, "Run the manual SDL3 GPU quad demo":
  exec "mkdir -p src/ellipse/rendering/shaders"
  exec "mkdir -p tests/assets/gpu"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/primitives.vert.spv src/ellipse/rendering/shaders/primitives.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/primitives.frag.spv src/ellipse/rendering/shaders/primitives.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/sprites.vert.spv src/ellipse/rendering/shaders/sprites.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/sprites.frag.spv src/ellipse/rendering/shaders/sprites.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/solid3d.vert.spv src/ellipse/rendering/shaders/solid3d.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/solid3d.frag.spv src/ellipse/rendering/shaders/solid3d.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/shadow3d.vert.spv src/ellipse/rendering/shaders/shadow3d.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/shadow3d.frag.spv src/ellipse/rendering/shaders/shadow3d.frag"
  exec "glslangValidator -V -S vert -o tests/assets/gpu/quad.vert.spv tests/assets/gpu/quad.vert"
  exec "glslangValidator -V -S frag -o tests/assets/gpu/quad.frag.spv tests/assets/gpu/quad.frag"
  exec "glslangValidator -V -S vert -o tests/assets/gpu/sprites.vert.spv tests/assets/gpu/sprites.vert"
  exec "glslangValidator -V -S frag -o tests/assets/gpu/sprites.frag.spv tests/assets/gpu/sprites.frag"
  exec "nim c -r tests/t_sdl3_gpu_quad.nim"

task test_sdl3_primitives_demo, "Run the manual SDL3 primitive drawing demo":
  exec "mkdir -p src/ellipse/rendering/shaders"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/primitives.vert.spv src/ellipse/rendering/shaders/primitives.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/primitives.frag.spv src/ellipse/rendering/shaders/primitives.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/sprites.vert.spv src/ellipse/rendering/shaders/sprites.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/sprites.frag.spv src/ellipse/rendering/shaders/sprites.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/solid3d.vert.spv src/ellipse/rendering/shaders/solid3d.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/solid3d.frag.spv src/ellipse/rendering/shaders/solid3d.frag"
  exec "glslangValidator -V -S vert -o src/ellipse/rendering/shaders/shadow3d.vert.spv src/ellipse/rendering/shaders/shadow3d.vert"
  exec "glslangValidator -V -S frag -o src/ellipse/rendering/shaders/shadow3d.frag.spv src/ellipse/rendering/shaders/shadow3d.frag"
  exec "nim c -r tests/t_sdl3_primitives.nim"
