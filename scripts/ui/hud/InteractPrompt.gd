extends CanvasLayer
## InteractPrompt.gd
## Renders floating world-space prompt panels anchored to 3D positions.
##
## ARCHITECTURE (rewritten v64, unified job cards Sep 2026):
##   - InteractionSystem owns _active[]; NPC job sources live separately in
##     _world_jobs and are merged only for rendering.
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
@onready var _template_label:    RichTextLabel   = $Panel/VBox/HBox/Label
@onready var _template_icon_row: Control          = $Panel/VBox/IconRow
@onready var _template_hold_icon: Control         = $Panel/VBox/HBox/HoldIcon

## Vertical world-space offset so the panel floats above the object origin
const WORLD_OFFSET: Vector3 = Vector3(0.0, 1.2, 0.0)

## Fade band: fully opaque [0 .. FADE_START], linear fade [FADE_START .. FADE_END]
## FADE_END must match InteractionSystem.MAX_PROMPT_DIST so alpha hits 0
## exactly when the distance cap removes the entry.
const FADE_START: float = 2.2
const FADE_END:   float = 3.2

## Icon SubViewport render size (px) / orthogonal camera framing.
const ICON_VP_SIZE: int = 48
const ICON_CAM_SIZE: float = 0.6

## Compact shared player/NPC job-card treatment. The player keeps the normal
## target anchor; NPC entries provide their own slightly higher head anchor.
const JOB_CARD_MIN_WIDTH: float = 190.0
const JOB_BAR_HEIGHT: float = 4.0
const NPC_JOB_OFFSET: Vector3 = Vector3(0.0, 1.48, 0.0)
const NPC_JOB_STALE_MSEC: int = 1000
const JOB_GREEN: Color = Color(0.43, 0.78, 0.43, 1.0)
const JOB_TRACK: Color = Color(0.025, 0.032, 0.032, 0.92)
const BUNKER_BLUE: Color = Color(0.34, 0.70, 0.93, 1.0)
const DIM_IVORY: Color = Color(0.67, 0.64, 0.57, 0.94)
const APPEAR_DURATION: float = 0.12
const APPEAR_OFFSET_Y: float = 2.0

const JobGlyphScript: GDScript = preload("res://scripts/ui/hud/JobProgressGlyph.gd")

# ─── Key / button icons (Aug 2026) ────────────────────────────────────────────
## Inline icon size in the prompt RichTextLabel (px). The source art is 16px;
## a restrained 17px presentation gives the keycap enough weight beside type.
const PROMPT_ICON_SIZE: int = 17
const PROMPT_ICON_DIR: String = "res://assets/ui/prompts/"
## Keyboard: prompt-key token -> key-cap icon file name.
const KEY_CAPS: Dictionary = {
	"E": "E", "F": "F", "G": "G",
	"0": "0", "1": "1", "2": "2", "3": "3", "4": "4",
	"5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
}
## Controller: prompt-key token -> Xbox button icon file name, matching the
## game's controller bindings (interact=A, pickup=X, store=Y).
const XBOX_BUTTONS: Dictionary = {
	"E": "XBOX_A", "F": "XBOX_X", "G": "XBOX_Y",
}

# ─── State ────────────────────────────────────────────────────────────────────
## What the caller wants shown this frame.
## Array of { text: String, world_pos: Vector3, dist: float, icons: Array (optional) }
var _active: Array = []

## NPC work indicators registered through set_world_job(). Kept independent
## from _active so InteractionSystem's per-frame set_prompts()/hide_prompt()
## calls cannot erase NPC jobs that are still running.
var _world_jobs: Dictionary = {}

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

## Per pool-panel-index: ProgressBar, shown beneath the label whenever an
## entry carries a "progress" key (0.0-1.0) — Job Progress Bar system
## (Aug 2026, InteractionSystem.start_job()). Built lazily per panel, same
## grows-with-the-pool convention as the icon slots/badge labels above.
var _progress_bars: Array = []
var _progress_labels: Array = []
var _job_glyphs: Array = []
var _panel_appear: Array[float] = []
var _panel_was_visible: Array[bool] = []
var _fuel_percent_regex: RegEx = RegEx.new()

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("interact_prompt")
	_template_panel.visible = false
	## Inline key/button icons are rendered as BBCode images.
	_template_label.bbcode_enabled = true
	# Compiled once; used only to tint the live generator fuel metadata. The
	# rest of the prompt text remains producer-owned and passes through intact.
	_fuel_percent_regex.compile("(?i)([0-9]+)%[ ]+fuel")

