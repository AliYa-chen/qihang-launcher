#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
mkdir -p "$project_dir/android-runtime"
"$godot_bin" --headless --path "$project_dir/godot" --script "$project_dir/scripts/export-runtime.gd"
