#version 450

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;
layout(set = 2, binding = 0) uniform sampler2D uDepth;
layout(set = 3, binding = 0) uniform Ssao {
  vec4 uResolutionRadius;
  vec4 uProjection;
  vec4 uStrengthBias;
};

float linearDepth(float z) {
  return z * uProjection.y;
}

float unpackDepth(vec4 packed) {
  return dot(packed, vec4(1.0 / 16777216.0, 1.0 / 65536.0,
    1.0 / 256.0, 1.0));
}

void main() {
  float center = linearDepth(unpackDepth(texture(uDepth, vUv)));
  if (center >= uProjection.y * 0.995) { outColor = vec4(1.0); return; }
  vec2 texel = 1.0 / uResolutionRadius.xy;
  const vec2 kernel[12] = vec2[](
    vec2(0.52, 0.18), vec2(-0.33, 0.61), vec2(-0.72, -0.16), vec2(0.21, -0.71),
    vec2(0.84, -0.42), vec2(-0.11, -0.93), vec2(0.42, 0.82), vec2(-0.91, 0.36),
    vec2(0.13, 0.42), vec2(-0.39, -0.28), vec2(0.58, 0.05), vec2(-0.05, 0.75)
  );
  float occlusion = 0.0;
  for (int i = 0; i < 12; ++i) {
    float scale = mix(0.35, 1.0, float(i) / 11.0);
    vec2 uv = clamp(vUv + kernel[i] * texel * uResolutionRadius.z * scale, 0.001, 0.999);
    float sampleDepth = linearDepth(unpackDepth(texture(uDepth, uv)));
    float delta = center - sampleDepth;
    float horizon = smoothstep(uStrengthBias.y, uStrengthBias.y + center * 0.08, delta);
    float range = smoothstep(center * 0.32, 0.0, abs(delta));
    occlusion += horizon * range;
  }
  float ao = 1.0 - (occlusion / 12.0) * uStrengthBias.x;
  outColor = vec4(vec3(clamp(ao, 0.0, 1.0)), 1.0);
}