func _process(delta: float) -> void:
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
	var focus_mode: bool = FocusMode.is_active()
	var combined_entries: Array = _active.duplicate()
	combined_entries.append_array(_collect_world_job_entries())
	var display_list: Array = combined_entries
	if focus_mode:
		display_list = combined_entries.filter(
			func(e: Dictionary) -> bool: return bool(e.get("is_focus_target", true)))

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < display_list.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)
		_icon_viewports.append(_build_icon_slots(clone))
		_icon_loaded_sig.append(["", "", ""])
		_icon_badge_labels.append(_build_badge_labels(clone))
		_progress_bars.append(_build_progress_bar(clone))
		_progress_labels.append(_build_progress_label(clone))
		_job_glyphs.append(_build_job_glyph(clone))
		_panel_appear.append(0.0)
		_panel_was_visible.append(false)

	# ── Phase 1: compute each panel's natural position/size/alpha and update
	## its content. `layouts[i]` is null for a hidden entry, else a Dictionary
	## with pos/size/alpha/priority/dist — Aug 2026, split out of the single
	## loop this used to be so overlap avoidance (Phase 2) can see every
	## panel's real size (post-content-update) before any position is final.
	var layouts: Array = []
	for i: int in display_list.size():
		var entry: Dictionary  = display_list[i]
		var p: PanelContainer  = _pool[i] as PanelContainer
		var world_offset: Vector3 = entry.get("world_offset", WORLD_OFFSET)
		var world_pos: Vector3 = entry["world_pos"] + world_offset

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

		var lbl: RichTextLabel = p.get_node_or_null("VBox/HBox/Label") as RichTextLabel
		var is_job: bool = entry.has("progress")
		var txt: String = entry.get("text", "")
		if is_job:
			txt = _job_display_text(txt)
		var rendered: String = _prompt_to_bbcode(txt)
		if lbl != null and lbl.text != rendered:
			lbl.text = rendered

		## Hold-to-fire icon + fill ring (Aug 2026) — the Research Station
		## chute's hold-to-feed prompt. When an entry carries a
		## "hold_progress" key, show the F/X button icon with a white ring
		## that sweeps clockwise as the player holds; hidden for every other
		## prompt.
		var hold_icon: Control = p.get_node_or_null("VBox/HBox/HoldIcon") as Control
		if hold_icon != null:
			if entry.has("hold_progress"):
				hold_icon.visible = true
				hold_icon.call("set_progress", clampf(float(entry["hold_progress"]), 0.0, 1.0))
				var hold_prefix: Control = p.get_node_or_null("VBox/HBox/HoldPrefix") as Control
				if hold_prefix != null:
					hold_prefix.visible = true
			else:
				hold_icon.visible = false
				var hold_prefix: Control = p.get_node_or_null("VBox/HBox/HoldPrefix") as Control
				if hold_prefix != null:
					hold_prefix.visible = false

		var icons: Array = entry.get("icons", [])
		var icon_row: Control = p.get_node_or_null("VBox/IconRow") as Control
		if icon_row != null:
			icon_row.visible = not icons.is_empty()
			if not icons.is_empty():
				_refresh_icon_slots(i, icons)

		## Job Progress Bar (Aug 2026) — shown beneath the label whenever the
		## entry carries a "progress" key (InteractionSystem.start_job()'s own
		## _render_job_prompt()). Augments the label text rather than replacing
		## it, so the "Turning Stove On..." line stays readable while the bar
		## fills underneath it.
		var progress_bar: ProgressBar = _progress_bars[i] if i < _progress_bars.size() else null
		var progress_label: Label = _progress_labels[i] if i < _progress_labels.size() else null
		var job_glyph: Control = _job_glyphs[i] if i < _job_glyphs.size() else null
		if progress_bar != null:
			if is_job:
				var progress: float = clampf(float(entry["progress"]), 0.0, 1.0)
				progress_bar.visible = true
				progress_bar.value = progress
				if progress_label != null:
					progress_label.text = "%d%%" % int(round(progress * 100.0))
					progress_label.visible = true
				if job_glyph != null:
					job_glyph.visible = true
				p.custom_minimum_size.x = JOB_CARD_MIN_WIDTH
			else:
				progress_bar.visible = false
				if progress_label != null:
					progress_label.visible = false
				if job_glyph != null:
					job_glyph.visible = false
				p.custom_minimum_size.x = 0.0

		p.reset_size()
		layouts.append({
			"pos":      screen_pos - p.size / 2.0,
			"size":     p.size,
			"alpha":    alpha,
			"priority": int(entry.get("display_priority",
				2 if is_job else (1 if not icons.is_empty() else 0))),
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
			_panel_was_visible[i] = false
			continue
		var d: Dictionary = lay as Dictionary
		if not _panel_was_visible[i]:
			_panel_appear[i] = 0.0
			var chrome: Control = p.get_node_or_null("PromptChrome") as Control
			if chrome != null and chrome.has_method("trigger_acquire"):
				chrome.call("trigger_acquire")
		_panel_appear[i] = minf(1.0, _panel_appear[i] + delta / APPEAR_DURATION)
		var appear: float = _panel_appear[i]
		p.position = d["pos"] + Vector2(0.0, (1.0 - appear) * APPEAR_OFFSET_Y)
		p.modulate = Color(1.0, 1.0, 1.0, float(d["alpha"]) * appear)
		p.visible  = true
		_panel_was_visible[i] = true

	# ── Hide surplus pool panels ──────────────────────────────────────────────
	for i: int in range(display_list.size(), _pool.size()):
		var p: PanelContainer = _pool[i] as PanelContainer
		if p.visible:
			p.visible = false
		_panel_was_visible[i] = false

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
## Cached true-circle slot background (see _make_circle_texture).
static var _circle_tex: Texture2D = null

## Generates a TRUE circle texture using the same charcoal, worn-brass, and
## restrained blue accent language as the approved bunker panels.
## StyleBoxFlat corner_radius draws a SQUIRCLE — four corner arcs
## with straight edges and visible AA seams, not a real circle — so the slot
## background is baked as an image instead (used via StyleBoxTexture).
func _make_circle_texture() -> Texture2D:
	if _circle_tex != null:
		return _circle_tex
	const SIZE: int = 64
	const C: float = 31.5
	const R_FILL: float = 26.5    ## inner translucent fill radius
	const R_OUT: float = 31.0     ## outline outer radius
	const RING_CENTER: float = 29.0   ## outline peak radius
	const RING_HALF_W: float = 2.0
	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(SIZE):
		for x in range(SIZE):
			var d: float = Vector2(float(x) - C, float(y) - C).length()
			var col: Color = Color(0, 0, 0, 0)
			if d <= R_FILL:
				# Slightly blue-charcoal fill keeps empty slots readable without
				# making them look occupied.
				col = Color(0.055, 0.075, 0.078, 0.92)
				# Fine blue inner keyline: enough to connect the bespoke three-
				# ingredient view to the wider UI system, never a neon ring.
				if d >= 25.2:
					var blue_edge: float = clampf((d - 25.2) / 1.3, 0.0, 1.0)
					col = col.lerp(Color(0.25, 0.58, 0.76, 0.72), blue_edge * 0.7)
			elif d <= R_OUT:
				## Soft worn-brass outline — peaks at RING_CENTER and fades
				## both inward (into the fill) and outward (soft outer edge).
				var t: float = absf(d - RING_CENTER) / RING_HALF_W
				col = Color(0.48, 0.40, 0.27, 0.78 * clampf(1.0 - t, 0.0, 1.0))
			img.set_pixel(x, y, col)
	_circle_tex = ImageTexture.create_from_image(img)
	return _circle_tex

func _build_icon_slots(clone: PanelContainer) -> Array:
	var out: Array = [null, null, null]
	var row: Control = clone.get_node_or_null("VBox/IconRow") as Control
	if row == null:
		return out
	for slot_i: int in 3:
		var slot: PanelContainer = row.get_node_or_null("Slot%d" % slot_i) as PanelContainer
		if slot == null:
			continue
		## True circle background (baked texture) — replaces the template's
		## squircle StyleBoxFlat so the ring renders as a smooth circle.
		var sb: StyleBoxTexture = StyleBoxTexture.new()
		sb.texture = _make_circle_texture()
		slot.add_theme_stylebox_override("panel", sb)
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
		GraphicsSettings.register_preview_viewport(vp)

		var cam: Camera3D = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ICON_CAM_SIZE
		vp.add_child(cam)
		cam.position = Vector3(1.0, 1.2, 1.0)
		cam.call_deferred("look_at", Vector3.ZERO, Vector3.UP)

		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(1.0, 2.0, 1.0)
		light.light_color = Color(0.95, 0.90, 0.79, 1.0)
		light.light_energy = 2.8
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
		lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.83, 1.0))
		lbl.add_theme_color_override("font_outline_color", Color(0.025, 0.032, 0.032, 0.98))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)
		out[slot_i] = lbl
	return out

