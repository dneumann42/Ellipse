import std/[os, strutils, times]
import ellipse
import sdl3 except Vertex
import ellipse/worlds/registry

import state, fps, persistence

template dropDownMenu*(menuKey: string, menuText: string, state: var bool,
    blk: untyped) =
  if menu(ui, id(ui, menuKey), menuText, fit(), fill()):
    state = not state
    markAllDirty(ui)
    requestRedrawAfter(ui, 0)
  if state:
    floatingCardBelow(ui,
      id(ui, menuKey, "popover"),
      id(ui, menuKey),
      cfg(width = fixed(220), height = fit(), gap = 0, padding = 6),
    ):
      let parentId {.inject.} = menuKey
      blk

template dropDownMenuItem*(itemKey: string, itemText: string, blk: untyped) =
  block:
    scope(ui, parentId):
      scope(ui, itemKey):
        let itemID {.inject.} = id(ui)
        menuItem(ui,
          itemID,
          cfg(width = fill(), height = fixed(28), padding = 4,
              alignItems = Center),
        ):
          label(ui, itemText, fill(), fit())
        let clicked {.inject.} = inEventPhase(ui) and clicked(ui, itemID)
        blk

template dropDownCheckboxMenuItem*(
    itemKey: string, itemText: string, checkedState: bool, blk: untyped
) =
  block:
    scope(ui, parentId):
      scope(ui, itemKey):
        let itemID {.inject.} = id(ui)
        menuItem(ui,
          itemID,
          cfg(width = fill(), height = fixed(28), padding = 4,
              alignItems = Center),
        ):
          checkbox(ui, itemText, checkedState, fill(), fit())
        let clicked {.inject.} = inEventPhase(ui) and clicked(ui, itemID)
        blk

widget editorMenuBarFileMenu*(
  sceneStack: var SceneStack,
  running: var bool,
  worldRegistry: var WorldsRegistry,
):
  dropDownMenu("file menu", "File", editor.showFileMenu):
    dropDownMenuItem("new", "New World"):
      if clicked:
        editor.newWorldDialog.worldName.text = ""
        editor.newWorldDialog.worldName.cursor = 0
        ui.openDialog(editor.newWorldDialog.show)
        editor.showFileMenu = false
    dropDownMenuItem("open", "Open World"):
      if clicked:
        ui.openDialog(editor.openWorldDialog.show)
        editor.showFileMenu = false
    ui.menuDivider(ui.id("file menu divider"), fill(), fixed(9))
    dropDownMenuItem("save", "Save World"):
      if clicked:
        if validWorldID(editor.editWorld.name):
          discard saveEditorWorldToDisk(worldRegistry)
        else:
          editor.saveWorldDialog.worldName.text = ""
          editor.saveWorldDialog.worldName.cursor = 0
          ui.openDialog(editor.saveWorldDialog.show)
        editor.showFileMenu = false
    dropDownMenuItem("save as", "Save As"):
      if clicked:
        editor.saveWorldDialog.worldName.text = editor.editWorld.name
        editor.saveWorldDialog.worldName.cursor =
          editor.saveWorldDialog.worldName.text.len
        ui.openDialog(editor.saveWorldDialog.show)
        editor.showFileMenu = false
    ui.menuDivider(ui.id("file menu divider 2"), fill(), fixed(9))
    dropDownMenuItem("quit menu", "Quit to Menu"):
      if clicked:
        sceneStack.push("MainMenuScene")
    dropDownMenuItem("quit desktop", "Quit to Desktop"):
      if clicked:
        running = false
widget editorMenuBarViewMenu*():
  dropDownMenu("view menu", "View", editor.showViewMenu):
    dropDownCheckboxMenuItem("solid mesh", "Solid", editor.showSolidMesh):
      if clicked:
        editor.showSolidMesh = not editor.showSolidMesh
        ui.markAllDirty()
    dropDownCheckboxMenuItem("wireframe mesh", "Wireframe",
        editor.showWireframeMesh):
      if clicked:
        editor.showWireframeMesh = not editor.showWireframeMesh
        ui.markAllDirty()
    ui.menuDivider(ui.id("view visual modes divider"), fill(), fixed(9))
    dropDownCheckboxMenuItem("hierarchy", "Hierarchy",
        editor.showHierarchyPanel):
      if clicked:
        editor.showHierarchyPanel = not editor.showHierarchyPanel
        ui.markAllDirty()
    dropDownCheckboxMenuItem("meshes", "Meshes", editor.showMeshPanel):
      if clicked:
        editor.showMeshPanel = not editor.showMeshPanel
        ui.markAllDirty()
    dropDownCheckboxMenuItem("render targets", "Render Targets",
        editor.showRenderTargetsPanel):
      if clicked:
        editor.showRenderTargetsPanel = not editor.showRenderTargetsPanel
        ui.markAllDirty()

