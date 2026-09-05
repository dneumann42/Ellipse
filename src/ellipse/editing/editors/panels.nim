import std/[math, sets, strutils]
import ellipse
import nest/screen as nestScreen
import vmath
import ellipse/worlds/worlds
import ellipse/editing/worldMeshEditing

import state, uihelpers, uv, dialogs
import panels/renderTargets

proc moveTerrainCursor*(dx, dz: int) =
  editor.terrainPanel.cellX += dx * TerrainCursorStep
  editor.terrainPanel.cellZ += dz * TerrainCursorStep

proc selectTerrainCursorCell*() =
  let index = editor.editWorld.terrainMeshAtCell(
    editor.terrainPanel.cellX, editor.terrainPanel.cellZ
  )
  if index >= 0:
    editor.meshEditor.selectMesh(editor.editWorld, index)

proc moveMeshToPlacementCursor(index: int) =
  if index >= 0:
    editor.editWorld.translateMesh(index, placementCursorPosition())

proc terrainCursorButtonImpl(
    gui: var UI, id, label: string, dx, dz: int,
        width = TerrainCursorButtonWidth
) =
  gui.scope("terrain cursor"):
    gui.scope(id):
      if gui.button(
        gui.id(), label, fixed(width.float64), fixed(TerrainCursorButtonHeight)
      ):
        moveTerrainCursor(dx, dz)
        selectTerrainCursorCell()

proc hierarchyEditId(index: int): WidgetID =
  WidgetID(index + 1)

proc beginHierarchyRename(index: int, name: string) =
  editor.meshEditId = hierarchyEditId(index)
  editor.meshNameInput.text = name
  editor.meshNameInput.cursor = name.len
  editor.meshNameInput.selectionAnchor = 0
  editor.meshNameInput.undoStack.setLen(0)
  editor.meshNameInput.redoStack.setLen(0)

proc hierarchyItemStyle(selected: bool): ComponentStyle =
  if selected:
    selectedStyle(true, color(56, 78, 83))
  else:
    ComponentStyle(hasBackground: true, background: EditorCardBackground)

proc finishHierarchyRename(index: int) =
  let name = editor.meshNameInput.text.strip()
  if name.len > 0:
    editor.editWorld.renameMesh(index, name)
  editor.meshEditId = 0

proc selectHierarchyMesh(index: int) =
  if index < 0 or index >= editor.editWorld.meshCount:
    return
  editor.meshEditor.selectMesh(editor.editWorld, index)
  if editor.editWorld.meshKind(index) == TerrainWorldMesh:
    let region = editor.editWorld.terrainCellForMesh(index)
    editor.terrainPanel.cellX = region.cellX
    editor.terrainPanel.cellZ = region.cellZ

