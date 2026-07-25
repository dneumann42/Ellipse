# Package

version = "0.0.0"
author = "dneumann42"
description = "A game engine"
license = "Proprietary"
srcDir = "src"
bin = @["ellipse"]

# Dependencies

requires "nim >= 2.2.10"

requires "vmath >= 3.0.0"
requires "chroma >= 1.0.0"
requires "https://github.com/nim-lang/sdl3"
requires "plugnim"
requires "nest"

task shaders, "Build GLSL shaders":
  mkDir "build/shaders"
  exec "glslc -fshader-stage=vert shaders/triangle.vert -o build/shaders/triangle.vert.spv"
  exec "glslc -fshader-stage=frag shaders/triangle.frag -o build/shaders/triangle.frag.spv"
