#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUv;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec4 inColor;
layout(location = 4) in float inTextureIndex;

layout(set = 1, binding = 0, std140) uniform FrameUniforms {
  mat4 projection;
  mat4 view;
} frameUniforms;

layout(location = 0) out vec2 fragUv;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec4 fragColor;
layout(location = 3) flat out int fragTextureIndex;

void main() {
  fragUv = inUv;
  fragNormal = normalize(inNormal);
  fragColor = inColor;
  fragTextureIndex = int(inTextureIndex + 0.5);
  gl_Position = frameUniforms.projection * frameUniforms.view * vec4(inPosition, 1.0);
}