proc hierarchyPanelImpl(gui: var UI) =
  var
    selectIndex = -1
    selectModelIndex = -1
    deleteModelIndex = -1
    renameIndex = -1
    renameName = ""
    cancelRename = false
  template sectionHeader(openFlag: var bool, sectionKey, title: string, count: int) =
    let marker = if openFlag: "v " else: "> "
    if gui.button(
      gui.id(sectionKey & " header"), marker & title & " (" & $count & ")",
      fill(), fixed(30),
      style = ComponentStyle(hasBackground: true, background: color(40, 50,
          54)),
    ):
      openFlag = not openFlag
      gui.markAllDirty()

  template renderMeshItem(i: int, mesh: WorldMesh) =
    let selected = i == editor.editWorld.selectedMesh
    gui.card(
      gui.id("mesh item", i, mesh.name),
      cfg(
        width = fill(),
        height = fit(),
        gap = 0,
        padding = 0,
        style = hierarchyItemStyle(selected),
      ),
    ):
      gui.row(
        gui.id("mesh item body", i),
        cfg(width = fill(), height = fit(), gap = 8, padding = 10),
      ):
        gui.column(
          gui.id("mesh item summary", i),
          cfg(width = fill(), height = fit(), gap = 8, padding = 0),
        ):
          let kindLabel = mesh.kind.meshKindLabel
          gui.label(kindLabel, fill(), fit())
          if editor.meshEditId == hierarchyEditId(i):
            let inputId = gui.id("mesh item name input", i)
            gui.lineInput(inputId, editor.meshNameInput, fill(), fixed(32))
            if gui.inEventPhase() and gui.focused(inputId):
              gui.markAllDirty()
            if gui.inEventPhase() and gui.submitted(inputId):
              renameIndex = i
              renameName = editor.meshNameInput.text
            if gui.inEventPhase() and gui.keyPressed("escape"):
              cancelRename = true
          else:
            gui.label(
              gui.id("mesh item name", i), mesh.name, fill(), fixed(26),
                  textScroll = true
            )

        # gui.row(
        #   gui.id("mesh item details", i),
        #   cfg(width = fill(), height = fit(), gap = 8, padding = 0,
        #       alignItems = Center),
        # ):
        #   gui.label(gui.id("mesh item vertices", i), $mesh.vertices.len &
        #       " vertices", fixed(104), fixed(22))
        #   gui.label(gui.id("mesh item faces", i),
        #       $(mesh.indices.len div 3) & " faces", fixed(82), fixed(22))
        #   if mesh.kind == TerrainWorldMesh:
        #     let region = editor.editWorld.terrainCellForMesh(i)
        #     gui.label(gui.id("mesh item cell", i),
        #         "cell " & $region.cellX & ", " & $region.cellZ, fill(),
        #         fixed(22))
        #   else:
        #     gui.spacer(fill(), fixed(1))
        gui.spacer(fill(), fixed(1))

        gui.column(
          gui.id("mesh item actions", i),
          cfg(width = fill(), height = fit(), gap = 4, padding = 0,
              alignItems = Center),
        ):
          if editor.meshEditId == hierarchyEditId(i):
            if gui.button(gui.id("mesh save button", i), "Save", fill(),
                fixed(28)):
              renameIndex = i
              renameName = editor.meshNameInput.text
            if gui.button(gui.id("mesh cancel button", i), "Cancel", fill(),
                fixed(28)):
              cancelRename = true
            gui.spacer(fill(), fixed(1))
          else:
            if gui.button(gui.id("mesh rename button", i), "Edit", fill(),
                fixed(28)):
              beginHierarchyRename(i, mesh.name)
              gui.markAllDirty()
            if gui.button(gui.id("mesh select button", i), "Select", fill(),
                fixed(28)):
              selectIndex = i
          if gui.button(gui.id("mesh delete button", i), "Delete", fill(),
              fixed(28)):
            let meshType =
              if mesh.kind == TerrainWorldMesh:
                "terrain"
              else:
                "mesh"
            requestConfirmation(
              gui,
              editor.confirmationDialog,
              "Delete " & mesh.kind.meshKindLabel,
              "Delete " & meshType & " \"" & mesh.name & "\"?",
              DeleteMeshConfirmationAction,
              confirmLabel = "Delete",
              cancelLabel = "Cancel",
              meshIndex = i,
            )

  gui.panel(
    gui.id("hierarchy panel"),
    cfg(
      width = fixed(320),
      height = fill(),
      gap = 0,
      padding = 0,
      style = ComponentStyle(hasBackground: true, background: color(29, 35,
          38, 190)),
    ),
  ):
    gui.panelHeader("hierarchy panel", "Hierarchy")
    gui.column(
      gui.id("hierarchy list"),
      cfg(width = fill(), height = fill(), gap = 8, padding = 10,
          scrollY = true),
    ):
      if editor.editWorld.meshCount == 0 and editor.editWorld.modelCount == 0:
        gui.card(
          gui.id("hierarchy empty card"),
          cfg(width = fill(), height = fit(), gap = 6, padding = 10),
        ):
          gui.label("No terrain, meshes, or models", fill(), fixed(28))
      var terrainCount = 0
      var meshCount = 0
      for i, mesh in editor.editWorld.meshes:
        if mesh.kind == TerrainWorldMesh:
          inc terrainCount
        else:
          inc meshCount

      sectionHeader(editor.hierarchyTerrainOpen, "terrain hierarchy",
          "Terrain", terrainCount)
      if editor.hierarchyTerrainOpen:
        for i, mesh in editor.editWorld.meshes:
          if mesh.kind == TerrainWorldMesh:
            renderMeshItem(i, mesh)

      sectionHeader(editor.hierarchyMeshesOpen, "mesh hierarchy", "Meshes",
          meshCount)
      if editor.hierarchyMeshesOpen:
        for i, mesh in editor.editWorld.meshes:
          if mesh.kind != TerrainWorldMesh:
            renderMeshItem(i, mesh)

      sectionHeader(editor.hierarchyModelsOpen, "model hierarchy", "Models",
          editor.editWorld.modelCount)
      if editor.hierarchyModelsOpen:
        for i, instance in editor.editWorld.models:
          let selected = i == editor.editWorld.selectedModel
          gui.card(
            gui.id("hierarchy model item", i, instance.name),
            cfg(width = fill(), height = fit(), gap = 8, padding = 10,
                style = hierarchyItemStyle(selected)),
          ):
            gui.row(
              gui.id("hierarchy model actions container", i),
              cfg(width = fill(), height = fit(), gap = 4, padding = 0),
            ):
              gui.column(
                gui.id("hmac ", i),
                cfg(width = fit(), height = fit(), gap = 4, padding = 0),
              ):
                gui.label(gui.id("hierarchy model name", i), instance.name,
                    fill(), fixed(26), textScroll = true)
                gui.label(
                  gui.id("hierarchy model source", i),
                  instance.sourceWorld & "/" & instance.sourceMesh,
                  fit(),
                  fixed(22),
                  textScroll = true,
                )
              gui.spacer(fill(), fixed(1))
              gui.column(
                gui.id("hierarchy model actions", i),
                cfg(width = fixed(80), height = fit(), gap = 4, padding = 0),
              ):
                if gui.button(gui.id("hierarchy model select", i), "Select",
                    fill(), fixed(28)):
                  selectModelIndex = i
                if gui.button(gui.id("hierarchy model delete", i), "Delete",
                    fill(), fixed(28)):
                  deleteModelIndex = i

  if renameIndex >= 0:
    editor.meshNameInput.text = renameName
    finishHierarchyRename(renameIndex)
    gui.markAllDirty()
  elif cancelRename:
    editor.meshEditId = 0
    gui.markAllDirty()
  if selectIndex >= 0:
    selectHierarchyMesh(selectIndex)
  if selectModelIndex >= 0:
    editor.editWorld.selectedModel = selectModelIndex
    editor.modelGizmoDragging = false
    gui.markAllDirty()
  if deleteModelIndex >= 0:
    editor.editWorld.deleteModel(deleteModelIndex)
    editor.modelGizmoDragging = false
    gui.markAllDirty()

