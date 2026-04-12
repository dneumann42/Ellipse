import std/[options, os]

import ellipse/platform/application
import ellipse/gui

proc accentName(index: int): string =
  case index mod 3
  of 1: "amber"
  of 2: "cyan"
  else: "gold"

const
  demoFontPath = currentSourcePath.parentDir / "assets" / "fonts" / "Manrope-Regular.ttf"
  themeOptions = ["gold", "amber", "cyan", "mint"]
  stationList = [
    "Bridge",
    "Engineering",
    "Hangar",
    "Hydroponics",
    "Navigation",
    "Security",
    "Archive",
    "Observatory"
  ]

proc selectedStationName(index: int): string =
  if index >= 0 and index < stationList.len:
    stationList[index]
  else:
    "(none)"

widget ReactorCard:
  state:
    count: int = 0
    accent: int = 0
    note: string = ""

  event:
    Clicked(count: int, accent: int)
    Cleared

  render(title: string, prefix: string):
    panel(title, ElemId(prefix & ".panel")):
      vbox:
        label("Local power: " & $state.count)
        label("Accent channel: " & accentName(state.accent))
        textInput(state.note, ElemId(prefix & ".note")):
          placeholder = "Widget-local note"

        hbox:
          button("Pulse", ElemId(prefix & ".pulse")):
            onClick:
              inc state.count
              emit Clicked(count: state.count, accent: state.accent)

          button("Shift", ElemId(prefix & ".shift")):
            onClick:
              state.accent = (state.accent + 1) mod 3
              emit Clicked(count: state.count, accent: state.accent)

          button("Clear", ElemId(prefix & ".clear")):
            onClick:
              state.count = 0
              state.note.setLen(0)
              emit Cleared

        label(if state.note.len > 0: "Note: " & state.note else: "Note: (empty)")

widget ControlDeck:
  state:
    callsign: string = ""
    totalClicks: int = 0
    lastEvent: string = "Waiting for input"
    shieldsEnabled: bool = true
    powerMix: float = 42.0
    thrustBias: float = 0.35
    stationIndex: int = 2
    theme: string = themeOptions[0]
    left: ReactorCard = ReactorCard()
    right: ReactorCard = ReactorCard()

  handle:
    onEvent(state.left, Clicked):
      inc state.totalClicks
      state.lastEvent = "Port reactor -> " & $evt.count & " / " & accentName(evt.accent)

    onEvent(state.right, Clicked):
      inc state.totalClicks
      state.lastEvent = "Starboard reactor -> " & $evt.count & " / " & accentName(evt.accent)

    onEvent(state.left, Cleared):
      state.lastEvent = "Port reactor cleared"

    onEvent(state.right, Cleared):
      state.lastEvent = "Starboard reactor cleared"

  render():
    panel("Ellipse + Shui Widget Showcase", ElemId"deck.panel"):
      vbox:
        label("Custom Shui widgets with local state and child events.")
        textInput(state.callsign, ElemId"deck.callsign"):
          placeholder = "Crew callsign"

        hbox:
          label("Total widget actions: " & $state.totalClicks)
          label("Pilot: " & (if state.callsign.len > 0: state.callsign else: "(unset)"))

        label("Last event: " & state.lastEvent)

        hbox:
          vbox:
            hbox:
              container:
                reactorCard("Port Reactor", "deck.left", state.left)
              container:
                reactorCard("Starboard Reactor", "deck.right", state.right)

            hbox:
              button("Sync Colors", ElemId"deck.sync"):
                onClick:
                  let target = (state.left.accent + 1) mod 3
                  state.left.accent = target
                  state.right.accent = target
                  state.lastEvent = "Synchronized both reactors to " & accentName(target)

              button("Reset Mission", ElemId"deck.reset"):
                onClick:
                  state.callsign.setLen(0)
                  state.totalClicks = 0
                  state.lastEvent = "Mission state reset"
                  state.shieldsEnabled = true
                  state.powerMix = 42.0
                  state.thrustBias = 0.35
                  state.stationIndex = 2
                  state.theme = themeOptions[0]
                  state.left = ReactorCard()
                  state.right = ReactorCard()

          panel("Control Surface", ElemId"deck.controls"):
            hbox:
              vbox:
                checkbox("Shields Enabled", state.shieldsEnabled, ElemId"deck.shields")

                vbox:
                  label("Power Mix: " & $int(state.powerMix))
                  hslider(state.powerMix, 0.0, 100.0, ElemId"deck.powerMix")

                vbox:
                  label("Active Theme")
                  comboBox(state.theme, ElemId"deck.theme"):
                    for option in themeOptions:
                      comboOption(option, option)

              vbox:
                label("Thrust Bias: " & $int(state.thrustBias * 100.0) & "%")
                vslider(state.thrustBias, 0.0, 1.0, ElemId"deck.thrust")

              vbox:
                label("Station Queue")
                listBox(state.stationIndex, stationList, ElemId"deck.stations", 4)
                label("Selected Station: " & selectedStationName(state.stationIndex))

type
  DemoState = object
    deck: ControlDeck

plugin Demo:
  proc draw(
    ui: var UI;
    deck: var ControlDeck;
    swapchainWidth: uint32;
    swapchainHeight: uint32
  ) =
    screenUi(swapchainWidth.int, swapchainHeight.int):
      controlDeck(deck)

when isMainModule:
  startApplication(
    AppConfig(
      appId: "dev.ellipse.tests.guidemo",
      title: "Ellipse GUI Demo",
      width: 1600,
      height: 720,
      windowFlags: 0,
      resizable: true,
      shaderFormat: GPU_SHADERFORMAT_SPIRV,
      driverName: "vulkan",
      debugMode: true,
      clearColor: FColor(r: 0.05, g: 0.07, b: 0.11, a: 1.0),
      defaultFontPath: demoFontPath,
      defaultFontSize: 10'f32
    ),
    DemoState()
  )
