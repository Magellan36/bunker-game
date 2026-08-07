# Player Subsystem Cleanup: Assessment + Phased Refactor Plan (Aug 2026)

**Owner:** Player subsystem (this plan)
**Scope:** `scripts/player/Player.gd`, `scripts/player/PlayerStats.gd`,
`scripts/player/InteractionSystem.gd` — everything this thread owns.
**Type:** Structural cleanup, NOT a rewrite. Every change below is
"extract-and-delegate": move code into a new file, leave a one-line
forwarding call in its place. **No method Brannon or any other
subsystem calls changes name, signature, or behavior.** This is the
same pattern already proven twice elsewhere in this exact codebase (see
"Precedent" below) — nothing here is novel or experimental.

---

## Why now, and why this shape

You're right that `InteractionSystem.gd` in particular has outgrown its
original shape. Concretely, as of this pull it's **1,222 lines** (up
from ~686 when the doc last measured it) and the file's own
`docs/systems/player/README.md` "Known tradeoffs" section already
flagged this as a "plausible future split candidate" — that note is now
almost a year and 500+ lines stale. This plan is that split, done the
way the project already does it.

**Precedent — this is not a new pattern:** the Power system
(`PowerGraph.gd`/`PowerRegistry.gd`/`PowerSolver.gd`, "Stage 10", July
2026) and Build Mode (`WallSnapHelpers.gd`, `MoveDuplicateTool.gd`,
`BuildUndoStack.gd`, etc.) both went through the exact same extraction:
a `RefCounted` file with `class_name`, holding a plain `_owner` back-
reference to the original controller, reaching into the owner's own
state rather than duplicating it. `docs/systems/build/README.md`
documents it directly:

> extend `RefCounted` with `class_name`, take a plain `_owner:
> BuildModeController` back-reference in `_init(owner)`, and reach into
> `BuildModeController`'s own state... rather than owning copies

This plan applies that identical shape to `InteractionSystem.gd`, in
the same folder convention (new files sit flat in `scripts/player/`,
same as `WallSnapHelpers.gd` sits flat in `scripts/world/build/`, not in
a subfolder).

---

## What's actually wrong (concrete findings, not vibes)

I read all three files in full. `Player.gd` (169 lines) and
`PlayerStats.gd` (199 lines) are in reasonable shape — small, sectioned,
well-commented. `InteractionSystem.gd` is where the real problem is.
Four specific, fixable issues:

### 1. The same "find nearest thing" loop is duplicated ~9 times

Two near-identical filter chains repeat throughout the file:

**Pattern A** (scan `detect_area.get_overlapping_bodies()`, skip the
held item itself, skip `"shelved"`, skip frozen `RigidBody3D`, keep
closest by `distance_to`) — duplicated in `_try_pickup()`,
`_nearest_pickup_distance()`, `_try_add_nearest_to_basket()`,
`_try_add_nearest_to_cookpot()`, and `_nearest_group_storable_distance()`
(which is already a step toward generalizing this — it just never got
applied to its four siblings).

**Pattern B** (scan a scene-tree group by name, since Jolt's
`Area3D.get_overlapping_bodies()` misses `StaticBody3D`, apply an
optional predicate, keep closest within a max range) — duplicated in
`_find_nearest_open_stove()`, `_find_nearest_stove_with_pot()`,
`_find_nearest_npc()`, and `_find_nearest_ready_pot()`.

Every one of these is 12–15 lines that differ only in the group name and
(for Pattern B) the predicate. When a bug gets found in the filter logic
itself (e.g. the `shelved`/frozen skip), it has to be fixed in up to 9
places by hand — exactly the "headache" pattern you described.

### 2. `_update_prompt()` is a single ~290-line function doing two jobs

Lines 394–681: one function builds both the held-item prompt panel
(CASE 1 — use-prompt, store hint, shelf panel, basket/cookpot/NPC-give
target lists) and the empty-handed prompt panel (CASE 2 — tracked-body
scan, static-body scan with `set_player_in_range` bookkeeping, sort,
cap, per-body text assembly). These are genuinely two different
responsibilities glued into one function because it grew incrementally
as each new held-item type (basket → cookpot → NPC-give) got bolted on.

### 3. Held-item bookkeeping has already silently diverged into two
   different implementations

