import std/[algorithm, json, os, sets, streams, strutils]
import ellipse
import vmath
import ellipse/worlds/registry
import ellipse/editing/worldMeshEditing

import state

proc editorStatePath*(): string =
  getCurrentDir() / EditorStatePath

proc editorWorldStatePath*(): string =
  getCurrentDir() / EditorWorldStatePath

proc lineInputJson*(state: LineInputState): JsonNode =
  %*{"text": state.text, "cursor": state.cursor}

proc readLineInput*(node: JsonNode, state: LineInputState) =
  state.text = node["text"].getStr()
  state.cursor = node["cursor"].getInt()
  state.clampCursor()

proc vec3Json*(value: Vec3): JsonNode =
  %*{"x": value.x, "y": value.y, "z": value.z}

proc readVec3*(node: JsonNode): Vec3 =
  vec3(
    node["x"].getFloat().float32,
    node["y"].getFloat().float32,
    node["z"].getFloat().float32,
  )

proc worldJson*(world: World): string =
  let stream = newStringStream()
  defer:
    stream.close()
  stream.write(world)
  stream.data

proc readWorldJson*(text: string): World =
  let stream = newStringStream(text)
  defer:
    stream.close()
  stream.read(result)

proc writeEditorWorldState*() =
  try:
    createDir(editorWorldStatePath().parentDir)
    let fstream = openFileStream(editorWorldStatePath(), fmWrite)
    defer:
      fstream.close()
    fstream.write(editor.editWorld)
  except CatchableError as error:
    debugEcho "Failed to save editor world state: ", error.msg

proc readEditorWorldState*(): bool =
  if not editorWorldStatePath().fileExists:
    return false
  try:
    let fstream = openFileStream(editorWorldStatePath(), fmRead)
    defer:
      fstream.close()
    fstream.read(editor.editWorld)
    true
  except CatchableError as error:
    debugEcho "Failed to restore editor world state: ", error.msg
    false

proc readWorldFromDisk*(worldID: WorldID): bool =
  if not validWorldID(worldID):
    return false
  try:
    let fstream = openFileStream(getWorldsDirectory() / worldID /
        "data.world", fmRead)
    defer:
      fstream.close()
    fstream.read(editor.editWorld)
    true
  except CatchableError as error:
    debugEcho "Failed to restore world from disk: ", error.msg
    false

proc saveEditorWorldToDisk*(): bool {.discardable.} =
  if not validWorldID(editor.editWorld.name):
    debugEcho "Failed to save editor world: invalid world id"
    return false
  let dir =
    try:
      getWorldsDirectory() / editor.editWorld.name
    except CatchableError as error:
      debugEcho "Failed to get worlds directory: ", error.msg
      return false
  try:
    createDir(dir)
    let fstream = openFileStream(dir / "data.world", fmWrite)
    defer:
      fstream.close()
    fstream.write(editor.editWorld)
    true
  except CatchableError as error:
    debugEcho "Failed to save editor world: ", error.msg
    false

proc saveEditorWorldToDisk*(worldRegistry: var WorldsRegistry): bool {.discardable.} =
  ## Refresh the runtime registry from the saved file so Play uses this save.
  result = saveEditorWorldToDisk()
  if result:
    worldRegistry.load(editor.editWorld.name.WorldID)

