import std/[math, os, sets, strutils, tables]
import sdl3
import ellipse
import nest/coords
import vmath
import ellipse/worlds/worlds
import ellipse/editing/worldMeshEditing

import state

const
  EditorAccent* = color(78, 113, 112)
  EditorSelection* = color(61, 83, 88)
  EditorCardBackground* = color(37, 45, 48)

proc selectedStyle*(selected: bool,
    background = EditorAccent): ComponentStyle =
  if selected:
    ComponentStyle(hasBackground: true, background: background)
  else:
    ComponentStyle()

widget panelHeader*(key, title: string):
  ui.scope(key):
    ui.dialogHeader(
      ui.id("header"),
      cfg(
        width = fill(), height = fixed(34), gap = 8, padding = 8,
            alignItems = Center
      ),
    ):
      ui.label(title, fill(), fit())

widget editorCard*(key, title: string, body: untyped):
  ui.scope(key):
    ui.card(
      ui.id("card"),
      cfg(width = fill(), height = fit(), gap = 8, padding = 10),
    ):
      if title.len > 0:
        ui.label(ui.id("title"), title, fill(), fit())
      body

widget metricRow*(key, label, value: string):
  ui.scope(key):
    ui.row(
      ui.id("row"),
      cfg(
        width = fill(), height = fixed(24), gap = 8, padding = 0,
            alignItems = Center
      ),
    ):
      ui.label(ui.id("label"), label, fill(), fit())
      ui.label(ui.id("value"), value, fit(), fit())

widget actionRow*(key: string, body: untyped):
  ui.scope(key):
    ui.row(
      ui.id("row"),
      cfg(width = fill(), height = fit(), gap = 6, padding = 0),
    ):
      body

widget selectedButton*(key, label: string, selected: bool) -> bool:
  result = ui.button(
    ui.id(key), label, fill(), fixed(30), style = selectedStyle(selected)
  )

widget editorToggle*(key, label: string, value: var bool) -> bool:
  let id = ui.id(key)
  ui.checkbox(id, label, value, fill(), fixed(28))
  if ui.inEventPhase and ui.clicked(id):
    value = not value
    result = true

proc ensureTerrainTextureMaterial*(): int

proc toolButtonImpl(gui: var UI, tool: TerrainTool, label: string) =
  if gui.selectedButton("terrain tool " & label, label,
      editor.meshEditor.terrainTool == tool):
    editor.meshEditor.terrainTool = tool
    if tool == Paint:
      discard ensureTerrainTextureMaterial()

proc terrainToolModeButtonImpl(gui: var UI, mode: TerrainToolMode, label: string) =
  if gui.selectedButton("terrain tool mode " & label, label,
      editor.meshEditor.terrainToolMode == mode):
    editor.meshEditor.terrainToolMode = mode

proc editModeButtonImpl(gui: var UI, mode: WorldMeshEditMode, label: string) =
  if gui.selectedButton("world mesh edit mode " & label, label,
      editor.meshEditor.editMode == mode):
    if editor.editWorld.meshCount == 0:
      editor.meshEditor.clearSelection()
      return
    editor.meshEditor.editMode = mode
    editor.meshEditor.clearSelection()

proc meshKindLabel*(kind: WorldMeshKind): string =
  case kind
  of TerrainWorldMesh: "Terrain"
  of OtherWorldMesh: "World Mesh"

proc formattedNumber(value: float32, precision: float32): string =
  $(round(value * precision) / precision)

proc setNumberInputText(input: LineInputState, text: string) =
  if input.text == text:
    return
  input.text = text
  input.cursor = text.len
  input.selectionAnchor = -1
  input.undoStack.setLen(0)
  input.redoStack.setLen(0)
  input.preferredColumn = -1

proc altModifierDown(): bool =
  if (getModState().uint32 and KMOD_ALT) != 0:
    return true
  var keyCount: cint
  let keyboard = getKeyboardState(keyCount)
  not keyboard.isNil and keyCount > SCANCODE_RALT.int and
    (keyboard[SCANCODE_LALT.int] or keyboard[SCANCODE_RALT.int])

