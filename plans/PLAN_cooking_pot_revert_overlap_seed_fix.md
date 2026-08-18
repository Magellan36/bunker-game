# Plan: Cooking Pot Size Revert + Prompt Overlap Avoidance + Seed Preview Fix

**Owner of this plan:** UI Claude instance (HUD/menus)
**Scope:** `scenes/ui/InteractPrompt.tscn`, `scripts/ui/hud/InteractPrompt.gd`,
`scripts/ui/build/BuildModeHUD.gd`. No Player-thread files touched this
time — the overlap-avoidance logic lives entirely in my own file.

---

## 1. Confirming what you asked about

Yes — `InteractPrompt.gd`/`InteractPrompt.tscn` is the **one shared
template** every interactable in the game uses for its floating prompt,
not something cooking-specific. I flagged this explicitly in the previous
plan ("this affects the floating prompt for every interactable in the
game, not just cooking") because there's no way to touch it for cooking
only — it's a single shared panel design cloned per active prompt. The
rounded corners, dark background, and padding are now genuinely global.
Since you've said you like that part and don't want it reversed, it stays
exactly as-is — only the **size** portion (§2 below) is being walked back,
and only for the icon circles specifically.

## 2. Revert icon/circle size to original, keep the 15% raise + padding

Last pass doubled the icon slots from 32px to 64px alongside the padding
fix — that was more than you asked for. This reverts the size back to
32px while keeping the two things you did ask for and want kept: the
middle circle sitting higher, and the outer panel's padding.

- Icon size: 64px → **32px** (back to original)
- Middle circle raise: 15% of 32px ≈ 4.8px, rounded to **5px** (was 10px
  at the larger size)
- Row gap between circles: kept modest at 6px, appropriate for the
  smaller 32px scale
- Panel padding (`content_margin_top`, rounded corners, dark background):
  **unchanged** — this is the part you want kept

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
corner_radius_top_left = 16
corner_radius_top_right = 16
corner_radius_bottom_right = 16
corner_radius_bottom_left = 16

[node name="InteractPrompt" type="CanvasLayer"]
layer = 5
script = ExtResource("1_prompt")

[node name="Panel" type="PanelContainer" parent="."]
visible = false
theme = ExtResource("2_theme")
theme_override_styles/panel = SubResource("PromptPanelStyle")

[node name="VBox" type="VBoxContainer" parent="Panel"]

[node name="IconRow" type="Control" parent="Panel/VBox"]
custom_minimum_size = Vector2(108, 37)
visible = false

[node name="Slot0" type="PanelContainer" parent="Panel/VBox/IconRow"]
position = Vector2(0, 5)
size = Vector2(32, 32)
theme_override_styles/panel = SubResource("CircleSlot")

[node name="Slot1" type="PanelContainer" parent="Panel/VBox/IconRow"]
position = Vector2(38, 0)
size = Vector2(32, 32)
theme_override_styles/panel = SubResource("CircleSlot")

[node name="Slot2" type="PanelContainer" parent="Panel/VBox/IconRow"]
position = Vector2(76, 5)
size = Vector2(32, 32)
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

(Only the `PromptPanelStyle` block — padding/rounding/colors — is
identical to last pass and untouched. Everything sizing-related in
`IconRow`/`Slot0`/`Slot1`/`Slot2`/`CircleSlot` is back to the original
32px scale, with `Slot1` still offset 5px higher than `Slot0`/`Slot2`.)

### Step 2.2 — Revert the render resolution back to match

Find this exact block:

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

Replace it with exactly this:

```gdscript
## Icon SubViewport render size (px) / orthogonal camera framing.
const ICON_VP_SIZE: int = 40
const ICON_CAM_SIZE: float = 0.6
```

---

## 3. "Pick up Cooking Pot" appearing separate — traced, and it's the same issue as the overlap

I traced the actual prompt-building code end to end rather than assuming.
`CookingPot.gd`'s own prompt is already correctly unified — its
`get_prompt_text()` ("[F] Pick up X") and `get_interact_prompt()`
(filling/cooking status) both feed into the SAME single entry, alongside
its icon row, every time the pot itself is scanned as a candidate — on the
ground or frozen on a stove, doesn't matter, it's always one panel with
both lines and the icons.

What's actually happening: when the pot is sitting on a Stove, the **Stove
itself** is a second, entirely separate interactable at nearly the same
world position, with its own separate panel ("[E] Turn Stove On/Off," no
icons). Two genuinely different objects, two genuinely correct individual
panels — just close enough together that they visually overlap, which
reads as "the pickup text looks disconnected from the rest of the pot's
info." There's no separate code path to fix here beyond §4 below — once
the two panels are guaranteed to stack instead of overlap, it'll be
visually obvious the pot's panel already has everything (pickup line +
status + icons) together in one place, with the Stove's simple toggle
prompt sitting cleanly below it.

