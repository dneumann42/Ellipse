import ellipse
import ellipse/rendering/cameras as renderingCameras
import vmath
import ellipse/worlds/worlds
import ellipse/editing/worldMeshEditing

import state, uv

proc addVec3Key*(key: var string, value: Vec3) =
  key.add $value.x
  key.add ","
  key.add $value.y
  key.add ","
  key.add $value.z

proc addQuatKey*(key: var string, value: Quat) =
  key.add $value.x
  key.add ","
  key.add $value.y
  key.add ","
  key.add $value.z
  key.add ","
  key.add $value.w

proc overlayCacheKey*(camera: renderingCameras.Camera): string =
  result.add $editor.editWorld.revision
  result.add "|"
  result.add $editor.meshEditor.terrainCursorCellX
  result.add ","
  result.add $editor.meshEditor.terrainCursorCellZ
  result.add "|"
  result.add $editor.meshEditor.input.viewportWidth
  result.add "x"
  result.add $editor.meshEditor.input.viewportHeight
  result.add "|"
  result.add $editor.meshEditor.selectedVertex
  result.add "|"
  for vertex in editor.meshEditor.selectedVertexList():
    result.add $vertex
    result.add ","
  result.add "|"
  result.add $editor.meshEditor.hovered.kind
  result.add ":"
  result.add $editor.meshEditor.hovered.vertex
  result.add ":"
  result.add $editor.meshEditor.hovered.triangle
  result.add ":"
  result.add $editor.meshEditor.hovered.edgeA
  result.add ":"
  result.add $editor.meshEditor.hovered.edgeB
  result.add "|"
  for triangle in selectedTriangleList():
    result.add $triangle
    result.add ","
  result.add "|"
  result.addVec3Key(camera.position)
  result.add "|"
  result.addQuatKey(camera.orientation)

proc syncOverlayMesh*(artist: Artist3D) =
  editor.meshEditor.terrainCursorCellX = editor.terrainPanel.cellX
  editor.meshEditor.terrainCursorCellZ = editor.terrainPanel.cellZ

  # The orientation widget follows the active camera even while camera input
  # is active, when the editable overlay is intentionally left untouched.
  let cameraWidget = cameraOrientationWidgetMeshes(artist.activeCamera)
  artist.setMesh(
    CameraWidgetUpMeshID, cameraWidget.up.vertices, cameraWidget.up.indices
  )
  artist.setMesh(
    CameraWidgetRightMeshID, cameraWidget.right.vertices,
    cameraWidget.right.indices
  )
  artist.setMesh(
    CameraWidgetForwardMeshID,
    cameraWidget.forward.vertices,
    cameraWidget.forward.indices,
  )
  if editor.meshEditor.cameraInputActive:
    return

  let key = overlayCacheKey(artist.activeCamera)
  if editor.cachedOverlayKey == key:
    return
  let marker = editor.editWorld.overlayMesh(editor.meshEditor,
      artist.activeCamera)
  editor.cachedOverlayKey = key
  editor.cachedOverlayVertices = marker.vertices
  editor.cachedOverlayIndices = marker.indices
  if editor.cachedOverlayVertices.len > 0:
    artist.setMesh(
      EditorOverlayMeshID, editor.cachedOverlayVertices,
      editor.cachedOverlayIndices
    )

proc waterTransform*(water: WorldWaterPlane): Mat4 =
  translate(water.position) * scale(vec3(water.size.x, 1'f32, water.size.y))

proc waterRenderOptions*(water: WorldWaterPlane, time: float64): RenderOptions =
  result = RenderOptions.init()
  result.effect = WaterEffect
  result.depthWrite = false
  result.water = WaterRenderOptions.init(
    time = time.float32,
    waveAmplitude = water.waveAmplitude,
    waveLength = water.waveLength,
    waveSpeed = water.waveSpeed,
    surfaceColor = water.surfaceColor,
    deepColor = water.deepColor,
    opacity = water.opacity,
    specularStrength = water.specularStrength,
  )