proc terrainTabPanelImpl(gui: var UI, io: IO) =
  gui.column(
    gui.id("terrain body"),
    cfg(width = fill(), height = fill(), gap = 10, padding = 10,
        scrollY = true),
  ):
    gui.editorCard("terrain create", "Mesh"):
      gui.metricRow(
        "terrain cursor cell",
        "Cursor",
        $editor.terrainPanel.cellX & ", " & $editor.terrainPanel.cellZ,
      )
      gui.metricRow(
        "terrain region subdivisions", "Subdivisions", $TerrainRegionSubdivisions
      )
      gui.metricRow("terrain region size", "Size", $TerrainRegionSize)
      gui.row(
        gui.id("terrain cursor north row"),
        cfg(width = fill(), height = fit(), gap = TerrainCursorGap,
            padding = 0),
      ):
        gui.spacer(fill(), fit())
        gui.terrainCursorButtonImpl("north", "Z-", 0, -1)
        gui.spacer(fill(), fit())
      gui.row(
        gui.id("terrain cell row"),
        cfg(width = fill(), height = fit(), gap = TerrainCursorGap,
            padding = 0),
      ):
        gui.terrainCursorButtonImpl("west", "X-", -1, 0)
        gui.spacer(fill(), fit())
        gui.terrainCursorButtonImpl("east", "X+", 1, 0)
      gui.row(
        gui.id("terrain cursor south row"),
        cfg(width = fill(), height = fit(), gap = TerrainCursorGap,
            padding = 0),
      ):
        gui.spacer(fill(), fit())
        gui.terrainCursorButtonImpl("south", "Z+", 0, 1)
        gui.spacer(fill(), fit())
      let existingTerrain = editor.editWorld.terrainMeshAtCell(
        editor.terrainPanel.cellX, editor.terrainPanel.cellZ
      )
      let addLabel =
        if existingTerrain >= 0:
          "Select Terrain Cell"
        else:
          "Add Terrain Cell"
      if gui.button(
        gui.id("terrain add mesh"), addLabel, fill(), fixed(TerrainCursorActionHeight)
      ):
        if existingTerrain >= 0:
          editor.meshEditor.selectMesh(editor.editWorld, existingTerrain)
        else:
          let name = "Terrain " & $(editor.editWorld.meshCount + 1)
          let index = editor.editWorld.createTerrainRegion(
            name,
            editor.terrainPanel.cellX,
            editor.terrainPanel.cellZ,
          )
          if index >= 0:
            editor.meshEditor.selectMesh(editor.editWorld, index)

    gui.editorCard("terrain tools", "Tools"):
      gui.actionRow("terrain tool row 1"):
        gui.toolButton(Raise, "Raise")
        gui.toolButton(Plateau, "Plateau")
      gui.actionRow("terrain tool row 2"):
        gui.toolButton(Flatten, "Flatten")
        gui.toolButton(Paint, "Paint")
      gui.actionRow("terrain tool mode row"):
        gui.terrainToolModeButton(NormalTerrainToolMode, "Normal")
        gui.terrainToolModeButton(InvertedTerrainToolMode, "Invert")
      gui.terrainSlider(
        "terrain radius", "Brush Radius", editor.meshEditor.brushRadius, 0.2, 5
      )
      gui.terrainSlider(
        "terrain strength", "Strength", editor.meshEditor.brushStrength, 0.01,
        0.3, 100
      )
      gui.terrainSlider(
        "terrain plateau", "Plateau Height", editor.meshEditor.plateauHeight,
        -4, 8
      )
      if gui.textureAtlasPicker("terrain texture", TerrainTextureAtlasTarget,
          texturePreviewPath(editor.terrainPanel.texturePath),
          editor.meshEditor.terrainTextureIndex):
        discard ensureTerrainTextureMaterial()
      var terrainSpecular = editor.editWorld.terrainSpecular()
      gui.terrainSlider(
        "terrain specular", "Specular", terrainSpecular, 0, 2
      )
      editor.editWorld.setTerrainSpecular(terrainSpecular)
      editor.terrainPanel.specularStrength = terrainSpecular
      gui.terrainIntSlider(
        "terrain sample size", "Sample Size",
        editor.meshEditor.terrainSampleSize, 128,
        512,
      )

    gui.editorCard("terrain selection", "Selection"):
      if editor.editWorld.meshCount > 0:
        let mesh = editor.editWorld.mesh(editor.editWorld.selectedMesh)
        gui.metricRow("terrain mesh name", "Mesh", mesh.name)
        gui.metricRow("terrain mesh kind", "Kind", mesh.kind.meshKindLabel)
        if mesh.kind == TerrainWorldMesh:
          let region = editor.editWorld.terrainCellForMesh(
            editor.editWorld.selectedMesh
          )
          gui.metricRow(
            "terrain mesh cell", "Cell", $region.cellX & ", " & $region.cellZ
          )
        gui.metricRow("terrain mesh vertices", "Vertices", $mesh.vertices.len)
        gui.metricRow("terrain mesh faces", "Faces", $(mesh.indices.len div 3))
      else:
        gui.label("Create a terrain mesh to edit", fill(), fit())