## 4. Stove/Pot prompt overlap avoidance

Added directly to `InteractPrompt.gd` — no changes needed to
`InteractionSystem.gd` (Player-thread scope) for this, since the
avoidance logic works generically off data every entry already carries.

**The rule:** any entry with a non-empty `icons` array (a "richer" prompt
— today, only `CookingPot`) outranks a plain-text entry when their panels
would overlap on screen. The higher-priority panel keeps its natural
position; the lower-priority one gets pushed directly below it with a
fixed gap. When panels DON'T overlap, nothing changes — every prompt in
the game behaves exactly as it does today. This is a general pairwise
rule, not a hardcoded "Stove vs CookingPot" special case, so it'll cover
any future pair of prompts that end up near each other too.

### Step 4.1 — Edit `scripts/ui/hud/InteractPrompt.gd`

Find this exact block (the entire `_process()` function):

```gdscript
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	# ── No camera — hide everything ──────────────────────────────────────────
	if camera == null:
		for p: PanelContainer in _pool:
			p.visible = false
		return

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < _active.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)
		_icon_viewports.append(_build_icon_slots(clone))
		_icon_loaded_sig.append(["", "", ""])

	# ── Update active panels ──────────────────────────────────────────────────
	for i: int in _active.size():
		var entry: Dictionary    = _active[i]
		var p: PanelContainer    = _pool[i] as PanelContainer
		var world_pos: Vector3   = entry["world_pos"] + WORLD_OFFSET

		# Behind camera check
		if camera.is_position_behind(world_pos):
			p.visible = false
			continue

		# Compute screen position
		p.reset_size()
		var screen_pos: Vector2 = camera.unproject_position(world_pos)

		# Distance-based alpha
		var dist: float  = entry.get("dist", 0.0)
		var alpha: float = 1.0
		if dist > FADE_START:
			alpha = clampf(1.0 - (dist - FADE_START) / (FADE_END - FADE_START), 0.0, 1.0)

		# Update text
		var lbl: RichTextLabel = p.get_node_or_null("VBox/Label") as RichTextLabel
		var txt: String = entry.get("text", "")
		if lbl != null and lbl.text != txt:
			lbl.text = txt

		# Update icon row (only visible/populated for entries that carry one)
		var icons: Array = entry.get("icons", [])
		var icon_row: Control = p.get_node_or_null("VBox/IconRow") as Control
		if icon_row != null:
			icon_row.visible = not icons.is_empty()
			if not icons.is_empty():
				_refresh_icon_slots(i, icons)

		# Apply — order matters: set text → reset_size → position → modulate → visible
		p.reset_size()
		p.position  = screen_pos - p.size / 2.0
		p.modulate  = Color(1.0, 1.0, 1.0, alpha)
		p.visible   = true

	# ── Hide surplus pool panels ──────────────────────────────────────────────
	for i: int in range(_active.size(), _pool.size()):
		var p: PanelContainer = _pool[i] as PanelContainer
		if p.visible:
			p.visible = false
```

Replace it with exactly this:

```gdscript
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	# ── No camera — hide everything ──────────────────────────────────────────
	if camera == null:
		for p: PanelContainer in _pool:
			p.visible = false
		return

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < _active.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)
		_icon_viewports.append(_build_icon_slots(clone))
		_icon_loaded_sig.append(["", "", ""])

	# ── Phase 1: compute each panel's natural position/size/alpha and update
	## its content. `layouts[i]` is null for a hidden entry, else a Dictionary
	## with pos/size/alpha/priority/dist — Aug 2026, split out of the single
	## loop this used to be so overlap avoidance (Phase 2) can see every
	## panel's real size (post-content-update) before any position is final.
	var layouts: Array = []
	for i: int in _active.size():
		var entry: Dictionary  = _active[i]
		var p: PanelContainer  = _pool[i] as PanelContainer
		var world_pos: Vector3 = entry["world_pos"] + WORLD_OFFSET

		if camera.is_position_behind(world_pos):
			p.visible = false
			layouts.append(null)
			continue

		p.reset_size()
		var screen_pos: Vector2 = camera.unproject_position(world_pos)

		var dist: float  = entry.get("dist", 0.0)
		var alpha: float = 1.0
		if dist > FADE_START:
			alpha = clampf(1.0 - (dist - FADE_START) / (FADE_END - FADE_START), 0.0, 1.0)

		var lbl: RichTextLabel = p.get_node_or_null("VBox/Label") as RichTextLabel
		var txt: String = entry.get("text", "")
		if lbl != null and lbl.text != txt:
			lbl.text = txt

		var icons: Array = entry.get("icons", [])
		var icon_row: Control = p.get_node_or_null("VBox/IconRow") as Control
		if icon_row != null:
			icon_row.visible = not icons.is_empty()
			if not icons.is_empty():
				_refresh_icon_slots(i, icons)

		p.reset_size()
		layouts.append({
			"pos":      screen_pos - p.size / 2.0,
			"size":     p.size,
			"alpha":    alpha,
			"priority": 1 if not icons.is_empty() else 0,
			"dist":     dist,
		})

	## Phase 2: pairwise overlap avoidance — only moves panels that actually
	## overlap on screen; every other panel keeps its natural position
	## exactly as before. See _resolve_overlaps()'s own header for the rule.
	_resolve_overlaps(layouts)

	## Phase 3: apply final positions.
	for i: int in _active.size():
		var p: PanelContainer = _pool[i] as PanelContainer
		var lay: Variant = layouts[i]
		if lay == null:
			p.visible = false
			continue
		var d: Dictionary = lay as Dictionary
		p.position = d["pos"]
		p.modulate = Color(1.0, 1.0, 1.0, float(d["alpha"]))
		p.visible  = true

	# ── Hide surplus pool panels ──────────────────────────────────────────────
	for i: int in range(_active.size(), _pool.size()):
		var p: PanelContainer = _pool[i] as PanelContainer
		if p.visible:
			p.visible = false

## Pushes lower-priority panels directly below higher-priority ones until no
## two visible panels' rects overlap. Priority: an entry with a non-empty
## icon row (e.g. CookingPot's ingredient previews) outranks a plain-text
## entry (e.g. a Stove's on/off toggle) — ties broken by whichever is
## closer to the player. This is a general rule, not a hardcoded pot-vs-
## stove case, so it covers any future pair of nearby prompts too. Runs a
## few passes so a chain of 3+ overlapping panels all separate out cleanly.
const OVERLAP_GAP: float = 6.0
const OVERLAP_PASSES: int = 4

func _resolve_overlaps(layouts: Array) -> void:
	for _pass: int in OVERLAP_PASSES:
		var moved_any: bool = false
		for a: int in layouts.size():
			var la: Variant = layouts[a]
			if la == null:
				continue
			for b: int in range(a + 1, layouts.size()):
				var lb: Variant = layouts[b]
				if lb == null:
					continue
				var da: Dictionary = la as Dictionary
				var db: Dictionary = lb as Dictionary
				var ra: Rect2 = Rect2(da["pos"] as Vector2, da["size"] as Vector2)
				var rb: Rect2 = Rect2(db["pos"] as Vector2, db["size"] as Vector2)
				if not ra.intersects(rb):
					continue

				var a_wins: bool = float(da["priority"]) > float(db["priority"]) \
					or (float(da["priority"]) == float(db["priority"]) and float(da["dist"]) <= float(db["dist"]))
				var top: Dictionary    = da if a_wins else db
				var bottom: Dictionary = db if a_wins else da

				var new_y: float = (top["pos"] as Vector2).y + (top["size"] as Vector2).y + OVERLAP_GAP
				if (bottom["pos"] as Vector2).y != new_y:
					bottom["pos"] = Vector2((bottom["pos"] as Vector2).x, new_y)
					moved_any = true
		if not moved_any:
			break
```

---

## 5. Seed preview color bug — found and fixed

