import std/[os, sets, tables]
import ellipse
import nest/components/component
import sdl3 except Vertex
import vmath
import ellipse/editing/worldMeshEditing
import ellipse/worlds/worlds

const PluginEventTypeAnchor {.used.} = sizeof(sdl3.Event)

const DefaultTexturePath* = "res/textures/environment.aseprite"
const EditorStateHeading* = "ELLIPSE Editor 0."
const EditorStatePath* = "data/editor.state"
const EditorWorldStatePath* = "data/editor.world"
const EditorOverlayMeshID* = "editor mesh overlay"
const EditorPlacementCursorMeshID* = "editor placement cursor"
const EditorPlacementPreviewMeshID* = "editor placement preview"
const ModelGizmoXMeshID* = "editor model gizmo x"
const ModelGizmoYMeshID* = "editor model gizmo y"
const ModelGizmoZMeshID* = "editor model gizmo z"
const ModelGizmoCenterMeshID* = "editor model gizmo center"
const EditorEntitySpawnMeshID* = "editor entity spawn marker"
const CameraWidgetUpMeshID* = "editor camera widget up"
const CameraWidgetRightMeshID* = "editor camera widget right"
const CameraWidgetForwardMeshID* = "editor camera widget forward"
const FpsChartHistorySeconds* = 10.0
const FpsTrimBatch* = 120
const FpsLabelAverageFrames* = 30
const TerrainAtlasColumns* = 8
const TerrainAtlasRows* = 8
const TerrainAtlasPixelSize* = 1024
const TextureAtlasButtonSize* = 128
const TextureAtlasDialogColumns* = 4
const WaterMeshID* = "editor water plane"
const
  TerrainCursorStep* = 1
  TerrainCursorButtonWidth* = 42
  TerrainCursorButtonHeight* = 30
  TerrainCursorActionHeight* = 32
  TerrainCursorGap* = 6

proc texturePreviewPath*(path: string): string =
  if path.len == 0:
    return path.normalizedPath
  if path.isAbsolute:
    return path.normalizedPath
  if path.fileExists:
    return path.absolutePath.normalizedPath
  let projectPath = currentSourcePath().parentDir.parentDir.parentDir / path
  if projectPath.fileExists:
    return projectPath.absolutePath.normalizedPath
  path.absolutePath.normalizedPath

type
  TextureAtlasTarget* = enum
    NoTextureAtlasTarget
    UvTextureAtlasTarget
    TerrainTextureAtlasTarget

  EditorNewWorldDialog* = object
    show*: bool
    worldName*: LineInputState

  EditorOpenWorldDialog* = object
    show*: bool
    search*: LineInputState

  EditorSaveWorldDialog* = object
    show*: bool
    worldName*: LineInputState

  ModelPickerStage* = enum
    PickModelWorld
    PickModelMesh

  EditorModelPickerDialog* = object
    show*: bool
    stage*: ModelPickerStage
    worldID*: WorldID
    search*: LineInputState

  ConfirmationAction* = enum
    NoConfirmationAction
    DeleteMeshConfirmationAction

  ConfirmationDialog* = object
    show*: bool
    title*, message*: string
    confirmLabel*, cancelLabel*: string
    action*: ConfirmationAction
    meshIndex*: int

  TerrainPanel* = object
    cellX*, cellZ*: int
    texturePath*: string
    specularStrength*: float32

  MeshPanelTab* = enum
    TerrainTab
    WorldMeshesTab
    WaterTab
    EnvTab
    ModelsTab
    SpawnsTab

  ModelGizmoMode* = enum
    ModelGizmoMove
    ModelGizmoRotate
    ModelGizmoScale
    ModelGizmoScaleAll

  ModelGizmoHandle* = enum
    NoModelGizmoHandle
    ModelGizmoX
    ModelGizmoY
    ModelGizmoZ
    ModelGizmoCenter

  EditorSourceRenderMesh* = object
    sourceWorld*: WorldID
    sourceMesh*: string
    meshID*: MeshID
    materialID*: MaterialID

  EditorWorldRenderMesh* = object
    meshID*: MeshID
    materialID*: MaterialID

  Editor* = object
    showFileMenu*, showViewMenu*, showPlugins*: bool
    showHierarchyPanel*, showMeshPanel*, showRenderTargetsPanel*: bool
    showSolidMesh*, showWireframeMesh*, showWater*: bool
    newWorldDialog*: EditorNewWorldDialog
    openWorldDialog*: EditorOpenWorldDialog
    saveWorldDialog*: EditorSaveWorldDialog
    modelPickerDialog*: EditorModelPickerDialog
    confirmationDialog*: ConfirmationDialog
    editWorld*: World
    editWorldID*: WorldID
    meshEditor*: WorldMeshEditor
    terrainPanel*: TerrainPanel
    meshPanelTab*: int
    modelGizmoMode*: ModelGizmoMode
    modelGizmoHover*: ModelGizmoHandle
    modelGizmoDragHandle*: ModelGizmoHandle
    modelGizmoDragging*: bool
    modelGizmoDragStartMouseX*, modelGizmoDragStartMouseY*: int
    modelGizmoDragStartParam*: float32
    modelGizmoDragStart*: WorldModelInstance
    spawnGizmoHover*: ModelGizmoHandle
    spawnGizmoDragHandle*: ModelGizmoHandle
    spawnGizmoDragging*: bool
    spawnGizmoDragStartParam*: float32
    spawnGizmoDragStart*: WorldEntitySpawn
    placementCursorActive*: bool
    placementCursorPosition*: Vec3
    hierarchyTerrainOpen*, hierarchyMeshesOpen*, hierarchyModelsOpen*: bool
    selectedWaterPlane*: int
    selectedLocalEnvironment*: int
    uvState*: Mesh2DState
    uvMultiSelectBase*: HashSet[int]
    uvTriangles*: seq[int]
    uvSelectionKey*: string
    uvRectangleWinding*: int
    uvTexturePath*: string
    uvTextureIndex*: int
    textureAtlasDialogTarget*: TextureAtlasTarget
    showTextureAtlasDialog*: bool
    cachedWorldRevision*: uint64
    cachedWorldMeshes*: seq[WorldRenderMesh]
    cachedWorldRenderMeshes*: seq[EditorWorldRenderMesh]
    cachedSourceWorldIDs*: seq[WorldID]
    cachedSourceMeshKey*: string
    cachedSourceRenderMeshes*: seq[EditorSourceRenderMesh]
    cachedOverlayKey*: string
    cachedOverlayVertices*: seq[Vertex]
    cachedOverlayIndices*: seq[uint32]
    cachedWaterMeshReady*: bool
    fpsSamples*: seq[tuple[t, dt: float64]]
    fpsClock*: float64
    fpsLastCounter*: uint64
    fpsCounterFrequency*: uint64
    fpsSnapshotMessage*: string
    fpsWidgetID*: WidgetID
    showFpsDialog*: bool
    showPluginBuildOutput*: bool
    pluginBuildOutput*: LineInputState
    meshNameInput*: LineInputState
    meshEditId*: WidgetID
    waterNumberInputs*: Table[string, LineInputState]
    sliderNumberInputs*: Table[string, LineInputState]
    editingSliderNumbers*: HashSet[string]
    numberDragStartValues*: Table[string, float32]

  FpsChart* = ref object of Component

