import std/[algorithm, math, sets]

import ellipse
import ellipse/rendering/cameras
import vmath

import ellipse/editing/inputs
import ellipse/worlds/worlds

const
  FocusPlaneStep* = PI.float32 / 12'f32
  GridStep* = 0.1'f32
  VertexHitRadius* = 0.09'f32
  EdgeHitRadius* = 0.07'f32
  EdgePickPixels* = 10'f32
  SelectionMarkerSegments* = 16
  SelectionMarkerPixels* = 9'f32
  HoverVertexPixels* = 6'f32
  HoverEdgePixels* = 5'f32
  TriangleMarkerPixels* = 2.5'f32
  TerrainCursorHeight* = 0.08'f32
  TerrainCursorRodRadius* = 0.035'f32
  CameraWidgetRodLength* = 0.14'f32
  CameraWidgetRodRadius* = 0.009'f32
  CameraWidgetHeadLength* = 0.06'f32
  CameraWidgetHeadRadius* = 0.026'f32
  InitialCameraPosition = vec3(0, 3.5, -6)
  InitialCameraPitch = 0.52'f32
  DefaultFovY = 70'f32
  CameraMaxFrameDt = 1'f32 / 60'f32
  KeyboardVertexMoveSpeed = 1.5'f32

type
  PickKind* = enum
    Empty
    Point
    Edge
    Triangle

  WorldMeshEditMode* = enum
    VertexEditMode
    TriangleEditMode
    QuadEditMode
    EdgeEditMode

  TerrainTool* = enum
    Raise
    Plateau
    Flatten
    Paint

  TerrainToolMode* = enum
    NormalTerrainToolMode
    InvertedTerrainToolMode

  MeshPick* = object
    kind*: PickKind
    vertex*: int
    triangle*: int
    edgeA*, edgeB*: int
    distance*, rayT*: float32

  EditorRay* = object
    origin*, direction*: Vec3
  TerrainBrushVertexKey = tuple[x, z: int]

  FocusPlane* = object
    angle*: float32
    origin*: Vec3

  MeshEditInput* = object
    mouseX*, mouseY*: int
    mouseLeftDown*, mouseLeftPressed*, mouseLeftReleased*: bool
    mouseMiddlePressed*: bool
    mouseRightDown*: bool
    multiSelect*: bool
    mouseDeltaX*, mouseDeltaY*: float32
    viewportWidth*, viewportHeight*: int

  WorldMeshEditor* = object
    focusPlane*: FocusPlane
    dragPlane*: FocusPlane
    input*: MeshEditInput
    selectedVertex*: int
    selectedVertices*: HashSet[int]
    selectedTriangles*: HashSet[int]
    selectedQuads*: HashSet[int]
    selectedMesh*: int
    keyboardMoveVertex*: int
    keyboardMovePosition*: Vec3
    hovered*: MeshPick
    ## The last edge seen in the viewport.  Geometry buttons live outside the
    ## viewport, so the target must survive moving the mouse into the panel.
    geometryEdge*: MeshPick
    dragging*: bool
    faceNormalDragging*: bool
    dragLastPosition*: Vec3
    dragAxisOrigin*: Vec3
    dragAxisDirection*: Vec3
    dragAxisLastOffset*: float32
    editMode*: WorldMeshEditMode
    quadExtrusionMode*: bool
    faceNormalDragMode*: bool
    terrainTool*: TerrainTool
    terrainToolMode*: TerrainToolMode
    brushRadius*: float32
    brushStrength*: float32
    plateauHeight*: float32
    terrainTextureIndex*: int
    terrainSampleSize*: int
    terrainPaintMaterial*: int
    terrainTabActive*: bool
    terrainCursorCellX*, terrainCursorCellZ*: int
    fpsCamera*: FpsCamera
    lastPickMouseX*, lastPickMouseY*: int
    lastPickViewportWidth*, lastPickViewportHeight*: int
    lastPickWorldRevision*: uint64
    lastPickCamera*: cameras.Camera
    pickInitialized*: bool
    cameraInputActive*: bool

proc init*(T: typedesc[WorldMeshEditor]): T =
  T(
    focusPlane: FocusPlane(angle: 0, origin: vec3(0, 0, 0)),
    selectedVertex: -1,
    selectedVertices: initHashSet[int](),
    selectedQuads: initHashSet[int](),
    selectedMesh: -1,
    geometryEdge: MeshPick(kind: Empty, edgeA: -1, edgeB: -1),
    keyboardMoveVertex: -1,
    terrainTool: Raise,
    terrainToolMode: NormalTerrainToolMode,
    brushRadius: 1.4'f32,
    brushStrength: 0.08'f32,
    plateauHeight: 1'f32,
    terrainTextureIndex: 0,
    terrainSampleSize: 128,
    terrainPaintMaterial: 0,
    terrainTabActive: true,
    fpsCamera:
    FpsCamera.init(position = InitialCameraPosition,
        pitch = InitialCameraPitch),
    editMode: VertexEditMode,
    quadExtrusionMode: false,
    faceNormalDragMode: false,
  )

proc rotateFocusPlane*(editor: var WorldMeshEditor, steps: int)

proc applyInput*(editor: var WorldMeshEditor, inputs: InputMap) =
  editor.input.mouseX = inputs.mouseX
  editor.input.mouseY = inputs.mouseY
  editor.input.mouseDeltaX = if inputs.down(
      GameCameraLook): inputs.mouseDeltaX else: 0
  editor.input.mouseDeltaY = if inputs.down(
      GameCameraLook): inputs.mouseDeltaY else: 0
  editor.input.mouseLeftDown = inputs.down(GamePrimary)
  editor.input.mouseLeftPressed = inputs.pressed(GamePrimary)
  editor.input.mouseLeftReleased = inputs.released(GamePrimary)
  editor.input.mouseMiddlePressed = inputs.pressed(GamePlaceCursor)
  editor.input.mouseRightDown = inputs.down(GameCameraLook)
  editor.input.multiSelect = inputs.down(GameMeshMultiSelect)
  if inputs.pressed(GameMeshRotatePlaneLeft):
    editor.rotateFocusPlane(-1)
  if inputs.pressed(GameMeshRotatePlaneRight):
    editor.rotateFocusPlane(1)

proc normal*(plane: FocusPlane): Vec3 =
  normalize(vec3(sin(plane.angle), 0, cos(plane.angle)))

proc axisU*(plane: FocusPlane): Vec3 =
  normalize(vec3(cos(plane.angle), 0, -sin(plane.angle)))

proc axisV*(plane: FocusPlane): Vec3 =
  vec3(0, 1, 0)

proc rotateFocusPlane*(editor: var WorldMeshEditor, steps: int) =
  editor.focusPlane.angle += FocusPlaneStep * steps.float32

proc updateCamera*(
    editor: var WorldMeshEditor, artist: Artist3D, inputs: InputMap, dt: float64
) =
  let previousCamera = editor.fpsCamera.camera
  let
    keyboardMoveVertex = inputs.down(GameMeshKeyboardMove)
    movingKeys =
      not keyboardMoveVertex and (
        inputs.down(GameCameraForward) or inputs.down(GameCameraBackward) or
        inputs.down(GameCameraLeft) or inputs.down(GameCameraRight) or
        inputs.down(GameCameraUp) or inputs.down(GameCameraDown)
      )
  let controls = FpsCameraControls(
    enabled: editor.input.mouseRightDown or movingKeys,
    lookX: editor.input.mouseDeltaX,
    lookY: editor.input.mouseDeltaY,
    forward: movingKeys and inputs.down(GameCameraForward),
    backward: movingKeys and inputs.down(GameCameraBackward),
    left: movingKeys and inputs.down(GameCameraLeft),
    right: movingKeys and inputs.down(GameCameraRight),
    up: movingKeys and inputs.down(GameCameraUp),
    down: movingKeys and inputs.down(GameCameraDown),
  )
  editor.cameraInputActive = controls.enabled
  editor.fpsCamera.update(controls, min(dt.float32, CameraMaxFrameDt))
  artist.activeCamera = editor.fpsCamera.camera
  if editor.fpsCamera.camera.position != previousCamera.position or
      editor.fpsCamera.camera.orientation != previousCamera.orientation:
    editor.pickInitialized = false

proc snapToTenths*(value: float32): float32 =
  round(value / GridStep) * GridStep

