import std/[algorithm, math, sets]
import ellipse
import vmath
import ellipse/worlds/worlds
import ellipse/editing/inputs

import state, uihelpers

const
  UvAltDragSensitivity = 0.1'f64
  UvAltDragSnapStep = 8'f64 / TerrainAtlasPixelSize.float64

proc configureUvDrag(state: var Mesh2DState) =
  state.altDragSensitivity = UvAltDragSensitivity
  state.altDragSnapStep = UvAltDragSnapStep

proc selectedTriangleList*(): seq[int] =
  for triangle in editor.meshEditor.selectedTriangles:
    result.add triangle
  result.sort()

proc selectedTriangleKey*(triangles: openArray[int]): string =
  for triangle in triangles:
    if result.len > 0:
      result.add ","
    result.add $triangle

proc uvTriangleArea*(uvs: array[3, Vec2]): float32 =
  abs(
    (uvs[1].x - uvs[0].x) * (uvs[2].y - uvs[0].y) -
      (uvs[2].x - uvs[0].x) * (uvs[1].y - uvs[0].y)
  ) * 0.5'f32

proc projectedTriangleUvs*(a, b, c: Vec3): array[3, Vec2] =
  let
    normal = cross(b - a, c - a)
    absNormal = vec3(abs(normal.x), abs(normal.y), abs(normal.z))

  proc project(point: Vec3): Vec2 =
    if absNormal.x >= absNormal.y and absNormal.x >= absNormal.z:
      vec2(point.y, point.z)
    elif absNormal.y >= absNormal.z:
      vec2(point.x, point.z)
    else:
      vec2(point.x, point.y)

  result = [project(a), project(b), project(c)]
  let
    minU = min(result[0].x, min(result[1].x, result[2].x))
    maxU = max(result[0].x, max(result[1].x, result[2].x))
    minV = min(result[0].y, min(result[1].y, result[2].y))
    maxV = max(result[0].y, max(result[1].y, result[2].y))
    width = maxU - minU
    height = maxV - minV
  if width <= 0.000001'f32 or height <= 0.000001'f32:
    return [vec2(0, 0), vec2(1, 0), vec2(0, 1)]
  for uv in result.mitems:
    uv = vec2((uv.x - minU) / width, (uv.y - minV) / height)

proc editableTriangleUvs*(triangle: int): array[3, Vec2] =
  result = editor.editWorld.triangleUvs(triangle)
  if result.uvTriangleArea() > 0.000001'f32:
    return
  let offset = triangle * 3
  if offset + 2 >= editor.editWorld.indices.len:
    return [vec2(0, 0), vec2(1, 0), vec2(0, 1)]
  result = projectedTriangleUvs(
    editor.editWorld.vertexPosition(editor.editWorld.indices[offset].int),
    editor.editWorld.vertexPosition(editor.editWorld.indices[offset + 1].int),
    editor.editWorld.vertexPosition(editor.editWorld.indices[offset + 2].int),
  )

proc triangleVertexIndices*(triangle: int): array[3, int] =
  let offset = triangle * 3
  if offset + 2 >= editor.editWorld.indices.len:
    return [-1, -1, -1]
  [
    editor.editWorld.indices[offset].int,
    editor.editWorld.indices[offset + 1].int,
    editor.editWorld.indices[offset + 2].int,
  ]

proc addUnique*(values: var seq[int], value: int) =
  if value < 0:
    return
  for existing in values:
    if existing == value:
      return
  values.add value

proc projectedQuadCoordinates*(vertexIds: openArray[int]): array[4, Vec2] =
  let
    a = editor.editWorld.vertexPosition(vertexIds[0])
    b = editor.editWorld.vertexPosition(vertexIds[1])
    c = editor.editWorld.vertexPosition(vertexIds[2])
    d = editor.editWorld.vertexPosition(vertexIds[3])
    normal = cross(b - a, c - a) + cross(c - a, d - a)
    absNormal = vec3(abs(normal.x), abs(normal.y), abs(normal.z))

  proc project(point: Vec3): Vec2 =
    if absNormal.x >= absNormal.y and absNormal.x >= absNormal.z:
      vec2(point.y, point.z)
    elif absNormal.y >= absNormal.z:
      vec2(point.x, point.z)
    else:
      vec2(point.x, point.y)

  [project(a), project(b), project(c), project(d)]

proc applyUvState*()

