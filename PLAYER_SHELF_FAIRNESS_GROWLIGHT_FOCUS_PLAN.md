# Plan: Shelf E-Priority Fairness + Grow Light Priority + Focus Mode E-Target Plumbing (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** Cross-thread hand-off
(`PLAYER_THREAD_HANDOFF_shelf_priority_growlight_focus_target.md`),
verified in full against the current on-disk state of
`scripts/player/InteractionSystem.gd` on 2026-08-09 — every anchor below
matches exactly what's currently on disk, including the `grow_light`/
`farming_tray` group names (confirmed via direct read of `GrowLight.gd`/
`FarmingTray.gd`, both `StaticBody3D` with their own `on_interact()`).
No corrections needed to the original hand-off's logic — this is a
straight adopt, reframed as an implementation-ready plan with the
documentation updates the original explicitly deferred.
**File touched:** `scripts/player/InteractionSystem.gd` only.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.
**Cross-thread dependency:** a separate UI-thread plan ("Focus Mode
Prompt Filter") depends on Part 6 below to have anything to filter on.
Order doesn't matter for crash-safety (per that plan's own notes), but
Focus Mode won't correctly highlight anything until this lands.

---

## What this fixes and adds

1. **Bugfix:** the empty-handed `E` handler gives a nearby shelf an
   unconditional win over every other world interactable, regardless of
   true distance — confirmed still live in the current dispatch (lines
   230–239). This is a different case from the "held-item E priority"
   fix earlier this session (that one made a *held item* always beat the
   shelf); this one is shelf-vs-*other-world-object* while empty-handed,
   e.g. a shelf stealing E from a generator that's genuinely closer.
   Fixed with the same fairness pattern already used elsewhere in this
   same handler (stove-with-pot, ready-dish).
2. **New feature:** grow lights now beat their own `FarmingTray`
   specifically in interact-target resolution — not a blanket
   "always wins nearby" rule, everything else still resolves by fair
   distance. Fixes lights being functionally unreachable because their
   tray sits directly beneath them and is almost always physically
   closer.
3. **New plumbing:** a read-only `_resolve_current_e_target()` peek
   (empty-handed case only) so a separate UI-thread Focus Mode feature
   can tag the exact prompt E would fire — guaranteed to never drift
   from what E actually does, since both paths share the same
   underlying scan.
4. **De-duplication:** `_nearest_interact_distance()` was hand-rolling
   almost the exact same two-pass scan `_try_interact()` itself already
   did — both now go through one shared `_nearest_generic_interactable()`.

---

## Part 1 — New shared scan: `_nearest_generic_interactable()`

Absorbs `_try_interact()`'s scan and `_nearest_interact_distance()`'s
scan into one function returning both the winning node and its
distance, plus the grow-light-over-tray override.

**Anchor:** verified current lines 987–1021.

```gdscript
old_str:
## Read-only peek at the distance to whatever _try_interact() would
## actually interact with, without triggering it — mirrors both of
## _try_interact()'s passes exactly. Used purely to fairly compare against
## the ready-dish special case above. Returns INF if nothing is eligible.
func _nearest_interact_distance() -> float:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF

	for body in bodies:
		if body.is_in_group("interactable") and body.has_method("on_interact"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d

	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
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
		if d < static_reach and d < closest_dist:
			closest_dist = d

	return closest_dist

new_str:
## Read-only peek at whatever _try_interact() would actually interact
## with, without triggering it — the ONE shared scan used by
## _try_interact() itself, _nearest_interact_distance() (kept as a thin
## distance-only wrapper below, several callers only need the number),
## the shelf E-priority fairness check, and Focus Mode's
## _resolve_current_e_target(). Returns { "node": Node3D or null, "dist":
## float (INF if nothing eligible) }.
##
## Aug 2026 — added the grow-light-over-tray override: a GrowLight sits
## on the ceiling directly above its FarmingTray (the intended setup), so
## the tray is almost always physically closer to the player and would
## otherwise always win here. Deliberately narrow — only overrides when
## a FarmingTray specifically would otherwise win and a grow light is
## also in reach. Every other pair of nearby interactables (shelves,
## generators, anything else near a grow light) still resolves by
## genuine fair distance, unaffected.
func _nearest_generic_interactable() -> Dictionary:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest: Node3D     = null
	var closest_dist: float = INF

	for body in bodies:
		if body.is_in_group("interactable") and body.has_method("on_interact"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

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

## Thin distance-only wrapper — several existing callers (the ready-dish
## fairness check below) only need the number, not the node.
func _nearest_interact_distance() -> float:
	return float(_nearest_generic_interactable()["dist"])
```