## Builds the compact bottom progress track shared by player and NPC jobs.
func _build_progress_bar(clone: PanelContainer) -> ProgressBar:
	var vbox: VBoxContainer = clone.get_node_or_null("VBox") as VBoxContainer
	if vbox == null:
		return null
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value          = 0.0
	bar.max_value          = 1.0
	bar.step               = 0.0
	bar.show_percentage    = false
	bar.custom_minimum_size = Vector2(JOB_CARD_MIN_WIDTH - 16.0, JOB_BAR_HEIGHT)
	bar.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	bar.visible            = false

	var fg: StyleBoxFlat = StyleBoxFlat.new()
	fg.bg_color = JOB_GREEN
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)

	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = JOB_TRACK
	bg.border_color = Color(0.31, 0.27, 0.19, 0.72)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)

	vbox.add_child(bar)
	return bar


## Right-aligned exact progress preserves the information carried by real work
## speed modifiers without making the card any taller.
func _build_progress_label(clone: PanelContainer) -> Label:
	var row := clone.get_node_or_null("VBox/HBox") as HBoxContainer
	if row == null:
		return null
	var label := Label.new()
	label.name = "JobProgressPercent"
	label.custom_minimum_size.x = 30.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UIKit.font())
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", DIM_IVORY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	row.add_child(label)
	return label


