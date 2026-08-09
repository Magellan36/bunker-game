# Plan: Soften Upright Snap + CTRL Manual-Upright Hold (Aug 2026)

**Owner:** Player subsystem (this plan) — one flagged file family outside
the usual three (see note below).
**Files touched:** `scripts/world/items/PickupableItem.gd`,
`scripts/world/items/Basket.gd`, `scripts/world/items/CookingPot.gd`,
`scripts/world/items/Flashlight.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

**Scope note:** all four files live under `scripts/world/items/`,
Furniture/Objects-thread territory, not my three core files. Same
approach as `PickupableItem.gd`'s earlier bulky-carry-arc fix this
session — the behavior is fundamentally about the hold mechanic itself,
so handling it directly and flagging clearly rather than routing it
through another thread.

---

## Part 1 — Found it, confirmed exactly as you described

`Basket.gd` and `CookingPot.gd` both override `_physics_process()`, call
`super._physics_process(delta)` first (the position-follow logic lives
entirely in the base class, untouched), then do this every physics tick
while held:

```gdscript
if is_held and _hold_point != null:
	global_transform.basis = Basis.IDENTITY
	angular_velocity       = Vector3.ZERO
```

Confirmed both are byte-identical in structure (`CookingPot.gd`'s own
comment even says "Same upright lock as Basket.gd"). This is an instant,
hard snap — `Basis.IDENTITY` is assigned outright every frame, no
interpolation. That's the exact thing you want softened.

### The fix — spherical interpolation, frame-rate independent

Added as a new public method on the shared base class (`PickupableItem.
gd`), not duplicated in each subclass, since both `Basket.gd` and
`CookingPot.gd` already do the literal same thing and — per Part 2 below
— a third caller needs the identical behavior too.

**Anchor:** verified current lines 292–298 (end of file).

```gdscript
old_str:
## Shared spawn helper — see FarmingShopHelper.spawn_scene_settled()
## for the convention: freeze this body for exactly one physics frame right
## after spawning (so it doesn't fall through a floor that physics hasn't
## "seen" yet), then call this deferred to unfreeze it.
func _unfreeze_after_spawn() -> void:
	freeze = false

new_str:
## Shared spawn helper — see FarmingShopHelper.spawn_scene_settled()
## for the convention: freeze this body for exactly one physics frame right
## after spawning (so it doesn't fall through a floor that physics hasn't
## "seen" yet), then call this deferred to unfreeze it.
func _unfreeze_after_spawn() -> void:
	freeze = false

# ─── Upright interpolation (Aug 2026) ─────────────────────────────────────────
## How quickly slerp_to_upright() converges — same role follow_speed plays
## for position-chase. Higher = snappier. 10.0 reaches ~99% converged in
## roughly a third of a second regardless of framerate (exponential decay,
## see slerp_to_upright()'s own comment) — visibly smooth but not sluggish.
## Shared by Basket/CookingPot's own always-on upright lock AND the CTRL
## manual-upright hold below; split into two separate consts if you want
## a different feel for the two cases after trying this in-editor.
const UPRIGHT_SLERP_SPEED: float = 10.0

## Smoothly rotates this item's CURRENT orientation toward perfectly
## upright (Basis.IDENTITY) using spherical interpolation, so the shortest
## rotational path is taken regardless of current tilt. `speed` controls
## convergence rate the same way follow_speed does for position (t =
## speed * delta each call — exponential decay, so it naturally slows down
## as it approaches upright rather than snapping then stopping). Call this
## every physics tick you want the behavior active; simply stop calling it
## to leave the item's rotation exactly wherever it currently is — this
## function holds no state of its own between calls, it only ever takes
## one step per call.
func slerp_to_upright(delta: float, speed: float) -> void:
	var t: float = clampf(speed * delta, 0.0, 1.0)
	global_transform.basis = global_transform.basis.slerp(Basis.IDENTITY, t).orthonormalized()
	angular_velocity = Vector3.ZERO
