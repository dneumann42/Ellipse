#version 450

layout(location = 0) in vec3 aPosition;

layout(set = 1, binding = 0) uniform Transform {
  mat4 uModelViewProjection;
};

void main() {
  gl_Position = uModelViewProjection * vec4(aPosition, 1.0);
}
