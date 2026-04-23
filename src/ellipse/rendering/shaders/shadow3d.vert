#version 450

layout(location = 0) in vec3 inPosition;

layout(set = 1, binding = 0, std140) uniform ShadowPassVertexUniforms {
  mat4 viewProjection;
} shadowPass;

layout(location = 0) out vec3 fragWorldPosition;

void main() {
  fragWorldPosition = inPosition;
  gl_Position = shadowPass.viewProjection * vec4(inPosition, 1.0);
}
