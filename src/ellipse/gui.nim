import shui/elements as shui
import shui/widgets/buttons as shuiButtons
import shui/widgets/inputs as shuiInputs
import shui/widgets/statefulWidgets as shuiStateful
import chroma
import std/macros
import std/strutils

import ./rendering/artist2D

export shui, shuiStateful

type
  GuiContext* = object
    ui*: shui.UI

type
  GuiButtonConfig = object
    disabled = false
    toggle: shuiButtons.ButtonToggleState

var gActiveArtist {.threadvar.}: ptr Artist2D

template activeArtist: untyped =
  gActiveArtist[]

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

  (
    w: widest * fontGlyphAdvance,
    h: lines * fontGlyphHeight
  )

proc drawBackground(elem: Elem) =
  if elem.style.bg.a <= 0 or elem.box.w <= 0 or elem.box.h <= 0:
    return
  discard activeArtist.drawFilledRect(
    [elem.box.x.cfloat, elem.box.y.cfloat],
    [elem.box.w.cfloat, elem.box.h.cfloat],
    colorToTint(elem.style.bg)
  )

proc drawBorder(elem: Elem) =
  if elem.style.border <= 0 or elem.style.borderColor.a <= 0:
    return
  discard activeArtist.drawRect(
    [elem.box.x.cfloat, elem.box.y.cfloat],
    [elem.box.w.cfloat, elem.box.h.cfloat],
    colorToTint(elem.style.borderColor),
    elem.style.border.cfloat
  )

proc drawTextContent(elem: Elem) =
  if elem.text.len == 0 or elem.style.fg.a <= 0:
    return

  let textPos =
    [
      (elem.box.x + elem.style.padding).cfloat,
      (elem.box.y + elem.style.padding).cfloat
    ]
  discard activeArtist.drawText(
    elem.text,
    textPos,
    colorToTint(elem.style.fg),
    1'f32
  )

proc drawScrollIndicator(elem: Elem) =
  if elem.scrollThumbHeight <= 0:
    return

  let trackX = elem.box.x + max(elem.box.w - 8, 0)
  discard activeArtist.drawFilledRect(
    [trackX.cfloat, elem.box.y.cfloat],
    [6'f32, elem.box.h.cfloat],
    [1'f32, 1'f32, 1'f32, 0.08'f32]
  )
  discard activeArtist.drawFilledRect(
    [trackX.cfloat, elem.scrollThumbY.cfloat],
    [6'f32, elem.scrollThumbHeight.cfloat],
    [1'f32, 1'f32, 1'f32, 0.28'f32]
  )

proc drawGuiElement(elem: Elem; phase: DrawPhase) {.gcsafe.} =
  if gActiveArtist.isNil:
    return

  case phase
  of BeforeChildren:
    drawBackground(elem)
    drawBorder(elem)
    drawTextContent(elem)
  of AfterChildren:
    drawScrollIndicator(elem)

proc initGuiContext*(): GuiContext =
  result.ui = shui.UI.init()
  result.ui.onDraw = drawGuiElement
  result.ui.onMeasureText = measureGuiText

proc beginFrame*(gui: var GuiContext) =
  gui.ui.begin()

proc render*(
  gui: var GuiContext;
  artist: var Artist2D;
  width: int;
  height: int;
  deltaTime: float
) =
  gActiveArtist = addr artist
  try:
    gui.ui.updateWidgets(deltaTime)
    gui.ui.updateLayout((x: 0, y: 0, w: width, h: height))
    gui.ui.draw()
  finally:
    gActiveArtist = nil

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
      bg = color(0.08, 0.10, 0.16, 0.92),
      borderColor = color(0.94, 0.67, 0.22, 0.95),
      border = 2,
      padding = 14,
      gap = 12
    )
    shui.elem:
      text = title
      style = style(
        fg = color(0.97, 0.86, 0.42, 1.0)
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
      fg = color(0.95, 0.96, 0.99, 1.0)
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
      var bgCol =
        if `id`.hot(ui) or `toggleCheck`:
          color(0.35, 0.34, 0.7)
        else:
          color(0.1, 0.1, 0.3)
      var fgCol = color(1.0)
      if `id`.down(ui):
        bgCol = color(0.6, 0.5, 0.9)
      if config.disabled:
        bgCol = color(0.1, 0.1, 0.2)
        fgCol = color(0.7)
      shui.elem:
        id = `id`
        style = Style(
          fg: fgCol,
          bg: bgCol,
          borderColor: color(0.6, 0.6, 0.6),
          border: 1,
          padding: 4,
          borderRadius: 8.0,
        )
        size = (w: Fit, h: Fit)
        dir = Row
        align = Center
        crossAlign = Center
        shui.elem:
          text = `text`
          style = Style(fg: fgCol, bg: color(0.0, 0.0, 0.0, 0.0))

template textInput*(value: var string; id: ElemId; body: untyped) =
  shuiInputs.lineInput(value, id):
    body
