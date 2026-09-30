#!/usr/bin/env bash
# Runs the headless NPC simulation harness and filters engine noise.
# Usage: tools/tests/run_npc_sim.sh [--scenario=basic] [--minutes=10] [--npcs=4] [--seed=1] [--verbose] [--timeline] [--combat-trace]
GODOT_BIN="${GODOT_BIN:-godot4}"
cd "$(dirname "$0")/../.."
OUT="$(mktemp)"
timeout "${SIM_TIMEOUT:-1800}" "$GODOT_BIN" --headless --fixed-fps 60 --path . \
  res://tools/tests/NPCSimHarness.tscn -- "$@" > "$OUT" 2>&1
CODE=$?
ERRS=$(grep -cE "SCRIPT ERROR|Invalid call|Invalid access|Invalid get|Invalid set|Nonexistent function|previously freed" "$OUT")
grep -E "^\[Combat\]|^\[cdebug\]|^\[combat\]|^\[harness\]|^\[VIOLATION|^\[tl\]|^Asleep|^\[capture\]|^\[scores\]|══|^Activity|^  |^NPC end|^VIOLATIONS|^RESULT|^    " "$OUT"
if [ "$ERRS" != "0" ]; then
  echo "SCRIPT ERRORS: $ERRS (first 20 unique):"
  grep -E -A2 "SCRIPT ERROR|Invalid call|Invalid access|Nonexistent function|previously freed" "$OUT" | grep -vE "^--$" | sort | uniq -c | sort -rn | head -20
  CODE=2
fi
echo "(full log: $OUT) exit=$CODE"
exit $CODE
