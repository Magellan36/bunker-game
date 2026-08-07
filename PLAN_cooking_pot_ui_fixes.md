# Plan: Cooking Pot UI — Persistence Fix, Layout, 2x Size, Rotation, Food Can

**Owner of this plan:** UI Claude instance (HUD/menus)
**Scope:** `scripts/ui/hud/InteractPrompt.gd`, `scenes/ui/InteractPrompt.tscn`,
`scripts/world/items/CookingPot.gd` (all mine), plus a small, necessary
edit to `scripts/player/InteractionSystem.gd` — flagged clearly in §1
since that file is Player-thread-owned, not mine.

---

## 1. The two disappearing-UI bugs — root cause found for both

I traced the actual prompt-building code (`InteractionSystem._update_prompt()`)
rather than guessing. Both bugs are real, and both are simple, contained
fixes — not a redesign.

**Bug 1 — icons vanish the instant the pot is picked up.** `_update_prompt()`
has two branches: CASE 1 (something is held) and CASE 2 (empty-handed,
nearby interactables). CASE 2 already looks up
`get_slot_icon_descriptors()` and includes it as `"icons"` in its prompt
entry. **CASE 1 never does this at all** — the held item's own prompt
entry is built with only `"text"`/`"world_pos"`/`"dist"`, no `"icons"` key,
so `InteractPrompt.gd` always treats a held item as icon-less. This is why
the circles disappear the moment you pick the pot up — it's not that the
row hides, it's that the row's row of icons is never sent for CASE 1 at
all.

**Bug 2 — after picking it up (once Bug 1 is fixed) and setting it back
down, the icons/prompt vanish until you leave and re-enter range.** This
one's a physics-tracking gap, and it's not specific to cooking — it would
affect any item you pick up and quick-drop. `_tracked_bodies` (the set
CASE 2 scans) is populated by the player's `Area3D` `body_entered` signal.
At pickup, the item is explicitly removed from that set
(`_tracked_bodies.erase(held_item)` — there's a comment there already
noting Jolt may not fire `body_exited` reliably on a collision-layer
change). But **nothing re-adds it on drop.** Since a quick-dropped item
usually lands at roughly the same spot it was picked up from — well inside
the same `Area3D` trigger volume the whole time — Jolt's `body_entered`
never fires again (the body never physically left and re-entered the
volume, it was just reparented away and back). So the dropped item stays
invisible to CASE 2's scan until an actual boundary crossing happens —
exactly "walk out of range and back in."

(For completeness: placing the pot ON a stove is a *different*, already-
working path — `Stove.try_place_pot()` freezes the pot, and frozen bodies
are found through a separate per-frame group scan, not `_tracked_bodies`,
so that path was never affected. This is specifically about the pot
sitting free on the ground after a quick-drop.)

### Step 1.1 — Edit `scripts/player/InteractionSystem.gd` (flagged: Player-thread scope)

**Fix 1a — give CASE 1's held-item entry an icons row too.**

Find this exact block:

```gdscript
		# Anchor prompt to hold_point position, not physics body center.
		var item_prompt_pos: Vector3 = hold_point.global_position \
				if hold_point != null else held_item.global_position

		if not item_lines.is_empty():
			entries.append({
				"text":      "\n".join(item_lines),
				"world_pos": item_prompt_pos,
				"dist":      0.0
			})
```

Replace it with exactly this:

```gdscript
		# Anchor prompt to hold_point position, not physics body center.
		var item_prompt_pos: Vector3 = hold_point.global_position \
				if hold_point != null else held_item.global_position

		## Aug 2026 fix — CASE 2 (below) already does this lookup for nearby
		## interactables; CASE 1 never did, which is why a held item's own
		## icon row (e.g. CookingPot's 3 ingredient previews) used to vanish
		## the instant it was picked up. Generic — works for any held item
		## that implements get_slot_icon_descriptors(), not cooking-specific.
		var held_icons: Array = []
		if held_item.has_method("get_slot_icon_descriptors"):
			held_icons = held_item.get_slot_icon_descriptors()

		if not item_lines.is_empty():
			entries.append({
				"text":      "\n".join(item_lines),
				"world_pos": item_prompt_pos,
				"dist":      0.0,
				"icons":     held_icons,
			})
```

