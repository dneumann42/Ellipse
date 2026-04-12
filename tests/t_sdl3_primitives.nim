import std/math

import ellipse/platform/application

type
  DemoState = object
    frameIndex: uint64

const
  windowWidth = 1280
  windowHeight = 720

proc pointOnCircle(center: array[2, cfloat]; radius: cfloat; angle: cfloat): array[2, cfloat] =
  [
    center[0] + cos(angle) * radius,
    center[1] + sin(angle) * radius
  ]

plugin Demo:
  proc draw(artist: var Artist2D; frameIndex: var uint64) =
    let time = cfloat(frameIndex) * 0.016'f32
    inc frameIndex

    let panelColor = [0.10'f32, 0.12'f32, 0.16'f32, 0.92'f32]
    let accent = [0.95'f32, 0.72'f32, 0.26'f32, 1'f32]
    let cyan = [0.24'f32, 0.82'f32, 0.93'f32, 1'f32]
    let pink = [0.98'f32, 0.40'f32, 0.63'f32, 1'f32]
    let green = [0.35'f32, 0.85'f32, 0.52'f32, 1'f32]
    let white = [0.95'f32, 0.96'f32, 0.98'f32, 1'f32]

    discard drawFilledRect(artist, [52'f32, 72'f32], [320'f32, 236'f32], panelColor)
    discard drawFilledRect(artist, [408'f32, 72'f32], [340'f32, 236'f32], panelColor)
    discard drawFilledRect(artist, [786'f32, 72'f32], [442'f32, 236'f32], panelColor)
    discard drawFilledRect(artist, [52'f32, 346'f32], [1176'f32, 312'f32], [0.08'f32, 0.10'f32, 0.14'f32, 0.96'f32])

    discard drawText(artist, "FILLED / STROKED RECTS", [78'f32, 96'f32], white, 2'f32)
    discard drawFilledRect(artist, [84'f32, 140'f32], [120'f32, 78'f32], accent)
    discard drawFilledRect(artist, [230'f32, 140'f32], [96'f32, 140'f32], [0.18'f32, 0.24'f32, 0.34'f32, 1'f32])
    discard drawRect(artist, [230'f32, 140'f32], [96'f32, 140'f32], cyan, 6'f32 + sin(time * 1.2'f32) * 2'f32)
    discard drawRect(artist, [96'f32, 232'f32], [226'f32, 42'f32], pink, 10'f32)
    discard drawText(artist, "rectangles now share the stage", [82'f32, 286'f32], [0.80'f32, 0.83'f32, 0.90'f32, 1'f32], 1.5'f32)

    discard drawText(artist, "LINES + TRIANGLES", [436'f32, 96'f32], white, 2'f32)
    let hub = [578'f32, 192'f32]
    for i in 0 ..< 12:
      let angle = time * 0.55'f32 + cfloat(i) * (PI.cfloat / 6'f32)
      let outer = pointOnCircle(hub, 92'f32, angle)
      let thickness = 2'f32 + cfloat(i mod 4) * 2.5'f32
      let tint = [
        0.30'f32 + 0.05'f32 * cfloat(i),
        0.35'f32 + 0.04'f32 * cfloat((i + 3) mod 6),
        0.95'f32,
        0.95'f32
      ]
      discard drawLine(artist, hub, outer, tint, thickness)
    let triCenter = [682'f32, 212'f32]
    let triAngle = -time * 0.9'f32
    discard drawTriangle(
      artist,
      pointOnCircle(triCenter, 72'f32, triAngle),
      pointOnCircle(triCenter, 72'f32, triAngle + 2'f32 * PI.cfloat / 3'f32),
      pointOnCircle(triCenter, 72'f32, triAngle + 4'f32 * PI.cfloat / 3'f32),
      green
    )
    discard drawLine(artist, [442'f32, 276'f32], [716'f32, 144'f32], [1'f32, 1'f32, 1'f32, 0.24'f32], 2'f32)

    discard drawText(artist, "CIRCLES + RINGS", [818'f32, 96'f32], white, 2'f32)
    let orbitCenter = [930'f32, 194'f32]
    let pulse = 18'f32 * (0.5'f32 + 0.5'f32 * sin(time * 1.7'f32))
    discard drawCircle(artist, orbitCenter, 44'f32 + pulse, [0.99'f32, 0.56'f32, 0.18'f32, 0.92'f32])
    discard drawRing(artist, [1086'f32, 194'f32], 82'f32, cyan, 14'f32 + 4'f32 * sin(time))
    for i in 0 ..< 8:
      let angle = -time * 0.8'f32 + cfloat(i) * (PI.cfloat / 4'f32)
      let point = pointOnCircle([1086'f32, 194'f32], 82'f32, angle)
      discard drawLine(artist, [1086'f32, 194'f32], point, [1'f32, 1'f32, 1'f32, 0.16'f32], 2'f32)

    discard drawText(artist, "COMPOSITION", [84'f32, 372'f32], white, 2'f32)
    discard drawFilledRect(artist, [86'f32, 416'f32], [540'f32, 198'f32], [0.12'f32, 0.15'f32, 0.22'f32, 1'f32])
    discard drawCircle(artist, [218'f32, 514'f32], 84'f32, [0.96'f32, 0.30'f32, 0.34'f32, 0.88'f32])
    discard drawRing(artist, [306'f32, 514'f32], 104'f32, [0.20'f32, 0.82'f32, 0.98'f32, 0.92'f32], 18'f32)
    discard drawTriangle(artist, [364'f32, 428'f32], [576'f32, 530'f32], [430'f32, 612'f32], [0.98'f32, 0.76'f32, 0.24'f32, 0.85'f32])
    discard drawLine(artist, [102'f32, 594'f32], [598'f32, 440'f32], [1'f32, 1'f32, 1'f32, 0.28'f32], 6'f32)
    discard drawRect(artist, [86'f32, 416'f32], [540'f32, 198'f32], [1'f32, 1'f32, 1'f32, 0.16'f32], 3'f32)

    discard drawFilledRect(artist, [668'f32, 416'f32], [530'f32, 198'f32], [0.12'f32, 0.15'f32, 0.22'f32, 1'f32])
    for row in 0 ..< 3:
      for col in 0 ..< 5:
        let center = [734'f32 + cfloat(col) * 90'f32, 464'f32 + cfloat(row) * 58'f32]
        let radius = 14'f32 + cfloat(row * 5 + col * 2)
        let hue = cfloat(row * 5 + col)
        discard drawRing(
          artist,
          center,
          radius + 18'f32,
          [
            0.30'f32 + 0.10'f32 * sin(hue),
            0.55'f32 + 0.08'f32 * cos(hue),
            0.78'f32 + 0.05'f32 * sin(hue * 0.7'f32),
            0.95'f32
          ],
          6'f32
        )
        discard drawCircle(artist, center, radius, [
          0.96'f32,
          0.76'f32 - 0.05'f32 * cfloat(row),
          0.26'f32 + 0.10'f32 * cfloat(col) / 4'f32,
          0.92'f32
        ])

    discard drawText(artist, "Artist2D primitive drawing demo", [84'f32, 636'f32], [0.82'f32, 0.86'f32, 0.93'f32, 1'f32], 1.75'f32)
    discard drawText(artist, "line  triangle  circle  ring  stroke", [726'f32, 636'f32], [0.95'f32, 0.72'f32, 0.26'f32, 1'f32], 1.75'f32)

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
      clearColor: FColor(r: 0.04, g: 0.06, b: 0.09, a: 1.0)
    ),
    DemoState()
  )