widget editorMenuBarPluginMenu*(io: IO, pluginControls: PluginControls):
  dropDownMenu("plugin menu", "Plugins", editor.showPlugins):
    dropDownMenuItem("plugin menu load", "Load Plugin"):
      if clicked:
        if not io.files.pick(ui.id("plugin menu", "load picker"), getHomeDir()):
          echo io.files.error(ui.id("plugin menu", "load picker"))
      block:
        let pickedPlugin = io.files.value(ui.id("plugin menu", "load picker"))
        if pickedPlugin.len > 0:
          io.files.clear(ui.id("plugin menu", "load picker"))
    ui.menuDivider(ui.id("plugin menu divider"), fill(), fixed(9))
    for plugin in pluginControls.plugins:
      ui.row(
        ui.id("plugin menu " & plugin),
        cfg(width = fill(), height = fit(), gap = 8, padding = 8),
      ):
        ui.label(
          ui.id("plugin menu label " & plugin), plugin, width = fit(),
              height = fit()
        )
        if ui.button(
          ui.id("plugin menu reload " & plugin),
          "Reload",
          width = fit(),
          height = fit(),
        ):
          pluginControls.reload plugin

proc pluginBuildOutput*(pluginControls: PluginControls): string =
  result = $pluginControls.lastOutput()
  let error = $pluginControls.lastError()
  if error.len > 0 and result.len == 0:
    result = error
  if result.len == 0:
    result = "No compiler output."

widget pluginBuildNotification*(pluginControls: PluginControls):
  let status = $pluginControls.buildStatus()
  if status notin ["building", "failed", "ready"]:
    return
  let
    compiling = status == "building"
    failed = status == "failed"
    spinnerFrames = ["|", "/", "-", "\\"]
    spinner = spinnerFrames[(epochTime() * 8).int mod spinnerFrames.len]
    label =
      if compiling:
        spinner & " Building"
      elif failed:
        "Build Failed"
      else:
        "Activating"
    style =
      if failed:
        ComponentStyle(hasBackground: true, background: color(132, 45, 45))
      else:
        ComponentStyle(hasBackground: true, background: color(78, 113, 112))
  if compiling:
    pluginControls.requestFrame()
  if ui.button(
    ui.id("plugin build notification"), label, fit(), fill(), style = style
  ):
    editor.pluginBuildOutput.text = pluginBuildOutput(pluginControls)
    editor.pluginBuildOutput.cursor = 0
    ui.openDialog(editor.showPluginBuildOutput)

