#!/usr/bin/env bash
# Usage: GODOT_BIN=/path/to/godot bash tools/linux_launch.sh [editor|play|compatibility]
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$PROJECT_DIR/.local-tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}"
command -v "$GODOT_BIN" >/dev/null || { echo "Set GODOT_BIN to the Godot 4.7.2 Linux executable." >&2; exit 1; }
case "${1:-editor}" in
  editor) exec "$GODOT_BIN" --path "$PROJECT_DIR" --editor ;;
  play) exec "$GODOT_BIN" --path "$PROJECT_DIR" ;;
  compatibility) exec "$GODOT_BIN" --path "$PROJECT_DIR" --rendering-method gl_compatibility --rendering-driver opengl3 ;;
  *) echo "Usage: $0 [editor|play|compatibility]" >&2; exit 2 ;;
esac
