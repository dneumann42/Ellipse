#version 450

layout(location = 0) in vec2 inLocalPosition;
layout(location = 1) in vec2 inBaseUv;
layout(location = 2) in vec2 inSpritePosition;
layout(location = 3) in vec2 inSpriteSize;
layout(location = 4) in vec2 inSpriteScale;
layout(location = 5) in vec2 inSpriteOrigin;
layout(location = 6) in vec4 inSpriteUvRect;
layout(location = 7) in vec4 inSpriteTint;
layout(location = 8) in float inSpriteRotation;
layout(location = 9) in float inSpriteTextureIndex;

layout(set = 1, binding = 0, std140) uniform FrameUniforms {
  mat4 projection;
} frameUniforms;

layout(location = 0) out vec2 fragUv;
layout(location = 1) out vec4 fragTint;
layout(location = 2) flat out int fragTextureIndex;

void main() {
  vec2 spriteExtent = inSpriteSize * inSpriteScale;
  vec2 local = (inLocalPosition - inSpriteOrigin) * spriteExtent;

  float c = cos(inSpriteRotation);
  float s = sin(inSpriteRotation);
  vec2 rotated = vec2(
    local.x * c - local.y * s,
    local.x * s + local.y * c
  );

  vec2 worldPosition = inSpritePosition + rotated;
  fragUv = mix(inSpriteUvRect.xy, inSpriteUvRect.zw, inBaseUv);
  fragTint = inSpriteTint;
  fragTextureIndex = int(inSpriteTextureIndex + 0.5);

  gl_Position = frameUniforms.projection * vec4(worldPosition, 0.0, 1.0);
}