widget pluginBuildOutputDialog*(pluginControls: PluginControls):
  if editor.showPluginBuildOutput:
    editor.pluginBuildOutput.text = pluginBuildOutput(pluginControls)
    editor.pluginBuildOutput.clampCursor()
  ui.modalDialog(
    ui.id("plugin build output dialog"),
    editor.showPluginBuildOutput,
    cfg(width = fixed(760), height = fixed(500), gap = 0, padding = 0),
  ):
    ui.dialogHeader(
      ui.id("plugin build output dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      ui.label(
        ui.id("plugin build output dialog title"), "Compiler Output", fill(),
            fit()
      )
      if ui.button(ui.id("plugin build output close"), "Close", fit(), fit()):
        ui.closeDialog(editor.showPluginBuildOutput)
    ui.column(
      ui.id("plugin build output dialog body"),
      cfg(width = fill(), height = fill(), gap = 8, padding = 10),
    ):
      ui.textEditor(
        ui.id("plugin build output text"),
        editor.pluginBuildOutput,
        fill(),
        fill(),
        fontName = "font",
        scrollbars = true,
      )

widget fpsDialog*():
  ui.modalDialog(
    ui.id("fps dialog"),
    editor.showFpsDialog,
    cfg(width = fixed(720), height = fixed(420), gap = 0, padding = 0),
  ):
    ui.dialogHeader(
      ui.id("fps dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      ui.label(ui.id("fps dialog title"), "FPS", fill(), fit())
      if ui.button(ui.id("fps dialog close"), "Close", fit(), fit()):
        ui.closeDialog(editor.showFpsDialog)
    ui.column(
      ui.id("fps dialog body"),
      cfg(width = fill(), height = fill(), gap = 8, padding = 10),
    ):
      ui.row(
        ui.id("fps controls"),
        cfg(width = fill(), height = fit(), gap = 8, padding = 0),
      ):
        if ui.button(ui.id("fps save snapshot"), "Save Snapshot", fit(),
            fixed(30)):
          editor.fpsSnapshotMessage = saveFpsSnapshot()
      if editor.fpsSnapshotMessage.len > 0:
        ui.label(
          ui.id("fps snapshot message"),
          editor.fpsSnapshotMessage,
          fill(),
          fixed(24),
          textScroll = true,
        )
      ui.fpsChart(ui.id("fps chart"), fill(), fill())

proc fpsLabel*(): string =
  if editor.fpsSamples.len == 0:
    return "FPS --"
  var total = 0.0
  let first = max(0, editor.fpsSamples.len - FpsLabelAverageFrames)
  for i in first .. editor.fpsSamples.high:
    let sample = editor.fpsSamples[i]
    total += sample.dt
  if total <= 0:
    return "FPS --"
  let fps = (editor.fpsSamples.len - first).float64 / total
  "FPS " & fps.formatFloat(ffDecimal, 1)

proc recordFrameTime*(updateDt: float64) =
  if updateDt <= 0:
    return
  let now = getPerformanceCounter()
  if editor.fpsCounterFrequency == 0:
    editor.fpsCounterFrequency = getPerformanceFrequency()
  if editor.fpsLastCounter == 0 or editor.fpsCounterFrequency == 0:
    editor.fpsLastCounter = now
    return
  let elapsedCounters =
    if now >= editor.fpsLastCounter:
      now - editor.fpsLastCounter
    else:
      0'u64
  editor.fpsLastCounter = now
  if elapsedCounters == 0:
    return
  let dt = elapsedCounters.float64 / editor.fpsCounterFrequency.float64
  if dt <= 0:
    return
  editor.fpsClock += dt
  editor.fpsSamples.add (editor.fpsClock, dt)
  let cutoff = editor.fpsClock - fpsHistorySeconds()
  var first = 0
  while first < editor.fpsSamples.len and editor.fpsSamples[first].t < cutoff:
    inc first
  if first > 0:
    if first >= editor.fpsSamples.len:
      editor.fpsSamples.setLen(0)
    elif first >= FpsTrimBatch:
      editor.fpsSamples = editor.fpsSamples[first .. ^1]

proc updateFpsWidget*(pluginControls: PluginControls) =
  if editor.fpsWidgetID == InvalidWidgetID:
    return
  pluginControls.setWidgetTextValue(editor.fpsWidgetID, fpsLabel())

widget editorMenuBar*(
  io: IO,
  pluginControls: PluginControls,
  sceneStack: var SceneStack,
  running: var bool,
  worldRegistry: var WorldsRegistry,
):
  ui.menuBar(
    ui.id("menu"), cfg(width = fill(), height = fixed(32), gap = 4, padding = 4)
  ):
    ui.row(
      ui.id("menu left"),
      cfg(width = fill(), height = fill(), gap = 4, padding = 0),
    ):
      ui.editorMenuBarFileMenu(sceneStack, running, worldRegistry)
      ui.editorMenuBarViewMenu()
      ui.editorMenuBarPluginMenu(io, pluginControls)
    ui.spacer(ui.id("spacer"), fill(), fixed(1))
    if ui.button(ui.id("play game"), "Play", fixed(72), fill()):
      sceneStack.push("GameScene")
    ui.row(
      ui.id("menu right"),
      cfg(width = fill(), height = fill(), gap = 4, padding = 0,
          justifyContent = End),
    ):
      if ui.button(ui.id("reload editor plugin"), "Reload Editor", fit(), fill()):
        discard pluginControls.reload("Editor")
        ui.markAllDirty()
        ui.requestRedrawAfter(0)
      ui.pluginBuildNotification(pluginControls)
      editor.fpsWidgetID = ui.id("fps")
      if ui.button(editor.fpsWidgetID, "", fixed(92), fill()):
        ui.openDialog(editor.showFpsDialog)