**Root cause:** `BuildModeHUD.PREVIEW_SOURCES` maps every one of the 12
seed `tile_id`s (2-13) to the same generic `SeedItem.gd` script, but never
sets `SeedItem.gd`'s own `seed_type` export var before instantiating it —
unlike `FarmProduceItem`'s `produce_type`, which this same file's
`_refresh_shop_previews()` explicitly sets per-instance already. Since
`seed_type` defaults to `"tomato"` when never set, every single seed
preview rendered as a generic tomato-colored packet — the mesh/color logic
itself (`PlantDatabase.get_seed_packet_color(seed_type)`) already supports
all 12 species correctly, it just never received the right value.

### Step 5.1 — Edit `scripts/ui/build/BuildModeHUD.gd`

Find this exact block:

```gdscript
const PREVIEW_SOURCES: Dictionary = {
	2:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	3:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	4:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	5:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	6:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	7:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	8:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	9:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	10: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	11: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	12: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
	13: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true },
```

Replace it with exactly this (keeps the dict open exactly as before —
whatever entries follow key `13` in the file, e.g. soil/fertilizer/
resources, are unchanged and untouched below this block):

```gdscript
const PREVIEW_SOURCES: Dictionary = {
	## Aug 2026 fix — each seed now carries its own seed_type so
	## _refresh_shop_previews() below can set it on the instance before
	## _ready() runs, exactly matching FarmProduceItem's existing
	## produce_type handling. Without this every seed defaulted to
	## SeedItem.gd's "tomato" fallback and looked identical. Values match
	## FarmingShopHelper.SHOP_ITEM_INFO's "type" field exactly for each id.
	2:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "tomato" },
	3:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "onion" },
	4:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "basil" },
	5:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "strawberry" },
	6:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "carrot" },
	7:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "chili_pepper" },
	8:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "bell_pepper" },
	9:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "garlic" },
	10: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "potato" },
	11: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "blueberry" },
	12: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "corn" },
	13: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "pumpkin" },
```

### Step 5.2 — Actually apply `seed_type` before the instance enters the tree

Find this exact block:

```gdscript
		var inst: Node3D = null
		if bool(info.get("is_script", false)):
			var script: GDScript = load(String(info["scene"])) as GDScript
			if script == null:
				continue
			inst = script.new()
		else:
			var packed: PackedScene = load(String(info["scene"])) as PackedScene
			if packed == null:
				continue
			inst = packed.instantiate() as Node3D
		if inst == null:
			continue
```

Replace it with exactly this:

```gdscript
		var inst: Node3D = null
		if bool(info.get("is_script", false)):
			var script: GDScript = load(String(info["scene"])) as GDScript
			if script == null:
				continue
			inst = script.new()
			## Aug 2026 fix — must be set BEFORE the node enters the tree, so
			## SeedItem.gd's own _ready() builds its placeholder mesh with the
			## correct species color instead of the "tomato" default.
			if info.has("seed_type") and "seed_type" in inst:
				inst.set("seed_type", info["seed_type"])
		else:
			var packed: PackedScene = load(String(info["scene"])) as PackedScene
			if packed == null:
				continue
			inst = packed.instantiate() as Node3D
		if inst == null:
			continue
```

---

## 6. Verification checklist

1. Open the Farming shop's Seeds category in Build Mode — confirm all 12
   seed packets now show visually distinct colors/models matching their
   spawned-in-world appearance (e.g. Blueberry blue, Basil green).
2. Cooking Pot: confirm the 3 circles and the whole icon row are back to
   their original (pre-last-pass) size — not the 2x-larger version.
3. Confirm the middle circle is still visibly higher than the two flanking
   it, and the panel still has the top padding (circles not touching the
   edge).
4. Place a Cooking Pot on a Stove with ingredients in it — confirm the
   Pot's panel (pickup line + filling/cooking status + icons) and the
   Stove's panel (on/off toggle) no longer overlap, and the Pot's panel is
   always the one on top.
5. Walk around a pot-on-stove setup from different angles/distances —
   confirm the two panels stay separated no matter where you stand (the
   fix is generic screen-space math, not a fixed world-space offset).
6. Confirm an ordinary stove with no pot on it, and an ordinary pot not on
   a stove, both still behave exactly as before — single panel, no
   unnecessary repositioning.
7. Confirm no console errors referencing `InteractPrompt` or
   `BuildModeHUD`.