proc writeEditorState*() =
  try:
    createDir(editorStatePath().parentDir)
    var selectedTriangles: seq[int]
    for triangle in editor.meshEditor.selectedTriangles:
      selectedTriangles.add triangle
    selectedTriangles.sort()
    var selectedQuads: seq[int]
    for quad in editor.meshEditor.selectedQuads:
      selectedQuads.add quad
    selectedQuads.sort()
    let state = %*{
      "heading": EditorStateHeading,
      "panels": {
        "hierarchy": editor.showHierarchyPanel,
        "mesh": editor.showMeshPanel,
        "solid": editor.showSolidMesh,
        "wireframe": editor.showWireframeMesh,
        "water": editor.showWater,
      },
      "dialogs": {
        "newWorld": {
          "show": editor.newWorldDialog.show,
          "worldName": lineInputJson(editor.newWorldDialog.worldName),
        },
        "openWorld": {
          "show": editor.openWorldDialog.show,
          "search": lineInputJson(editor.openWorldDialog.search),
        },
        "saveWorld": {
          "show": editor.saveWorldDialog.show,
          "worldName": lineInputJson(editor.saveWorldDialog.worldName),
        },
      },
      "editWorldID": editor.editWorldID,
      "terrainPanel": {
        "cellX": editor.terrainPanel.cellX,
        "cellZ": editor.terrainPanel.cellZ,
        "texturePath": editor.terrainPanel.texturePath,
        "specularStrength": editor.terrainPanel.specularStrength,
      },
      "meshPanelTab": editor.meshPanelTab,
      "showRenderTargetsPanel": editor.showRenderTargetsPanel,
      "selectedWaterPlane": editor.selectedWaterPlane,
      "selectedLocalEnvironment": editor.selectedLocalEnvironment,
      "uvTexturePath": editor.uvTexturePath,
      "uvTextureIndex": editor.uvTextureIndex,
      "meshEditor": {
        "focusPlane": {
          "angle": editor.meshEditor.focusPlane.angle,
          "origin": vec3Json(editor.meshEditor.focusPlane.origin),
        },
        "selectedVertex": editor.meshEditor.selectedVertex,
        "selectedVertices": editor.meshEditor.selectedVertexList(),
        "selectedMesh": editor.meshEditor.selectedMesh,
        "selectedTriangles": selectedTriangles,
        "selectedQuads": selectedQuads,
        "quadExtrusionMode": editor.meshEditor.quadExtrusionMode,
        "editMode": $editor.meshEditor.editMode,
        "terrainTool": $editor.meshEditor.terrainTool,
        "terrainToolMode": $editor.meshEditor.terrainToolMode,
        "brushRadius": editor.meshEditor.brushRadius,
        "brushStrength": editor.meshEditor.brushStrength,
        "plateauHeight": editor.meshEditor.plateauHeight,
        "terrainTextureIndex": editor.meshEditor.terrainTextureIndex,
        "terrainSampleSize": editor.meshEditor.terrainSampleSize,
        "terrainPaintMaterial": editor.meshEditor.terrainPaintMaterial,
        "camera": {
          "position": vec3Json(editor.meshEditor.fpsCamera.camera.position),
          "yaw": editor.meshEditor.fpsCamera.yaw,
          "pitch": editor.meshEditor.fpsCamera.pitch,
          "moveSpeed": editor.meshEditor.fpsCamera.moveSpeed,
          "lookSensitivity": editor.meshEditor.fpsCamera.lookSensitivity,
        },
      },
    }
    writeFile(editorStatePath(), state.pretty())
  except CatchableError as error:
    debugEcho "Failed to save editor state: ", error.msg

proc resetEditorRuntimeState*() =
  editor.cachedWorldRevision = high(uint64)
  editor.cachedWorldMeshes.setLen(0)
  editor.cachedWorldRenderMeshes.setLen(0)
  editor.cachedSourceWorldIDs.setLen(0)
  editor.cachedSourceMeshKey = ""
  editor.cachedSourceRenderMeshes.setLen(0)
  editor.cachedOverlayKey = ""
  editor.cachedOverlayVertices.setLen(0)
  editor.cachedOverlayIndices.setLen(0)
  editor.cachedWaterMeshReady = false
  editor.fpsSamples.setLen(0)
  editor.fpsClock = 0
  editor.fpsLastCounter = 0
  editor.fpsCounterFrequency = 0
  editor.fpsWidgetID = InvalidWidgetID
  editor.meshEditor.hovered = MeshPick(kind: Empty)
  editor.meshEditor.dragging = false
  editor.meshEditor.keyboardMoveVertex = -1
  editor.meshEditor.pickInitialized = false
  editor.uvSelectionKey = ""

proc clampOrReset(index, count: int): int =
  if count <= 0:
    -1
  elif index < 0 or index >= count:
    0
  else:
    index