**Fix 1b — re-track a quick-dropped item so it doesn't need a range
leave/re-enter to reappear.**

Find this exact block:

```gdscript
func _quick_drop() -> void:
	if held_item == null:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var drop_pos: Vector3 = player.global_position + \
		player.global_transform.basis.z * -1.5 + Vector3(0.0, 0.2, 0.0)

	if _held_from_slot != -1 and inventory != null:
		# Item was from inventory — remove it from the slot before dropping
		inventory.remove_item(_held_from_slot, drop_pos)
		# remove_item calls item.drop() internally, so we're done
	else:
		# World item — just drop it
		held_item.drop(_world_root, drop_pos)

	held_item = null
	_held_from_slot = -1
```

Replace it with exactly this:

```gdscript
func _quick_drop() -> void:
	if held_item == null:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var drop_pos: Vector3 = player.global_position + \
		player.global_transform.basis.z * -1.5 + Vector3(0.0, 0.2, 0.0)

	var dropped_item: RigidBody3D = held_item   ## captured before nulling below

	if _held_from_slot != -1 and inventory != null:
		# Item was from inventory — remove it from the slot before dropping
		inventory.remove_item(_held_from_slot, drop_pos)
		# remove_item calls item.drop() internally, so we're done
	else:
		# World item — just drop it
		held_item.drop(_world_root, drop_pos)

	held_item = null
	_held_from_slot = -1

	## Aug 2026 fix — re-add to the tracked set immediately. Jolt's Area3D
	## body_entered only fires on a genuine boundary crossing; an item
	## dropped back roughly where it was picked up never physically leaves/
	## re-enters detect_area's collision volume (it was just reparented away
	## and back), so body_entered never refires. Without this, a dropped
	## item's prompt — and for anything with get_slot_icon_descriptors()
	## like CookingPot, its icon row — stayed invisible until the player
	## actually walked out of range and back in. Mirrors the explicit
	## _tracked_bodies.erase() already done at pickup, just in reverse.
	if is_instance_valid(dropped_item):
		_tracked_bodies[dropped_item] = true
```

---

## 2. Layout: middle circle 15% higher, more top padding, 2x size

Reworking `scenes/ui/InteractPrompt.tscn`'s `IconRow` from an
`HBoxContainer` (which auto-manages every child's position, fighting any
attempt to offset just one of them) to a plain `Control` with each slot's
`position`/`size` set explicitly and permanently in the scene — this is
the template panel every pool entry gets cloned from, so setting it once
here applies everywhere automatically, no code changes needed for the
positioning itself.

**Sizing math:** icons go from 32px to 64px (2x, per your ask). 15% of
64px ≈ 9.6px, rounded to **10px** for the middle icon's raise. Gap between
icons kept at 8px. Total row: 208px wide (`64×3 + 8×2`), 74px tall
(`64 + 10`, the extra 10 is headroom for the raised middle icon).

