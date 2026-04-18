import std/[math]

import vmath

type
  GridDirection* = enum
    gdN, gdE, gdS, gdW

  WallBlocker* = proc(x, y: int; direction: GridDirection): bool {.closure, gcsafe.}

  GridLight* = object
    cellX*, cellY*: int
    height*: float32
    radiusCells*: float32
    color*: Vec3
    intensity*: float32
    falloff*: float32
    enabled*: bool

  GridLightConfig* = object
    width*, height*: int
    cellSize*: float32
    samplesPerCell*: int
    ambient*: Vec3
    maxBrightness*: float32
    shadowBlackPoint*: float32

  GridLightTextureInfo* = object
    originX*, originZ*: float32
    cellSize*: float32
    gridWidth*, gridHeight*: int
    samplesPerCell*: int
    blockStride*: int
    textureWidth*, textureHeight*: int

  GridLightField* = object
    info*: GridLightTextureInfo
    pixels*: seq[uint8]

const
  DefaultCellSize* = 1'f32
  VisibilitySubsampleOffsets = [-1'f32, 0'f32, 1'f32]

proc initGridLight*(
  cellX, cellY: int;
  color: Vec3;
  radiusCells = 4'f32;
  intensity = 1'f32;
  falloff = 1.6'f32;
  height = 0.75'f32;
  enabled = true
): GridLight =
  GridLight(
    cellX: cellX,
    cellY: cellY,
    height: height,
    radiusCells: radiusCells,
    color: color,
    intensity: intensity,
    falloff: falloff,
    enabled: enabled
  )

proc clamp01(value: float32): float32 =
  max(0'f32, min(1'f32, value))

proc positive(value, fallback: float32): float32 =
  if value > 0'f32: value else: fallback

proc positive(value, fallback: int): int =
  if value > 0: value else: fallback

