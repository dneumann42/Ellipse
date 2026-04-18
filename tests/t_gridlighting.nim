import unittest

import vmath

import ellipse/rendering/gridlighting

type WallEdge = tuple[x, y: int; direction: GridDirection]

proc containsWall(walls: openArray[WallEdge]; x, y: int; direction: GridDirection): bool =
  for wall in walls:
    if wall.x == x and wall.y == y and wall.direction == direction:
      return true
  false

proc makeBlocker(walls: seq[WallEdge]): WallBlocker =
  result = proc(x, y: int; direction: GridDirection): bool {.closure, gcsafe.} =
    walls.containsWall(x, y, direction)

proc baseConfig(width, height: int): GridLightConfig =
  GridLightConfig(
    width: width,
    height: height,
    cellSize: 1'f32,
    samplesPerCell: 4,
    ambient: vec3(0'f32, 0'f32, 0'f32),
    maxBrightness: 1'f32
  )

proc ambientConfig(width, height: int): GridLightConfig =
  GridLightConfig(
    width: width,
    height: height,
    cellSize: 1'f32,
    samplesPerCell: 4,
    ambient: vec3(0.25'f32, 0.25'f32, 0.25'f32),
    maxBrightness: 1'f32,
    shadowBlackPoint: 0.24'f32
  )

suite "grid lighting":
  test "light reaches open neighboring cells":
    let field = buildGridLightField(
      baseConfig(2, 1),
      [initGridLight(0, 0, vec3(1'f32, 0'f32, 0'f32), radiusCells = 3'f32)],
      makeBlocker(@[])
    )

    check field.cellSampleRgb(0, 0, 2, 2).x > 0.5'f32
    check field.cellSampleRgb(1, 0, 1, 2).x > 0.1'f32

  test "solid wall blocks adjacent light bleed":
    let field = buildGridLightField(
      baseConfig(2, 1),
      [initGridLight(0, 0, vec3(1'f32, 0'f32, 0'f32), radiusCells = 3'f32)],
      makeBlocker(@[(x: 0, y: 0, direction: gdE)])
    )

    check field.cellSampleRgb(0, 0, 2, 2).x > 0.5'f32
    check field.cellSampleRgb(1, 0, 1, 2).x == 0'f32

  test "doorway gap allows light through the open grid edge":
    let field = buildGridLightField(
      baseConfig(3, 1),
      [initGridLight(0, 0, vec3(1'f32, 0'f32, 0'f32), radiusCells = 4'f32)],
      makeBlocker(@[(x: 1, y: 0, direction: gdE)])
    )

    check field.cellSampleRgb(1, 0, 1, 2).x > 0.1'f32
    check field.cellSampleRgb(2, 0, 1, 2).x == 0'f32

  test "blocked corner does not leak diagonal light":
    let field = buildGridLightField(
      baseConfig(2, 2),
      [initGridLight(0, 0, vec3(1'f32, 0'f32, 0'f32), radiusCells = 3'f32)],
      makeBlocker(@[
        (x: 0, y: 0, direction: gdE),
        (x: 0, y: 0, direction: gdS)
      ])
    )

    check field.cellSampleRgb(1, 1, 1, 1).x == 0'f32

  test "shadow edge samples receive fractional visibility":
    let config = baseConfig(3, 2)
    let light = initGridLight(
      0, 0,
      vec3(1'f32, 0'f32, 0'f32),
      radiusCells = 4'f32,
      intensity = 1'f32,
      falloff = 1'f32
    )
    let openField = buildGridLightField(config, [light], makeBlocker(@[]))
    let shadowField = buildGridLightField(
      config,
      [light],
      makeBlocker(@[(x: 1, y: 0, direction: gdE)])
    )

    let openSample = openField.cellSampleRgb(2, 1, 1, 0).x
    let shadowSample = shadowField.cellSampleRgb(2, 1, 1, 0).x

    check shadowSample > 0'f32
    check shadowSample < openSample

  test "multiple tinted lights accumulate and clamp":
    let field = buildGridLightField(
      baseConfig(1, 1),
      [
        initGridLight(0, 0, vec3(1'f32, 0'f32, 0'f32), radiusCells = 2'f32, intensity = 2'f32),
        initGridLight(0, 0, vec3(0'f32, 0'f32, 1'f32), radiusCells = 2'f32, intensity = 2'f32)
      ],
      makeBlocker(@[])
    )
    let rgb = field.cellSampleRgb(0, 0, 2, 2)

    check rgb.x == 1'f32
    check rgb.y == 0'f32
    check rgb.z == 1'f32

  test "disabled lights contribute nothing":
    let field = buildGridLightField(
      baseConfig(1, 1),
      [initGridLight(0, 0, vec3(1'f32, 1'f32, 1'f32), radiusCells = 2'f32, enabled = false)],
      makeBlocker(@[])
    )

    check field.cellSampleRgb(0, 0, 2, 2) == vec3(0'f32, 0'f32, 0'f32)

  test "shadow black point compresses ambient without dimming bright light":
    let field = buildGridLightField(
      ambientConfig(2, 1),
      [
        initGridLight(
          0, 0,
          vec3(1'f32, 1'f32, 1'f32),
          radiusCells = 2'f32,
          intensity = 2'f32
        )
      ],
      makeBlocker(@[(x: 0, y: 0, direction: gdE)])
    )

    check field.cellSampleRgb(1, 0, 2, 2).x < 0.03'f32
    check field.cellSampleRgb(0, 0, 2, 2) == vec3(1'f32, 1'f32, 1'f32)

  test "cell gutters duplicate edge samples":
    let field = buildGridLightField(
      baseConfig(1, 1),
      [initGridLight(0, 0, vec3(1'f32, 0'f32, 0'f32), radiusCells = 2'f32)],
      makeBlocker(@[])
    )

    check field.pixelRgb(0, 1) == field.pixelRgb(1, 1)
    check field.pixelRgb(field.info.blockStride - 1, 1) == field.pixelRgb(field.info.blockStride - 2, 1)