proc sanitizeEditorStateAfterLoad() =
  editor.editWorld.normalizeSelectionState()
  editor.meshEditor.selectedMesh = editor.editWorld.selectedMesh

  let vertexCount = editor.editWorld.vertexCount()
  if editor.meshEditor.selectedVertex < 0 or
      editor.meshEditor.selectedVertex >= vertexCount:
    editor.meshEditor.selectedVertex = -1

  var selectedVertices = initHashSet[int]()
  for vertex in editor.meshEditor.selectedVertices:
    if vertex >= 0 and vertex < vertexCount:
      selectedVertices.incl vertex
  if editor.meshEditor.selectedVertex >= 0:
    selectedVertices.incl editor.meshEditor.selectedVertex
  editor.meshEditor.selectedVertices = selectedVertices

  let triangleCount =
    if editor.editWorld.meshCount > 0:
      editor.editWorld.indexCount() div 3
    else:
      0
  var selectedTriangles = initHashSet[int]()
  for triangle in editor.meshEditor.selectedTriangles:
    if triangle >= 0 and triangle < triangleCount:
      selectedTriangles.incl triangle
  editor.meshEditor.selectedTriangles = selectedTriangles

  var selectedQuads = initHashSet[int]()
  for quad in editor.meshEditor.selectedQuads:
    if quad >= 0 and quad < triangleCount:
      selectedQuads.incl quad
  editor.meshEditor.selectedQuads = selectedQuads

  editor.selectedWaterPlane = clampOrReset(
    editor.selectedWaterPlane,
    editor.editWorld.waterPlaneCount(),
  )
  editor.selectedLocalEnvironment = clampOrReset(
    editor.selectedLocalEnvironment,
    editor.editWorld.localEnvironmentCount(),
  )

  if editor.meshPanelTab < TerrainTab.int or editor.meshPanelTab > SpawnsTab.int:
    editor.meshPanelTab = TerrainTab.int
  if editor.uvTextureIndex < 0:
    editor.uvTextureIndex = 0
  if editor.meshEditor.terrainTextureIndex < 0:
    editor.meshEditor.terrainTextureIndex = 0
  if editor.meshEditor.terrainSampleSize < 1:
    editor.meshEditor.terrainSampleSize = 1

