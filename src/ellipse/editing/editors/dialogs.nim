import std/strutils
import ellipse
import ellipse/worlds/worlds
import ellipse/worlds/registry
import ellipse/editing/worldMeshEditing

import state
import persistence

proc createWorld*(worldRegistry: var WorldsRegistry, editor: var state.Editor,
    state: EditorNewWorldDialog) =
  let worldID = state.worldName.text.strip().WorldID
  if not validWorldID(worldID):
    return
  editor.editWorldID = worldID
  editor.editWorld = World.init(worldID)
  editor.meshEditor.selectMesh(editor.editWorld, editor.editWorld.selectedMesh)
  discard saveEditorWorldToDisk(worldRegistry)

proc saveWorldAs*(worldRegistry: var WorldsRegistry, editor: var state.Editor,
    state: EditorSaveWorldDialog) =
  let worldID = state.worldName.text.strip().WorldID
  if not validWorldID(worldID):
    return
  editor.editWorld.name = worldID
  editor.editWorldID = worldID
  discard saveEditorWorldToDisk(worldRegistry)

proc resetConfirmation*(state: var ConfirmationDialog) =
  state.show = false
  state.title = "Confirm"
  state.message = ""
  state.confirmLabel = "Confirm"
  state.cancelLabel = "Cancel"
  state.action = NoConfirmationAction
  state.meshIndex = -1

proc requestConfirmation*(
    gui: var UI,
    state: var ConfirmationDialog,
    title, message: string,
    action: ConfirmationAction,
    confirmLabel = "Confirm",
    cancelLabel = "Cancel",
    meshIndex = -1,
) =
  state.title = title
  state.message = message
  state.confirmLabel = confirmLabel
  state.cancelLabel = cancelLabel
  state.action = action
  state.meshIndex = meshIndex
  gui.openDialog(state.show)

proc applyConfirmation*(editor: var state.Editor,
    state: var ConfirmationDialog) =
  case state.action
  of DeleteMeshConfirmationAction:
    let index = state.meshIndex
    editor.editWorld.deleteMesh(index)
    editor.meshEditId = 0
    if editor.editWorld.meshCount > 0:
      let selected = editor.editWorld.selectedMesh
      editor.meshEditor.selectMesh(editor.editWorld, selected)
      if editor.editWorld.meshKind(selected) == TerrainWorldMesh:
        let region = editor.editWorld.terrainCellForMesh(selected)
        editor.terrainPanel.cellX = region.cellX
        editor.terrainPanel.cellZ = region.cellZ
    else:
      editor.meshEditor.selectMesh(editor.editWorld,
          editor.editWorld.selectedMesh)
  of NoConfirmationAction:
    discard
  state.resetConfirmation()

proc openWorld*(worldRegistry: var WorldsRegistry, editor: var state.Editor,
    worldID: WorldID) =
  worldRegistry.load(worldID)
  editor.editWorldID = worldID
  editor.editWorld = worldRegistry.getOrDefault(worldID)
  editor.cachedWorldRevision = high(uint64)
  editor.cachedWaterMeshReady = false
  editor.meshEditor.selectMesh(editor.editWorld, editor.editWorld.selectedMesh)

