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
@onready var _template_icon_row: HBoxContainer   = $Panel/VBox/IconRow

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
		var icon_row: HBoxContainer = p.get_node_or_null("VBox/IconRow") as HBoxContainer
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

# ─── Icon slot construction / refresh ─────────────────────────────────────────
## Builds the 3 SubViewport+Camera3D+OmniLight3D triples for one pool
## panel's IconRow (Slot0/Slot1/Slot2), matching BuildModeHUD's shop-preview
## viewport setup. Returns the 3 SubViewports so _process() can address
## them by index.
func _build_icon_slots(clone: PanelContainer) -> Array:
	var out: Array = [null, null, null]
	var row: HBoxContainer = clone.get_node_or_null("VBox/IconRow") as HBoxContainer
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

## Re-instantiates only the slots whose content actually changed since last
## frame (tracked via _icon_loaded_sig), matching BuildModeHUD's own
## "queue_free old Node3D children, instantiate new one" pattern.
func _refresh_icon_slots(pool_index: int, icons: Array) -> void:
	var vps: Array = _icon_viewports[pool_index]
	var sigs: Array = _icon_loaded_sig[pool_index]
	for slot_i: int in 3:
		var vp: SubViewport = vps[slot_i] if slot_i < vps.size() else null
		if vp == null:
			continue
		var desc: Variant = icons[slot_i] if slot_i < icons.size() else null
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

func _signature_for(desc: Variant) -> String:
	if desc == null or not (desc is Dictionary) or (desc as Dictionary).is_empty():
		return ""
	var d: Dictionary = desc as Dictionary
	return "%s|%s" % [d.get("scene", ""), d.get("produce_type", "")]

# ─── Public API ───────────────────────────────────────────────────────────────
## Primary API — call every frame from InteractionSystem._update_prompt().
## Pass an Array of { "text": String, "world_pos": Vector3, "dist": float,
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null) }. Pass [] to hide all panels.
func set_prompts(new_entries: Array) -> void:
	_active = new_entries

func show_prompt(text: String, world_position: Vector3) -> void:
	set_prompts([{ "text": text, "world_pos": world_position, "dist": 0.0 }])

func hide_prompt() -> void:
	set_prompts([])