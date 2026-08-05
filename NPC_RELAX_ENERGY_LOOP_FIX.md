# Fix: Relaxing In a Chair/Bed Loops When Energy Is Already Full (Aug 2026)

**File:** `scripts/npc/NPCBrain.gd` only.

## Confirmed root cause

`LieActivity.done()`: `return _lying and npc.energy >= LIE_UNTIL_ENERGY`
(100.0). `SitActivity.done()` is the same pattern at 90.0. `RelaxActivity`
delegates to these directly via `enter()`, bypassing their `score()`
gates entirely (which is correct — score() being blocked at high energy
should NOT stop a scheduled relax session) — but `done()` isn't
bypassed, and it doesn't care HOW it was entered. If energy is already at
or above the threshold the instant `_seated`/`_lying` flips true,
`done()` is already true on the very next check — stand back up, RelaxActivity
re-selects, tries the same chair/bed again, same result. Confirmed this is
exactly what's happening, not a guess.

## Fix

Two new dedicated activities — `RelaxSitActivity`/`RelaxLieActivity` —
used only by `RelaxActivity`'s delegation, never scored/selected
directly. Same arrival/seating mechanics as `SitActivity`/`LieActivity`
(inherited via `extends`, only `tick()`/`done()`/`label()`/`score()`
overridden), with two changes:
- `done()` no longer checks energy at all — ending is entirely
  `RelaxActivity`'s own session-length timer's job, not energy.
- Energy regen while seated/lying runs at **1/4** the normal rate (a
  relaxing break, not full rest/sleep).

### `scripts/npc/NPCBrain.gd`

**Anchor:** add these two classes anywhere near `SitActivity`/
`LieActivity` (e.g. immediately after each, respectively).

```gdscript
class RelaxSitActivity extends SitActivity:
	## Relaxing in a chair (Aug 2026) — delegation-only, never auto-
	## selected. Unlike SitActivity, does NOT end just because energy
	## reached SIT_UNTIL_ENERGY — without this override, an NPC already
	## at/above that energy would sit down, have done()==true the instant
	## _seated flips, stand right back up, and loop with RelaxActivity
	## re-selecting the same chair every think-cycle. RelaxActivity's own
	## session-length timer is what ends this instead. Energy still
	## regenerates, just at 1/4 the normal rate — a break, not full rest.
	const RELAX_ENERGY_REGEN_MULT: float = 0.25

	func label() -> String:
		return "Relaxing (Sitting)" if _seated else "Finding a seat"

	func score(_npc: NPC) -> float:
		return 0.0   ## delegation-only

	func tick(npc: NPC, delta: float) -> void:
		if _chair == null or not is_instance_valid(_chair):
			_chair = null
			return
		if _seated:
			npc.energy = minf(100.0, npc.energy
				+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))
			return
		npc.nav_steer(delta)
		var chair_pos: Vector3 = (_chair as Node3D).global_position
		var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
			.distance_to(Vector2(chair_pos.x, chair_pos.z))
		if npc.nav_finished() or flat_dist < 0.9:
			if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
				_seated = true
				var t: Transform3D = _chair.get_seat_transform()
				npc.global_position = t.origin
				npc.rotation.y = t.basis.get_euler().y
				npc.lock_movement()
			else:
				_chair = null   ## someone took it

	func done(npc: NPC) -> bool:
		return _chair == null   ## energy is NOT a completion condition here
```

```gdscript
class RelaxLieActivity extends LieActivity:
	## Relaxing in bed (Aug 2026) — same reasoning as RelaxSitActivity,
	## mirrored for beds.
	const RELAX_ENERGY_REGEN_MULT: float = 0.25

	func label() -> String:
		return "Relaxing (Lying down)" if _lying else "Finding a bed"

	func score(_npc: NPC) -> float:
		return 0.0   ## delegation-only

	func tick(npc: NPC, delta: float) -> void:
		if _bed == null or not is_instance_valid(_bed):
			_bed = null
			return
		if _lying:
			npc.energy = minf(100.0, npc.energy
				+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))
			return
		npc.nav_steer(delta)
		var bed_pos: Vector3 = (_bed as Node3D).global_position
		var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
			.distance_to(Vector2(bed_pos.x, bed_pos.z))
		if npc.nav_finished() or flat_dist < 1.1:
			if _bed.has_method("npc_try_lie") and _bed.npc_try_lie(npc):
				_lying = true
				_orig_rotation = npc.rotation
				npc.lock_movement()
				var t: Transform3D = _bed.get_lie_transform()
				npc.global_position = t.origin
				npc.rotation = t.basis.get_euler()
			else:
				_bed = null   ## someone took it

	func done(npc: NPC) -> bool:
		return _bed == null   ## energy is NOT a completion condition here
```

**Anchor:** `RelaxActivity.enter()` (from the previous plan):

```gdscript
	func enter(npc: NPC) -> void:
		npc.reset_relax_job_requests()
		_session_length = randf_range(SESSION_MIN, SESSION_MAX)
		_session_elapsed = 0.0
		_inner = SitActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):   ## no free chair — try a bed instead
			_inner.exit(npc)
			_inner = LieActivity.new()
			_inner.enter(npc)
			if _inner.done(npc):   ## no free bed either — just stand in place
				_inner.exit(npc)
				_inner = null
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		npc.reset_relax_job_requests()
		_session_length = randf_range(SESSION_MIN, SESSION_MAX)
		_session_elapsed = 0.0
		_inner = RelaxSitActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):   ## no free chair — try a bed instead
			_inner.exit(npc)
			_inner = RelaxLieActivity.new()
			_inner.enter(npc)
			if _inner.done(npc):   ## no free bed either — just stand in place
				_inner.exit(npc)
				_inner = null
```

(`_inner.done(npc)` right after `enter()` now correctly means "no
chair/bed was found at all" — never "energy's already full" — so this
fallback chain still works exactly as intended.)

## Testing

1. Max an NPC's energy to 100 (F7), force/wait for a relax session with a
   free chair or bed nearby — confirm they sit/lie down and STAY there
   for the session duration, no in-and-out loop.
2. Confirm energy still very slowly climbs (if not already at 100) while
   relaxing in a chair/bed, at a visibly slower rate than normal
   resting/sleeping.
3. Confirm normal (non-relax) Sit/Lie behavior is completely unchanged —
   this only touches the new Relax-prefixed classes.