proc uvViewFrame(frame: Frame): Frame =
  let size = min(frame.width, frame.height)
  Frame(
    x: frame.x + (frame.width - size) * 0.5,
    y: frame.y + (frame.height - size) * 0.5,
    width: size,
    height: size,
  )

proc pickUvPoint(state: Mesh2DState, frame: Frame, mouseX, mouseY: int): int =
  const PointPickRadius = 14.0
  let view = uvViewFrame(frame)
  result = -1
  var best = PointPickRadius
  for i, point in state.points:
    let
      x = view.x + point.x * view.width
      y = view.y + point.y * view.height
      distance = hypot(mouseX.float64 - x, mouseY.float64 - y)
    if distance < best:
      best = distance
      result = i

proc selectAllUvPoints*() =
  editor.uvState.selectedPoints.clear()
  editor.uvState.selectedEdges.clear()
  for point in 0 ..< editor.uvState.points.len:
    editor.uvState.selectedPoints.incl point

proc rotateUvIsland*() =
  if editor.uvState.points.len == 0:
    return
  var
    minX = editor.uvState.points[0].x
    maxX = editor.uvState.points[0].x
    minY = editor.uvState.points[0].y
    maxY = editor.uvState.points[0].y
  for point in editor.uvState.points:
    minX = min(minX, point.x)
    maxX = max(maxX, point.x)
    minY = min(minY, point.y)
    maxY = max(maxY, point.y)
  let
    centerX = (minX + maxX) * 0.5
    centerY = (minY + maxY) * 0.5
  for point in editor.uvState.points.mitems:
    let
      dx = point.x - centerX
      dy = point.y - centerY
    point.x = centerX - dy
    point.y = centerY + dx
  applyUvState()

proc applyRectangleWinding*(vertexIds: var seq[int]) =
  if vertexIds.len != 4:
    return
  var ordered = vertexIds
  if (editor.uvRectangleWinding div 4) mod 2 == 1:
    ordered = @[ordered[0], ordered[3], ordered[2], ordered[1]]
  let rotation = editor.uvRectangleWinding mod 4
  for i in 0 ..< 4:
    vertexIds[i] = ordered[(i + rotation) mod 4]

proc selectedRectangleVertexIds*(): seq[int] =
  if editor.uvTriangles.len != 2:
    return

  let
    first = editor.uvTriangles[0].triangleVertexIndices()
    second = editor.uvTriangles[1].triangleVertexIndices()
  for vertex in first:
    result.addUnique vertex
  for vertex in second:
    result.addUnique vertex
  if result.len != 4:
    result.setLen(0)
    return

  let projected = projectedQuadCoordinates(result)
  var center = vec2(0, 0)
  for uv in projected:
    center += uv
  center /= 4'f32

  type QuadCorner = object
    vertex: int
    angle: float32

  var corners: seq[QuadCorner]
  for i, vertex in result:
    corners.add QuadCorner(
      vertex: vertex,
      angle: arctan2(projected[i].y - center.y, projected[i].x - center.x),
    )
  corners.sort(
    proc(a, b: QuadCorner): int =
    cmp(a.angle, b.angle)
  )

  result.setLen(0)
  for corner in corners:
    result.add corner.vertex
  result.applyRectangleWinding()

proc setRectangleTriangleWinding*(vertexIds: seq[int]): bool =
  if vertexIds.len != 4 or editor.uvTriangles.len != 2:
    return false
  let
    first = editor.uvTriangles[0].triangleVertexIndices()
    second = editor.uvTriangles[1].triangleVertexIndices()

  proc pointForVertex(vertex: int): int =
    for i, id in vertexIds:
      if id == vertex:
        return i
    -1

  let
    firstPoints =
      [pointForVertex(first[0]), pointForVertex(first[1]), pointForVertex(first[2])]
    secondPoints =
      [pointForVertex(second[0]), pointForVertex(second[1]), pointForVertex(
          second[2])]
  if firstPoints[0] < 0 or firstPoints[1] < 0 or firstPoints[2] < 0 or
      secondPoints[0] < 0 or secondPoints[1] < 0 or secondPoints[2] < 0:
    return false

  editor.uvState.triangles.setLen(0)
  editor.uvState.triangles.add firstPoints
  editor.uvState.triangles.add secondPoints
  true

