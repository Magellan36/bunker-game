# Bugfix Plan: `allow_manual_upright` Var-Redeclaration Compile Error (Aug 2026)

**Owner:** Player subsystem (this plan) — correction to my own prior
plan (`PLAYER_UPRIGHT_SLERP_AND_CTRL_HOLD_PLAN.md`).
**File touched:** `scripts/world/items/Flashlight.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

---

## The error

```
Flashlight.gd: Error at (28, 1): The member "allow_manual_upright"
already exists in parent class PickupableItem.
```

My own mistake in the prior plan: `Flashlight.gd`'s exclusion was
written as a fresh `var` declaration —

```gdscript
var allow_manual_upright: bool = false
```

— but GDScript does not allow a subclass to redeclare a `var` with the
same name as one already declared on its parent class, even to override
just the default value. `PickupableItem.gd` already declares
`var allow_manual_upright: bool = true`, so `Flashlight.gd` declaring it
again is a hard compile error, not a warning — the whole script (and
anything depending on it) fails to load.

**Already fixed directly in this conversation** (not left as an
unapplied plan) since it was a one-line correction to code I'd just
written moments earlier — this document is the record of that fix for
`docs`/`HANDOVER` purposes, matching the standing practice of
documenting every change made this session, including small corrections.

---

## The fix

Replace the redeclaration with a plain assignment inside `_ready()` —
this is the correct way to override an inherited `var`'s default value
in GDScript (assign to it, don't redeclare it).

**Anchor 1 — remove the redeclaration:**

```gdscript
old_str:
# ─── State ────────────────────────────────────────────────────────────────────
var _player:           Node3D = null   ## CharacterBody3D — set on pickup

## Excluded from CTRL manual-upright (see PickupableItem._physics_process()'s
## CTRL branch) — this item's rotation IS its aim direction (auto-aimed
## along the player's facing, per the header comment above), so forcing it
## upright while held would fight the entire point of holding one.
var allow_manual_upright: bool = false

var _on:         bool  = false

new_str:
# ─── State ────────────────────────────────────────────────────────────────────
var _player:           Node3D = null   ## CharacterBody3D — set on pickup

var _on:         bool  = false
```

**Anchor 2 — set it in `_ready()` instead:**

```gdscript
old_str:
func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")

	_build_mesh()

new_str:
func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")

	## Excluded from CTRL manual-upright (see PickupableItem.
	## _physics_process()'s CTRL branch) — this item's rotation IS its aim
	## direction (auto-aimed along the player's facing, per the header
	## comment above), so forcing it upright while held would fight the
	## entire point of holding one. Set here rather than as a var
	## redeclaration — GDScript doesn't allow shadowing a var that already
	## exists on the parent class (PickupableItem already declares
	## allow_manual_upright), even to override its default value.
	allow_manual_upright = false

	_build_mesh()
```

**Status: both anchors already applied and verified** — confirmed via
direct grep that `allow_manual_upright` now appears exactly once in the
file, as the assignment above, not a redeclaration.

---

## Why this is correct and complete

- **Same end result as intended**: `Flashlight` instances still end up
  with `allow_manual_upright == false` by the time `_ready()` finishes —
  before `_physics_process()` ever runs, so the CTRL branch in
  `PickupableItem.gd` sees the correct value on every frame from the
  first tick onward. No behavior change from what was originally
  intended, only the mechanism for setting it.
- **Nothing else in the prior plan is affected** — `PickupableItem.gd`'s
  `slerp_to_upright()`, `UPRIGHT_SLERP_SPEED`, the CTRL branch itself,
  and `Basket.gd`/`CookingPot.gd`'s updated calls were all correct as
  written and don't touch this variable's declaration.

---

## Verification checklist

1. Confirm the project compiles/loads with no errors (the original
   blocking issue).
2. Re-run the Flashlight-specific check from the prior plan's
   checklist: hold CTRL while carrying the Flashlight — confirm nothing
   happens, its rotation still tracks the player's aim exactly as before.
3. Confirm every other item from the prior plan's checklist still
   passes (Basket/Cooking Pot softened snap, CTRL on an ordinary item,
   CTRL release stopping mid-rotation, empty-handed CTRL) — this fix
   only touches `Flashlight.gd`, nothing else should have regressed, but
   worth a full re-pass given the whole script failed to load until now.

---

## Documentation updates

### `docs/systems/player/README.md`

Amend the existing "Softened upright snap + CTRL manual-upright hold
(Aug 2026)" Common-edits entry (added by the prior plan) — append this
as a trailing note rather than a new bullet, since it's a correction to
that same entry, not a new feature:

```markdown
  (Correction, same session: `Flashlight.gd`'s exclusion was initially
  written as a fresh `var allow_manual_upright: bool = false`
  declaration, which is a GDScript compile error — subclasses can't
  redeclare a parent class's `var`, even to override its default. Fixed
  to a plain assignment inside `_ready()` instead.)
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Flashlight.gd Compile Error Fix (Aug 2026)

## What changed this session
Fixed a compile error introduced by the prior "Softened Upright Snap +
CTRL Manual-Upright Hold" plan: `Flashlight.gd`'s
`allow_manual_upright` exclusion was written as a fresh `var`
declaration, but GDScript doesn't allow a subclass to redeclare a `var`
already declared on its parent class (`PickupableItem.gd` already
declares this one) — hard compile error, script failed to load. Fixed
by removing the redeclaration and instead assigning
`allow_manual_upright = false` inside `Flashlight._ready()`, which is
the correct way to override an inherited var's default in GDScript. No
behavior change from what was originally intended — same end value,
just set the right way. Already applied and verified directly in this
session, not left as a pending plan.

### Files modified
- `scripts/world/items/Flashlight.gd` — redeclaration replaced with an
  assignment in `_ready()`.
- `docs/systems/player/README.md` — correction note appended to the
  prior entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_FLASHLIGHT_VAR_REDECLARATION_FIX_PLAN.md` for the full 3-item
checklist)
```
