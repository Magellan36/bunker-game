# Plan: Water Hookup Unconditional E-Priority (Aug 2026)

**Owner:** Player subsystem (this plan)
**Files touched:** `scripts/player/InteractionSystem.gd`,
`scripts/world/water/WaterHookup.gd` (one flagged file outside the usual
three — see note below).
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

**Scope note:** `WaterHookup.gd` is Water-system territory, not one of
my three core files. The change there is a single one-line group
registration (matching the exact pattern `GrowLight.gd`/`FarmingTray.gd`
already use for the grow-light override), so handling it directly and
flagging clearly, same approach as every other cross-thread touch this
session.

---

## Confirming the shape of the fix, since it matters

This is a different kind of override from grow-light-over-tray, on
purpose, matching what you described: not "beats one specific named
rival" (there's no single fixed thing Water Hookup competes with — it
can end up near a wall light, a breaker box, a terminal, whatever a
given bunker happens to have on that wall), but "wins over whatever else
is in range, unconditionally, whenever it's reachable at all."

**One consequence worth being explicit about before this lands:** the
whole point of `_nearest_generic_interactable()` — the function both the
real `E` dispatch (`_try_interact()`) and Focus Mode's highlight
(`_resolve_current_e_target()`) share — is that those two can never
disagree. Adding the override there means Water Hookup becomes the
unconditional `E` target **for a plain `E` press too, not just while
Ctrl/Focus Mode is held.** I considered scoping this to only affect
Focus Mode's highlight and leaving real `E`-dispatch alone, but that
would mean Ctrl shows you "reach the Water Hookup" and then a plain `E`
press does something else entirely — a worse bug than the one you're
asking me to fix, and it defeats the entire "guaranteed to never drift"
design the shared resolver exists for. Implementing it as a genuine,
always-on priority (which is also literally what you described — "make
it the #1 priority over other prompts") is the correct, consistent
version of this fix. Flagging it so it's a known, deliberate choice
rather than a surprise once you're testing it.

---

## Part 1 — `WaterHookup.gd`: add a duck-type marker group

Matches the exact pattern `GrowLight.gd`/`FarmingTray.gd` already
established (`add_to_group("grow_light")`/`add_to_group("farming_tray")`)
rather than a class-based `node is WaterHookup` check in
`InteractionSystem.gd` — keeps that file from needing to know about a
specific Water-system class by name.

**Anchor:** verified current lines 86–91.

```gdscript
old_str:
func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()
	call_deferred("_register_deferred")

new_str:
func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	## Duck-typed marker InteractionSystem._nearest_generic_interactable()
	## checks for ("water_hookup" group) to give this unconditional E-
	## priority over other nearby interactables — mounted high on the
	## wall, so it otherwise almost always loses fair-distance comparison
	## against lower-mounted wall objects (lights, breaker boxes, etc.)
	## that sit physically closer to a player standing on the ground.
	## Mirrors the "grow_light"/"farming_tray" marker pattern.
	add_to_group("water_hookup")
	_build_mesh()
	call_deferred("_register_deferred")
```

---

## Part 2 — `InteractionSystem._nearest_generic_interactable()`: the override

**Anchor:** verified current lines 1075–1101.

```gdscript
old_str:
	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	var nearest_grow_light: Node3D     = null
	var nearest_grow_light_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if not node.has_method("on_interact"):
			continue
		if node.is_in_group("shelved"):
			continue
		var n3: Node3D = node as Node3D
		var d: float = n3.global_position.distance_to(player_pos)
		if node.is_in_group("grow_light") and d < static_reach and d < nearest_grow_light_dist:
			nearest_grow_light_dist = d
			nearest_grow_light = n3
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	if nearest_grow_light != null and closest != null and closest.is_in_group("farming_tray"):
		closest      = nearest_grow_light
		closest_dist = nearest_grow_light_dist

	return { "node": closest, "dist": closest_dist }

new_str:
	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	var nearest_grow_light: Node3D     = null
	var nearest_grow_light_dist: float = INF
	var nearest_water_hookup: Node3D     = null
	var nearest_water_hookup_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if not node.has_method("on_interact"):
			continue
		if node.is_in_group("shelved"):
			continue
		var n3: Node3D = node as Node3D
		var d: float = n3.global_position.distance_to(player_pos)
		if node.is_in_group("grow_light") and d < static_reach and d < nearest_grow_light_dist:
			nearest_grow_light_dist = d
			nearest_grow_light = n3
		if node.is_in_group("water_hookup") and d < static_reach and d < nearest_water_hookup_dist:
			nearest_water_hookup_dist = d
			nearest_water_hookup = n3
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	if nearest_grow_light != null and closest != null and closest.is_in_group("farming_tray"):
		closest      = nearest_grow_light
		closest_dist = nearest_grow_light_dist

	## Aug 2026 — Water Hookup: unconditional top priority whenever in
	## reach at all, applied AFTER the grow-light override so it wins
	## even in the extremely unlikely case both would otherwise fire the
	## same frame. Deliberately unscoped, unlike the grow-light override
	## above (which only beats one specific named rival, FarmingTray) —
	## a Water Hookup can end up near any number of different wall-
	## mounted objects depending on how a given bunker is furnished, so
	## there's no single fixed rival worth naming; it simply always wins
	## over whatever else is in range. This also means a plain E press
	## (not just Focus Mode's Ctrl-held highlight) now always resolves to
	## the hookup when one's in reach — deliberate, not an oversight; see
	## this plan's own header for why decoupling the two would be worse.
	if nearest_water_hookup != null:
		closest      = nearest_water_hookup
		closest_dist = nearest_water_hookup_dist

	return { "node": closest, "dist": closest_dist }
```

---

## Why this is safe

- **The shelf-fairness fix from the last plan composes correctly with
  no further changes.** That fix compares the shelf's own distance
  against `_nearest_generic_interactable()`'s result — since Water
  Hookup's override lives inside that same function, a shelf near a
  Water Hookup still competes fairly (by true distance) against it, it
  doesn't get any special unfair treatment either way. Nothing extra
  needed there.
- **The grow-light-over-tray override is untouched and still applies
  first** — Water Hookup's override is a separate, independent check
  applied after it, not a replacement.
- **Every other interactable pairing is unaffected** — the new override
  only fires when a `"water_hookup"`-grouped node is actually in range;
  everything else still resolves by genuine fair distance exactly as
  before this plan.
- **Held-item behavior is completely untouched** — this function is
  only ever reached in the empty-handed fallback path (per the earlier
  "held-item E priority" fix), so nothing here interacts with Basket/
  Cooking Pot/Give/generic-on_use held-item dispatch at all.

---

## Verification checklist

1. Stand near a Water Hookup with a wall light mounted lower and closer
   — confirm `E` now targets the hookup, not the light (this is the
   reported bug).
2. Same test with a breaker box or other wall-mounted interactable
   nearby instead of a light — confirm the hookup still wins (unscoped
   override, not light-specific).
3. Hold Ctrl (Focus Mode) in the same scenario — confirm the hookup is
   the one prompt that stays visible, matching what plain `E` would do.
4. Stand near a Water Hookup AND a shelf — confirm the shelf still wins
   if it's genuinely closer, and the hookup still wins if it's closer
   (fair competition between the two, not an automatic hookup win).
5. Stand near a Water Hookup with nothing else nearby — confirm `E`
   still opens/interacts with it exactly as before (baseline regression
   check).
6. Stand near multiple non-hookup interactables with no Water Hookup in
   range at all — confirm normal fair-distance resolution, completely
   unaffected by this change.

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry:

```markdown
- **Water Hookup unconditional E-priority (Aug 2026,
  `WaterHookup.gd` — flagged: `scripts/world/water/`, not one of the
  three core files).** Mounted high on the wall, so it was almost always
  losing fair-distance comparison in `_nearest_generic_interactable()`
  against lower-mounted wall objects (lights, breaker boxes, etc.)
  physically closer to a player standing on the ground. Given a new
  `"water_hookup"` duck-type marker group (mirrors `"grow_light"`/
  `"farming_tray"`); `_nearest_generic_interactable()` now gives it
  unconditional top priority whenever one's in reach at all — unlike the
  narrow grow-light-over-tray override (which only beats one specific
  named rival), this is deliberately unscoped, since a Water Hookup has
  no single fixed competitor. Because both the real `E` dispatch and
  Focus Mode's highlight share this same function by design, a plain `E`
  press now also always resolves to a nearby hookup, not just Focus
  Mode's Ctrl-held highlight — deliberate, keeps the two from ever being
  able to disagree.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Water Hookup Unconditional E-Priority (Aug 2026)

## What changed this session
Fixed Water Hookup losing E-priority to nearby lower-mounted wall
objects (wall lights, breaker boxes, etc.) — being mounted high on the
wall meant it was almost always physically farther from a
ground-standing player than whatever else happened to share that wall,
so it kept losing the fair-distance comparison in
`_nearest_generic_interactable()`. Gave it a new `"water_hookup"`
duck-type marker group (`WaterHookup.gd`, mirrors the existing
`"grow_light"`/`"farming_tray"` pattern) and an unconditional top-
priority override in `_nearest_generic_interactable()` — unlike the
narrow grow-light-over-tray override (beats one specific named rival
only), this one is deliberately unscoped: a Water Hookup can end up near
any number of different wall-mounted objects depending on how a given
bunker is furnished, so there's no single fixed rival to name.

Worth noting explicitly: because both the real `E` dispatch
(`_try_interact()`) and Focus Mode's highlight
(`_resolve_current_e_target()`) share this same function by design, this
also makes a plain `E` press (not just Ctrl/Focus Mode) always resolve
to a nearby Water Hookup. Considered scoping the override to only affect
Focus Mode and leave real dispatch alone, but that would let the two
disagree — worse than the original bug, and against the entire point of
the shared-resolver design. Implemented as a genuine always-on priority
instead, per direct instruction.

### Files modified
- `scripts/world/water/WaterHookup.gd` — new `"water_hookup"` group
  registration.
- `scripts/player/InteractionSystem.gd` —
  `_nearest_generic_interactable()` gains the unconditional Water
  Hookup override, applied after the existing grow-light override.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_WATER_HOOKUP_E_PRIORITY_PLAN.md` for
the full 6-item checklist)
```
