#!/usr/bin/env bash
set -euo pipefail

mode="${1:-spirv}"
if [[ "$mode" != spirv && "$mode" != dxil ]]; then
  echo "usage: $0 [spirv|dxil]" >&2
  exit 2
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$project_root/build/shaders"
mkdir -p "$output_dir"

glsl_compiler="${GLSL_COMPILER:-}"
if [[ -z "$glsl_compiler" ]]; then
  glsl_compiler="$(command -v glslangValidator || command -v glslc || true)"
fi
if [[ -z "$glsl_compiler" ]]; then
  echo "error: glslangValidator or glslc is required" >&2
  exit 1
fi

if [[ "$mode" == dxil ]]; then
  spirv_cross="${SPIRV_CROSS:-$(command -v spirv-cross || true)}"
  dxc="${DXC:-$(command -v dxc || true)}"
  if [[ -z "$spirv_cross" || -z "$dxc" ]]; then
    echo "error: spirv-cross and dxc are required for DXIL shaders" >&2
    exit 1
  fi
  scratch_dir="$(mktemp -d)"
  trap 'rm -rf -- "$scratch_dir"' EXIT
fi

for shader in "$project_root"/shaders/*.vert "$project_root"/shaders/*.frag; do
  stage="${shader##*.}"
  name="$(basename "$shader")"
  spirv="$output_dir/$name.spv"
  case "${glsl_compiler##*/}" in
    glslangValidator*) "$glsl_compiler" -V -S "$stage" "$shader" -o "$spirv" ;;
    *) "$glsl_compiler" -fshader-stage="$stage" "$shader" -o "$spirv" ;;
  esac

  if [[ "$mode" == dxil ]]; then
    hlsl="$scratch_dir/$name.hlsl"
    "$spirv_cross" "$spirv" --hlsl --shader-model 60 --output "$hlsl"
    if [[ "$stage" == vert ]]; then
      profile=vs_6_0
    else
      profile=ps_6_0
    fi
    "$dxc" -T "$profile" -E main "$hlsl" -Fo "$output_dir/$name.dxil"
  fi
done
