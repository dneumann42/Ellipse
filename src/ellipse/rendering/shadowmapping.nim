import std/[algorithm, math]

import vmath

type
  ShadowRenderConfig* = object
    cascadeCount*: int
    cascadeResolution*: int
    splitLambda*: float32
    maxSunDistance*: float32
    sunDepthBias*: float32
    sunNormalBias*: float32
    sunFilterRadiusTexels*: float32
    maxVisiblePointLights*: int
    maxShadowedPointLights*: int
    pointShadowResolution*: int
    pointDepthBias*: float32
    pointNormalBias*: float32
    pointSoftness*: float32

  ShadowCamera* = object
    position*: Vec3
    view*: Mat4
    projection*: Mat4
    nearPlane*: float32
    farPlane*: float32

  DirectionalShadowCascade* = object
    viewProjection*: Mat4
    splitNear*: float32
    splitFar*: float32
    texelSize*: float32

  ShadowPointLight* = object
    position*: Vec3
    color*: Vec3
    radius*: float32
    intensity*: float32
    falloff*: float32
    enabled*: bool
    castsShadows*: bool

  SelectedPointLight* = object
    sourceIndex*: int
    light*: ShadowPointLight
    distanceSq*: float32
    castsShadow*: bool

const
  CubeFaceDirections*: array[6, Vec3] = [
    vec3(1'f32, 0'f32, 0'f32),
    vec3(-1'f32, 0'f32, 0'f32),
    vec3(0'f32, 1'f32, 0'f32),
    vec3(0'f32, -1'f32, 0'f32),
    vec3(0'f32, 0'f32, 1'f32),
    vec3(0'f32, 0'f32, -1'f32)
  ]
  CubeFaceUps*: array[6, Vec3] = [
    vec3(0'f32, 1'f32, 0'f32),
    vec3(0'f32, 1'f32, 0'f32),
    vec3(0'f32, 0'f32, -1'f32),
    vec3(0'f32, 0'f32, 1'f32),
    vec3(0'f32, 1'f32, 0'f32),
    vec3(0'f32, 1'f32, 0'f32)
  ]

proc clamp01(value: float32): float32 =
  clamp(value, 0'f32, 1'f32)

proc shadowViewMatrix(eye, center, up: Vec3): Mat4 =
  let z = normalize(eye - center)
  let x = normalize(cross(up, z))
  let y = normalize(cross(z, x))
  mat4(
    x.x, y.x, z.x, 0'f32,
    x.y, y.y, z.y, 0'f32,
    x.z, y.z, z.z, 0'f32,
    -dot(x, eye), -dot(y, eye), -dot(z, eye), 1'f32
  )

proc interpolate(a, b: Vec3; t: float32): Vec3 =
  a + (b - a) * t

proc snapToShadowTexel*(value, texelSize: float32): float32 =
  if texelSize <= 0.000001'f32:
    return value
  floor(value / texelSize + 0.5'f32) * texelSize

proc buildCascadeSplits*(
  nearPlane, farPlane: float32;
  cascadeCount: int;
  lambda: float32
): seq[float32] =
  if cascadeCount <= 0 or farPlane <= nearPlane:
    return @[]

  let clampedLambda = clamp(lambda, 0'f32, 1'f32)
  for cascadeIndex in 1 .. cascadeCount:
    let fraction = cascadeIndex.float32 / cascadeCount.float32
    let logarithmic = nearPlane * pow(farPlane / nearPlane, fraction)
    let linear = nearPlane + (farPlane - nearPlane) * fraction
    result.add(linear * (1'f32 - clampedLambda) + logarithmic * clampedLambda)

proc worldFrustumCorners(camera: ShadowCamera): array[8, Vec3] =
  let inverseViewProjection = inverse(camera.projection * camera.view)
  let ndcCorners = [
    vec3(-1'f32, -1'f32, -1'f32),
    vec3(1'f32, -1'f32, -1'f32),
    vec3(1'f32, 1'f32, -1'f32),
    vec3(-1'f32, 1'f32, -1'f32),
    vec3(-1'f32, -1'f32, 1'f32),
    vec3(1'f32, -1'f32, 1'f32),
    vec3(1'f32, 1'f32, 1'f32),
    vec3(-1'f32, 1'f32, 1'f32)
  ]
  for i, corner in ndcCorners:
    let transformed = inverseViewProjection * vec4(corner, 1'f32)
    result[i] = vec3(
      transformed.x / transformed.w,
      transformed.y / transformed.w,
      transformed.z / transformed.w
    )

proc worldBoundsCorners(boundsMin, boundsMax: Vec3): array[8, Vec3] =
  [
    vec3(boundsMin.x, boundsMin.y, boundsMin.z),
    vec3(boundsMax.x, boundsMin.y, boundsMin.z),
    vec3(boundsMax.x, boundsMax.y, boundsMin.z),
    vec3(boundsMin.x, boundsMax.y, boundsMin.z),
    vec3(boundsMin.x, boundsMin.y, boundsMax.z),
    vec3(boundsMax.x, boundsMin.y, boundsMax.z),
    vec3(boundsMax.x, boundsMax.y, boundsMax.z),
    vec3(boundsMin.x, boundsMax.y, boundsMax.z)
  ]

proc buildDirectionalShadowCascades*(
  camera: ShadowCamera;
  sunDirection: Vec3;
  cascadeCount: int;
  maxDistance: float32;
  splitLambda: float32;
  resolution: int
): seq[DirectionalShadowCascade] =
  if cascadeCount <= 0 or resolution <= 0 or lengthSq(sunDirection) <= 0.000001'f32:
    return @[]

  let fullCorners = camera.worldFrustumCorners()
  let effectiveFar = min(camera.farPlane, max(maxDistance, camera.nearPlane + 0.001'f32))
  let splits = buildCascadeSplits(camera.nearPlane, effectiveFar, cascadeCount, splitLambda)
  let fullDepth = max(0.001'f32, camera.farPlane - camera.nearPlane)
  let lightDirection = normalize(sunDirection)
  let up =
    if abs(dot(lightDirection, vec3(0'f32, 1'f32, 0'f32))) > 0.95'f32:
      vec3(0'f32, 0'f32, 1'f32)
    else:
      vec3(0'f32, 1'f32, 0'f32)

  var previousSplit = camera.nearPlane
  for split in splits:
    let nearRatio = clamp01((previousSplit - camera.nearPlane) / fullDepth)
    let farRatio = clamp01((split - camera.nearPlane) / fullDepth)
    var corners: array[8, Vec3]
    for i in 0 .. 3:
      corners[i] = interpolate(fullCorners[i], fullCorners[i + 4], nearRatio)
      corners[i + 4] = interpolate(fullCorners[i], fullCorners[i + 4], farRatio)

    var center = vec3(0'f32, 0'f32, 0'f32)
    for corner in corners:
      center += corner
    center /= corners.len.float32

    var radius = 0'f32
    for corner in corners:
      radius = max(radius, length(corner - center))
    radius = max(radius, 1'f32)

    let lightPosition = center - lightDirection * (radius * 4'f32)
    let lightView = shadowViewMatrix(lightPosition, center, up)

    var minX = Inf.float32
    var maxX = -Inf.float32
    var minY = Inf.float32
    var maxY = -Inf.float32
    var minZ = Inf.float32
    var maxZ = -Inf.float32
    for corner in corners:
      let lightSpace = lightView * vec4(corner, 1'f32)
      minX = min(minX, lightSpace.x)
      maxX = max(maxX, lightSpace.x)
      minY = min(minY, lightSpace.y)
      maxY = max(maxY, lightSpace.y)
      minZ = min(minZ, lightSpace.z)
      maxZ = max(maxZ, lightSpace.z)

    let width = max(maxX - minX, 0.001'f32)
    let height = max(maxY - minY, 0.001'f32)
    let texelSize = max(width, height) / resolution.float32
    let snappedCenterX = snapToShadowTexel((minX + maxX) * 0.5'f32, texelSize)
    let snappedCenterY = snapToShadowTexel((minY + maxY) * 0.5'f32, texelSize)
    minX = snappedCenterX - width * 0.5'f32
    maxX = snappedCenterX + width * 0.5'f32
    minY = snappedCenterY - height * 0.5'f32
    maxY = snappedCenterY + height * 0.5'f32
    let depthPadding = max(8'f32, radius * 2'f32)
    minZ -= depthPadding
    maxZ += depthPadding

    result.add(DirectionalShadowCascade(
      viewProjection: ortho(minX, maxX, minY, maxY, -maxZ, -minZ) * lightView,
      splitNear: previousSplit,
      splitFar: split,
      texelSize: texelSize
    ))
    previousSplit = split

proc buildDirectionalShadowCascades*(
  camera: ShadowCamera;
  sunDirection: Vec3;
  worldBoundsMin, worldBoundsMax: Vec3;
  cascadeCount: int;
  maxDistance: float32;
  splitLambda: float32;
  resolution: int
): seq[DirectionalShadowCascade] =
  if cascadeCount <= 0 or resolution <= 0 or lengthSq(sunDirection) <= 0.000001'f32:
    return @[]

  if worldBoundsMax.x <= worldBoundsMin.x or
      worldBoundsMax.y <= worldBoundsMin.y or
      worldBoundsMax.z <= worldBoundsMin.z:
    return buildDirectionalShadowCascades(
      camera,
      sunDirection,
      cascadeCount,
      maxDistance,
      splitLambda,
      resolution
    )

  let effectiveFar = min(camera.farPlane, max(maxDistance, camera.nearPlane + 0.001'f32))
  let splits = buildCascadeSplits(camera.nearPlane, effectiveFar, cascadeCount, splitLambda)
  let lightDirection = normalize(sunDirection)
  let up =
    if abs(dot(lightDirection, vec3(0'f32, 1'f32, 0'f32))) > 0.95'f32:
      vec3(0'f32, 0'f32, 1'f32)
    else:
      vec3(0'f32, 1'f32, 0'f32)

  let corners = worldBoundsCorners(worldBoundsMin, worldBoundsMax)
  var center = (worldBoundsMin + worldBoundsMax) * 0.5'f32
  var radius = 0'f32
  for corner in corners:
    radius = max(radius, length(corner - center))
  radius = max(radius, 1'f32)

  let lightPosition = center - lightDirection * (radius * 4'f32)
  let lightView = shadowViewMatrix(lightPosition, center, up)

  var minX = Inf.float32
  var maxX = -Inf.float32
  var minY = Inf.float32
  var maxY = -Inf.float32
  var minZ = Inf.float32
  var maxZ = -Inf.float32
  for corner in corners:
    let lightSpace = lightView * vec4(corner, 1'f32)
    minX = min(minX, lightSpace.x)
    maxX = max(maxX, lightSpace.x)
    minY = min(minY, lightSpace.y)
    maxY = max(maxY, lightSpace.y)
    minZ = min(minZ, lightSpace.z)
    maxZ = max(maxZ, lightSpace.z)

  let width = max(maxX - minX, 0.001'f32)
  let height = max(maxY - minY, 0.001'f32)
  let texelSize = max(width, height) / resolution.float32
  let snappedCenterX = snapToShadowTexel((minX + maxX) * 0.5'f32, texelSize)
  let snappedCenterY = snapToShadowTexel((minY + maxY) * 0.5'f32, texelSize)
  minX = snappedCenterX - width * 0.5'f32
  maxX = snappedCenterX + width * 0.5'f32
  minY = snappedCenterY - height * 0.5'f32
  maxY = snappedCenterY + height * 0.5'f32
  let depthPadding = max(8'f32, radius * 2'f32)
  minZ -= depthPadding
  maxZ += depthPadding

  var previousSplit = camera.nearPlane
  for split in splits:
    result.add(DirectionalShadowCascade(
      viewProjection: ortho(minX, maxX, minY, maxY, -maxZ, -minZ) * lightView,
      splitNear: previousSplit,
      splitFar: split,
      texelSize: texelSize
    ))
    previousSplit = split

proc pointLightSelectionScore(light: ShadowPointLight; cameraPosition: Vec3): float32 =
  let distanceSq = lengthSq(light.position - cameraPosition)
  let distanceWeight = 1'f32 / max(0.25'f32, distanceSq)
  (light.intensity + light.radius * 0.1'f32) * distanceWeight

proc selectActivePointLights*(
  lights: openArray[ShadowPointLight];
  cameraPosition: Vec3;
  maxVisibleLights: int;
  maxShadowedLights: int
): seq[SelectedPointLight] =
  if maxVisibleLights <= 0:
    return @[]

  for index, light in lights:
    if not light.enabled or light.intensity <= 0'f32 or light.radius <= 0'f32:
      continue
    result.add(SelectedPointLight(
      sourceIndex: index,
      light: light,
      distanceSq: lengthSq(light.position - cameraPosition),
      castsShadow: false
    ))

  result.sort(proc(a, b: SelectedPointLight): int =
    let scoreA = a.light.pointLightSelectionScore(cameraPosition)
    let scoreB = b.light.pointLightSelectionScore(cameraPosition)
    result = cmp(scoreB, scoreA)
    if result == 0:
      result = cmp(a.distanceSq, b.distanceSq)
    if result == 0:
      result = cmp(a.sourceIndex, b.sourceIndex)
  )

  if result.len > maxVisibleLights:
    result.setLen(maxVisibleLights)

  var assignedShadowCasters = 0
  for item in result.mitems:
    if item.light.castsShadows and assignedShadowCasters < maxShadowedLights:
      item.castsShadow = true
      inc assignedShadowCasters

proc pointLightFaceViewProjection*(
  lightPosition: Vec3;
  radius: float32;
  faceIndex: int;
  nearPlane = 0.05'f32
): Mat4 =
  let clampedFace = clamp(faceIndex, 0, CubeFaceDirections.high)
  let target = lightPosition + CubeFaceDirections[clampedFace]
  let farPlane = max(radius, nearPlane + 0.001'f32)
  perspective(90'f32, 1'f32, nearPlane, farPlane) *
    shadowViewMatrix(lightPosition, target, CubeFaceUps[clampedFace])

proc buildPointLightFaceViewProjections*(
  lightPosition: Vec3;
  radius: float32;
  nearPlane = 0.05'f32
): seq[Mat4] =
  result = newSeq[Mat4](CubeFaceDirections.len)
  for faceIndex in 0 .. CubeFaceDirections.high:
    result[faceIndex] = pointLightFaceViewProjection(lightPosition, radius, faceIndex, nearPlane)

proc defaultShadowRenderConfig*(): ShadowRenderConfig =
  ShadowRenderConfig(
    cascadeCount: 3,
    cascadeResolution: 1024,
    splitLambda: 0.65'f32,
    maxSunDistance: 40'f32,
    sunDepthBias: 0.0012'f32,
    sunNormalBias: 0.04'f32,
    sunFilterRadiusTexels: 1.5'f32,
    maxVisiblePointLights: 8,
    maxShadowedPointLights: 2,
    pointShadowResolution: 512,
    pointDepthBias: 0.015'f32,
    pointNormalBias: 0.03'f32,
    pointSoftness: 0.03'f32
  )