proc applyBlackPoint(value, blackPoint: float32): float32 =
  let point = min(0.95'f32, max(0'f32, blackPoint))
  if point <= 0'f32:
    clamp01(value)
  else:
    clamp01((value - point) / (1'f32 - point))

proc inBounds(width, height, x, y: int): bool =
  x >= 0 and x < width and y >= 0 and y < height

proc opposite(direction: GridDirection): GridDirection =
  case direction
  of gdN: gdS
  of gdE: gdW
  of gdS: gdN
  of gdW: gdE

proc neighbor(x, y: int; direction: GridDirection): tuple[x, y: int] =
  case direction
  of gdN: (x, y - 1)
  of gdE: (x + 1, y)
  of gdS: (x, y + 1)
  of gdW: (x - 1, y)

proc blocked(
  blocker: WallBlocker;
  width, height, x, y: int;
  direction: GridDirection
): bool =
  let n = neighbor(x, y, direction)
  if not inBounds(width, height, x, y) or not inBounds(width, height, n.x, n.y):
    return true
  blocker(x, y, direction) or blocker(n.x, n.y, direction.opposite)

proc addReachableCells(
  reachable: var seq[bool];
  config: GridLightConfig;
  light: GridLight;
  blocker: WallBlocker
) =
  if not inBounds(config.width, config.height, light.cellX, light.cellY):
    return

  let maxSteps = int(ceil(light.radiusCells))
  var distances = newSeq[int](config.width * config.height)
  for i in 0 ..< distances.len:
    distances[i] = high(int)

  var queue: seq[tuple[x, y: int]]
  queue.add((light.cellX, light.cellY))
  distances[light.cellY * config.width + light.cellX] = 0
  reachable[light.cellY * config.width + light.cellX] = true

  var head = 0
  while head < queue.len:
    let current = queue[head]
    inc head
    let currentDistance = distances[current.y * config.width + current.x]
    if currentDistance >= maxSteps:
      continue

    for direction in [gdN, gdE, gdS, gdW]:
      if blocked(blocker, config.width, config.height, current.x, current.y, direction):
        continue
      let next = neighbor(current.x, current.y, direction)
      let nextIndex = next.y * config.width + next.x
      if distances[nextIndex] <= currentDistance + 1:
        continue
      distances[nextIndex] = currentDistance + 1
      reachable[nextIndex] = true
      queue.add(next)

proc hasLineOfSight(
  config: GridLightConfig;
  blocker: WallBlocker;
  ax, ay, bx, by: float32
): bool =
  var x = int(floor(ax))
  var y = int(floor(ay))
  let targetX = int(floor(bx))
  let targetY = int(floor(by))
  if not inBounds(config.width, config.height, x, y) or
      not inBounds(config.width, config.height, targetX, targetY):
    return false

  let dx = bx - ax
  let dy = by - ay
  if abs(dx) <= 0.000001'f32 and abs(dy) <= 0.000001'f32:
    return true

  let stepX = if dx > 0'f32: 1 elif dx < 0'f32: -1 else: 0
  let stepY = if dy > 0'f32: 1 elif dy < 0'f32: -1 else: 0
  var tMaxX =
    if stepX == 0:
      Inf.float32
    else:
      let nextBoundary = if stepX > 0: floor(ax) + 1'f32 else: floor(ax)
      abs((nextBoundary - ax) / dx)
  var tMaxY =
    if stepY == 0:
      Inf.float32
    else:
      let nextBoundary = if stepY > 0: floor(ay) + 1'f32 else: floor(ay)
      abs((nextBoundary - ay) / dy)
  let tDeltaX = if stepX == 0: Inf.float32 else: abs(1'f32 / dx)
  let tDeltaY = if stepY == 0: Inf.float32 else: abs(1'f32 / dy)

  var guard = 0
  while (x != targetX or y != targetY) and guard < config.width * config.height * 2:
    inc guard
    if abs(tMaxX - tMaxY) <= 0.00001'f32:
      let dirX = if stepX > 0: gdE else: gdW
      let dirY = if stepY > 0: gdS else: gdN
      if blocked(blocker, config.width, config.height, x, y, dirX) or
          blocked(blocker, config.width, config.height, x, y, dirY):
        return false
      x += stepX
      y += stepY
      tMaxX += tDeltaX
      tMaxY += tDeltaY
    elif tMaxX < tMaxY:
      let dirX = if stepX > 0: gdE else: gdW
      if blocked(blocker, config.width, config.height, x, y, dirX):
        return false
      x += stepX
      tMaxX += tDeltaX
    else:
      let dirY = if stepY > 0: gdS else: gdN
      if blocked(blocker, config.width, config.height, x, y, dirY):
        return false
      y += stepY
      tMaxY += tDeltaY

    if not inBounds(config.width, config.height, x, y):
      return false

  x == targetX and y == targetY

proc lineOfSightCoverage(
  config: GridLightConfig;
  blocker: WallBlocker;
  ax, ay, bx, by, sampleStep: float32
): float32 =
  var visible = 0
  var total = 0
  for oy in VisibilitySubsampleOffsets:
    for ox in VisibilitySubsampleOffsets:
      inc total
      if hasLineOfSight(config, blocker, ax, ay, bx + ox * sampleStep, by + oy * sampleStep):
        inc visible

  visible.float32 / total.float32

proc writeCellGutters(
  values: var seq[Vec3];
  textureWidth, blockStride, cellX, cellY, samplesPerCell: int
) =
  let blockX = cellX * blockStride
  let blockY = cellY * blockStride
  for i in 0 ..< samplesPerCell:
    values[(blockY * textureWidth) + blockX + 1 + i] =
      values[((blockY + 1) * textureWidth) + blockX + 1 + i]
    values[((blockY + blockStride - 1) * textureWidth) + blockX + 1 + i] =
      values[((blockY + samplesPerCell) * textureWidth) + blockX + 1 + i]
    values[((blockY + 1 + i) * textureWidth) + blockX] =
      values[((blockY + 1 + i) * textureWidth) + blockX + 1]
    values[((blockY + 1 + i) * textureWidth) + blockX + blockStride - 1] =
      values[((blockY + 1 + i) * textureWidth) + blockX + samplesPerCell]

  values[(blockY * textureWidth) + blockX] =
    values[((blockY + 1) * textureWidth) + blockX + 1]
  values[(blockY * textureWidth) + blockX + blockStride - 1] =
    values[((blockY + 1) * textureWidth) + blockX + samplesPerCell]
  values[((blockY + blockStride - 1) * textureWidth) + blockX] =
    values[((blockY + samplesPerCell) * textureWidth) + blockX + 1]
  values[((blockY + blockStride - 1) * textureWidth) + blockX + blockStride - 1] =
    values[((blockY + samplesPerCell) * textureWidth) + blockX + samplesPerCell]

proc buildGridLightField*(
  config: GridLightConfig;
  lights: openArray[GridLight];
  blocker: WallBlocker;
  originX = 0'f32;
  originZ = 0'f32
): GridLightField =
  let width = positive(config.width, 1)
  let height = positive(config.height, 1)
  let samples = max(1, positive(config.samplesPerCell, 4))
  let blockStride = samples + 2
  let textureWidth = width * blockStride
  let textureHeight = height * blockStride
  let normalizedConfig = GridLightConfig(
    width: width,
    height: height,
    cellSize: positive(config.cellSize, DefaultCellSize),
    samplesPerCell: samples,
    ambient: config.ambient,
    maxBrightness: positive(config.maxBrightness, 1'f32),
    shadowBlackPoint: config.shadowBlackPoint
  )

  result.info = GridLightTextureInfo(
    originX: originX,
    originZ: originZ,
    cellSize: normalizedConfig.cellSize,
    gridWidth: width,
    gridHeight: height,
    samplesPerCell: samples,
    blockStride: blockStride,
    textureWidth: textureWidth,
    textureHeight: textureHeight
  )

  var values = newSeq[Vec3](textureWidth * textureHeight)
  for i in 0 ..< values.len:
    values[i] = normalizedConfig.ambient

  for light in lights:
    if not light.enabled or light.radiusCells <= 0'f32 or light.intensity <= 0'f32:
      continue

    var reachable = newSeq[bool](width * height)
    addReachableCells(reachable, normalizedConfig, light, blocker)
    let lightX = light.cellX.float32 + 0.5'f32
    let lightY = light.cellY.float32 + 0.5'f32
    let radius = positive(light.radiusCells, 0.001'f32)
    let falloff = positive(light.falloff, 1'f32)
    let visibilitySampleStep = 0.25'f32 / samples.float32

    for cellY in 0 ..< height:
      for cellX in 0 ..< width:
        if not reachable[cellY * width + cellX]:
          continue
        for sy in 0 ..< samples:
          for sx in 0 ..< samples:
            let sampleX = cellX.float32 + (sx.float32 + 0.5'f32) / samples.float32
            let sampleY = cellY.float32 + (sy.float32 + 0.5'f32) / samples.float32
            let dx = sampleX - lightX
            let dy = sampleY - lightY
            let distance = sqrt(dx * dx + dy * dy)
            if distance > radius:
              continue
            let visibility = lineOfSightCoverage(
              normalizedConfig,
              blocker,
              lightX,
              lightY,
              sampleX,
              sampleY,
              visibilitySampleStep
            )
            if visibility <= 0'f32:
              continue

            let amount = pow(max(0'f32, 1'f32 - distance / radius), falloff) *
              light.intensity * visibility
            let px = cellX * blockStride + 1 + sx
            let py = cellY * blockStride + 1 + sy
            values[py * textureWidth + px] = values[py * textureWidth + px] + light.color * amount

  for cellY in 0 ..< height:
    for cellX in 0 ..< width:
      writeCellGutters(values, textureWidth, blockStride, cellX, cellY, samples)

  result.pixels = newSeq[uint8](textureWidth * textureHeight * 4)
  for i, value in values:
    let base = i * 4
    result.pixels[base] = uint8(round(
      applyBlackPoint(value.x / normalizedConfig.maxBrightness, normalizedConfig.shadowBlackPoint) * 255'f32
    ))
    result.pixels[base + 1] = uint8(round(
      applyBlackPoint(value.y / normalizedConfig.maxBrightness, normalizedConfig.shadowBlackPoint) * 255'f32
    ))
    result.pixels[base + 2] = uint8(round(
      applyBlackPoint(value.z / normalizedConfig.maxBrightness, normalizedConfig.shadowBlackPoint) * 255'f32
    ))
    result.pixels[base + 3] = 255'u8

proc pixelRgb*(field: GridLightField; x, y: int): Vec3 =
  let index = (y * field.info.textureWidth + x) * 4
  vec3(
    field.pixels[index].float32 / 255'f32,
    field.pixels[index + 1].float32 / 255'f32,
    field.pixels[index + 2].float32 / 255'f32
  )

proc cellSampleRgb*(field: GridLightField; cellX, cellY, sampleX, sampleY: int): Vec3 =
  let px = cellX * field.info.blockStride + 1 + sampleX
  let py = cellY * field.info.blockStride + 1 + sampleY
  field.pixelRgb(px, py)
