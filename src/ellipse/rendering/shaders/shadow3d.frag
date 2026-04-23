#version 450

layout(location = 0) in vec3 fragWorldPosition;
layout(location = 0) out float outDepth;

layout(set = 3, binding = 0, std140) uniform ShadowPassFragmentUniforms {
  vec4 lightPositionFarMode;
} shadowPass;

void main() {
  if (shadowPass.lightPositionFarMode.w > 0.0) {
    outDepth = clamp(
      length(fragWorldPosition - shadowPass.lightPositionFarMode.xyz) / shadowPass.lightPositionFarMode.w,
      0.0,
      1.0
    );
  } else {
    outDepth = gl_FragCoord.z;
  }
}
