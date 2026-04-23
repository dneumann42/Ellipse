import std/[math, unittest]

import vmath

import ellipse/rendering/shadowmapping

proc approxEqual(a, b: float32; epsilon = 0.0001'f32): bool =
  abs(a - b) <= epsilon

proc approxEqual(a, b: Mat4; epsilon = 0.0001'f32): bool =
  for row in 0 .. 3:
    for col in 0 .. 3:
      if not a[row][col].approxEqual(b[row][col], epsilon):
        return false
  true

proc cameraView(eye, center, up: Vec3): Mat4 =
  let z = normalize(eye - center)
  let x = normalize(cross(up, z))
  let y = normalize(cross(z, x))
  mat4(
    x.x, y.x, z.x, 0'f32,
    x.y, y.y, z.y, 0'f32,
    x.z, y.z, z.z, 0'f32,
    -dot(x, eye), -dot(y, eye), -dot(z, eye), 1'f32
  )

suite "shadow mapping":
  test "cascade splits stay ordered and end at the configured distance":
    let splits = buildCascadeSplits(0.03'f32, 40'f32, 3, 0.65'f32)

    check splits.len == 3
    check splits[0] > 0.03'f32
    check splits[0] < splits[1]
    check splits[1] < splits[2]
    check splits[2].approxEqual(40'f32)

  test "texel snapping keeps small offsets on the same snapped coordinate":
    let texelSize = 24'f32 / 1024'f32
    let snappedA = snapToShadowTexel(1.1250'f32, texelSize)
    let snappedB = snapToShadowTexel(1.1250'f32 + texelSize * 0.2'f32, texelSize)
    let snappedC = snapToShadowTexel(1.1250'f32 + texelSize * 1.2'f32, texelSize)

    check snappedA.approxEqual(snappedB)
    check not snappedA.approxEqual(snappedC)

  test "nearest enabled point lights are chosen and shadow budget is capped":
    let lights = @[
      ShadowPointLight(position: vec3(0'f32, 0'f32, 2'f32), radius: 8'f32, intensity: 2'f32, enabled: true, castsShadows: true),
      ShadowPointLight(position: vec3(0'f32, 0'f32, 4'f32), radius: 8'f32, intensity: 2'f32, enabled: true, castsShadows: true),
      ShadowPointLight(position: vec3(0'f32, 0'f32, 6'f32), radius: 8'f32, intensity: 2'f32, enabled: true, castsShadows: true),
      ShadowPointLight(position: vec3(0'f32, 0'f32, 1'f32), radius: 8'f32, intensity: 2'f32, enabled: false, castsShadows: true)
    ]
    let selected = selectActivePointLights(
      lights,
      vec3(0'f32, 0'f32, 0'f32),
      maxVisibleLights = 3,
      maxShadowedLights = 2
    )

    check selected.len == 3
    check selected[0].sourceIndex == 0
    check selected[1].sourceIndex == 1
    check selected[2].sourceIndex == 2
    check selected[0].castsShadow
    check selected[1].castsShadow
    check not selected[2].castsShadow

  test "point light face matrices cover six faces":
    let faces = buildPointLightFaceViewProjections(vec3(1'f32, 2'f32, 3'f32), 10'f32)

    check faces.len == 6
    for face in faces:
      for row in 0 .. 3:
        for col in 0 .. 3:
          check face[row][col] == face[row][col]

  test "world-bounds cascades stay stable when the camera moves":
    let projection = perspective(70'f32, 16'f32 / 9'f32, 0.03'f32, 100'f32)
    let cameraA = ShadowCamera(
      position: vec3(0'f32, 1.6'f32, -5'f32),
      view: cameraView(vec3(0'f32, 1.6'f32, -5'f32), vec3(0'f32, 1.2'f32, 0'f32), vec3(0'f32, 1'f32, 0'f32)),
      projection: projection,
      nearPlane: 0.03'f32,
      farPlane: 100'f32
    )
    let cameraB = ShadowCamera(
      position: vec3(3'f32, 1.6'f32, -2'f32),
      view: cameraView(vec3(3'f32, 1.6'f32, -2'f32), vec3(2'f32, 1.2'f32, 2'f32), vec3(0'f32, 1'f32, 0'f32)),
      projection: projection,
      nearPlane: 0.03'f32,
      farPlane: 100'f32
    )
    let boundsMin = vec3(-8'f32, -0.1'f32, -8'f32)
    let boundsMax = vec3(8'f32, 5'f32, 8'f32)
    let cascadesA = buildDirectionalShadowCascades(
      cameraA,
      normalize(vec3(0.4'f32, -1'f32, 0.2'f32)),
      boundsMin,
      boundsMax,
      3,
      40'f32,
      0.65'f32,
      1024
    )
    let cascadesB = buildDirectionalShadowCascades(
      cameraB,
      normalize(vec3(0.4'f32, -1'f32, 0.2'f32)),
      boundsMin,
      boundsMax,
      3,
      40'f32,
      0.65'f32,
      1024
    )

    check cascadesA.len == cascadesB.len
    for i in 0 ..< cascadesA.len:
      check cascadesA[i].viewProjection.approxEqual(cascadesB[i].viewProjection)
      check cascadesA[i].texelSize.approxEqual(cascadesB[i].texelSize)
