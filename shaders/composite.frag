#version 450
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;
layout(set = 2, binding = 0) uniform sampler2D uColor;
layout(set = 2, binding = 1) uniform sampler2D uOcclusion;
void main() {
  vec4 color = texture(uColor, vUv);
  float ao = texture(uOcclusion, vUv).r;
  outColor = vec4(color.rgb * ao, color.a);
}
