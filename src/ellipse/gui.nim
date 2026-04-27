import shui/elements as shui
import shui/widgets/buttons as shuiButtons
import shui/widgets/inputs as shuiInputs
import shui/widgets/statefulWidgets as shuiStateful
import chroma
import std/macros
import std/math
import std/strutils
import std/tables

import ./rendering/artist2D

export shui, shuiStateful

type
  GuiContext* = object
    ui*: shui.UI

type
  SliderAxis* = enum
    saHorizontal,
    saVertical

  GuiButtonConfig = object
    disabled = false
    toggle: shuiButtons.ButtonToggleState

  GuiClipState = object
    inheritedClip: ScissorRect
    boxClip: ScissorRect
    childClip: ScissorRect

  GuiImage* = object
    texture*: SpriteTexture
    region*: SpriteTextureRegion
    tint*: array[4, cfloat]

  ImageGridItem* = object
    texture*: SpriteTexture
    region*: SpriteTextureRegion

var gActiveArtist {.threadvar.}: ptr Artist2D
var gFontSize {.threadvar.}: int
var gTargetClip {.threadvar.}: ScissorRect
var gClipStack {.threadvar.}: seq[GuiClipState]
var gImages {.threadvar.}: Table[string, GuiImage]
var gRenderScale {.threadvar.}: cfloat

template activeArtist: untyped =
  gActiveArtist[]

proc scaled(value: int): cfloat =
  value.cfloat * gRenderScale

proc scaled(value: cfloat): cfloat =
  value * gRenderScale

proc scaledClip(clip: ScissorRect): ScissorRect =
  ScissorRect(
    x: int(round(clip.x.cfloat * gRenderScale)),
    y: int(round(clip.y.cfloat * gRenderScale)),
    w: int(round(clip.w.cfloat * gRenderScale)),
    h: int(round(clip.h.cfloat * gRenderScale))
  )

proc colorToTint(color: Color): array[4, cfloat] =
  [color.r.cfloat, color.g.cfloat, color.b.cfloat, color.a.cfloat]

proc extractGuiButtonConfig(node: NimNode): tuple[config: GuiButtonConfig, toggleExpr: NimNode] =
  result.config = GuiButtonConfig()
  result.toggleExpr = nil
  for child in node.items:
    if child.kind == nnkAsgn:
      if child[0].repr == "disabled":
        result.config.disabled = child[1].repr == "true"
      if child[0].repr == "toggle":
        if child[1].kind in {nnkIdent, nnkSym}:
          result.config.toggle = parseEnum[shuiButtons.ButtonToggleState](child[1].repr)
        else:
          result.toggleExpr = child[1]

proc measureGuiText(text: string): tuple[w, h: int] =
  if gActiveArtist.isNil:
    var lines = 1
    var widest = 0
    var current = 0
    for ch in text:
      case ch
      of '\n':
        if current > widest:
          widest = current
        current = 0
        inc lines
      of '\r':
        discard
      else:
        inc current
    if current > widest:
      widest = current
    let fontSize = if gFontSize > 0: gFontSize else: 16
    return (w: widest * (fontSize div 2), h: lines * fontSize)
  activeArtist.measureText(text)

proc clamp01(value: float): float =
  if value < 0.0:
    return 0.0
  if value > 1.0:
    return 1.0
  value

proc sliderValueFromBox(
  ui: UI;
  id: ElemId;
  minValue: float;
  maxValue: float;
  axis: SliderAxis
): float =
  if not ui.hasBox(id):
    return minValue

  let box = ui.getBox(id)
  let (mx, my) = ui.input.mousePosition
  let t =
    case axis
    of saHorizontal:
      if box.w <= 1: 0.0
      else: clamp01((mx - box.x).float / max(box.w - 1, 1).float)
    of saVertical:
      if box.h <= 1: 0.0
      else: 1.0 - clamp01((my - box.y).float / max(box.h - 1, 1).float)

  minValue + (maxValue - minValue) * t

proc sliderFraction(value: float; minValue: float; maxValue: float): float =
  if maxValue <= minValue:
    return 0.0
  clamp01((value - minValue) / (maxValue - minValue))

