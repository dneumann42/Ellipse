## Compile-time integration coverage for application loop plugin phases.

import ellipse

var
  constantTicks = 0
  sceneConstantTicks = 0
  simulationTicks = 0
  uiTicks = 0

scene ApplicationPhaseScene:
  proc constantUpdate*(dt: float64, paused: var bool) =
    doAssert dt >= 0
    discard paused
    inc sceneConstantTicks

plugin ApplicationPhaseProbe:
  proc constantUpdate*(dt: float64, paused: var bool) =
    doAssert dt >= 0
    inc constantTicks
    paused = constantTicks == 1

  proc update*() =
    inc simulationTicks

  proc ui*(gui: var UI, paused: var bool) =
    inc uiTicks
    if paused and uiTicks > 1:
      paused = false

  proc postUi*(running: var bool) =
    if constantTicks >= 4:
      doAssert simulationTicks == constantTicks - 1
      doAssert sceneConstantTicks == constantTicks
      doAssert uiTicks >= constantTicks
      echo "[OK] constant update and UI continue while simulation is paused"
      running = false

let config = ApplicationConfig(
  appname: "Ellipse application phase probe",
  appversion: "0.0.0",
)

buildApplication(config):
  sceneStack.push(ApplicationPhaseScene)

when isMainModule:
  start()