This is the concrete bug-risk finding, not a style complaint. There are
two functions that both exist to do "the held item just left the
player's hand for a non-drop reason":

- **`_release_item_to_npc()`** (used by Snatch, via
  `clear_held_item_external()`): checks `is_instance_valid(held_item)`
  before touching `knocked_out`, then `inventory.clear_slot()`.
- **`release_held_item_to_npc()`** (used by Give, via
  `_try_give_to_nearest_npc()`): captures `item`/`slot` into locals
  first, unconditionally disconnects `knocked_out` (no validity guard),
  calls `item.pickup(npc.hold_point)` itself, THEN
  `inventory.clear_slot()`.

These do almost the same thing through two independently-maintained code
paths with subtly different guards. They haven't caused a visible bug
yet, but they're one future edit away from drifting further apart in a
way that only shows up for one of the two features (Give works, Snatch
breaks, or vice versa) — exactly the kind of thing that's hard to catch
in testing because each path only gets exercised by its own feature.
Consolidating these into one implementation is a correctness
improvement, not just tidiness. **Flagged in Phase 3 below.**

### 4. Magic numbers and offsets scattered inline

`MAX_PROMPT_DIST = 3.2`, shelf reach `2.5`, `MAX_VISIBLE_PROMPTS = 3`,
and several one-off `Vector3(0.0, 1.8, 0.0)` / `Vector3(0.0, 0.9, 0.0)` /
`Vector3(0.0, 2.3, 0.0)` prompt-anchor offsets are declared at their one
use site rather than gathered somewhere a future editor would look
first. Minor compared to 1–3, but cheap to fix in the same pass.

---

## What is genuinely fine and should NOT be touched

- `Player.gd` and `PlayerStats.gd` — no structural changes proposed.
  `PlayerStats.gd` has one small doc-comment misplacement (the "Restores
  elapsed time (e.g. from a save file)..." comment block currently sits
  directly above `skip_time_with_drain()` but describes `set_elapsed()`
  below it) — a one-line comment move, folded into Phase 4, not worth
  its own phase.