var editor* = Editor(
  showHierarchyPanel: true,
  showMeshPanel: true,
  showRenderTargetsPanel: false,
  showSolidMesh: true,
  showWireframeMesh: false,
  showWater: true,
  newWorldDialog: EditorNewWorldDialog(show: false,
      worldName: LineInputState.new("")),
  openWorldDialog: EditorOpenWorldDialog(show: false,
      search: LineInputState.new("")),
  saveWorldDialog: EditorSaveWorldDialog(show: false,
      worldName: LineInputState.new("")),
  modelPickerDialog: EditorModelPickerDialog(show: false,
      stage: PickModelWorld, search: LineInputState.new("")),
  confirmationDialog: ConfirmationDialog(
    show: false,
    title: "Confirm",
    message: "",
    confirmLabel: "Confirm",
    cancelLabel: "Cancel",
    action: NoConfirmationAction,
    meshIndex: -1,
  ),
  pluginBuildOutput: LineInputState.new(""),
  meshNameInput: LineInputState.new(""),
  meshEditor: WorldMeshEditor.init(),
  modelGizmoMode: ModelGizmoMove,
  modelGizmoHover: NoModelGizmoHandle,
  modelGizmoDragHandle: NoModelGizmoHandle,
  spawnGizmoHover: NoModelGizmoHandle,
  spawnGizmoDragHandle: NoModelGizmoHandle,
  placementCursorActive: false,
  placementCursorPosition: vec3(0, 0, 0),
  hierarchyTerrainOpen: false,
  hierarchyMeshesOpen: false,
  hierarchyModelsOpen: false,
  uvMultiSelectBase: initHashSet[int](),
  uvTexturePath: DefaultTexturePath,
  uvTextureIndex: 0,
  textureAtlasDialogTarget: NoTextureAtlasTarget,
  showTextureAtlasDialog: false,
  terrainPanel: TerrainPanel(texturePath: DefaultTexturePath,
      specularStrength: DefaultSpecularStrength),
  meshEditId: 0,
  waterNumberInputs: initTable[string, LineInputState](),
  sliderNumberInputs: initTable[string, LineInputState](),
  editingSliderNumbers: initHashSet[string](),
  numberDragStartValues: initTable[string, float32](),
)

var spawnableEntityTypes*: seq[string] = @[]

proc setSpawnableEntityTypes*(entityTypes: openArray[string]) =
  ## Supplies the project-specific entity catalogue used by the Spawn panel.
  spawnableEntityTypes = @entityTypes

proc entityTypes*(): lent seq[string] = spawnableEntityTypes

proc placementCursorPosition*(): Vec3 =
  if editor.placementCursorActive:
    editor.placementCursorPosition
  else:
    vec3(0, 0, 0)
