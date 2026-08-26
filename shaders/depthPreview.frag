#version 450
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;
layout(set = 2, binding = 0) uniform sampler2D uDepth;

float unpackDepth(vec4 packed) {
  return dot(packed, vec4(1.0 / 16777216.0, 1.0 / 65536.0,
    1.0 / 256.0, 1.0));
}
void main() {
  float linearDepth = unpackDepth(texture(uDepth, vUv));
  float value = 1.0 - clamp(linearDepth, 0.0, 1.0);
  outColor = vec4(vec3(value), 1.0);
}
