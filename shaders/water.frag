#version 450

layout(location = 0) in vec3 vWorldPosition;
layout(location = 1) in vec2 vUv;

layout(location = 0) out vec4 outColor;

layout(set = 3, binding = 1) uniform Water {
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

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float octaveWave(vec2 p, vec2 direction, float frequency, float speed, float weight) {
  float phase = dot(p, normalize(direction)) * frequency + uTime * uWaveSpeed * speed;
  float wave = sin(phase);
  float sharpenedCrest = wave * 0.72 + sin(phase * 2.07 + 0.45) * 0.18;
  return sharpenedCrest * weight;
}

float waveHeight(vec2 p) {
  float k = 6.28318530718 / max(uWaveLength, 0.001);
  float t = uTime * uWaveSpeed;
  vec2 warp = vec2(
    valueNoise(p * 0.041 + vec2(t * 0.035, -t * 0.021)),
    valueNoise(p * 0.037 + vec2(-t * 0.026, t * 0.031))
  ) - 0.5;
  vec2 q = p + warp * uWaveLength * 0.42;

  float swell = octaveWave(q, vec2(0.82, 0.57), k * 0.58, 0.55, 0.30);
  float primary = octaveWave(q, vec2(-0.38, 0.93), k, 1.00, 0.34);
  float cross = octaveWave(q, vec2(0.98, -0.18), k * 1.73, -0.78, 0.20);
  float chop = octaveWave(q, vec2(-0.72, -0.69), k * 2.64, 1.47, 0.11);
  float ripple = octaveWave(q, vec2(0.24, -0.97), k * 4.35, -2.10, 0.05);
  return (swell + primary + cross + chop + ripple) * uWaveAmplitude;
}

vec3 waterNormal(vec2 p) {
  float e = max(uWaveLength * 0.018, 0.03);
  float hL = waveHeight(p - vec2(e, 0.0));
  float hR = waveHeight(p + vec2(e, 0.0));
  float hD = waveHeight(p - vec2(0.0, e));
  float hU = waveHeight(p + vec2(0.0, e));
  return normalize(vec3(hL - hR, e * 2.0, hD - hU));
}

void main() {
  vec3 normal = waterNormal(vWorldPosition.xz);
  vec3 lightDirection = normalize(vec3(-0.45, 0.85, -0.35));
  vec3 viewDirection = normalize(uCameraPosition - vWorldPosition);
  vec3 halfVector = normalize(lightDirection + viewDirection);
  float facing = max(dot(normal, viewDirection), 0.0);
  float fresnel = pow(1.0 - facing, 4.0);
  float diffuse = max(dot(normal, lightDirection), 0.0);
  float specular = pow(max(dot(normal, halfVector), 0.0), 120.0) * uSpecularStrength;
  float broadSpecular = pow(max(dot(reflect(-lightDirection, normal), viewDirection), 0.0), 22.0);
  float crest = waveHeight(vWorldPosition.xz) / max(uWaveAmplitude, 0.001);
  float breakup = valueNoise(vWorldPosition.xz * 0.31 + uTime * uWaveSpeed * 0.08);
  float detail = valueNoise(vWorldPosition.xz * 1.17 - uTime * uWaveSpeed * 0.16);
  float foam = smoothstep(0.52, 0.92, crest + breakup * 0.28) *
      smoothstep(0.38, 0.78, detail);
  float depthTint = 0.34 + fresnel * 0.42 + diffuse * 0.18 + breakup * 0.07;
  vec3 color = mix(uDeepColor, uSurfaceColor, clamp(depthTint, 0.0, 1.0));
  color *= 0.55 + diffuse * 0.45;
  color += vec3(0.70, 0.92, 1.0) * broadSpecular * uSpecularStrength * 0.24;
  color += vec3(0.88, 0.97, 1.0) * (specular + foam * 0.11);
  outColor = vec4(color, clamp(uOpacity, 0.0, 1.0));
}
