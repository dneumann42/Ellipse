#version 450

layout(location = 0) out vec3 vViewDirection;

layout(set = 1, binding = 0) uniform Sky {
  mat4 uInverseViewProjection;
  vec3 uCameraPosition;
  float uExposure;
  vec3 uHorizonColor;
  float uUseSkybox;
  vec3 uZenithColor;
  float uPadding0;
  vec3 uGroundColor;
  float uPadding1;
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
  vec4 worldPosition = uInverseViewProjection * vec4(position, 1.0, 1.0);
  worldPosition.xyz /= worldPosition.w;
  vViewDirection = normalize(worldPosition.xyz - uCameraPosition);
  gl_Position = vec4(position, 0.0, 1.0);
}
