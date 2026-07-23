import ellipse/application
export application

import sdl3
from nest/ui import update, draw

var
  u: UI
  count = 0
  root: WidgetID
  panel: WidgetID
  title: WidgetID
  countLabel: WidgetID
  buttonRow: WidgetID
  decrementButton: WidgetID
  incrementButton: WidgetID

proc initCounterIds() =
  root = nextWidgetID()
  panel = nextWidgetID()
  title = nextWidgetID()
  countLabel = nextWidgetID()
  buttonRow = nextWidgetID()
  decrementButton = nextWidgetID()
  incrementButton = nextWidgetID()

when isMainModule:
  plugin Ellipse:
    proc load() =
      initNest(u)
      initCounterIds()

    proc nestEvent(event: sdl3.Event) =
      handleNestEvent(u, event)

    proc draw(renderer: Renderer) =
      renderNest(u):
        u.layout:
          u.column(
            root,
            cfg(
              width = fill(),
              height = fill(),
              padding = 24,
              gap = 0,
              alignItems = AlignCenter,
              justifyContent = JustifyCenter,
            ),
          ):
            u.card(
              panel,
              cfg(
                width = fixed(360),
                height = fixed(170),
                padding = 16,
                gap = 12,
                alignItems = AlignStretch,
              ),
            ):
              u.label(title, "Ellipse Counter", width = fill(), height = fixed(28))
              u.label(
                countLabel, "Count: " & $count, width = fill(), height = fixed(28)
              )
              u.row(
                buttonRow,
                cfg(
                  width = fill(),
                  height = fixed(44),
                  gap = 8,
                  alignItems = AlignStretch,
                  justifyContent = JustifyCenter,
                ),
              ):
                if u.button(
                  decrementButton, "-", width = fixed(150), height = fixed(44)
                ):
                  dec count
                if u.button(
                  incrementButton, "+", width = fixed(150), height = fixed(44)
                ):
                  inc count

  buildApplication()

  start()
