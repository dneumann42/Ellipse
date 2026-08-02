#version 450

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUv;

layout(location = 0) out vec3 vWorldPosition;
layout(location = 1) out vec2 vUv;

layout(set = 1, binding = 0) uniform Transform {
  mat4 uModelViewProjection;
  mat4 uModel;
};

layout(set = 1, binding = 1) uniform Water {
  vec3 uCameraPosition;
  float uTime;
  vec3 uSurfaceColor;
  float uWaveAmplitude;
  vec3 uDeepColor;
  float uWaveLength;
  float uOpacity;
  float uWaveSpeed;
  float uSpecularStrength;
  float uPadding;
};

float waveHeight(vec2 p) {
  float k = 6.28318530718 / max(uWaveLength, 0.001);
  float t = uTime * uWaveSpeed;
  float a = uWaveAmplitude;
  return (
    sin(dot(p, vec2(0.82, 0.57)) * k + t * 1.15) * 0.52 +
    sin(dot(p, vec2(-0.38, 0.93)) * k * 1.37 + t * 0.74) * 0.31 +
    sin(dot(p, vec2(0.98, -0.18)) * k * 0.63 - t * 0.52) * 0.17
  ) * a;
}

void main() {
  vec4 worldPosition = uModel * vec4(aPosition, 1.0);
  worldPosition.y += waveHeight(worldPosition.xz);
  vWorldPosition = worldPosition.xyz;
  vUv = aUv;
  gl_Position = uModelViewProjection * vec4(aPosition.x, aPosition.y + waveHeight(worldPosition.xz), aPosition.z, 1.0);
}
