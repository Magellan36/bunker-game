extends CanvasLayer
## InteractPrompt.gd
## Renders floating world-space prompt panels anchored to 3D positions.
##
## ARCHITECTURE (rewritten v64):
##   - Single source of truth: _active[] array set each frame by the caller
##   - Panel pool grows on demand, never shrinks (avoids alloc/free per frame)
##   - ALL visibility, position, alpha, and text updates happen in ONE place: _process()
##   - set_prompts() ONLY updates _active[]. _process() does all rendering.
##   - This eliminates the race between set_prompts() hiding panels and _process()
##     showing them, which caused the flicker/not-appearing bug.
##
## ICON ROW (Aug 2026, Cooking System) — up to 3 small circular live-3D
## previews above the text, used by CookingPot to show its ingredients
## filling in left-to-right as they're added. Same SubViewport + orthogonal
## Camera3D + OmniLight3D technique BuildModeHUD's construct/shop menu
## previews already use (see BuildModeHUD._refresh_shop_previews()) — just
## built procedurally per pool panel instead of baked into the .tscn, since
## the pool grows on demand at runtime. Any entry without an "icons" array
## (i.e. every non-CookingPot prompt) simply hides the row.

# ─── Template panel ───────────────────────────────────────────────────────────
@onready var _template_panel:    PanelContainer  = $Panel
@onready var _template_label:    RichTextLabel   = $Panel/VBox/Label
@onready var _template_icon_row: Control          = $Panel/VBox/IconRow

## Vertical world-space offset so the panel floats above the object origin
const WORLD_OFFSET: Vector3 = Vector3(0.0, 1.2, 0.0)

## Fade band: fully opaque [0 .. FADE_START], linear fade [FADE_START .. FADE_END]
## FADE_END must match InteractionSystem.MAX_PROMPT_DIST so alpha hits 0
## exactly when the distance cap removes the entry.
const FADE_START: float = 2.2
const FADE_END:   float = 3.2

## Icon SubViewport render size (px) / orthogonal camera framing.
const ICON_VP_SIZE: int = 40
const ICON_CAM_SIZE: float = 0.6

# ─── State ────────────────────────────────────────────────────────────────────
## What the caller wants shown this frame.
## Array of { text: String, world_pos: Vector3, dist: float, icons: Array (optional) }
var _active: Array = []

## Pool of PanelContainers. Index matches _active[]. Grows, never shrinks.
var _pool: Array = []   ## Array[PanelContainer]

## Per pool-panel-index: Array[3] of SubViewport (icon slot 0/1/2).
var _icon_viewports: Array = []

## Per pool-panel-index: Array[3] of String — a cheap signature of whatever
## is CURRENTLY instanced in that icon slot, so re-instantiation only
## happens when a slot's content actually changes, not every frame.
var _icon_loaded_sig: Array = []

## Per pool-panel-index: Array[3] of Label — small text badge overlaid in
## each icon slot's corner for partial-charge ingredients (e.g. "1/2",
## "67%"). Added Aug 2026.
var _icon_badge_labels: Array = []

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_template_panel.visible = false