widget confirmationDialog*(state: var ConfirmationDialog) -> bool:
  ui.modalDialog(
    ui.id("confirmation dialog"),
    state.show,
    cfg(width = fixed(380), height = fit(), gap = 0, padding = 0),
  ):
    ui.dialogHeader(
      ui.id("confirmation dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      ui.label(ui.id("confirmation dialog title"), state.title, fill(), fit())
      if ui.button(ui.id("confirmation dialog close"), "Close", fit(), fit()):
        state.resetConfirmation()
    ui.column(
      ui.id("confirmation dialog body"),
      cfg(width = fill(), height = fit(), gap = 10, padding = 10),
    ):
      ui.label(ui.id("confirmation dialog message"), state.message, fill(),
          fit())
      ui.row(
        ui.id("confirmation dialog actions"),
        cfg(
          width = fill(),
          height = fit(),
          gap = 8,
          padding = 0,
          justifyContent = End,
        ),
      ):
        if ui.button(ui.id("confirmation dialog cancel"), state.cancelLabel,
            fit(), fixed(30)):
          state.resetConfirmation()
        if ui.button(ui.id("confirmation dialog confirm"), state.confirmLabel,
            fit(), fixed(30)):
          result = true
          ui.closeDialog(state.show)

proc fuzzyMatch*(needle, haystack: string): bool =
  let query = needle.normalize.toLowerAscii
  if query.len == 0:
    return true

  let candidate = haystack.normalize.toLowerAscii
  var queryIndex = 0
  for ch in candidate:
    if ch == query[queryIndex]:
      inc queryIndex
      if queryIndex == query.len:
        return true
  false

widget newWorldDialog*(state: var EditorNewWorldDialog) -> bool:
  ui.modalDialog(
    ui.id("new world dialog"),
    state.show,
    cfg(width = fixed(360), height = fit(), gap = 0, padding = 0),
  ):
    ui.dialogHeader(
      ui.id("new world dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      ui.label(ui.id("new world dialog title"), "New World", fill(), fit())
      if ui.button(ui.id("new world dialog close"), "Close", fit(), fit()):
        ui.closeDialog(state.show)
    ui.column(
      ui.id("new world dialog body"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      ui.label(ui.id("new world name label"), "World Name", fill(), fit())
      ui.lineInput(ui.id("new world name input"), state.worldName, fill(),
          fixed(32))
      ui.row(
        ui.id("new world dialog actions"),
        cfg(
          width = fill(),
          height = fit(),
          gap = 8,
          padding = 0,
          justifyContent = End,
        ),
      ):
        if ui.button(ui.id("new world cancel"), "Cancel", fit(), fit()):
          ui.closeDialog(state.show)
        if ui.button(ui.id("new world create"), "Create", fit(), fit()):
          result = true
          ui.closeDialog(state.show)
        if ui.submitted(ui.id("new world name input")):
          result = true
          ui.closeDialog(state.show)

widget saveWorldDialog*(state: var EditorSaveWorldDialog) -> bool:
  ui.modalDialog(
    ui.id("save world dialog"),
    state.show,
    cfg(width = fixed(360), height = fit(), gap = 0, padding = 0),
  ):
    ui.dialogHeader(
      ui.id("save world dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      ui.label(ui.id("save world dialog title"), "Save World As", fill(), fit())
      if ui.button(ui.id("save world dialog close"), "Close", fit(), fit()):
        ui.closeDialog(state.show)
    ui.column(
      ui.id("save world dialog body"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      ui.label(ui.id("save world name label"), "World Name", fill(), fit())
      ui.lineInput(ui.id("save world name input"), state.worldName, fill(),
          fixed(32))
      ui.row(
        ui.id("save world dialog actions"),
        cfg(
          width = fill(),
          height = fit(),
          gap = 8,
          padding = 0,
          justifyContent = End,
        ),
      ):
        if ui.button(ui.id("save world cancel"), "Cancel", fit(), fit()):
          ui.closeDialog(state.show)
        if ui.button(ui.id("save world save"), "Save", fit(), fit()):
          result = true
          ui.closeDialog(state.show)
        if ui.submitted(ui.id("save world name input")):
          result = true
          ui.closeDialog(state.show)

widget openWorldDialog*(
    state: var EditorOpenWorldDialog, worldIDs: openArray[WorldID]
) -> WorldID:
  ui.modalDialog(
    ui.id("open world dialog"),
    state.show,
    cfg(width = fixed(420), height = fit(), gap = 0, padding = 0),
  ):
    ui.dialogHeader(
      ui.id("open world dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      ui.label(ui.id("open world dialog title"), "Open World", fill(), fit())
      if ui.button(ui.id("open world dialog close"), "Close", fit(), fit()):
        ui.closeDialog(state.show)
    ui.column(
      ui.id("open world dialog body"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      ui.lineInput(ui.id("open world search"), state.search, fill(), fixed(32))
      ui.column(
        ui.id("open world list"),
        cfg(width = fill(), height = fixed(260), gap = 2, padding = 4,
            scrollY = true),
      ):
        var hasMatches = false
        for worldID in worldIDs:
          if not fuzzyMatch(state.search.text, worldID):
            continue
          hasMatches = true
          let selected = worldID == editor.editWorldID
          let itemConfig =
            if selected:
              cfg(
                width = fill(),
                height = fixed(30),
                padding = 6,
                alignItems = Center,
              )
                .withBackground(color(42, 48, 52))
            else:
              cfg(
                width = fill(),
                height = fixed(30),
                padding = 6,
                alignItems = Center,
              )
          ui.menuItem(ui.id("open world item", worldID), itemConfig):
            ui.label(
              ui.id("open world item label", worldID),
              worldID,
              fill(),
              fit(),
              textScroll = true,
            )
          if ui.inEventPhase() and
              ui.clicked(ui.id("open world item", worldID)):
            result = worldID
            ui.closeDialog(state.show)
        if not hasMatches:
          ui.label(ui.id("open world empty"), "No worlds found", fill(),
              fixed(30))

widget editorOpenWorldDialog*(worldRegistry: var WorldsRegistry):
  let selectedWorldID =
    ui.openWorldDialog(editor.openWorldDialog, worldRegistry.worldIDs())
  if selectedWorldID.len > 0:
    worldRegistry.openWorld(editor, selectedWorldID)

proc sourceWorldPtr(worldRegistry: var WorldsRegistry,
    worldID: WorldID): ptr World =
  if worldID == editor.editWorldID:
    addr editor.editWorld
  else:
    worldRegistry.getPtr(worldID)

widget modelPickerDialog*(
    state: var EditorModelPickerDialog,
    worldRegistry: var WorldsRegistry,
) -> bool:
  ui.modalDialog(
    ui.id("model picker dialog"), state.show,
    cfg(width = fixed(420), height = fit(), gap = 0, padding = 0),
  ):
    ui.dialogHeader(ui.id("model picker header"),
        cfg(width = fill(), height = fixed(36), gap = 8, padding = 8)):
      let title = if state.stage == PickModelWorld: "Add Model - World" else:
        "Add Model - Model"
      ui.label(ui.id("model picker title"), title, fill(), fit())
      if ui.button(ui.id("model picker close"), "Close", fit(), fit()):
        state.show = false
    ui.column(ui.id("model picker body"),
        cfg(width = fill(), height = fit(), gap = 8, padding = 10)):
      ui.lineInput(ui.id("model picker search"), state.search, fill(), fixed(32))
      ui.column(ui.id("model picker list"),
          cfg(width = fill(), height = fixed(260), gap = 2, padding = 4,
              scrollY = true)):
        if state.stage == PickModelWorld:
          var hasMatches = false
          for sourceWorldID in editor.cachedSourceWorldIDs:
            if not fuzzyMatch(state.search.text, sourceWorldID): continue
            hasMatches = true
            ui.menuItem(ui.id("model picker world", sourceWorldID),
                cfg(width = fill(), height = fixed(30), padding = 6,
                    alignItems = Center)):
              ui.label(ui.id("model picker world label", sourceWorldID),
                  sourceWorldID, fill(), fit(), textScroll = true)
            if ui.inEventPhase() and ui.clicked(
                ui.id("model picker world", sourceWorldID)):
              state.worldID = sourceWorldID
              state.stage = PickModelMesh
              state.search.text = ""
              state.search.cursor = 0
          if not hasMatches:
            ui.label(ui.id("model picker no worlds"), "No worlds found", fill(),
                fixed(30))
        else:
          var hasMatches = false
          let sourceWorld = sourceWorldPtr(worldRegistry, state.worldID)
          if not sourceWorld.isNil:
            for sourceMesh in sourceWorld[].meshes:
              if sourceMesh.kind != OtherWorldMesh or
                  not fuzzyMatch(state.search.text, sourceMesh.name): continue
              hasMatches = true
              ui.menuItem(ui.id("model picker mesh", sourceMesh.name),
                  cfg(width = fill(), height = fixed(30), padding = 6,
                      alignItems = Center)):
                ui.label(ui.id("model picker mesh label", sourceMesh.name),
                    sourceMesh.name, fill(), fit(), textScroll = true)
              if ui.inEventPhase() and ui.clicked(
                  ui.id("model picker mesh", sourceMesh.name)):
                editor.editWorld.selectedModel = editor.editWorld.addModel(
                    state.worldID, sourceMesh.name,
                    position = placementCursorPosition())
                state.show = false
          if not hasMatches:
            ui.label(ui.id("model picker no models"), "No models found", fill(),
                fixed(30))
      if state.stage == PickModelMesh:
        if ui.button(ui.id("model picker back"), "Back", fit(), fixed(30)):
          state.stage = PickModelWorld
          state.search.text = ""
          state.search.cursor = 0
