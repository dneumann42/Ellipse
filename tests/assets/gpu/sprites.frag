#version 450

layout(location = 0) in vec2 fragUv;
layout(location = 1) in vec4 fragTint;
layout(location = 2) flat in int fragTextureIndex;

layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform sampler2D spriteTextures[8];

vec4 sampleSprite(int textureIndex, vec2 uv) {
  switch (textureIndex) {
  case 0: return texture(spriteTextures[0], uv);
  case 1: return texture(spriteTextures[1], uv);
  case 2: return texture(spriteTextures[2], uv);
  case 3: return texture(spriteTextures[3], uv);
  case 4: return texture(spriteTextures[4], uv);
  case 5: return texture(spriteTextures[5], uv);
  case 6: return texture(spriteTextures[6], uv);
  case 7: return texture(spriteTextures[7], uv);
  default: return vec4(1.0);
  }
}

void main() {
  outColor = sampleSprite(fragTextureIndex, fragUv) * fragTint;
}
