# Plan: Can Case / Water Case — Keep the Larger Scale Permanently (Aug 2026)

**Owner:** Player subsystem (this plan) — two flagged files outside the
usual three (same `scripts/world/items/` scope as the upright-slerp work
this session).
**Files touched:** `scripts/world/items/CanCase.gd`,
`scripts/world/items/WaterCase.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

---

## Confirms your understanding exactly

You're right — `1.0` is exactly the value `slerp_to_upright()` was
drifting these two toward, per my earlier investigation.
`Basis.IDENTITY`'s implicit scale is `(1.0, 1.0, 1.0)`; both items were
authored with a deliberate downscale:

```gdscript
## Scale down by 1/4
scale = Vector3(0.75, 0.75, 0.75)
```

(`CanCase.gd` line 34, `WaterCase.gd` line 37 — identical in both).
Since you like the fully-scaled-up look, the fix is simply to drop the
downscale and let them sit at their natural authored mesh size (`1.0`)
permanently, rather than only reaching it as a side effect of holding
CTRL.

---

## The change

**`CanCase.gd`** — verified current lines 30–34.

```gdscript
old_str:
func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Scale down by 1/4
	scale = Vector3(0.75, 0.75, 0.75)
	_collect_can_visuals()

new_str:
func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Aug 2026 — was scaled down by 1/4 (0.75); kept at full authored mesh
	## size (1.0) instead, per Brannon's preference for how it looked
	## after the CTRL manual-upright slerp (which targets Basis.IDENTITY,
	## scale 1.0) briefly grew it toward this size as a side effect.
	_collect_can_visuals()
```

**`WaterCase.gd`** — verified current lines 32–36.

```gdscript
old_str:
func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Scale down by 1/4
	scale = Vector3(0.75, 0.75, 0.75)
	_collect_bottle_visuals()

new_str:
func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Aug 2026 — was scaled down by 1/4 (0.75); kept at full authored mesh
	## size (1.0) instead, per Brannon's preference for how it looked
	## after the CTRL manual-upright slerp (which targets Basis.IDENTITY,
	## scale 1.0) briefly grew it toward this size as a side effect.
	_collect_bottle_visuals()
```

Simplest correct fix is removing the `scale =` line entirely rather than
setting it to `Vector3(1.0, 1.0, 1.0)` explicitly — `Node3D.scale`
already defaults to `Vector3.ONE`, so not setting it at all achieves
exactly the same result with one less line.

---

## One real side effect worth flagging, not fixing here

`Node3D.scale` isn't purely cosmetic — Godot's physics engine applies a
`RigidBody3D`'s own scale when placing its collision shape in world
space, so this is a genuine ~1.33× **physical** collision-footprint
increase (1 ÷ 0.75), not just a visual one. Two things I checked so this
isn't a guess:

- **The bulky-carry head-clearance arc from earlier this session is
  unaffected.** `_carry_bulk_radius` is computed via
  `_compute_obstacle_radius()`, which measures each `CollisionShape3D`
  child's own *local* transform relative to the `RigidBody3D` — it never
  reads the `RigidBody3D`'s own `scale` property at all. So that
  computed value was already independent of the 0.75 downscale, and
  stays exactly the same after this change. No behavior change to the
  arc feature's gating.
- **The `NavigationObstacle3D` radius (heavy-item NPC avoidance,
  `_maybe_create_nav_obstacle()`) has the same property** — also driven
  by `_compute_obstacle_radius()`, also unaffected numerically by this
  change. Which means there's a real, pre-existing (not introduced by
  this change) mismatch worth knowing about: the NPC-avoidance radius
  for both items was already computed independent of their `scale`, so
  it was already sized for something closer to the *larger* footprint,
  not the 0.75-scaled one — after this change, that radius now actually
  matches the item's true (now un-shrunk) physical size better than it
  did before, if anything. Not something I'm fixing here since it's a
  side observation, not a new problem this change introduces — flagging
  for completeness, not as an action item.

Worth a quick in-editor eyeball once applied: whether the now-larger
Can Case/Water Case still look right sitting in a Dresser/End Table/
Shelf slot next to other items, and fit through doorways/tight bunker
gaps the way you want — purely a visual judgment call, not something I
can assess from code.

---

## Verification checklist

1. Spawn a Can Case and a Water Case — confirm both now render at full
   (previously CTRL-grown) size immediately, no scale-up needed.
2. Hold CTRL while carrying either — confirm no visible scale change at
   all now (nothing left to interpolate toward; `global_transform.basis`
   is already effectively `Basis.IDENTITY`-scaled once upright).
3. Store a Can Case/Water Case in a Dresser, End Table, and Shelf —
   confirm the now-larger size still looks acceptable in each storage
   UI/slot (visual check, not a functional one — nothing about storage
   eligibility is scale-based).
4. Confirm the bulky-carry head-clearance arc (180° turn while holding
   either) still works exactly as before — should be unaffected per the
   "why this is safe" note above, but worth a quick re-check.

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry:

```markdown
- **Can Case / Water Case: removed the 0.75 downscale (Aug 2026,
  `CanCase.gd`/`WaterCase.gd` — flagged: `scripts/world/items/`, not
  one of the three core files).** Both previously scaled themselves
  down to 0.75 on `_ready()`; removed after the CTRL manual-upright
  slerp (which targets `Basis.IDENTITY`, scale `1.0`) was found to drag
  their scale up toward `1.0` as an unintended side effect while CTRL
  was held (`Basis.slerp()` interpolates a decomposed scale component
  alongside rotation — not something `slerp_to_upright()`'s rotation-only
  intent accounted for). Brannon preferred the resulting larger look, so
  made it permanent instead of drifting there conditionally. Confirmed
  no effect on the bulky-carry-arc gating or the `NavigationObstacle3D`
  avoidance radius for either item — both are computed from each
  collision shape's own local transform, never from the `RigidBody3D`'s
  own `scale` property, so this change doesn't alter either.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Can Case / Water Case Scale Change (Aug 2026)

## What changed this session
Removed `CanCase.gd`/`WaterCase.gd`'s `scale = Vector3(0.75, 0.75, 0.75)`
downscale (both now sit at their full authored mesh size, `1.0`).
Follow-up to a bug found in the CTRL manual-upright feature: `Basis.
slerp()` (used by `PickupableItem.slerp_to_upright()`) decomposes and
interpolates BOTH rotation and scale toward its target — since the
target is always `Basis.IDENTITY` (scale `1.0`), holding CTRL on either
item was gradually growing them from their authored 0.75 scale toward
1.0 as an unintended side effect of what was meant to be a rotation-only
correction. Brannon preferred the resulting larger look over the
original 0.75 scale, so rather than fixing the slerp to leave scale
alone, made 1.0 the permanent authored scale instead. Confirmed via
direct read of `_compute_obstacle_radius()` that neither the bulky-
carry-arc gating nor the `NavigationObstacle3D` avoidance radius for
either item are affected — both are computed from each `CollisionShape3D`
child's own local transform, never from the parent `RigidBody3D`'s own
`scale`, so this was already independent of the 0.75 value one way or
the other.

### Files modified
- `scripts/world/items/CanCase.gd` — `scale` override removed.
- `scripts/world/items/WaterCase.gd` — same.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_CANCASE_WATERCASE_SCALE_PLAN.md` for the full 4-item checklist)
```
