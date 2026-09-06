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
requires "zlib >= 0.1.0"
requires "https://github.com/nim-lang/sdl3#e5f87eb992f828419aad83075ea1c41147fbb088"
requires "https://github.com/dneumann42/plugnim#head"
requires "https://github.com/dneumann42/nest#head"
requires "https://github.com/dneumann42/owl#head"

task shaders, "Build GLSL shaders":
  mkDir "build/shaders"
  exec "glslc -fshader-stage=vert shaders/triangle.vert -o build/shaders/triangle.vert.spv"
  exec "glslc -fshader-stage=frag shaders/triangle.frag -o build/shaders/triangle.frag.spv"
  exec "glslc -fshader-stage=vert shaders/water.vert -o build/shaders/water.vert.spv"
  exec "glslc -fshader-stage=frag shaders/water.frag -o build/shaders/water.frag.spv"
  exec "glslc -fshader-stage=vert shaders/sky.vert -o build/shaders/sky.vert.spv"
  exec "glslc -fshader-stage=frag shaders/sky.frag -o build/shaders/sky.frag.spv"
  exec "glslc -fshader-stage=vert shaders/fullscreen.vert -o build/shaders/fullscreen.vert.spv"
  exec "glslc -fshader-stage=frag shaders/ssao.frag -o build/shaders/ssao.frag.spv"
  exec "glslc -fshader-stage=frag shaders/composite.frag -o build/shaders/composite.frag.spv"
  exec "glslc -fshader-stage=frag shaders/depthPreview.frag -o build/shaders/depthPreview.frag.spv"
  exec "glslc -fshader-stage=frag shaders/depth.frag -o build/shaders/depth.frag.spv"
