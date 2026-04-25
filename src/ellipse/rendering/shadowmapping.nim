import std/[algorithm, math]

import vmath

type
  DirectionalShadowMode* = enum
    dsmCameraCascaded
    dsmWorldStable

  ShadowRenderConfig* = object
    directionalShadowMode*: DirectionalShadowMode
    cascadeCount*: int
    cascadeResolution*: int
    splitLambda*: float32
    maxSunDistance*: float32
    sunRasterDepthBiasConstant*: float32
    sunRasterDepthBiasClamp*: float32
    sunRasterDepthBiasSlope*: float32
    sunDepthBias*: float32
    sunNormalBias*: float32
    sunFilterRadiusTexels*: float32
    maxVisiblePointLights*: int
    maxShadowedPointLights*: int
    pointShadowResolution*: int
    pointDepthBias*: float32
    pointNormalBias*: float32
    pointSoftness*: float32
    pointShadowCasterRadiusScale*: float32

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
    vec3(0'f32, -1'f32, 0'f32),
    vec3(0'f32, -1'f32, 0'f32),
    vec3(0'f32, 0'f32, 1'f32),
    vec3(0'f32, 0'f32, -1'f32),
    vec3(0'f32, -1'f32, 0'f32),
    vec3(0'f32, -1'f32, 0'f32)
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

proc orthoDepthZeroToOne(left, right, bottom, top, nearPlane, farPlane: float32): Mat4 =
  let
    rl = right - left
    tb = top - bottom
    fn = farPlane - nearPlane
  result[0, 0] = 2'f32 / rl
  result[1, 1] = 2'f32 / tb
  result[2, 2] = -1'f32 / fn
  result[3, 0] = -(left + right) / rl
  result[3, 1] = -(top + bottom) / tb
  result[3, 2] = -nearPlane / fn
  result[3, 3] = 1'f32

proc perspectiveDepthZeroToOne(fovy, aspect, nearPlane, farPlane: float32): Mat4 =
  let
    top = nearPlane * tan(fovy * PI.float32 / 360'f32)
    right = top * aspect
    fn = farPlane - nearPlane
  result[0, 0] = nearPlane / right
  result[1, 1] = nearPlane / top
  result[2, 2] = -farPlane / fn
  result[2, 3] = -1'f32
  result[3, 2] = -(farPlane * nearPlane) / fn

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

proc directionalShadowUp(sunDirection: Vec3): Vec3 =
  let lightDirection = normalize(sunDirection)
  if abs(dot(lightDirection, vec3(0'f32, 1'f32, 0'f32))) > 0.95'f32:
    vec3(0'f32, 0'f32, 1'f32)
  else:
    vec3(0'f32, 1'f32, 0'f32)

proc cornersCenter(corners: openArray[Vec3]): Vec3 =
  for corner in corners:
    result += corner
  result /= max(1, corners.len).float32

proc cornersRadius(corners: openArray[Vec3]; center: Vec3): float32 =
  for corner in corners:
    result = max(result, length(corner - center))
  result = max(result, 1'f32)

proc lightSpaceExtents(corners: openArray[Vec3]; lightView: Mat4): tuple[minX, maxX, minY, maxY, minZ, maxZ: float32] =
  result = (
    minX: Inf.float32,
    maxX: -Inf.float32,
    minY: Inf.float32,
    maxY: -Inf.float32,
    minZ: Inf.float32,
    maxZ: -Inf.float32
  )
  for corner in corners:
    let lightSpace = lightView * vec4(corner, 1'f32)
    result.minX = min(result.minX, lightSpace.x)
    result.maxX = max(result.maxX, lightSpace.x)
    result.minY = min(result.minY, lightSpace.y)
    result.maxY = max(result.maxY, lightSpace.y)
    result.minZ = min(result.minZ, lightSpace.z)
    result.maxZ = max(result.maxZ, lightSpace.z)

proc constrainExtents(
  extents: var tuple[minX, maxX, minY, maxY, minZ, maxZ: float32];
  crop: tuple[minX, maxX, minY, maxY, minZ, maxZ: float32]
) =
  extents.minX = max(extents.minX, crop.minX)
  extents.maxX = min(extents.maxX, crop.maxX)
  extents.minY = max(extents.minY, crop.minY)
  extents.maxY = min(extents.maxY, crop.maxY)
  extents.minZ = max(extents.minZ, crop.minZ)
  extents.maxZ = min(extents.maxZ, crop.maxZ)

  if extents.maxX <= extents.minX:
    let centerX = clamp((extents.minX + extents.maxX) * 0.5'f32, crop.minX, crop.maxX)
    extents.minX = centerX - 0.0005'f32
    extents.maxX = centerX + 0.0005'f32
  if extents.maxY <= extents.minY:
    let centerY = clamp((extents.minY + extents.maxY) * 0.5'f32, crop.minY, crop.maxY)
    extents.minY = centerY - 0.0005'f32
    extents.maxY = centerY + 0.0005'f32
  if extents.maxZ <= extents.minZ:
    extents.minZ = crop.minZ
    extents.maxZ = crop.maxZ

proc stabilizedDirectionalCascade(
  corners: openArray[Vec3];
  sunDirection: Vec3;
  resolution: int;
  splitNear, splitFar: float32;
  cropCorners: openArray[Vec3] = []
): DirectionalShadowCascade =
  let lightDirection = normalize(sunDirection)
  let up = sunDirection.directionalShadowUp()
  let center = corners.cornersCenter()
  let radius = corners.cornersRadius(center)
  let lightPosition = center - lightDirection * (radius * 4'f32)
  let lightView = shadowViewMatrix(lightPosition, center, up)

  var extents = corners.lightSpaceExtents(lightView)
  if cropCorners.len > 0:
    extents.constrainExtents(cropCorners.lightSpaceExtents(lightView))

  let width = max(extents.maxX - extents.minX, 0.001'f32)
  let height = max(extents.maxY - extents.minY, 0.001'f32)
  let texelSize = max(width, height) / resolution.float32
  let snappedCenterX = snapToShadowTexel((extents.minX + extents.maxX) * 0.5'f32, texelSize)
  let snappedCenterY = snapToShadowTexel((extents.minY + extents.maxY) * 0.5'f32, texelSize)
  let minX = snappedCenterX - width * 0.5'f32
  let maxX = snappedCenterX + width * 0.5'f32
  let minY = snappedCenterY - height * 0.5'f32
  let maxY = snappedCenterY + height * 0.5'f32
  let depthPadding = max(8'f32, radius * 2'f32)
  let minZ = extents.minZ - depthPadding
  let maxZ = extents.maxZ + depthPadding

  DirectionalShadowCascade(
    viewProjection: orthoDepthZeroToOne(minX, maxX, minY, maxY, -maxZ, -minZ) * lightView,
    splitNear: splitNear,
    splitFar: splitFar,
    texelSize: texelSize
  )

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

  var previousSplit = camera.nearPlane
  for split in splits:
    let nearRatio = clamp01((previousSplit - camera.nearPlane) / fullDepth)
    let farRatio = clamp01((split - camera.nearPlane) / fullDepth)
    var corners: array[8, Vec3]
    for i in 0 .. 3:
      corners[i] = interpolate(fullCorners[i], fullCorners[i + 4], nearRatio)
      corners[i + 4] = interpolate(fullCorners[i], fullCorners[i + 4], farRatio)

    result.add(stabilizedDirectionalCascade(corners, sunDirection, resolution, previousSplit, split))
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
  let fullCorners = camera.worldFrustumCorners()
  let fullDepth = max(0.001'f32, camera.farPlane - camera.nearPlane)
  let boundsCorners = worldBoundsCorners(worldBoundsMin, worldBoundsMax)

  var previousSplit = camera.nearPlane
  for split in splits:
    let nearRatio = clamp01((previousSplit - camera.nearPlane) / fullDepth)
    let farRatio = clamp01((split - camera.nearPlane) / fullDepth)
    var corners: array[8, Vec3]
    for i in 0 .. 3:
      corners[i] = interpolate(fullCorners[i], fullCorners[i + 4], nearRatio)
      corners[i + 4] = interpolate(fullCorners[i], fullCorners[i + 4], farRatio)

    result.add(stabilizedDirectionalCascade(
      corners,
      sunDirection,
      resolution,
      previousSplit,
      split,
      boundsCorners
    ))
    previousSplit = split

proc buildStableDirectionalShadowCascades*(
  sunDirection: Vec3;
  worldBoundsMin, worldBoundsMax: Vec3;
  maxDistance: float32;
  resolution: int
): seq[DirectionalShadowCascade] =
  if resolution <= 0 or lengthSq(sunDirection) <= 0.000001'f32:
    return @[]
  if worldBoundsMax.x <= worldBoundsMin.x or
      worldBoundsMax.y <= worldBoundsMin.y or
      worldBoundsMax.z <= worldBoundsMin.z:
    return @[]

  let boundsCorners = worldBoundsCorners(worldBoundsMin, worldBoundsMax)
  result.add(stabilizedDirectionalCascade(
    boundsCorners,
    sunDirection,
    resolution,
    0'f32,
    max(maxDistance, 0.001'f32)
  ))

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
  perspectiveDepthZeroToOne(110'f32, 1'f32, nearPlane, farPlane) *
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
    directionalShadowMode: dsmCameraCascaded,
    cascadeCount: 3,
    cascadeResolution: 1024,
    splitLambda: 0.65'f32,
    maxSunDistance: 40'f32,
    sunRasterDepthBiasConstant: 1.25'f32,
    sunRasterDepthBiasClamp: 0'f32,
    sunRasterDepthBiasSlope: 1.75'f32,
    sunDepthBias: 0.0012'f32,
    sunNormalBias: 0.04'f32,
    sunFilterRadiusTexels: 1.5'f32,
    maxVisiblePointLights: 8,
    maxShadowedPointLights: 2,
    pointShadowResolution: 512,
    pointDepthBias: 0.00005'f32,
    pointNormalBias: 0'f32,
    pointSoftness: 0.0005'f32,
    pointShadowCasterRadiusScale: 1.0'f32
  )
