#version 450

layout(location = 0) in vec3 aPosition;

layout(set = 1, binding = 0) uniform Camera {
  mat4 uViewProjection;
};

void main() {
  gl_Position = vec4(aPosition, 1.0) * uViewProjection;
}
