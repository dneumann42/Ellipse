import std/[os]
import ellipse
import ellipse/rendering/cameras
import vmath

import ellipse/worlds/worlds
import ellipse/worlds/registry
import ellipse/editing/worldMeshEditing
import ellipse/editing/inputs
import ellipse/editing/editors/[state, persistence, fps, menus, dialogs, panels, rendering, uv,
  uihelpers]
import ellipse/editing/editors/panels/renderTargets

const WaterMaterialID = "editor water material"
const WaterTexturePath = "res/textures/water.png"

proc updatePlacementCursor(ray: EditorRay) =
  let terrain = editor.editWorld.terrainRaycast(ray)
  if terrain.hit:
    editor.placementCursorActive = true
    editor.placementCursorPosition = terrain.point
    return

  if editor.editWorld.meshCount > 0:
    let triangle = editor.editWorld.pickTriangle(ray)
    if triangle.kind == Triangle:
      editor.placementCursorActive = true
      editor.placementCursorPosition = snapToWorldGrid(
        ray.origin + ray.direction * triangle.rayT
      )
      return

  let plane = ray.terrainPoint()
  if plane.hit:
    editor.placementCursorActive = true
    editor.placementCursorPosition = snapToWorldGrid(plane.point)
  else:
    editor.placementCursorActive = false

proc modelGizmoAxis(handle: ModelGizmoHandle): Vec3 =
  case handle
  of ModelGizmoX:
    vec3(1, 0, 0)
  of ModelGizmoY:
    vec3(0, 1, 0)
  of ModelGizmoZ:
    vec3(0, 0, 1)
  of NoModelGizmoHandle, ModelGizmoCenter:
    vec3(0, 0, 0)

proc rayAxisParam(ray: EditorRay, origin, axis: Vec3): float32 =
  let
    u = ray.direction
    v = axis
    w = ray.origin - origin
    aa = dot(u, u)
    bb = dot(u, v)
    cc = dot(v, v)
    dd = dot(u, w)
    ee = dot(v, w)
    denom = aa * cc - bb * bb
  if abs(denom) < 0.000001'f32:
    return 0
  (aa * ee - bb * dd) / denom

