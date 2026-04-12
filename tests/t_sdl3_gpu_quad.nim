import std/math

import ellipse/platform/application

type
  SpriteMotion = object
    basePosition: array[2, cfloat]
    velocity: array[2, cfloat]
    size: array[2, cfloat]
    baseScale: cfloat
    scaleAmplitude: cfloat
    scaleSpeed: cfloat
    rotationOffset: cfloat
    rotationSpeed: cfloat
    tint: array[4, cfloat]
    textureKind: int
    regionIndex: int

  DemoState = object
    atlasTexture: GPUTextureHandle
    texture1: GPUTextureHandle
    texture2: GPUTextureHandle
    texture3: GPUTextureHandle
    texture4: GPUTextureHandle
    texture5: GPUTextureHandle
    texture6: GPUTextureHandle
    texture7: GPUTextureHandle
    motions: seq[SpriteMotion]
    frameIndex: uint64

const
  windowWidth = 1280
  windowHeight = 720
  textureSize = 256
  spriteCount = 50_000
  pi32 = PI.cfloat

proc wrap(value, extent: cfloat): cfloat =
  if extent <= 0:
    return value
  value - floor(value / extent) * extent

proc atlasRegion(index: int): SpriteTextureRegion =
  let column = cfloat(index mod 2) * 0.5
  let row = cfloat(index div 2) * 0.5
  spriteTextureRegion(column, row, column + 0.5, row + 0.5)