proc snapToFocusGrid*(point: Vec3, plane: FocusPlane): Vec3 =
  let
    u = plane.axisU
    v = plane.axisV
    relative = point - plane.origin
    snappedU = snapToTenths(dot(relative, u))
    snappedV = snapToTenths(dot(relative, v))
    planeOffset = dot(relative, plane.normal)
  plane.origin + u * snappedU + v * snappedV + plane.normal * planeOffset

proc snappedToPlaneGrid*(point: Vec3, plane: FocusPlane): Vec3 =
  let
    u = plane.axisU
    v = plane.axisV
    relative = point - plane.origin
    snappedU = snapToTenths(dot(relative, u))
    snappedV = snapToTenths(dot(relative, v))
  plane.origin + u * snappedU + v * snappedV

proc snapToWorldGrid*(point: Vec3): Vec3 =
  vec3(snapToTenths(point.x), snapToTenths(point.y), snapToTenths(point.z))

proc rayFromScreen*(
    mouseX, mouseY, viewportWidth, viewportHeight: int, camera: cameras.Camera
): EditorRay =
  let
    w = max(viewportWidth, 1).float32
    h = max(viewportHeight, 1).float32
    aspect = w / h
    halfFov = tan(DefaultFovY * PI.float32 / 360'f32)
    ndcX = (2'f32 * mouseX.float32 / w) - 1'f32
    ndcY = 1'f32 - (2'f32 * mouseY.float32 / h)
    cameraDirection = normalize(vec3(ndcX * aspect * halfFov, ndcY * halfFov, 1))
  EditorRay(
    origin: camera.position,
    direction: normalize(quatRotate(camera.orientation, cameraDirection)),
  )

proc pixelsToWorldRadius*(
    center: Vec3, camera: cameras.Camera, viewportHeight: int, pixels: float32
): float32 =
  let
    viewDistance = max(length(center - camera.position), 0.1'f32)
    pixelsToWorld =
      2'f32 * viewDistance * tan(DefaultFovY * PI.float32 / 360'f32) /
      max(viewportHeight, 1).float32
  pixels * pixelsToWorld

proc distanceRayPoint*(ray: EditorRay, point: Vec3): tuple[distance,
    rayT: float32] =
  let t = dot(point - ray.origin, ray.direction)
  if t < 0:
    return (float32.high, t)
  let closest = ray.origin + ray.direction * t
  (length(point - closest), t)

proc distanceRaySegment*(
    ray: EditorRay, a, b: Vec3
): tuple[distance, rayT, segmentT: float32] =
  let
    u = ray.direction
    v = b - a
    w = ray.origin - a
    aa = dot(u, u)
    bb = dot(u, v)
    cc = dot(v, v)
    dd = dot(u, w)
    ee = dot(v, w)
    denom = aa * cc - bb * bb

  var rayT, segmentT: float32
  if abs(denom) < 0.000001'f32:
    rayT = 0
    segmentT = clamp(ee / max(cc, 0.000001'f32), 0'f32, 1'f32)
  else:
    rayT = max((bb * ee - cc * dd) / denom, 0'f32)
    segmentT = clamp((aa * ee - bb * dd) / denom, 0'f32, 1'f32)

  let
    rayPoint = ray.origin + u * rayT
    segmentPoint = a + v * segmentT
  (length(rayPoint - segmentPoint), rayT, segmentT)

proc pickVertex*(world: World, ray: EditorRay): MeshPick =
  result =
    MeshPick(kind: Empty, vertex: -1, distance: VertexHitRadius,
        rayT: float32.high)
  if world.meshCount == 0:
    return
  for i, vertex in world.vertices:
    let hit = distanceRayPoint(ray, vertex.position)
    if hit.distance <= result.distance and hit.rayT < result.rayT:
      result = MeshPick(kind: Point, vertex: i, distance: hit.distance,
          rayT: hit.rayT)

proc pickEdge*(
    world: World, ray: EditorRay, camera: cameras.Camera, viewportHeight: int
): MeshPick =
  result = MeshPick(
    kind: Empty, edgeA: -1, edgeB: -1, distance: float32.high,
    rayT: float32.high
  )
  if world.meshCount == 0:
    return
  var i = 0
  while i + 2 < world.indices.len:
    let tri = [world.indices[i].int, world.indices[i + 1].int, world.indices[i + 2].int]
    for edge in [(tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])]:
      let
        a = world.vertexPosition(edge[0])
        b = world.vertexPosition(edge[1])
        midpoint = (a + b) * 0.5'f32
        edgeRadius = max(
          EdgeHitRadius,
          pixelsToWorldRadius(midpoint, camera, viewportHeight, EdgePickPixels),
        )
      let hit = distanceRaySegment(ray, a, b)
      let hitScore = hit.distance / edgeRadius
      if hitScore <= 1'f32 and (
        hitScore < result.distance or
        (hitScore == result.distance and hit.rayT < result.rayT)
      ):
        result = MeshPick(
          kind: Edge, edgeA: edge[0], edgeB: edge[1], distance: hitScore, rayT: hit.rayT
        )
    i += 3

proc intersectTriangle(ray: EditorRay, a, b, c: Vec3): tuple[hit: bool,
    rayT: float32] =
  let
    edge1 = b - a
    edge2 = c - a
    h = cross(ray.direction, edge2)
    det = dot(edge1, h)
  if abs(det) < 0.000001'f32:
    return (false, 0)
  let
    invDet = 1'f32 / det
    s = ray.origin - a
    u = invDet * dot(s, h)
  if u < 0 or u > 1:
    return (false, 0)
  let
    q = cross(s, edge1)
    v = invDet * dot(ray.direction, q)
  if v < 0 or u + v > 1:
    return (false, 0)
  let t = invDet * dot(edge2, q)
  if t <= 0.000001'f32:
    return (false, t)
  (true, t)

proc pickTriangle*(world: World, ray: EditorRay): MeshPick =
  result = MeshPick(kind: Empty, triangle: -1, rayT: float32.high)
  if world.meshCount == 0:
    return
  var i = 0
  while i + 2 < world.indices.len:
    let
      a = world.vertexPosition(world.indices[i].int)
      b = world.vertexPosition(world.indices[i + 1].int)
      c = world.vertexPosition(world.indices[i + 2].int)
      hit = intersectTriangle(ray, a, b, c)
    if hit.hit and hit.rayT < result.rayT:
      result = MeshPick(kind: Triangle, triangle: i div 3, rayT: hit.rayT)
    i += 3

proc triangleContainsEdge(world: World, triangle, edgeA, edgeB: int): bool =
  let base = triangle * 3
  if base < 0 or base + 2 >= world.indices.len:
    return false
  let points = [world.indices[base].int, world.indices[base + 1].int,
    world.indices[base + 2].int]
  (edgeA in points) and (edgeB in points)

proc adjacentTriangle(world: World, triangle, edgeA, edgeB: int): int =
  var candidate = 0
  while candidate * 3 + 2 < world.indices.len:
    if candidate != triangle and world.triangleContainsEdge(candidate, edgeA, edgeB):
      return candidate
    inc candidate
  -1

proc triangleNormal(world: World, triangle: int): Vec3 =
  let base = triangle * 3
  if base < 0 or base + 2 >= world.indices.len:
    return vec3()
  let
    a = world.vertexPosition(world.indices[base].int)
    b = world.vertexPosition(world.indices[base + 1].int)
    c = world.vertexPosition(world.indices[base + 2].int)
    normal = cross(b - a, c - a)
  if length(normal) <= 0.000001'f32:
    return vec3()
  normalize(normal)

proc quadForTriangle*(world: World, triangle: int): array[2, int] =
  result = [triangle, -1]
  if triangle < 0 or triangle * 3 + 2 >= world.indices.len:
    return
  let normal = world.triangleNormal(triangle)
  var fallback = -1
  let base = triangle * 3
  let points = [world.indices[base].int, world.indices[base + 1].int,
    world.indices[base + 2].int]
  for edge in [(points[0], points[1]), (points[1], points[2]),
      (points[2], points[0])]:
    let other = world.adjacentTriangle(triangle, edge[0], edge[1])
    if other >= 0:
      if fallback < 0:
        fallback = other
      let otherNormal = world.triangleNormal(other)
      if length(normal) > 0.000001'f32 and
          length(otherNormal) > 0.000001'f32 and
          dot(normal, otherNormal) > 0.98'f32:
        result[1] = other
        return
  result[1] = fallback

proc selectedQuadList*(editor: WorldMeshEditor): seq[int] =
  for quad in editor.selectedQuads:
    result.add quad
  result.sort()

proc flipSelectedFaces*(editor: WorldMeshEditor, world: var World) =
  for triangle in editor.selectedTriangles:
    discard world.flipTriangle(triangle)

proc pickMesh*(
    world: World, ray: EditorRay, camera: cameras.Camera, viewportHeight: int
): MeshPick =
  if world.meshCount == 0:
    return MeshPick(kind: Empty, vertex: -1, edgeA: -1, edgeB: -1)
  let
    vertexPick = world.pickVertex(ray)
    edgePick = world.pickEdge(ray, camera, viewportHeight)
  if edgePick.kind == Edge and vertexPick.kind == Point:
    return vertexPick
  if edgePick.kind == Edge:
    return edgePick
  vertexPick

proc pickEditable*(
    editor: WorldMeshEditor,
    world: World,
    ray: EditorRay,
    camera: cameras.Camera,
    viewportHeight: int,
): MeshPick =
  case editor.editMode
  of VertexEditMode:
    world.pickMesh(ray, camera, viewportHeight)
  of EdgeEditMode:
    world.pickEdge(ray, camera, viewportHeight)
  of TriangleEditMode, QuadEditMode:
    world.pickTriangle(ray)

proc intersectFocusPlane*(
    ray: EditorRay, plane: FocusPlane
): tuple[hit: bool, point: Vec3] =
  let denom = dot(ray.direction, plane.normal)
  if abs(denom) < 0.000001'f32:
    return (false, vec3())
  let t = dot(plane.origin - ray.origin, plane.normal) / denom
  if t < 0:
    return (false, vec3())
  (true, ray.origin + ray.direction * t)

proc moveSelectedVertex*(
    editor: var WorldMeshEditor, world: var World, ray: EditorRay
) =
  if editor.selectedVertex < 0:
    return
  let planeHit = ray.intersectFocusPlane(editor.dragPlane)
  if planeHit.hit:
    let position = snappedToPlaneGrid(planeHit.point, editor.dragPlane)
    let delta = position - editor.dragLastPosition
    if length(delta) <= 0.000001'f32:
      return
    for vertex in editor.selectedVertices:
      if vertex >= 0 and vertex < world.vertexCount:
        world.moveVertex(vertex, world.vertexPosition(vertex) + delta)
    editor.dragLastPosition = position
    editor.keyboardMovePosition = position

proc rayAxisOffset(ray: EditorRay, origin, axis: Vec3): float32 =
  let
    direction = normalize(axis)
    rayAxisDot = dot(ray.direction, direction)
    relative = ray.origin - origin
    rayOriginOffset = dot(ray.direction, relative)
    axisOriginOffset = dot(direction, relative)
    denom = 1'f32 - rayAxisDot * rayAxisDot
  if abs(denom) <= 0.000001'f32:
    return axisOriginOffset
  (axisOriginOffset - rayAxisDot * rayOriginOffset) / denom

proc selectedFaceVertices*(editor: WorldMeshEditor, world: World): HashSet[int] =
  result = initHashSet[int]()
  for triangle in editor.selectedTriangles:
    let base = triangle * 3
    if base >= 0 and base + 2 < world.indexCount:
      result.incl world.indices[base].int
      result.incl world.indices[base + 1].int
      result.incl world.indices[base + 2].int

proc selectedFaceNormalAndCenter(
    editor: WorldMeshEditor, world: World
): tuple[valid: bool, normal, center: Vec3] =
  var
    normal = vec3()
    center = vec3()
    centerCount = 0
  for triangle in editor.selectedTriangles:
    let base = triangle * 3
    if base < 0 or base + 2 >= world.indexCount:
      continue
    let
      a = world.vertexPosition(world.indices[base].int)
      b = world.vertexPosition(world.indices[base + 1].int)
      c = world.vertexPosition(world.indices[base + 2].int)
      triangleNormal = cross(b - a, c - a)
    if length(triangleNormal) > 0.000001'f32:
      normal += normalize(triangleNormal)
      center += a + b + c
      centerCount += 3
  if centerCount == 0 or length(normal) <= 0.000001'f32:
    return (false, vec3(), vec3())
  (true, normalize(normal), center / centerCount.float32)

proc beginFaceNormalDrag*(
    editor: var WorldMeshEditor, world: World, ray: EditorRay
) =
  let face = editor.selectedFaceNormalAndCenter(world)
  if not face.valid:
    editor.faceNormalDragging = false
    editor.dragging = false
    return
  editor.selectedVertices = editor.selectedFaceVertices(world)
  editor.selectedVertex = -1
  for vertex in editor.selectedVertices:
    editor.selectedVertex = vertex
    break
  editor.dragAxisOrigin = face.center
  editor.dragAxisDirection = face.normal
  editor.dragAxisLastOffset = snapToTenths(ray.rayAxisOffset(
    editor.dragAxisOrigin, editor.dragAxisDirection
  ))
  editor.faceNormalDragging = true
  editor.dragging = true
  editor.keyboardMoveVertex = -1

proc moveSelectedFaceAlongNormal*(
    editor: var WorldMeshEditor, world: var World, ray: EditorRay
) =
  if not editor.faceNormalDragging or editor.selectedVertices.len == 0:
    return
  let offset = snapToTenths(ray.rayAxisOffset(
    editor.dragAxisOrigin, editor.dragAxisDirection
  ))
  let deltaOffset = offset - editor.dragAxisLastOffset
  if abs(deltaOffset) <= 0.000001'f32:
    return
  let delta = editor.dragAxisDirection * deltaOffset
  for vertex in editor.selectedVertices:
    if vertex >= 0 and vertex < world.vertexCount:
      world.moveVertex(vertex, world.vertexPosition(vertex) + delta)
  editor.dragAxisOrigin += delta
  editor.dragAxisLastOffset = offset
  world.recalculateNormals()

proc horizontalDirection(direction: Vec3): Vec3 =
  result = vec3(direction.x, 0, direction.z)
  if length(result) > 0.000001'f32:
    result = normalize(result)

proc keyboardMoveSelectedVertex*(
    editor: var WorldMeshEditor,
    world: var World,
    camera: cameras.Camera,
    inputs: InputMap,
    dt: float64,
) =
  if editor.selectedVertex < 0 or editor.selectedVertex >= world.vertexCount:
    return
  if not inputs.down(GameMeshKeyboardMove):
    editor.keyboardMoveVertex = -1
    return

  let
    forward = horizontalDirection(camera.forward)
    right = horizontalDirection(camera.right)
  var direction = vec3()
  if inputs.down(GameCameraForward):
    direction += forward
  if inputs.down(GameCameraBackward):
    direction -= forward
  if inputs.down(GameCameraRight):
    direction += right
  if inputs.down(GameCameraLeft):
    direction -= right
  if inputs.down(GameCameraUp):
    direction += vec3(0, 1, 0)
  if inputs.down(GameCameraDown):
    direction -= vec3(0, 1, 0)
  if length(direction) <= 0.000001'f32:
    return

  if editor.keyboardMoveVertex != editor.selectedVertex:
    editor.keyboardMoveVertex = editor.selectedVertex
    editor.keyboardMovePosition = world.vertexPosition(editor.selectedVertex)
  let delta = normalize(direction) * KeyboardVertexMoveSpeed * min(dt.float32, CameraMaxFrameDt)
  editor.keyboardMovePosition += delta
  for vertex in editor.selectedVertices:
    if vertex >= 0 and vertex < world.vertexCount:
      world.moveVertex(vertex, world.vertexPosition(vertex) + delta)
  editor.focusPlane.origin = editor.keyboardMovePosition

proc selectedVertexList*(editor: WorldMeshEditor): seq[int] =
  for vertex in editor.selectedVertices:
    result.add vertex

proc clearSelection*(editor: var WorldMeshEditor)

proc deleteSelectedVertices*(editor: var WorldMeshEditor,
    world: var World): bool =
  var vertices = editor.selectedVertexList()
  vertices.sort()
  for i in countdown(vertices.len - 1, 0):
    result = world.deleteVertex(vertices[i]) or result
  if result:
    editor.clearSelection()
    editor.hovered = MeshPick(kind: Empty, vertex: -1, edgeA: -1, edgeB: -1)
    editor.pickInitialized = false

proc deleteHoveredEdge*(editor: var WorldMeshEditor, world: var World): bool =
  if editor.hovered.kind != Edge:
    return false
  result = world.deleteEdge(editor.hovered.edgeA, editor.hovered.edgeB)
  if result:
    editor.clearSelection()
    editor.hovered = MeshPick(kind: Empty, vertex: -1, edgeA: -1, edgeB: -1)
    editor.pickInitialized = false

proc edgeOutwardDirection(world: World, edgeA, edgeB: int,
    plane: FocusPlane): Vec3 =
  let
    a = world.vertexPosition(edgeA)
    b = world.vertexPosition(edgeB)
    edge = b - a
    midpoint = (a + b) * 0.5'f32
  if length(edge) <= 0.000001'f32:
    return vec3()
  var adjacentCenter = vec3()
  var adjacentCount = 0
  var i = 0
  while i + 2 < world.indices.len:
    let points = [world.indices[i].int, world.indices[i + 1].int,
      world.indices[i + 2].int]
    if (edgeA in points) and (edgeB in points):
      for point in points:
        if point != edgeA and point != edgeB:
          adjacentCenter += world.vertexPosition(point)
          inc adjacentCount
    i += 3
  if adjacentCount > 0:
    let edgeDirection = normalize(edge)
    let inward = adjacentCenter / adjacentCount.float32 - midpoint
    result = inward - edgeDirection * dot(inward, edgeDirection)
    if length(result) > 0.000001'f32:
      result = -normalize(result)
      return
  result = cross(normalize(edge), plane.normal)
  if length(result) <= 0.000001'f32:
    result = plane.axisV
  result = normalize(result)

proc edgeAdjacentNormal(world: World, edgeA, edgeB: int): Vec3 =
  var i = 0
  while i + 2 < world.indices.len:
    let points = [world.indices[i].int, world.indices[i + 1].int,
      world.indices[i + 2].int]
    if (edgeA in points) and (edgeB in points):
      let normal = cross(
        world.vertexPosition(points[1]) - world.vertexPosition(points[0]),
        world.vertexPosition(points[2]) - world.vertexPosition(points[0]),
      )
      if length(normal) > 0.000001'f32:
        return normalize(normal)
    i += 3
  vec3()

proc addExtrudedVertex(world: var World, position, normal, outward: Vec3): int =
  var candidate = position
  for attempt in 0 .. 8:
    if world.findVertexAt(candidate) < 0:
      return world.addVertex(candidate, normal)
    candidate += outward * GridStep * (attempt + 1).float32
  result = world.addVertex(candidate, normal)

proc addQuadFromEdge*(world: var World, edgeA, edgeB: int, plane: FocusPlane):
    array[2, int] =
  if edgeA < 0 or edgeB < 0 or edgeA >= world.vertexCount or edgeB >=
      world.vertexCount:
    result = [-1, -1]
    return
  let
    a = world.vertexPosition(edgeA)
    b = world.vertexPosition(edgeB)
    edge = b - a
    edgeLength = length(edge)
  if edgeLength <= 0.000001'f32:
    result = [-1, -1]
    return
  let side = world.edgeOutwardDirection(edgeA, edgeB, plane) * edgeLength
  let
    # Reuse existing corners so adjacent extrusions share one vertex instead
    # of offsetting the second extrusion to avoid a position collision.
    newA = world.addMergedVertex(a + side, -plane.normal)
    newB = world.addMergedVertex(b + side, -plane.normal)
  discard world.addTriangle(edgeA, newB, edgeB)
  discard world.addTriangle(edgeA, newA, newB)
  world.recalculateNormals()
  result = [newA, newB]

proc addSelectedFace*(world: var World, vertexIds: openArray[int],
    plane: FocusPlane, floor: bool): bool =
  if vertexIds.len < 3:
    result = false
    return
  var ids: seq[int]
  for id in vertexIds:
    ids.add id
  var center = vec3()
  for id in ids:
    if id < 0 or id >= world.vertexCount:
      result = false
      return
    center += world.vertexPosition(id)
  center /= ids.len.float32
  if floor:
    for id in ids:
      var p = world.vertexPosition(id)
      p.y = center.y
      world.moveVertex(id, p)
    let u = plane.axisU
    let w = plane.normal
    var angles: seq[tuple[id: int, angle: float32]]
    for id in ids:
      let relative = world.vertexPosition(id) - center
      angles.add (id: id, angle: arctan2(dot(relative, w), dot(relative, u)))
    angles.sort(proc(a, b: tuple[id: int, angle: float32]): int =
      cmp(a.angle, b.angle))
    ids.setLen(0)
    for item in angles:
      ids.add item.id
  else:
    let u = plane.axisU
    let v = plane.axisV
    var angles: seq[tuple[id: int, angle: float32]]
    for id in ids:
      let relative = world.vertexPosition(id) - center
      world.moveVertex(id, center + u * dot(relative, u) + v * dot(relative, v))
      angles.add (id: id, angle: arctan2(dot(relative, v), dot(relative, u)))
    angles.sort(proc(a, b: tuple[id: int, angle: float32]): int = cmp(a.angle, b.angle))
    ids.setLen(0)
    for item in angles:
      ids.add item.id
  for i in 1 ..< ids.len - 1:
    discard world.addTriangle(ids[0], ids[i], ids[i + 1])
  world.recalculateNormals()
  result = true

proc snapSelectedVertices*(editor: var WorldMeshEditor, world: var World) =
  for id in editor.selectedVertices:
    if id >= 0 and id < world.vertexCount:
      world.moveVertex(id, snapToWorldGrid(world.vertexPosition(id)))

proc levelSelectedVertices*(editor: var WorldMeshEditor, world: var World,
    axis: int) =
  if editor.selectedVertices.len == 0:
    return
  var total: float32
  for id in editor.selectedVertices:
    let p = world.vertexPosition(id)
    case axis
    of 0: total += p.x
    of 1: total += p.y
    else: total += p.z
  let value = total / editor.selectedVertices.len.float32
  for id in editor.selectedVertices:
    var p = world.vertexPosition(id)
    if axis == 0: p.x = value
    elif axis == 1: p.y = value
    else: p.z = value
    world.moveVertex(id, p)

proc addTriangleFromEdge*(world: var World, edgeA, edgeB: int,
    plane: FocusPlane): int =
  if edgeA < 0 or edgeB < 0 or edgeA >= world.vertexCount or edgeB >=
      world.vertexCount:
    return -1
  let
    a = world.vertexPosition(edgeA)
    b = world.vertexPosition(edgeB)
    edge = b - a
    edgeLength = length(edge)
  if edgeLength <= 0.000001'f32:
    return -1

  let planeNormal = plane.normal
  var planeEdge = edge - planeNormal * dot(edge, planeNormal)
  if length(planeEdge) <= 0.000001'f32:
    planeEdge = plane.axisU * edgeLength
  let edgeDirection = normalize(planeEdge)
  var direction = world.edgeOutwardDirection(edgeA, edgeB, plane)
  if length(direction) <= 0.000001'f32:
    direction = plane.axisU
  direction = normalize(direction)

  let midpoint = (a + b) * 0.5'f32

  let
    height = length(planeEdge) * sqrt(3'f32) * 0.5'f32
    position = midpoint + direction * height
  result = world.addExtrudedVertex(position, -planeNormal, direction)
  var expectedNormal = world.edgeAdjacentNormal(edgeA, edgeB)
  if length(expectedNormal) <= 0.000001'f32:
    expectedNormal = normalize(cross(b - a, direction))
  let added =
    if dot(cross(b - a, world.vertexPosition(result) - a), expectedNormal) >= 0:
      world.addTriangle(edgeA, edgeB, result)
    else:
      world.addTriangle(edgeB, edgeA, result)
  if added:
    world.recalculateNormals()

proc handleMouseDown*(editor: var WorldMeshEditor, world: var World,
    ray: EditorRay) =
  if world.meshCount == 0 or world.selectedMeshKind == TerrainWorldMesh:
    return
  if editor.editMode == EdgeEditMode:
    let pick = world.pickEdge(ray, editor.fpsCamera.camera,
      editor.input.viewportHeight)
    editor.hovered = pick
    editor.dragging = false
    editor.faceNormalDragging = false
    editor.keyboardMoveVertex = -1
    if pick.kind == Edge:
      editor.selectedTriangles.clear()
      editor.selectedQuads.clear()
      if not editor.input.multiSelect:
        editor.selectedVertices.clear()
      editor.selectedVertices.incl pick.edgeA
      editor.selectedVertices.incl pick.edgeB
      editor.selectedVertex = pick.edgeB
    return
  if editor.input.multiSelect and editor.editMode == VertexEditMode:
    let pick = world.pickVertex(ray)
    editor.hovered = pick
    editor.dragging = false
    editor.faceNormalDragging = false
    editor.keyboardMoveVertex = -1
    if pick.kind == Point:
      editor.selectedTriangles.clear()
      editor.selectedQuads.clear()
      editor.selectedVertices.incl pick.vertex
      editor.selectedVertex = pick.vertex
    return
  let pick = editor.pickEditable(
    world, ray, editor.fpsCamera.camera, editor.input.viewportHeight
  )
  editor.hovered = pick
  case pick.kind
  of Triangle:
    editor.selectedVertex = -1
    editor.selectedVertices.clear()
    editor.faceNormalDragging = false
    if pick.triangle >= 0:
      if editor.editMode == QuadEditMode:
        let quad = world.quadForTriangle(pick.triangle)
        let quadKey = if quad[1] < 0: quad[0] else: min(quad[0], quad[1])
        let selected = quadKey in editor.selectedQuads
        if editor.input.multiSelect and selected:
          editor.selectedQuads.excl quadKey
        elif editor.input.multiSelect:
          editor.selectedQuads.incl quadKey
        else:
          editor.selectedQuads.clear()
          editor.selectedQuads.incl quadKey
        if not editor.input.multiSelect or not selected:
          editor.selectedTriangles.clear()
          editor.selectedTriangles.incl quad[0]
          if quad[1] >= 0:
            editor.selectedTriangles.incl quad[1]
        else:
          editor.selectedTriangles.excl quad[0]
          if quad[1] >= 0:
            editor.selectedTriangles.excl quad[1]
      elif editor.input.multiSelect:
        editor.selectedQuads.clear()
        if pick.triangle in editor.selectedTriangles:
          editor.selectedTriangles.excl pick.triangle
        else:
          editor.selectedTriangles.incl pick.triangle
      else:
        editor.selectedQuads.clear()
        editor.selectedTriangles.clear()
        editor.selectedTriangles.incl pick.triangle
      if editor.faceNormalDragMode and not editor.input.multiSelect and
          editor.selectedTriangles.len > 0:
        editor.beginFaceNormalDrag(world, ray)
  of Point:
    editor.selectedTriangles.clear()
    editor.selectedQuads.clear()
    editor.faceNormalDragging = false
    if editor.input.multiSelect:
      if pick.vertex in editor.selectedVertices:
        editor.selectedVertices.excl pick.vertex
        if editor.selectedVertex == pick.vertex:
          editor.selectedVertex = -1
          for vertex in editor.selectedVertices:
            editor.selectedVertex = vertex
            break
      else:
        editor.selectedVertices.incl pick.vertex
        editor.selectedVertex = pick.vertex
    else:
      editor.selectedVertices.clear()
      editor.selectedVertices.incl pick.vertex
      editor.selectedVertex = pick.vertex
    if editor.input.multiSelect:
      editor.dragging = false
      editor.faceNormalDragging = false
      editor.keyboardMoveVertex = -1
      return
    if editor.selectedVertex < 0:
      editor.dragging = false
      editor.faceNormalDragging = false
      return
    editor.dragging = true
    editor.faceNormalDragging = false
    editor.focusPlane.origin = world.vertexPosition(pick.vertex)
    editor.dragPlane = editor.focusPlane
    editor.dragLastPosition = world.vertexPosition(pick.vertex)
    editor.keyboardMoveVertex = pick.vertex
    editor.keyboardMovePosition = world.vertexPosition(pick.vertex)
  of Edge:
    editor.selectedTriangles.clear()
    editor.selectedQuads.clear()
    if editor.quadExtrusionMode:
      let newVertices = world.addQuadFromEdge(pick.edgeA, pick.edgeB,
          editor.focusPlane)
      if newVertices[0] >= 0:
        editor.selectedVertices.clear()
        editor.selectedVertices.incl newVertices[0]
        editor.selectedVertices.incl newVertices[1]
        editor.selectedVertex = newVertices[1]
        # Edge extrusion is a click action; it must not also drag the new edge.
        editor.dragging = false
        editor.faceNormalDragging = false
        editor.keyboardMoveVertex = -1
    else:
      let newVertex = world.addTriangleFromEdge(pick.edgeA, pick.edgeB,
          editor.focusPlane)
      if newVertex >= 0:
        editor.selectedVertices.clear()
        editor.selectedVertices.incl newVertex
        editor.selectedVertex = newVertex
        editor.dragging = true
        editor.faceNormalDragging = false
        editor.focusPlane.origin = world.vertexPosition(newVertex)
        editor.dragPlane = editor.focusPlane
        let dragStart = ray.intersectFocusPlane(editor.dragPlane)
        editor.dragLastPosition =
          if dragStart.hit:
            snappedToPlaneGrid(dragStart.point, editor.dragPlane)
          else:
            editor.focusPlane.origin
        editor.keyboardMoveVertex = newVertex
        editor.keyboardMovePosition = world.vertexPosition(newVertex)
  of Empty:
    if not editor.input.multiSelect:
      editor.selectedVertex = -1
      editor.selectedVertices.clear()
      editor.selectedTriangles.clear()
    editor.keyboardMoveVertex = -1
    editor.faceNormalDragging = false

proc clearSelection*(editor: var WorldMeshEditor) =
  editor.selectedVertex = -1
  editor.selectedVertices.clear()
  editor.selectedTriangles.clear()
  editor.selectedQuads.clear()
  editor.dragging = false
  editor.faceNormalDragging = false
  editor.keyboardMoveVertex = -1

proc selectAllVertices*(editor: var WorldMeshEditor, world: World) =
  editor.selectedTriangles.clear()
  editor.selectedQuads.clear()
  editor.selectedVertices.clear()
  editor.selectedVertex = -1
  if world.meshCount == 0 or world.selectedMeshKind == TerrainWorldMesh:
    return
  for vertex in 0 ..< world.vertexCount:
    editor.selectedVertices.incl vertex
    editor.selectedVertex = vertex
  editor.dragging = false
  editor.faceNormalDragging = false
  editor.keyboardMoveVertex = -1

proc selectMesh*(editor: var WorldMeshEditor, world: var World, index: int) =
  world.selectedMesh = index
  editor.selectedMesh = world.selectedMesh
  editor.selectedVertex = -1
  editor.selectedVertices.clear()
  editor.selectedTriangles.clear()
  editor.selectedQuads.clear()
  editor.faceNormalDragging = false
  editor.keyboardMoveVertex = -1
  editor.hovered = MeshPick(kind: Empty, vertex: -1, edgeA: -1, edgeB: -1)
  editor.pickInitialized = false

proc terrainPoint*(ray: EditorRay): tuple[hit: bool, point: Vec3] =
  let denom = ray.direction.y
  if abs(denom) < 0.000001'f32:
    return (false, vec3())
  let t = -ray.origin.y / denom
  if t < 0:
    return (false, vec3())
  (true, ray.origin + ray.direction * t)

proc terrainRaycast*(world: World, ray: EditorRay): tuple[
    hit: bool,
    point: Vec3,
    rayT: float32
  ] =
  result = (hit: false, point: vec3(), rayT: float32.high)
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
      let hit = intersectTriangle(
        ray, mesh.vertices[ia].position, mesh.vertices[ib].position,
        mesh.vertices[ic].position,
      )
      if hit.hit and hit.rayT < result.rayT:
        result = (
          hit: true,
          point: ray.origin + ray.direction * hit.rayT,
          rayT: hit.rayT,
        )

proc brushWeight(distance, radius: float32): float32 =
  if radius <= 0:
    return 0
  let normalized = clamp(distance / radius, 0'f32, 1'f32)
  1'f32 - normalized * normalized * (3'f32 - 2'f32 * normalized)

proc terrainAtlasUv(tileIndex, sampleSize: int, u, v: float32): Vec2 =
  const
    columns = 8
    rows = 8
    baseSample = 128'f32
  let
    tile = clamp(tileIndex, 0, columns * rows - 1)
    col = tile mod columns
    row = tile div columns
    scale = max(sampleSize.float32 / baseSample, 1'f32)
    u0 = col.float32 / columns.float32
    v0 = row.float32 / rows.float32
    du = scale / columns.float32
    dv = scale / rows.float32
  vec2(u0 + u * du, v0 + v * dv)

proc terrainAtlasUvs(tileIndex, sampleSize: int, a, b, c: Vec3): array[3, Vec2] =
  let
    minX = min(a.x, min(b.x, c.x))
    maxX = max(a.x, max(b.x, c.x))
    minZ = min(a.z, min(b.z, c.z))
    maxZ = max(a.z, max(b.z, c.z))
    width = max(maxX - minX, 0.000001'f32)
    depth = max(maxZ - minZ, 0.000001'f32)

  proc cornerUv(point: Vec3): Vec2 =
    terrainAtlasUv(
      tileIndex,
      sampleSize,
      clamp((point.x - minX) / width, 0'f32, 1'f32),
      clamp((point.z - minZ) / depth, 0'f32, 1'f32),
    )

  [cornerUv(a), cornerUv(b), cornerUv(c)]

proc terrainSplatUv(position: Vec3, sampleSize: int): Vec2 =
  const baseSample = 128'f32
  let scale = max(sampleSize.float32 / baseSample, 1'f32)
  vec2(position.x / scale, position.z / scale)

proc terrainBrushVertexKey(position: Vec3): TerrainBrushVertexKey =
  const scale = 1000'f32
  (x: round(position.x * scale).int, z: round(position.z * scale).int)

proc applyTerrainTool*(editor: var WorldMeshEditor, world: var World,
    ray: EditorRay) =
  if world.meshCount == 0 or world.selectedMeshKind != TerrainWorldMesh:
    return
  let hit = ray.terrainPoint()
  if not hit.hit:
    return

  var touchedTerrainMeshes: seq[int]
  proc touchTerrainMesh(meshIndex: int) =
    if meshIndex >= 0 and meshIndex notin touchedTerrainMeshes:
      touchedTerrainMeshes.add meshIndex

  if editor.terrainTool == Paint:
    for region in world.terrainRegions:
      world.setTerrainSplatUvs(region.meshIndex, editor.terrainSampleSize)
    var paintedVertices = initHashSet[TerrainBrushVertexKey]()
    for terrainVertex in world.terrainVertices:
      let key = terrainBrushVertexKey(terrainVertex.position)
      if key in paintedVertices:
        continue
      paintedVertices.incl key
      let
        position = terrainVertex.position
        distance = length(vec2(position.x - hit.point.x, position.z - hit.point.z))
        weight = brushWeight(distance, editor.brushRadius)
      if weight > 0:
        world.setTerrainVertexSplat(
          terrainVertex.meshIndex,
          terrainVertex.vertexIndex,
          editor.terrainTextureIndex,
          weight * min(editor.brushStrength * 8'f32, 1'f32),
          terrainSplatUv(position, editor.terrainSampleSize),
        )
        touchTerrainMesh(terrainVertex.meshIndex)
    for region in world.terrainRegions:
      let mesh = world.mesh(region.meshIndex)
      var i = 0
      while i + 2 < mesh.indices.len:
        let
          a = mesh.vertices[mesh.indices[i].int].position
          b = mesh.vertices[mesh.indices[i + 1].int].position
          c = mesh.vertices[mesh.indices[i + 2].int].position
          center = (a + b + c) / 3'f32
          distance = length(vec2(center.x - hit.point.x, center.z - hit.point.z))
        if brushWeight(distance, editor.brushRadius) > 0:
          world.setTerrainTriangleMaterial(
            region.meshIndex, i div 3, editor.terrainPaintMaterial
          )
          world.setTerrainTriangleUvs(
            region.meshIndex,
            i div 3,
            terrainAtlasUvs(editor.terrainTextureIndex,
                editor.terrainSampleSize, a, b, c),
          )
          touchTerrainMesh(region.meshIndex)
        i += 3
    return

  let inverted = editor.terrainToolMode == InvertedTerrainToolMode
  var targetHeight =
    if inverted and editor.terrainTool == Plateau:
      -editor.plateauHeight
    else:
      editor.plateauHeight
  if editor.terrainTool == Flatten:
    var total, weights: float32
    var sampledVertices = initHashSet[TerrainBrushVertexKey]()
    for terrainVertex in world.terrainVertices:
      let key = terrainBrushVertexKey(terrainVertex.position)
      if key in sampledVertices:
        continue
      sampledVertices.incl key
      let
        position = terrainVertex.position
        distance = length(vec2(position.x - hit.point.x, position.z - hit.point.z))
        weight = brushWeight(distance, editor.brushRadius)
      if weight > 0:
        total += position.y * weight
        weights += weight
    if weights <= 0:
      return
    targetHeight = total / weights

  let raiseAmount =
    if abs(editor.input.mouseDeltaY) > 0:
      -editor.input.mouseDeltaY * editor.brushStrength
    else:
      editor.brushStrength
  let directionalRaiseAmount =
    if inverted:
      -raiseAmount
    else:
      raiseAmount

  var editedVertices = initHashSet[TerrainBrushVertexKey]()
  for terrainVertex in world.terrainVertices:
    let key = terrainBrushVertexKey(terrainVertex.position)
    if key in editedVertices:
      continue
    editedVertices.incl key
    var position = terrainVertex.position
    let
      distance = length(vec2(position.x - hit.point.x, position.z - hit.point.z))
      weight = brushWeight(distance, editor.brushRadius)
    if weight <= 0:
      continue
    case editor.terrainTool
    of Raise:
      position.y += directionalRaiseAmount * weight
    of Plateau:
      position.y =
        position.y + (targetHeight - position.y) * min(weight * 0.7'f32, 1'f32)
    of Flatten:
      position.y =
        position.y + (targetHeight - position.y) * min(weight * 0.35'f32, 1'f32)
    of Paint:
      discard
    world.moveTerrainVertex(terrainVertex.meshIndex, terrainVertex.vertexIndex, position)
    touchTerrainMesh(terrainVertex.meshIndex)
  for region in world.terrainRegions:
    touchTerrainMesh(region.meshIndex)
  world.recalculateTerrainNormals(touchedTerrainMeshes)

proc update*(
    editor: var WorldMeshEditor,
    world: var World,
    artist: Artist3D,
    inputs: InputMap,
    dt: float64,
) =
  if editor.selectedMesh != world.selectedMesh:
    editor.selectedMesh = world.selectedMesh
    editor.selectedVertex = -1
    editor.hovered = MeshPick(kind: Empty, vertex: -1, edgeA: -1, edgeB: -1)
    editor.geometryEdge = MeshPick(kind: Empty, edgeA: -1, edgeB: -1)
    editor.pickInitialized = false

  editor.applyInput(inputs)
  editor.updateCamera(artist, inputs, dt)
  if editor.cameraInputActive:
    editor.dragging = false
    editor.faceNormalDragging = false
    return

  let editingTerrain =
    world.meshCount > 0 and world.selectedMeshKind == TerrainWorldMesh and
    editor.terrainTabActive

  let ray = rayFromScreen(
    editor.input.mouseX, editor.input.mouseY, editor.input.viewportWidth,
    editor.input.viewportHeight, artist.activeCamera,
  )
  let meshOffset =
    if not editingTerrain and world.selectedMesh >= 0:
      world.meshPosition(world.selectedMesh)
    else:
      vec3(0, 0, 0)
  let localRay = EditorRay(origin: ray.origin - meshOffset,
      direction: ray.direction)
  var localCamera = artist.activeCamera
  localCamera.position -= meshOffset
  if inputs.pressed(GameMeshClearSelection):
    editor.clearSelection()

  if editor.input.mouseLeftPressed:
    if editingTerrain:
      editor.dragging = true
    else:
      editor.handleMouseDown(world, localRay)
  elif editor.input.mouseLeftReleased:
    if not editingTerrain and editor.dragging and editor.selectedVertex >= 0 and
        editor.selectedVertex < world.vertexCount:
      editor.focusPlane.origin = world.vertexPosition(editor.selectedVertex)
    editor.dragging = false
    editor.faceNormalDragging = false

  if editor.input.multiSelect:
    editor.dragging = false
    editor.faceNormalDragging = false

  if editor.dragging and editor.input.mouseLeftDown and
      not editor.input.mouseLeftPressed:
    if editingTerrain:
      editor.applyTerrainTool(world, ray)
    elif editor.faceNormalDragging:
      editor.moveSelectedFaceAlongNormal(world, localRay)
    else:
      editor.moveSelectedVertex(world, localRay)
    editor.pickInitialized = false

  if not editingTerrain and not editor.dragging:
    editor.keyboardMoveSelectedVertex(world, artist.activeCamera, inputs, dt)

  if not editingTerrain:
    let pickDirty =
      not editor.pickInitialized or editor.lastPickMouseX !=
          editor.input.mouseX or
      editor.lastPickMouseY != editor.input.mouseY or
      editor.lastPickViewportWidth != editor.input.viewportWidth or
      editor.lastPickViewportHeight != editor.input.viewportHeight or
      editor.lastPickWorldRevision != world.revision or
      editor.lastPickCamera.position != artist.activeCamera.position or
      editor.lastPickCamera.orientation != artist.activeCamera.orientation
    if pickDirty:
      editor.hovered =
        world.pickMesh(localRay, localCamera, editor.input.viewportHeight)
      editor.hovered = editor.pickEditable(
        world, localRay, localCamera, editor.input.viewportHeight
      )
      if editor.hovered.kind == Edge:
        editor.geometryEdge = editor.hovered
      editor.lastPickMouseX = editor.input.mouseX
      editor.lastPickMouseY = editor.input.mouseY
      editor.lastPickViewportWidth = editor.input.viewportWidth
      editor.lastPickViewportHeight = editor.input.viewportHeight
      editor.lastPickWorldRevision = world.revision
      editor.lastPickCamera = artist.activeCamera
      editor.pickInitialized = true
  else:
    editor.hovered = MeshPick(kind: Empty, vertex: -1, edgeA: -1, edgeB: -1)
    editor.selectedVertex = -1

proc appendMesh(
    target: var tuple[vertices: seq[Vertex], indices: seq[uint32]],
    source: tuple[vertices: seq[Vertex], indices: seq[uint32]],
) =
  let offset = target.vertices.len.uint32
  target.vertices.add source.vertices
  for index in source.indices:
    target.indices.add offset + index

proc vertexMarkerMesh(
    center: Vec3, camera: cameras.Camera, viewportHeight: int, pixels: float32
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let
    radius = pixelsToWorldRadius(center, camera, viewportHeight, pixels)
    right = normalize(quatRotate(camera.orientation, vec3(1, 0, 0)))
    up = normalize(quatRotate(camera.orientation, vec3(0, 1, 0)))
    normal = normalize(camera.position - center)

  result.vertices.add Vertex(position: center, normal: normal, uv: vec2(0, 0))
  for i in 0 ..< SelectionMarkerSegments:
    let angle = 2'f32 * PI.float32 * i.float32 / SelectionMarkerSegments.float32
    let point = center + right * cos(angle) * radius + up * sin(angle) * radius
    result.vertices.add Vertex(position: point, normal: normal, uv: vec2(0, 0))

  for i in 0 ..< SelectionMarkerSegments:
    let next =
      if i + 1 == SelectionMarkerSegments:
        1
      else:
        i + 2
    result.indices.add 0'u32
    result.indices.add next.uint32
    result.indices.add (i + 1).uint32

proc edgeMarkerMesh(
    a, b: Vec3, camera: cameras.Camera, viewportHeight: int,
        pixels = HoverEdgePixels
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let
    midpoint = (a + b) * 0.5'f32
    edge = b - a
  if length(edge) <= 0.000001'f32:
    return

  let
    edgeDirection = normalize(edge)
    viewDirection = normalize(midpoint - camera.position)
    width = pixelsToWorldRadius(midpoint, camera, viewportHeight, pixels)

  var side = cross(viewDirection, edgeDirection)
  if length(side) <= 0.000001'f32:
    side = quatRotate(camera.orientation, vec3(0, 1, 0))
  side = normalize(side) * width

  let normal = normalize(camera.position - midpoint)
  for point in [a + side, b + side, b - side, a - side]:
    result.vertices.add Vertex(position: point, normal: normal, uv: vec2(0, 0))
  result.indices = @[0'u32, 1, 2, 0, 2, 3]

proc triangleMarkerMesh(
    a, b, c: Vec3, camera: cameras.Camera, viewportHeight: int, selected: bool
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let
    center = (a + b + c) / 3'f32
    inset = if selected: 0.04'f32 else: 0.025'f32
    ia = a + (center - a) * inset
    ib = b + (center - b) * inset
    ic = c + (center - c) * inset
  result.appendMesh edgeMarkerMesh(ia, ib, camera, viewportHeight, TriangleMarkerPixels)
  result.appendMesh edgeMarkerMesh(ib, ic, camera, viewportHeight, TriangleMarkerPixels)
  result.appendMesh edgeMarkerMesh(ic, ia, camera, viewportHeight, TriangleMarkerPixels)

proc addPyramid(
    mesh: var tuple[vertices: seq[Vertex], indices: seq[uint32]],
    baseCenter, axis, sideA, sideB: Vec3,
    length, radius: float32,
) =
  let
    offset = mesh.vertices.len.uint32
    tip = baseCenter + axis * length
    a = baseCenter + sideA * radius
    b = baseCenter + sideB * radius
    c = baseCenter - sideA * radius
    d = baseCenter - sideB * radius
  for point in [tip, a, b, c, d]:
    mesh.vertices.add Vertex(position: point, normal: axis, uv: vec2(0, 0))
  for tri in [[0'u32, 1, 2], [0'u32, 2, 3], [0'u32, 3, 4], [0'u32, 4, 1]]:
    mesh.indices.add offset + tri[0]
    mesh.indices.add offset + tri[1]
    mesh.indices.add offset + tri[2]

proc addRod*(
    mesh: var tuple[vertices: seq[Vertex], indices: seq[uint32]],
    start, axis, sideA, sideB: Vec3,
    length, radius: float32,
) =
  let
    offset = mesh.vertices.len.uint32
    finish = start + axis * length
    points = [
      start + sideA * radius,
      start + sideB * radius,
      start - sideA * radius,
      start - sideB * radius,
      finish + sideA * radius,
      finish + sideB * radius,
      finish - sideA * radius,
      finish - sideB * radius,
    ]
  for point in points:
    mesh.vertices.add Vertex(position: point, normal: axis, uv: vec2(0, 0))
  for tri in [
    [0'u32, 4, 1],
    [1'u32, 4, 5],
    [1'u32, 5, 2],
    [2'u32, 5, 6],
    [2'u32, 6, 3],
    [3'u32, 6, 7],
    [3'u32, 7, 0],
    [0'u32, 7, 4],
  ]:
    mesh.indices.add offset + tri[0]
    mesh.indices.add offset + tri[1]
    mesh.indices.add offset + tri[2]

proc addBox(
    mesh: var tuple[vertices: seq[Vertex], indices: seq[uint32]],
    center: Vec3,
    size: float32,
) =
  let
    half = size * 0.5'f32
    offset = mesh.vertices.len.uint32
    points = [
      center + vec3(-half, -half, -half),
      center + vec3(half, -half, -half),
      center + vec3(half, half, -half),
      center + vec3(-half, half, -half),
      center + vec3(-half, -half, half),
      center + vec3(half, -half, half),
      center + vec3(half, half, half),
      center + vec3(-half, half, half),
    ]
  for point in points:
    mesh.vertices.add Vertex(position: point, normal: vec3(0, 1, 0), uv: vec2(0, 0))
  for tri in [
    [0'u32, 1, 2], [0'u32, 2, 3],
    [4'u32, 6, 5], [4'u32, 7, 6],
    [0'u32, 4, 5], [0'u32, 5, 1],
    [1'u32, 5, 6], [1'u32, 6, 2],
    [2'u32, 6, 7], [2'u32, 7, 3],
    [3'u32, 7, 4], [3'u32, 4, 0],
  ]:
    mesh.indices.add offset + tri[0]
    mesh.indices.add offset + tri[1]
    mesh.indices.add offset + tri[2]

proc addCameraWidgetArrow(
    mesh: var tuple[vertices: seq[Vertex], indices: seq[uint32]],
    center, axis, sideA, sideB: Vec3,
) =
  mesh.addRod(
    center, axis, sideA, sideB, CameraWidgetRodLength, CameraWidgetRodRadius
  )
  mesh.addPyramid(
    center + axis * CameraWidgetRodLength,
    axis,
    sideA,
    sideB,
    CameraWidgetHeadLength,
    CameraWidgetHeadRadius,
  )

proc cameraOrientationWidgetMeshes*(
    camera: cameras.Camera
): tuple[
  up: tuple[vertices: seq[Vertex], indices: seq[uint32]],
  right: tuple[vertices: seq[Vertex], indices: seq[uint32]],
  forward: tuple[vertices: seq[Vertex], indices: seq[uint32]],
] =
  let
    cameraForward = normalize(quatRotate(camera.orientation, vec3(0, 0, 1)))
    cameraRight = normalize(quatRotate(camera.orientation, vec3(1, 0, 0)))
    cameraUp = normalize(quatRotate(camera.orientation, vec3(0, 1, 0)))
    center =
      camera.position + cameraForward * 1.0'f32 - cameraRight * 0.52'f32 -
      cameraUp * 0.42'f32
    upAxis = vec3(0, 1, 0)
    rightAxis = vec3(1, 0, 0)
    forwardAxis = vec3(0, 0, 1)
    upSideA = vec3(1, 0, 0)
    upSideB = vec3(0, 0, 1)
    rightSideA = vec3(0, 1, 0)
    rightSideB = vec3(0, 0, 1)
    forwardSideA = vec3(1, 0, 0)
    forwardSideB = vec3(0, 1, 0)

  result.up.addCameraWidgetArrow(center, upAxis, upSideA, upSideB)
  result.right.addCameraWidgetArrow(center, rightAxis, rightSideA, rightSideB)
  result.forward.addCameraWidgetArrow(
    center, forwardAxis, forwardSideA, forwardSideB
  )

proc modelGizmoMeshes*(
    center: Vec3, camera: cameras.Camera, viewportHeight: int
): tuple[
  x: tuple[vertices: seq[Vertex], indices: seq[uint32]],
  y: tuple[vertices: seq[Vertex], indices: seq[uint32]],
  z: tuple[vertices: seq[Vertex], indices: seq[uint32]],
  center: tuple[vertices: seq[Vertex], indices: seq[uint32]],
] =
  let
    length = pixelsToWorldRadius(center, camera, viewportHeight, 78'f32)
    radius = pixelsToWorldRadius(center, camera, viewportHeight, 4'f32)
    boxSize = pixelsToWorldRadius(center, camera, viewportHeight, 12'f32)
    xAxis = vec3(1, 0, 0)
    yAxis = vec3(0, 1, 0)
    zAxis = vec3(0, 0, 1)

  result.x.addRod(center, xAxis, yAxis, zAxis, length, radius)
  result.y.addRod(center, yAxis, xAxis, zAxis, length, radius)
  result.z.addRod(center, zAxis, xAxis, yAxis, length, radius)
  result.center.addBox(center, boxSize)

proc terrainCursorMesh(
    cellX, cellZ: int
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let
    half = TerrainRegionSize * 0.5'f32
    center = vec3(
      cellX.float32 * TerrainRegionSize,
      TerrainCursorHeight,
      cellZ.float32 * TerrainRegionSize,
    )
    west = center.x - half
    east = center.x + half
    north = center.z - half
    south = center.z + half
    nw = vec3(west, TerrainCursorHeight, north)
    ne = vec3(east, TerrainCursorHeight, north)
    sw = vec3(west, TerrainCursorHeight, south)
    xAxis = vec3(1, 0, 0)
    zAxis = vec3(0, 0, 1)
    up = vec3(0, 1, 0)
  result.addRod(nw, xAxis, up, zAxis, TerrainRegionSize, TerrainCursorRodRadius)
  result.addRod(sw, xAxis, up, zAxis, TerrainRegionSize, TerrainCursorRodRadius)
  result.addRod(nw, zAxis, xAxis, up, TerrainRegionSize, TerrainCursorRodRadius)
  result.addRod(ne, zAxis, xAxis, up, TerrainRegionSize, TerrainCursorRodRadius)

proc placementCursorMesh*(
    center: Vec3, camera: cameras.Camera, viewportHeight: int
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let
    radius = pixelsToWorldRadius(center, camera, viewportHeight, 18'f32)
    height = pixelsToWorldRadius(center, camera, viewportHeight, 38'f32)
    rodRadius = pixelsToWorldRadius(center, camera, viewportHeight, 2.5'f32)
    xAxis = vec3(1, 0, 0)
    yAxis = vec3(0, 1, 0)
    zAxis = vec3(0, 0, 1)
  result.addRod(center - xAxis * radius, xAxis, yAxis, zAxis, radius * 2'f32,
      rodRadius)
  result.addRod(center - zAxis * radius, zAxis, xAxis, yAxis, radius * 2'f32,
      rodRadius)
  result.addRod(center, yAxis, xAxis, zAxis, height, rodRadius)

proc overlayMesh*(
    world: World, editor: WorldMeshEditor, camera: cameras.Camera
): tuple[vertices: seq[Vertex], indices: seq[uint32]] =
  let viewportHeight = editor.input.viewportHeight
  let meshOffset =
    if world.selectedMesh >= 0 and world.selectedMeshKind != TerrainWorldMesh:
      world.meshPosition(world.selectedMesh)
    else:
      vec3(0, 0, 0)
  var localCamera = camera
  localCamera.position -= meshOffset

  result.appendMesh terrainCursorMesh(
    editor.terrainCursorCellX, editor.terrainCursorCellZ
  )

  let editingTerrain =
    world.meshCount > 0 and world.selectedMeshKind == TerrainWorldMesh
  if not editingTerrain:
    case editor.hovered.kind
    of Point:
      if editor.hovered.vertex >= 0 and editor.hovered.vertex <
          world.vertexCount:
        result.appendMesh vertexMarkerMesh(
          world.vertexPosition(editor.hovered.vertex),
          localCamera,
          viewportHeight,
          HoverVertexPixels,
        )
    of Edge:
      if editor.hovered.edgeA >= 0 and editor.hovered.edgeB >= 0 and
          editor.hovered.edgeA < world.vertexCount and
          editor.hovered.edgeB < world.vertexCount:
        result.appendMesh edgeMarkerMesh(
          world.vertexPosition(editor.hovered.edgeA),
          world.vertexPosition(editor.hovered.edgeB),
          localCamera,
          viewportHeight,
        )
    of Triangle:
      let base = editor.hovered.triangle * 3
      if base >= 0 and base + 2 < world.indexCount:
        result.appendMesh triangleMarkerMesh(
          world.vertexPosition(world.indices[base].int),
          world.vertexPosition(world.indices[base + 1].int),
          world.vertexPosition(world.indices[base + 2].int),
          localCamera,
          viewportHeight,
          false,
        )
    of Empty:
      discard

    for triangle in editor.selectedTriangles:
      let base = triangle * 3
      if base >= 0 and base + 2 < world.indexCount:
        result.appendMesh triangleMarkerMesh(
          world.vertexPosition(world.indices[base].int),
          world.vertexPosition(world.indices[base + 1].int),
          world.vertexPosition(world.indices[base + 2].int),
          localCamera,
          viewportHeight,
          true,
        )

    if editor.selectedVertex >= 0 and editor.selectedVertex < world.vertexCount:
      result.appendMesh vertexMarkerMesh(
        world.vertexPosition(editor.selectedVertex),
        localCamera,
        viewportHeight,
        SelectionMarkerPixels,
      )
    for vertex in editor.selectedVertices:
      if vertex >= 0 and vertex < world.vertexCount and
          vertex != editor.selectedVertex:
        result.appendMesh vertexMarkerMesh(
          world.vertexPosition(vertex), localCamera, viewportHeight,
          SelectionMarkerPixels,
        )
    for vertex in result.vertices.mitems:
      vertex.position += meshOffset

proc syncViewport*(editor: var WorldMeshEditor, width, height: int) =
  editor.input.viewportWidth = max(width, 1)
  editor.input.viewportHeight = max(height, 1)
