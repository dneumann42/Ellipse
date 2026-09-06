## Global renderer settings loaded safely from hot-reloadable Owl data.

import std/[math, tables]

import owl
import vmath

const RenderSettingsPath* = "render-settings.owl"

type
  AntialiasingMode* {.pure.} = enum
    Disabled, Msaa2x, Msaa4x, Msaa8x

  EnvironmentSettings* = object
    fogNearColor*, fogFarColor*: Vec3
    fogDensity*, fogFalloff*, fogLimit*: float32
    skyHorizonColor*, skyZenithColor*, skyGroundColor*: Vec3
    skyExposure*: float32

  LightingSettings* = object
    direction*: Vec3
    ambientStrength*, diffuseStrength*: float32
    color*, specularColor*: Vec3
    shininess*, defaultSpecularStrength*: float32

  SsaoSettings* = object
    enabled*: bool
    radius*, strength*, bias*: float32

  CameraRenderSettings* = object
    fieldOfView*, nearPlane*, farPlane*: float32

  RenderSettings* = object
    environment*: EnvironmentSettings
    lighting*: LightingSettings
    ssao*: SsaoSettings
    camera*: CameraRenderSettings
    clearColor*: Vec3
    textureFiltering*: bool
    antialiasing*: AntialiasingMode

  RenderSettingsLoader* = object
    path*: string
    settings*: RenderSettings
    lastError*: string
    watcher: OwlFileWatcher

proc init*(T: typedesc[RenderSettings]): T =
  T(
    environment: EnvironmentSettings(
      fogNearColor: vec3(0.72'f32, 0.8'f32, 0.86'f32),
      fogFarColor: vec3(0.42'f32, 0.56'f32, 0.66'f32),
      fogDensity: 0'f32,
      fogFalloff: 1'f32,
      fogLimit: 120'f32,
      skyHorizonColor: vec3(0.72'f32, 0.8'f32, 0.86'f32),
      skyZenithColor: vec3(0.42'f32, 0.56'f32, 0.66'f32),
      skyGroundColor: vec3(0.45'f32, 0.5'f32, 0.48'f32),
      skyExposure: 1'f32,
    ),
    lighting: LightingSettings(
      direction: vec3(-0.45'f32, 0.85'f32, -0.35'f32),
      ambientStrength: 0.22'f32,
      diffuseStrength: 0.72'f32,
      color: vec3(1, 1, 1),
      specularColor: vec3(1'f32, 0.9'f32, 0.68'f32),
      shininess: 32'f32,
      defaultSpecularStrength: 0.35'f32,
    ),
    ssao: SsaoSettings(enabled: true, radius: 3.2'f32,
      strength: 1.15'f32, bias: 0.012'f32),
    camera: CameraRenderSettings(fieldOfView: 70'f32,
      nearPlane: 0.1'f32, farPlane: 100'f32),
    clearColor: vec3(0.04'f32, 0.05'f32, 0.07'f32),
    textureFiltering: false,
    antialiasing: AntialiasingMode.Disabled,
  )

proc clampSettings(settings: var RenderSettings) =
  settings.environment.fogDensity = max(settings.environment.fogDensity, 0)
  settings.environment.fogFalloff = max(settings.environment.fogFalloff, 0.001)
  settings.environment.fogLimit = max(settings.environment.fogLimit, 0.001)
  settings.environment.skyExposure = max(settings.environment.skyExposure, 0)
  settings.lighting.ambientStrength = max(settings.lighting.ambientStrength, 0)
  settings.lighting.diffuseStrength = max(settings.lighting.diffuseStrength, 0)
  settings.lighting.shininess = max(settings.lighting.shininess, 1)
  settings.lighting.defaultSpecularStrength =
    max(settings.lighting.defaultSpecularStrength, 0)
  if length(settings.lighting.direction) < 0.000001'f32:
    settings.lighting.direction = RenderSettings.init().lighting.direction
  settings.ssao.radius = max(settings.ssao.radius, 0.1)
  settings.ssao.strength = clamp(settings.ssao.strength, 0, 3)
  settings.ssao.bias = max(settings.ssao.bias, 0)
  settings.camera.fieldOfView = clamp(settings.camera.fieldOfView, 1, 179)
  settings.camera.nearPlane = max(settings.camera.nearPlane, 0.001)
  settings.camera.farPlane = max(settings.camera.farPlane,
    settings.camera.nearPlane + 0.001)
  settings.clearColor.x = clamp(settings.clearColor.x, 0, 1)
  settings.clearColor.y = clamp(settings.clearColor.y, 0, 1)
  settings.clearColor.z = clamp(settings.clearColor.z, 0, 1)

proc toOwl*(value: Vec3): Value =
  list(@[value.x.toOwl(), value.y.toOwl(), value.z.toOwl()])

proc fromOwl*(value: Value, target: var Vec3) =
  if value.kind != List or value.len != 3:
    raise newException(DataError, "expected an Owl list with three numbers")
  value[0].fromOwl(target.x)
  value[1].fromOwl(target.y)
  value[2].fromOwl(target.z)

proc toOwl*(settings: RenderSettings): Value =
  ## Convert renderer settings to the same top-level record shape used by
  ## `render-settings.owl`.
  result = record([
    ("environment", settings.environment.toOwl()),
    ("lighting", settings.lighting.toOwl()),
    ("ssao", settings.ssao.toOwl()),
    ("camera", settings.camera.toOwl()),
    ("clearColor", settings.clearColor.toOwl()),
    ("textureFiltering", settings.textureFiltering.toOwl()),
    ("antialiasing", settings.antialiasing.toOwl()),
  ])

proc fromOwl*(value: Value, settings: var RenderSettings) =
  ## Apply fields present in Owl data while preserving initialized defaults.
  if value.kind != Record:
    raise newException(DataError, "render settings must be an Owl record")
  for name, field in settings.fieldPairs:
    if value.entries.hasKey(name):
      value.entries[name].fromOwl(field)
  settings.clampSettings()

proc loadRenderSettings*(path = RenderSettingsPath): RenderSettings =
  ## Load settings with Owl's restricted data evaluator. Missing fields keep
  ## their defaults, allowing small project-specific overrides.
  let data = loadOwlFile(path, restrictedOwlData)
  var
    root: Value
    foundRoot = false
  if data.kind == Record:
    root = data
    foundRoot = true
  elif data.kind == List and data.len > 0:
    for index in countdown(data.len - 1, 0):
      if data[index].kind == Record and data[index].entries.len > 0:
        root = data[index]
        foundRoot = true
        break
  if not foundRoot:
    raise newException(DataError,
      "render settings must evaluate to top-level Owl bindings")
  result = RenderSettings.init()
  root.fromOwl(result)

proc reload(loader: var RenderSettingsLoader): bool =
  try:
    let loaded = loadRenderSettings(loader.path)
    loader.settings = loaded
    loader.lastError = ""
    result = true
  except CatchableError as error:
    loader.lastError = error.msg

proc init*(T: typedesc[RenderSettingsLoader],
           path = RenderSettingsPath): T =
  result = T(path: path, settings: RenderSettings.init(),
    watcher: initOwlFileWatcher())
  discard result.reload()
  result.watcher.watch(path)

proc poll*(loader: var RenderSettingsLoader): bool =
  ## Reload after a create/change/delete event. Failed edits retain the last
  ## valid settings and are retried after the next filesystem change.
  if not loader.watcher.changed():
    return false
  loader.watcher.refresh()
  result = loader.reload()

proc close*(loader: var RenderSettingsLoader) =
  ## Release resources held by the shared Owl file watcher.
  loader.watcher.close()