- The dispatch chain in `_unhandled_input()` (F/E/G routing). It's grown
  but is still readable at a glance, and the project's own stated
  philosophy (see `docs/systems/build/README.md`'s Extension points —
  "only split it if a genuinely self-contained new feature needs its own
  file... not as a dedicated refactor pass") argues for leaving it alone
  until a concrete new feature needs it. Noted as a documented future
  extension point in Phase 4, not touched now.
- `_nearest_shelf()` — uses flat-XZ distance instead of full 3D, the one
  genuine outlier among the "find nearest" functions. Deliberately
  **excluded** from the Pattern-B consolidation below rather than forced
  into it — a shelf at a different height than the player should still
  use flat-XZ reach, and folding it into the 3D-distance generic helper
  would be a silent behavior change dressed up as a refactor. Left as
  its own small function, called out explicitly so nobody "fixes" it by
  accident in a future pass.

---

## Proposed architecture

Two new files in `scripts/player/`, following the exact `_owner`
`RefCounted` pattern:

- **`InteractionProximityScan.gd`** — Pattern A and Pattern B's shared
  filter chains, generalized into two small functions. Phase 1.
- **`InteractionPromptBuilder.gd`** — the full CASE 1 / CASE 2 prompt-
  building logic, moved verbatim. Phase 2.

And one consolidation inside `InteractionSystem.gd` itself (no new
file needed — small enough to stay as private helper methods):

- Held-item bookkeeping (assign/clear variants), unifying the two
  divergent Give/Snatch cleanup paths found in issue #3. Phase 3.

`InteractionSystem.gd` keeps every existing method name and signature —
each extracted function becomes a one-line forwarding call. No other
file in the repo (not `NPC.gd`, not `NPCItemUser.gd`, not
`Shelving.gd`, not the HUD) needs to change, because nothing it calls
moves or is renamed.

---

## Phase 1 — Extract proximity scanning (ready to execute now)

Lowest risk of all four phases: pure read-only distance-finding, no
state mutation, easy to verify 1:1 against current behavior. This is
the fully-specified, ready-to-hand-to-the-coding-agent phase; Phases 2–3
are scoped below and will get their own follow-up plan docs (same
incremental "Stage" approach the Power/Build systems used) once you're
happy with how Phase 1 lands.

### New file: `scripts/player/InteractionProximityScan.gd`

```gdscript
extends RefCounted
class_name InteractionProximityScan
## InteractionProximityScan.gd  —  InteractionSystem slice, Phase 1 (Aug 2026)
## ─────────────────────────────────────────────────────────────────────────
## Two "find nearest thing" filter chains that were independently
## duplicated across up to 9 places in InteractionSystem.gd:
##
## Pattern A (nearest_body_in_group): scan detect_area.get_overlapping_bodies(),
## skip the currently-held item, skip "shelved", skip frozen RigidBody3D,
## optionally apply a predicate, keep closest by distance_to(). Was
## duplicated in _try_pickup(), _nearest_pickup_distance(),
## _try_add_nearest_to_basket(), _try_add_nearest_to_cookpot(), and
## _nearest_group_storable_distance().
##
## Pattern B (nearest_in_group): scan a scene-tree group by name (the
## standard workaround for Jolt's Area3D.get_overlapping_bodies() missing
## StaticBody3D, used throughout this file already), apply an optional
## predicate, keep closest within max_dist. Was duplicated in
## _find_nearest_open_stove(), _find_nearest_stove_with_pot(),
## _find_nearest_npc(), and _find_nearest_ready_pot().
##
## Same _owner back-reference pattern as WallSnapHelpers.gd/PowerGraph.gd —
## nothing moved off InteractionSystem, this reaches into _owner.detect_area/
## _owner.held_item/_owner.player/_owner.get_tree() rather than owning copies.
##
## Deliberately NOT generalized here: _nearest_shelf() (flat-XZ distance,
## the one outlier — see InteractionSystem.gd's own comment on it) and the
## CASE 2 prompt-loop's static scan (has set_player_in_range() side effects,
## not a pure query) — both stay where they are.

var _owner: InteractionSystem = null

func _init(owner: InteractionSystem) -> void:
	_owner = owner

## Pattern A. Nearest RigidBody3D in detect_area overlap belonging to
## group_name, skipping the held item / shelved / frozen. predicate, if
## given, is called as predicate.call(body) and must return true to keep
## the candidate. Returns null if nothing qualifies.
func nearest_body_in_group(group_name: String, predicate: Callable = Callable()) -> Node3D:
	var bodies: Array        = _owner.detect_area.get_overlapping_bodies()
	var closest: Node3D      = null
	var closest_dist: float  = INF
	for body in bodies:
		if body == _owner.held_item:
			continue
		if not body.is_in_group(group_name):
			continue
		if body.is_in_group("shelved"):
			continue
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		if predicate.is_valid() and not predicate.call(body):
			continue
		var d: float = (body as Node3D).global_position.distance_to(_owner.player.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = body
	return closest

## Distance-only twin of nearest_body_in_group(). Returns INF if nothing
## qualifies — safe to use directly in a "strictly closer than" comparison.
func nearest_distance_in_group(group_name: String, predicate: Callable = Callable()) -> float:
	var body: Node3D = nearest_body_in_group(group_name, predicate)
	if body == null:
		return INF
	return body.global_position.distance_to(_owner.player.global_position)

## Pattern B. Nearest node in scene-tree group_name (full 3D distance from
## _owner.player), no farther than max_dist, additionally passing predicate
## if given (predicate.call(node) -> bool). StaticBody3D-safe — this is the
## group-scan workaround already used throughout InteractionSystem.gd for
## nodes Area3D can't reliably see.
func nearest_in_group(group_name: String, max_dist: float, predicate: Callable = Callable()) -> Node:
	var closest: Node        = null
	var closest_dist: float  = max_dist
	var player_pos: Vector3  = _owner.player.global_position
	for node: Node in _owner.get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		if predicate.is_valid() and not predicate.call(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest
```

### Wire it into `InteractionSystem.gd`

**Anchor A — node ref, verified current lines 20–22:**

```gdscript
old_str:
@onready var hold_point: Node3D      = $HoldPoint
@onready var detect_area: Area3D     = $DetectArea
@onready var player: CharacterBody3D = get_parent()

new_str:
@onready var hold_point: Node3D      = $HoldPoint
@onready var detect_area: Area3D     = $DetectArea
@onready var player: CharacterBody3D = get_parent()

## Phase 1 (Aug 2026) extraction — see InteractionProximityScan.gd's own
## header comment for what moved and why.
var _proximity: InteractionProximityScan = null
```

**Anchor B — instantiate in `_ready()`, verified current lines 57–61:**

```gdscript
old_str:
func _ready() -> void:
	hold_point.position = Vector3(0.0, hold_height, -1.0)
	_world_root = get_tree().get_first_node_in_group("world")
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)

new_str:
func _ready() -> void:
	hold_point.position = Vector3(0.0, hold_height, -1.0)
	_world_root = get_tree().get_first_node_in_group("world")
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)
	_proximity = InteractionProximityScan.new(self)
```

### Replace each duplicated function body with a forwarding call

**`_nearest_pickup_distance()` — verified current lines 1129–1141:**

```gdscript
old_str:
func _nearest_pickup_distance() -> float:
	var bodies: Array = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF
	for body in bodies:
		if body.is_in_group("pickup"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
	return closest_dist

new_str:
func _nearest_pickup_distance() -> float:
	return _proximity.nearest_distance_in_group("pickup")
```

**`_try_pickup()` — verified current lines 1144–1159 (only the scan
block; everything from `if closest == null:` onward is unchanged):**

```gdscript
old_str:
func _try_pickup() -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("pickup"):
			## Shelved items — block direct pickup via F; use shelf menu (E) to retrieve
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	if closest == null:
		return

new_str:
func _try_pickup() -> void:
	## Shelved items — block direct pickup via F; use shelf menu (E) to retrieve.
	## Frozen-body / shelved / held-item filtering now lives in
	## InteractionProximityScan (Phase 1, Aug 2026) — see its header comment.
	var closest: RigidBody3D = _proximity.nearest_body_in_group("pickup") as RigidBody3D

	if closest == null:
		return
```

**`_nearest_group_storable_distance()` — verified current lines
738–752:**

```gdscript
old_str:
func _nearest_group_storable_distance(group_name: String) -> float:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF
	for body in bodies:
		if body == held_item:
			continue
		if body.is_in_group(group_name):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
	return closest_dist

new_str:
func _nearest_group_storable_distance(group_name: String) -> float:
	return _proximity.nearest_distance_in_group(group_name)
```

**`_try_add_nearest_to_basket()` — verified current lines 756–773 (only
the scan block; `var hud` onward unchanged):**

```gdscript
old_str:
func _try_add_nearest_to_basket(basket: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body == held_item:   ## DetectArea now also sees the player's
			continue              ## own held item (layer 2, Aug 2026 mask
			                       ## widen) — never treat it as a candidate.
		if body.is_in_group("basket_storable"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	var hud: Node = get_tree().get_first_node_in_group("hud")

new_str:
func _try_add_nearest_to_basket(basket: Node) -> void:
	## held_item / shelved / frozen filtering now lives in
	## InteractionProximityScan (Phase 1, Aug 2026) — see its header comment.
	var closest: RigidBody3D = _proximity.nearest_body_in_group("basket_storable") as RigidBody3D

	var hud: Node = get_tree().get_first_node_in_group("hud")
```

**`_try_add_nearest_to_cookpot()` — verified current lines 804–821
(same shape as basket, `"cookpot_storable"` instead):**

```gdscript
old_str:
func _try_add_nearest_to_cookpot(pot: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body == held_item:   ## DetectArea now also sees the player's
			continue              ## own held item (layer 2, Aug 2026 mask
			                       ## widen) — never treat it as a candidate.
		if body.is_in_group("cookpot_storable"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	var hud: Node = get_tree().get_first_node_in_group("hud")

new_str:
func _try_add_nearest_to_cookpot(pot: Node) -> void:
	## held_item / shelved / frozen filtering now lives in
	## InteractionProximityScan (Phase 1, Aug 2026) — see its header comment.
	var closest: RigidBody3D = _proximity.nearest_body_in_group("cookpot_storable") as RigidBody3D

	var hud: Node = get_tree().get_first_node_in_group("hud")
```

**`_find_nearest_open_stove()` — verified current lines 837–850:**

```gdscript
old_str:
func _find_nearest_open_stove() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(node):
			continue
		if not node.has_method("has_open_slot") or not node.has_open_slot():
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

new_str:
func _find_nearest_open_stove() -> Node:
	return _proximity.nearest_in_group("stove", MAX_PROMPT_DIST,
		func(n: Node) -> bool: return n.has_method("has_open_slot") and n.has_open_slot())
```

**`_find_nearest_stove_with_pot()` — verified current lines 853–866:**

```gdscript
old_str:
func _find_nearest_stove_with_pot() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(node):
			continue
		if not ("pot_ref" in node) or node.pot_ref == null:
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

new_str:
func _find_nearest_stove_with_pot() -> Node:
	return _proximity.nearest_in_group("stove", MAX_PROMPT_DIST,
		func(n: Node) -> bool: return ("pot_ref" in n) and n.pot_ref != null)
```

**`_find_nearest_npc()` — verified current lines 870–881:**

```gdscript
old_str:
func _find_nearest_npc() -> Node:
	var closest: Node       = null
	var closest_dist: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

new_str:
func _find_nearest_npc() -> Node:
	return _proximity.nearest_in_group("npc", MAX_PROMPT_DIST)
```

**`_find_nearest_ready_pot()` — verified current lines 989–1002:**

```gdscript
old_str:
func _find_nearest_ready_pot() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("cooking_pot"):
		if not is_instance_valid(node):
			continue
		if not node.has_method("is_dish_ready") or not node.is_dish_ready():
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

new_str:
func _find_nearest_ready_pot() -> Node:
	return _proximity.nearest_in_group("cooking_pot", MAX_PROMPT_DIST,
		func(n: Node) -> bool: return n.has_method("is_dish_ready") and n.is_dish_ready())
```

### Explicitly NOT touched in Phase 1

- `_nearest_shelf()` (flat-XZ outlier, see above).
- `_try_interact()` and `_nearest_interact_distance()` — these mix
  Pattern A and Pattern B across two passes sharing one running
  `closest`/`closest_dist` accumulator (Pass 2 has to beat Pass 1's
  result, not just its own max range). Riskier to mechanically convert
  safely; deferred to Phase 2 alongside the prompt builder, where the
  two-pass accumulator can be handled deliberately in context rather
  than forced through a generic single-pass helper.
- The CASE 2 prompt loop's static-body scan (lines ~583–620) — has
  `set_player_in_range()` side effects, not a pure query. Deferred to
  Phase 2 (it moves into `InteractionPromptBuilder.gd` as-is).

### Phase 1 verification checklist

1. Pick up a world item (F) at various distances/angles — identical to
   before.
2. Hold a Basket, stash a nearby can (E) — identical to before,
   including the "Nothing nearby to store" / "Basket full" warnings.
3. Same for Cooking Pot stash.
4. Stove-open lookup (place Cooking Pot on E), stove-with-pot lookup (F
   pickup-pot fairness) — both still resolve to the correct nearest
   stove.
5. NPC lookup (Give dispatch, shelf-fairness rival distance) — still
   resolves to the correct nearest NPC.
6. Ready-dish pickup (E near a finished Cooking Pot) — unchanged.
7. Empty-handed F near nothing, near a shelved item, near a frozen
   item — all still correctly find nothing (regression check on the
   filter chain now living in `InteractionProximityScan`).

---

## Phase 2 — Extract prompt building (scoped, not yet diffed)

Move `_update_prompt()` (current lines 394–681, ~290 lines) verbatim
into a new `InteractionPromptBuilder.gd`, same `_owner` pattern.
`InteractionSystem._update_prompt()` becomes a one-line forwarding call:
`_prompt_builder.build()`. Also absorbs `_try_interact()`'s two-pass
scan and `_nearest_interact_distance()` (held back from Phase 1 above)
once they're in the same file as the CASE 2 static-scan they already
mirror — that's a better place to reconcile the shared accumulator
logic than doing it twice in two different files.

**Why deferred to its own plan doc rather than diffed now:** this
function is nearly 300 lines touching `prompt`, `_tracked_bodies`,
`_static_in_range`, `detect_area`, `held_item`, and several group scans
at once — worth its own careful pass with full before/after prompt-text
verification (every existing prompt string, icon, and world-anchor
offset must render byte-identical), rather than folding into this
already-long Phase-1 document. Will follow the same
verified-against-current-code process as every prior plan from this
thread.

---

## Phase 3 — Consolidate held-item bookkeeping + fix the Give/Snatch
   divergence (scoped, not yet diffed)

Unify `_release_item_to_npc()` and `release_held_item_to_npc()`'s
inline duplicate logic (issue #3 above) into one implementation, and
audit the other ~6 "disconnect knocked_out → null held_item →
-1 slot → false is_holding_e" sequences (`_on_item_knocked_out()`,
`_quick_drop()`, `_put_item_back_to_slot()`, `_store_item_to_slot()`,
`_store_item()`, `_try_use_held_cookpot()`'s stove-placement branch,
`_try_pickup_pot_from_stove()`, `_try_take_dish()`) for the same
opportunity. This phase touches actual state-mutation logic (not pure
reads like Phase 1), so it needs a side-by-side "does the new unified
path produce exactly the same resulting state as each of the paths it's
replacing" verification pass before being handed over — will be its own
plan doc with that comparison worked out explicitly per call site.

---

## Phase 4 — Constants, doc-comment fix, and documentation pass
   (scoped, small)

- Gather `MAX_PROMPT_DIST`, `MAX_VISIBLE_PROMPTS`, the shelf 2.5 m
  reach, and the three prompt-anchor `Vector3` offsets into one clearly-
  labeled constants block near the top of `InteractionSystem.gd` (or
  keep `MAX_PROMPT_DIST`/`MAX_VISIBLE_PROMPTS` where they are if Phase
  2's extraction makes a different location more natural — decide when
  Phase 2 lands).
- `PlayerStats.gd`: move the misplaced "Restores elapsed time..." doc
  comment (currently sits above `skip_time_with_drain()`, describes
  `set_elapsed()`) to sit directly above `set_elapsed()` where it
  belongs.
- Document `_unhandled_input()`'s dispatch chain as a stated future
  extension point (per-held-item-type dispatch table) rather than
  refactoring it now, matching the project's own "don't split
  preemptively" philosophy for code that isn't causing active pain yet.
- Update `docs/systems/player/README.md`'s "Files" table (currently
  shows `InteractionSystem.gd` at "~686" lines — stale) and "Known
  tradeoffs" section to reflect the completed split and list the two
  new files.

