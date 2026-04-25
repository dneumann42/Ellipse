#version 450

layout(location = 0) in vec2 fragUv;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec4 fragColor;
layout(location = 3) flat in int fragTextureIndex;
layout(location = 4) in vec3 fragLightingPosition;
layout(location = 5) in vec3 fragWorldPosition;
layout(location = 6) in float fragViewDepth;

layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform sampler2D textures3D[8];
layout(set = 2, binding = 8) uniform sampler2D sunShadowMaps[3];
layout(set = 2, binding = 11) uniform samplerCube pointShadowMaps[2];

layout(set = 3, binding = 0, std140) uniform LightingUniforms {
  mat4 sunShadowMatrices[3];
  vec4 cascadeSplits;
  vec4 sunShadowTexelSize[3];
  vec4 ambientColor;
  vec4 textureSize;
  vec4 sunDirectionIntensity;
  vec4 sunColorEnabled;
  vec4 sunShadowParams;
  vec4 pointShadowParams;
  vec4 pointLightPositionRadius[8];
  vec4 pointLightColorIntensity[8];
  vec4 pointLightFalloffShadow[8];
  vec4 fogTintDensity;
  vec4 cameraPosition;
} lighting;

layout(set = 3, binding = 1, std140) uniform BatchLightingUniforms {
  vec4 flags;
} batchLighting;

const int DIRECTIONAL_SHADOW_MODE_CAMERA_CASCADED = 0;
const int DIRECTIONAL_SHADOW_MODE_WORLD_STABLE = 1;

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

float sampleSunShadow(int cascadeIndex, vec3 worldPosition, vec3 normal) {
  int cascadeCount = int(lighting.cascadeSplits.w + 0.5);
  if (cascadeIndex < 0 || cascadeIndex >= cascadeCount) {
    return 1.0;
  }

  vec3 biasedWorldPosition = worldPosition + normal * lighting.sunShadowParams.y;
  vec4 shadowPosition = lighting.sunShadowMatrices[cascadeIndex] * vec4(biasedWorldPosition, 1.0);
  vec3 ndc = shadowPosition.xyz / max(shadowPosition.w, 0.000001);
  vec3 uvw = vec3(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, ndc.z);
  if (uvw.x < 0.0 || uvw.x > 1.0 || uvw.y < 0.0 || uvw.y > 1.0 || uvw.z < 0.0 || uvw.z > 1.0) {
    return 1.0;
  }

  float bias = lighting.sunShadowParams.x;
  float filterRadius = lighting.sunShadowParams.z;
  vec2 texel = lighting.sunShadowTexelSize[cascadeIndex].xy;
  float lit = 0.0;
  float taps = 0.0;
  for (int y = -1; y <= 1; ++y) {
    for (int x = -1; x <= 1; ++x) {
      vec2 offset = vec2(x, y) * texel * filterRadius;
      float closest = texture(sunShadowMaps[cascadeIndex], uvw.xy + offset).r;
      lit += (uvw.z - bias <= closest) ? 1.0 : 0.0;
      taps += 1.0;
    }
  }
  return lit / max(taps, 1.0);
}

void main() {
  vec3 normal = normalize(fragNormal);
  vec4 texel = sampleTexture(fragTextureIndex, fragUv);
  if (texel.a <= 0.01) {
    discard;
  }

  vec3 shadedLight = lighting.ambientColor.rgb;
  if (batchLighting.flags.x > 0.5) {
    if (lighting.sunColorEnabled.w > 0.5 && lighting.sunDirectionIntensity.w > 0.0) {
      vec3 lightDirection = normalize(-lighting.sunDirectionIntensity.xyz);
      float lambert = max(dot(normal, lightDirection), 0.0);
      if (lambert > 0.0) {
        int cascadeIndex = 0;
        int shadowMode = int(lighting.sunShadowParams.w + 0.5);
        int cascadeCount = int(lighting.cascadeSplits.w + 0.5);
        if (shadowMode == DIRECTIONAL_SHADOW_MODE_CAMERA_CASCADED) {
          if (cascadeCount > 1 && fragViewDepth > lighting.cascadeSplits.x) {
            cascadeIndex = 1;
          }
          if (cascadeCount > 2 && fragViewDepth > lighting.cascadeSplits.y) {
            cascadeIndex = 2;
          }
        } else if (shadowMode == DIRECTIONAL_SHADOW_MODE_WORLD_STABLE) {
          cascadeIndex = 0;
        }
        shadedLight += lighting.sunColorEnabled.rgb *
          lighting.sunDirectionIntensity.w *
          lambert *
          sampleSunShadow(cascadeIndex, fragLightingPosition, normal);
      }
    }

    int pointLightCount = int(lighting.pointShadowParams.x + 0.5);
    for (int i = 0; i < pointLightCount && i < 8; ++i) {
      vec3 lightPosition = lighting.pointLightPositionRadius[i].xyz;
      float radius = lighting.pointLightPositionRadius[i].w;
      if (radius <= 0.0) {
        continue;
      }
      vec3 toLight = lightPosition - fragLightingPosition;
      float distanceToLight = length(toLight);
      if (distanceToLight >= radius || distanceToLight <= 0.00001) {
        continue;
      }

      vec3 lightDirection = toLight / distanceToLight;
      float lambert = max(dot(normal, lightDirection), 0.0);
      if (lambert <= 0.0) {
        continue;
      }

      float attenuation = pow(max(0.0, 1.0 - distanceToLight / radius), lighting.pointLightFalloffShadow[i].x) *
        lighting.pointLightColorIntensity[i].w;

      float visibility = 1.0;
      int shadowIndex = int(round(lighting.pointLightFalloffShadow[i].y));
      if (shadowIndex >= 0 && shadowIndex < int(lighting.pointShadowParams.y + 0.5)) {
        vec3 biasedSamplePosition = fragLightingPosition + normal * lighting.pointLightFalloffShadow[i].z;
        vec3 shadowVector = biasedSamplePosition - lightPosition;
        float currentDepth = length(shadowVector) / radius;
        vec3 sampleDirection = normalize(vec3(shadowVector.x, -shadowVector.y, shadowVector.z));
        float storedDepth = texture(pointShadowMaps[shadowIndex], sampleDirection).r;
        float delta = currentDepth - storedDepth - lighting.pointShadowParams.z;
        visibility = 1.0 - smoothstep(0.0, lighting.pointShadowParams.w, delta);
      }

      shadedLight += lighting.pointLightColorIntensity[i].rgb * attenuation * lambert * visibility;
    }
  } else {
    shadedLight = vec3(1.0);
  }

  vec3 color = texel.rgb * fragColor.rgb * shadedLight;
  if (batchLighting.flags.x > 0.5) {
    float fogDensity = max(lighting.fogTintDensity.w, 0.0);
    if (fogDensity > 0.0) {
      float distanceToCamera = length(fragWorldPosition - lighting.cameraPosition.xyz);
      float fogAmount = clamp(1.0 - exp(-distanceToCamera * fogDensity), 0.0, 1.0);
      color = mix(color, lighting.fogTintDensity.rgb, fogAmount);
    }
  }
  outColor = vec4(color, texel.a * fragColor.a);
}
