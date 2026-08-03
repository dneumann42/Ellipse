#version 450

layout(location = 0) out vec3 vViewDirection;

layout(set = 1, binding = 0) uniform Sky {
  mat4 uCameraRotation;
  vec4 uViewportScale;
  vec4 uHorizonExposure;
  vec4 uZenithUseSkybox;
  vec4 uGroundColorValue;
};

vec2 fullscreenTrianglePosition(int index) {
  if (index == 0) {
    return vec2(-1.0, -1.0);
  }
  if (index == 1) {
    return vec2(3.0, -1.0);
  }
  return vec2(-1.0, 3.0);
}

void main() {
  vec2 position = fullscreenTrianglePosition(gl_VertexIndex);
  vec3 viewDirection = vec3(
    position.x * uViewportScale.x,
    position.y * uViewportScale.y,
    1.0
  );
  vViewDirection = (uCameraRotation * vec4(viewDirection, 0.0)).xyz;
  gl_Position = vec4(position, 0.0, 1.0);
}
