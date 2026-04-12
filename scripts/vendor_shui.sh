#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
develop_file="$repo_root/nimble.develop"
vendor_dir="$repo_root/vendor"
shui_dir="$vendor_dir/shui"

mkdir -p "$vendor_dir"

if [ -f "$shui_dir/shui.nimble" ]; then
  git -C "$shui_dir" fetch origin main
  git -C "$shui_dir" switch main
  git -C "$shui_dir" pull --ff-only origin main
  nimble --developFile:"$develop_file" develop -a:"$shui_dir"
else
  nimble --developFile:"$develop_file" develop --path:"$vendor_dir" https://github.com/dneumann42/shui.git
  git -C "$shui_dir" switch main
  git -C "$shui_dir" pull --ff-only origin main
fi

cd "$repo_root"
nimble setup