proc tryRectangleWinding*(): bool =
  if editor.uvTriangles.len != 2:
    return false
  editor.uvRectangleWinding = (editor.uvRectangleWinding + 1) mod 8
  let vertexIds = selectedRectangleVertexIds()
  if vertexIds.len != 4 or not setRectangleTriangleWinding(vertexIds):
    return false
  applyUvState()
  true

proc mapSelectedPairToRectangle*(): bool =
  if editor.uvTriangles.len != 2:
    return false

  editor.uvRectangleWinding = 0
  var vertexIds = selectedRectangleVertexIds()
  if vertexIds.len != 4:
    return false

  var
    sideWidth = dist(
      editor.editWorld.vertexPosition(vertexIds[0]),
      editor.editWorld.vertexPosition(vertexIds[1]),
    )
    sideHeight = dist(
      editor.editWorld.vertexPosition(vertexIds[1]),
      editor.editWorld.vertexPosition(vertexIds[2]),
    )
  if sideWidth <= 0.000001'f32 or sideHeight <= 0.000001'f32:
    return false

  let
    cellWidth = 1'f32 / TerrainAtlasColumns.float32
    cellHeight = 1'f32 / TerrainAtlasRows.float32
    tileX = editor.uvTextureIndex mod TerrainAtlasColumns
    tileY = editor.uvTextureIndex div TerrainAtlasColumns
    scale = min(cellWidth / sideWidth, cellHeight / sideHeight)
    rectWidth = sideWidth * scale
    rectHeight = sideHeight * scale
    origin =
      vec2(
        tileX.float32 * cellWidth + (cellWidth - rectWidth) * 0.5'f32,
        tileY.float32 * cellHeight + (cellHeight - rectHeight) * 0.5'f32,
      )
    rectUvs = [
      origin,
      vec2(origin.x + rectWidth, origin.y),
      vec2(origin.x + rectWidth, origin.y + rectHeight),
      vec2(origin.x, origin.y + rectHeight),
    ]

  editor.uvState = Mesh2DState()
  editor.uvState.configureUvDrag()
  for uv in rectUvs:
    editor.uvState.points.add Mesh2DPoint(x: uv.x.float64, y: uv.y.float64)

  if not setRectangleTriangleWinding(vertexIds):
    return false
  result = true
  applyUvState()

proc syncUvState*() =
  if editor.editWorld.meshCount == 0:
    editor.uvSelectionKey = ""
    editor.uvTriangles.setLen(0)
    editor.uvState = Mesh2DState()
    return
  let triangles = selectedTriangleList()
  let key = triangles.selectedTriangleKey()
  if editor.uvSelectionKey == key:
    return
  editor.uvSelectionKey = key
  editor.uvTriangles = triangles
  editor.uvRectangleWinding = 0
  editor.uvState = Mesh2DState()
  editor.uvState.configureUvDrag()
  for triangle in triangles:
    let uvs = editableTriangleUvs(triangle)
    let offset = editor.uvState.points.len
    for uv in uvs:
      editor.uvState.points.add Mesh2DPoint(x: uv.x, y: uv.y)
    editor.uvState.triangles.add [offset, offset + 1, offset + 2]

proc applyUvState*() =
  for i, triangle in editor.uvTriangles:
    if i >= editor.uvState.triangles.len:
      continue
    let pointIndices = editor.uvState.triangles[i]
    if pointIndices[0] < 0 or pointIndices[1] < 0 or pointIndices[2] < 0 or
        pointIndices[0] >= editor.uvState.points.len or
        pointIndices[1] >= editor.uvState.points.len or
        pointIndices[2] >= editor.uvState.points.len:
      continue
    editor.editWorld.setTriangleUvs(
      triangle,
      [
        vec2(
          editor.uvState.points[pointIndices[0]].x.float32,
          editor.uvState.points[pointIndices[0]].y.float32,
        ),
        vec2(
          editor.uvState.points[pointIndices[1]].x.float32,
          editor.uvState.points[pointIndices[1]].y.float32,
        ),
        vec2(
          editor.uvState.points[pointIndices[2]].x.float32,
          editor.uvState.points[pointIndices[2]].y.float32,
        ),
      ],
    )

