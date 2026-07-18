extends Control
## InventoryHUD.gd
## Draws 4 inventory slots at bottom-center of the screen.
## Each occupied slot shows a live 3D preview (SubViewport) + item name label.

const SLOT_SIZE:    float = 64.0
const SLOT_GAP:     float = 10.0
const CORNER:       float = 8.0
const LABEL_HEIGHT: float = 16.0   ## Space below the slot box for the name
const TOTAL_HEIGHT: float = SLOT_SIZE + LABEL_HEIGHT

const COLOR_BG:       Color = Color(0.10, 0.10, 0.10, 0.82)
const COLOR_BORDER:   Color = Color(0.25, 0.25, 0.25, 0.90)
const COLOR_SELECTED: Color = Color(0.55, 0.55, 0.55, 1.00)
const COLOR_LABEL:    Color = Color(0.75, 0.75, 0.75, 0.90)
const COLOR_NAME:     Color = Color(0.80, 0.78, 0.72, 0.95)

## Charge badge colours
const COLOR_CHARGE_BG:   Color = Color(0.08, 0.08, 0.08, 0.88)
const COLOR_CHARGE_FULL: Color = Color(0.75, 0.85, 0.70, 1.00)   ## greenish — has charges
const COLOR_CHARGE_LOW:  Color = Color(0.85, 0.55, 0.40, 1.00)   ## amber — last charge
const COLOR_CHARGE_FONT: float = 9.0                              ## font size for badge text

## Water bottle quality badge colours (Jul 2026 bottle rework) — mirrors
## WaterDispenserUI._quality_color()'s red/yellow/green convention exactly.
## Separate meaning from the charge badge colours above (those show
## charges-remaining, these show water QUALITY 0-100).
const CRIT_COLOR:         Color = Color(1.00, 0.35, 0.30, 1.00)
const WARN_COLOR:         Color = Color(1.00, 0.72, 0.10, 1.00)
const QUALITY_GOOD_COLOR: Color = Color(0.30, 0.85, 0.35, 1.00)

## Set by MainWorld after ready
var inventory: Node = null

var _selected_slot: int = -1

## Error message overlay — fades in red text above inventory bar
var _error_label: Label    = null
var _error_tween: Tween    = null
## Items whose charge_changed signal we're currently watching
var _charge_watched: Array = []

## One SubViewport per slot — holds the 3D preview scene
var _viewports:  Array[SubViewport]    = []
var _cameras:    Array[Camera3D]       = []
var _previews:   Array[MeshInstance3D] = []   ## Currently displayed mesh copy
var _vp_textures: Array[ViewportTexture] = []

func _ready() -> void:
	var total_w: float = SLOT_SIZE * 4 + SLOT_GAP * 3
	custom_minimum_size = Vector2(total_w, TOTAL_HEIGHT)
	_build_viewports()
	_build_error_label()

func _build_error_label() -> void:
	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_color_override("font_color", Color(0.92, 0.25, 0.25, 0.0))
	_error_label.add_theme_font_size_override("font_size", 13)
	## Positioned above the HUD bar — anchored via _process so it tracks layout
	_error_label.size = Vector2(300, 24)
	_error_label.visible = false
	add_child(_error_label)

## Shows a red fade-in/fade-out error message above the inventory bar.
## Safe to call from ShelfUI or any other system.
func show_error_message(text: String) -> void:
	if _error_label == null:
		return

	## Kill any in-progress tween first
	if _error_tween != null and _error_tween.is_valid():
		_error_tween.kill()

	_error_label.text = text
	_error_label.modulate.a = 0.0
	_error_label.visible = true

	## Centre above the HUD bar
	var bar_w: float = SLOT_SIZE * 4 + SLOT_GAP * 3
	_error_label.position = Vector2(bar_w * 0.5 - _error_label.size.x * 0.5, -32.0)

	_error_tween = create_tween()
	_error_tween.set_ease(Tween.EASE_OUT)
	_error_tween.set_trans(Tween.TRANS_QUAD)
	## Fade in 0.15s → hold 1.4s → fade out 0.45s
	_error_tween.tween_property(_error_label, "modulate:a", 1.0, 0.15)
	_error_tween.tween_interval(1.4)
	_error_tween.tween_property(_error_label, "modulate:a", 0.0, 0.45)
	_error_tween.tween_callback(func() -> void: _error_label.visible = false)