---

## Part 2 — `_try_interact()` uses the shared scan

**Anchor:** verified current lines 1054–1108 (the entire function).

```gdscript
old_str:
func _try_interact() -> void:
	## Seated players always stand, regardless of what else is nearby —
	## checked first, before any proximity scan, so a chair can never lose
	## a closest-distance comparison to some other interactable.
	if player.seated_chair != null and is_instance_valid(player.seated_chair):
		player.seated_chair.on_interact()
		return

	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest: Node3D     = null
	var closest_dist: float = INF

	## Pass 1 - RigidBody3D interactables tracked via Area3D overlap.
	## NOTE: only bodies that actually implement on_interact() are considered.
	## Some items (e.g. FuelCan) sit in the "interactable" group purely so their
	## get_prompt_text()/get_use_prompt() lines show up while HELD - they have no
	## on_interact() of their own. If those were allowed to win the closest-node
	## comparison, pressing E while merely standing near one would silently no-op
	## instead of falling through to the next-closest thing that can actually
	## respond (e.g. a WaterHookup a bit further away). Filtering here keeps E
	## always resolving to the closest thing that will actually do something.
	for body in bodies:
		if body.is_in_group("interactable") and body.has_method("on_interact"):
			## Shelved items — block direct interaction; use shelf menu (E) to retrieve
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	## Pass 2 — StaticBody3D interactables (e.g. PowerTerminal, BreakerBox).
	## Jolt's Area3D.get_overlapping_bodies() is unreliable for StaticBody3D nodes,
	## so we do a proximity group scan — same pattern as _nearest_shelf().
	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
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
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	if closest != null:
		closest.on_interact()

new_str:
func _try_interact() -> void:
	## Seated players always stand, regardless of what else is nearby —
	## checked first, before any proximity scan, so a chair can never lose
	## a closest-distance comparison to some other interactable.
	if player.seated_chair != null and is_instance_valid(player.seated_chair):
		player.seated_chair.on_interact()
		return

	## Aug 2026 — scan itself moved into _nearest_generic_interactable()
	## (shared with _nearest_interact_distance(), the shelf E-priority
	## fairness check, and Focus Mode's _resolve_current_e_target()) so
	## "what would fire" and "what actually fires" can never disagree.
	var best: Dictionary = _nearest_generic_interactable()
	var closest: Node3D = best["node"]
	if closest != null:
		closest.on_interact()
```

---

## Part 3 — New helper: `_nearest_shelf_distance()`

Distance-only twin of `_nearest_shelf()`, same flat-XZ metric — needed
by the fairness check in Part 4 and Focus Mode's resolver in Part 5.

**Anchor:** verified current lines 791–806 (immediately after
`_nearest_shelf()`).