func _build_job_glyph(clone: PanelContainer) -> Control:
	var row := clone.get_node_or_null("VBox/HBox") as HBoxContainer
	if row == null:
		return null
	var glyph: Control = JobGlyphScript.new()
	glyph.name = "JobGlyph"
	glyph.set("glyph_color", BUNKER_BLUE)
	glyph.visible = false
	row.add_child(glyph)
	row.move_child(glyph, 0)
	return glyph

## Re-instantiates only the slots whose content actually changed since last
## frame (tracked via _icon_loaded_sig), matching BuildModeHUD's own
## "queue_free old Node3D children, instantiate new one" pattern.
func _refresh_icon_slots(pool_index: int, icons: Array) -> void:
	var vps: Array = _icon_viewports[pool_index]
	var sigs: Array = _icon_loaded_sig[pool_index]
	var labels: Array = _icon_badge_labels[pool_index] \
		if pool_index < _icon_badge_labels.size() else [null, null, null]
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

# ─── Key / button icon rendering (Aug 2026) ───────────────────────────────────
## Converts a prompt string like "[F] Pick up  Flashlight" into BBCode for the
## RichTextLabel, replacing [E]/[F]/[G] key tokens with inline key-cap or Xbox
## button icons based on the current InputMode (last-input-wins). EVERYTHING
## else is passed through VERBATIM — the label is BBCode-enabled and must keep
## parsing its own tags (e.g. [color=#...]) exactly as it did before icons.
func _prompt_to_bbcode(prompt: String) -> String:
	var controller: bool = InputMode.is_controller()
	var semantic_prompt: String = _style_prompt_semantics(prompt)
	var out: String = ""
	var i: int = 0
	while i < semantic_prompt.length():
		if semantic_prompt[i] == "[":
			var raw: String = _match_key_token(semantic_prompt, i)
			if raw != "":
				## raw is "[X]" or "[<action> X]" — the key is the char before
				## the closing bracket; the action word (e.g. "Hold") renders
				## as plain text ahead of the icon, so "[Hold E] Refill Bottle"
				## shows as "Hold <A-icon>  Refill Bottle".
				var key: String  = raw[raw.length() - 2]
				var word: String = raw.substr(1, raw.length() - 4) if raw.length() > 3 else ""
				out += (word + " " if word != "" else "") + _token_bbcode(key, controller)
				i += raw.length()
				continue
		out += semantic_prompt[i]
		i += 1
	return out