proc worldMeshesTabPanelImpl(gui: var UI) =
  gui.column(
    gui.id("world mesh body"),
    cfg(width = fill(), height = fill(), gap = 10, padding = 10,
        scrollY = true),
  ):
    gui.editorCard("world mesh create", "Mesh"):
      if gui.button(gui.id("world mesh add"), "Add World Mesh", fill(), fixed(32)):
        let name = "Mesh " & $(editor.editWorld.meshCount + 1)
        let index = editor.editWorld.createWorldMesh(name)
        moveMeshToPlacementCursor(index)
        editor.meshEditor.selectMesh(editor.editWorld, index)
      gui.actionRow("world mesh primitive tools 1"):
        if gui.button(gui.id("world mesh add cube"), "Add Cube", fill(), fixed(30)):
          let name = "Cube " & $(editor.editWorld.meshCount + 1)
          let index = editor.editWorld.createCubeWorldMesh(name)
          moveMeshToPlacementCursor(index)
          editor.meshEditor.selectMesh(editor.editWorld, index)
        if gui.button(gui.id("world mesh add cylinder"), "Add Cylinder", fill(),
            fixed(30)):
          let name = "Cylinder " & $(editor.editWorld.meshCount + 1)
          let index = editor.editWorld.createCylinderWorldMesh(name)
          moveMeshToPlacementCursor(index)
          editor.meshEditor.selectMesh(editor.editWorld, index)
      if gui.button(gui.id("world mesh add pyramid"), "Add Pyramid", fill(),
          fixed(30)):
        let name = "Pyramid " & $(editor.editWorld.meshCount + 1)
        let index = editor.editWorld.createPyramidWorldMesh(name)
        moveMeshToPlacementCursor(index)
        editor.meshEditor.selectMesh(editor.editWorld, index)

    gui.editorCard("world mesh selection", "Selection"):
      if editor.editWorld.meshCount > 0:
        let mesh = editor.editWorld.mesh(editor.editWorld.selectedMesh)
        gui.metricRow("world mesh name", "Mesh", mesh.name)
        gui.metricRow("world mesh kind", "Kind", mesh.kind.meshKindLabel)
        gui.metricRow("world mesh vertices", "Vertices", $mesh.vertices.len)
        gui.metricRow("world mesh faces", "Faces", $(mesh.indices.len div 3))
        if mesh.kind != TerrainWorldMesh:
          var position = mesh.position
          var positionChanged = false
          gui.label("Mesh Position", fill(), fit())
          positionChanged = gui.waterNumberInput("mesh pos x", "Position X",
              position.x, -512, 512) or positionChanged
          positionChanged = gui.waterNumberInput("mesh pos y", "Position Y",
              position.y, -64, 64) or positionChanged
          positionChanged = gui.waterNumberInput("mesh pos z", "Position Z",
              position.z, -512, 512) or positionChanged
          if positionChanged:
            editor.editWorld.setMeshPosition(editor.editWorld.selectedMesh,
                position)
            gui.markAllDirty()
          if gui.button(gui.id("world mesh duplicate"), "Duplicate Mesh", fill(
              ), fixed(30)):
            let index = editor.editWorld.duplicateMesh(
                editor.editWorld.selectedMesh)
            if index >= 0:
              editor.meshEditor.selectMesh(editor.editWorld, index)
      else:
        gui.label("Create a world mesh to edit", fill(), fit())

    gui.editorCard("world mesh edit mode", "Edit Mode"):
      gui.label("Choose what to select in the viewport.", fill(), fit())
      gui.actionRow("world mesh edit modes"):
        gui.editModeButton(VertexEditMode, "Vertices")
        gui.editModeButton(TriangleEditMode, "Triangles")
      gui.actionRow("world mesh edit modes 2"):
        gui.editModeButton(QuadEditMode, "Quads")
        gui.editModeButton(EdgeEditMode, "Edges")

    gui.editorCard("world mesh selection tools", "Selection"):
      gui.metricRow(
        "world mesh selected triangles",
        "Triangles",
        $editor.meshEditor.selectedTriangles.len,
      )
      gui.metricRow(
        "world mesh selected quads",
        "Quads",
        $editor.meshEditor.selectedQuads.len,
      )
      gui.metricRow(
        "world mesh selected vertices",
        "Vertices",
        $editor.meshEditor.selectedVertices.len,
      )
      let quadExtrusionID = gui.id("mesh quad extrusion")
      gui.checkbox(
        quadExtrusionID, "Extrude edges as quads",
        editor.meshEditor.quadExtrusionMode, fill(), fixed(28),
      )
      if gui.inEventPhase and gui.clicked(quadExtrusionID):
        editor.meshEditor.quadExtrusionMode =
          not editor.meshEditor.quadExtrusionMode
      let faceNormalDragID = gui.id("mesh face normal drag")
      gui.checkbox(
        faceNormalDragID, "Drag faces along normal",
        editor.meshEditor.faceNormalDragMode, fill(), fixed(28),
      )
      if gui.inEventPhase and gui.clicked(faceNormalDragID):
        editor.meshEditor.faceNormalDragMode =
          not editor.meshEditor.faceNormalDragMode
      if gui.button(gui.id("mesh select all vertices"), "Select All Vertices",
          fill(), fixed(30)):
        editor.meshEditor.selectAllVertices(editor.editWorld)

    gui.card(
      gui.id("world mesh geometry tools"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      gui.label("Geometry Tools", fill(), fit())
      if editor.meshEditor.editMode == EdgeEditMode and
          editor.meshEditor.selectedVertices.len == 4:
        if gui.button(gui.id("mesh add face"), "Add Face", fill(), fixed(30)):
          if editor.editWorld.addSelectedFace(
              editor.meshEditor.selectedVertexList(),
              editor.meshEditor.focusPlane,
              false,
            ):
            editor.meshEditor.clearSelection()
      if editor.meshEditor.selectedVertices.len > 0 or
          editor.meshEditor.hovered.kind == Edge:
        gui.actionRow("world mesh delete tools"):
          if editor.meshEditor.selectedVertices.len > 0:
            if gui.button(gui.id("mesh delete vertex"), "Delete Vertex", fill(),
                fixed(30)):
              discard editor.meshEditor.deleteSelectedVertices(editor.editWorld)
          if editor.meshEditor.hovered.kind == Edge:
            if gui.button(gui.id("mesh delete edge"), "Delete Edge", fill(),
                fixed(30)):
              discard editor.meshEditor.deleteHoveredEdge(editor.editWorld)
      gui.actionRow("world mesh vertex transforms 1"):
        if gui.button(gui.id("mesh snap grid"), "Snap Grid", fill(), fixed(30)):
          editor.meshEditor.snapSelectedVertices(editor.editWorld)
        if gui.button(gui.id("mesh level x"), "Level X", fill(), fixed(30)):
          editor.meshEditor.levelSelectedVertices(editor.editWorld, 0)
      gui.actionRow("world mesh vertex transforms 2"):
        if gui.button(gui.id("mesh level y"), "Level Y", fill(), fixed(30)):
          editor.meshEditor.levelSelectedVertices(editor.editWorld, 1)
        if gui.button(gui.id("mesh level z"), "Level Z", fill(), fixed(30)):
          editor.meshEditor.levelSelectedVertices(editor.editWorld, 2)
      gui.label("Face Tools", fill(), fit())
      gui.actionRow("world mesh face tools top"):
        if gui.button(gui.id("mesh make wall"), "Make Wall", fill(), fixed(30)):
          discard editor.editWorld.addSelectedFace(
            editor.meshEditor.selectedVertexList(),
            editor.meshEditor.focusPlane,
            false,
          )
        if gui.button(gui.id("mesh make floor"), "Make Floor", fill(), fixed(30)):
          discard editor.editWorld.addSelectedFace(
            editor.meshEditor.selectedVertexList(),
            editor.meshEditor.focusPlane,
            true,
          )
      gui.actionRow("world mesh face tools bottom"):
        if gui.button(gui.id("mesh flip faces"), "Flip Faces", fill(), fixed(30)):
          editor.meshEditor.flipSelectedFaces(editor.editWorld)
      let geometryEdge = editor.meshEditor.geometryEdge
      if geometryEdge.kind == Edge:
        if gui.button(gui.id("mesh edge loop cut"), "Edge Loop Cut", fill(),
            fixed(30)):
          let newVertices = editor.editWorld.edgeLoopCut(
            geometryEdge.edgeA, geometryEdge.edgeB
          )
          if newVertices.len > 0:
            editor.meshEditor.selectedVertices.clear()
            for vertex in newVertices:
              editor.meshEditor.selectedVertices.incl vertex
            editor.meshEditor.selectedVertex = newVertices[0]
            editor.meshEditor.geometryEdge = MeshPick(kind: Empty,
                edgeA: -1, edgeB: -1)
        if gui.button(gui.id("mesh extrude edge"), "Extrude Edge Quad", fill(),
            fixed(30)):
          let newVertices = editor.editWorld.addQuadFromEdge(
            geometryEdge.edgeA, geometryEdge.edgeB, editor.meshEditor.focusPlane
          )
          if newVertices[0] >= 0:
            editor.meshEditor.selectedVertices.clear()
            editor.meshEditor.selectedVertices.incl newVertices[0]
            editor.meshEditor.selectedVertices.incl newVertices[1]
            editor.meshEditor.selectedVertex = newVertices[1]
            editor.meshEditor.geometryEdge = MeshPick(kind: Empty,
                edgeA: -1, edgeB: -1)

proc modelsTabPanelImpl(gui: var UI) =
  gui.column(gui.id("models body"), cfg(width = fill(), height = fill(),
      gap = 10, padding = 10, scrollY = true)):
    gui.card(gui.id("models add"), cfg(width = fill(), height = fit(),
        gap = 8, padding = 10)):
      gui.label("Choose a source world and model with Add Model", fill(), fit())
      if gui.button(gui.id("add model"), "Add Model", fill(), fixed(32)):
        editor.modelPickerDialog.show = true
        editor.modelPickerDialog.stage = PickModelWorld
        editor.modelPickerDialog.worldID = ""
        editor.modelPickerDialog.search.text = ""
        editor.modelPickerDialog.search.cursor = 0
        gui.markAllDirty()
    gui.card(gui.id("model gizmo"), cfg(width = fill(), height = fit(),
        gap = 6, padding = 10)):
      gui.label("Gizmo", fill(), fit())
      gui.label("Select model instances from Hierarchy.", fill(), fixed(24))
      gui.actionRow("model gizmo modes 1"):
        if gui.selectedButton("model gizmo move", "Move",
            editor.modelGizmoMode == ModelGizmoMove):
          editor.modelGizmoMode = ModelGizmoMove
        if gui.selectedButton("model gizmo rotate", "Rotate",
            editor.modelGizmoMode == ModelGizmoRotate):
          editor.modelGizmoMode = ModelGizmoRotate
      gui.actionRow("model gizmo modes 2"):
        if gui.selectedButton("model gizmo scale", "Scale",
            editor.modelGizmoMode == ModelGizmoScale):
          editor.modelGizmoMode = ModelGizmoScale
        if gui.selectedButton("model gizmo scale all", "Scale All",
            editor.modelGizmoMode == ModelGizmoScaleAll):
          editor.modelGizmoMode = ModelGizmoScaleAll
    if editor.editWorld.selectedModel >= 0 and
        editor.editWorld.selectedModel < editor.editWorld.modelCount:
      var instance = editor.editWorld.model(editor.editWorld.selectedModel)
      var changed = false
      gui.card(gui.id("model transform"), cfg(width = fill(), height = fit(),
          gap = 8, padding = 10)):
        gui.label("Transform", fill(), fit())
        changed = gui.waterNumberInput("model pos x", "Position X",
            instance.position.x, -512, 512) or changed
        changed = gui.waterNumberInput("model pos y", "Position Y",
            instance.position.y, -64, 64) or changed
        changed = gui.waterNumberInput("model pos z", "Position Z",
            instance.position.z, -512, 512) or changed
        changed = gui.waterNumberInput("model rot x", "Rotation X",
            instance.rotation.x, -360, 360) or changed
        changed = gui.waterNumberInput("model rot y", "Rotation Y",
            instance.rotation.y, -360, 360) or changed
        changed = gui.waterNumberInput("model rot z", "Rotation Z",
            instance.rotation.z, -360, 360) or changed
        gui.label("Scale", fill(), fit())
        var scaleAll = instance.scale.x
        let scaleAllChanged = gui.waterNumberInput(
          "model scale all", "Scale All", scaleAll, 0.01, 100, 100, 10
        )
        if scaleAllChanged:
          instance.scale.x = scaleAll
          instance.scale.y = scaleAll
          instance.scale.z = scaleAll
          changed = true
        changed = gui.waterNumberInput(
          "model scale x", "Scale X", instance.scale.x, 0.01, 100, 100, 10
        ) or changed
        changed = gui.waterNumberInput(
          "model scale y", "Scale Y", instance.scale.y, 0.01, 100, 100, 10
        ) or changed
        changed = gui.waterNumberInput(
          "model scale z", "Scale Z", instance.scale.z, 0.01, 100, 100, 10
        ) or changed
      if gui.button(gui.id("delete model"), "Delete Model", fill(), fixed(32)):
        editor.editWorld.deleteModel(editor.editWorld.selectedModel)
        gui.markAllDirty()
      if gui.button(gui.id("duplicate model"), "Duplicate Model", fill(), fixed(32)):
        discard editor.editWorld.duplicateModel(editor.editWorld.selectedModel)
        gui.markAllDirty()
      if changed:
        instance.scale.x = max(instance.scale.x, 0.01'f32)
        instance.scale.y = max(instance.scale.y, 0.01'f32)
        instance.scale.z = max(instance.scale.z, 0.01'f32)
        editor.editWorld.setModel(editor.editWorld.selectedModel, instance)
        gui.markAllDirty()

proc entitySpawnsTabPanelImpl(gui: var UI) =
  gui.column(gui.id("entity spawns body"), cfg(width = fill(), height = fill(),
      gap = 10, padding = 10, scrollY = true)):
    gui.card(gui.id("entity spawns add"), cfg(width = fill(), height = fit(),
        gap = 6, padding = 10)):
      gui.label("Place Entity Spawn", fill(), fit())
      gui.label("Use the middle-mouse cursor to choose the spawn position.",
          fill(), fit())
      for entityID in entityTypes():
        if gui.button(gui.id("add entity spawn", entityID), "Add " & entityID,
            fill(), fixed(30)):
          let position = if editor.placementCursorActive:
            editor.placementCursorPosition else: vec3(0, 0, 0)
          discard editor.editWorld.addEntitySpawn(entityID, position)
          gui.markAllDirty()
    if editor.editWorld.selectedEntitySpawn >= 0 and
        editor.editWorld.selectedEntitySpawn <
            editor.editWorld.entitySpawnCount:
      var spawn = editor.editWorld.entitySpawn(
          editor.editWorld.selectedEntitySpawn)
      var changed = false
      gui.card(gui.id("entity spawn properties"), cfg(width = fill(),
          height = fit(), gap = 8, padding = 10)):
        gui.label("Properties", fill(), fit())
        gui.label("Entity ID: " & spawn.entityID, fill(), fit())
        gui.row(gui.id("entity spawn type"), cfg(width = fill(), height = fit(),
            gap = 6, padding = 0)):
          for entityID in entityTypes():
            let selected = spawn.entityID == entityID
            let style = if selected:
              ComponentStyle(hasBackground: true, background: color(61, 83, 88))
            else: ComponentStyle()
            if gui.button(gui.id("entity spawn type", entityID), entityID,
                fill(), fixed(28), style = style):
              spawn.entityID = entityID
              changed = true
        changed = gui.waterNumberInput("spawn pos x", "Position X",
            spawn.position.x, -512, 512) or changed
        changed = gui.waterNumberInput("spawn pos y", "Position Y",
            spawn.position.y, -64, 64) or changed
        changed = gui.waterNumberInput("spawn pos z", "Position Z",
            spawn.position.z, -512, 512) or changed
      if gui.button(gui.id("delete entity spawn"), "Delete Spawn", fill(),
          fixed(32)):
        editor.editWorld.deleteEntitySpawn(editor.editWorld.selectedEntitySpawn)
        gui.markAllDirty()
      elif changed:
        editor.editWorld.setEntitySpawn(editor.editWorld.selectedEntitySpawn, spawn)
        gui.markAllDirty()

proc waterTabPanelImpl(gui: var UI) =
  gui.column(
    gui.id("water body"),
    cfg(width = fill(), height = fill(), gap = 10, padding = 10,
        scrollY = true),
  ):
    gui.editorCard("water create", "Water"):
      if gui.editorToggle("water visibility", "Show Water", editor.showWater):
        gui.markAllDirty()
      if gui.button(gui.id("water add"), "Add Water Plane", fill(), fixed(32)):
        editor.selectedWaterPlane = editor.editWorld.addWaterPlane()
        gui.markAllDirty()

    gui.editorCard("water list", "Planes"):
      if editor.editWorld.waterPlaneCount == 0:
        gui.label("No water planes", fill(), fixed(28))
      for i, water in editor.editWorld.waterPlanes:
        if gui.selectedButton("water plane " & $i, water.name,
            i == editor.selectedWaterPlane):
          editor.selectedWaterPlane = i

    if editor.selectedWaterPlane < 0 or
        editor.selectedWaterPlane >= editor.editWorld.waterPlaneCount:
      editor.selectedWaterPlane =
        if editor.editWorld.waterPlaneCount > 0: 0 else: -1

    if editor.selectedWaterPlane >= 0:
      var water = editor.editWorld.waterPlane(editor.selectedWaterPlane)
      var changed = false
      gui.editorCard("water transform", "Transform"):
        changed = gui.waterNumberInput("water x", "X", water.position.x, -512,
            512) or
          changed
        changed = gui.waterNumberInput("water y", "Y", water.position.y, -64,
            64) or
          changed
        changed = gui.waterNumberInput("water z", "Z", water.position.z, -512,
            512) or
          changed
        changed = gui.waterNumberInput("water width", "Width", water.size.x, 1,
            2048, 10) or
          changed
        changed = gui.waterNumberInput("water depth", "Depth", water.size.y, 1,
            2048, 10) or
          changed
      gui.editorCard("water waves", "Waves"):
        changed = gui.waterNumberInput(
          "water amplitude", "Amplitude", water.waveAmplitude, 0, 2
        ) or changed
        changed = gui.waterNumberInput(
          "water wavelength", "Wavelength", water.waveLength, 0.5, 64, 10
        ) or changed
        changed = gui.waterNumberInput("water speed", "Speed", water.waveSpeed,
            0, 4) or
          changed
        changed = gui.waterNumberInput(
          "water opacity", "Opacity", water.opacity, 0.05, 1
        ) or changed
        changed = gui.waterNumberInput(
          "water specular", "Specular", water.specularStrength, 0, 2
        ) or changed
      gui.editorCard("water colors", "Color"):
        changed = gui.waterNumberInput(
          "water surface r", "Surface R", water.surfaceColor.x, 0, 1
        ) or changed
        changed = gui.waterNumberInput(
          "water surface g", "Surface G", water.surfaceColor.y, 0, 1
        ) or changed
        changed = gui.waterNumberInput(
          "water surface b", "Surface B", water.surfaceColor.z, 0, 1
        ) or changed
        changed = gui.waterNumberInput("water deep r", "Deep R",
            water.deepColor.x, 0, 1) or
          changed
        changed = gui.waterNumberInput("water deep g", "Deep G",
            water.deepColor.y, 0, 1) or
          changed
        changed = gui.waterNumberInput("water deep b", "Deep B",
            water.deepColor.z, 0, 1) or
          changed
      gui.editorCard("water actions", ""):
        if gui.button(gui.id("water delete"), "Delete Water Plane", fill(),
            fixed(32)):
          editor.editWorld.deleteWaterPlane(editor.selectedWaterPlane)
          editor.selectedWaterPlane = min(
            editor.selectedWaterPlane, editor.editWorld.waterPlaneCount - 1
          )
          gui.markAllDirty()
      if changed:
        water.size.x = max(water.size.x, 1'f32)
        water.size.y = max(water.size.y, 1'f32)
        water.waveLength = max(water.waveLength, 0.5'f32)
        editor.editWorld.setWaterPlane(editor.selectedWaterPlane, water)
        gui.markAllDirty()

proc toNestColor(value: Vec3): nestScreen.Color =
  nestScreen.color(
    clamp(round(value.x * 255'f32).int, 0, 255).uint8,
    clamp(round(value.y * 255'f32).int, 0, 255).uint8,
    clamp(round(value.z * 255'f32).int, 0, 255).uint8,
  )

proc toVec3(value: nestScreen.Color): Vec3 =
  vec3(
    value.r.float32 / 255'f32,
    value.g.float32 / 255'f32,
    value.b.float32 / 255'f32,
  )

proc environmentColorInput(
    gui: var UI, id, label: string, value: var Vec3
): bool {.discardable.} =
  var uiColor = value.toNestColor()
  result = gui.colorInput(gui.id(id), label, uiColor, fill(), fit())
  if result:
    value = uiColor.toVec3()

proc environmentFields(gui: var UI, prefix: string,
    environment: var WorldEnvironment): bool =
  result = gui.environmentColorInput(prefix & " near color", "Near Fog",
      environment.fog.nearColor) or result
  result = gui.environmentColorInput(prefix & " far color", "Far Fog",
      environment.fog.farColor) or result
  result = gui.waterNumberInput(prefix & " density", "Density",
      environment.fog.density, 0, 1, 1000) or result
  result = gui.waterNumberInput(prefix & " falloff", "Falloff",
      environment.fog.falloff, 0.05, 8, 100) or result
  result = gui.waterNumberInput(prefix & " limit", "Limit",
      environment.fog.limit, 1, 4096, 10) or result

proc environmentSkyboxFields(gui: var UI, io: IO, prefix: string,
    environment: var WorldEnvironment): bool =
  result = gui.environmentColorInput(prefix & " horizon color", "Horizon",
      environment.skyHorizonColor) or result
  result = gui.environmentColorInput(prefix & " zenith color", "Zenith",
      environment.skyZenithColor) or result
  result = gui.environmentColorInput(prefix & " ground color", "Ground",
      environment.skyGroundColor) or result
  let previousUseSkybox = environment.useSkybox
  discard gui.editorToggle(prefix & " use skybox", "Use Skybox",
      environment.useSkybox)
  result = previousUseSkybox != environment.useSkybox or result
  result = gui.texturePicker(io, prefix & " skybox texture",
      environment.skyboxPath) or result
  if gui.button(gui.id(prefix & " clear skybox"), "Clear Skybox", fill(),
      fixed(30)):
    environment.skyboxPath = ""
    environment.useSkybox = false
    result = true
  result = gui.waterNumberInput(prefix & " skybox exposure", "Exposure",
      environment.skyboxExposure, 0, 8, 100) or result

proc environmentBoxFields(gui: var UI, prefix: string,
    environment: var WorldEnvironment): bool =
  result = gui.waterNumberInput(prefix & " center x", "Center X",
      environment.boxCenter.x, -2048, 2048) or result
  result = gui.waterNumberInput(prefix & " center y", "Center Y",
      environment.boxCenter.y, -512, 512) or result
  result = gui.waterNumberInput(prefix & " center z", "Center Z",
      environment.boxCenter.z, -2048, 2048) or result
  result = gui.waterNumberInput(prefix & " size x", "Size X",
      environment.boxSize.x, 0.1, 4096) or result
  result = gui.waterNumberInput(prefix & " size y", "Size Y",
      environment.boxSize.y, 0.1, 1024) or result
  result = gui.waterNumberInput(prefix & " size z", "Size Z",
      environment.boxSize.z, 0.1, 4096) or result

proc envTabPanelImpl(gui: var UI, io: IO) =
  gui.column(
    gui.id("environment body"),
    cfg(width = fill(), height = fill(), gap = 10, padding = 10,
        scrollY = true),
  ):
    var globalEnvironment = editor.editWorld.globalEnvironment()
    var globalChanged = false
    gui.card(
      gui.id("global environment"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      gui.label("Global Environment", fill(), fit())
      globalChanged = gui.environmentFields("global environment",
          globalEnvironment)
      globalChanged = gui.environmentSkyboxFields(io, "global environment",
          globalEnvironment) or globalChanged
    if globalChanged:
      globalEnvironment.useSkybox = globalEnvironment.useSkybox and
          globalEnvironment.skyboxPath.len > 0
      globalEnvironment.skyboxExposure = max(globalEnvironment.skyboxExposure,
          0'f32)
      editor.editWorld.setGlobalEnvironment(globalEnvironment)
      gui.markAllDirty()

    gui.card(
      gui.id("local environment create"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      gui.label("Local Environments", fill(), fit())
      if gui.button(gui.id("local environment add"), "Add Environment Volume",
          fill(), fixed(32)):
        editor.selectedLocalEnvironment = editor.editWorld.addLocalEnvironment()
        gui.markAllDirty()

    gui.card(
      gui.id("local environment list"),
      cfg(width = fill(), height = fit(), gap = 6, padding = 10),
    ):
      gui.label("Volumes", fill(), fit())
      if editor.editWorld.localEnvironmentCount == 0:
        gui.label("No local environment volumes", fill(), fixed(28))
      for i, environment in editor.editWorld.localEnvironments:
        if gui.selectedButton("local environment " & $i, environment.name,
            i == editor.selectedLocalEnvironment):
          editor.selectedLocalEnvironment = i

    if editor.selectedLocalEnvironment < 0 or
        editor.selectedLocalEnvironment >=
            editor.editWorld.localEnvironmentCount:
      editor.selectedLocalEnvironment =
        if editor.editWorld.localEnvironmentCount > 0: 0 else: -1

    if editor.selectedLocalEnvironment >= 0:
      var environment =
        editor.editWorld.localEnvironment(editor.selectedLocalEnvironment)
      var changed = false
      gui.card(
        gui.id("local environment box"),
        cfg(width = fill(), height = fit(), gap = 8, padding = 10),
      ):
        gui.label("Box", fill(), fit())
        changed = gui.environmentBoxFields("local environment box",
            environment) or changed
      gui.card(
        gui.id("local environment fog"),
        cfg(width = fill(), height = fit(), gap = 8, padding = 10),
      ):
        gui.label("Fog", fill(), fit())
        changed = gui.environmentFields("local environment fog",
            environment) or changed
      gui.card(
        gui.id("local environment skybox"),
        cfg(width = fill(), height = fit(), gap = 8, padding = 10),
      ):
        gui.label("Skybox", fill(), fit())
        changed = gui.environmentSkyboxFields(io, "local environment skybox",
            environment) or changed
      gui.card(
        gui.id("local environment actions"),
        cfg(width = fill(), height = fit(), gap = 8, padding = 10),
      ):
        if gui.button(gui.id("local environment delete"),
            "Delete Environment Volume", fill(), fixed(32)):
          editor.editWorld.deleteLocalEnvironment(
              editor.selectedLocalEnvironment)
          editor.selectedLocalEnvironment = min(
            editor.selectedLocalEnvironment,
            editor.editWorld.localEnvironmentCount - 1,
          )
          gui.markAllDirty()
      if changed:
        environment.boxSize.x = max(environment.boxSize.x, 0.1'f32)
        environment.boxSize.y = max(environment.boxSize.y, 0.1'f32)
        environment.boxSize.z = max(environment.boxSize.z, 0.1'f32)
        environment.fog.density = max(environment.fog.density, 0'f32)
        environment.fog.falloff = max(environment.fog.falloff, 0.05'f32)
        environment.fog.limit = max(environment.fog.limit, 1'f32)
        environment.useSkybox = environment.useSkybox and
            environment.skyboxPath.len > 0
        environment.skyboxExposure = max(environment.skyboxExposure, 0'f32)
        editor.editWorld.setLocalEnvironment(
          editor.selectedLocalEnvironment, environment
        )
        gui.markAllDirty()

proc meshPanelTabButton(gui: var UI, tab: MeshPanelTab, label: string) =
  if gui.selectedButton("mesh panel tab " & label, label,
      editor.meshPanelTab == tab.int):
    editor.meshPanelTab = tab.int
    gui.markAllDirty()

proc meshPanelImpl*(gui: var UI, io: IO) =
  gui.panel(
    gui.id("mesh panel"),
    cfg(
      width = fixed(320),
      height = fill(),
      gap = 0,
      padding = 0,
      style = ComponentStyle(hasBackground: true, background: color(31, 38,
          39, 190)),
    ),
  ):
    gui.panelHeader("mesh panel", "Meshes")
    gui.column(
      gui.id("mesh panel tab rows"),
      cfg(width = fill(), height = fit(), gap = 4, padding = 6),
    ):
      gui.row(
        gui.id("mesh panel tab row 1"),
        cfg(width = fill(), height = fit(), gap = 6, padding = 0),
      ):
        gui.meshPanelTabButton(TerrainTab, "Terrain")
        gui.meshPanelTabButton(WorldMeshesTab, "Mesh")
        gui.meshPanelTabButton(ModelsTab, "Model")
        gui.meshPanelTabButton(SpawnsTab, "Spawn")
      gui.row(
        gui.id("mesh panel tab row 2"),
        cfg(width = fill(), height = fit(), gap = 6, padding = 0),
      ):
        gui.meshPanelTabButton(WaterTab, "Water")
        gui.meshPanelTabButton(EnvTab, "Env")
    case MeshPanelTab(editor.meshPanelTab)
    of TerrainTab:
      gui.terrainTabPanelImpl(io)
    of WorldMeshesTab:
      gui.worldMeshesTabPanelImpl()
    of ModelsTab:
      gui.modelsTabPanelImpl()
    of SpawnsTab:
      gui.entitySpawnsTabPanelImpl()
    of WaterTab:
      gui.waterTabPanelImpl()
    of EnvTab:
      gui.envTabPanelImpl(io)

proc editorPanelsImpl(gui: var UI, io: IO) =
  gui.row(
    gui.id("editor workspace"),
    cfg(
      width = fill(),
      height = fill(),
      gap = 0,
      padding = 0,
      style = ComponentStyle(hasBackground: true, background: color(18, 22,
          24, 120)),
    ),
  ):
    if editor.showHierarchyPanel:
      gui.hierarchyPanelImpl()
    gui.spacer(fill(), fill())
    if editor.editWorld.meshCount > 0 and
        editor.meshEditor.selectedTriangles.len > 0:
      gui.uvMappingPanel(io)
    if editor.showMeshPanel:
      gui.meshPanelImpl(io)
    if editor.showRenderTargetsPanel:
      gui.renderTargetsPanel()

widget terrainCursorButton*(
    id, label: string, dx, dz: int, width = TerrainCursorButtonWidth
):
  terrainCursorButtonImpl(ui, id, label, dx, dz, width)

widget hierarchyPanel*():
  hierarchyPanelImpl(ui)

widget terrainTabPanel*(io: IO):
  terrainTabPanelImpl(ui, io)

widget worldMeshesTabPanel*():
  worldMeshesTabPanelImpl(ui)

widget modelsTabPanel*():
  modelsTabPanelImpl(ui)

widget entitySpawnsTabPanel*():
  entitySpawnsTabPanelImpl(ui)

widget waterTabPanel*():
  waterTabPanelImpl(ui)

widget envTabPanel*(io: IO):
  envTabPanelImpl(ui, io)

widget meshPanel*(io: IO):
  meshPanelImpl(ui, io)

widget editorPanels*(io: IO):
  editorPanelsImpl(ui, io)
