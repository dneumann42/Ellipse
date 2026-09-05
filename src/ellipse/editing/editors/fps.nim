import std/[json, os, times]
import ellipse
import nest/components/component
import nest/resources as nestResources
import nest/screen as nestScreen

import state

proc fpsAtSample*(editor: state.Editor, offset: int): float64 =
  if editor.fpsSamples.len == 0:
    return 0
  let dt = editor.fpsSamples[offset].dt
  if dt <= 0:
    0
  else:
    1.0 / dt

proc fpsHistorySeconds*(): float64 =
  FpsChartHistorySeconds

proc fpsSnapshotPath*(): string =
  let dir = getCurrentDir() / "data" / "fps-snapshots"
  createDir(dir)
  dir / ("fps-" & $epochTime().int & ".json")

proc saveFpsSnapshot*(): string =
  try:
    var samples = newJArray()
    for sample in editor.fpsSamples:
      let fps =
        if sample.dt > 0:
          1.0 / sample.dt
        else:
          0.0
      samples.add %*{"t": sample.t, "dt": sample.dt, "fps": fps}
    let snapshot = %*{
      "historySeconds": fpsHistorySeconds(),
      "sampleCount": editor.fpsSamples.len,
      "samples": samples,
    }
    result = fpsSnapshotPath()
    writeFile(result, snapshot.pretty())
  except CatchableError as error:
    result = "Failed to save FPS snapshot: " & error.msg

proc drawFpsChart*(
    f: Frame, text: nestScreen.Color, font: nestScreen.Font, drawLabels = true
) =
  let bg = nestScreen.color(20, 24, 26)
  let grid = nestScreen.color(48, 58, 62)
  let line = nestScreen.color(116, 202, 168)
  let
    left = f.x.toInt + 42
    top = f.y.toInt + 12
    right = (f.x + f.width).toInt - 12
    bottom = (f.y + f.height).toInt - 26
    w = max(right - left, 1)
    h = max(bottom - top, 1)
  if drawLabels:
    nestScreen.fillRect(rect(f.x.toInt, f.y.toInt, f.width.toInt,
        f.height.toInt), bg)
  else:
    nestScreen.fillRect(rect(left, top, w, h), bg)
  for i in 0 .. 4:
    let y = top + (h * i div 4)
    nestScreen.drawLine(left, y, right, y, grid)
  if drawLabels:
    for fpsMark in [30, 60, 120]:
      let y = bottom - min(fpsMark, 120) * h div 120
      nestScreen.drawLine(left - 4, y, right, y, grid)
      discard nestScreen.drawText(
        font, left - 36, y - 8, $fpsMark, text, nestScreen.color(0, 0, 0, 0)
      )
  let count = editor.fpsSamples.len
  if count > 1:
    let historySeconds = fpsHistorySeconds()
    let windowStart = max(editor.fpsClock - historySeconds, 0.0)
    var prevX = -1
    var prevY = -1
    for i in 0 ..< count:
      let
        age = editor.fpsSamples[i].t - windowStart
        x = left + (age / historySeconds * w.float64).int
        fps = min(editor.fpsAtSample(i), 120.0)
        y = bottom - fps.int * h div 120
      if x < left or x > right:
        continue
      if prevX >= left:
        nestScreen.drawLine(prevX, prevY, x, y, line)
      prevX = x
      prevY = y
  if drawLabels:
    discard nestScreen.drawText(
      font,
      left,
      bottom + 6,
      "FPS over last " & $fpsHistorySeconds().int & "s",
      text,
      nestScreen.color(0, 0, 0, 0),
    )

method draw*(chart: FpsChart, widget: Widget, ctx: var DrawContext) =
  discard chart
  let font = nestScreen.Font(nestResources.get(ctx.resources, "font").resource)
  drawFpsChart(widget.frame, ctx.palette.textColor, font)

proc fpsChart*(gui: var UI, id: WidgetID, width, height: SizePolicy) =
  discard gui.component(id, Component(FpsChart()), width, height)
