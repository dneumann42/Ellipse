#version 450

layout(location = 0) in vec3 vViewDirection;

layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform samplerCube uSkybox;

layout(set = 3, binding = 0) uniform Sky {
  mat4 uCameraRotation;
  vec4 uViewportScale;
  vec4 uHorizonExposure;
  vec4 uZenithUseSkybox;
  vec4 uGroundColorValue;
};

#define uHorizonColor uHorizonExposure.rgb
#define uExposure uHorizonExposure.a
#define uZenithColor uZenithUseSkybox.rgb
#define uUseSkybox uZenithUseSkybox.a
#define uGroundColor uGroundColorValue.rgb

vec3 proceduralSky(vec3 direction) {
  float up = clamp(direction.y * 0.5 + 0.5, 0.0, 1.0);
  float horizon = exp(-abs(direction.y) * 7.0);
  vec3 sky = mix(uHorizonColor, uZenithColor, smoothstep(0.35, 1.0, up));
  vec3 ground = mix(uGroundColor, uHorizonColor, smoothstep(0.0, 0.45, up));
  sky = direction.y < 0.0 ? ground : sky;
  return mix(sky, uHorizonColor, horizon * 0.35);
}

vec3 skyboxSky(vec3 direction) {
  vec3 color = texture(uSkybox, direction).rgb;
  float horizonBlend = pow(clamp(1.0 - abs(direction.y), 0.0, 1.0), 3.0) * 0.55;
  float lowerBlend = smoothstep(-0.45, 0.05, -direction.y) * 0.35;
  return mix(color, uHorizonColor, max(horizonBlend, lowerBlend));
}

void main() {
  vec3 direction = normalize(vViewDirection);
  vec3 color = uUseSkybox > 0.5 ? skyboxSky(direction) : proceduralSky(direction);
  outColor = vec4(color * max(uExposure, 0.0), 1.0);
}