```

`orthonormalized()` guards against tiny numerical drift accumulating
across many repeated `slerp()` calls on a live-updating basis — cheap,
standard practice, not required for correctness on any single call but
worth having given this runs every physics tick for as long as the item
is held.

### Update `Basket.gd` to use it

**Anchor:** verified current lines 62–76.

```gdscript
old_str:
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Unlike every other held item — which keeps whatever tilt it happened to
	## have at pickup, by design — the basket must never lean or tip while
	## carried. Snap it back to its authored upright orientation (Basis
	## IDENTITY — Basket.tscn has no rotation set, and the cylinder mesh is
	## built along local Y in _build_placeholder_mesh(), so identity IS
	## upright) every physics tick, immediately after the parent class's
	## position-follow logic runs. This only touches rotation — linear_velocity
	## / follow_speed / knockout distance / grace timer are all untouched,
	## still handled entirely by PickupableItem._physics_process() above.
	if is_held and _hold_point != null:
		global_transform.basis = Basis.IDENTITY
		angular_velocity       = Vector3.ZERO

new_str:
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Unlike every other held item — which keeps whatever tilt it happened to
	## have at pickup, by design — the basket must never lean or tip while
	## carried. Smoothly returns to its authored upright orientation (Basis
	## IDENTITY — Basket.tscn has no rotation set, and the cylinder mesh is
	## built along local Y in _build_placeholder_mesh(), so identity IS
	## upright) every physics tick, immediately after the parent class's
	## position-follow logic runs. Aug 2026 — was an instant hard snap
	## (global_transform.basis = Basis.IDENTITY outright); now eases toward
	## it via PickupableItem.slerp_to_upright(), softer but still quick. This
	## only touches rotation — linear_velocity / follow_speed / knockout
	## distance / grace timer are all untouched, still handled entirely by
	## PickupableItem._physics_process() above.
	if is_held and _hold_point != null:
		slerp_to_upright(delta, UPRIGHT_SLERP_SPEED)
```

### Update `CookingPot.gd` to use it

**Anchor:** verified current lines 211–216.

```gdscript
old_str:
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Same upright lock as Basket.gd — never lean/tip while carried.
	if is_held and _hold_point != null:
		global_transform.basis = Basis.IDENTITY
		angular_velocity       = Vector3.ZERO

new_str:
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Same upright lock as Basket.gd — never lean/tip while carried.
	## Aug 2026 — softened from an instant snap to a quick ease via
	## PickupableItem.slerp_to_upright(); see Basket.gd's own comment for
	## the full reasoning, identical here.
	if is_held and _hold_point != null:
		slerp_to_upright(delta, UPRIGHT_SLERP_SPEED)
```

---

## Part 2 — CTRL manual-upright hold, any held item except the Flashlight

### Design questions I resolved myself rather than asking, plus one I
   didn't — flagging both

You said to ask if anything was ambiguous. Most of it wasn't once I
looked at the code — here's what I decided and why, plus the one open
question:

1. **Does this need a new Input Map action in `project.godot`?** No —
   and deliberately avoided one. Hand-editing `project.godot`'s raw
   `InputEventKey` resource requires a correct numeric `physical_keycode`
   for Ctrl, and I'm not willing to transcribe that from memory into a
   binary-ish config format I can't verify by running the engine — a
   wrong value would silently fail to bind. Instead this uses
   `Input.is_key_pressed(KEY_CTRL)`, a direct GDScript global-scope
   enum constant the engine guarantees is correct, checked every physics
   tick — no InputMap entry needed at all, and it matches either the
   left or right Ctrl key automatically (that's how Godot's generic
   `KEY_CTRL` constant works). Lower-risk and no new project setting to
   keep in sync.
2. **Where does the per-item exclusion (Flashlight) live?** Added a new
   overridable property, `allow_manual_upright: bool = true`, defaulting
   true on the base class and overridden to `false` on `Flashlight.gd`
   only. Keeps the base class from needing to know about a specific
   subclass by name (no `self is Flashlight` type-check reaching down
   into a subclass from the shared base — same duck-typed-override
   pattern this codebase already uses for `_on_pickup_extra()` etc.).
3. **Does this double-apply to Basket/Cooking Pot, which already
   always self-uprights?** Would have, harmlessly (calling
   `slerp_to_upright()` twice in one frame when already ~upright has no
   visible effect), but excluded them explicitly anyway for
   cleanliness — no reason to call it twice when their own override
   already guarantees upright every frame regardless of CTRL.
4. **Open question, not resolved on my own — flagging for you:** should
   holding CTRL near a Shelf/Dresser/End Table also suppress/interact
   with the "held-item E priority" system from earlier this session? I
   don't think so (CTRL isn't bound to any existing action, so there's
   no conflict), but wanted to name it explicitly in case you had
   something in mind there that I'm not aware of.

### The fix

**Anchor A — new state var, verified current lines 63–73 (right after
`_carry_bulk_radius`).**

```gdscript
old_str:
var _carry_bulk_radius: float = -1.0

