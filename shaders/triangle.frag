#version 450

layout(location = 0) in vec3 vWorldPosition;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec2 vUv;
layout(location = 3) in vec2 vSplatUv;
layout(location = 4) in vec4 vSplatIndices;
layout(location = 5) in vec4 vSplatWeights;

layout(location = 0) out vec4 outColor;

layout(set = 2, binding = 0) uniform sampler2D uTexture;

layout(set = 3, binding = 0) uniform Lighting {
  vec3 uCameraPosition;
  vec3 uBaseColor;
  float uUseTexture;
  vec4 uSplat;
  vec3 uFogNearColor;
  float uFogDensity;
  vec3 uFogFarColor;
  float uFogFalloff;
  float uFogLimit;
  float uSpecularStrength;
  vec2 uLightingPadding0;
  vec3 uLightDirection;
  float uAmbientStrength;
  vec3 uLightColor;
  float uDiffuseStrength;
  vec3 uSpecularColor;
  float uShininess;
  vec4 uUvRegion;
};

vec2 modelUv(vec2 uv) {
  return uUvRegion.xy + uv * uUvRegion.zw;
}

float fogAmountForDistance(float distanceToCamera) {
  float limit = max(uFogLimit, 0.001);
  float softFog = clamp(1.0 - exp(-distanceToCamera * max(uFogDensity, 0.0)), 0.0, 1.0);
  softFog = pow(softFog, max(uFogFalloff, 0.001));
  float cutoffFog = smoothstep(limit * 0.82, limit, distanceToCamera);
  return max(softFog, cutoffFog);
}

float fogVisibilityForDistance(float distanceToCamera) {
  float limit = max(uFogLimit, 0.001);
  return 1.0 - smoothstep(limit * 0.82, limit, distanceToCamera);
}

vec3 atlasSample(float tileIndex) {
  float columns = max(uSplat.y, 1.0);
  float rows = max(uSplat.z, 1.0);
  float tile = clamp(floor(tileIndex + 0.5), 0.0, columns * rows - 1.0);
  vec2 cell = vec2(mod(tile, columns), floor(tile / columns));
  vec2 uv = (cell + fract(vSplatUv)) / vec2(columns, rows);
  return texture(uTexture, uv).rgb;
}

vec3 splatSample() {
  vec4 weights = max(vSplatWeights, vec4(0.0));
  float total = dot(weights, vec4(1.0));
  if (total <= 0.0001) {
    return texture(uTexture, modelUv(vUv)).rgb;
  }
  weights /= total;
  return atlasSample(vSplatIndices.x) * weights.x +
    atlasSample(vSplatIndices.y) * weights.y +
    atlasSample(vSplatIndices.z) * weights.z +
    atlasSample(vSplatIndices.w) * weights.w;
}

void main() {
  float distanceToCamera = length(uCameraPosition - vWorldPosition);
  // Fade fragment coverage through the terminal fog band so the already-
  // rendered sky appears smoothly instead of being exposed by a hard slice.
  float fogVisibility = fogVisibilityForDistance(distanceToCamera);
  if (fogVisibility <= 0.001) {
    discard;
  }

  vec3 normal = normalize(vNormal);
  vec3 lightDirection = normalize(uLightDirection);
  vec3 viewDirection = normalize(uCameraPosition - vWorldPosition);
  vec3 reflectDirection = reflect(-lightDirection, normal);

  float diffuse = max(dot(normal, lightDirection), 0.0);
  float specular = pow(max(dot(viewDirection, reflectDirection), 0.0),
    max(uShininess, 1.0));
  vec3 baseColor = uUseTexture > 0.5
    ? (uSplat.x > 0.5 ? splatSample() : texture(uTexture, modelUv(vUv)).rgb)
    : uBaseColor;
  vec3 color = baseColor * (uAmbientStrength +
    uLightColor * diffuse * uDiffuseStrength) +
    uSpecularColor * specular * max(uSpecularStrength, 0.0);
  float fogAmount = fogAmountForDistance(distanceToCamera);
  vec3 fogColor = mix(uFogNearColor, uFogFarColor, fogAmount);
  outColor = vec4(mix(color, fogColor, fogAmount), fogVisibility);
}
