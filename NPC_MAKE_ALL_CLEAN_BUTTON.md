# F7 Debug: "Make All NPCs Clean" (Aug 2026)

**File:** `scripts/ui/menus/AdminMenu.gd`.

**Re-clone the repo fresh before starting.** Verify the anchor below
against the live file before editing.

---

## Fix

**Anchor:**

```gdscript
		{ "name": "NPC", "rows": [
			["Spawn NPC", _on_spawn_npc_pressed],
			["Spawn Neutral NPC (Testing)", _on_spawn_neutral_npc_pressed],
```

Replace with:

```gdscript
		{ "name": "NPC", "rows": [
			["Spawn NPC", _on_spawn_npc_pressed],
			["Spawn Neutral NPC (Testing)", _on_spawn_neutral_npc_pressed],
			["Make All NPCs Clean", _on_make_all_npcs_clean_pressed],
```

**Anchor:** immediately after the existing `_on_spawn_neutral_npc_pressed()`
(end of that function):

```gdscript
	if "personality" in npc:
		npc.personality = {}
	if "skills" in npc:
		for key: String in npc.skills.keys():
			npc.skills[key] = 1.0
```

Add immediately after it:

```gdscript

## Aug 2026 — force-starts every NPC in the level straight into Cleaning,
## bypassing normal scoring entirely (same force_command() path the
## player-issued Talk-menu "Clean the bunker" request uses via
## CommandCleaningActivity, just applied to every NPC at once instead of
## one at a time). Useful for clearing test clutter fast, and for
## isolating whether a reported cleaning issue is about the JOB-PICKING
## logic (never gets chosen) versus the cleaning behavior itself (chosen,
## but doesn't work right) — this button skips past the former entirely.
func _on_make_all_npcs_clean_pressed() -> void:
	var count: int = 0
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or not ("brain" in npc) or npc.brain == null:
			continue
		npc.brain.force_command(NPCBrain.CommandCleaningActivity.new())
		count += 1
	print("[AdminMenu] Forced %d NPC(s) into Cleaning" % count)
```

Stop and report on anchor mismatch — no improvisation.

## Testing

1. With several NPCs doing various things (wandering, sitting, eating),
   press "Make All NPCs Clean" — confirm every one immediately switches
   to Cleaning (or reports nothing to clean, if genuinely nothing's
   organizable for them specifically — e.g. all storage full/no reach).
2. Confirm the console prints the forced count, and each NPC's own
   `CLEANING [...]` debug lines still appear normally if NPC Debug
   Logging is on.

## Documentation

### `docs/systems/npc/README.md` — append to the checklist:

```
84. Press F7 → "Make All NPCs Clean" with several NPCs mid-activity —
    confirm every one immediately force-switches into Cleaning.
```

### `HANDOVER.md` — append:

```
## NPC: F7 "Make All NPCs Clean" (Aug 2026)

- Added a debug row that force_command()s every NPC in the "npc" group
  straight into CommandCleaningActivity at once, for fast test-clutter
  cleanup and to isolate job-picking issues from cleaning-behavior ones.

Files touched: `scripts/ui/menus/AdminMenu.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
