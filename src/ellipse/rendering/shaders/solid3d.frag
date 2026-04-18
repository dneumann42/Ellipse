#version 450

layout(location = 0) in vec2 fragUv;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec4 fragColor;
layout(location = 3) flat in int fragTextureIndex;
layout(location = 4) in vec3 fragLightingPosition;

layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform sampler2D textures3D[8];
layout(set = 2, binding = 8) uniform sampler2D gridLightTexture;

layout(set = 3, binding = 0, std140) uniform GridLightingUniforms {
  vec4 originCellSize;
  vec4 gridSamples;
  vec4 textureSize;
} gridLighting;

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

vec3 sampleGridLight(vec3 worldPosition, vec3 normal) {
  if (gridLighting.originCellSize.w < 0.5) {
    return vec3(1.0);
  }

  float cellSize = gridLighting.originCellSize.z;
  vec2 biasedPosition = worldPosition.xz - normal.xz * cellSize * 0.01;
  vec2 gridPosition = (biasedPosition - gridLighting.originCellSize.xy) / cellSize;
  vec2 cellFloat = floor(gridPosition);
  vec2 gridSize = gridLighting.gridSamples.xy;
  if (cellFloat.x < 0.0 || cellFloat.y < 0.0 ||
      cellFloat.x >= gridSize.x || cellFloat.y >= gridSize.y) {
    return vec3(1.0);
  }

  vec2 local = clamp(fract(gridPosition), vec2(0.0), vec2(1.0));
  float samplesPerCell = gridLighting.gridSamples.z;
  float blockStride = gridLighting.gridSamples.w;
  vec2 samplePosition = cellFloat * blockStride + vec2(1.0) +
    local * max(vec2(samplesPerCell - 1.0), vec2(0.0)) + vec2(0.5);
  vec2 uv = samplePosition * gridLighting.textureSize.zw;
  return texture(gridLightTexture, uv).rgb;
}

void main() {
  vec3 normal = normalize(fragNormal);
  vec3 lightDir = normalize(vec3(-0.45, 0.75, 0.55));
  float diffuse = max(dot(normal, lightDir), 0.0);
  float detailLight = 1.0 + diffuse * 0.18;
  vec3 gridLight = sampleGridLight(fragLightingPosition, normal);
  vec4 texel = sampleTexture(fragTextureIndex, fragUv);
  outColor = vec4(texel.rgb * fragColor.rgb * gridLight * detailLight, texel.a * fragColor.a);
}
