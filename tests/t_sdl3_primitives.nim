import std/[math, os]

import ellipse/platform/application

type
  DemoState = object
    frameIndex: uint64
    supersampleScale: int

const
  windowWidth = 1280
  windowHeight = 720
  demoFontPath = currentSourcePath.parentDir / "assets" / "fonts" / "Manrope-Regular.ttf"
  sceneCanvasId = "scene"
  scene2xCanvasId = "scene2x"
  scene4xCanvasId = "scene4x"
  scene8xCanvasId = "scene8x"

proc pointOnCircle(center: array[2, cfloat]; radius: cfloat; angle: cfloat): array[2, cfloat] =
  [
    center[0] + cos(angle) * radius,
    center[1] + sin(angle) * radius
  ]

proc scaled(point: array[2, cfloat]; factor: cfloat): array[2, cfloat] =
  [point[0] * factor, point[1] * factor]

proc scaledSize(size: array[2, cfloat]; factor: cfloat): array[2, cfloat] =
  [size[0] * factor, size[1] * factor]

proc canvasIdForScale(scale: int): string =
  case scale
  of 2: scene2xCanvasId
  of 4: scene4xCanvasId
  of 8: scene8xCanvasId
  else: sceneCanvasId

proc supersampleLabel(scale: int): string =
  case scale
  of 2: "2x supersample"
  of 4: "4x supersample"
  of 8: "8x supersample"
  else: "native"