---

## What this plan deliberately does not do

- No behavior changes. Every extraction is old-logic-moved, not
  new-logic-written, except the one explicitly-flagged bug-risk
  consolidation in Phase 3 (and even that preserves both existing
  paths' actual game-state outcomes — it just makes them share one
  implementation instead of two that happen to agree today).
- No renaming of any method another file calls
  (`release_held_item_to_npc`, `clear_held_item_external`,
  `get_held_item`, everything `NPC.gd`/`NPCItemUser.gd`/`Player.gd`
  depend on stays exactly as-is).
- No touching `_nearest_shelf()`'s flat-XZ behavior or the
  `_unhandled_input()` dispatch chain's priority order — both are
  explicitly out of scope, called out above so a future pass doesn't
  "fix" them by accident while following this plan's pattern.

## Overall regression checklist (run once, after all phases you choose
   to execute land)

1. Full pickup/drop/store/scroll cycle with a world item.
2. Full pickup/drop/store/scroll cycle with an inventory-slot item.
3. Basket stash, Cooking Pot stash + stove-placement, ready-dish pickup.
4. Give to NPC (single-serving and multi-charge), Takeaway from NPC,
   Snatch from NPC (all three Give/Takeaway/Snatch paths this thread
   built earlier this session).
5. Shelf E-fairness (basket/cookpot/NPC rival distance vs. shelf reach).
6. Knockout while holding an inventory item (confirm it stays in
   inventory, inactive) vs. knockout while holding a world item.
7. Seated-chair prompt override, static-body interactables (generators,
   terminals), empty-handed prompt capping at 3 visible entries.

## Suggested sequencing

Execute Phase 1 first (fully specified above, lowest risk, immediately
actionable). Once you've confirmed it plays correctly in-editor, say so
and I'll write Phase 2's full diff the same way — verified against
whatever the file looks like at that point, same process as every plan
this thread has delivered so far. Phase 3 after that (the one phase
worth extra scrutiny since it touches mutation logic), then Phase 4 as
a quick cleanup pass to close it out.
