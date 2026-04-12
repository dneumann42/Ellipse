#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec4 inColor;

layout(set = 1, binding = 0, std140) uniform FrameUniforms {
  mat4 projection;
} frameUniforms;

layout(location = 0) out vec4 fragColor;

void main() {
  fragColor = inColor;
  gl_Position = frameUniforms.projection * vec4(inPosition, 0.0, 1.0);
}
