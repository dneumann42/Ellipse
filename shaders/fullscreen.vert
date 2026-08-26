#version 450

layout(location = 0) out vec2 vUv;

void main() {
  vec2 positions[3] = vec2[](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
  vec2 position = positions[gl_VertexIndex];
  // SDL presents textures with a top-left origin. Match the direct scene
  // target rather than vertically flipping the post-process composite.
  vUv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position, 0.0, 1.0);
}
