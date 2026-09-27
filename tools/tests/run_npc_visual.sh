#!/usr/bin/env bash
# Renders the NPC harness with a real (software) OpenGL renderer under Xvfb
# and saves PNG frames. Needs Xvfb + Mesa (llvmpipe).
# Usage: tools/tests/run_npc_visual.sh --capture=/abs/dir --cam=px,py,pz,lx,ly,lz --shots=t0:count:dt[;...] [harness args]
GODOT_BIN="${GODOT_BIN:-godot4}"
cd "$(dirname "$0")/../.."
OUT="$(mktemp)"
LIBGL_ALWAYS_SOFTWARE=1 timeout "${SIM_TIMEOUT:-1800}" xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT_BIN" --rendering-method gl_compatibility --rendering-driver opengl3 --fixed-fps 60 \
  --resolution 1280x720 --path . res://tools/tests/NPCSimHarness.tscn -- "$@" > "$OUT" 2>&1
CODE=$?
grep -E "^\[harness\]|^\[capture\]|^\[tl\]|RESULT|══" "$OUT"
echo "(full log: $OUT) exit=$CODE"