func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	# ── No camera — hide everything ──────────────────────────────────────────
	if camera == null:
		for p: PanelContainer in _pool:
			p.visible = false
		return

	## Focus Mode (Aug 2026, broadened) — hold Ctrl to collapse every
	## prompt down to the single closest one, hiding the rest. Debugging
	## aid for prompt-priority bugs as well as a normal player-facing
	## decluttering option when several prompts compete for attention. A
	## HOLD, not a toggle — release Ctrl and everything returns to normal
	## immediately, no state to reset.
	##
	## Resolution is entirely Player-owned: InteractionSystem tags exactly
	## one CASE-2 (empty-handed) entry per frame with "is_focus_target":
	## true, every other CASE-2 entry gets "is_focus_target": false. This
	## file only reads the tag, it never re-derives priority itself.
	## v2 — originally tagged only whatever E would fire on, which meant
	## pickup-only objects (Test Crate, Fuel Can, etc. — no on_interact())
	## never got a Focus Mode prompt at all even though they show fine
	## normally; now it's simply the closest object with any prompt
	## (E or F), with the grow-light-over-tray override still applied.
	##
	## Entries that never set the key at all (every CASE-1 held-item
	## entry — basket/cookpot/give-to-NPC/held-item's-own-action) default
	## to shown via the `true` fallback below: Focus Mode intentionally
	## has no effect while holding an item this pass.
	var focus_mode: bool = Input.is_key_pressed(KEY_CTRL)
	var display_list: Array = _active
	if focus_mode:
		display_list = _active.filter(func(e: Dictionary) -> bool: return bool(e.get("is_focus_target", true)))

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < display_list.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)
		_icon_viewports.append(_build_icon_slots(clone))
		_icon_loaded_sig.append(["", "", ""])
		_icon_badge_labels.append(_build_badge_labels(clone))

	# ── Phase 1: compute each panel's natural position/size/alpha and update
	## its content. `layouts[i]` is null for a hidden entry, else a Dictionary
	## with pos/size/alpha/priority/dist — Aug 2026, split out of the single
	## loop this used to be so overlap avoidance (Phase 2) can see every
	## panel's real size (post-content-update) before any position is final.
	var layouts: Array = []
	for i: int in display_list.size():
		var entry: Dictionary  = display_list[i]
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
	for i: int in display_list.size():
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
	for i: int in range(display_list.size(), _pool.size()):
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

# ─── Icon slot construction / refresh ─────────────────────────────────────────
## Builds the 3 SubViewport+Camera3D+OmniLight3D triples for one pool
## panel's IconRow (Slot0/Slot1/Slot2), matching BuildModeHUD's shop-preview
## viewport setup. Returns the 3 SubViewports so _process() can address
## them by index.
func _build_icon_slots(clone: PanelContainer) -> Array:
	var out: Array = [null, null, null]
	var row: Control = clone.get_node_or_null("VBox/IconRow") as Control
	if row == null:
		return out
	for slot_i: int in 3:
		var slot: PanelContainer = row.get_node_or_null("Slot%d" % slot_i) as PanelContainer
		if slot == null:
			continue
		var vpc: SubViewportContainer = SubViewportContainer.new()
		vpc.stretch = true
		vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(vpc)

		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(ICON_VP_SIZE, ICON_VP_SIZE)
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.transparent_bg = true
		vp.disable_3d     = false
		vp.own_world_3d   = true
		vpc.add_child(vp)

		var cam: Camera3D = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ICON_CAM_SIZE
		vp.add_child(cam)
		cam.position = Vector3(1.0, 1.2, 1.0)
		cam.call_deferred("look_at", Vector3.ZERO, Vector3.UP)

		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(1.0, 2.0, 1.0)
		light.light_energy = 3.0
		light.omni_range = 8.0
		vp.add_child(light)

		out[slot_i] = vp
	return out

## Small text badge (e.g. "1/2" or "67%") overlaid in each icon slot's
## bottom-right corner, for partial-charge ingredients. Added Aug 2026 as a
## SEPARATE pass over the same Slot0/1/2 nodes _build_icon_slots() already
## populates, rather than modifying that function, to keep this addition
## isolated and low-risk.
func _build_badge_labels(clone: PanelContainer) -> Array:
	var out: Array = [null, null, null]
	var row: Control = clone.get_node_or_null("VBox/IconRow") as Control
	if row == null:
		return out
	for slot_i: int in 3:
		var slot: PanelContainer = row.get_node_or_null("Slot%d" % slot_i) as PanelContainer
		if slot == null:
			continue
		var lbl: Label = Label.new()
		lbl.text = ""
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)
		out[slot_i] = lbl
	return out

