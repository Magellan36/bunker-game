#!/usr/bin/env bash
# Import and boot with isolated user data; never patch project.godot.
set -euo pipefail
GODOT_BIN="${1:-${GODOT_BIN:-godot4}}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v "$GODOT_BIN" >/dev/null || { echo "Godot not found: $GODOT_BIN" >&2; exit 1; }
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bunker-check.XXXXXX")"
export XDG_DATA_HOME="$CHECK_DIR/data"
export XDG_CACHE_HOME="$CHECK_DIR/cache"
export XDG_CONFIG_HOME="$CHECK_DIR/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
python3 "$PROJECT_DIR/tools/configure_linux_editor.py" --godot "$GODOT_BIN"
echo "Engine: $("$GODOT_BIN" --version)"
echo "Logs and isolated user data: $CHECK_DIR"
run_check() {
  local name="$1"
  shift
  local result=0
  timeout "${GODOT_CHECK_TIMEOUT:-600}" "$GODOT_BIN" --headless --path "$PROJECT_DIR" "$@" > "$CHECK_DIR/$name.log" 2>&1 || result=$?
  if (( result != 0 )) || grep -qE '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:)' "$CHECK_DIR/$name.log"; then
    cat "$CHECK_DIR/$name.log"
    echo "FAIL: $name (exit $result). See $CHECK_DIR/$name.log" >&2
    return 1
  fi
}
run_check import --import
run_check boot --quit-after 120
run_check world res://scenes/world/MainWorld.tscn --quit-after 120
run_check migration --script res://tools/tests/linux_portability_smoke.gd
echo "PASS: import, character creation, world startup, and platform migration; no engine/script errors."