```gdscript
old_str:
func _nearest_shelf() -> Node3D:
	var shelves: Array      = get_tree().get_nodes_in_group("shelving")
	var closest: Node3D     = null
	var closest_dist: float = 2.5   ## Max reach (flat XZ distance, metres)
	var player_xz: Vector2  = Vector2(player.global_position.x, player.global_position.z)
	for shelf: Node in shelves:
		if not is_instance_valid(shelf):
			continue
		if shelf is Node3D:
			var s3: Node3D    = shelf as Node3D
			var shelf_xz: Vector2 = Vector2(s3.global_position.x, s3.global_position.z)
			var d: float = shelf_xz.distance_to(player_xz)
			if d < closest_dist:
				closest_dist = d
				closest = s3
	return closest

new_str:
func _nearest_shelf() -> Node3D:
	var shelves: Array      = get_tree().get_nodes_in_group("shelving")
	var closest: Node3D     = null
	var closest_dist: float = 2.5   ## Max reach (flat XZ distance, metres)
	var player_xz: Vector2  = Vector2(player.global_position.x, player.global_position.z)
	for shelf: Node in shelves:
		if not is_instance_valid(shelf):
			continue
		if shelf is Node3D:
			var s3: Node3D    = shelf as Node3D
			var shelf_xz: Vector2 = Vector2(s3.global_position.x, s3.global_position.z)
			var d: float = shelf_xz.distance_to(player_xz)
			if d < closest_dist:
				closest_dist = d
				closest = s3
	return closest

## Distance-only twin of _nearest_shelf() — same flat-XZ metric (reach
## along the shelf's whole vertical face, not full 3D distance to its
## origin — see the header comment above). Used by the E-handler's
## shelf-fairness check and Focus Mode's _resolve_current_e_target().
## Returns INF if no shelf is in range.
func _nearest_shelf_distance() -> float:
	var shelf: Node3D = _nearest_shelf()
	if shelf == null:
		return INF
	var player_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var shelf_xz: Vector2  = Vector2(shelf.global_position.x, shelf.global_position.z)
	return shelf_xz.distance_to(player_xz)
```

---

## Part 4 — Bugfix: shelf's unconditional E-priority win

**Anchor:** verified current lines 230–239.

```gdscript
old_str:
		## Shelf nearby — reached only if empty-handed, or holding
		## something with no E action of its own (Crate, etc. — see
		## header comment). No distance comparison needed any more: if
		## execution reaches here, nothing in the player's hand claimed E,
		## so the shelf is free to.
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			shelf.on_e_interact()
			get_viewport().set_input_as_handled()
			return

new_str:
		## Shelf nearby — reached only if empty-handed, or holding
		## something with no E action of its own (Crate, etc. — see
		## header comment).
		##
		## Aug 2026 fix — previously won unconditionally here regardless
		## of true distance to any other nearby interactable (reported
		## bug: shelving stealing E from things genuinely closer to the
		## player). Now fairly compared against the same candidate
		## _try_interact() would otherwise pick, mirroring the existing
		## ready-dish/stove-pot fairness pattern already used in this
		## handler. Metrics aren't identical — shelf distance is
		## intentionally flat-XZ (reach along its whole vertical face,
		## see _nearest_shelf()'s header) vs. the generic candidate's
		## full 3D distance — but this is the same head-to-head "peek
		## both, smaller wins" pattern already used for stove_dist vs.
		## _nearest_pickup_distance() a few lines up; if this metric
		## mismatch ever causes a new edge case, switching
		## _nearest_shelf()/_nearest_shelf_distance() to full 3D is a
		## small, isolated follow-up.
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			var shelf_dist: float = _nearest_shelf_distance()
			var other: Dictionary = _nearest_generic_interactable()
			if shelf_dist <= float(other["dist"]):
				shelf.on_e_interact()
				get_viewport().set_input_as_handled()
				return
			## else: something else is genuinely closer — fall through,
			## the logic below (or _try_interact() at the bottom) picks
			## the real winner instead.
```

---

## Part 5 — New: `_resolve_current_e_target()` for Focus Mode

Read-only peek, empty-handed case only. Mirrors the live dispatch's
shelf-fairness → ready-dish-fairness → generic-fallback order exactly
(verified against current lines 230–258).

**Anchor:** insert directly before `_try_add_nearest_to_basket()`.