proc intersectClip(a, b: ScissorRect): ScissorRect =
  let x1 = max(a.x, b.x)
  let y1 = max(a.y, b.y)
  let x2 = min(a.x + a.w, b.x + b.w)
  let y2 = min(a.y + a.h, b.y + b.h)
  ScissorRect(
    x: x1,
    y: y1,
    w: max(x2 - x1, 0),
    h: max(y2 - y1, 0)
  )

proc clipForElem(elem: Elem): GuiClipState =
  result.inheritedClip =
    if elem.stopClip or gClipStack.len == 0:
      gTargetClip
    else:
      gClipStack[^1].childClip
  let boxClip = ScissorRect(x: elem.box.x, y: elem.box.y, w: elem.box.w, h: elem.box.h)
  result.boxClip = intersectClip(result.inheritedClip, boxClip)
  result.childClip =
    if elem.clipOverflow:
      result.boxClip
    else:
      result.inheritedClip

proc applyGuiClip(clip: ScissorRect) =
  activeArtist.setScissor(scaledClip(clip))

proc drawBackground(elem: Elem; clip: ScissorRect) =
  if elem.style.bg.a <= 0 or elem.box.w <= 0 or elem.box.h <= 0 or clip.w <= 0 or clip.h <= 0:
    return
  discard activeArtist.drawFilledRect(
    [scaled(elem.box.x), scaled(elem.box.y)],
    [scaled(elem.box.w), scaled(elem.box.h)],
    colorToTint(elem.style.bg)
  )

proc drawBorder(elem: Elem; clip: ScissorRect) =
  if elem.style.border <= 0 or elem.style.borderColor.a <= 0 or clip.w <= 0 or clip.h <= 0:
    return
  discard activeArtist.drawRect(
    [scaled(elem.box.x), scaled(elem.box.y)],
    [scaled(elem.box.w), scaled(elem.box.h)],
    colorToTint(elem.style.borderColor),
    scaled(elem.style.border.cfloat)
  )

proc drawTextContent(elem: Elem; clip: ScissorRect) =
  if gActiveArtist.isNil or elem.text.len == 0 or elem.style.fg.a <= 0 or clip.w <= 0 or clip.h <= 0:
    return

  let textX = elem.box.x + elem.style.padding
  let textY = elem.box.y + elem.style.padding

  if textX < 0 or textY < 0:
    return

  let textPos =
    [
      scaled(textX),
      scaled(textY)
    ]
  let tint = colorToTint(elem.style.fg)
  discard activeArtist.drawText(elem.text, textPos, tint, gRenderScale)

proc drawImageContent(elem: Elem; clip: ScissorRect) =
  if gActiveArtist.isNil or clip.w <= 0 or clip.h <= 0:
    return
  let key = $elem.id
  if not gImages.hasKey(key):
    return

  let image = gImages[key]
  if image.texture.isNil:
    return

  let padding = elem.style.padding
  let contentX = elem.box.x + padding
  let contentY = elem.box.y + padding
  let contentW = max(elem.box.w - padding * 2, 0)
  let contentH = max(elem.box.h - padding * 2, 0)
  let side = min(contentW, contentH)
  if side <= 0:
    return

  var sprite = initSprite2D()
  sprite.position = [
    scaled(contentX + max((contentW - side) div 2, 0)),
    scaled(contentY + max((contentH - side) div 2, 0))
  ]
  sprite.size = [scaled(side), scaled(side)]
  sprite.origin = [0'f32, 0'f32]
  sprite.texture = image.texture
  sprite.region = image.region
  sprite.hasRegion = true
  sprite.tint = image.tint
  sprite.filterMode = Nearest
  sprite.hasFilterOverride = true
  discard activeArtist.drawSprite(sprite)

proc drawScrollIndicator(elem: Elem; clip: ScissorRect) =
  if elem.scrollThumbHeight <= 0 or clip.w <= 0 or clip.h <= 0:
    return

  let trackX = elem.box.x + max(elem.box.w - 8, 0)
  discard activeArtist.drawFilledRect(
    [scaled(trackX), scaled(elem.box.y)],
    [scaled(6), scaled(elem.box.h)],
    [1'f32, 1'f32, 1'f32, 0.08'f32]
  )
  discard activeArtist.drawFilledRect(
    [scaled(trackX), scaled(elem.scrollThumbY)],
    [scaled(6), scaled(elem.scrollThumbHeight)],
    [1'f32, 1'f32, 1'f32, 0.28'f32]
  )

