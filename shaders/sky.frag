#version 450

layout(location = 0) in vec3 vViewDirection;

layout(location = 0) out vec4 outColor;

layout(set = 3, binding = 0) uniform Sky {
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

vec3 proceduralSky(vec3 direction) {
  float up = clamp(direction.y * 0.5 + 0.5, 0.0, 1.0);
  float horizon = exp(-abs(direction.y) * 7.0);
  vec3 sky = mix(uHorizonColor, uZenithColor, smoothstep(0.35, 1.0, up));
  vec3 ground = mix(uGroundColor, uHorizonColor, smoothstep(0.0, 0.45, up));
  sky = direction.y < 0.0 ? ground : sky;
  return mix(sky, uHorizonColor, horizon * 0.35);
}

vec3 skyboxSky(vec3 direction) {
  // Placeholder for future cubemap sampling. The direction and uniform path are
  // already present so adding a sampler does not require changing scene code.
  return proceduralSky(direction);
}

void main() {
  vec3 direction = normalize(vViewDirection);
  vec3 color = uUseSkybox > 0.5 ? skyboxSky(direction) : proceduralSky(direction);
  outColor = vec4(color * max(uExposure, 0.0), 1.0);
}
