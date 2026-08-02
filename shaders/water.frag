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
  float fresnel = pow(1.0 - max(dot(normal, viewDirection), 0.0), 4.0);
  float diffuse = max(dot(normal, lightDirection), 0.0);
  float specular = pow(max(dot(normal, halfVector), 0.0), 96.0) * uSpecularStrength;
  float foam = smoothstep(0.42, 0.95, waveHeight(vWorldPosition.xz) / max(uWaveAmplitude, 0.001));
  vec3 color = mix(uDeepColor, uSurfaceColor, 0.45 + fresnel * 0.45);
  color *= 0.58 + diffuse * 0.42;
  color += vec3(0.78, 0.94, 1.0) * (specular + foam * 0.08);
  outColor = vec4(color, clamp(uOpacity, 0.0, 1.0));
}