func _ready() -> void:

new_str:
var _carry_bulk_radius: float = -1.0

## Whether CTRL-hold manual-upright (see _physics_process()'s CTRL branch
## below) applies to this item. True by default for every item;
## Flashlight.gd overrides this to false — a flashlight's own rotation IS
## its aim direction (it auto-aims along the player's facing), so forcing
## it upright while held would fight the entire point of holding one.
var allow_manual_upright: bool = true

func _ready() -> void:
```

**Anchor B — CTRL branch in `_physics_process()`, verified current lines
170–172 (end of the function).**

```gdscript
old_str:
	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (chase_target - global_position) * speed
	angular_velocity = Vector3.ZERO

new_str:
	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (chase_target - global_position) * speed
	angular_velocity = Vector3.ZERO

	## CTRL manual-upright hold (Aug 2026) — while CTRL is held, ease
	## ANY held item toward upright, same slerp_to_upright() the Basket/
	## Cooking Pot always-on lock uses. Excludes Flashlight.gd
	## (allow_manual_upright = false there) and Basket/Cooking Pot
	## specifically (they already do this unconditionally via their own
	## _physics_process() override, immediately after this base call
	## returns — calling it twice in the same frame would be harmless but
	## pointless). Stops the instant CTRL is released: this only ever
	## takes one interpolation step per call, so the item simply keeps
	## whatever orientation it had on the last frame CTRL was held.
	if allow_manual_upright and not ("is_basket_container" in self) and not ("is_cookpot_container" in self) \
			and Input.is_key_pressed(KEY_CTRL):
		slerp_to_upright(delta, UPRIGHT_SLERP_SPEED)
```

**Anchor C — `Flashlight.gd`'s exclusion, verified current lines 19–20.**

```gdscript
old_str:
# ─── State ────────────────────────────────────────────────────────────────────
var _player:           Node3D = null   ## CharacterBody3D — set on pickup

new_str:
# ─── State ────────────────────────────────────────────────────────────────────
var _player:           Node3D = null   ## CharacterBody3D — set on pickup

## Excluded from CTRL manual-upright (see PickupableItem._physics_process()'s
## CTRL branch) — this item's rotation IS its aim direction (auto-aimed
## along the player's facing, per the header comment above), so forcing it
## upright while held would fight the entire point of holding one.
var allow_manual_upright: bool = false
```

---

## Why this is safe

- **Basket/Cooking Pot's success-path behavior is functionally
  unchanged** — still upright within a fraction of a second of pickup,
  still never leans while carried. Only the instant-vs-eased character of
  the transition changed, per your request.
- **Every other held item is unaffected until CTRL is pressed** — the
  new branch is fully gated behind `Input.is_key_pressed(KEY_CTRL)`; with
  CTRL up, `_physics_process()` behaves exactly as it did before this
  plan for every item except Basket/CookingPot (whose own change is
  covered above).
- **Flashlight is verified excluded, not assumed** — `allow_manual_upright
  = false` is a hard, explicit override, not a heuristic.
- **No new project settings, no InputMap entry, no risk of a
  mistranscribed keycode** — `KEY_CTRL` is a compiler-checked GDScript
  global constant.
- **Release behavior needs no extra code** — `slerp_to_upright()` has no
  persistent state; the moment CTRL is no longer held, the branch simply
  isn't entered, and the item's last-set `angular_velocity` (always
  zeroed while the branch was active) leaves it holding still exactly
  where it was.

---

## Verification checklist

1. Pick up a Basket or Cooking Pot with the mesh currently tilted (e.g.
   picked up mid-tip from a shelf spill, if reproducible, or immediately
   after a knockout) — confirm it now visibly eases upright over a
   fraction of a second instead of snapping instantly, and still ends up
   perfectly upright.
2. Hold CTRL while carrying a Water Bottle (or any non-basket/pot/
   flashlight item) tilted at an angle — confirm it smoothly rotates
   upright while CTRL is held down.
3. Release CTRL mid-rotation — confirm the item immediately stops
   rotating and holds still at whatever angle it had reached, rather than
   continuing to the end or snapping back.
4. Hold CTRL while carrying the Flashlight — confirm nothing happens;
   its rotation still tracks the player's aim exactly as before.
5. Hold CTRL while carrying a Basket or Cooking Pot — confirm no visible
   change (already upright via its own always-on lock; CTRL should be
   a no-op here, not a double-correction or a glitch).
6. Hold CTRL while empty-handed — confirm nothing happens (no item, no
   effect, no errors).
7. General regression: pickup/drop/store/scroll cycle, and the bulky-
   carry head-clearance arc from earlier this session (Crate/Can Case/
   Water Case 180° turns), both unaffected by this change.

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry:

```markdown
- **Softened upright snap + CTRL manual-upright hold (Aug 2026,
  `PickupableItem.gd`/`Basket.gd`/`CookingPot.gd`/`Flashlight.gd` —
  flagged: `scripts/world/items/`, not one of the three core files, but
  the hold-follow mechanic itself is Player-subsystem scope).** Basket/
  Cooking Pot's always-on upright lock (never lean while carried) was an
  instant hard snap (`global_transform.basis = Basis.IDENTITY` outright,
  every physics tick) — replaced with a new shared
  `PickupableItem.slerp_to_upright(delta, speed)` using spherical
  interpolation (`Basis.slerp()`, exponential-decay convergence via
  `UPRIGHT_SLERP_SPEED = 10.0`, ~99% converged in ~⅓ second), same
  visual result but eased rather than snapped. New feature layered on
  the same primitive: holding **CTRL** applies this to ANY held item
  (new `allow_manual_upright: bool` on `PickupableItem`, default true,
  overridden `false` only on `Flashlight.gd` — its rotation is its aim
  direction, forcing it upright would fight the point of holding one).
  Basket/Cooking Pot are excluded from the CTRL branch specifically
  (checked via their existing `is_basket_container`/`is_cookpot_container`
  duck-type markers) since their own override already keeps them
  upright unconditionally — redundant, not broken, to call it twice, so
  skipped for cleanliness. Deliberately uses `Input.is_key_pressed
  (KEY_CTRL)` polled directly in `_physics_process()` rather than adding
  a new Input Map action — avoids hand-transcribing a `project.godot`
  `physical_keycode` value with no way to verify it outside the editor.
  Releasing CTRL needs no cleanup code: the function holds no state
  between calls, so the item simply stops moving and holds its last
  orientation.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Softened Upright Snap + CTRL Manual-Upright Hold (Aug 2026)

