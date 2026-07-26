#version 450

layout(location = 0) in vec3 vWorldPosition;
layout(location = 1) in vec3 vNormal;

layout(location = 0) out vec4 outColor;

layout(set = 3, binding = 0) uniform Lighting {
  vec3 uCameraPosition;
};

void main() {
  vec3 normal = normalize(vNormal);
  vec3 lightDirection = normalize(vec3(-0.45, 0.85, -0.35));
  vec3 viewDirection = normalize(uCameraPosition - vWorldPosition);
  vec3 reflectDirection = reflect(-lightDirection, normal);

  float diffuse = max(dot(normal, lightDirection), 0.0);
  float specular = pow(max(dot(viewDirection, reflectDirection), 0.0), 32.0);
  vec3 baseColor = vec3(0.9, 0.52, 0.22);
  vec3 color = baseColor * (0.22 + diffuse * 0.72) + vec3(1.0, 0.9, 0.68) * specular * 0.35;
  outColor = vec4(color, 1.0);
}