proc drawGuiElement(elem: Elem; phase: DrawPhase) {.gcsafe.} =
  if gActiveArtist.isNil:
    return

  case phase
  of BeforeChildren:
    let clipState = clipForElem(elem)
    gClipStack.add(clipState)
    applyGuiClip(clipState.boxClip)
    drawBackground(elem, clipState.boxClip)
    drawBorder(elem, clipState.boxClip)
    applyGuiClip(clipState.boxClip)
    drawImageContent(elem, clipState.boxClip)
    applyGuiClip(clipState.inheritedClip)
    drawTextContent(elem, clipState.inheritedClip)
  of AfterChildren:
    if gClipStack.len <= 0:
      return
    let clipState = gClipStack[^1]
    applyGuiClip(clipState.boxClip)
    drawScrollIndicator(elem, clipState.boxClip)
    discard gClipStack.pop()

proc initGuiContext*(): GuiContext =
  result.ui = shui.UI.init()
  result.ui.onDraw = drawGuiElement
  result.ui.onMeasureText = measureGuiText

proc beginFrame*(gui: var GuiContext; measureArtist: var Artist2D) =
  gActiveArtist = addr measureArtist
  gFontSize = measureArtist.defaultFontSize.int
  gImages = initTable[string, GuiImage]()
  gui.ui.begin()

proc update*(
  gui: var GuiContext;
  width: int;
  height: int;
  deltaTime: float
) =
  try:
    gui.ui.updateWidgets(deltaTime)
    gui.ui.updateLayout((x: 0, y: 0, w: width, h: height))
  finally:
    gActiveArtist = nil

