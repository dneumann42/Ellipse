import vmath
import ellipse/rendering/artist3D
import ellipse/resources
import std/[math, sets, streams, strutils, tables]

const MeshMergeDistance* = 0.001'f32
const DefaultSkyboxPath* = "res/textures/skyboxes/DefaultDay.aseprite"
const
  DefaultSkyHorizonColor* = vec3(1.0'f32, 0.44'f32, 0.62'f32)
  DefaultSkyZenithColor* = vec3(0.42'f32, 0.56'f32, 0.66'f32)
  DefaultSkyGroundColor* = vec3(0.45'f32, 0.5'f32, 0.48'f32)
const
  TerrainRegionSubdivisions* = 16
  TerrainRegionSize* = 8'f32

type
  WorldID* = string

  MaterialID* = string

  WorldMeshKind* = enum
    OtherWorldMesh, TerrainWorldMesh

  WorldMaterial* = object
    id*: MaterialID
    name*: string
    texturePath*: string
    baseColor*: Vec3
    useTexture*: bool
    specularStrength*: float32

  WorldRenderMesh* = object
    materialID*: MaterialID
    vertices*: seq[Vertex]
    indices*: seq[uint32]

  WorldWaterPlane* = object
    name*: string
    position*: Vec3
    size*: Vec2
    waveAmplitude*: float32
    waveLength*: float32
    waveSpeed*: float32
    surfaceColor*: Vec3
    deepColor*: Vec3
    opacity*: float32
    specularStrength*: float32

  WorldFog* = object
    nearColor*: Vec3
    farColor*: Vec3
    density*: float32
    falloff*: float32
    limit*: float32

  WorldEnvironment* = object
    name*: string
    boxCenter*: Vec3
    boxSize*: Vec3
    fog*: WorldFog
    skyHorizonColor*: Vec3
    skyZenithColor*: Vec3
    skyGroundColor*: Vec3
    skyboxPath*: string
    useSkybox*: bool
    skyboxExposure*: float32

  WorldTerrainRegion* = object
    meshIndex*: int
    cellX*, cellZ*: int

  WorldTerrainCell = tuple[x, z: int]
  WorldTerrainVertexRef* = tuple[meshIndex, vertexIndex: int, position: Vec3]
  TerrainNormalKey = tuple[x, y, z: int]

  WorldMesh* = object
    name*: string
    kind*: WorldMeshKind
    ## Local geometry stays centered on the model origin.  Position is only
    ## used when this mesh is rendered by its owning world.
    position*: Vec3
    materials*: seq[WorldMaterial]
    vertices*: seq[Vertex]
    indices*: seq[uint32]
    triangleMaterials*: seq[int]
    triangleUvs*: seq[array[3, Vec2]]

  WorldModelInstance* = object
    name*: string
    sourceWorld*: WorldID
    sourceMesh*: string
    position*: Vec3
    rotation*: Vec3 # Euler angles in degrees (x, y, z)
    scale*: Vec3

  WorldEntitySpawn* = object
    entityID*: string
    position*: Vec3

  World* = object
    id: WorldID
    meshes: seq[WorldMesh]
    models: seq[WorldModelInstance]
    entitySpawns: seq[WorldEntitySpawn]
    terrainRegions: seq[WorldTerrainRegion]
    terrainRegionLookup: Table[WorldTerrainCell, int]
    waterPlanes: seq[WorldWaterPlane]
    globalEnvironment: WorldEnvironment
    localEnvironments: seq[WorldEnvironment]
    selectedMesh: int
    selectedModel: int
    selectedEntitySpawn: int
    revision: uint64

  WorldError* = object of CatchableError

proc init*(T: typedesc[World], id: WorldID): T =
  T(
    id: id,
    meshes: @[],
    models: @[],
    entitySpawns: @[],
    terrainRegions: @[],
    terrainRegionLookup: initTable[WorldTerrainCell, int](),
    waterPlanes: @[],
    globalEnvironment: WorldEnvironment(
      name: "Environment 1",
      boxCenter: vec3(0, 0, 0),
      boxSize: vec3(64, 32, 64),
      fog: WorldFog(
        nearColor: vec3(0.72'f32, 0.8'f32, 0.86'f32),
        farColor: vec3(0.42'f32, 0.56'f32, 0.66'f32),
        density: 0.025'f32,
        falloff: 1.2'f32,
        limit: 120'f32,
    ),
      skyHorizonColor: DefaultSkyHorizonColor,
      skyZenithColor: DefaultSkyZenithColor,
      skyGroundColor: DefaultSkyGroundColor,
      skyboxPath: DefaultSkyboxPath,
      useSkybox: true,
      skyboxExposure: 1'f32,
  ),
    localEnvironments: @[],
    selectedMesh: -1,
    selectedModel: -1,
    selectedEntitySpawn: -1,
  )

proc init*(T: typedesc[WorldWaterPlane], name: string): T =
  T(
    name: name,
    position: vec3(0, 0, 0),
    size: vec2(128, 128),
    waveAmplitude: 0.12'f32,
    waveLength: 9'f32,
    waveSpeed: 0.8'f32,
    surfaceColor: vec3(0.2'f32, 0.75'f32, 0.92'f32),
    deepColor: vec3(0.01'f32, 0.16'f32, 0.28'f32),
    opacity: 0.82'f32,
    specularStrength: 0.55'f32,
  )

proc init*(T: typedesc[WorldFog]): T =
  T(
    nearColor: vec3(0.72'f32, 0.8'f32, 0.86'f32),
    farColor: vec3(0.42'f32, 0.56'f32, 0.66'f32),
    density: 0.025'f32,
    falloff: 1.2'f32,
    limit: 120'f32,
  )

proc init*(T: typedesc[WorldEnvironment], name: string): T =
  T(
    name: name,
    boxCenter: vec3(0, 0, 0),
    boxSize: vec3(64, 32, 64),
    fog: WorldFog.init(),
    skyHorizonColor: DefaultSkyHorizonColor,
    skyZenithColor: DefaultSkyZenithColor,
    skyGroundColor: DefaultSkyGroundColor,
    skyboxPath: "",
    useSkybox: false,
    skyboxExposure: 1'f32,
  )

proc name*(world: World): string =
  result = world.id

proc `name=`*(world: var World, newName: string) =
  world.id = newName

proc meshCount*(world: World): int =
  world.meshes.len

proc revision*(world: World): uint64 =
  world.revision

proc markChanged(world: var World) =
  inc world.revision

proc defaultMaterial*(): WorldMaterial =
  WorldMaterial(
    id: "default",
    name: "Default",
    texturePath: "",
    baseColor: vec3(1'f32, 1'f32, 1'f32),
    useTexture: false,
    specularStrength: DefaultSpecularStrength,
  )

proc ensureDefaultMaterial(mesh: var WorldMesh) =
  if mesh.materials.len == 0:
    mesh.materials.add defaultMaterial()

proc hasSplat(vertex: Vertex): bool =
  vertex.splatWeights.x + vertex.splatWeights.y + vertex.splatWeights.z +
      vertex.splatWeights.w > 0.0001'f32

proc normalizeSplat(vertex: var Vertex) =
  let total = vertex.splatWeights.x + vertex.splatWeights.y +
      vertex.splatWeights.z + vertex.splatWeights.w
  if total > 0.0001'f32:
    vertex.splatWeights = vertex.splatWeights / total
  else:
    vertex.splatIndices = vec4(0, 0, 0, 0)
    vertex.splatWeights = vec4(1, 0, 0, 0)

proc splatSlot(vertex: Vertex, tileIndex: int): int =
  let tile = tileIndex.float32
  if vertex.splatWeights.x > 0 and abs(vertex.splatIndices.x - tile) < 0.5:
    return 0
  if vertex.splatWeights.y > 0 and abs(vertex.splatIndices.y - tile) < 0.5:
    return 1
  if vertex.splatWeights.z > 0 and abs(vertex.splatIndices.z - tile) < 0.5:
    return 2
  if vertex.splatWeights.w > 0 and abs(vertex.splatIndices.w - tile) < 0.5:
    return 3
  -1

proc weakestSplatSlot(vertex: Vertex): int =
  result = 0
  var weight = vertex.splatWeights.x
  for i, candidate in [vertex.splatWeights.y, vertex.splatWeights.z,
      vertex.splatWeights.w]:
    if candidate < weight:
      result = i + 1
      weight = candidate

proc setSplat(vertex: var Vertex, slot, tileIndex: int, weight: float32) =
  case slot
  of 0:
    vertex.splatIndices.x = tileIndex.float32
    vertex.splatWeights.x = weight
  of 1:
    vertex.splatIndices.y = tileIndex.float32
    vertex.splatWeights.y = weight
  of 2:
    vertex.splatIndices.z = tileIndex.float32
    vertex.splatWeights.z = weight
  else:
    vertex.splatIndices.w = tileIndex.float32
    vertex.splatWeights.w = weight

proc splatIndex(vertex: Vertex, slot: int): int =
  case slot
  of 0:
    vertex.splatIndices.x.int
  of 1:
    vertex.splatIndices.y.int
  of 2:
    vertex.splatIndices.z.int
  else:
    vertex.splatIndices.w.int

proc splatWeight(vertex: Vertex, slot: int): float32 =
  case slot
  of 0:
    vertex.splatWeights.x
  of 1:
    vertex.splatWeights.y
  of 2:
    vertex.splatWeights.z
  else:
    vertex.splatWeights.w

proc blendSplat(vertex: var Vertex, tileIndex: int, amount: float32) =
  if not vertex.hasSplat():
    vertex.splatIndices = vec4(0, 0, 0, 0)
    vertex.splatWeights = vec4(1, 0, 0, 0)
  var slot = vertex.splatSlot(tileIndex)
  if slot < 0:
    slot = vertex.weakestSplatSlot()
    vertex.setSplat(slot, tileIndex, 0)
  vertex.splatWeights = vertex.splatWeights * max(1'f32 - amount, 0'f32)
  case slot
  of 0:
    vertex.splatWeights.x += amount
  of 1:
    vertex.splatWeights.y += amount
  of 2:
    vertex.splatWeights.z += amount
  else:
    vertex.splatWeights.w += amount
  vertex.normalizeSplat()

proc terrainSplatPalette(vertices: openArray[Vertex]): array[4, int] =
  var
    tiles: seq[int]
    weights: seq[float32]
  for vertex in vertices:
    for slot in 0 .. 3:
      let weight = vertex.splatWeight(slot)
      if weight <= 0.0001'f32:
        continue
      let tile = vertex.splatIndex(slot)
      var found = -1
      for i, existing in tiles:
        if existing == tile:
          found = i
          break
      if found >= 0:
        weights[found] += weight
      else:
        tiles.add tile
        weights.add weight
  for slot in 0 .. 3:
    var best = -1
    for i, weight in weights:
      if weight > 0 and (best < 0 or weight > weights[best]):
        best = i
    if best >= 0:
      result[slot] = tiles[best]
      weights[best] = -1
    elif slot > 0:
      result[slot] = result[slot - 1]

proc remapTerrainSplat(vertex: var Vertex, palette: array[4, int]) =
  var weights = vec4(0, 0, 0, 0)
  for slot in 0 .. 3:
    let
      tile = vertex.splatIndex(slot)
      weight = vertex.splatWeight(slot)
    if weight <= 0.0001'f32:
      continue
    for paletteSlot, paletteTile in palette:
      if tile == paletteTile:
        case paletteSlot
        of 0:
          weights.x += weight
        of 1:
          weights.y += weight
        of 2:
          weights.z += weight
        else:
          weights.w += weight
        break
  vertex.splatIndices = vec4(
    palette[0].float32,
    palette[1].float32,
    palette[2].float32,
    palette[3].float32,
  )
  vertex.splatWeights = weights
  vertex.normalizeSplat()

proc ensureTriangleMaterials(mesh: var WorldMesh) =
  mesh.ensureDefaultMaterial()
  let triangleCount = mesh.indices.len div 3
  while mesh.triangleMaterials.len < triangleCount:
    mesh.triangleMaterials.add 0
  if mesh.triangleMaterials.len > triangleCount:
    mesh.triangleMaterials.setLen(triangleCount)
  while mesh.triangleUvs.len < triangleCount:
    let base = mesh.triangleUvs.len * 3
    if base + 2 < mesh.indices.len:
      mesh.triangleUvs.add [
        mesh.vertices[mesh.indices[base].int].uv,
        mesh.vertices[mesh.indices[base + 1].int].uv,
        mesh.vertices[mesh.indices[base + 2].int].uv,
      ]
    else:
      mesh.triangleUvs.add [vec2(0, 0), vec2(1, 0), vec2(0, 1)]
  if mesh.triangleUvs.len > triangleCount:
    mesh.triangleUvs.setLen(triangleCount)

proc initWorldMesh(name: string, kind: WorldMeshKind): WorldMesh =
  result = WorldMesh(name: name, kind: kind, position: vec3(0, 0, 0),
      vertices: @[], indices: @[])
  result.ensureDefaultMaterial()

proc recalculateNormals*(mesh: var WorldMesh)

proc selectedMesh*(world: World): int =
  world.selectedMesh

proc `selectedMesh=`*(world: var World, index: int) =
  if index >= 0 and index < world.meshes.len:
    if world.selectedMesh != index:
      world.selectedMesh = index
      world.markChanged()
  elif world.meshes.len == 0:
    if world.selectedMesh != -1:
      world.selectedMesh = -1
      world.markChanged()

proc meshes*(world: World): lent seq[WorldMesh] =
  world.meshes

proc models*(world: World): lent seq[WorldModelInstance] =
  world.models

proc modelCount*(world: World): int = world.models.len

proc model*(world: World, index: int): WorldModelInstance = world.models[index]

proc selectedModel*(world: World): int = world.selectedModel

proc `selectedModel=`*(world: var World, index: int) =
  if index >= 0 and index < world.models.len:
    world.selectedModel = index
    world.markChanged()
  elif world.models.len == 0:
    world.selectedModel = -1

proc setModel*(world: var World, index: int, value: WorldModelInstance) =
  if index < 0 or index >= world.models.len: return
  world.models[index] = value
  world.markChanged()

proc addModel*(world: var World, sourceWorld: WorldID, sourceMesh: string,
    name = "", position = vec3(0, 0, 0)): int =
  result = world.models.len
  world.models.add WorldModelInstance(
    name: (if name.len > 0: name else: sourceMesh),
    sourceWorld: sourceWorld,
    sourceMesh: sourceMesh,
    position: position,
    rotation: vec3(0, 0, 0),
    scale: vec3(1, 1, 1),
  )
  world.selectedModel = result
  world.markChanged()

proc duplicateModel*(world: var World, index: int): int =
  if index < 0 or index >= world.models.len:
    return -1
  result = world.models.len
  var model = world.models[index]
  model.name = model.name & " Copy"
  world.models.add model
  world.selectedModel = result
  world.markChanged()

proc deleteModel*(world: var World, index: int) =
  if index < 0 or index >= world.models.len: return
  world.models.delete(index)
  world.selectedModel = if world.models.len == 0: -1 else: min(index,
      world.models.high)
  world.markChanged()

proc modelTransform*(model: WorldModelInstance): Mat4 =
  translate(model.position) *
    rotateZ(model.rotation.z * PI.float32 / 180'f32) *
    rotateY(model.rotation.y * PI.float32 / 180'f32) *
    rotateX(model.rotation.x * PI.float32 / 180'f32) *
    scale(model.scale)

proc entitySpawns*(world: World): lent seq[WorldEntitySpawn] = world.entitySpawns
proc entitySpawnCount*(world: World): int = world.entitySpawns.len
proc entitySpawn*(world: World, index: int): WorldEntitySpawn = world.entitySpawns[index]
proc selectedEntitySpawn*(world: World): int = world.selectedEntitySpawn

proc `selectedEntitySpawn=`*(world: var World, index: int) =
  if index >= 0 and index < world.entitySpawns.len:
    world.selectedEntitySpawn = index
    world.markChanged()
  elif world.entitySpawns.len == 0:
    world.selectedEntitySpawn = -1

proc addEntitySpawn*(world: var World, entityID: string,
    position = vec3(0, 0, 0)): int =
  result = world.entitySpawns.len
  world.entitySpawns.add WorldEntitySpawn(entityID: entityID, position: position)
  world.selectedEntitySpawn = result
  world.markChanged()

proc setEntitySpawn*(world: var World, index: int, spawn: WorldEntitySpawn) =
  if index < 0 or index >= world.entitySpawns.len: return
  world.entitySpawns[index] = spawn
  world.markChanged()

proc deleteEntitySpawn*(world: var World, index: int) =
  if index < 0 or index >= world.entitySpawns.len: return
  world.entitySpawns.delete(index)
  world.selectedEntitySpawn = if world.entitySpawns.len == 0: -1 else:
    min(index, world.entitySpawns.high)
  world.markChanged()

proc waterPlanes*(world: World): lent seq[WorldWaterPlane] =
  world.waterPlanes

proc globalEnvironment*(world: World): WorldEnvironment =
  world.globalEnvironment

proc localEnvironments*(world: World): lent seq[WorldEnvironment] =
  world.localEnvironments

proc terrainRegions*(world: World): lent seq[WorldTerrainRegion] =
  world.terrainRegions

proc terrainRegionCount*(world: World): int =
  world.terrainRegions.len

proc terrainRegion*(world: World, index: int): WorldTerrainRegion =
  world.terrainRegions[index]

proc terrainCell(cellX, cellZ: int): WorldTerrainCell =
  (x: cellX, z: cellZ)

proc rebuildTerrainRegionLookup(world: var World) =
  world.terrainRegionLookup = initTable[WorldTerrainCell, int]()
  for region in world.terrainRegions:
    if region.meshIndex >= 0 and region.meshIndex < world.meshes.len and
        world.meshes[region.meshIndex].kind == TerrainWorldMesh:
      world.terrainRegionLookup[terrainCell(region.cellX, region.cellZ)] =
        region.meshIndex

proc waterPlane*(world: World, index: int): WorldWaterPlane =
  world.waterPlanes[index]

proc waterPlaneCount*(world: World): int =
  world.waterPlanes.len

proc localEnvironment*(world: World, index: int): WorldEnvironment =
  world.localEnvironments[index]

proc localEnvironmentCount*(world: World): int =
  world.localEnvironments.len

proc mesh*(world: World, index: int): lent WorldMesh =
  world.meshes[index]

proc meshKind*(world: World, index: int): WorldMeshKind =
  world.meshes[index].kind

proc meshPosition*(world: World, index: int): Vec3 =
  if index < 0 or index >= world.meshes.len:
    return vec3(0, 0, 0)
  world.meshes[index].position

proc setMeshPosition*(world: var World, index: int, position: Vec3) =
  if index < 0 or index >= world.meshes.len or
      world.meshes[index].kind == TerrainWorldMesh:
    return
  if world.meshes[index].position != position:
    world.meshes[index].position = position
    world.markChanged()

proc pointInTerrainTriangle(
    x, z: float32, a, b, c: Vec3
): tuple[hit: bool, height: float32] =
  let
    v0x = b.x - a.x
    v0z = b.z - a.z
    v1x = c.x - a.x
    v1z = c.z - a.z
    v2x = x - a.x
    v2z = z - a.z
    denom = v0x * v1z - v1x * v0z
  if abs(denom) <= 0.000001'f32:
    return (false, 0)
  let
    u = (v2x * v1z - v1x * v2z) / denom
    v = (v0x * v2z - v2x * v0z) / denom
    w = 1'f32 - u - v
  if u < -0.0001'f32 or v < -0.0001'f32 or w < -0.0001'f32:
    return (false, 0)
  (true, a.y * w + b.y * u + c.y * v)

proc terrainHeightAt*(world: World, x, z: float32): tuple[
    hit: bool,
    height: float32
  ] =
  for mesh in world.meshes:
    if mesh.kind != TerrainWorldMesh:
      continue
    var i = 0
    while i + 2 < mesh.indices.len:
      let
        ia = mesh.indices[i].int
        ib = mesh.indices[i + 1].int
        ic = mesh.indices[i + 2].int
      i += 3
      if ia < 0 or ib < 0 or ic < 0 or ia >= mesh.vertices.len or
          ib >= mesh.vertices.len or ic >= mesh.vertices.len:
        continue
      let height = pointInTerrainTriangle(
        x, z, mesh.vertices[ia].position, mesh.vertices[ib].position,
        mesh.vertices[ic].position,
      )
      if height.hit and (not result.hit or height.height > result.height):
        result = height

proc renameMesh*(world: var World, index: int, name: string) =
  if index < 0 or index >= world.meshes.len:
    return
  let newName = name.strip()
  if newName.len == 0 or world.meshes[index].name == newName:
    return
  world.meshes[index].name = newName
  world.markChanged()

proc duplicateMesh*(world: var World, index: int): int =
  if index < 0 or index >= world.meshes.len or
      world.meshes[index].kind == TerrainWorldMesh:
    return -1
  let source = world.meshes[index]
  var mesh = initWorldMesh(source.name & " Copy", source.kind)
  mesh.materials.setLen(0)
  mesh.materials.add source.materials
  mesh.position = source.position
  mesh.vertices.add source.vertices
  mesh.indices.add source.indices
  mesh.triangleMaterials.add source.triangleMaterials
  mesh.triangleUvs.add source.triangleUvs
  result = world.meshes.len
  world.meshes.add mesh
  world.selectedMesh = result
  world.markChanged()

proc translateMesh*(world: var World, index: int, offset: Vec3) =
  if index < 0 or index >= world.meshes.len:
    return
  if length(offset) <= 0.000001'f32:
    return
  if world.meshes[index].kind == TerrainWorldMesh:
    for vertex in world.meshes[index].vertices.mitems:
      vertex.position += offset
  else:
    world.meshes[index].position += offset
  world.markChanged()

proc deleteMesh*(world: var World, index: int) =
  if index < 0 or index >= world.meshes.len:
    return
  world.meshes.delete index
  var i = 0
  while i < world.terrainRegions.len:
    if world.terrainRegions[i].meshIndex == index:
      world.terrainRegions.delete i
    else:
      if world.terrainRegions[i].meshIndex > index:
        dec world.terrainRegions[i].meshIndex
      inc i
  world.rebuildTerrainRegionLookup()
  if world.meshes.len == 0:
    world.selectedMesh = -1
  elif world.selectedMesh == index:
    world.selectedMesh = min(index, world.meshes.len - 1)
  elif world.selectedMesh > index:
    dec world.selectedMesh
  world.markChanged()

proc terrainRegionForMesh*(world: World, meshIndex: int): int =
  for i, region in world.terrainRegions:
    if region.meshIndex == meshIndex:
      return i
  -1

proc terrainMeshAtCell*(world: World, cellX, cellZ: int): int =
  world.terrainRegionLookup.getOrDefault(terrainCell(cellX, cellZ), -1)

proc terrainGridSteps(): int =
  max(TerrainRegionSubdivisions, 1)

proc terrainGridStride(): int =
  terrainGridSteps() + 1

proc terrainVertexIndex(x, z: int): int =
  z * terrainGridStride() + x

proc terrainVertexCoord(vertexIndex: int): tuple[x, z: int] =
  let stride = terrainGridStride()
  (x: vertexIndex mod stride, z: vertexIndex div stride)

iterator terrainVertices*(world: World): WorldTerrainVertexRef =
  for meshIndex, mesh in world.meshes:
    if mesh.kind != TerrainWorldMesh:
      continue
    for vertexIndex, vertex in mesh.vertices:
      yield (meshIndex: meshIndex, vertexIndex: vertexIndex,
          position: vertex.position)

proc copyTerrainSharedVertexData(
    world: var World, sourceMeshIndex, sourceVertexIndex, targetMeshIndex,
    targetVertexIndex: int
) =
  if sourceMeshIndex < 0 or sourceMeshIndex >= world.meshes.len or
      targetMeshIndex < 0 or targetMeshIndex >= world.meshes.len:
    return
  if sourceVertexIndex < 0 or sourceVertexIndex >=
      world.meshes[sourceMeshIndex].vertices.len or targetVertexIndex < 0 or
      targetVertexIndex >= world.meshes[targetMeshIndex].vertices.len:
    return
  let source = world.meshes[sourceMeshIndex].vertices[sourceVertexIndex]
  world.meshes[targetMeshIndex].vertices[targetVertexIndex].position.y =
    source.position.y
  world.meshes[targetMeshIndex].vertices[
      targetVertexIndex].splatUv = source.splatUv
  world.meshes[targetMeshIndex].vertices[targetVertexIndex].splatIndices =
    source.splatIndices
  world.meshes[targetMeshIndex].vertices[targetVertexIndex].splatWeights =
    source.splatWeights

proc syncTerrainSharedVertexData(
    world: var World, meshIndex, vertexIndex: int, touched: var HashSet[int]
) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  if vertexIndex < 0 or vertexIndex >= world.meshes[meshIndex].vertices.len:
    return
  let regionIndex = world.terrainRegionForMesh(meshIndex)
  if regionIndex < 0:
    return
  let
    region = world.terrainRegions[regionIndex]
    steps = terrainGridSteps()
    coord = terrainVertexCoord(vertexIndex)
  var dxs = @[0]
  var dzs = @[0]
  if coord.x == 0:
    dxs.add -1
  elif coord.x == steps:
    dxs.add 1
  if coord.z == 0:
    dzs.add -1
  elif coord.z == steps:
    dzs.add 1

  for dx in dxs:
    for dz in dzs:
      if dx == 0 and dz == 0:
        continue
      let neighborMesh = world.terrainMeshAtCell(region.cellX + dx,
          region.cellZ + dz)
      if neighborMesh < 0:
        continue
      let
        neighborX =
          if dx < 0: steps elif dx > 0: 0 else: coord.x
        neighborZ =
          if dz < 0: steps elif dz > 0: 0 else: coord.z
        neighborVertex = terrainVertexIndex(neighborX, neighborZ)
      world.copyTerrainSharedVertexData(
        meshIndex, vertexIndex, neighborMesh, neighborVertex
      )
      touched.incl neighborMesh

proc syncTerrainRegionFromNeighbors(world: var World, meshIndex: int) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  let regionIndex = world.terrainRegionForMesh(meshIndex)
  if regionIndex < 0:
    return
  let
    region = world.terrainRegions[regionIndex]
    steps = terrainGridSteps()
  block materialCopy:
    for dx in -1 .. 1:
      for dz in -1 .. 1:
        if dx == 0 and dz == 0:
          continue
        let neighborMesh = world.terrainMeshAtCell(region.cellX + dx,
            region.cellZ + dz)
        if neighborMesh >= 0:
          world.meshes[meshIndex].materials = world.meshes[
              neighborMesh].materials
          break materialCopy
  for z in 0 .. steps:
    for x in 0 .. steps:
      if x != 0 and x != steps and z != 0 and z != steps:
        continue
      let vertexIndex = terrainVertexIndex(x, z)
      block neighborCopy:
        for dx in [-1, 0, 1]:
          for dz in [-1, 0, 1]:
            if dx == 0 and dz == 0:
              continue
            if (dx < 0 and x != 0) or (dx > 0 and x != steps) or
                (dz < 0 and z != 0) or (dz > 0 and z != steps):
              continue
            let neighborMesh =
              world.terrainMeshAtCell(region.cellX + dx, region.cellZ + dz)
            if neighborMesh < 0:
              continue
            let
              neighborX = if dx < 0: steps elif dx > 0: 0 else: x
              neighborZ = if dz < 0: steps elif dz > 0: 0 else: z
              neighborVertex = terrainVertexIndex(neighborX, neighborZ)
            world.copyTerrainSharedVertexData(
              neighborMesh, neighborVertex, meshIndex, vertexIndex
            )
            break neighborCopy

proc terrainNormalKey(position: Vec3): TerrainNormalKey =
  const scale = 1000'f32
  (
    x: round(position.x * scale).int,
    y: round(position.y * scale).int,
    z: round(position.z * scale).int,
  )

proc smoothTerrainSharedNormals(world: var World) =
  var
    sums = initTable[TerrainNormalKey, Vec3]()
    counts = initTable[TerrainNormalKey, int]()
  for mesh in world.meshes:
    if mesh.kind != TerrainWorldMesh:
      continue
    for vertex in mesh.vertices:
      let key = terrainNormalKey(vertex.position)
      sums[key] = sums.getOrDefault(key, vec3(0, 0, 0)) + vertex.normal
      counts[key] = counts.getOrDefault(key, 0) + 1

  for mesh in world.meshes.mitems:
    if mesh.kind != TerrainWorldMesh:
      continue
    for vertex in mesh.vertices.mitems:
      let
        key = terrainNormalKey(vertex.position)
        normal = sums.getOrDefault(key, vertex.normal)
      if counts.getOrDefault(key, 0) > 1 and length(normal) > 0.000001'f32:
        vertex.normal = normalize(normal)

proc recalculateTerrainNormals*(world: var World, meshIndices: openArray[int]) =
  var recalculated = initHashSet[int]()
  for meshIndex in meshIndices:
    if meshIndex < 0 or meshIndex >= world.meshes.len or meshIndex in recalculated:
      continue
    world.meshes[meshIndex].recalculateNormals()
    recalculated.incl meshIndex
  world.smoothTerrainSharedNormals()
  world.markChanged()

proc selectedMeshKind*(world: World): WorldMeshKind =
  if world.meshes.len == 0 or world.selectedMesh < 0:
    return OtherWorldMesh
  world.meshes[world.selectedMesh].kind

proc normalizeSelectionState*(world: var World) =
  if world.selectedMesh < 0 or world.selectedMesh >= world.meshes.len:
    world.selectedMesh = if world.meshes.len > 0: 0 else: -1
  if world.selectedModel < 0 or world.selectedModel >= world.models.len:
    world.selectedModel = if world.models.len > 0: 0 else: -1
  if world.selectedEntitySpawn < 0 or
      world.selectedEntitySpawn >= world.entitySpawns.len:
    world.selectedEntitySpawn = if world.entitySpawns.len > 0: 0 else: -1

proc activeMesh(world: var World): var WorldMesh =
  if world.selectedMesh < 0 and world.meshes.len > 0:
    world.selectedMesh = 0
  world.meshes[world.selectedMesh].ensureTriangleMaterials()
  world.meshes[world.selectedMesh]

proc activeMesh(world: World): lent WorldMesh =
  let index = if world.selectedMesh >= 0: world.selectedMesh else: 0
  world.meshes[index]

proc selectedMeshMaterialCount*(world: World): int =
  if world.meshes.len == 0 or world.selectedMesh < 0:
    return 0
  world.activeMesh.materials.len

proc material*(world: World, meshIndex, materialIndex: int): WorldMaterial =
  world.meshes[meshIndex].materials[materialIndex]

proc selectedMaterial*(world: World, materialIndex: int): WorldMaterial =
  world.activeMesh.materials[materialIndex]

proc terrainSpecular*(world: World): float32 =
  for mesh in world.meshes:
    if mesh.kind != TerrainWorldMesh:
      continue
    for material in mesh.materials:
      if material.useTexture:
        return material.specularStrength
  DefaultSpecularStrength

proc setTerrainSpecular*(world: var World, value: float32) =
  var changed = false
  for mesh in world.meshes.mitems:
    if mesh.kind != TerrainWorldMesh:
      continue
    for material in mesh.materials.mitems:
      if material.specularStrength != value:
        material.specularStrength = value
        changed = true
  if changed:
    world.markChanged()

proc addMaterial*(world: var World, material: WorldMaterial): int =
  if world.meshes.len == 0:
    return -1
  let activeIndex = world.selectedMesh
  let activeKind = world.selectedMeshKind
  world.activeMesh.ensureDefaultMaterial()
  for i, existing in world.activeMesh.materials:
    if existing.id == material.id:
      world.activeMesh.materials[i] = material
      if activeKind == TerrainWorldMesh:
        for meshIndex, mesh in world.meshes.mpairs:
          if meshIndex != activeIndex and mesh.kind == TerrainWorldMesh:
            var found = false
            for materialIndex, existingMaterial in mesh.materials:
              if existingMaterial.id == material.id:
                world.meshes[meshIndex].materials[materialIndex] = material
                found = true
                break
            if not found:
              world.meshes[meshIndex].materials.add material
      world.markChanged()
      return i
  result = world.activeMesh.materials.len
  world.activeMesh.materials.add material
  if activeKind == TerrainWorldMesh:
    for meshIndex, mesh in world.meshes.mpairs:
      if meshIndex != activeIndex and mesh.kind == TerrainWorldMesh:
        var found = false
        for materialIndex, existingMaterial in mesh.materials:
          if existingMaterial.id == material.id:
            world.meshes[meshIndex].materials[materialIndex] = material
            found = true
            break
        if not found:
          world.meshes[meshIndex].materials.add material
  world.markChanged()

proc setTriangleMaterial*(world: var World, triangleIndex, materialIndex: int) =
  if world.meshes.len == 0:
    return
  world.activeMesh.ensureTriangleMaterials()
  if triangleIndex < 0 or triangleIndex >=
      world.activeMesh.triangleMaterials.len:
    return
  if materialIndex < 0 or materialIndex >= world.activeMesh.materials.len:
    return
  if world.activeMesh.triangleMaterials[triangleIndex] == materialIndex:
    return
  world.activeMesh.triangleMaterials[triangleIndex] = materialIndex
  world.markChanged()

proc setTriangleUvs*(world: var World, triangleIndex: int,
    uvs: array[3, Vec2]) =
  if world.meshes.len == 0:
    return
  world.activeMesh.ensureTriangleMaterials()
  if triangleIndex < 0 or triangleIndex >= world.activeMesh.triangleUvs.len:
    return
  if world.activeMesh.triangleUvs[triangleIndex] == uvs:
    return
  world.activeMesh.triangleUvs[triangleIndex] = uvs
  world.markChanged()

proc triangleContainsEdge(world: World, triangle, edgeA, edgeB: int): bool =
  let base = triangle * 3
  if base < 0 or base + 2 >= world.activeMesh.indices.len:
    return false
  let points = [world.activeMesh.indices[base].int,
      world.activeMesh.indices[base + 1].int,
      world.activeMesh.indices[base + 2].int]
  edgeA in points and edgeB in points

proc pairedQuad(world: World, triangle: int): array[2, int] =
  ## Return the coplanar triangle paired with this triangle, if any.
  result = [triangle, -1]
  let base = triangle * 3
  if base < 0 or base + 2 >= world.activeMesh.indices.len:
    return
  let points = [world.activeMesh.indices[base].int,
      world.activeMesh.indices[base + 1].int,
      world.activeMesh.indices[base + 2].int]
  for other in 0 ..< world.activeMesh.indices.len div 3:
    if other == triangle: continue
    for edge in [(points[0], points[1]), (points[1], points[2]),
        (points[2], points[0])]:
      if world.triangleContainsEdge(other, edge[0], edge[1]):
        result[1] = other
        return

proc edgeLoopCut*(world: var World, edgeA, edgeB: int): seq[int] =
  ## Split the quad under an edge into two quads.  Quads are stored as two
  ## triangles, so this preserves the renderer's triangle representation.
  if world.meshes.len == 0 or world.selectedMeshKind == TerrainWorldMesh or
      edgeA < 0 or edgeB < 0 or edgeA == edgeB:
    return
  var first = -1
  var second = -1
  for triangle in 0 ..< world.activeMesh.indices.len div 3:
    if world.triangleContainsEdge(triangle, edgeA, edgeB):
      let quad = world.pairedQuad(triangle)
      if quad[1] >= 0:
        first = quad[0]
        second = quad[1]
        break
  if first < 0 or second < 0:
    return

  var vertices: seq[int] = @[]
  for triangle in [first, second]:
    let base = triangle * 3
    for corner in 0 .. 2:
      let vertex = world.activeMesh.indices[base + corner].int
      if vertex notin vertices:
        vertices.add vertex
  if vertices.len != 4:
    return
  var c = -1
  var d = -1
  for vertex in vertices:
    if vertex != edgeA and vertex != edgeB:
      if c < 0: c = vertex else: d = vertex
  if c < 0 or d < 0:
    return
  # Orient the boundary as a-b-c-d.  The alternative ordering is a-b-d-c.
  var hasBC = false
  var hasAD = false
  for triangle in [first, second]:
    hasBC = hasBC or world.triangleContainsEdge(triangle, edgeB, c)
    hasAD = hasAD or world.triangleContainsEdge(triangle, edgeA, d)
  if not (hasBC and hasAD):
    swap(c, d)
  var mesh = addr world.activeMesh
  let aVertex = mesh[].vertices[edgeA]
  let bVertex = mesh[].vertices[edgeB]
  let cVertex = mesh[].vertices[c]
  let dVertex = mesh[].vertices[d]
  let midAB = mesh[].vertices.len
  var ab = aVertex
  ab.position = (aVertex.position + bVertex.position) * 0.5'f32
  ab.uv = (aVertex.uv + bVertex.uv) * 0.5'f32
  let midCD = midAB + 1
  var cd = cVertex
  cd.position = (cVertex.position + dVertex.position) * 0.5'f32
  cd.uv = (cVertex.uv + dVertex.uv) * 0.5'f32
  mesh[].vertices.add ab
  mesh[].vertices.add cd

  let material = mesh[].triangleMaterials[first]
  var newIndices: seq[uint32] = @[]
  var newMaterials: seq[int] = @[]
  var newUvs: seq[array[3, Vec2]] = @[]
  proc addTriangle(a, b, c: int) =
    newIndices.add a.uint32; newIndices.add b.uint32; newIndices.add c.uint32
    newMaterials.add material
    newUvs.add [mesh[].vertices[a].uv, mesh[].vertices[b].uv,
        mesh[].vertices[c].uv]
  for triangle in 0 ..< mesh[].indices.len div 3:
    if triangle == first:
      addTriangle(edgeA, midAB, midCD)
      addTriangle(edgeA, midCD, d)
    elif triangle == second:
      addTriangle(midAB, edgeB, c)
      addTriangle(midAB, c, midCD)
    else:
      let base = triangle * 3
      newIndices.add mesh[].indices[base]
      newIndices.add mesh[].indices[base + 1]
      newIndices.add mesh[].indices[base + 2]
      newMaterials.add mesh[].triangleMaterials[triangle]
      newUvs.add mesh[].triangleUvs[triangle]
  mesh[].indices = newIndices
  mesh[].triangleMaterials = newMaterials
  mesh[].triangleUvs = newUvs
  mesh[].recalculateNormals()
  world.markChanged()
  result = @[midAB, midCD]

proc setTerrainVertexSplat*(world: var World, vertexIndex, tileIndex: int,
    amount: float32, splatUv: Vec2) =
  if world.meshes.len == 0 or world.selectedMeshKind != TerrainWorldMesh:
    return
  if vertexIndex < 0 or vertexIndex >= world.activeMesh.vertices.len:
    return
  world.activeMesh.vertices[vertexIndex].splatUv = splatUv
  world.activeMesh.vertices[vertexIndex].blendSplat(tileIndex, clamp(amount,
      0'f32, 1'f32))
  world.markChanged()

proc setTerrainVertexSplat*(world: var World, meshIndex, vertexIndex,
    tileIndex: int, amount: float32, splatUv: Vec2) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  if vertexIndex < 0 or vertexIndex >= world.meshes[meshIndex].vertices.len:
    return
  world.meshes[meshIndex].vertices[vertexIndex].splatUv = splatUv
  world.meshes[meshIndex].vertices[vertexIndex].blendSplat(tileIndex, clamp(
      amount, 0'f32, 1'f32))
  var touched = initHashSet[int]()
  touched.incl meshIndex
  world.syncTerrainSharedVertexData(meshIndex, vertexIndex, touched)
  world.markChanged()

proc setTerrainSplatUvs*(world: var World, sampleSize: int) =
  if world.meshes.len == 0 or world.selectedMeshKind != TerrainWorldMesh:
    return
  const baseSample = 128'f32
  let scale = max(sampleSize.float32 / baseSample, 1'f32)
  for vertex in world.activeMesh.vertices.mitems:
    vertex.splatUv = vec2(vertex.position.x / scale, vertex.position.z / scale)
  world.markChanged()

proc setTerrainSplatUvs*(world: var World, meshIndex, sampleSize: int) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  const baseSample = 128'f32
  let scale = max(sampleSize.float32 / baseSample, 1'f32)
  for vertex in world.meshes[meshIndex].vertices.mitems:
    vertex.splatUv = vec2(vertex.position.x / scale, vertex.position.z / scale)
  world.markChanged()

proc setTerrainTriangleMaterial*(world: var World, meshIndex, triangleIndex,
    materialIndex: int) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  world.meshes[meshIndex].ensureTriangleMaterials()
  if triangleIndex < 0 or triangleIndex >=
      world.meshes[meshIndex].triangleMaterials.len:
    return
  if materialIndex < 0 or materialIndex >= world.meshes[
      meshIndex].materials.len:
    return
  if world.meshes[meshIndex].triangleMaterials[triangleIndex] == materialIndex:
    return
  world.meshes[meshIndex].triangleMaterials[triangleIndex] = materialIndex
  world.markChanged()

proc setTerrainTriangleUvs*(world: var World, meshIndex, triangleIndex: int,
    uvs: array[3, Vec2]) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  world.meshes[meshIndex].ensureTriangleMaterials()
  if triangleIndex < 0 or triangleIndex >= world.meshes[
      meshIndex].triangleUvs.len:
    return
  if world.meshes[meshIndex].triangleUvs[triangleIndex] == uvs:
    return
  world.meshes[meshIndex].triangleUvs[triangleIndex] = uvs
  world.markChanged()

proc triangleUvs*(world: World, triangleIndex: int): array[3, Vec2] =
  if world.meshes.len == 0 or triangleIndex < 0 or
      triangleIndex >= world.activeMesh.triangleUvs.len:
    return [vec2(0, 0), vec2(1, 0), vec2(0, 1)]
  world.activeMesh.triangleUvs[triangleIndex]

proc triangleMaterial*(world: World, triangleIndex: int): int =
  if world.meshes.len == 0 or triangleIndex < 0 or
      triangleIndex >= world.activeMesh.triangleMaterials.len:
    return 0
  world.activeMesh.triangleMaterials[triangleIndex]

proc vertices*(world: World): lent seq[Vertex] =
  world.activeMesh.vertices

proc indices*(world: World): lent seq[uint32] =
  world.activeMesh.indices

proc vertexCount*(world: World): int =
  if world.meshes.len == 0:
    return 0
  world.activeMesh.vertices.len

proc indexCount*(world: World): int =
  if world.meshes.len == 0:
    return 0
  world.activeMesh.indices.len

proc vertexPosition*(world: World, index: int): Vec3 =
  world.activeMesh.vertices[index].position

proc moveVertex*(world: var World, index: int, position: Vec3) =
  if world.meshes.len == 0:
    return
  if index < 0 or index >= world.activeMesh.vertices.len:
    return
  world.activeMesh.vertices[index].position = position
  if world.selectedMeshKind == TerrainWorldMesh:
    var touched = initHashSet[int]()
    touched.incl world.selectedMesh
    world.syncTerrainSharedVertexData(world.selectedMesh, index, touched)
  world.markChanged()

proc moveTerrainVertex*(world: var World, meshIndex, vertexIndex: int,
    position: Vec3) =
  if meshIndex < 0 or meshIndex >= world.meshes.len or
      world.meshes[meshIndex].kind != TerrainWorldMesh:
    return
  if vertexIndex < 0 or vertexIndex >= world.meshes[meshIndex].vertices.len:
    return
  world.meshes[meshIndex].vertices[vertexIndex].position = position
  var touched = initHashSet[int]()
  touched.incl meshIndex
  world.syncTerrainSharedVertexData(meshIndex, vertexIndex, touched)
  world.markChanged()

proc addVertex*(world: var World, position: Vec3, normal = vec3(0, 1, 0)): int =
  if world.meshes.len == 0:
    world.meshes.add initWorldMesh("Mesh 1", OtherWorldMesh)
    world.selectedMesh = 0
  result = world.activeMesh.vertices.len
  world.activeMesh.vertices.add Vertex(position: position, normal: normal,
      uv: vec2(0, 0))
  world.markChanged()

proc findVertexAt*(world: World, position: Vec3,
    maxDistance = MeshMergeDistance): int =
  if world.meshes.len == 0:
    return -1
  let maxDistanceSq = maxDistance * maxDistance
  for i, vertex in world.activeMesh.vertices:
    if distSq(vertex.position, position) <= maxDistanceSq:
      return i
  -1

proc addMergedVertex*(world: var World, position: Vec3,
    normal = vec3(0, 1, 0), maxDistance = MeshMergeDistance): int =
  result = world.findVertexAt(position, maxDistance)
  if result >= 0:
    return
  result = world.addVertex(position, normal)

proc sortedTriangle(a, b, c: int): array[3, int] =
  result = [a, b, c]
  if result[0] > result[1]:
    swap result[0], result[1]
  if result[1] > result[2]:
    swap result[1], result[2]
  if result[0] > result[1]:
    swap result[0], result[1]

proc hasTriangle*(world: World, a, b, c: int): bool =
  if world.meshes.len == 0:
    return false
  let wanted = sortedTriangle(a, b, c)
  var i = 0
  while i + 2 < world.activeMesh.indices.len:
    let existing = sortedTriangle(
      world.activeMesh.indices[i].int,
      world.activeMesh.indices[i + 1].int,
      world.activeMesh.indices[i + 2].int,
    )
    if existing == wanted:
      return true
    i += 3

proc addTriangle*(world: var World, a, b, c: int): bool {.discardable.} =
  if world.meshes.len == 0:
    return false
  if a < 0 or b < 0 or c < 0:
    return false
  if a == b or b == c or a == c:
    return false
  if a >= world.activeMesh.vertices.len or b >= world.activeMesh.vertices.len or
      c >= world.activeMesh.vertices.len:
    return false
  if world.hasTriangle(a, b, c):
    return false
  world.activeMesh.indices.add a.uint32
  world.activeMesh.indices.add b.uint32
  world.activeMesh.indices.add c.uint32
  world.activeMesh.triangleMaterials.add 0
  world.activeMesh.triangleUvs.add [
    world.activeMesh.vertices[a].uv,
    world.activeMesh.vertices[b].uv,
    world.activeMesh.vertices[c].uv,
  ]
  world.markChanged()
  true

proc deleteTriangles*(world: var World, shouldDelete: proc(
    a, b, c: int): bool {.closure.}): bool =
  if world.meshes.len == 0:
    return false
  var
    indices: seq[uint32] = @[]
    triangleMaterials: seq[int] = @[]
    triangleUvs: seq[array[3, Vec2]] = @[]
    deleted = false
  var triangle = 0
  while triangle * 3 + 2 < world.activeMesh.indices.len:
    let base = triangle * 3
    let
      a = world.activeMesh.indices[base].int
      b = world.activeMesh.indices[base + 1].int
      c = world.activeMesh.indices[base + 2].int
    if shouldDelete(a, b, c):
      deleted = true
    else:
      indices.add world.activeMesh.indices[base]
      indices.add world.activeMesh.indices[base + 1]
      indices.add world.activeMesh.indices[base + 2]
      if triangle < world.activeMesh.triangleMaterials.len:
        triangleMaterials.add world.activeMesh.triangleMaterials[triangle]
      if triangle < world.activeMesh.triangleUvs.len:
        triangleUvs.add world.activeMesh.triangleUvs[triangle]
    inc triangle
  if not deleted:
    return false
  world.activeMesh.indices = indices
  world.activeMesh.triangleMaterials = triangleMaterials
  world.activeMesh.triangleUvs = triangleUvs
  world.activeMesh.recalculateNormals()
  world.markChanged()
  true

proc deleteVertex*(world: var World, vertex: int): bool =
  if world.meshes.len == 0 or world.selectedMeshKind == TerrainWorldMesh or
      vertex < 0 or vertex >= world.activeMesh.vertices.len:
    return false
  discard world.deleteTriangles(proc(a, b, c: int): bool =
    vertex == a or vertex == b or vertex == c
  )
  world.activeMesh.vertices.delete(vertex)
  for index in world.activeMesh.indices.mitems:
    if index.int > vertex:
      dec index
  world.activeMesh.recalculateNormals()
  world.markChanged()
  true

proc deleteEdge*(world: var World, edgeA, edgeB: int): bool =
  if world.meshes.len == 0 or world.selectedMeshKind == TerrainWorldMesh or
      edgeA < 0 or edgeB < 0 or edgeA == edgeB or
      edgeA >= world.activeMesh.vertices.len or
      edgeB >= world.activeMesh.vertices.len:
    return false
  world.deleteTriangles(proc(a, b, c: int): bool =
    (edgeA == a or edgeA == b or edgeA == c) and
    (edgeB == a or edgeB == b or edgeB == c)
  )

proc flipTriangle*(world: var World, triangle: int): bool =
  if world.meshes.len == 0 or triangle < 0:
    result = false
    return
  let base = triangle * 3
  if base + 2 >= world.activeMesh.indices.len:
    result = false
    return
  swap world.activeMesh.indices[base + 1], world.activeMesh.indices[base + 2]
  if triangle < world.activeMesh.triangleUvs.len:
    swap world.activeMesh.triangleUvs[triangle][1],
      world.activeMesh.triangleUvs[triangle][2]
  world.activeMesh.recalculateNormals()
  world.markChanged()
  result = true

proc addMesh*(world: var World, name: string,
    kind = OtherWorldMesh): int =
  result = world.meshes.len
  world.meshes.add initWorldMesh(name, kind)
  world.selectedMesh = result
  world.markChanged()

proc addMesh*(world: var World, mesh: WorldMesh): int =
  result = world.meshes.len
  var newMesh = mesh
  newMesh.ensureTriangleMaterials()
  world.meshes.add newMesh
  world.selectedMesh = result
  world.markChanged()

proc addTerrainRegion(world: var World, meshIndex, cellX, cellZ: int) =
  if meshIndex < 0 or meshIndex >= world.meshes.len:
    return
  let cell = terrainCell(cellX, cellZ)
  if world.terrainRegionLookup.hasKey(cell) and
      world.terrainRegionLookup[cell] != meshIndex:
    return
  for region in world.terrainRegions.mitems:
    if region.meshIndex == meshIndex:
      world.terrainRegionLookup.del(terrainCell(region.cellX, region.cellZ))
      region.cellX = cellX
      region.cellZ = cellZ
      world.terrainRegionLookup[cell] = meshIndex
      world.markChanged()
      return
  world.terrainRegions.add WorldTerrainRegion(
    meshIndex: meshIndex, cellX: cellX, cellZ: cellZ
  )
  world.terrainRegionLookup[cell] = meshIndex
  world.markChanged()

proc addWaterPlane*(world: var World, name = ""): int =
  result = world.waterPlanes.len
  let planeName =
    if name.len > 0:
      name
    else:
      "Water " & $(result + 1)
  world.waterPlanes.add WorldWaterPlane.init(planeName)
  world.markChanged()

proc deleteWaterPlane*(world: var World, index: int) =
  if index < 0 or index >= world.waterPlanes.len:
    return
  world.waterPlanes.delete index
  world.markChanged()

proc setWaterPlane*(world: var World, index: int, plane: WorldWaterPlane) =
  if index < 0 or index >= world.waterPlanes.len:
    return
  world.waterPlanes[index] = plane
  world.markChanged()

proc setGlobalEnvironment*(world: var World, environment: WorldEnvironment) =
  world.globalEnvironment = environment
  world.markChanged()

proc addLocalEnvironment*(world: var World, name = ""): int =
  result = world.localEnvironments.len
  let environmentName =
    if name.len > 0:
      name
    else:
      "Environment " & $(result + 1)
  world.localEnvironments.add WorldEnvironment.init(environmentName)
  world.markChanged()

proc deleteLocalEnvironment*(world: var World, index: int) =
  if index < 0 or index >= world.localEnvironments.len:
    return
  world.localEnvironments.delete index
  world.markChanged()

proc setLocalEnvironment*(world: var World, index: int,
    environment: WorldEnvironment) =
  if index < 0 or index >= world.localEnvironments.len:
    return
  world.localEnvironments[index] = environment
  world.markChanged()

proc contains*(environment: WorldEnvironment, position: Vec3): bool =
  let halfSize = environment.boxSize * 0.5'f32
  position.x >= environment.boxCenter.x - halfSize.x and
    position.x <= environment.boxCenter.x + halfSize.x and
    position.y >= environment.boxCenter.y - halfSize.y and
    position.y <= environment.boxCenter.y + halfSize.y and
    position.z >= environment.boxCenter.z - halfSize.z and
    position.z <= environment.boxCenter.z + halfSize.z

proc activeEnvironment*(world: World, cameraPosition: Vec3): WorldEnvironment =
  for environment in world.localEnvironments:
    if environment.contains(cameraPosition):
      return environment
  world.globalEnvironment

proc fogRenderOptions*(environment: WorldEnvironment): FogRenderOptions =
  FogRenderOptions.init(
    nearColor = environment.fog.nearColor,
    farColor = environment.fog.farColor,
    density = environment.fog.density,
    falloff = environment.fog.falloff,
    limit = environment.fog.limit,
  )

proc skyRenderOptions*(
    environment: WorldEnvironment,
    skybox: TextureResourceHandle = nil,
): SkyRenderOptions =
  SkyRenderOptions.init(
    horizonColor = environment.skyHorizonColor,
    zenithColor = environment.skyZenithColor,
    groundColor = environment.skyGroundColor,
    skybox = skybox,
    exposure = environment.skyboxExposure,
    useSkybox = environment.useSkybox and skybox != nil,
  )

proc combinedMesh*(world: World): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  for mesh in world.meshes:
    let offset = result.vertices.len.uint32
    for sourceVertex in mesh.vertices:
      var vertex = sourceVertex
      vertex.position += mesh.position
      result.vertices.add vertex
    for index in mesh.indices:
      result.indices.add offset + index

proc appendTerrainRenderMesh(renderMesh: var WorldRenderMesh,
    source: WorldMesh) =
  var i = 0
  while i + 2 < source.indices.len:
    let
      a = source.vertices[source.indices[i].int]
      b = source.vertices[source.indices[i + 1].int]
      c = source.vertices[source.indices[i + 2].int]
      palette = terrainSplatPalette([a, b, c])
      offset = renderMesh.vertices.len.uint32
    for sourceVertex in [a, b, c]:
      var vertex = sourceVertex
      if not vertex.hasSplat():
        vertex.splatIndices = vec4(0, 0, 0, 0)
        vertex.splatWeights = vec4(1, 0, 0, 0)
      if vertex.splatUv == vec2(0, 0):
        vertex.splatUv = vec2(vertex.position.x, vertex.position.z)
      vertex.remapTerrainSplat(palette)
      renderMesh.vertices.add vertex
    renderMesh.indices.add offset
    renderMesh.indices.add offset + 1
    renderMesh.indices.add offset + 2
    i += 3

proc renderMeshes*(world: World): seq[WorldRenderMesh] =
  var terrainRenderMeshes = initTable[MaterialID, int]()
  for mesh in world.meshes:
    var source = mesh
    source.ensureTriangleMaterials()
    if source.kind == TerrainWorldMesh:
      let materialIndex =
        block:
          var found = 0
          for i, material in source.materials:
            if material.useTexture:
              found = i
              break
          found
      let materialID = source.materials[materialIndex].id
      let renderMeshIndex =
        if terrainRenderMeshes.hasKey(materialID):
          terrainRenderMeshes[materialID]
        else:
          result.add WorldRenderMesh(materialID: materialID)
          terrainRenderMeshes[materialID] = result.high
          result.high
      result[renderMeshIndex].appendTerrainRenderMesh(source)
      continue
    for materialIndex, material in source.materials:
      var renderMesh = WorldRenderMesh(materialID: material.id)
      var i = 0
      while i + 2 < source.indices.len:
        let triangleIndex = i div 3
        if source.triangleMaterials[triangleIndex] == materialIndex:
          let offset = renderMesh.vertices.len.uint32
          for corner in 0 .. 2:
            let vertexIndex = source.indices[i + corner].int
            var vertex = source.vertices[vertexIndex]
            vertex.position += source.position
            vertex.uv = source.triangleUvs[triangleIndex][corner]
            renderMesh.vertices.add vertex
          renderMesh.indices.add offset
          renderMesh.indices.add offset + 1
          renderMesh.indices.add offset + 2
        i += 3
      if renderMesh.indices.len > 0:
        result.add renderMesh

proc recalculateNormals*(mesh: var WorldMesh) =
  for vertex in mesh.vertices.mitems:
    vertex.normal = vec3(0, 0, 0)
  var i = 0
  while i + 2 < mesh.indices.len:
    let
      a = mesh.indices[i].int
      b = mesh.indices[i + 1].int
      c = mesh.indices[i + 2].int
    if a < mesh.vertices.len and b < mesh.vertices.len and c <
        mesh.vertices.len:
      let normal = normalize(cross(
        mesh.vertices[b].position - mesh.vertices[a].position,
        mesh.vertices[c].position - mesh.vertices[a].position,
      ))
      mesh.vertices[a].normal += normal
      mesh.vertices[b].normal += normal
      mesh.vertices[c].normal += normal
    i += 3
  for vertex in mesh.vertices.mitems:
    if length(vertex.normal) > 0.000001'f32:
      vertex.normal = normalize(vertex.normal)
    else:
      vertex.normal = vec3(0, 1, 0)

proc recalculateNormals*(world: var World) =
  if world.meshes.len == 0:
    return
  world.activeMesh.recalculateNormals()
  world.markChanged()

proc recalculateAllNormals*(world: var World) =
  for mesh in world.meshes.mitems:
    mesh.recalculateNormals()
  world.markChanged()

proc meshBounds(mesh: WorldMesh): tuple[minPoint, maxPoint: Vec3] =
  if mesh.vertices.len == 0:
    return (vec3(0, 0, 0), vec3(0, 0, 0))
  result.minPoint = mesh.vertices[0].position
  result.maxPoint = mesh.vertices[0].position
  for vertex in mesh.vertices:
    result.minPoint.x = min(result.minPoint.x, vertex.position.x)
    result.minPoint.y = min(result.minPoint.y, vertex.position.y)
    result.minPoint.z = min(result.minPoint.z, vertex.position.z)
    result.maxPoint.x = max(result.maxPoint.x, vertex.position.x)
    result.maxPoint.y = max(result.maxPoint.y, vertex.position.y)
    result.maxPoint.z = max(result.maxPoint.z, vertex.position.z)

proc centerModelMesh(mesh: var WorldMesh) =
  if mesh.kind == TerrainWorldMesh or mesh.vertices.len == 0: return
  let bounds = mesh.meshBounds()
  let center = (bounds.minPoint + bounds.maxPoint) * 0.5'f32
  for vertex in mesh.vertices.mitems:
    vertex.position -= center

proc terrainCellForMesh*(world: World, meshIndex: int): WorldTerrainRegion =
  let regionIndex = world.terrainRegionForMesh(meshIndex)
  if regionIndex >= 0:
    return world.terrainRegions[regionIndex]
  WorldTerrainRegion(meshIndex: meshIndex, cellX: 0, cellZ: 0)

proc createWorldMesh*(world: var World, name: string, size = 2'f32): int =
  let half = size * 0.5'f32
  var mesh = initWorldMesh(name, OtherWorldMesh)
  mesh.indices = @[0'u32, 1, 2, 0, 2, 3]
  mesh.triangleMaterials = @[0, 0]
  mesh.triangleUvs = @[
    [vec2(0, 0), vec2(1, 0), vec2(1, 1)],
    [vec2(0, 0), vec2(1, 1), vec2(0, 1)],
  ]
  for i, position in [
    vec3(-half, half, 0),
    vec3(half, half, 0),
    vec3(half, -half, 0),
    vec3(-half, -half, 0),
  ]:
    mesh.vertices.add Vertex(position: position, normal: vec3(0, 0, -1),
        uv: (if i < 2: mesh.triangleUvs[0][i] else: mesh.triangleUvs[1][i - 1]))
  mesh.recalculateNormals()
  result = world.addMesh(mesh)

proc addMeshTriangle(mesh: var WorldMesh, a, b, c: int) =
  mesh.indices.add a.uint32
  mesh.indices.add b.uint32
  mesh.indices.add c.uint32

proc createCubeWorldMesh*(world: var World, name: string, size = 2'f32): int =
  let half = size * 0.5'f32
  var mesh = initWorldMesh(name, OtherWorldMesh)
  for position in [
    vec3(-half, -half, -half),
    vec3(half, -half, -half),
    vec3(half, half, -half),
    vec3(-half, half, -half),
    vec3(-half, -half, half),
    vec3(half, -half, half),
    vec3(half, half, half),
    vec3(-half, half, half),
  ]:
    mesh.vertices.add Vertex(position: position, normal: vec3(0, 1, 0),
        uv: vec2(0, 0))
  for tri in [
    [0, 1, 2], [0, 2, 3],
    [4, 6, 5], [4, 7, 6],
    [0, 4, 5], [0, 5, 1],
    [1, 5, 6], [1, 6, 2],
    [2, 6, 7], [2, 7, 3],
    [3, 7, 4], [3, 4, 0],
  ]:
    mesh.addMeshTriangle(tri[0], tri[2], tri[1])
  mesh.ensureTriangleMaterials()
  mesh.recalculateNormals()
  result = world.addMesh(mesh)

proc createPyramidWorldMesh*(world: var World, name: string,
    size = 2'f32): int =
  let half = size * 0.5'f32
  var mesh = initWorldMesh(name, OtherWorldMesh)
  for position in [
    vec3(-half, -half, -half),
    vec3(half, -half, -half),
    vec3(half, -half, half),
    vec3(-half, -half, half),
    vec3(0, half, 0),
  ]:
    mesh.vertices.add Vertex(position: position, normal: vec3(0, 1, 0),
        uv: vec2(0, 0))
  for tri in [
    [0, 2, 1], [0, 3, 2],
    [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4],
  ]:
    mesh.addMeshTriangle(tri[0], tri[1], tri[2])
  mesh.ensureTriangleMaterials()
  mesh.recalculateNormals()
  result = world.addMesh(mesh)

proc createCylinderWorldMesh*(
    world: var World, name: string, radius = 1'f32, height = 2'f32,
    segments = 16
): int =
  let
    sideCount = max(segments, 3)
    halfHeight = height * 0.5'f32
    bottomCenter = 0
    topCenter = 1
  var mesh = initWorldMesh(name, OtherWorldMesh)
  mesh.vertices.add Vertex(position: vec3(0, -halfHeight, 0), normal: vec3(0,
      -1, 0), uv: vec2(0.5, 0.5))
  mesh.vertices.add Vertex(position: vec3(0, halfHeight, 0), normal: vec3(0, 1,
      0), uv: vec2(0.5, 0.5))
  for i in 0 ..< sideCount:
    let
      angle = 2'f32 * PI.float32 * i.float32 / sideCount.float32
      x = cos(angle) * radius
      z = sin(angle) * radius
      u = i.float32 / sideCount.float32
    mesh.vertices.add Vertex(position: vec3(x, -halfHeight, z),
        normal: vec3(x, 0, z), uv: vec2(u, 0))
    mesh.vertices.add Vertex(position: vec3(x, halfHeight, z),
        normal: vec3(x, 0, z), uv: vec2(u, 1))
  for i in 0 ..< sideCount:
    let
      next = (i + 1) mod sideCount
      bottomA = 2 + i * 2
      topA = bottomA + 1
      bottomB = 2 + next * 2
      topB = bottomB + 1
    mesh.addMeshTriangle(bottomA, bottomB, topB)
    mesh.addMeshTriangle(bottomA, topB, topA)
    mesh.addMeshTriangle(topCenter, topA, topB)
    mesh.addMeshTriangle(bottomCenter, bottomB, bottomA)
  mesh.ensureTriangleMaterials()
  mesh.recalculateNormals()
  result = world.addMesh(mesh)

proc createTerrainPlane*(world: var World, name: string, cellX = 0,
    cellZ = 0): int =
  let steps = max(TerrainRegionSubdivisions, 1)
  var mesh = initWorldMesh(name, TerrainWorldMesh)
  let origin = vec3(
    cellX.float32 * TerrainRegionSize, 0, cellZ.float32 * TerrainRegionSize
  )
  for z in 0 .. steps:
    for x in 0 .. steps:
      let
        u = x.float32 / steps.float32
        v = z.float32 / steps.float32
        position = origin + vec3(
          (u - 0.5'f32) * TerrainRegionSize,
          0,
          (v - 0.5'f32) * TerrainRegionSize,
        )
      mesh.vertices.add Vertex(position: position, normal: vec3(0, 1, 0),
          uv: vec2(u, v), splatUv: vec2(position.x, position.z),
              splatIndices: vec4(
          0, 0, 0, 0), splatWeights: vec4(1, 0, 0, 0))
  for z in 0 ..< steps:
    for x in 0 ..< steps:
      let
        a = (z * (steps + 1) + x).uint32
        b = a + 1
        c = ((z + 1) * (steps + 1) + x).uint32
        d = c + 1
      mesh.indices.add a
      mesh.indices.add c
      mesh.indices.add b
      mesh.indices.add b
      mesh.indices.add c
      mesh.indices.add d
      mesh.triangleMaterials.add 0
      mesh.triangleMaterials.add 0
      mesh.triangleUvs.add [
        mesh.vertices[a.int].uv,
        mesh.vertices[c.int].uv,
        mesh.vertices[b.int].uv,
      ]
      mesh.triangleUvs.add [
        mesh.vertices[b.int].uv,
        mesh.vertices[c.int].uv,
        mesh.vertices[d.int].uv,
      ]
  mesh.recalculateNormals()
  result = world.addMesh(mesh)
  world.addTerrainRegion(result, cellX, cellZ)
  world.syncTerrainRegionFromNeighbors(result)
  var touched = @[result]
  for dx in -1 .. 1:
    for dz in -1 .. 1:
      if dx == 0 and dz == 0:
        continue
      let neighbor = world.terrainMeshAtCell(cellX + dx, cellZ + dz)
      if neighbor >= 0 and neighbor notin touched:
        touched.add neighbor
  world.recalculateTerrainNormals(touched)

proc createTerrainRegion*(world: var World, name: string, cellX,
    cellZ: int): int =
  if world.terrainMeshAtCell(cellX, cellZ) >= 0:
    return -1
  world.createTerrainPlane(name, cellX, cellZ)

const
  SaveHeading = "ELLIPSE World 9."
  SaveHeading8 = "ELLIPSE World 8."
  SaveHeading7 = "ELLIPSE World 7."
  SaveHeading6 = "ELLIPSE World 6."
  SaveHeading5 = "ELLIPSE World 5."
  SaveHeading4 = "ELLIPSE World 4."
  SaveHeading3 = "ELLIPSE World 3."
  SaveHeading2 = "ELLIPSE World 2."
  SaveHeading1 = "ELLIPSE World 1."
  LegacySaveHeading = "ELLIPSE World 0."

proc writeVec3(stream: Stream, value: Vec3) =
  stream.write($value.x)
  stream.write(" ")
  stream.write($value.y)
  stream.write(" ")
  stream.write($value.z)
  stream.write("\n")

proc writeEnvironment(stream: Stream, environment: WorldEnvironment) =
  stream.write(environment.name)
  stream.write("\n")
  stream.writeVec3(environment.boxCenter)
  stream.writeVec3(environment.boxSize)
  stream.writeVec3(environment.fog.nearColor)
  stream.writeVec3(environment.fog.farColor)
  stream.writeVec3(environment.skyHorizonColor)
  stream.writeVec3(environment.skyZenithColor)
  stream.writeVec3(environment.skyGroundColor)
  stream.write($environment.fog.density)
  stream.write(" ")
  stream.write($environment.fog.falloff)
  stream.write(" ")
  stream.write($environment.fog.limit)
  stream.write("\n")
  stream.write(environment.skyboxPath)
  stream.write("\n")
  stream.write($environment.useSkybox)
  stream.write(" ")
  stream.write($environment.skyboxExposure)
  stream.write("\n")

proc write*(stream: Stream, world: World) =
  stream.write(SaveHeading)
  stream.write("\n")
  stream.write(world.id)
  stream.write("\n")
  stream.write($world.selectedMesh)
  stream.write("\n")
  stream.write($world.meshes.len)
  stream.write("\n")
  for mesh in world.meshes:
    stream.write(mesh.name)
    stream.write("\n")
    stream.write($mesh.kind)
    stream.write("\n")
    stream.writeVec3(mesh.position)
    stream.write($mesh.materials.len)
    stream.write("\n")
    for material in mesh.materials:
      stream.write(material.id)
      stream.write("\n")
      stream.write(material.name)
      stream.write("\n")
      stream.write(material.texturePath)
      stream.write("\n")
      stream.write($material.baseColor.x)
      stream.write(" ")
      stream.write($material.baseColor.y)
      stream.write(" ")
      stream.write($material.baseColor.z)
      stream.write(" ")
      stream.write($material.useTexture)
      stream.write(" ")
      stream.write($material.specularStrength)
      stream.write("\n")
    stream.write($mesh.indices.len.uint32)
    stream.write("\n")
    for i in mesh.indices:
      stream.write($i)
      stream.write(" ")
    stream.write("\n")
    stream.write($mesh.triangleMaterials.len.uint32)
    stream.write("\n")
    for materialIndex in mesh.triangleMaterials:
      stream.write($materialIndex)
      stream.write(" ")
    stream.write("\n")
    stream.write($mesh.triangleUvs.len.uint32)
    stream.write("\n")
    for uvs in mesh.triangleUvs:
      for uv in uvs:
        stream.write($uv.x)
        stream.write(" ")
        stream.write($uv.y)
        stream.write(" ")
      stream.write("\n")
    stream.write($mesh.vertices.len.uint32)
    stream.write("\n")
    for v in mesh.vertices:
      stream.write($v.position.x)
      stream.write(" ")
      stream.write($v.position.y)
      stream.write(" ")
      stream.write($v.position.z)
      stream.write("\t")
      stream.write($v.normal.x)
      stream.write(" ")
      stream.write($v.normal.y)
      stream.write(" ")
      stream.write($v.normal.z)
      stream.write("\t")
      stream.write($v.uv.x)
      stream.write(" ")
      stream.write($v.uv.y)
      stream.write(" ")
      stream.write($v.splatUv.x)
      stream.write(" ")
      stream.write($v.splatUv.y)
      stream.write(" ")
      stream.write($v.splatIndices.x)
      stream.write(" ")
      stream.write($v.splatIndices.y)
      stream.write(" ")
      stream.write($v.splatIndices.z)
      stream.write(" ")
      stream.write($v.splatIndices.w)
      stream.write(" ")
      stream.write($v.splatWeights.x)
      stream.write(" ")
      stream.write($v.splatWeights.y)
      stream.write(" ")
      stream.write($v.splatWeights.z)
      stream.write(" ")
      stream.write($v.splatWeights.w)
      stream.write("\n")
  stream.write($world.terrainRegions.len.uint32)
  stream.write("\n")
  for region in world.terrainRegions:
    stream.write($region.meshIndex)
    stream.write(" ")
    stream.write($region.cellX)
    stream.write(" ")
    stream.write($region.cellZ)
    stream.write("\n")
  stream.write($world.models.len)
  stream.write("\n")
  for model in world.models:
    stream.write(model.name)
    stream.write("\n")
    stream.write(model.sourceWorld)
    stream.write("\n")
    stream.write(model.sourceMesh)
    stream.write("\n")
    stream.writeVec3(model.position)
    stream.writeVec3(model.rotation)
    stream.writeVec3(model.scale)
  stream.write($world.entitySpawns.len)
  stream.write("\n")
  for spawn in world.entitySpawns:
    stream.write(spawn.entityID)
    stream.write("\n")
    stream.writeVec3(spawn.position)
  stream.write($world.waterPlanes.len.uint32)
  stream.write("\n")
  for water in world.waterPlanes:
    stream.write(water.name)
    stream.write("\n")
    stream.write($water.position.x)
    stream.write(" ")
    stream.write($water.position.y)
    stream.write(" ")
    stream.write($water.position.z)
    stream.write("\n")
    stream.write($water.size.x)
    stream.write(" ")
    stream.write($water.size.y)
    stream.write("\n")
    stream.write($water.waveAmplitude)
    stream.write(" ")
    stream.write($water.waveLength)
    stream.write(" ")
    stream.write($water.waveSpeed)
    stream.write("\n")
    stream.write($water.surfaceColor.x)
    stream.write(" ")
    stream.write($water.surfaceColor.y)
    stream.write(" ")
    stream.write($water.surfaceColor.z)
    stream.write("\n")
    stream.write($water.deepColor.x)
    stream.write(" ")
    stream.write($water.deepColor.y)
    stream.write(" ")
    stream.write($water.deepColor.z)
    stream.write("\n")
    stream.write($water.opacity)
    stream.write(" ")
    stream.write($water.specularStrength)
    stream.write("\n")
  stream.writeEnvironment(world.globalEnvironment)
  stream.write($world.localEnvironments.len.uint32)
  stream.write("\n")
  for environment in world.localEnvironments:
    stream.writeEnvironment(environment)

proc parseToken(stream: Stream): string {.raises: [IOError, OSError,
    ValueError].} =
  var lexeme = ""
  while not stream.atEnd() and stream.peekChar() in Whitespace:
    discard stream.readChar()
  while not stream.atEnd() and stream.peekChar() notin Whitespace:
    lexeme.add(stream.readChar())
  if lexeme.len == 0:
    raise ValueError.newException("Expected token")
  result = lexeme

proc parseInt*(stream: Stream): int {.raises: [IOError, OSError, ValueError].} =
  let lexeme = stream.parseToken()
  result = parseInt(lexeme)

proc parseFloat32(stream: Stream): float32 {.raises: [IOError, OSError,
    ValueError].} =
  let lexeme = stream.parseToken()
  result = parseFloat(lexeme).float32

proc parseVec3(stream: Stream): Vec3 {.raises: [IOError, OSError,
    ValueError].} =
  vec3(stream.parseFloat32(), stream.parseFloat32(), stream.parseFloat32())

proc parseBool(stream: Stream): bool {.raises: [IOError, OSError,
    ValueError].} =
  case stream.parseToken()
  of "true":
    true
  of "false":
    false
  else:
    raise ValueError.newException("Invalid bool")

proc parseVertex(line: string): Vertex =
  let parts = line.splitWhitespace()
  if parts.len != 8 and parts.len != 18:
    raise ValueError.newException("Invalid vertex")
  result = Vertex(
    position: vec3(parseFloat(parts[0]).float32, parseFloat(parts[1]).float32,
        parseFloat(parts[2]).float32),
    normal: vec3(parseFloat(parts[3]).float32, parseFloat(parts[4]).float32,
        parseFloat(parts[5]).float32),
    uv: vec2(parseFloat(parts[6]).float32, parseFloat(parts[7]).float32),
  )
  if parts.len == 18:
    result.splatUv = vec2(parseFloat(parts[8]).float32,
        parseFloat(parts[9]).float32)
    result.splatIndices = vec4(parseFloat(parts[10]).float32,
        parseFloat(parts[11]).float32, parseFloat(parts[12]).float32,
        parseFloat(parts[13]).float32)
    result.splatWeights = vec4(parseFloat(parts[14]).float32,
        parseFloat(parts[15]).float32, parseFloat(parts[16]).float32,
        parseFloat(parts[17]).float32)
  else:
    result.splatUv = result.uv
    result.splatIndices = vec4(0, 0, 0, 0)
    result.splatWeights = vec4(1, 0, 0, 0)

template eatLine*(s: Stream): auto =
  try:
    s.readLine()
  except:
    raise WorldError.newException(getCurrentExceptionMsg())

proc consumeLineEnd(stream: Stream) {.raises: [IOError, OSError].} =
  if stream.atEnd():
    return
  if stream.peekChar() == '\c':
    discard stream.readChar()
    if not stream.atEnd() and stream.peekChar() == '\l':
      discard stream.readChar()
  elif stream.peekChar() == '\l':
    discard stream.readChar()

template eatLineEnd*(s: Stream) =
  try:
    s.consumeLineEnd()
  except:
    raise WorldError.newException(getCurrentExceptionMsg())

template eatInt*(s: Stream): auto =
  try:
    s.parseInt()
  except:
    raise WorldError.newException("Invalid integer")

proc eatCount(stream: Stream): int =
  result = stream.eatInt()
  if result < 0:
    raise WorldError.newException("Invalid negative collection count")

proc eatIndex(stream: Stream): uint32 =
  let value = stream.eatInt()
  if value < 0 or value > uint32.high.int:
    raise WorldError.newException("Invalid mesh index")
  result = value.uint32

proc parseEnvironment(stream: Stream, hasLimit, hasSkybox,
    hasSkyColors: bool): WorldEnvironment {.
    raises: [WorldError].} =
  try:
    result = WorldEnvironment.init(stream.eatLine())
    result.boxCenter = stream.parseVec3()
    stream.eatLineEnd()
    result.boxSize = stream.parseVec3()
    stream.eatLineEnd()
    result.fog.nearColor = stream.parseVec3()
    stream.eatLineEnd()
    result.fog.farColor = stream.parseVec3()
    stream.eatLineEnd()
    if hasSkyColors:
      result.skyHorizonColor = stream.parseVec3()
      stream.eatLineEnd()
      result.skyZenithColor = stream.parseVec3()
      stream.eatLineEnd()
      result.skyGroundColor = stream.parseVec3()
      stream.eatLineEnd()
    else:
      result.skyHorizonColor = DefaultSkyHorizonColor
      result.skyZenithColor = result.fog.farColor
      result.skyGroundColor = DefaultSkyGroundColor
    result.fog.density = stream.parseFloat32()
    result.fog.falloff = stream.parseFloat32()
    if hasLimit:
      result.fog.limit = stream.parseFloat32()
    else:
      result.fog.limit = WorldFog.init().limit
    stream.eatLineEnd()
    if hasSkybox:
      result.skyboxPath = stream.eatLine()
      result.useSkybox = stream.parseBool()
      result.skyboxExposure = stream.parseFloat32()
      stream.eatLineEnd()
    else:
      result.skyboxPath = ""
      result.useSkybox = false
      result.skyboxExposure = 1'f32
  except:
    raise WorldError.newException("Invalid environment")

proc parseWorldMeshKind(value: string): WorldMeshKind =
  case value
  of "TerrainWorldMesh":
    TerrainWorldMesh
  else:
    OtherWorldMesh

proc inferTerrainRegions(world: var World) =
  world.terrainRegions.setLen(0)
  for meshIndex, mesh in world.meshes:
    if mesh.kind != TerrainWorldMesh:
      continue
    let bounds = mesh.meshBounds()
    let
      center = (bounds.minPoint + bounds.maxPoint) * 0.5'f32
      width = max(bounds.maxPoint.x - bounds.minPoint.x, MeshMergeDistance)
      depth = max(bounds.maxPoint.z - bounds.minPoint.z, MeshMergeDistance)
      cellSize = max(width, depth)
      cellX = round(center.x / cellSize).int
      cellZ = round(center.z / cellSize).int
    world.terrainRegions.add WorldTerrainRegion(
      meshIndex: meshIndex, cellX: cellX, cellZ: cellZ
    )
  world.rebuildTerrainRegionLookup()

proc read*(stream: Stream, world: var World) {.raises: [WorldError].} =
  let heading = stream.eatLine()
  let legacy = heading == LegacySaveHeading
  let version1 = heading == SaveHeading1
  let version2 = heading == SaveHeading2
  let version3 = heading == SaveHeading3
  let version9 = heading == SaveHeading
  let version8 = heading == SaveHeading8 or version9
  let version7 = heading == SaveHeading7 or version8
  let version6 = heading == SaveHeading6 or version7
  let version5 = heading == SaveHeading5 or version6
  let version4 = heading == SaveHeading4 or version5
  if not (
    version8 or version7 or version6 or version5 or version4 or version3 or version2 or
    version1 or
    legacy
  ):
    raise WorldError.newException("Invalid world heading")
  world.name = stream.eatLine()
  world.selectedMesh = stream.eatInt()
  stream.eatLineEnd()
  let meshCount = stream.eatCount()
  stream.eatLineEnd()
  world.meshes = newSeqOfCap[WorldMesh](meshCount)
  for _ in 0 ..< meshCount:
    var mesh = initWorldMesh(stream.eatLine(), OtherWorldMesh)
    mesh.kind = parseWorldMeshKind(stream.eatLine())
    if version8:
      try:
        mesh.position = stream.parseVec3()
        stream.eatLineEnd()
      except:
        raise WorldError.newException("Invalid mesh position")
    let materialCount = stream.eatCount()
    stream.eatLineEnd()
    mesh.materials.setLen(0)
    for _ in 0 ..< materialCount:
      try:
        let material = WorldMaterial(
          id: stream.eatLine().MaterialID,
          name: stream.eatLine(),
          texturePath: stream.eatLine(),
          baseColor: vec3(stream.parseFloat32(), stream.parseFloat32(),
              stream.parseFloat32()),
          useTexture: stream.parseBool(),
          specularStrength: (if version4: stream.parseFloat32() else:
          DefaultSpecularStrength),
        )
        stream.eatLineEnd()
        mesh.materials.add material
      except:
        raise WorldError.newException("Invalid material")
    mesh.ensureDefaultMaterial()
    let indiceCount = stream.eatCount()
    stream.eatLineEnd()
    mesh.indices = newSeqOfCap[uint32](indiceCount)
    for _ in 0 ..< indiceCount:
      let i = stream.eatIndex()
      mesh.indices.add(i)
    stream.eatLineEnd()
    let triangleMaterialCount = stream.eatCount()
    stream.eatLineEnd()
    mesh.triangleMaterials = newSeqOfCap[int](triangleMaterialCount)
    for _ in 0 ..< triangleMaterialCount:
      mesh.triangleMaterials.add stream.eatInt()
    stream.eatLineEnd()
    let triangleUvCount = stream.eatCount()
    stream.eatLineEnd()
    mesh.triangleUvs = newSeqOfCap[array[3, Vec2]](triangleUvCount)
    for _ in 0 ..< triangleUvCount:
      try:
        mesh.triangleUvs.add [
          vec2(stream.parseFloat32(), stream.parseFloat32()),
          vec2(stream.parseFloat32(), stream.parseFloat32()),
          vec2(stream.parseFloat32(), stream.parseFloat32()),
        ]
        stream.eatLineEnd()
      except:
        raise WorldError.newException("Invalid triangle uvs")
    let verticesCount = stream.eatCount()
    stream.eatLineEnd()
    mesh.vertices = newSeqOfCap[Vertex](verticesCount)
    for _ in 0 ..< verticesCount:
      try:
        mesh.vertices.add parseVertex(stream.readLine())
      except:
        raise WorldError.newException("Invalid vertex")
    mesh.ensureTriangleMaterials()
    if not version8:
      mesh.centerModelMesh()
    mesh.recalculateNormals()
    world.meshes.add mesh
  if legacy:
    world.inferTerrainRegions()
  else:
    let terrainRegionCount = stream.eatCount()
    stream.eatLineEnd()
    world.terrainRegions = newSeqOfCap[WorldTerrainRegion](terrainRegionCount)
    for _ in 0 ..< terrainRegionCount:
      try:
        let region = WorldTerrainRegion(
          meshIndex: stream.parseInt(),
          cellX: stream.parseInt(),
          cellZ: stream.parseInt(),
        )
        stream.eatLineEnd()
        if region.meshIndex >= 0 and region.meshIndex < world.meshes.len and
            world.meshes[region.meshIndex].kind == TerrainWorldMesh:
          world.terrainRegions.add region
      except:
        raise WorldError.newException("Invalid terrain region")
    world.rebuildTerrainRegionLookup()
  world.models.setLen(0)
  if version5:
    let modelCount = stream.eatCount()
    stream.eatLineEnd()
    for _ in 0 ..< modelCount:
      try:
        let name = stream.eatLine()
        let sourceWorld = stream.eatLine().WorldID
        let sourceMesh = stream.eatLine()
        let position = stream.parseVec3()
        stream.eatLineEnd()
        let rotation = stream.parseVec3()
        stream.eatLineEnd()
        let scale = stream.parseVec3()
        stream.eatLineEnd()
        world.models.add WorldModelInstance(name: name,
          sourceWorld: sourceWorld, sourceMesh: sourceMesh,
          position: position, rotation: rotation, scale: scale)
      except:
        raise WorldError.newException("Invalid model instance")
  world.entitySpawns.setLen(0)
  if version9:
    let spawnCount = stream.eatCount()
    stream.eatLineEnd()
    for _ in 0 ..< spawnCount:
      try:
        let entityID = stream.eatLine()
        let position = stream.parseVec3()
        stream.eatLineEnd()
        world.entitySpawns.add WorldEntitySpawn(entityID: entityID,
            position: position)
      except:
        raise WorldError.newException("Invalid entity spawn")
  let waterPlaneCount = stream.eatCount()
  stream.eatLineEnd()
  world.waterPlanes = newSeqOfCap[WorldWaterPlane](waterPlaneCount)
  for _ in 0 ..< waterPlaneCount:
    try:
      var water = WorldWaterPlane.init(stream.eatLine())
      water.position = vec3(
        stream.parseFloat32(), stream.parseFloat32(), stream.parseFloat32()
      )
      stream.eatLineEnd()
      water.size = vec2(stream.parseFloat32(), stream.parseFloat32())
      stream.eatLineEnd()
      water.waveAmplitude = stream.parseFloat32()
      water.waveLength = stream.parseFloat32()
      water.waveSpeed = stream.parseFloat32()
      stream.eatLineEnd()
      water.surfaceColor = vec3(
        stream.parseFloat32(), stream.parseFloat32(), stream.parseFloat32()
      )
      stream.eatLineEnd()
      water.deepColor = vec3(
        stream.parseFloat32(), stream.parseFloat32(), stream.parseFloat32()
      )
      stream.eatLineEnd()
      water.opacity = stream.parseFloat32()
      water.specularStrength = stream.parseFloat32()
      stream.eatLineEnd()
      world.waterPlanes.add water
    except:
      raise WorldError.newException("Invalid water plane")
  if version2 or version3 or version4:
    world.globalEnvironment = stream.parseEnvironment(version3 or version4,
        version6, version7)
    let environmentCount = stream.eatCount()
    stream.eatLineEnd()
    world.localEnvironments = newSeqOfCap[WorldEnvironment](environmentCount)
    for _ in 0 ..< environmentCount:
      world.localEnvironments.add stream.parseEnvironment(version3 or version4,
          version6, version7)
  else:
    world.globalEnvironment = WorldEnvironment.init("Environment 1")
    world.localEnvironments.setLen(0)
  world.normalizeSelectionState()
  world.markChanged()

proc draw*(artist: Artist3D, world: var World) =
  let mesh = world.combinedMesh()
  artist.setMesh(mesh.vertices, mesh.indices)
  artist.render()