**Also fixing the top-padding complaint properly, not just adding a
number** — the outer floating panel currently has **zero custom styling
at all**. I checked: `BunkerTheme.tres` (the theme this panel references)
has no `PanelContainer` style defined, so this panel has been rendering
with Godot's raw default engine look this whole time — no padding
anywhere, on any side, is why the icons touch the top edge directly. Since
adding padding means giving this panel a real `StyleBoxFlat` for the first
time, I used the opportunity to bring it onto the same dark/bordered
palette every other panel in the project now shares (per "keep
consistency") — corner radius 8px (slightly rounder than the 4px modal-
panel standard, intentionally, matching the "own smaller-scale identity"
precedent already set by `StorageUI.gd`'s 14px radius), background/border
colors matching `UIKit`'s shared palette. This affects the floating prompt
for **every interactable in the game**, not just cooking — flagging that
clearly since it's a bigger blast radius than just this one request, but
it's the same panel used everywhere, so there's no way to touch it for
cooking only.

### Step 2.1 — Replace `scenes/ui/InteractPrompt.tscn` entirely

Replace the ENTIRE file contents with exactly this:

```
[gd_scene format=3 uid="uid://interact_prompt_001"]

[ext_resource type="Script" path="res://scripts/ui/hud/InteractPrompt.gd" id="1_prompt"]
[ext_resource type="Theme" path="res://assets/fonts/BunkerTheme.tres" id="2_theme"]

[sub_resource type="StyleBoxFlat" id="PromptPanelStyle"]
bg_color = Color(0.08, 0.08, 0.09, 0.88)
border_color = Color(0.55, 0.58, 0.62, 0.60)
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_right = 8
corner_radius_bottom_left = 8
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
content_margin_left = 12.0
content_margin_right = 12.0
content_margin_top = 18.0
content_margin_bottom = 10.0

[sub_resource type="StyleBoxFlat" id="CircleSlot"]
bg_color = Color(0, 0, 0, 0.35)
corner_radius_top_left = 32
corner_radius_top_right = 32
corner_radius_bottom_right = 32
corner_radius_bottom_left = 32

[node name="InteractPrompt" type="CanvasLayer"]
layer = 5
script = ExtResource("1_prompt")

[node name="Panel" type="PanelContainer" parent="."]
visible = false
theme = ExtResource("2_theme")
theme_override_styles/panel = SubResource("PromptPanelStyle")

[node name="VBox" type="VBoxContainer" parent="Panel"]

[node name="IconRow" type="Control" parent="Panel/VBox"]
custom_minimum_size = Vector2(208, 74)
visible = false

[node name="Slot0" type="PanelContainer" parent="Panel/VBox/IconRow"]
position = Vector2(0, 10)
size = Vector2(64, 64)
theme_override_styles/panel = SubResource("CircleSlot")

[node name="Slot1" type="PanelContainer" parent="Panel/VBox/IconRow"]
position = Vector2(72, 0)
size = Vector2(64, 64)
theme_override_styles/panel = SubResource("CircleSlot")

[node name="Slot2" type="PanelContainer" parent="Panel/VBox/IconRow"]
position = Vector2(144, 10)
size = Vector2(64, 64)
theme_override_styles/panel = SubResource("CircleSlot")

[node name="Label" type="RichTextLabel" parent="Panel/VBox"]
theme_override_colors/default_color = Color(0.85, 0.85, 0.85, 1)
theme_override_font_sizes/normal_font_size = 13
bbcode_enabled = true
fit_content = true
scroll_active = false
autowrap_mode = 0
text = ""
horizontal_alignment = 1
```

(`Slot1`, the middle one, sits at `y = 0` while `Slot0`/`Slot2` sit at
`y = 10` — that's the "15% higher" expressed as a fixed pixel offset
within the row's own local space. `PanelContainer` auto-fits whatever
single child it's given to its own content rect, so simply resizing these
3 slots from 32×32 to 64×64 automatically doubles the rendered icon size
too — no code changes needed for that part, see §3.)

---

## 3. Edit `scripts/ui/hud/InteractPrompt.gd`

### Step 3.1 — Match the render resolution to the new 2x display size

Find this exact block:

```gdscript
## Icon SubViewport render size (px) / orthogonal camera framing.
const ICON_VP_SIZE: int = 40
const ICON_CAM_SIZE: float = 0.6
```

Replace it with exactly this:

```gdscript
## Icon SubViewport render size (px) / orthogonal camera framing.
## Aug 2026 — VP size doubled to 80 alongside the display slots doubling
## from 32px to 64px (see InteractPrompt.tscn), keeping the same ~1.25x
## oversample ratio as before so the larger icons don't look softer than
## the old smaller ones. ICON_CAM_SIZE (the 3D framing/zoom) is unrelated
## to pixel resolution and stays unchanged.
const ICON_VP_SIZE: int = 80
const ICON_CAM_SIZE: float = 0.6
```

### Step 3.2 — Match the 45°/45° angle used everywhere else

Find this exact block:

```gdscript
		var pivot: Node3D = Node3D.new()
		vp.add_child(pivot)
		pivot.add_child(inst)
```

Replace it with exactly this:

```gdscript
		var pivot: Node3D = Node3D.new()
		vp.add_child(pivot)
		pivot.add_child(inst)
		## Aug 2026 — matches BuildModeHUD's PREVIEW_ROTATION_DEFAULT exactly
		## (45° left, 45° down), same convention already applied to
		## InventoryHUD's previews. These previews had no rotation applied
		## at all before this — always rendered at each item's raw default
		## orientation.
		pivot.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
```

---

## 4. Edit `scripts/world/items/CookingPot.gd` — Food Can preview fix

**Root cause:** the descriptor for `food_can` already existed, but was
marked `is_script: true`, which makes `InteractPrompt.gd` instantiate
`FoodCan.gd` as a bare script with `Script.new()` — no scene, no child
nodes. `FoodCan.gd`'s own `_ready()` does `_mesh =
get_node_or_null("MeshInstance3D")`, expecting that node to already exist
as an authored child (unlike `FarmProduceItem.gd`, which builds its mesh
procedurally in code — that's why produce previews already worked and
Food Can's didn't). The fix is pointing at the actual scene file instead.

Find this exact line:

```gdscript
	if key == "food_can":
		return {"is_script": true, "scene": "res://scripts/world/items/FoodCan.gd"}
```

Replace it with exactly this:

```gdscript
	if key == "food_can":
		## Aug 2026 fix — FoodCan.gd expects a pre-built MeshInstance3D CHILD
		## node (get_node_or_null("MeshInstance3D") in its own _ready()),
		## unlike FarmProduceItem which builds its mesh procedurally in code.
		## is_script mode instantiates a bare Script.new() with no children,
		## so FoodCan rendered as a fully invisible/empty preview before this
		## fix. Pointing at the actual scene (which has that mesh child
		## authored) instead of the script directly fixes it.
		return {"scene": "res://scenes/world/FoodCan.tscn"}
```

---

## 5. Verification checklist

1. Walk up to a Cooking Pot on the ground (not held) — 3 circles + text
   show, as before.
2. Pick it up (F) — confirm the 3 circles **stay visible** above the held
   pot (previously vanished immediately).
3. Add ingredients, then quick-drop the pot (not onto a stove, just drop
   it) — confirm the prompt and circles **reappear immediately**, without
   needing to walk away and back.
4. Confirm placing the pot on a Stove still works exactly as before (this
   path wasn't touched — it uses a different, already-working mechanism).
5. Add a Food Can to the pot — confirm its circle now shows an actual can
   model instead of an empty circle.
6. Confirm the middle circle sits visibly higher than the two flanking it,
   and none of the three touch the top edge of the panel anymore.
7. Confirm all 3 circles are visibly larger than before (2x).
8. Confirm every ingredient preview (produce, food can) sits at the same
   45°/45° tilted angle as Build Mode's construct/shop previews and the
   inventory bar's previews.
9. Open a non-cooking interactable (e.g. a generator) — confirm its prompt
   panel now has the same dark rounded-corner background as everything
   else, with no icon row shown (since it has no
   `get_slot_icon_descriptors()`).
10. Confirm no console errors referencing `InteractPrompt`, `CookingPot`,
    or `InteractionSystem`.
