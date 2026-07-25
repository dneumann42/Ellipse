import vmath

type Camera* = object
  position*: Vec3
  orientation*: Quat

proc init*(T: typedesc[Camera], position = vec3()): T =
  T(position: position, orientation: quat())

proc lookAt*(camera: var Camera, target: Vec3) =
  let direction = normalize(target - camera.position)
  camera.orientation = fromTwoVectors(vec3(0, 0, 1), direction)

proc viewMatrix*(camera: Camera): Mat4 =
  # inverse(q) = conjugate(q)
  let inverseRotation = quatInverse(normalize(camera.orientation))
  result = mat4(inverseRotation) * translate(camera.position * -1'f32)