proc drawScene(artist: var Artist2D; frameIndex: var uint64; scale: cfloat) =
    let time = cfloat(frameIndex) * 0.016'f32
    inc frameIndex

    let panelColor = [0.10'f32, 0.12'f32, 0.16'f32, 0.92'f32]
    let accent = [0.95'f32, 0.72'f32, 0.26'f32, 1'f32]
    let cyan = [0.24'f32, 0.82'f32, 0.93'f32, 1'f32]
    let pink = [0.98'f32, 0.40'f32, 0.63'f32, 1'f32]
    let green = [0.35'f32, 0.85'f32, 0.52'f32, 1'f32]
    let white = [0.95'f32, 0.96'f32, 0.98'f32, 1'f32]

    discard drawFilledRect(artist, scaled([52'f32, 72'f32], scale), scaledSize([320'f32, 236'f32], scale), panelColor)
    discard drawFilledRect(artist, scaled([408'f32, 72'f32], scale), scaledSize([340'f32, 236'f32], scale), panelColor)
    discard drawFilledRect(artist, scaled([786'f32, 72'f32], scale), scaledSize([442'f32, 236'f32], scale), panelColor)
    discard drawFilledRect(artist, scaled([52'f32, 346'f32], scale), scaledSize([1176'f32, 312'f32], scale), [0.08'f32, 0.10'f32, 0.14'f32, 0.96'f32])

    discard drawText(artist, "FILLED / STROKED RECTS", scaled([78'f32, 96'f32], scale), white, 2'f32 * scale)
    discard drawFilledRect(artist, scaled([84'f32, 140'f32], scale), scaledSize([120'f32, 78'f32], scale), accent)
    discard drawFilledRect(artist, scaled([230'f32, 140'f32], scale), scaledSize([96'f32, 140'f32], scale), [0.18'f32, 0.24'f32, 0.34'f32, 1'f32])
    discard drawRect(artist, scaled([230'f32, 140'f32], scale), scaledSize([96'f32, 140'f32], scale), cyan, (6'f32 + sin(time * 1.2'f32) * 2'f32) * scale)
    discard drawRect(artist, scaled([96'f32, 232'f32], scale), scaledSize([226'f32, 42'f32], scale), pink, 10'f32 * scale)
    discard drawText(artist, "rectangles now share the stage", scaled([82'f32, 286'f32], scale), [0.80'f32, 0.83'f32, 0.90'f32, 1'f32], 1.5'f32 * scale)

    discard drawText(artist, "LINES + TRIANGLES", scaled([436'f32, 96'f32], scale), white, 2'f32 * scale)
    let hub = scaled([578'f32, 192'f32], scale)
    for i in 0 ..< 12:
      let angle = time * 0.55'f32 + cfloat(i) * (PI.cfloat / 6'f32)
      let outer = pointOnCircle(hub, 92'f32 * scale, angle)
      let thickness = (2'f32 + cfloat(i mod 4) * 2.5'f32) * scale
      let tint = [
        0.30'f32 + 0.05'f32 * cfloat(i),
        0.35'f32 + 0.04'f32 * cfloat((i + 3) mod 6),
        0.95'f32,
        0.95'f32
      ]
      discard drawLine(artist, hub, outer, tint, thickness)
    let triCenter = scaled([682'f32, 212'f32], scale)
    let triAngle = -time * 0.9'f32
    discard drawTriangle(
      artist,
      pointOnCircle(triCenter, 72'f32 * scale, triAngle),
      pointOnCircle(triCenter, 72'f32 * scale, triAngle + 2'f32 * PI.cfloat / 3'f32),
      pointOnCircle(triCenter, 72'f32 * scale, triAngle + 4'f32 * PI.cfloat / 3'f32),
      green
    )
    discard drawLine(artist, scaled([442'f32, 276'f32], scale), scaled([716'f32, 144'f32], scale), [1'f32, 1'f32, 1'f32, 0.24'f32], 2'f32 * scale)

    discard drawText(artist, "CIRCLES + RINGS", scaled([818'f32, 96'f32], scale), white, 2'f32 * scale)
    let orbitCenter = scaled([930'f32, 194'f32], scale)
    let pulse = 18'f32 * (0.5'f32 + 0.5'f32 * sin(time * 1.7'f32))
    discard drawCircle(artist, orbitCenter, (44'f32 + pulse) * scale, [0.99'f32, 0.56'f32, 0.18'f32, 0.92'f32])
    discard drawRing(artist, scaled([1086'f32, 194'f32], scale), 82'f32 * scale, cyan, (14'f32 + 4'f32 * sin(time)) * scale)
    for i in 0 ..< 8:
      let angle = -time * 0.8'f32 + cfloat(i) * (PI.cfloat / 4'f32)
      let point = pointOnCircle(scaled([1086'f32, 194'f32], scale), 82'f32 * scale, angle)
      discard drawLine(artist, scaled([1086'f32, 194'f32], scale), point, [1'f32, 1'f32, 1'f32, 0.16'f32], 2'f32 * scale)

    discard drawText(artist, "COMPOSITION", scaled([84'f32, 372'f32], scale), white, 2'f32 * scale)
    discard drawFilledRect(artist, scaled([86'f32, 416'f32], scale), scaledSize([540'f32, 198'f32], scale), [0.12'f32, 0.15'f32, 0.22'f32, 1'f32])
    discard drawCircle(artist, scaled([218'f32, 514'f32], scale), 84'f32 * scale, [0.96'f32, 0.30'f32, 0.34'f32, 0.88'f32])
    discard drawRing(artist, scaled([306'f32, 514'f32], scale), 104'f32 * scale, [0.20'f32, 0.82'f32, 0.98'f32, 0.92'f32], 18'f32 * scale)
    discard drawTriangle(artist, scaled([364'f32, 428'f32], scale), scaled([576'f32, 530'f32], scale), scaled([430'f32, 612'f32], scale), [0.98'f32, 0.76'f32, 0.24'f32, 0.85'f32])
    discard drawLine(artist, scaled([102'f32, 594'f32], scale), scaled([598'f32, 440'f32], scale), [1'f32, 1'f32, 1'f32, 0.28'f32], 6'f32 * scale)
    discard drawRect(artist, scaled([86'f32, 416'f32], scale), scaledSize([540'f32, 198'f32], scale), [1'f32, 1'f32, 1'f32, 0.16'f32], 3'f32 * scale)

    discard drawFilledRect(artist, scaled([668'f32, 416'f32], scale), scaledSize([530'f32, 198'f32], scale), [0.12'f32, 0.15'f32, 0.22'f32, 1'f32])
    for row in 0 ..< 3:
      for col in 0 ..< 5:
        let center = scaled([734'f32 + cfloat(col) * 90'f32, 464'f32 + cfloat(row) * 58'f32], scale)
        let radius = 14'f32 + cfloat(row * 5 + col * 2)
        let hue = cfloat(row * 5 + col)
        discard drawRing(
          artist,
          center,
          (radius + 18'f32) * scale,
          [
            0.30'f32 + 0.10'f32 * sin(hue),
            0.55'f32 + 0.08'f32 * cos(hue),
            0.78'f32 + 0.05'f32 * sin(hue * 0.7'f32),
            0.95'f32
          ],
          6'f32 * scale
        )
        discard drawCircle(artist, center, radius * scale, [
          0.96'f32,
          0.76'f32 - 0.05'f32 * cfloat(row),
          0.26'f32 + 0.10'f32 * cfloat(col) / 4'f32,
          0.92'f32
        ])

    discard drawText(artist, "Artist2D primitive drawing demo", scaled([84'f32, 636'f32], scale), [0.82'f32, 0.86'f32, 0.93'f32, 1'f32], 1.75'f32 * scale)
    discard drawText(artist, "line  triangle  circle  ring  stroke", scaled([726'f32, 636'f32], scale), [0.95'f32, 0.72'f32, 0.26'f32, 1'f32], 1.75'f32 * scale)

plugin Demo:
  proc load(canvases: var CanvasManager) =
    registerCanvas(canvases, RenderCanvasConfig(
      id: sceneCanvasId,
      width: windowWidth,
      height: windowHeight,
      scaleMode: csmStretch,
      filterMode: tfLinear,
      layer: 0,
      clearColor: FColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    ))
    registerCanvas(canvases, RenderCanvasConfig(
      id: scene2xCanvasId,
      width: windowWidth * 2,
      height: windowHeight * 2,
      scaleMode: csmStretch,
      filterMode: tfLinear,
      layer: 0,
      clearColor: FColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    ))
    registerCanvas(canvases, RenderCanvasConfig(
      id: scene4xCanvasId,
      width: windowWidth * 4,
      height: windowHeight * 4,
      scaleMode: csmStretch,
      filterMode: tfLinear,
      layer: 0,
      clearColor: FColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    ))
    registerCanvas(canvases, RenderCanvasConfig(
      id: scene8xCanvasId,
      width: windowWidth * 8,
      height: windowHeight * 8,
      scaleMode: csmStretch,
      filterMode: tfLinear,
      layer: 0,
      clearColor: FColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    ))

  proc listen(
    msg: KeyDownMessage;
    messages: var PluginMessages;
    supersampleScale: var int
  ) =
    if msg.repeat:
      messages.handle(KeyDownMessage)
      return

    case msg.scancode.ord
    of SCANCODE_1:
      supersampleScale = 1
    of SCANCODE_2:
      supersampleScale = 2
    of SCANCODE_3:
      supersampleScale = 4
    of SCANCODE_4:
      supersampleScale = 8
    else:
      discard

    messages.handle(KeyDownMessage)

  proc draw(
    artist: var Artist2D;
    canvases: var CanvasManager;
    frameIndex: var uint64;
    supersampleScale: int
  ) =
    if supersampleScale <= 1:
      withCanvas(canvases, artist, sceneCanvasId):
        drawScene(artist, frameIndex, 1'f32)
    else:
      withCanvas(canvases, artist, canvasIdForScale(supersampleScale)):
        drawScene(artist, frameIndex, supersampleScale.cfloat)

    let status = "1 native  2 2x  3 4x  4 8x: " & supersampleLabel(supersampleScale)
    discard drawText(artist, status, [28'f32, 22'f32], [0'f32, 0'f32, 0'f32, 0.8'f32], 2'f32)
    discard drawText(artist, status, [26'f32, 20'f32], [0.98'f32, 0.82'f32, 0.32'f32, 1'f32], 2'f32)

when isMainModule:
  startApplication(
    AppConfig(
      appId: "dev.ellipse.tests.sdl3primitives",
      title: "Ellipse SDL3 Primitives",
      width: windowWidth,
      height: windowHeight,
      windowFlags: 0,
      resizable: true,
      shaderFormat: GPU_SHADERFORMAT_SPIRV,
      driverName: "vulkan",
      debugMode: true,
      clearColor: FColor(r: 0.04, g: 0.06, b: 0.09, a: 1.0),
      defaultFontPath: demoFontPath,
      defaultFontSize: 10'f32
    ),
    DemoState(supersampleScale: 2)
  )