```gdscript
old_str:
## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:

new_str:
## Resolves exactly which object E would trigger right now, empty-handed
## — the single source of truth for the UI thread's Focus Mode prompt
## tagging. Pure read-only peek, mirrors the empty-handed branch of
## _unhandled_input()'s "interact" handler exactly (shelf fairness check,
## then ready-dish fairness check, then the generic candidate). MUST be
## kept in sync with that branch if its priority order ever changes —
## kept as a light, clearly-cross-referenced duplication rather than a
## restructure of the input-handling hot path itself, same philosophy
## InteractionProximityScan.gd's header already uses for _nearest_shelf().
## Not valid while holding an item — CASE 1 in InteractPrompt.gd doesn't
## call this and isn't filtered by Focus Mode this pass. Returns null if
## nothing qualifies.
func _resolve_current_e_target() -> Node3D:
	var shelf: Node3D = _nearest_shelf()
	if shelf != null and shelf.has_method("on_e_interact"):
		var shelf_dist: float = _nearest_shelf_distance()
		var other: Dictionary = _nearest_generic_interactable()
		if shelf_dist <= float(other["dist"]):
			return shelf

	var ready_pot: Node = _find_nearest_ready_pot()
	if ready_pot != null:
		var pot_dist: float = (ready_pot as Node3D).global_position.distance_to(player.global_position)
		if pot_dist <= _nearest_interact_distance():
			return ready_pot as Node3D

	var other2: Dictionary = _nearest_generic_interactable()
	return other2["node"] as Node3D

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:
```

---

## Part 6 — Tag the E-target in CASE 2's prompt entries

**Anchor A:** verified current lines 713–718.

```gdscript
old_str:
	# Cap to the N closest so the screen never gets crowded with prompts.
	if candidates.size() > MAX_VISIBLE_PROMPTS:
		candidates = candidates.slice(0, MAX_VISIBLE_PROMPTS)

	var entries: Array = []
	for cand: Dictionary in candidates:

new_str:
	# Cap to the N closest so the screen never gets crowded with prompts.
	if candidates.size() > MAX_VISIBLE_PROMPTS:
		candidates = candidates.slice(0, MAX_VISIBLE_PROMPTS)

	## Aug 2026 — Focus Mode support. Resolved once per frame, tagged onto
	## whichever entry below actually matches — see
	## _resolve_current_e_target()'s header for why this can never drift
	## from what E actually does.
	var e_target: Node3D = _resolve_current_e_target()

	var entries: Array = []
	for cand: Dictionary in candidates:
```

**Anchor B:** verified current lines 767–772.

```gdscript
old_str:
		entries.append({
			"text":      "\n".join(lines),
			"world_pos": prompt_pos,
			"dist":      cand["dist"],
			"icons":     icons,
		})

new_str:
		entries.append({
			"text":         "\n".join(lines),
			"world_pos":    prompt_pos,
			"dist":         cand["dist"],
			"icons":        icons,
			"is_e_target":  body == e_target,
		})
```

`body` is already in scope at this point (`var body: Node3D = cand["node"]
as Node3D`, set at the top of this same loop) — confirmed directly, no
new variable needed.

---

## Why this is safe

- **Held-item E priority (earlier this session) is untouched.** Part 4
  only changes the shelf-vs-other-world-interactable case reached when
  nothing in the player's hand claimed E — the basket/cookpot/give/
  generic-on_use branches above it in the dispatch chain are unmodified.
- **The grow-light override is narrow by construction** — it only
  triggers when a `FarmingTray` specifically would otherwise win AND a
  grow light is separately in reach; every other interactable pair
  (shelves, generators, anything else) resolves by genuine distance,
  confirmed by reading the override's exact condition
  (`closest.is_in_group("farming_tray")`).
- **`_nearest_interact_distance()`'s one caller (the ready-dish fairness
  check) gets the identical computed value as before** — the new thin
  wrapper delegates to the exact same underlying scan logic, just
  centralized.
