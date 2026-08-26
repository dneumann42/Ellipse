#version 450

layout(location = 0) out vec4 outColor;

vec4 packDepth(float value) {
  const vec4 shifts = vec4(16777216.0, 65536.0, 256.0, 1.0);
  const vec4 masks = vec4(0.0, 1.0 / 256.0, 1.0 / 256.0, 1.0 / 256.0);
  vec4 packed = fract(clamp(value, 0.0, 0.999999) * shifts);
  packed -= packed.xxyz * masks;
  return packed;
}

void main() {
  // Store linear view depth in a filterable colour target. The camera planes
  // match Artist3D's projection setup (0.1 .. 100.0).
  const float nearPlane = 0.1;
  const float farPlane = 100.0;
  float z = gl_FragCoord.z;
  float linear = (nearPlane * farPlane) /
    max(farPlane - z * (farPlane - nearPlane), 0.0001);
  outColor = packDepth(linear / farPlane);
}
