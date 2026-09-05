import std/[os, tables, unittest]

import owl
import vmath

import ellipse/renderSettings

test "render settings load through Owl data conversion":
  let data = loadOwlFile("render-settings.owl", restrictedOwlData)
  check data[data.len - 1].entries.hasKey("environment")
  let settings = loadRenderSettings("render-settings.owl")
  check settings.camera.fieldOfView == 70'f32
  check settings.environment.fogLimit == 120'f32
  check settings.lighting.direction.y == 0.85'f32
  check settings.ssao.enabled
  let encoded = settings.toOwl()
  check encoded.kind == Record
  var decoded = RenderSettings.init()
  encoded.fromOwl(decoded)
  check decoded.camera.fieldOfView == settings.camera.fieldOfView

test "partial settings preserve defaults":
  let path = getTempDir() / "ellipse-partial-render-settings.owl"
  writeFile(path, """
lighting = {}:
  ambientStrength = 0.5
""")
  defer: removeFile(path)

  let settings = loadRenderSettings(path)
  check settings.lighting.ambientStrength == 0.5'f32
  check settings.lighting.diffuseStrength ==
    RenderSettings.init().lighting.diffuseStrength

test "hot reload retains the last valid settings":
  let path = getTempDir() / "ellipse-hot-render-settings.owl"
  writeFile(path, "clearColor = []:\n  0.1\n  0.2\n  0.3\n")
  defer: removeFile(path)
  var loader = RenderSettingsLoader.init(path)
  check loader.settings.clearColor.x == 0.1'f32

  writeFile(path, "eval-source \"1\"")
  check not loader.poll()
  check loader.lastError.len > 0
  check loader.settings.clearColor.x == 0.1'f32

  writeFile(path, "clearColor = []:\n  0.7\n  0.8\n  0.9\n")
  check loader.poll()
  check loader.settings.clearColor.x == 0.7'f32