- **`entries.append()` only gains a new key** (`is_e_target`) — nothing
  reads or removes existing keys, so anything not yet aware of this key
  (i.e., everything before the UI thread's Focus Mode plan lands) is
  unaffected.

---

## Verification checklist

1. Stand equidistant-ish between a shelf and some other interactable
   (e.g. a generator) such that the other one is genuinely closer in
   true 3D distance — confirm `E` now interacts with the closer one,
   not the shelf.
2. Stand directly at a shelf with nothing else nearby — confirm `E`
   still opens it exactly as before (no regression on the common case).
3. Stand under a grow light with its tray directly beneath it — confirm
   `E` now toggles/adjusts the grow light, not the tray.
4. Stand near a grow light AND some unrelated third interactable (not a
   tray) where the third one is genuinely closer — confirm the grow
   light does NOT override that one (narrow-override scope check).
5. Once the UI-thread Focus Mode plan is also applied: hold Ctrl in each
   of the above scenarios and confirm the single highlighted prompt
   always matches whichever object steps 1–4 confirmed E actually
   triggers.
6. Held-item cases (Crate, Flashlight, Basket, Cooking Pot, giveable
   items) near a shelf — re-verify no regression, since Part 4 only
   touches the fallback path reached after CASE 1's own held-item checks.

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry:

```markdown
- **Shelf E-priority fairness + grow-light-over-tray + Focus Mode
  plumbing (Aug 2026).** Fixed a second shelf E-priority bug distinct
  from the held-item fix earlier this session: a nearby shelf was
  winning E unconditionally over OTHER world interactables too (e.g. a
  closer generator) whenever empty-handed. Now fairly compared via the
  same "peek both, smaller wins" pattern already used for stove-pot/
  ready-dish, through a new shared `_nearest_generic_interactable()`
  (also absorbs `_try_interact()`'s own scan and
  `_nearest_interact_distance()`, previously two near-duplicate copies
  of the same two-pass RigidBody3D/StaticBody3D scan). Added a narrow
  grow-light-over-tray override inside that same shared scan — a
  `GrowLight` sitting directly above its `FarmingTray` was otherwise
  functionally unreachable since the tray is almost always physically
  closer; only overrides when a `FarmingTray` specifically would
  otherwise win, every other interactable pair still resolves by fair
  distance. New `_resolve_current_e_target()` (empty-handed only) gives
  a UI-thread Focus Mode feature a read-only peek at exactly what E
  would fire, sharing the same underlying scan so the two can never
  drift apart — tagged onto CASE 2 prompt entries via a new
  `"is_e_target"` key.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Shelf E-Priority Fairness + Grow Light Priority + Focus Mode Plumbing (Aug 2026)

## What changed this session
Fixed a shelf E-priority bug distinct from the held-item-priority fix
earlier this session: while empty-handed, a nearby shelf was winning E
unconditionally over any OTHER world interactable too (e.g. a generator
genuinely closer to the player), not just over held items. Fixed with
the same distance-fairness pattern already established in this handler
for stove-pot/ready-dish — "peek both, smaller wins." Centralized the
scan itself: `_try_interact()` and `_nearest_interact_distance()` were
two near-identical copies of the same RigidBody3D/StaticBody3D two-pass
scan; both now go through one shared `_nearest_generic_interactable()`.

Added a grow-light-over-tray override inside that same shared scan — a
`GrowLight` mounted directly above its `FarmingTray` was functionally
unreachable via E, since the tray sits almost exactly at the same
horizontal position and is essentially always the physically closer
candidate. Deliberately narrow: only overrides when a `FarmingTray`
specifically would otherwise win and a grow light is also in reach —
every other pairing resolves by genuine fair distance, unaffected.

Added `_resolve_current_e_target()`, a read-only empty-handed-only peek
mirroring the live dispatch's priority order exactly (shelf fairness →
ready-dish fairness → generic fallback), for a separate UI-thread Focus
Mode feature to tag which prompt E would actually fire — shares the
same underlying scan as the real dispatch, so the two can't drift apart.
Tagged onto CASE 2's prompt entries via a new `"is_e_target"` boolean key
(additive only, no existing entry keys touched).

### Files modified
- `scripts/player/InteractionSystem.gd` — new
  `_nearest_generic_interactable()` (absorbs `_try_interact()`'s and
  `_nearest_interact_distance()`'s scans, adds the grow-light override);
  `_try_interact()` simplified to use it; new `_nearest_shelf_distance()`;
  shelf E-dispatch now distance-fair against other interactables; new
  `_resolve_current_e_target()`; CASE 2 prompt entries gain
  `"is_e_target"`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Cross-thread note
A separate UI-thread plan ("Focus Mode Prompt Filter") depends on this
one — order of application doesn't matter for crash-safety, but Focus
Mode only correctly highlights anything once this lands.

### Verification checklist
(see Player subsystem plan
`PLAYER_SHELF_FAIRNESS_GROWLIGHT_FOCUS_PLAN.md` for the full 6-item
checklist)
```