proc waterNumberInputImpl(
    gui: var UI,
    id, label: string,
    value: var float32,
    minimum, maximum: float64,
    precision = 10'f32,
    altStepMultiplier = 10'f32,
): bool =
  let previous = value
  let step = 1'f32 / precision *
      (if altStepMultiplier != 1'f32 and altModifierDown():
        altStepMultiplier
      else:
        1'f32)
  gui.scope(id):
    if id notin editor.waterNumberInputs:
      editor.waterNumberInputs[id] = LineInputState.new(
        value.formattedNumber(precision)
      )
    let input = editor.waterNumberInputs[id]
    let inputID = gui.id("input")
    let focused = gui.focused(inputID)
    if not focused:
      input.setNumberInputText(value.formattedNumber(precision))
    gui.column(gui.id(), cfg(width = fill(), height = fit(), gap = 4, padding = 0)):
      gui.label(label, fill(), fit())
      gui.row(
        gui.id("number input row"),
        cfg(width = fill(), height = fixed(30), gap = 4, padding = 0),
      ):
        if gui.button(gui.id("decrement"), "-", fixed(30), fill()):
          value = clamp(value - step, minimum.float32, maximum.float32)
          input.setNumberInputText(value.formattedNumber(precision))
        gui.lineInput(inputID, input, fill(), fill())
        if gui.button(gui.id("increment"), "+", fixed(30), fill()):
          value = clamp(value + step, minimum.float32, maximum.float32)
          input.setNumberInputText(value.formattedNumber(precision))
      if gui.inEventPhase:
        let drag = gui.middleDragDelta(inputID)
        if drag.started:
          editor.numberDragStartValues[id] = value
        if drag.active and id in editor.numberDragStartValues:
          value = clamp(editor.numberDragStartValues[id] +
              drag.deltaX.float32 * step, minimum.float32, maximum.float32)
          input.setNumberInputText(value.formattedNumber(precision))
        try:
          let parsed = input.text.strip.parseFloat.float32
          value = clamp(parsed, minimum.float32, maximum.float32)
          if input.text.strip.len > 0 and not focused and
              abs(value - parsed) > 0.000001'f32:
            input.setNumberInputText(value.formattedNumber(precision))
        except ValueError:
          discard
  abs(value - previous) > 0.000001'f32

proc terrainSliderImpl(
    gui: var UI,
    id, label: string,
    value: var float32,
    minimum, maximum: float64,
    precision = 10'f32,
) =
  gui.scope(id):
    let sliderID = gui.id("slider")
    let inputID = gui.id("input")
    if id notin editor.sliderNumberInputs:
      editor.sliderNumberInputs[id] = LineInputState.new(
        value.formattedNumber(precision)
      )
    let input = editor.sliderNumberInputs[id]
    if gui.inEventPhase and gui.rightClicked(sliderID):
      editor.editingSliderNumbers.incl(id)
      input.setNumberInputText(value.formattedNumber(precision))
      gui.focus(inputID)
    let editing = id in editor.editingSliderNumbers
    gui.column(gui.id(), cfg(width = fill(), height = fit(), gap = 4, padding = 0)):
      gui.metricRow("metric", label, $(round(value * precision) / precision))
      if editing:
        gui.lineInput(inputID, input, fill(), fixed(30))
        if gui.inEventPhase:
          if gui.submitted(inputID) or gui.keyPressed("escape"):
            editor.editingSliderNumbers.excl(id)
          else:
            try:
              let parsed = input.text.strip.parseFloat.float32
              value = clamp(parsed, minimum.float32, maximum.float32)
            except ValueError:
              discard
      else:
        let changed = gui.slider(
          sliderID, value.float64, minimum, maximum, fill(), fixed(30)
        )
        if changed.active:
          value = changed.value.float32

proc terrainIntSliderImpl(
    gui: var UI, id, label: string, value: var int, minimum, maximum: float64
) =
  gui.scope(id):
    let sliderID = gui.id("slider")
    let inputID = gui.id("input")
    if id notin editor.sliderNumberInputs:
      editor.sliderNumberInputs[id] = LineInputState.new($value)
    let input = editor.sliderNumberInputs[id]
    if gui.inEventPhase and gui.rightClicked(sliderID):
      editor.editingSliderNumbers.incl(id)
      input.setNumberInputText($value)
      gui.focus(inputID)
    let editing = id in editor.editingSliderNumbers
    gui.column(gui.id(), cfg(width = fill(), height = fit(), gap = 4, padding = 0)):
      gui.metricRow("metric", label, $value)
      if editing:
        gui.lineInput(inputID, input, fill(), fixed(30))
        if gui.inEventPhase:
          if gui.submitted(inputID) or gui.keyPressed("escape"):
            editor.editingSliderNumbers.excl(id)
          else:
            try:
              value = clamp(input.text.strip.parseInt, minimum.int, maximum.int)
            except ValueError:
              discard
      else:
        let changed = gui.slider(
          sliderID, value.float64, minimum, maximum, fill(), fixed(30)
        )
        if changed.active:
          value = clamp(round(changed.value).int, minimum.int, maximum.int)

proc materialIDForTexture*(scope, path: string): MaterialID =
  ("texture:" & scope & ":" & path).MaterialID

proc textureMaterial*(scope, path: string): WorldMaterial =
  WorldMaterial(
    id: materialIDForTexture(scope, path),
    name: path.extractFilename,
    texturePath: path,
    baseColor: vec3(1, 1, 1),
    useTexture: path.len > 0,
    specularStrength: (if scope == "terrain":
    editor.terrainPanel.specularStrength else: DefaultSpecularStrength),
  )

proc ensureTextureMaterial*(scope, path: string): int =
  if editor.editWorld.meshCount == 0:
    return 0
  editor.editWorld.addMaterial(textureMaterial(scope, path))

proc ensureTerrainTextureMaterial*(): int =
  result = ensureTextureMaterial("terrain", editor.terrainPanel.texturePath)
  editor.meshEditor.terrainPaintMaterial = result

proc ensureUvTextureMaterial*(): int =
  ensureTextureMaterial("mesh:" & $editor.editWorld.selectedMesh,
      editor.uvTexturePath)

proc texturePickerImpl(gui: var UI, io: IO, id: string, path: var string): bool =
  gui.scope(id):
    let pickerID = gui.id("picker")
    gui.row(
      gui.id(),
      cfg(width = fill(), height = fit(), gap = 6, padding = 0,
          alignItems = Center),
    ):
      gui.label(path, fill(), fit(), textScroll = true)
      if gui.button(gui.id("pick"), "Change", fit(), fixed(30)):
        if not io.files.pick(pickerID, getCurrentDir() / "res" / "textures"):
          echo io.files.error(pickerID)
    let picked = io.files.value(pickerID)
    if picked.len > 0:
      path = picked
      editor.uvSelectionKey = ""
      io.files.clear(pickerID)
      return true

proc textureAtlasSource(tile: int): coords.Rect =
  let
    col = tile mod TerrainAtlasColumns
    row = tile div TerrainAtlasColumns
    x0 = (col * TerrainAtlasPixelSize) div TerrainAtlasColumns
    y0 = (row * TerrainAtlasPixelSize) div TerrainAtlasRows
    x1 = ((col + 1) * TerrainAtlasPixelSize) div TerrainAtlasColumns
    y1 = ((row + 1) * TerrainAtlasPixelSize) div TerrainAtlasRows
  coords.rect(x0, y0, max(x1 - x0, 1), max(y1 - y0, 1))

proc textureAtlasTileButton(
    gui: var UI, id, path: string, tile: int, selected: bool
): bool =
  let style =
    if selected:
      ComponentStyle(hasBackground: true, background: color(78, 113, 112))
    else:
      ComponentStyle()
  gui.imageButton(
    gui.id(id), path, textureAtlasSource(tile),
    fixed(TextureAtlasButtonSize), fixed(TextureAtlasButtonSize), style = style,
  )

proc textureAtlasPickerImpl(
    gui: var UI, id: string, target: TextureAtlasTarget,
    path: string, tile: int
): bool =
  gui.scope(id):
    if gui.imageButton(
        gui.id("selected"), path, textureAtlasSource(tile),
        fixed(TextureAtlasButtonSize), fixed(TextureAtlasButtonSize),
      ):
      editor.textureAtlasDialogTarget = target
      gui.openDialog(editor.showTextureAtlasDialog)
      result = true

proc textureAtlasTileRow(gui: var UI, path: string,
    row: int): bool {.discardable.} =
  for col in 0 ..< TextureAtlasDialogColumns:
    let tile = row * TextureAtlasDialogColumns + col
    if tile >= TerrainAtlasColumns * TerrainAtlasRows:
      break
    let selected =
      if editor.textureAtlasDialogTarget == UvTextureAtlasTarget:
        editor.uvTextureIndex == tile
      else:
        editor.meshEditor.terrainTextureIndex == tile
    if gui.textureAtlasTileButton("tile " & $tile, path, tile, selected):
      case editor.textureAtlasDialogTarget
      of UvTextureAtlasTarget:
        editor.uvTextureIndex = tile
        editor.uvSelectionKey = ""
      of TerrainTextureAtlasTarget:
        editor.meshEditor.terrainTextureIndex = tile
        discard ensureTerrainTextureMaterial()
      of NoTextureAtlasTarget:
        discard
      gui.closeDialog(editor.showTextureAtlasDialog)
      result = true

proc textureAtlasDialogImpl(gui: var UI) =
  if not editor.showTextureAtlasDialog:
    return
  gui.modalDialog(
    gui.id("texture atlas dialog"), editor.showTextureAtlasDialog,
    cfg(width = fixed(548), height = fixed(590), gap = 0, padding = 0),
  ):
    gui.dialogHeader(
      gui.id("texture atlas dialog header"),
      cfg(width = fill(), height = fixed(36), gap = 8, padding = 8),
    ):
      gui.label(gui.id("texture atlas dialog title"), "Select Texture", fill(),
          fit())
      if gui.button(gui.id("texture atlas dialog close"), "Close", fit(), fit()):
        gui.closeDialog(editor.showTextureAtlasDialog)
    gui.column(
      gui.id("texture atlas dialog body"),
      cfg(width = fill(), height = fill(), gap = 8, padding = 10,
          scrollY = true),
    ):
      let path =
        if editor.textureAtlasDialogTarget == UvTextureAtlasTarget:
          texturePreviewPath(editor.uvTexturePath)
        else:
          texturePreviewPath(editor.terrainPanel.texturePath)
      gui.column(
        gui.id("texture atlas dialog grid"),
        cfg(width = fill(), height = fit(), gap = 2, padding = 0),
      ):
        for row in 0 ..< (TerrainAtlasColumns * TerrainAtlasRows +
            TextureAtlasDialogColumns - 1) div TextureAtlasDialogColumns:
          gui.row(
            gui.id("texture atlas dialog row", row),
            cfg(width = fill(), height = fixed(TextureAtlasButtonSize), gap = 2,
                padding = 0),
          ):
            gui.textureAtlasTileRow(path, row)
      discard

widget toolButton*(tool: TerrainTool, label: string):
  toolButtonImpl(ui, tool, label)

widget terrainToolModeButton*(mode: TerrainToolMode, label: string):
  terrainToolModeButtonImpl(ui, mode, label)

widget editModeButton*(mode: WorldMeshEditMode, label: string):
  editModeButtonImpl(ui, mode, label)

widget waterNumberInput*(
    id, label: string,
    value: var float32,
    minimum, maximum: float64,
    precision = 10'f32,
    altStepMultiplier = 10'f32,
) -> bool:
  result = waterNumberInputImpl(ui, id, label, value, minimum, maximum,
      precision, altStepMultiplier)

widget terrainSlider*(
    id, label: string,
    value: var float32,
    minimum, maximum: float64,
    precision = 10'f32,
):
  terrainSliderImpl(ui, id, label, value, minimum, maximum, precision)

widget terrainIntSlider*(
    id, label: string, value: var int, minimum, maximum: float64
):
  terrainIntSliderImpl(ui, id, label, value, minimum, maximum)

widget texturePicker*(io: IO, id: string, path: var string) -> bool:
  result = texturePickerImpl(ui, io, id, path)

widget textureAtlasPicker*(
    id: string, target: TextureAtlasTarget, path: string, tile: int
) -> bool:
  result = textureAtlasPickerImpl(ui, id, target, path, tile)

widget textureAtlasDialog*():
  textureAtlasDialogImpl(ui)
