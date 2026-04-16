#version 450

layout(location = 0) in vec2 fragUv;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec4 fragColor;
layout(location = 3) flat in int fragTextureIndex;

layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform sampler2D textures3D[8];

vec4 sampleTexture(int textureIndex, vec2 uv) {
  switch (textureIndex) {
  case 0: return texture(textures3D[0], uv);
  case 1: return texture(textures3D[1], uv);
  case 2: return texture(textures3D[2], uv);
  case 3: return texture(textures3D[3], uv);
  case 4: return texture(textures3D[4], uv);
  case 5: return texture(textures3D[5], uv);
  case 6: return texture(textures3D[6], uv);
  case 7: return texture(textures3D[7], uv);
  default: return vec4(1.0);
  }
}

void main() {
  vec3 normal = normalize(fragNormal);
  vec3 lightDir = normalize(vec3(-0.45, 0.75, 0.55));
  float diffuse = max(dot(normal, lightDir), 0.0);
  float light = 0.28 + diffuse * 0.72;
  vec4 texel = sampleTexture(fragTextureIndex, fragUv);
  outColor = vec4(texel.rgb * fragColor.rgb * light, texel.a * fragColor.a);
}
