import std/os

import ellipse/platform/application

type
  DemoState = object

const
  demoFontPath = currentSourcePath.parentDir / "assets" / "fonts" / "Manrope-Regular.ttf"

plugin Demo:
  proc load(canvases: var CanvasManager) =
    registerCanvas(canvases, RenderCanvasConfig(
      id: "hello",
      width: 320,
      height: 180,
      scaleMode: csmContain,
      layer: 1
    ))

  proc draw(artist: var Artist2D; canvases: var CanvasManager) =
    var background = initSprite2D()
    background.position = [24'f32, 24'f32]
    background.size = [200'f32, 120'f32]
    background.origin = [0'f32, 0'f32]
    background.tint = [0.15'f32, 0.3'f32, 0.55'f32, 1'f32]
    discard drawSprite(artist, background)

    withCanvas(canvases, artist, "hello"):
      var canvasSprite = initSprite2D()
      canvasSprite.position = [16'f32, 16'f32]
      canvasSprite.size = [288'f32, 148'f32]
      canvasSprite.origin = [0'f32, 0'f32]
      canvasSprite.tint = [1'f32, 0.65'f32, 0.2'f32, 1'f32]
      discard drawSprite(artist, canvasSprite)

when isMainModule:
  startApplication(
    AppConfig(
      appId: "dev.ellipse.tests.sdl3hello",
      title: "Ellipse SDL3 Hello",
      width: 800,
      height: 600,
      windowFlags: 0,
      defaultFontPath: demoFontPath,
      defaultFontSize: 10'f32
    ),
    DemoState()
  )