## Re-instantiates only the slots whose content actually changed since last
## frame (tracked via _icon_loaded_sig), matching BuildModeHUD's own
## "queue_free old Node3D children, instantiate new one" pattern.
func _refresh_icon_slots(pool_index: int, icons: Array) -> void:
	var vps: Array = _icon_viewports[pool_index]
	var sigs: Array = _icon_loaded_sig[pool_index]
	var labels: Array = _icon_badge_labels[pool_index] if pool_index < _icon_badge_labels.size() else [null, null, null]
	for slot_i: int in 3:
		var vp: SubViewport = vps[slot_i] if slot_i < vps.size() else null
		if vp == null:
			continue
		var desc: Variant = icons[slot_i] if slot_i < icons.size() else null

		## Badge text updates every frame regardless of the 3D-render skip
		## below — it's a cheap string compare-and-set, no reason to gate it
		## on the expensive re-instantiation check that follows.
		var lbl: Label = labels[slot_i] if slot_i < labels.size() else null
		if lbl != null:
			var badge_txt: String = ""
			if desc != null and desc is Dictionary:
				badge_txt = String((desc as Dictionary).get("badge_text", ""))
			if lbl.text != badge_txt:
				lbl.text = badge_txt

		var sig: String = _signature_for(desc)
		if sigs[slot_i] == sig:
			continue   ## unchanged since last frame — skip re-instantiation
		sigs[slot_i] = sig

		for child in vp.get_children():
			if child is Node3D and child is not Camera3D and child is not OmniLight3D:
				child.queue_free()

		if desc == null or not (desc is Dictionary) or (desc as Dictionary).is_empty():
			continue   ## empty slot — circle stays empty, nothing to render

		var info: Dictionary = desc as Dictionary
		var inst: Node3D = null
		if bool(info.get("is_script", false)):
			var script: GDScript = load(String(info.get("scene", ""))) as GDScript
			if script == null:
				continue
			inst = script.new()
			## Per-instance variation (e.g. FarmProduceItem's produce_type)
			## must be set BEFORE the node enters the tree, so its own
			## _ready() picks up the correct value when building its mesh.
			if info.has("produce_type") and "produce_type" in inst:
				inst.set("produce_type", info["produce_type"])
		else:
			var packed: PackedScene = load(String(info.get("scene", ""))) as PackedScene
			if packed == null:
				continue
			inst = packed.instantiate() as Node3D
		if inst == null:
			continue

		if inst is RigidBody3D:
			var rb: RigidBody3D = inst as RigidBody3D
			rb.freeze = true
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		inst.set_process(false)
		inst.set_physics_process(false)

		var pivot: Node3D = Node3D.new()
		vp.add_child(pivot)
		pivot.add_child(inst)
		## Aug 2026 — matches BuildModeHUD's PREVIEW_ROTATION_DEFAULT exactly
		## (45° left, 45° down), same convention already applied to
		## InventoryHUD's previews. These previews had no rotation applied
		## at all before this — always rendered at each item's raw default
		## orientation.
		pivot.rotation_degrees = Vector3(-45.0, -45.0, 0.0)

func _signature_for(desc: Variant) -> String:
	if desc == null or not (desc is Dictionary) or (desc as Dictionary).is_empty():
		return ""
	var d: Dictionary = desc as Dictionary
	return "%s|%s" % [d.get("scene", ""), d.get("produce_type", "")]

# ─── Public API ───────────────────────────────────────────────────────────────
## Primary API — call every frame from InteractionSystem._update_prompt().
## Pass an Array of { "text": String, "world_pos": Vector3, "dist": float,
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null), "is_focus_target": bool (optional, Aug 2026 — Focus Mode:
## true for the single closest empty-handed candidate with any prompt
## (E or F), false for other empty-handed candidates, omitted entirely
## for held-item entries that haven't opted into Focus Mode filtering
## yet — a missing key defaults to shown) }. Pass [] to hide all panels.
func set_prompts(new_entries: Array) -> void:
	_active = new_entries

func show_prompt(text: String, world_position: Vector3) -> void:
	set_prompts([{ "text": text, "world_pos": world_position, "dist": 0.0 }])

func hide_prompt() -> void:
	set_prompts([])