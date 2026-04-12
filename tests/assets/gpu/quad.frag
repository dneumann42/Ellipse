#version 450

layout(location = 0) in vec2 fragUv;
layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform sampler2D checkerTexture;

void main() {
  outColor = texture(checkerTexture, fragUv);
}