proc makePatternPixels(size: int; variant: int): seq[uint8] =
  result = newSeq[uint8](size * size * 4)
  let half = size div 2
  for y in 0 ..< size:
    for x in 0 ..< size:
      let xf = x.cfloat / max(size - 1, 1).cfloat
      let yf = y.cfloat / max(size - 1, 1).cfloat
      var rgba: array[4, uint8]
      case variant
      of 0:
        let topLeft = x < half and y < half
        let topRight = x >= half and y < half
        let bottomLeft = x < half and y >= half
        if topLeft:
          rgba = [uint8(255 * xf), uint8(70), uint8(120), uint8(255)]
        elif topRight:
          rgba = [uint8(40), uint8(255 * yf), uint8(210), uint8(255)]
        elif bottomLeft:
          rgba = [uint8(255), uint8(200 * xf), uint8(20), uint8(255)]
        else:
          let checker = (((x div 12) + (y div 12)) and 1) == 0
          rgba =
            if checker: [uint8(245), uint8(245), uint8(245), uint8(255)]
            else: [uint8(25), uint8(25), uint8(25), uint8(255)]
      of 1:
        let stripe = sin(xf * 18'f32 + yf * 7'f32)
        rgba = [
          uint8(40 + 110 * (xf + 0.2)),
          uint8(150 + 80 * max(stripe, 0'f32)),
          uint8(220),
          uint8(255)
        ]
      of 2:
        let dx = xf - 0.5'f32
        let dy = yf - 0.5'f32
        let dist = sqrt(dx * dx + dy * dy)
        let ring = abs(sin(dist * 42'f32))
        rgba = [
          uint8(240 * ring),
          uint8(40 + 150 * (1'f32 - dist)),
          uint8(80 + 120 * dist),
          uint8(255)
        ]
      of 3:
        let wave = abs(sin((xf + yf) * 30'f32))
        rgba = [
          uint8(220 * wave),
          uint8(70 + 140 * xf),
          uint8(255 * yf),
          uint8(255)
        ]
      of 4:
        let scan = (((x div 8) xor (y div 8)) and 1).cfloat
        rgba = [
          uint8(80 + 90 * scan),
          uint8(190),
          uint8(40 + 160 * (1'f32 - scan)),
          uint8(255)
        ]
      of 5:
        let diag = abs(sin((xf - yf) * 36'f32))
        rgba = [
          uint8(250),
          uint8(80 + 120 * diag),
          uint8(40 + 180 * xf),
          uint8(255)
        ]
      of 6:
        let radial = max(0'f32, 1'f32 - sqrt((xf - 0.5'f32)^2 + (yf - 0.5'f32)^2) * 1.7'f32)
        rgba = [
          uint8(20 + 220 * yf),
          uint8(20 + 200 * radial),
          uint8(220),
          uint8(255)
        ]
      else:
        let bars = (((x div 16) + variant) mod 3).cfloat
        rgba = [
          uint8(70 + 60 * bars),
          uint8(40 + 170 * xf),
          uint8(120 + 110 * yf),
          uint8(255)
        ]

      let offset = (y * size + x) * 4
      result[offset + 0] = rgba[0]
      result[offset + 1] = rgba[1]
      result[offset + 2] = rgba[2]
      result[offset + 3] = rgba[3]

proc buildMotions(count: int): seq[SpriteMotion] =
  result = newSeq[SpriteMotion](count)
  for i in 0 ..< count:
    let column = i mod 600
    let row = i div 600
    let phase = cfloat(i mod 2048) * 0.041'f32
    let hue = cfloat(i mod 360) / 359'f32
    result[i] = SpriteMotion(
      basePosition: [
        cfloat((column * 11) mod (windowWidth + 420) - 160),
        cfloat((row * 9) mod (windowHeight + 420) - 160)
      ],
      velocity: [
        cos(phase) * (18'f32 + cfloat(i mod 23)),
        sin(phase * 1.17'f32) * (14'f32 + cfloat(i mod 19))
      ],
      size: [
        8'f32 + cfloat(i mod 21),
        8'f32 + cfloat((i * 7) mod 19)
      ],
      baseScale: 0.55'f32 + cfloat(i mod 5) * 0.18'f32,
      scaleAmplitude: 0.08'f32 + cfloat(i mod 7) * 0.03'f32,
      scaleSpeed: 0.75'f32 + cfloat(i mod 11) * 0.09'f32,
      rotationOffset: phase,
      rotationSpeed: 0.2'f32 + cfloat(i mod 17) * 0.035'f32,
      tint: [
        0.35'f32 + 0.65'f32 * abs(sin(hue * pi32)),
        0.35'f32 + 0.65'f32 * abs(sin((hue + 0.33'f32) * pi32)),
        0.35'f32 + 0.65'f32 * abs(sin((hue + 0.66'f32) * pi32)),
        0.45'f32 + 0.5'f32 * cfloat((i mod 9)) / 8'f32
      ],
      textureKind: i mod 9,
      regionIndex: i mod 4
    )

proc texturePointer(
  atlasTexture: GPUTextureHandle;
  texture1: GPUTextureHandle;
  texture2: GPUTextureHandle;
  texture3: GPUTextureHandle;
  texture4: GPUTextureHandle;
  texture5: GPUTextureHandle;
  texture6: GPUTextureHandle;
  texture7: GPUTextureHandle;
  kind: int
): SpriteTexture =
  case kind
  of 0: raw(atlasTexture)
  of 1: raw(texture1)
  of 2: raw(texture2)
  of 3: raw(texture3)
  of 4: raw(texture4)
  of 5: raw(texture5)
  of 6: raw(texture6)
  of 7: raw(texture7)
  else: nil

plugin Demo:
  proc load(
    artist: Artist2D;
    atlasTexture: var GPUTextureHandle;
    texture1: var GPUTextureHandle;
    texture2: var GPUTextureHandle;
    texture3: var GPUTextureHandle;
    texture4: var GPUTextureHandle;
    texture5: var GPUTextureHandle;
    texture6: var GPUTextureHandle;
    texture7: var GPUTextureHandle;
    motions: var seq[SpriteMotion]
  ) =
    atlasTexture = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 0))
    texture1 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 1))
    texture2 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 2))
    texture3 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 3))
    texture4 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 4))
    texture5 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 5))
    texture6 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 6))
    texture7 = createSpriteTexture(artist, textureSize, textureSize, makePatternPixels(textureSize, 7))
    motions = buildMotions(spriteCount)

  proc draw(
    artist: var Artist2D;
    atlasTexture: GPUTextureHandle;
    texture1: GPUTextureHandle;
    texture2: GPUTextureHandle;
    texture3: GPUTextureHandle;
    texture4: GPUTextureHandle;
    texture5: GPUTextureHandle;
    texture6: GPUTextureHandle;
    texture7: GPUTextureHandle;
    motions: seq[SpriteMotion];
    frameIndex: var uint64;
    swapchainWidth: uint32;
    swapchainHeight: uint32
  ) =
    let time = cfloat(frameIndex) * 0.016'f32
    inc frameIndex
    let widthf = max(1'u32, swapchainWidth).cfloat
    let heightf = max(1'u32, swapchainHeight).cfloat

    for motion in motions:
      var sprite = initSprite2D()
      let scalePulse = motion.baseScale + motion.scaleAmplitude * sin(time * motion.scaleSpeed + motion.rotationOffset)
      sprite.position = [
        wrap(motion.basePosition[0] + motion.velocity[0] * time, widthf + 240'f32) - 120'f32,
        wrap(motion.basePosition[1] + motion.velocity[1] * time, heightf + 240'f32) - 120'f32
      ]
      sprite.size = motion.size
      sprite.scale = [scalePulse, scalePulse]
      sprite.origin = [0.5'f32, 0.5'f32]
      sprite.rotation = motion.rotationOffset + time * motion.rotationSpeed
      sprite.tint = motion.tint
      sprite.texture = texturePointer(
        atlasTexture,
        texture1,
        texture2,
        texture3,
        texture4,
        texture5,
        texture6,
        texture7,
        motion.textureKind
      )
      if motion.textureKind == 0:
        sprite.region = atlasRegion(motion.regionIndex)
        sprite.hasRegion = true

      if not drawSprite(artist, sprite):
        break

when isMainModule:
  startApplication(
    AppConfig(
      appId: "dev.ellipse.tests.sdl3gpuartist2d",
      title: "Ellipse SDL3 GPU Artist2D",
      width: windowWidth,
      height: windowHeight,
      windowFlags: 0,
      resizable: true,
      shaderFormat: GPU_SHADERFORMAT_SPIRV,
      driverName: "vulkan",
      debugMode: true,
      maxSprites: spriteCount,
      maxTextureSlots: 8,
      clearColor: FColor(r: 0.08, g: 0.10, b: 0.13, a: 1.0)
    ),
    DemoState()
  )