proc pickModelGizmoHandle(ray: EditorRay, camera: cameras.Camera,
    viewportHeight: int, instance: WorldModelInstance): ModelGizmoHandle =
  let
    center = instance.position
    length = pixelsToWorldRadius(center, camera, viewportHeight, 78'f32)
    axisRadius = pixelsToWorldRadius(center, camera, viewportHeight, 10'f32)
    centerRadius = pixelsToWorldRadius(center, camera, viewportHeight, 14'f32)
    centerHit = distanceRayPoint(ray, center)
  if centerHit.distance <= centerRadius:
    return ModelGizmoCenter
  var best = (handle: NoModelGizmoHandle, score: float32.high,
      rayT: float32.high)
  for handle in [ModelGizmoX, ModelGizmoY, ModelGizmoZ]:
    let axis = modelGizmoAxis(handle)
    let hit = distanceRaySegment(ray, center, center + axis * length)
    if hit.distance <= axisRadius:
      let score = hit.distance / axisRadius
      if score < best.score or (score == best.score and hit.rayT < best.rayT):
        best = (handle, score, hit.rayT)
  best.handle

proc beginModelGizmoDrag(ray: EditorRay, instance: WorldModelInstance) =
  editor.modelGizmoDragging = true
  editor.modelGizmoDragHandle = editor.modelGizmoHover
  editor.modelGizmoDragStartMouseX = editor.meshEditor.input.mouseX
  editor.modelGizmoDragStartMouseY = editor.meshEditor.input.mouseY
  editor.modelGizmoDragStart = instance
  let axis = modelGizmoAxis(editor.modelGizmoDragHandle)
  editor.modelGizmoDragStartParam =
    if length(axis) > 0.000001'f32:
      rayAxisParam(ray, instance.position, axis)
    else:
      0
  editor.meshEditor.dragging = false

proc updateModelGizmoDrag(ray: EditorRay) =
  let index = editor.editWorld.selectedModel
  if index < 0 or index >= editor.editWorld.modelCount:
    editor.modelGizmoDragging = false
    return
  var instance = editor.modelGizmoDragStart
  let
    handle = editor.modelGizmoDragHandle
    mouseDx = (
      editor.meshEditor.input.mouseX - editor.modelGizmoDragStartMouseX
    ).float32
    mouseDy = (
      editor.meshEditor.input.mouseY - editor.modelGizmoDragStartMouseY
    ).float32
  case editor.modelGizmoMode
  of ModelGizmoMove:
    if handle in [ModelGizmoX, ModelGizmoY, ModelGizmoZ]:
      let
        axis = modelGizmoAxis(handle)
        delta = rayAxisParam(ray, editor.modelGizmoDragStart.position, axis) -
          editor.modelGizmoDragStartParam
      instance.position = editor.modelGizmoDragStart.position + axis * delta
  of ModelGizmoRotate:
    let deltaDegrees = (mouseDx - mouseDy) * 0.35'f32
    case handle
    of ModelGizmoX:
      instance.rotation.x = editor.modelGizmoDragStart.rotation.x + deltaDegrees
    of ModelGizmoY:
      instance.rotation.y = editor.modelGizmoDragStart.rotation.y + deltaDegrees
    of ModelGizmoZ:
      instance.rotation.z = editor.modelGizmoDragStart.rotation.z + deltaDegrees
    of NoModelGizmoHandle, ModelGizmoCenter:
      discard
  of ModelGizmoScale:
    if handle in [ModelGizmoX, ModelGizmoY, ModelGizmoZ]:
      let factor = max(0.01'f32, 1'f32 + (mouseDx - mouseDy) * 0.01'f32)
      case handle
      of ModelGizmoX:
        instance.scale.x = max(0.01'f32, editor.modelGizmoDragStart.scale.x * factor)
      of ModelGizmoY:
        instance.scale.y = max(0.01'f32, editor.modelGizmoDragStart.scale.y * factor)
      of ModelGizmoZ:
        instance.scale.z = max(0.01'f32, editor.modelGizmoDragStart.scale.z * factor)
      of NoModelGizmoHandle, ModelGizmoCenter:
        discard
  of ModelGizmoScaleAll:
    let factor = max(0.01'f32, 1'f32 + (mouseDx - mouseDy) * 0.01'f32)
    instance.scale.x = max(0.01'f32, editor.modelGizmoDragStart.scale.x * factor)
    instance.scale.y = max(0.01'f32, editor.modelGizmoDragStart.scale.y * factor)
    instance.scale.z = max(0.01'f32, editor.modelGizmoDragStart.scale.z * factor)
  editor.editWorld.setModel(index, instance)

proc beginSpawnGizmoDrag(ray: EditorRay, spawn: WorldEntitySpawn) =
  editor.spawnGizmoDragging = true
  editor.spawnGizmoDragHandle = editor.spawnGizmoHover
  editor.spawnGizmoDragStart = spawn
  let axis = modelGizmoAxis(editor.spawnGizmoDragHandle)
  editor.spawnGizmoDragStartParam = if length(axis) > 0.000001'f32:
    rayAxisParam(ray, spawn.position, axis) else: 0
  editor.meshEditor.dragging = false

proc updateSpawnGizmoDrag(ray: EditorRay) =
  let index = editor.editWorld.selectedEntitySpawn
  if index < 0 or index >= editor.editWorld.entitySpawnCount:
    editor.spawnGizmoDragging = false
    return
  var spawn = editor.spawnGizmoDragStart
  let axis = modelGizmoAxis(editor.spawnGizmoDragHandle)
  if length(axis) > 0.000001'f32:
    let delta = rayAxisParam(ray, editor.spawnGizmoDragStart.position, axis) -
      editor.spawnGizmoDragStartParam
    spawn.position = editor.spawnGizmoDragStart.position + axis * delta
    editor.editWorld.setEntitySpawn(index, spawn)

proc sourceWorldPtr(worldRegistry: var WorldsRegistry,
    worldID: WorldID): ptr World =
  if worldID == editor.editWorldID:
    addr editor.editWorld
  else:
    worldRegistry.getPtr(worldID)

proc load*(worldRegistry: var WorldsRegistry) =
  if worldRegistry.readEditorState():
    discard
  if getEnv("IOC_OPEN_FPS_DIALOG") in ["1", "true", "TRUE", "yes", "YES"]:
    editor.showFpsDialog = true

proc preReload*(worldRegistry: var WorldsRegistry) =
  discard worldRegistry
  writeEditorWorldState()
  writeEditorState()

proc afterReload*(worldRegistry: var WorldsRegistry) =
  if not worldRegistry.readEditorState():
    if worldRegistry.contains("Beans"):
      worldRegistry.openWorld(editor, "Beans")

proc update*(
    artist: var Artist3D,
    inputs: var InputMap,
    dt: float64,
    pluginControls: PluginControls,
    worldRegistry: var WorldsRegistry,
) =
  recordFrameTime(dt)
  updateFpsWidget(pluginControls)
  if inputs.pressed(GameToggleTextureFiltering):
    artist.textureFiltering = not artist.textureFiltering
  editor.meshEditor.terrainTabActive =
    MeshPanelTab(editor.meshPanelTab) == TerrainTab
  editor.meshEditor.update(editor.editWorld, artist, inputs, dt)
  let ray = rayFromScreen(
    editor.meshEditor.input.mouseX,
    editor.meshEditor.input.mouseY,
    editor.meshEditor.input.viewportWidth,
    editor.meshEditor.input.viewportHeight,
    artist.activeCamera,
  )
  if editor.meshEditor.input.mouseMiddlePressed:
    updatePlacementCursor(ray)
  if MeshPanelTab(editor.meshPanelTab) == SpawnsTab:
    if editor.spawnGizmoDragging:
      if editor.meshEditor.input.mouseLeftDown:
        updateSpawnGizmoDrag(ray)
      else:
        editor.spawnGizmoDragging = false
        editor.spawnGizmoDragHandle = NoModelGizmoHandle
    elif editor.editWorld.selectedEntitySpawn >= 0 and
        editor.editWorld.selectedEntitySpawn < editor.editWorld.entitySpawnCount:
      let spawn = editor.editWorld.entitySpawn(editor.editWorld.selectedEntitySpawn)
      editor.spawnGizmoHover = pickModelGizmoHandle(ray, artist.activeCamera,
          editor.meshEditor.input.viewportHeight,
          WorldModelInstance(position: spawn.position))
      if editor.meshEditor.input.mouseLeftPressed and
          editor.spawnGizmoHover != NoModelGizmoHandle:
        beginSpawnGizmoDrag(ray, spawn)
    else:
      editor.spawnGizmoHover = NoModelGizmoHandle
    if not editor.spawnGizmoDragging and
        editor.spawnGizmoHover == NoModelGizmoHandle and
        editor.meshEditor.input.mouseLeftPressed:
      var best = (index: -1, distance: float32.high)
      for index, spawn in editor.editWorld.entitySpawns:
        let hit = distanceRayPoint(ray, spawn.position)
        if hit.rayT >= 0 and hit.distance <= 0.75'f32 and hit.rayT < best.distance:
          best = (index, hit.rayT)
      if best.index >= 0:
        editor.editWorld.selectedEntitySpawn = best.index
    if inputs.pressed(GameModelDelete):
      editor.editWorld.deleteEntitySpawn(editor.editWorld.selectedEntitySpawn)
  elif editor.modelGizmoDragging:
    if editor.meshEditor.input.mouseLeftDown:
      updateModelGizmoDrag(ray)
    else:
      editor.modelGizmoDragging = false
      editor.modelGizmoDragHandle = NoModelGizmoHandle
  elif editor.editWorld.selectedModel >= 0 and
      editor.editWorld.selectedModel < editor.editWorld.modelCount:
    let selectedInstance = editor.editWorld.model(
        editor.editWorld.selectedModel)
    editor.modelGizmoHover = pickModelGizmoHandle(
      ray, artist.activeCamera, editor.meshEditor.input.viewportHeight,
      selectedInstance,
    )
    if editor.meshEditor.input.mouseLeftPressed and
        editor.modelGizmoHover != NoModelGizmoHandle:
      beginModelGizmoDrag(ray, selectedInstance)
  else:
    editor.modelGizmoHover = NoModelGizmoHandle

  if (
    not editor.modelGizmoDragging and
    editor.modelGizmoHover == NoModelGizmoHandle and
    MeshPanelTab(editor.meshPanelTab) == ModelsTab and
    editor.meshEditor.input.mouseLeftPressed
  ):
    var best = (index: -1, distance: float32.high)
    for index, instance in editor.editWorld.models:
      let sourceWorld = sourceWorldPtr(worldRegistry, instance.sourceWorld)
      if sourceWorld.isNil:
        continue
      for sourceMesh in sourceWorld[].meshes:
        if sourceMesh.name != instance.sourceMesh or
            sourceMesh.vertices.len == 0: continue
        var radius = 0'f32
        for vertex in sourceMesh.vertices:
          radius = max(radius, length(vertex.position) * max(instance.scale.x,
            max(instance.scale.y, instance.scale.z)))
        let hit = distanceRayPoint(ray, instance.position)
        if hit.rayT >= 0 and hit.distance <= max(radius, 0.15'f32) and
            hit.rayT < best.distance:
          best = (index, hit.rayT)
    if best.index >= 0:
      editor.editWorld.selectedModel = best.index
  if MeshPanelTab(editor.meshPanelTab) == ModelsTab and
      inputs.pressed(GameModelDelete):
    editor.editWorld.deleteModel(editor.editWorld.selectedModel)
  updateUvKeyboard(inputs, dt)

widget editorShell*(
  io: IO,
  pluginControls: PluginControls,
  sceneStack: var SceneStack,
  running: var bool,
  worldRegistry: var WorldsRegistry,
):
  editor.cachedSourceWorldIDs.setLen(0)
  for worldID in worldRegistry.worldIDs:
    editor.cachedSourceWorldIDs.add(worldID)
  if editor.editWorldID notin editor.cachedSourceWorldIDs:
    editor.cachedSourceWorldIDs.add(editor.editWorldID)
  ui.layout:
    ui.editorMenuBar(io, pluginControls, sceneStack, running, worldRegistry)
    ui.editorPanels(io)
    if ui.newWorldDialog(editor.newWorldDialog):
      worldRegistry.createWorld(editor, editor.newWorldDialog)
    if ui.saveWorldDialog(editor.saveWorldDialog):
      worldRegistry.saveWorldAs(editor, editor.saveWorldDialog)
    ui.editorOpenWorldDialog(worldRegistry)
    discard ui.modelPickerDialog(editor.modelPickerDialog, worldRegistry)
    if ui.confirmationDialog(editor.confirmationDialog):
      editor.applyConfirmation(editor.confirmationDialog)
    ui.pluginBuildOutputDialog(pluginControls)
    ui.fpsDialog()
    ui.textureAtlasDialog()

proc ui*(
  gui: var UI,
  io: IO,
  pluginControls: PluginControls,
  sceneStack: var SceneStack,
  running: var bool,
  worldRegistry: var WorldsRegistry
) =
  gui.editorShell(io, pluginControls, sceneStack, running, worldRegistry)

proc postUi*(gui: var UI, pluginControls: PluginControls) =
  updateFpsWidget(pluginControls)
  if editor.showFpsDialog:
    let chartFrame = gui.widgetFrame(gui.id("fps chart"))
    if chartFrame.ok:
      drawFpsChart(
        chartFrame.frame, gui.palette.textColor, gui.font("font"),
        drawLabels = false,
      )

proc sourceMeshCacheKey(worldRegistry: var WorldsRegistry): string =
  for sourceWorldID in editor.cachedSourceWorldIDs:
    let sourceWorld = sourceWorldPtr(worldRegistry, sourceWorldID)
    if sourceWorld.isNil:
      continue
    result.add sourceWorldID
    result.add ":"
    result.add $sourceWorld[].revision
    result.add ";"

proc syncSourceRenderMeshes(
    artist: var Artist3D, resources: var ResourceManager,
    worldRegistry: var WorldsRegistry,
) =
  let cacheKey = sourceMeshCacheKey(worldRegistry)
  if editor.cachedSourceMeshKey != cacheKey:
    editor.cachedSourceMeshKey = cacheKey
    editor.cachedSourceRenderMeshes.setLen(0)
    for sourceWorldID in editor.cachedSourceWorldIDs:
      let sourceWorld = sourceWorldPtr(worldRegistry, sourceWorldID)
      if sourceWorld.isNil:
        continue
      for sourceMesh in sourceWorld[].meshes:
        if sourceMesh.kind != OtherWorldMesh:
          continue
        var source = World.init("source")
        var localMesh = sourceMesh
        # A model instance owns its transform; a layout position in Models
        # must never leak into worlds (such as Oberman) that instance it.
        localMesh.position = vec3(0, 0, 0)
        discard source.addMesh(localMesh)
        for i, renderMesh in source.renderMeshes:
          let meshID = "source mesh " & sourceWorld[].name & ":" &
            sourceMesh.name & ":" & $i
          artist.setMesh(meshID, renderMesh.vertices, renderMesh.indices)
          editor.cachedSourceRenderMeshes.add EditorSourceRenderMesh(
            sourceWorld: sourceWorld[].name,
            sourceMesh: sourceMesh.name,
            meshID: meshID,
            materialID: renderMesh.materialID,
          )
  for sourceWorldID in editor.cachedSourceWorldIDs:
    let sourceWorld = sourceWorldPtr(worldRegistry, sourceWorldID)
    if sourceWorld.isNil:
      continue
    for sourceMesh in sourceWorld[].meshes:
      if sourceMesh.kind != OtherWorldMesh:
        continue
      for material in sourceMesh.materials:
        var texture: TextureResourceHandle = nil
        if material.useTexture and material.texturePath.len > 0:
          let id = resourceId(material.texturePath)
          if not resources.contains(id):
            discard resources.addTexture(id, material.texturePath)
          texture = resources.get(id, TextureResourceHandle)
        artist.setMaterial(Material(id: material.id, texture: texture,
          baseColor: material.baseColor, useTexture: material.useTexture,
          textureSampling: Single, atlasColumns: TerrainAtlasColumns,
          atlasRows: TerrainAtlasRows,
          specularStrength: material.specularStrength))

proc draw*(artist: var Artist3D,
    resources: var ResourceManager, worldRegistry: var WorldsRegistry,
    canvas: var Canvas) =
  editor.meshEditor.syncViewport(canvas.width, canvas.height)
  if editor.cachedWorldRevision != editor.editWorld.revision:
    editor.cachedWorldMeshes = editor.editWorld.renderMeshes()
    editor.cachedWorldRenderMeshes.setLen(0)
    for i, mesh in editor.cachedWorldMeshes:
      let meshID = "world mesh " & $i
      artist.setMesh(meshID, mesh.vertices, mesh.indices)
      editor.cachedWorldRenderMeshes.add EditorWorldRenderMesh(
        meshID: meshID,
        materialID: mesh.materialID,
      )
    editor.cachedWorldRevision = editor.editWorld.revision
  for mesh in editor.editWorld.meshes:
    for material in mesh.materials:
      let texture =
        if material.useTexture and material.texturePath.len > 0:
          let id = resourceId(material.texturePath)
          if not resources.contains(id):
            discard resources.addTexture(id, material.texturePath)
          resources.get(id, TextureResourceHandle)
        else:
          nil
      artist.setMaterial(
        Material(
          id: material.id,
          texture: texture,
          baseColor: material.baseColor,
          useTexture: material.useTexture,
          textureSampling: (if mesh.kind ==
              TerrainWorldMesh: Splat else: Single),
          atlasColumns: TerrainAtlasColumns,
          atlasRows: TerrainAtlasRows,
          specularStrength: (if mesh.kind == TerrainWorldMesh:
          material.specularStrength else: DefaultSpecularStrength),
        )
      )
  syncSourceRenderMeshes(artist, resources, worldRegistry)
  syncOverlayMesh(artist)
  if editor.editWorld.entitySpawnCount > 0 or
      (editor.placementCursorActive and MeshPanelTab(editor.meshPanelTab) == SpawnsTab):
    var spawnWorld = World.init("entity spawn marker")
    discard spawnWorld.createCubeWorldMesh("marker", 1'f32)
    let spawnMeshes = spawnWorld.renderMeshes()
    if spawnMeshes.len > 0:
      artist.setMesh(EditorEntitySpawnMeshID, spawnMeshes[0].vertices,
          spawnMeshes[0].indices)
  if editor.placementCursorActive:
    let cursorMesh = placementCursorMesh(
      editor.placementCursorPosition, artist.activeCamera,
      editor.meshEditor.input.viewportHeight,
    )
    artist.setMesh(
      EditorPlacementCursorMeshID, cursorMesh.vertices, cursorMesh.indices
    )
    if MeshPanelTab(editor.meshPanelTab) == WorldMeshesTab:
      var previewWorld = World.init("editor placement preview")
      discard previewWorld.createCubeWorldMesh("Preview", 2'f32)
      previewWorld.translateMesh(0, editor.placementCursorPosition)
      let previewMeshes = previewWorld.renderMeshes()
      if previewMeshes.len > 0:
        artist.setMesh(
          EditorPlacementPreviewMeshID,
          previewMeshes[0].vertices,
          previewMeshes[0].indices,
        )
  if editor.editWorld.selectedModel >= 0 and
      editor.editWorld.selectedModel < editor.editWorld.modelCount:
    let instance = editor.editWorld.model(editor.editWorld.selectedModel)
    let gizmo = modelGizmoMeshes(
      instance.position, artist.activeCamera,
      editor.meshEditor.input.viewportHeight
    )
    artist.setMesh(ModelGizmoXMeshID, gizmo.x.vertices, gizmo.x.indices)
    artist.setMesh(ModelGizmoYMeshID, gizmo.y.vertices, gizmo.y.indices)
    artist.setMesh(ModelGizmoZMeshID, gizmo.z.vertices, gizmo.z.indices)
    artist.setMesh(
      ModelGizmoCenterMeshID, gizmo.center.vertices, gizmo.center.indices
    )
  if MeshPanelTab(editor.meshPanelTab) == SpawnsTab and
      editor.editWorld.selectedEntitySpawn >= 0 and
      editor.editWorld.selectedEntitySpawn < editor.editWorld.entitySpawnCount:
    let spawn = editor.editWorld.entitySpawn(editor.editWorld.selectedEntitySpawn)
    let gizmo = modelGizmoMeshes(spawn.position, artist.activeCamera,
        editor.meshEditor.input.viewportHeight)
    artist.setMesh(ModelGizmoXMeshID, gizmo.x.vertices, gizmo.x.indices)
    artist.setMesh(ModelGizmoYMeshID, gizmo.y.vertices, gizmo.y.indices)
    artist.setMesh(ModelGizmoZMeshID, gizmo.z.vertices, gizmo.z.indices)
    artist.setMesh(ModelGizmoCenterMeshID, gizmo.center.vertices, gizmo.center.indices)
  if editor.editWorld.waterPlaneCount > 0 and not editor.cachedWaterMeshReady:
    let waterMesh = createPlaneMesh(subdivisions = 96)
    artist.setMesh(WaterMeshID, waterMesh.vertices, waterMesh.indices)
    editor.cachedWaterMeshReady = true
  var models: seq[Model] = @[]
  let activeEnvironment = editor.editWorld.activeEnvironment(
    artist.activeCamera.position
  )
  let fog = activeEnvironment.fogRenderOptions()
  var skyboxTexture: TextureResourceHandle = nil
  if activeEnvironment.useSkybox and activeEnvironment.skyboxPath.len > 0:
    let id = resourceId(activeEnvironment.skyboxPath)
    if not resources.contains(id):
      discard resources.addTexture(id, activeEnvironment.skyboxPath)
    skyboxTexture = resources.get(id, TextureResourceHandle)
  let sky = activeEnvironment.skyRenderOptions(skyboxTexture)
  if editor.showSolidMesh:
    for mesh in editor.cachedWorldRenderMeshes:
      models.add Model.init(
        mesh.meshID,
        renderOptions = RenderOptions.init(materialID = mesh.materialID,
            fog = fog),
      )
  if editor.showWireframeMesh:
    for mesh in editor.cachedWorldRenderMeshes:
      models.add Model.init(
        mesh.meshID,
        renderOptions = RenderOptions.init(
          mode = WireframeMesh,
          depthWrite = not editor.showSolidMesh,
          baseColor = vec3(0.02'f32, 0.025'f32, 0.03'f32),
          fog = fog,
        ),
      )
  for modelIndex, instance in editor.editWorld.models:
    for renderMesh in editor.cachedSourceRenderMeshes:
      if renderMesh.sourceWorld != instance.sourceWorld or
          renderMesh.sourceMesh != instance.sourceMesh:
        continue
      models.add Model.init(renderMesh.meshID,
          transform = instance.modelTransform(), renderOptions = RenderOptions.init(
            materialID = renderMesh.materialID,
            fog = fog, baseColor = (if modelIndex ==
                editor.editWorld.selectedModel:
        vec3(1.15'f32, 0.85'f32, 0.65'f32) else: vec3(1, 1, 1))))
  for index, spawn in editor.editWorld.entitySpawns:
    models.add Model.init(EditorEntitySpawnMeshID,
        transform = translate(spawn.position + vec3(0, 0.5'f32, 0)),
        renderOptions = RenderOptions.init(
          mode = WireframeMesh,
          depthTest = false,
          depthWrite = false,
          baseColor = if index == editor.editWorld.selectedEntitySpawn:
            vec3(1.0'f32, 0.8'f32, 0.2'f32) else: vec3(0.75'f32, 0.3'f32, 1.0'f32),
        ))
  if editor.cachedOverlayVertices.len > 0:
    models.add Model.init(EditorOverlayMeshID)
  if editor.placementCursorActive:
    models.add Model.init(
      EditorPlacementCursorMeshID,
      renderOptions = RenderOptions.init(depthTest = false,
          baseColor = vec3(0.2'f32, 1.0'f32, 0.95'f32)),
    )
    if MeshPanelTab(editor.meshPanelTab) == WorldMeshesTab:
      models.add Model.init(
        EditorPlacementPreviewMeshID,
        renderOptions = RenderOptions.init(
          mode = WireframeMesh,
          depthTest = false,
          depthWrite = false,
          baseColor = vec3(0.2'f32, 1.0'f32, 0.95'f32),
        ),
      )
    elif MeshPanelTab(editor.meshPanelTab) == ModelsTab and
        editor.editWorld.selectedModel >= 0 and
        editor.editWorld.selectedModel < editor.editWorld.modelCount:
      var previewInstance = editor.editWorld.model(
          editor.editWorld.selectedModel)
      previewInstance.position = editor.placementCursorPosition
      for renderMesh in editor.cachedSourceRenderMeshes:
        if renderMesh.sourceWorld != previewInstance.sourceWorld or
            renderMesh.sourceMesh != previewInstance.sourceMesh:
          continue
        models.add Model.init(
          renderMesh.meshID,
          transform = previewInstance.modelTransform(),
          renderOptions = RenderOptions.init(
            mode = WireframeMesh,
            depthTest = false,
            depthWrite = false,
            baseColor = vec3(0.2'f32, 1.0'f32, 0.95'f32),
          ),
        )
    elif MeshPanelTab(editor.meshPanelTab) == SpawnsTab:
      models.add Model.init(EditorEntitySpawnMeshID,
          transform = translate(editor.placementCursorPosition + vec3(0, 0.5'f32, 0)),
          renderOptions = RenderOptions.init(mode = WireframeMesh,
              depthTest = false, depthWrite = false,
              baseColor = vec3(0.2'f32, 1.0'f32, 0.95'f32)))
  if (editor.editWorld.selectedModel >= 0 and
      editor.editWorld.selectedModel < editor.editWorld.modelCount) or
      (MeshPanelTab(editor.meshPanelTab) == SpawnsTab and
      editor.editWorld.selectedEntitySpawn >= 0 and
      editor.editWorld.selectedEntitySpawn < editor.editWorld.entitySpawnCount):
    models.add Model.init(
      ModelGizmoXMeshID,
      renderOptions = RenderOptions.init(depthTest = false,
          baseColor = vec3(0.95'f32, 0.18'f32, 0.16'f32)),
    )
    models.add Model.init(
      ModelGizmoYMeshID,
      renderOptions = RenderOptions.init(depthTest = false,
          baseColor = vec3(0.24'f32, 0.82'f32, 0.32'f32)),
    )
    models.add Model.init(
      ModelGizmoZMeshID,
      renderOptions = RenderOptions.init(depthTest = false,
          baseColor = vec3(0.22'f32, 0.48'f32, 1.0'f32)),
    )
    models.add Model.init(
      ModelGizmoCenterMeshID,
      renderOptions = RenderOptions.init(depthTest = false,
          baseColor = vec3(1.0'f32, 0.86'f32, 0.2'f32)),
    )
  models.add Model.init(
    CameraWidgetRightMeshID,
    renderOptions = RenderOptions.init(baseColor = vec3(0.95'f32, 0.18'f32,
        0.16'f32)),
  )
  models.add Model.init(
    CameraWidgetUpMeshID,
    renderOptions = RenderOptions.init(baseColor = vec3(0.24'f32, 0.82'f32,
        0.32'f32)),
  )
  models.add Model.init(
    CameraWidgetForwardMeshID,
    renderOptions = RenderOptions.init(baseColor = vec3(0.22'f32, 0.48'f32,
        1.0'f32)),
  )
  if editor.showWater:
    let waterTexturePath = texturePreviewPath(WaterTexturePath)
    let waterTextureID = resourceId(waterTexturePath)
    if not resources.contains(waterTextureID):
      discard resources.addTexture(waterTextureID, waterTexturePath)
    artist.setMaterial(Material(
      id: WaterMaterialID,
      texture: resources.get(waterTextureID, TextureResourceHandle),
      baseColor: vec3(1, 1, 1),
      useTexture: true,
      textureSampling: Single,
      specularStrength: DefaultSpecularStrength,
    ))
    for water in editor.editWorld.waterPlanes:
      var waterOptions = water.waterRenderOptions(editor.fpsClock)
      waterOptions.fog = fog
      waterOptions.materialID = WaterMaterialID
      models.add Model.init(
        WaterMeshID,
        transform = water.waterTransform(),
        renderOptions = waterOptions,
      )
  artist.render(models, sky = sky, canvas = addr canvas)
  artist.registerRenderTargetImages()
  # Nest normally caches the editor chrome. The target inspector is a live GPU
  # view, so request a fresh UI composite while it is visible.
  if editor.showRenderTargetsPanel:
    requestNestEveryFrame()