func _build_viewports() -> void:
	for i in 4:
		var vp := SubViewport.new()
		vp.size = Vector2i(int(SLOT_SIZE), int(SLOT_SIZE))
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.transparent_bg = true
		vp.disable_3d = false
		# CRITICAL: own world so the preview light doesn't leak into the main scene
		# and so the main scene's lights don't corrupt the preview render.
		vp.own_world_3d = true
		add_child(vp)

		# Camera at a fixed iso angle looking at origin.
		# IMPORTANT: add to tree BEFORE calling look_at() — look_at() requires
		# the node to be inside the scene tree to compute global transforms.
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.2
		vp.add_child(cam)   ## Must be in tree first
		cam.position = Vector3(0.8, 0.8, 0.8)
		cam.look_at(Vector3.ZERO, Vector3.UP)

		# Soft fill light so mesh isn't pitch black
		var light := OmniLight3D.new()
		light.position = Vector3(1.0, 1.5, 1.0)
		light.light_energy = 2.5
		light.omni_range = 8.0
		vp.add_child(light)

		_viewports.append(vp)
		_cameras.append(cam)
		_previews.append(null)

		# Grab the texture handle once — stays valid
		_vp_textures.append(vp.get_texture())

# ─── Public API ───────────────────────────────────────────────────────────────
func set_selected(slot: int) -> void:
	_selected_slot = slot
	queue_redraw()

## Called after inventory_changed — rebuilds preview meshes for all slots.
func refresh_previews() -> void:
	var slots: Array = inventory.slots if inventory != null else [null, null, null, null]
	for i in 4:
		_set_preview(i, slots[i])

	# ── Reconnect charge_changed listeners ──────────────────────────────────
	# Disconnect from any previously watched items (slots may have changed)
	for item in _charge_watched:
		if item != null and item.has_signal("charge_changed"):
			if item.charge_changed.is_connected(queue_redraw):
				item.charge_changed.disconnect(queue_redraw)
	_charge_watched.clear()

	# Connect to every currently slotted item that has the signal
	for item in slots:
		if item != null and item.has_signal("charge_changed"):
			item.charge_changed.connect(queue_redraw)
			_charge_watched.append(item)

	queue_redraw()

