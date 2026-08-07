# Defensive Fix: Guard Recently-Added Cross-File NPC Calls (Aug 2026)

**File:** `scripts/npc/NPCBrain.gd` only.

## Why this approach

Exhaustive verification (mini-lexer for unterminated strings, full
bracket/paren/quote balance check, duplicate-declaration search, scene
script-reference check) confirms `NPC.gd`'s source is correct — there is
no text-level bug to fix. Given a full `.godot` deletion didn't resolve
it either, this is most likely a Godot-specific class-resolution quirk
with mutually-referencing `class_name`'d scripts (`NPC.gd` ↔
`NPCBrain.gd` reference each other's types), specifically affecting the
newest batch of cross-file method calls.

Every other cross-file call in this codebase already goes through a
`has_method()` guard as standing practice (e.g. `if
_partner.has_method("end_talk_session"): ...`). The handful of calls
added in the last two plans (Talk cooldown, Snatch pair cooldown,
hostile log) are the only ones that skipped it. Applying the same
pattern here stops the crash regardless of whether the underlying cause
is ever fully pinned down — if `has_method()` also can't resolve it, the
code just treats the feature as unavailable for that call instead of
throwing.

## Changes

**Anchor:** `TalkActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0
		if npc.is_talk_on_cooldown():
			return 0.0
		if npc.find_talk_partner() == null:
			return 0.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0
		if npc.has_method("is_talk_on_cooldown") and npc.is_talk_on_cooldown():
			return 0.0
		if npc.find_talk_partner() == null:
			return 0.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

**Anchor:** `TalkActivity.exit()`:

```gdscript
		if _duration > 0.0:
			npc.start_talk_cooldown()   ## covers both natural completion and any interrupt/abort path
```

Replace with:

```gdscript
		if _duration > 0.0 and npc.has_method("start_talk_cooldown"):
			npc.start_talk_cooldown()   ## covers both natural completion and any interrupt/abort path
```

**Anchor:** `SnatchActivity.tick()` — the block added for the hostile
log and pair cooldown:

```gdscript
		if _target != null and is_instance_valid(_target):
			var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
			npc.start_snatch_cooldown_against(target_id)
			npc.update_hostile_log()
			if not _target.is_in_group("player"):
				npc.start_npc_snatch_pair_cooldown(target_id)
				_target.start_npc_snatch_pair_cooldown(npc.npc_id)   ## bidirectional
```

Replace with:

```gdscript
		if _target != null and is_instance_valid(_target):
			var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
			if npc.has_method("start_snatch_cooldown_against"):
				npc.start_snatch_cooldown_against(target_id)
			if npc.has_method("update_hostile_log"):
				npc.update_hostile_log()
			if not _target.is_in_group("player"):
				if npc.has_method("start_npc_snatch_pair_cooldown"):
					npc.start_npc_snatch_pair_cooldown(target_id)
				if _target.has_method("start_npc_snatch_pair_cooldown"):
					_target.start_npc_snatch_pair_cooldown(npc.npc_id)   ## bidirectional
```

**Anchor:** `SnatchActivity.enter()`:

```gdscript
	func enter(npc: NPC) -> void:
		NPCDebug.log_snatch(npc, "started",
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		npc.start_hostile_log()
		if _target != null and is_instance_valid(_target):
			npc.set_nav_target((_target as Node3D).global_position)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		NPCDebug.log_snatch(npc, "started",
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		if npc.has_method("start_hostile_log"):
			npc.start_hostile_log()
		if _target != null and is_instance_valid(_target):
			npc.set_nav_target((_target as Node3D).global_position)
```

**Anchor:** `SnatchActivity.exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		npc.end_hostile_log()
		_target = null
		_handoff = null
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		if npc.has_method("end_hostile_log"):
			npc.end_hostile_log()
		_target = null
		_handoff = null
```

## If this DOESN'T fix it

If the exact same "nonexistent function" error still appears after this
(now guarded by `has_method()`, which should be nearly impossible to
still crash from), that would be genuinely surprising and would point to
something even stranger — possibly worth testing whether ANY newly-added
method on `NPC.gd` has this issue (not just Talk-related ones), by
temporarily adding a trivial throwaway method (e.g. `func
_test_marker() -> bool: return true`) and checking from an existing,
already-working call site whether `has_method("_test_marker")` resolves
correctly. That would isolate whether this is truly about "brand new
methods on this class" as a category, or specific to these particular
ones.

## Testing

```
58. Spawn a fresh NPC — confirm no "nonexistent function" error appears
    at all now, immediately or otherwise.
59. Let Talk and Snatch mechanics run normally for several minutes —
    confirm cooldowns are still visibly taking effect (conversations
    space out, snatch pairs cool down) rather than silently no-op'ing
    due to the has_method() guards failing open.
```