## Adds colour hierarchy to a deliberately small set of shared status phrases.
## This is presentation only: producers still own their exact wording and all
## bespoke data (including CookingPot's dish name, filling, cook time, and the
## three ingredient descriptors) continues through unchanged.
func _style_prompt_semantics(prompt: String) -> String:
	var out: String = prompt
	# Replace the established wide divider with the worn-brass hairline used by
	# modern panels. Newlines and multi-action prompt structure are untouched.
	out = out.replace("  —  ", "  [color=#8B744C]│[/color]  ")

	# Known machine/system states. Exact replacements keep action wording such
	# as "Turn Stove On" from being mistaken for a status.
	var states: Dictionary = {
		"[Running]": "[color=#74D48A]● RUNNING[/color]",
		"[Backup — Active]": "[color=#74D48A]● BACKUP ACTIVE[/color]",
		"[Backup — Standby]": "[color=#D2AA68]● STANDBY[/color]",
		"[Stopped]": "[color=#DF7669]● STOPPED[/color]",
		"[Online]": "[color=#74D48A]● ONLINE[/color]",
		"[ON]": "[color=#74D48A]● ON[/color]",
		"[OFF]": "[color=#B5AA96]● OFF[/color]",
		"COOKING": "[color=#74D48A]● COOKING[/color]",
		"DONE": "[color=#74D48A]● READY[/color]",
		"NO POWER": "[color=#DF7669]● NO POWER[/color]",
		"SHED": "[color=#D2AA68]● SHED[/color]",
		"Stove Not Connected": "[color=#DF7669]STOVE NOT CONNECTED[/color]",
		"  [color=#8B744C]│[/color]  OFF": "  [color=#8B744C]│[/color]  [color=#B5AA96]● OFF[/color]",
		"  [color=#8B744C]│[/color]  ON 500W": "  [color=#8B744C]│[/color]  [color=#74D48A]● ON 500W[/color]",
		"(Dead)": "[color=#DF7669](DEAD)[/color]",
		"(Empty)": "[color=#8F8A7F](EMPTY)[/color]",
		"Inventory full": "[color=#D2AA68]INVENTORY FULL[/color]",
		"Shelf full": "[color=#D2AA68]SHELF FULL[/color]",
		"  →  ": "  [color=#62BAF2]→[/color]  ",
		"(+": "[color=#74D48A](+",
		" Diversity)": " DIVERSITY)[/color]",
	}
	for source: String in states:
		out = out.replace(source, String(states[source]))
	# Some older producers use a single-spaced em dash (not the standard
	# double-spaced separator). Normalize those after state tokens have been
	# resolved so names such as "Backup — Active" remain semantic atoms.
	out = out.replace(" — ", " [color=#8B744C]│[/color] ")

	if _fuel_percent_regex.is_valid():
		out = _fuel_percent_regex.sub(out, "[color=#C6A86B]$1% FUEL[/color]", true)
	return out

## Returns the FULL bracketed key token at prompt[i] — either "[X]" or a
## "[<action> X]" hold-style token like "[Hold E]" — or "" if prompt[i]
## isn't a key token. Callers skip exactly raw.length() characters.
func _match_key_token(prompt: String, i: int) -> String:
	if i + 2 >= prompt.length() or prompt[i] != "[":
		return ""
	## Fast path: "[X]" exactly.
	if prompt[i + 2] == "]":
		if _is_key_char(prompt[i + 1]):
			return "[%s]" % prompt[i + 1]
		return ""
	## "[<action> X]" path — scan a letters-only word, then require
	## "<space><key>]". Collides with nothing in BBCode ([color=..], [/img],
	## [center], etc. all fail this shape check).
	var j: int = i + 1
	while j < prompt.length() and prompt[j] != " " and prompt[j] != "]" \
			and prompt[j].is_valid_identifier():
		j += 1
	if j + 2 >= prompt.length():
		return ""
	if prompt[j] == " " and _is_key_char(prompt[j + 1]) and prompt[j + 2] == "]":
		return "[%s %s]" % [prompt.substr(i + 1, j - (i + 1)), prompt[j + 1]]
	return ""

