import std/math

import vmath

const
  MaxFpsCameraPitch = 1.2'f32

type Camera* = object
  position*: Vec3
  orientation*: Quat

type
  FpsCameraControls* = object
    lookX*, lookY*: float32
    forward*, backward*, left*, right*: bool
    up*, down*: bool
    enabled*: bool

  FpsCamera* = object
    camera*: Camera
    yaw*, pitch*: float32
    moveSpeed*: float32
    lookSensitivity*: float32

  OrbitCamera* = object
    target*: Vec3
    distance*, yaw*, pitch*: float32
    minDistance*, maxDistance*: float32
    orbitSensitivity*, zoomSensitivity*: float32

proc init*(T: typedesc[Camera], position = vec3()): T =
  T(position: position, orientation: quat())

proc orientation*(camera: FpsCamera): Quat =
  normalize(quatMultiply(quatRotateY(camera.yaw), quatRotateX(camera.pitch)))

proc init*(
    T: typedesc[FpsCamera],
    position = vec3(0, 0, -4),
    yaw = 0'f32,
    pitch = 0'f32,
    moveSpeed = 4'f32,
    lookSensitivity = 0.003'f32,
): T =
  result = T(
    camera: Camera.init(position),
    yaw: yaw,
    pitch: pitch,
    moveSpeed: moveSpeed,
    lookSensitivity: lookSensitivity,
  )
  result.camera.orientation = result.orientation

proc init*(
    T: typedesc[OrbitCamera],
    target = vec3(),
    distance = 4'f32,
    yaw = 0'f32,
    pitch = 0'f32,
    minDistance = 0.25'f32,
    maxDistance = 100'f32,
    orbitSensitivity = 0.0025'f32,
    zoomSensitivity = 0.15'f32,
): T =
  let
    safeMinDistance = max(minDistance, 0.001'f32)
    safeMaxDistance = max(maxDistance, safeMinDistance)
  T(
    target: target,
    distance: clamp(distance, safeMinDistance, safeMaxDistance),
    yaw: yaw,
    pitch: clamp(pitch, -MaxFpsCameraPitch, MaxFpsCameraPitch),
    minDistance: safeMinDistance,
    maxDistance: safeMaxDistance,
    orbitSensitivity: orbitSensitivity,
    zoomSensitivity: zoomSensitivity,
  )

proc orbit*(camera: var OrbitCamera, deltaX, deltaY: float32) =
  camera.yaw -= deltaX * camera.orbitSensitivity
  camera.pitch -= deltaY * camera.orbitSensitivity
  camera.pitch = clamp(camera.pitch, -MaxFpsCameraPitch, MaxFpsCameraPitch)

proc zoom*(camera: var OrbitCamera, wheelDelta: float32) =
  camera.distance *= exp(-wheelDelta * camera.zoomSensitivity)
  camera.distance = clamp(camera.distance, camera.minDistance, camera.maxDistance)

proc lookAt*(camera: var Camera, target: Vec3) =
  let direction = normalize(target - camera.position)
  camera.orientation = fromTwoVectors(vec3(0, 0, 1), direction)

proc renderCamera*(camera: OrbitCamera): Camera =
  let
    horizontal = cos(camera.pitch) * camera.distance
    offset = vec3(
      sin(camera.yaw) * horizontal,
      sin(camera.pitch) * camera.distance,
      -cos(camera.yaw) * horizontal,
    )
  result = Camera(
    position: camera.target + offset,
    orientation: normalize(quatMultiply(
      quatRotateY(-camera.yaw), quatRotateX(camera.pitch)
    )),
  )

proc forward*(camera: Camera): Vec3 =
  normalize(quatRotate(camera.orientation, vec3(0, 0, 1)))

proc right*(camera: Camera): Vec3 =
  normalize(quatRotate(camera.orientation, vec3(1, 0, 0)))

proc up*(camera: Camera): Vec3 =
  normalize(quatRotate(camera.orientation, vec3(0, 1, 0)))

proc look*(camera: var FpsCamera, deltaX, deltaY: float32) =
  camera.yaw -= deltaX * camera.lookSensitivity
  camera.pitch -= deltaY * camera.lookSensitivity
  camera.pitch = clamp(camera.pitch, -MaxFpsCameraPitch, MaxFpsCameraPitch)
  camera.camera.orientation = camera.orientation

proc horizontalDirection(direction: Vec3): Vec3 =
  result = vec3(direction.x, 0, direction.z)
  if length(result) > 0.000001'f32:
    result = normalize(result)

proc move*(camera: var FpsCamera, controls: FpsCameraControls, dt: float32) =
  let
    forward = horizontalDirection(camera.camera.forward)
    right = horizontalDirection(camera.camera.right)
  var direction = vec3()
  if controls.forward:
    direction += forward
  if controls.backward:
    direction -= forward
  if controls.right:
    direction += right
  if controls.left:
    direction -= right
  if controls.up:
    direction += vec3(0, 1, 0)
  if controls.down:
    direction -= vec3(0, 1, 0)
  if length(direction) > 0.000001'f32:
    camera.camera.position += normalize(direction) * camera.moveSpeed * dt

proc update*(camera: var FpsCamera, controls: FpsCameraControls, dt: float32) =
  if not controls.enabled:
    return
  camera.look(controls.lookX, controls.lookY)
  camera.move(controls, dt)

proc viewMatrix*(camera: Camera): Mat4 =
  # inverse(q) = conjugate(q)
  let inverseRotation = quatInverse(normalize(camera.orientation))
  result = mat4(inverseRotation) * translate(camera.position * -1'f32)

proc viewMatrix*(camera: FpsCamera): Mat4 =
  camera.camera.viewMatrix
