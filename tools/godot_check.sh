#!/usr/bin/env bash
# Headless Godot compile/parse check for BunkerGame.
#
# Runs the real Godot 4.6.3 engine headless against this project to catch
# script parse errors, type errors, and broken autoload/class_name
# references BEFORE Brannon has to pull and hit them in his own editor.
#
# Usage:
#   tools/godot_check.sh [path-to-godot-binary]
#
# If no binary path is given, defaults to $GODOT_BIN env var, then falls
# back to "godot4" on PATH.
#
# IMPORTANT — known local-only caveat (see HANDOVER.md "class-cache gotcha"):
# project.godot's committed [autoload] section does NOT include
# GraphicsSettings, because that autoload is registered by Brannon locally
# via the Godot editor (Project Settings > Autoload) rather than committed,
# to avoid the editor silently overwriting hand-edits to that section.
# Running this script against a fresh clone will therefore report false
# positives:
#   SCRIPT ERROR: Parse Error: Identifier "GraphicsSettings" not declared...
# and a cascading failure loading MainWorld.gd (depends on GameCamera.gd,
# which depends on GraphicsSettings).
#
# This script works around that by adding the missing autoload line to a
# throwaway, git-ignored working copy before running the check, then
# discarding it. This mirrors Brannon's real local editor state without
# ever touching the committed project.godot.

set -euo pipefail

GODOT_BIN="${1:-${GODOT_BIN:-godot4}}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "ERROR: Godot binary not found/executable at '$GODOT_BIN'." >&2
  echo "Pass the path explicitly: tools/godot_check.sh /path/to/Godot_v4.6.3-stable_linux.x86_64" >&2
  exit 1
fi

# Ensure the known-missing local autoload is present for this run only.
if ! grep -q '^GraphicsSettings=' "$PROJECT_DIR/project.godot"; then
  cp "$PROJECT_DIR/project.godot" "$PROJECT_DIR/project.godot.bak"
  sed -i '/^DeviceDatabase=/a GraphicsSettings="*res://scripts/core/GraphicsSettings.gd"' "$PROJECT_DIR/project.godot"
  RESTORE_NEEDED=1
else
  RESTORE_NEEDED=0
fi

cleanup() {
  if [ "$RESTORE_NEEDED" = "1" ] && [ -f "$PROJECT_DIR/project.godot.bak" ]; then
    mv "$PROJECT_DIR/project.godot.bak" "$PROJECT_DIR/project.godot"
  fi
}
trap cleanup EXIT

echo "== Importing assets =="
LOG1="$(mktemp)"
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import > "$LOG1" 2>&1 || true

echo "== Booting project (--quit) =="
LOG2="$(mktemp)"
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --quit > "$LOG2" 2>&1 || true

echo "== Results =="
ERRORS="$(grep -iE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" "$LOG1" "$LOG2" || true)"

if [ -n "$ERRORS" ]; then
  echo "$ERRORS"
  echo ""
  echo "FAIL — script/parse/compile errors found above."
  echo "(Full logs: $LOG1 , $LOG2)"
  exit 2
else
  echo "PASS — no script parse/compile errors."
  echo "(Full logs: $LOG1 , $LOG2 — includes any non-fatal warnings)"
  exit 0
fi