proc updateUvKeyboard*(inputs: InputMap, dt: float64) =
  if not inputs.down(GameMeshKeyboardMove) or
      editor.uvState.selectedPoints.len == 0:
    return
  var delta = Mesh2DPoint()
  if inputs.down(GameCameraForward):
    delta.y -= 1'f64
  if inputs.down(GameCameraBackward):
    delta.y += 1'f64
  if inputs.down(GameCameraRight):
    delta.x += 1'f64
  if inputs.down(GameCameraLeft):
    delta.x -= 1'f64
  if abs(delta.x) <= 0.000001 and abs(delta.y) <= 0.000001:
    return
  let distance = 1.5'f64 * min(dt, 1'f64 / 60'f64)
  let directionLength = hypot(delta.x, delta.y)
  delta.x = delta.x / directionLength * distance
  delta.y = delta.y / directionLength * distance
  for point in editor.uvState.selectedPoints:
    if point >= 0 and point < editor.uvState.points.len:
      editor.uvState.points[point].x += delta.x
      editor.uvState.points[point].y += delta.y
  applyUvState()

proc uvMappingPanelImpl(gui: var UI, io: IO) =
  syncUvState()
  gui.panel(
    gui.id("uv panel"),
    cfg(
      width = fixed(360),
      height = fill(),
      gap = 0,
      padding = 0,
      style = ComponentStyle(hasBackground: true, background: color(28, 32,
          34, 190)),
    ),
  ):
    gui.panelHeader("uv panel", "UV Mapping")
    gui.column(
      gui.id("uv panel body"),
      cfg(width = fill(), height = fill(), gap = 10, padding = 10,
          scrollY = true),
    ):
      if gui.button(gui.id("uv select all"), "Select All", fill(), fixed(30)):
        selectAllUvPoints()
        gui.markAllDirty()
      if editor.uvTriangles.len == 0:
        gui.label(gui.id("uv empty"), "Select triangles to edit UVs", fill(),
            fixed(28))
      else:
        if editor.editWorld.selectedMeshKind != TerrainWorldMesh:
          let materialIndex = ensureUvTextureMaterial()
          for triangle in editor.uvTriangles:
            editor.editWorld.setTriangleMaterial(triangle, materialIndex)
        gui.metricRow("uv selected count", "Triangles", $editor.uvTriangles.len)
        if gui.textureAtlasPicker("uv texture", UvTextureAtlasTarget,
            texturePreviewPath(editor.uvTexturePath), editor.uvTextureIndex):
          gui.markAllDirty()
        gui.row(
          gui.id("uv tools row"),
          cfg(width = fill(), height = fit(), gap = 6, padding = 0),
        ):
          if gui.button(gui.id("uv rotate"), "Rotate", fill(), fixed(30)):
            rotateUvIsland()
            gui.markAllDirty()
        if editor.uvTriangles.len == 2:
          gui.row(
            gui.id("uv rectangle tools row"),
            cfg(width = fill(), height = fit(), gap = 6, padding = 0),
          ):
            if gui.button(
              gui.id("uv map rectangle"), "Map Rectangle", fill(), fixed(30)
            ):
              if mapSelectedPairToRectangle():
                gui.markAllDirty()
            if gui.button(gui.id("uv try winding"), "Try Winding", fill(),
                fixed(30)):
              if tryRectangleWinding():
                gui.markAllDirty()
        let uvEditorId = gui.id("uv mesh editor")
        gui.label(
          gui.id("uv navigation help"),
          "Wheel: zoom  •  Middle drag: pan  •  Alt drag: 8 px snap",
          fill(),
          fixed(22),
        )
        if gui.inEventPhase() and not editor.meshEditor.input.mouseLeftDown:
          editor.uvMultiSelectBase = editor.uvState.selectedPoints
        let uvChanged = gui.mesh2d(
          uvEditorId,
          editor.uvState,
          texturePreviewPath(editor.uvTexturePath),
          fill(),
          fixed(320),
        )
        if uvChanged:
          applyUvState()
        if gui.inEventPhase() and editor.meshEditor.input.multiSelect and
            editor.meshEditor.input.mouseLeftPressed:
          let frame = gui.widgetFrame(uvEditorId)
          editor.uvState.selectedPoints = editor.uvMultiSelectBase
          if frame.ok:
            let point = editor.uvState.pickUvPoint(
              frame.frame, editor.meshEditor.input.mouseX,
              editor.meshEditor.input.mouseY
            )
            if point >= 0:
              editor.uvState.selectedPoints.incl point
              editor.uvMultiSelectBase = editor.uvState.selectedPoints
          editor.uvState.dragKind = Mesh2DNoDrag
          gui.markAllDirty()
        discard uvChanged

widget uvMappingPanel*(io: IO):
  uvMappingPanelImpl(ui, io)
