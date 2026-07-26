#version 450

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUv;
layout(location = 3) in vec2 aSplatUv;
layout(location = 4) in vec4 aSplatIndices;
layout(location = 5) in vec4 aSplatWeights;

layout(location = 0) out vec3 vWorldPosition;
layout(location = 1) out vec3 vNormal;
layout(location = 2) out vec2 vUv;
layout(location = 3) out vec2 vSplatUv;
layout(location = 4) out vec4 vSplatIndices;
layout(location = 5) out vec4 vSplatWeights;

layout(set = 1, binding = 0) uniform Transform {
  mat4 uModelViewProjection;
  mat4 uModel;
};

void main() {
  vec4 worldPosition = uModel * vec4(aPosition, 1.0);
  vWorldPosition = worldPosition.xyz;
  vNormal = normalize(mat3(uModel) * aNormal);
  vUv = aUv;
  vSplatUv = aSplatUv;
  vSplatIndices = aSplatIndices;
  vSplatWeights = aSplatWeights;
  gl_Position = uModelViewProjection * vec4(aPosition, 1.0);
}
