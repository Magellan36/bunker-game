# Fix: JobBoard Stale Target After Harvest + F7 NPC↔NPC Relationship Buttons (Aug 2026)

**Files:** `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/ui/menus/AdminMenu.gd`.

## Part A — Bug fix

### `scripts/npc/JobBoard.gd`

**Anchor:** the current `get_open_jobs()`:

```gdscript
func get_open_jobs() -> Array:
	var out: Array = []
	for job: Dictionary in _jobs.values():
		var claimant: Node = job.get("claimed_by")
		if claimant != null and not is_instance_valid(claimant):
			job["claimed_by"] = null   ## claimant vanished — auto-release
		if job.get("claimed_by") == null:
			out.append(job)
	return out
```

Replace with:

```gdscript
func get_open_jobs() -> Array:
	var out: Array = []
	for id: String in _jobs.keys().duplicate():
		var job: Dictionary = _jobs[id]
		var target: Node = job.get("target")
		if target == null or not is_instance_valid(target):
			## Target vanished (harvested/freed, etc.) — drop immediately
			## rather than waiting for the next _rescan() (up to
			## SCAN_INTERVAL later). This is what was letting a
			## just-harvested, already-freed plant get handed to a
			## DIFFERENT NPC's JobActivity.score() as if it were still
			## open — Godot flags the freed reference the moment it's
			## assigned to a typed Node var, before score()'s own
			## is_instance_valid() check even runs.
			_jobs.erase(id)
			continue
		var claimant: Node = job.get("claimed_by")
		if claimant != null and not is_instance_valid(claimant):
			job["claimed_by"] = null   ## claimant vanished — auto-release
		if job.get("claimed_by") == null:
			out.append(job)
	return out
```

**Anchor:** the current `still_valid()`:

```gdscript
func still_valid(job: Dictionary) -> bool:
	return _jobs.has(job.get("id", ""))
```

Replace with:

```gdscript
func still_valid(job: Dictionary) -> bool:
	if not _jobs.has(job.get("id", "")):
		return false
	var target: Node = job.get("target")
	return target != null and is_instance_valid(target)
```

(This second one covers an NPC already mid-work on a job whose target
gets freed some other way before they finish — same class of gap, same
fix shape.)

---

## Part B — F7: NPC↔NPC relationship ±25 (all pairs)

### `scripts/npc/NPC.gd`

**Anchor:** the existing `debug_adjust_player_relationship()`:

```gdscript
func debug_adjust_player_relationship(delta: float) -> void:
	var current: float = get_relationship("player")
	relationships["player"] = clampf(current + delta, RELATIONSHIP_MIN, RELATIONSHIP_MAX)
```

Replace with:

```gdscript
func debug_adjust_relationship(target_id: String, delta: float) -> void:
	var current: float = get_relationship(target_id)
	relationships[target_id] = clampf(current + delta, RELATIONSHIP_MIN, RELATIONSHIP_MAX)

func debug_adjust_player_relationship(delta: float) -> void:
	debug_adjust_relationship("player", delta)
```

### `scripts/ui/menus/AdminMenu.gd`

**Anchor:** the NPC section's row list — add two rows anywhere among the
existing relationship buttons:

```gdscript
			["NPC↔NPC Relationship -25 (All Pairs)", _on_npc_npc_relationship_down_pressed],
			["NPC↔NPC Relationship +25 (All Pairs)", _on_npc_npc_relationship_up_pressed],
```

**Anchor:** near the existing `_adjust_all_npc_relationship()` handler —
add:

```gdscript
func _on_npc_npc_relationship_down_pressed() -> void: _adjust_all_npc_npc_relationships(-25.0)
func _on_npc_npc_relationship_up_pressed() -> void:   _adjust_all_npc_npc_relationships(25.0)

## Adjusts every DIRECTED pair independently (A's feeling toward B, and
## B's feeling toward A, separately) — relationships are one-sided per
## NPC, same as everywhere else in this system.
func _adjust_all_npc_npc_relationships(delta: float) -> void:
	var npcs: Array = get_tree().get_nodes_in_group("npc")
	for npc: Node in npcs:
		if not is_instance_valid(npc) or not npc.has_method("debug_adjust_relationship"):
			continue
		for other: Node in npcs:
			if other == npc or not is_instance_valid(other) or not ("npc_id" in other):
				continue
			npc.debug_adjust_relationship(other.npc_id, delta)
```

## Testing

```
49. Harvest multiple ready plants back-to-back with 2+ NPCs farming
    actively — confirm no "freed instance" errors in the console, even
    under repeated rapid harvesting.
50. Press F7 "NPC↔NPC Relationship +25 (All Pairs)" a few times — confirm
    every NPC's relationship toward every OTHER NPC rises (check via each
    NPC's F7 relationship visualizer), not just toward the player.
```