func _is_key_char(c: String) -> bool:
	return "EFG0123456789".contains(c)

## Builds the inline-image BBCode for a key token, or falls back to the
## literal "[X]" text if the current input mode has no icon for it.
func _token_bbcode(token: String, controller: bool) -> String:
	var file: String = ""
	if controller and XBOX_BUTTONS.has(token):
		file = XBOX_BUTTONS[token]
	elif KEY_CAPS.has(token):
		file = KEY_CAPS[token]
	if file == "":
		return "[%s]" % token
	return "[img width=%d height=%d]%s%s.png[/img]" % [
		PROMPT_ICON_SIZE, PROMPT_ICON_SIZE, PROMPT_ICON_DIR, file]


func _job_display_text(raw_text: String) -> String:
	var cleaned := raw_text.strip_edges()
	while cleaned.ends_with("."):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	return cleaned.to_upper()


## Produces render entries for every live NPC job and removes stale sources.
## A short update timeout is defensive: an interrupted activity can never leave
## a permanent progress card behind even if one exit path forgets to clear it.
func _collect_world_job_entries() -> Array:
	var entries: Array = []
	var stale_ids: Array = []
	var now := Time.get_ticks_msec()
	for source_id: int in _world_jobs:
		var job: Dictionary = _world_jobs[source_id]
		var source_ref := job.get("source") as WeakRef
		var source: Node3D = null
		if source_ref != null:
			source = source_ref.get_ref() as Node3D
		if source == null or not is_instance_valid(source) \
				or now - int(job.get("updated_at_msec", 0)) > NPC_JOB_STALE_MSEC:
			stale_ids.append(source_id)
			continue
		entries.append({
			"text": str(job.get("text", "WORKING")),
			"world_pos": source.global_position,
			"world_offset": NPC_JOB_OFFSET,
			"dist": 0.0,
			"progress": clampf(float(job.get("progress", 0.0)), 0.0, 1.0),
			"display_priority": 2,
			"is_focus_target": true,
		})
	for source_id: int in stale_ids:
		_world_jobs.erase(source_id)
	return entries

# ─── Public API ───────────────────────────────────────────────────────────────
## Primary API — call every frame from InteractionSystem._update_prompt().
## Pass an Array of { "text": String, "world_pos": Vector3, "dist": float,
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null), "progress": float (optional, Aug 2026 — Job Progress Bar,
## 0.0-1.0, shows a fill bar beneath the text), "is_focus_target": bool
## (optional, Aug 2026 — Focus Mode: true for the single closest
## empty-handed candidate with any prompt (E or F), false for other
## empty-handed candidates, omitted entirely for held-item entries that
## haven't opted into Focus Mode filtering yet — a missing key defaults
## to shown) }. Pass [] to hide all panels.
func set_prompts(new_entries: Array) -> void:
	_active = new_entries

func show_prompt(text: String, world_position: Vector3) -> void:
	set_prompts([{ "text": text, "world_pos": world_position, "dist": 0.0 }])

func hide_prompt() -> void:
	set_prompts([])


## External world-job API used by NPC's preserved show/update/hide banner
## facade. InteractionSystem's player job continues through set_prompts(), so
## both routes arrive at the exact same pooled card and ProgressBar renderer.
func set_world_job(source: Node3D, action: String, progress: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	_world_jobs[source.get_instance_id()] = {
		"source": weakref(source),
		"text": action,
		"progress": clampf(progress, 0.0, 1.0),
		"updated_at_msec": Time.get_ticks_msec(),
	}


func clear_world_job(source: Node3D) -> void:
	if source == null:
		return
	_world_jobs.erase(source.get_instance_id())
