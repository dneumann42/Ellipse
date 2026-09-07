# Package

version = "0.1.0"
author = "dneumann42"
description = "A game engine"
license = "Proprietary"
srcDir = "src"
bin = @["ellipse"]
installExt = @["nim"]
installDirs = @["shaders", "scripts"]

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
  exec "bash scripts/build-shaders.sh spirv"