proc readEditorState*(worldRegistry: var WorldsRegistry): bool =
  if not editorStatePath().fileExists:
    return false
  try:
    let state = parseJson(readFile(editorStatePath()))
    let heading = state["heading"].getStr()
    if heading != EditorStateHeading:
      raise ValueError.newException("Unsupported editor state heading " & heading)
    let panels = state["panels"]
    editor.showHierarchyPanel = panels["hierarchy"].getBool()
    editor.showMeshPanel = panels["mesh"].getBool()
    editor.showSolidMesh = panels["solid"].getBool()
    editor.showWireframeMesh = panels["wireframe"].getBool()
    if panels.hasKey("water"):
      editor.showWater = panels["water"].getBool()
    let dialogs = state["dialogs"]
    editor.newWorldDialog.show = dialogs["newWorld"]["show"].getBool()
    readLineInput(dialogs["newWorld"]["worldName"],
        editor.newWorldDialog.worldName)
    editor.openWorldDialog.show = dialogs["openWorld"]["show"].getBool()
    readLineInput(dialogs["openWorld"]["search"], editor.openWorldDialog.search)
    editor.saveWorldDialog.show = dialogs["saveWorld"]["show"].getBool()
    readLineInput(dialogs["saveWorld"]["worldName"],
        editor.saveWorldDialog.worldName)
    editor.editWorldID = state["editWorldID"].getStr().WorldID
    let terrainPanel = state["terrainPanel"]
    if terrainPanel.hasKey("cellX"):
      editor.terrainPanel.cellX = terrainPanel["cellX"].getInt()
    if terrainPanel.hasKey("cellZ"):
      editor.terrainPanel.cellZ = terrainPanel["cellZ"].getInt()
    editor.terrainPanel.texturePath = terrainPanel["texturePath"].getStr()
    if terrainPanel.hasKey("specularStrength"):
      editor.terrainPanel.specularStrength =
        terrainPanel["specularStrength"].getFloat().float32
    editor.meshPanelTab = state["meshPanelTab"].getInt()
    if state.hasKey("showRenderTargetsPanel"):
      editor.showRenderTargetsPanel = state["showRenderTargetsPanel"].getBool()
    if state.hasKey("selectedWaterPlane"):
      editor.selectedWaterPlane = state["selectedWaterPlane"].getInt()
    if state.hasKey("selectedLocalEnvironment"):
      editor.selectedLocalEnvironment = state[
          "selectedLocalEnvironment"].getInt()
    editor.uvTexturePath = state["uvTexturePath"].getStr()
    if state.hasKey("uvTextureIndex"):
      editor.uvTextureIndex = state["uvTextureIndex"].getInt()
    let meshEditor = state["meshEditor"]
    editor.meshEditor.focusPlane.angle =
      meshEditor["focusPlane"]["angle"].getFloat().float32
    editor.meshEditor.focusPlane.origin = readVec3(meshEditor["focusPlane"]["origin"])
    let selectedVertex = meshEditor["selectedVertex"].getInt()
    editor.meshEditor.selectedMesh = meshEditor["selectedMesh"].getInt()
    editor.meshEditor.editMode =
      parseEnum[WorldMeshEditMode](meshEditor["editMode"].getStr())
    editor.meshEditor.terrainTool =
      parseEnum[TerrainTool](meshEditor["terrainTool"].getStr())
    if meshEditor.hasKey("terrainToolMode"):
      editor.meshEditor.terrainToolMode =
        parseEnum[TerrainToolMode](meshEditor["terrainToolMode"].getStr())
    editor.meshEditor.brushRadius = meshEditor["brushRadius"].getFloat().float32
    editor.meshEditor.brushStrength = meshEditor["brushStrength"].getFloat().float32
    editor.meshEditor.plateauHeight = meshEditor["plateauHeight"].getFloat().float32
    editor.meshEditor.terrainTextureIndex = meshEditor[
        "terrainTextureIndex"].getInt()
    editor.meshEditor.terrainSampleSize = meshEditor[
        "terrainSampleSize"].getInt()
    editor.meshEditor.terrainPaintMaterial = meshEditor[
        "terrainPaintMaterial"].getInt()
    let camera = meshEditor["camera"]
    editor.meshEditor.fpsCamera.camera.position = readVec3(camera["position"])
    editor.meshEditor.fpsCamera.yaw = camera["yaw"].getFloat().float32
    editor.meshEditor.fpsCamera.pitch = camera["pitch"].getFloat().float32
    editor.meshEditor.fpsCamera.moveSpeed = camera["moveSpeed"].getFloat().float32
    editor.meshEditor.fpsCamera.lookSensitivity =
      camera["lookSensitivity"].getFloat().float32
    editor.meshEditor.fpsCamera.camera.orientation =
      editor.meshEditor.fpsCamera.orientation
    var selectedTriangles = initHashSet[int]()
    for triangle in meshEditor["selectedTriangles"].items:
      selectedTriangles.incl(triangle.getInt())
    if state.hasKey("world"):
      editor.editWorld = readWorldJson(state["world"].getStr())
    elif not readEditorWorldState():
      if not readWorldFromDisk(editor.editWorldID):
        editor.editWorld = World.init(editor.editWorldID)

    editor.meshEditor.selectMesh(editor.editWorld,
        editor.editWorld.selectedMesh)
    editor.meshEditor.selectedVertex = selectedVertex
    editor.meshEditor.selectedTriangles = selectedTriangles
    editor.meshEditor.selectedQuads.clear()
    if meshEditor.hasKey("selectedQuads"):
      for quad in meshEditor["selectedQuads"].items:
        editor.meshEditor.selectedQuads.incl(quad.getInt())
    if meshEditor.hasKey("quadExtrusionMode"):
      editor.meshEditor.quadExtrusionMode = meshEditor[
        "quadExtrusionMode"].getBool()
    editor.meshEditor.selectedVertices.clear()
    if meshEditor.hasKey("selectedVertices"):
      for vertex in meshEditor["selectedVertices"].items:
        editor.meshEditor.selectedVertices.incl(vertex.getInt())
    elif selectedVertex >= 0:
      editor.meshEditor.selectedVertices.incl(selectedVertex)
    sanitizeEditorStateAfterLoad()
    resetEditorRuntimeState()
    true
  except CatchableError as error:
    debugEcho "Failed to restore editor state: ", error.msg
    false