proc draw*(
  gui: var GuiContext;
  artist: var Artist2D;
  width: int;
  height: int;
  renderScale: cfloat = 1'f32
) =
  gActiveArtist = addr artist
  gFontSize = artist.defaultFontSize.int
  gTargetClip = ScissorRect(x: 0, y: 0, w: width, h: height)
  gClipStack.setLen(0)
  gRenderScale = max(renderScale, 1'f32)
  artist.clearScissor()
  try:
    gui.ui.draw()
  finally:
    artist.clearScissor()
    gClipStack.setLen(0)
    gRenderScale = 1'f32
    gActiveArtist = nil

proc render*(
  gui: var GuiContext;
  artist: var Artist2D;
  width: int;
  height: int;
  deltaTime: float;
  renderScale: cfloat = 1'f32
) =
  gActiveArtist = addr artist
  gFontSize = artist.defaultFontSize.int
  gui.update(width, height, deltaTime)
  gui.draw(artist, width, height, renderScale)

proc clearTransientInput*(gui: var GuiContext) =
  gui.ui.input.scrollY = 0
  gui.ui.input.actionPressed = false
  gui.ui.input.dragPressed = false
  gui.ui.input.backspacePressed = false
  gui.ui.input.enterPressed = false
  gui.ui.input.tabPressed = false
  gui.ui.input.textInput.setLen(0)

proc setMousePosition*(gui: var GuiContext; x, y: int) =
  gui.ui.input.mousePosition = (x: x, y: y)

proc addScroll*(gui: var GuiContext; deltaY: float) =
  gui.ui.input.scrollY += deltaY

proc appendTextInput*(gui: var GuiContext; text: string) =
  gui.ui.input.textInput.add(text)

proc setActionButton*(gui: var GuiContext; down: bool) =
  gui.ui.setActionButtonState(down)

proc setDragButton*(gui: var GuiContext; down: bool) =
  if down and not gui.ui.input.dragDown:
    gui.ui.input.dragPressed = true
  gui.ui.input.dragDown = down

proc setShiftDown*(gui: var GuiContext; down: bool) =
  gui.ui.input.shiftDown = down

proc pressBackspace*(gui: var GuiContext) =
  gui.ui.input.backspacePressed = true

proc pressEnter*(gui: var GuiContext) =
  gui.ui.input.enterPressed = true

proc pressTab*(gui: var GuiContext) =
  gui.ui.input.tabPressed = true

template screenUi*(width: int; height: int; body: untyped) =
  shui.elem:
    size = (
      w: Sizing(kind: Fixed, min: width, max: width),
      h: Sizing(kind: Fixed, min: height, max: height)
    )
    dir = Col
    align = Start
    crossAlign = Start
    style = style(
      bg = color(0.0, 0.0, 0.0, 0.0),
      padding = 20,
      gap = 16
    )
    body

template vbox*(body: untyped) =
  shui.elem:
    dir = Col
    size = (w: FitSize, h: FitSize)
    align = Start
    crossAlign = Start
    style = style(
      bg = color(0.0, 0.0, 0.0, 0.0),
      gap = 12
    )
    body

template hbox*(body: untyped) =
  shui.elem:
    dir = Row
    size = (w: FitSize, h: FitSize)
    align = Start
    crossAlign = Center
    style = style(
      bg = color(0.0, 0.0, 0.0, 0.0),
      gap = 12
    )
    body

template vfill*(body: untyped) =
  shui.elem:
    dir = Col
    size = (w: GrowSize, h: FitSize)
    align = Start
    crossAlign = Start
    style = style(
      bg = color(0.0, 0.0, 0.0, 0.0),
      gap = 12
    )
    body

template hfill*(body: untyped) =
  shui.elem:
    dir = Row
    size = (w: GrowSize, h: FitSize)
    align = Start
    crossAlign = Center
    style = style(
      bg = color(0.0, 0.0, 0.0, 0.0),
      gap = 12
    )
    body

template panel*(title: string; panelId: ElemId; body: untyped) =
  shui.elem:
    id = panelId
    dir = Col
    size = (w: FitSize, h: FitSize)
    align = Start
    crossAlign = Start
    style = style(
      bg = ui.theme.panel.bg,
      borderColor = ui.theme.panel.border,
      border = ui.theme.panel.borderWidth,
      padding = ui.theme.panel.padding,
      gap = ui.theme.panel.gap
    )
    shui.elem:
      text = title
      style = style(
        fg = ui.theme.panel.titleFg
      )
      size = (w: FitSize, h: FitSize)
    body

template windowPanel*(title: string; panelId: ElemId; body: untyped) =
  panel(title, panelId):
    body

template label*(caption: string) =
  shui.elem:
    text = caption
    style = style(
      fg = ui.theme.textFg
    )
    size = (w: FitSize, h: FitSize)

macro button*(text: string; id: ElemId; body: untyped): untyped =
  let (config, toggleExpr) = extractGuiButtonConfig(body)
  var onClick = nnkStmtList.newTree()

  for i in 0 ..< body.len:
    if body[i].kind == nnkCall and body[i][0].repr == "onClick":
      let fn = body[i][1]
      body[i] = nnkStmtList.newTree()
      onClick = quote:
        if `id`.clicked(ui):
          `fn`

  let toggleCheck =
    if toggleExpr != nil:
      quote do:
        `toggleExpr` == shuiButtons.On
    else:
      quote do:
        `config`.toggle == shuiButtons.On

  result = quote do:
    let config = `config`
    ui.registerWidget(`id`)
    `onClick`
    block:
      let theme = ui.theme.button
      var bgCol =
        if `id`.hot(ui) or `toggleCheck`:
          theme.hotBg
        else:
          theme.bg
      var fgCol = theme.fg
      var borderCol =
        if `id`.hot(ui) or `toggleCheck`:
          theme.hotBorder
        else:
          theme.border
      if `id`.down(ui):
        bgCol = theme.downBg
        borderCol = theme.downBorder
      if config.disabled:
        bgCol = theme.disabledBg
        fgCol = theme.disabledFg
        borderCol = theme.disabledBorder
      shui.elem:
        id = `id`
        style = Style(
          fg: fgCol,
          bg: bgCol,
          borderColor: borderCol,
          border: theme.borderWidth,
          padding: theme.padding,
          borderRadius: theme.borderRadius,
        )
        size = (
          w: Sizing(kind: Fit, min: theme.minWidth, max: theme.maxWidth),
          h: Sizing(kind: Fixed, min: theme.height, max: theme.height)
        )
        dir = Row
        align = Center
        crossAlign = Center
        shui.elem:
          text = `text`
          style = Style(fg: fgCol, bg: color(0.0, 0.0, 0.0, 0.0))

template textInput*(value: var string; id: ElemId; body: untyped) =
  shuiInputs.lineInput(value, id):
    body

template numberInput*(
  value: var float;
  widgetId: ElemId;
  decimals = 2;
  step = 1.0
) =
  shuiInputs.numberInput(value, widgetId)

template checkbox*(caption: string; value: var bool; widgetId: ElemId) =
  block:
    ui.registerWidget(widgetId)
    if widgetId.clicked(ui):
      value = not value

    let active = value
    let rowBg =
      if widgetId.down(ui):
        ui.theme.list.rowDownBg
      elif widgetId.hot(ui):
        ui.theme.list.rowHotBg
      else:
        color(0.0, 0.0, 0.0, 0.0)
    let boxBg =
      if active: ui.theme.accentHot
      else: ui.theme.input.bg

    shui.elem:
      id = widgetId
      dir = Row
      align = Start
      crossAlign = Center
      size = (w: FitSize, h: FitSize)
      style = style(bg = rowBg, padding = 4, gap = 8, borderRadius = 4.0)
      shui.elem:
        style = style(
          bg = boxBg,
          borderColor = ui.theme.input.border,
          border = ui.theme.input.borderWidth,
          borderRadius = ui.theme.input.borderRadius
        )
        size = (
          w: Sizing(kind: Fixed, min: 18, max: 18),
          h: Sizing(kind: Fixed, min: 18, max: 18)
        )
        if active:
          shui.elem:
            text = "X"
            style = style(fg = ui.theme.button.fg)
            size = (w: FitSize, h: FitSize)
            align = Center
            crossAlign = Center
      label(caption)

template slider*(
  value: var float;
  minValue: float;
  maxValue: float;
  widgetId: ElemId;
  axis: static[SliderAxis]
) =
  block:
    ui.registerWidget(widgetId)
    if widgetId.active(ui) and ui.input.actionDown:
      value = sliderValueFromBox(ui, widgetId, minValue, maxValue, axis)

    let fraction = sliderFraction(value, minValue, maxValue)
    let trackSize =
      case axis
      of saHorizontal:
        (w: Sizing(kind: Fixed, min: 220, max: 220), h: Sizing(kind: Fixed, min: 26, max: 26))
      of saVertical:
        (w: Sizing(kind: Fixed, min: 26, max: 26), h: Sizing(kind: Fixed, min: 160, max: 160))
    let fillStyle =
      if widgetId.down(ui): ui.theme.accentDown
      elif widgetId.hot(ui): ui.theme.accentHot
      else: ui.theme.accent
    let fillW =
      case axis
      of saHorizontal: max(12, int(220.0 * fraction))
      of saVertical: 26
    let fillH =
      case axis
      of saHorizontal: 26
      of saVertical: max(12, int(160.0 * fraction))

    shui.elem:
      id = widgetId
      dir =
        case axis
        of saHorizontal: Row
        of saVertical: Col
      align =
        case axis
        of saHorizontal: Start
        of saVertical: End
      crossAlign = Center
      size = trackSize
      style = style(
        bg = ui.theme.input.bg,
        borderColor = ui.theme.input.border,
        border = ui.theme.input.borderWidth,
        padding = 0,
        gap = 0,
        borderRadius = 6.0
      )
      shui.elem:
        size = (
          w: Sizing(kind: Fixed, min: fillW, max: fillW),
          h: Sizing(kind: Fixed, min: fillH, max: fillH)
        )
        style = style(
          bg = fillStyle,
          borderRadius = 6.0
        )

template hslider*(value: var float; minValue: float; maxValue: float; widgetId: ElemId) =
  slider(value, minValue, maxValue, widgetId, saHorizontal)

template vslider*(value: var float; minValue: float; maxValue: float; widgetId: ElemId) =
  slider(value, minValue, maxValue, widgetId, saVertical)

proc registerGuiImage(id: ElemId; image: GuiImage) =
  gImages[$id] = image

template imageButton*(
  widgetId: ElemId;
  imageTexture: SpriteTexture;
  imageRegion: SpriteTextureRegion;
  buttonSize: static[int];
  selected: bool;
  body: untyped
) =
  block:
    ui.registerWidget(widgetId)
    if widgetId.clicked(ui):
      body

    let buttonBg =
      if widgetId.down(ui):
        ui.theme.list.rowDownBg
      elif selected:
        ui.theme.list.rowSelectedBg
      elif widgetId.hot(ui):
        ui.theme.list.rowHotBg
      else:
        ui.theme.list.bg
    let buttonBorder =
      if selected:
        ui.theme.button.hotBorder
      elif widgetId.hot(ui):
        ui.theme.button.border
      else:
        ui.theme.list.border

    registerGuiImage(widgetId, GuiImage(
      texture: imageTexture,
      region: imageRegion,
      tint: [1'f32, 1'f32, 1'f32, 1'f32]
    ))
    shui.elem:
      id = widgetId
      dir = Row
      align = Center
      crossAlign = Center
      size = (
        w: Sizing(kind: Fixed, min: buttonSize, max: buttonSize),
        h: Sizing(kind: Fixed, min: buttonSize, max: buttonSize)
      )
      style = style(
        bg = buttonBg,
        borderColor = buttonBorder,
        border = ui.theme.button.borderWidth,
        padding = ui.theme.button.padding,
        gap = 0,
        borderRadius = 4.0
      )

template imageGridPicker*(
  selectedIndex: var int;
  items: untyped;
  widgetId: ElemId;
  columns: static[int];
  cellSize: static[int];
  visibleRows: static[int]
) =
  block:
    const GridGap = 6
    let rowCount =
      if items.len <= 0:
        0
      else:
        (items.len + columns - 1) div columns
    shui.elem:
      id = widgetId
      dir = Col
      size = (
        w: Sizing(kind: Fixed, min: columns * cellSize + (columns - 1) * GridGap + 12, max: columns * cellSize + (columns - 1) * GridGap + 12),
        h: Sizing(kind: Fixed, min: visibleRows * cellSize + max(visibleRows - 1, 0) * GridGap + 12, max: visibleRows * cellSize + max(visibleRows - 1, 0) * GridGap + 12)
      )
      clipOverflow = true
      scrollable = true
      style = style(
        bg = ui.theme.list.bg,
        borderColor = ui.theme.list.border,
        border = ui.theme.list.borderWidth,
        padding = 6,
        gap = GridGap,
        borderRadius = 4.0
      )
      for row in 0 ..< rowCount:
        shui.elem:
          dir = Row
          size = (w: FitSize, h: Sizing(kind: Fixed, min: cellSize, max: cellSize))
          style = style(bg = color(0.0, 0.0, 0.0, 0.0), gap = GridGap)
          for column in 0 ..< columns:
            let itemIndex = row * columns + column
            if itemIndex < items.len:
              let gridItem = items[itemIndex]
              let itemId = ElemId($widgetId & ".item." & $itemIndex)
              imageButton(
                itemId,
                gridItem.texture,
                gridItem.region,
                cellSize,
                selectedIndex == itemIndex
              ):
                selectedIndex = itemIndex
            else:
              shui.elem:
                size = (
                  w: Sizing(kind: Fixed, min: cellSize, max: cellSize),
                  h: Sizing(kind: Fixed, min: cellSize, max: cellSize)
                )
                style = style(bg = color(0.0, 0.0, 0.0, 0.0), gap = 0)

template listBox*(
  selectedIndex: var int;
  items: untyped;
  widgetId: ElemId;
  visibleRows: static[int] = 5
) =
  let scrollId = ElemId($widgetId & ".scroll")
  shui.elem:
    id = widgetId
    dir = Col
    size = (
      w: Sizing(kind: Fixed, min: 220, max: 220),
      h: Sizing(kind: Fixed, min: visibleRows * 28 + 10, max: visibleRows * 28 + 10)
    )
    style = style(
      bg = ui.theme.list.bg,
      borderColor = ui.theme.list.border,
      border = ui.theme.list.borderWidth,
      padding = ui.theme.list.padding,
      gap = ui.theme.list.gap,
      borderRadius = ui.theme.list.borderRadius
    )
    shui.elem:
      id = scrollId
      dir = Col
      size = (w: GrowSize, h: GrowSize)
      clipOverflow = true
      scrollable = true
      style = style(bg = color(0.0, 0.0, 0.0, 0.0), gap = 2)
      for index, item in items:
        let rowId = ElemId($widgetId & ".row." & $index)
        ui.registerWidget(rowId)
        if rowId.clicked(ui):
          selectedIndex = index
        let isSelected = selectedIndex == index
        let rowBg =
          if rowId.down(ui):
            ui.theme.list.rowDownBg
          elif isSelected:
            ui.theme.list.rowSelectedBg
          elif rowId.hot(ui):
            ui.theme.list.rowHotBg
          else:
            ui.theme.list.rowBg
        shui.elem:
          id = rowId
          dir = Row
          size = (
            w: GrowSize,
            h: Sizing(kind: Fixed, min: ui.theme.list.rowHeight, max: ui.theme.list.rowHeight)
          )
          align = Start
          crossAlign = Center
          style = style(bg = rowBg, padding = ui.theme.list.padding, borderRadius = ui.theme.list.rowBorderRadius)
          shui.elem:
            text = item
            style = style(
              fg =
                if isSelected: ui.theme.list.selectedFg
                else: ui.theme.list.fg
            )
            size = (w: FitSize, h: FitSize)

template comboBox*(value: var string; widgetId: ElemId; body: untyped) =
  block:
    let focused = widgetId.focused(ui)

    ui.registerWidget(widgetId)

    if focused:
      if widgetId.pressed(ui) or ui.input.enterPressed or ui.input.tabPressed:
        widgetId.unfocus(ui)
    else:
      if widgetId.pressed(ui):
        widgetId.focus(ui)

    var bgCol =
      if widgetId.hot(ui) or focused:
        ui.theme.input.hotBg
      else:
        ui.theme.input.bg
    let fgCol = ui.theme.input.fg
    if widgetId.down(ui):
      bgCol = ui.theme.input.downBg

    shui.elem:
      dir = Col
      shui.elem:
        id = widgetId
        style = Style(
          fg: fgCol,
          bg: bgCol,
          borderColor: ui.theme.input.border,
          border: ui.theme.input.borderWidth,
          padding: ui.theme.input.padding,
          borderRadius: ui.theme.input.borderRadius,
          gap: 4
        )
        size = (w: Fit, h: Fit)
        dir = Col
        align = Start
        crossAlign = Start
        shui.elem:
          dir = Row
          align = Center
          crossAlign = Center
          size = (w: Fit, h: Fit)
          style = Style(
            fg: fgCol,
            bg: color(0.0, 0.0, 0.0, 0.0)
          )
          shui.elem:
            text = value
            style = Style(fg: fgCol, bg: color(0.0, 0.0, 0.0, 0.0))
          shui.elem:
            text = "[-]"
            style = Style(fg: fgCol, bg: color(0.0, 0.0, 0.0, 0.0))

      if widgetId.focused(ui):
        let comboBoxId {.inject.} = widgetId
        var comboValue {.inject.} = value
        shui.elem:
          floating = true
          dir = Col
          style = Style(
            fg: fgCol,
            bg: bgCol,
            borderColor: ui.theme.input.border,
            border: ui.theme.input.borderWidth,
            padding: ui.theme.input.padding,
            borderRadius: ui.theme.input.borderRadius,
            gap: 4
          )
          size = (w: Sizing(kind: Fit, min: 200, max: 400), h: Fit)
          body
        value = comboValue

template comboOption*(key: string; caption: string) =
  block:
    let optionId = ElemId(key)
    if optionId.pressed(ui):
      comboValue = key
      comboBoxId.unfocus(ui)
    ui.registerWidget(optionId)

    var bgCol =
      if optionId.hot(ui):
        ui.theme.input.hotBg
      else:
        ui.theme.input.bg
    let fgCol = ui.theme.input.fg
    if optionId.down(ui):
      bgCol = ui.theme.input.downBg

    shui.elem:
      id = optionId
      style = Style(
        fg: fgCol,
        bg: bgCol,
        padding: ui.theme.input.padding,
        borderRadius: ui.theme.input.borderRadius,
      )
      size = (w: Grow, h: Fit)
      dir = Row
      shui.elem:
        text = caption
        style = Style(fg: fgCol, bg: color(0.0, 0.0, 0.0, 0.0))