## What changed this session
Softened Basket/Cooking Pot's always-on "never lean while carried"
behavior from an instant hard snap (`global_transform.basis =
Basis.IDENTITY` outright every physics tick) to a quick spherical-
interpolation ease, via a new shared `PickupableItem.slerp_to_upright
(delta, speed)` (Basis.slerp() toward identity, exponential-decay
convergence, `UPRIGHT_SLERP_SPEED = 10.0` — tunable, ~99% converged in
~⅓ second). Then layered a new feature on the same primitive: holding
CTRL now applies the same ease-to-upright to ANY held item, via a new
`allow_manual_upright: bool` on `PickupableItem` (default true,
overridden false only on `Flashlight.gd`, since its rotation is its own
aim direction). Basket/Cooking Pot are excluded from the CTRL branch
(checked via their existing container duck-type markers) since their own
override already keeps them upright regardless — avoids a harmless but
pointless double-call, not a bug fix. Used `Input.is_key_pressed
(KEY_CTRL)` polled directly rather than adding a new Input Map action —
avoided hand-transcribing a `physical_keycode` value into `project.godot`
with no way to verify it outside the Godot editor. Releasing CTRL needs
no explicit stop logic: the interpolation function holds no state
between calls, so the item simply holds still at whatever orientation it
last reached.

One open question flagged for Brannon rather than resolved
unilaterally: whether CTRL near a Shelf/Dresser/End Table should
interact with the held-item E-priority system from earlier this session
— currently doesn't, since CTRL isn't bound to any existing action, but
named explicitly in case something else was intended there.

### Files modified
- `scripts/world/items/PickupableItem.gd` — new
  `slerp_to_upright()`/`UPRIGHT_SLERP_SPEED`/`allow_manual_upright`; CTRL
  branch added to `_physics_process()`.
- `scripts/world/items/Basket.gd` — instant snap replaced with
  `slerp_to_upright()` call.
- `scripts/world/items/CookingPot.gd` — same replacement.
- `scripts/world/items/Flashlight.gd` — `allow_manual_upright = false`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_UPRIGHT_SLERP_AND_CTRL_HOLD_PLAN.md`
for the full 7-item checklist)
```