func _set_preview(slot_idx: int, item) -> void:
	var vp: SubViewport = _viewports[slot_idx]

	# Remove old preview mesh
	if _previews[slot_idx] != null:
		_previews[slot_idx].queue_free()
		_previews[slot_idx] = null

	if item == null:
		return

	# Get mesh from the item — try get_inventory_mesh() first, fallback to child scan
	var mesh_inst: MeshInstance3D = null

	if item.has_method("get_inventory_mesh"):
		var m: Mesh = item.get_inventory_mesh()
		if m != null:
			mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = m
	
	if mesh_inst == null:
		# Fallback: duplicate the first MeshInstance3D child of the item
		for child in item.get_children():
			if child is MeshInstance3D:
				mesh_inst = child.duplicate() as MeshInstance3D
				break

	if mesh_inst == null:
		return

	# Rotate 45° on Y for an angled look
	mesh_inst.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	mesh_inst.position = Vector3.ZERO

	# Add to viewport FIRST — node must be in the scene tree before we can
	# read its world-space AABB (get_aabb() needs a valid global transform).
	vp.add_child(mesh_inst)

	# Now read the AABB in the node's LOCAL space but transformed by its basis
	# so rotation is accounted for. mesh.get_aabb() is pre-rotation and gives
	# the wrong center; instead we transform it manually with the node's basis.
	if mesh_inst.mesh != null:
		var local_aabb: AABB  = mesh_inst.mesh.get_aabb()
		# Transform each corner through the rotation basis to get the true
		# rotated extents, then rebuild the AABB from the transformed center.
		var basis: Basis      = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center
	# else position stays Vector3.ZERO — nothing to center

	_previews[slot_idx] = mesh_inst

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _draw() -> void:
	var slots: Array = inventory.slots if inventory != null else [null, null, null, null]
	var font: Font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")

	for i in 4:
		var x: float = i * (SLOT_SIZE + SLOT_GAP)
		var rect: Rect2 = Rect2(x, 0.0, SLOT_SIZE, SLOT_SIZE)

		# ── Background ──
		draw_rect_with_corners(rect, COLOR_BG)

		# ── SubViewport texture (3D preview) ──
		var item = slots[i] if i < slots.size() else null
		if item != null and _vp_textures[i] != null:
			draw_texture_rect(_vp_textures[i], rect, false)

		# ── Border — highlight selected ──
		var border_col: Color = COLOR_SELECTED if i == _selected_slot else COLOR_BORDER
		draw_rect_with_corners_outline(rect, border_col, 2.0)

		# ── Slot number (top-left, subtle) ──
		var num: String = str(i + 1)
		draw_string(font, Vector2(x + 5.0, 13.0),
			num, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.40, 0.40, 0.40, 0.70))

		# ── Charge / quality badge (top-right) ──
		if item != null:
			## WaterBottle-style items (Jul 2026 rework) expose fill% + quality
			## via a dedicated contract — checked first, ahead of the generic
			## charge-count fallback chain below.
			if item.has_method("get_bottle_badge_info"):
				var bottle_info: Dictionary = item.get_bottle_badge_info()
				_draw_quality_badge(font, x,
					float(bottle_info.get("fill_mL", 0.0)),
					float(bottle_info.get("max_fill_mL", 750.0)),
					float(bottle_info.get("quality", 100.0)))
			else:
				var charge_info: Array = _get_charge_info(item)
				if charge_info.size() == 2:
					_draw_charge_badge(font, x, charge_info[0], charge_info[1])

		# ── Item name label below the slot ──
		var label_y: float = SLOT_SIZE + LABEL_HEIGHT - 3.0
		if item != null:
			var item_name: String = ""
			if item.has_method("get_display_name"):
				item_name = item.get_display_name()
			else:
				# Strip trailing numbers Godot appends (e.g. "WaterBottle2" → "Water Bottle")
				item_name = _prettify_name(item.name)

			var tsz: Vector2 = font.get_string_size(item_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
			var tx: float = x + SLOT_SIZE * 0.5 - tsz.x * 0.5
			draw_string(font, Vector2(tx, label_y),
				item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_NAME)

# ─── Charge info ──────────────────────────────────────────────────────────────
## Returns [current, max] if the item exposes charge data, otherwise [].
## Items can implement get_charge_info() -> Array[int] for custom logic,
## or the HUD falls back to the known variable names used by FoodCan.
## NOTE: WaterBottle no longer uses this chain (sip-count model retired, Jul
## 2026) — see get_bottle_badge_info() / _draw_quality_badge() above in _draw().
func _get_charge_info(item: Node) -> Array:
	# Preferred: item implements the interface explicitly
	if item.has_method("get_charge_info"):
		return item.get_charge_info()

	# Fallback: FoodCan-style (_bites_left / TOTAL_BITES)
	if "_bites_left" in item and "TOTAL_BITES" in item:
		return [item._bites_left, item.TOTAL_BITES]

	# Fallback: generic _charges / _max_charges convention for future items
	if "_charges" in item and "_max_charges" in item:
		return [item._charges, item._max_charges]

	return []

## Draws a small rounded badge in the top-right corner of the slot.
## current/max are ints — shows "current/max" or just "current" if max == 1.
func _draw_charge_badge(font: Font, slot_x: float, current: int, max_charges: int) -> void:
	var label: String = "%d/%d" % [current, max_charges] if max_charges > 1 else str(current)

	var font_size: int = int(COLOR_CHARGE_FONT)
	var tsz: Vector2  = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	# Badge rect — 4px padding each side, 3px top/bottom
	const PAD_X: float = 4.0
	const PAD_Y: float = 3.0
	var bw: float = tsz.x + PAD_X * 2.0
	var bh: float = tsz.y + PAD_Y * 2.0

	# Anchor top-right of the slot with a 3px inset
	const INSET: float = 3.0
	var bx: float = slot_x + SLOT_SIZE - bw - INSET
	var by: float = INSET

	# Background pill
	var badge_rect: Rect2 = Rect2(bx, by, bw, bh)
	draw_rect(badge_rect, COLOR_CHARGE_BG, true, -1.0)

	# Text colour: amber on last charge, green otherwise
	var text_col: Color = COLOR_CHARGE_LOW if current <= 1 else COLOR_CHARGE_FULL

	# Draw text centred in badge
	draw_string(font,
		Vector2(bx + PAD_X, by + PAD_Y + tsz.y - 2.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)

## Draws the water-bottle-specific badge — same pill shape/position as
## _draw_charge_badge() above, but shows "Xml/Yml" on one line and "(Q%)" on
## a second line beneath it, both coloured by water QUALITY (not charge state)
## (Jul 2026 bottle rework — separate, parallel contract, see
## get_bottle_badge_info() / _bottle_quality_color() below). Two lines instead
## of one because "525ml/750ml (70%)" is far wider than the 64px slot — a
## single line would overflow into the neighbouring slot's badge.
func _draw_quality_badge(font: Font, slot_x: float, fill_mL: float, max_fill_mL: float, quality: float) -> void:
	var line1: String = "%dml/%dml" % [int(round(fill_mL)), int(round(max_fill_mL))]
	var line2: String = "(%d%%)" % int(round(quality))

	var font_size: int = int(COLOR_CHARGE_FONT)
	var tsz1: Vector2 = font.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tsz2: Vector2 = font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	const PAD_X: float = 4.0
	const PAD_Y: float = 2.0
	const LINE_GAP: float = 1.0
	var bw: float = maxf(tsz1.x, tsz2.x) + PAD_X * 2.0
	var bh: float = tsz1.y + tsz2.y + LINE_GAP + PAD_Y * 2.0

	const INSET: float = 3.0
	var bx: float = slot_x + SLOT_SIZE - bw - INSET
	var by: float = INSET

	var badge_rect: Rect2 = Rect2(bx, by, bw, bh)
	draw_rect(badge_rect, COLOR_CHARGE_BG, true, -1.0)

	var text_col: Color = _bottle_quality_color(quality)

	draw_string(font,
		Vector2(bx + bw - PAD_X - tsz1.x, by + PAD_Y + tsz1.y - 2.0),
		line1, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)
	draw_string(font,
		Vector2(bx + bw - PAD_X - tsz2.x, by + PAD_Y + tsz1.y + LINE_GAP + tsz2.y - 2.0),
		line2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)

## Water quality red/yellow/green convention — mirrored verbatim from
## WaterDispenserUI._quality_color() (0-50 red / 50.01-75 yellow / 75.01-100
## green, inclusive lower boundary each tier). Duplicated per this project's
## existing per-file-helper convention for water UI colour code.
func _bottle_quality_color(quality: float) -> Color:
	if quality <= 50.0:
		return CRIT_COLOR
	elif quality <= 75.0:
		return WARN_COLOR
	return QUALITY_GOOD_COLOR

# ─── Name prettifier ──────────────────────────────────────────────────────────
func _prettify_name(raw: String) -> String:
	# Strip trailing digits
	var s: String = raw.strip_edges()
	while s.length() > 0 and s[-1].is_valid_int():
		s = s.substr(0, s.length() - 1)
	# Insert spaces before capital letters (PascalCase → "Pascal Case")
	var result: String = ""
	for i in s.length():
		if i > 0 and s[i] == s[i].to_upper() and s[i] != " ":
			result += " "
		result += s[i]
	return result.strip_edges()

# ─── Rounded rect helpers ─────────────────────────────────────────────────────
func draw_rect_with_corners(rect: Rect2, col: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(CORNER, 0),
		Vector2(rect.size.x - CORNER * 2, rect.size.y)), col, true)
	draw_rect(Rect2(rect.position + Vector2(0, CORNER),
		Vector2(rect.size.x, rect.size.y - CORNER * 2)), col, true)
	draw_circle(rect.position + Vector2(CORNER, CORNER), CORNER, col)
	draw_circle(rect.position + Vector2(rect.size.x - CORNER, CORNER), CORNER, col)
	draw_circle(rect.position + Vector2(CORNER, rect.size.y - CORNER), CORNER, col)
	draw_circle(rect.position + Vector2(rect.size.x - CORNER, rect.size.y - CORNER), CORNER, col)

func draw_rect_with_corners_outline(rect: Rect2, col: Color, width: float) -> void:
	draw_line(rect.position + Vector2(CORNER, 0),
		rect.position + Vector2(rect.size.x - CORNER, 0), col, width)
	draw_line(rect.position + Vector2(CORNER, rect.size.y),
		rect.position + Vector2(rect.size.x - CORNER, rect.size.y), col, width)
	draw_line(rect.position + Vector2(0, CORNER),
		rect.position + Vector2(0, rect.size.y - CORNER), col, width)
	draw_line(rect.position + Vector2(rect.size.x, CORNER),
		rect.position + Vector2(rect.size.x, rect.size.y - CORNER), col, width)
	var r: float = CORNER
	_draw_arc_corner(rect.position + Vector2(r, r),             r, PI,       PI * 1.5, col, width)
	_draw_arc_corner(rect.position + Vector2(rect.size.x-r, r), r, PI * 1.5, TAU,      col, width)
	_draw_arc_corner(rect.position + Vector2(r, rect.size.y-r), r, PI * 0.5, PI,       col, width)
	_draw_arc_corner(rect.position + Vector2(rect.size.x-r, rect.size.y-r), r, 0, PI*0.5, col, width)

func _draw_arc_corner(center: Vector2, r: float, from_angle: float, to_angle: float,
		col: Color, width: float) -> void:
	var steps: int = 8
	var prev: Vector2 = center + Vector2(cos(from_angle), sin(from_angle)) * r
	for s in range(1, steps + 1):
		var a: float = from_angle + (to_angle - from_angle) * s / steps
		var cur: Vector2 = center + Vector2(cos(a), sin(a)) * r
		draw_line(prev, cur, col, width)
		prev = cur
