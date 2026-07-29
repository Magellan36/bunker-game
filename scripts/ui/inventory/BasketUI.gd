extends CanvasLayer
## BasketUI.gd
## Overlay menu opened when the player presses G while holding a Basket.
## Shows up to 12 basket slots as 3D previews (SubViewport, 45° angle),
## with Drop / Add-to-inventory buttons beneath each occupied slot.
##
## Buttons:
##   ↓  (drop)    — pop item from slot, place it on the ground near player
##   ⊕  (inv)     — pop item into inventory pocket [only for pocket-sized items]
##
## "Pocket-sized" items must be in the "inventory_item" group (FoodCan, WaterBottle).
## Cases and crates never show the inventory button.
##
## Unlike ShelfUI: keeps menu open after Drop/Inv actions (item-by-item emptying),
## refreshes slot instead of closing. Title is "BASKET CONTENTS".

# ─── Dependencies (injected by MainWorld) ─────────────────────────────────────
var interaction_system: Node   = null
var inventory: Node            = null
var inventory_hud: Node        = null

# ─── State ────────────────────────────────────────────────────────────────────
var _basket: Node3D            = null
var is_open: bool              = false

# ─── Layout constants ─────────────────────────────────────────────────────────
const PREVIEW_SIZE:  int   = 96
const SLOT_GAP:      int   = 18
const BTN_SIZE:      float = 36.0   ## Square icon button side length
const BTN_GAP:       float = 8.0
const PANEL_PAD:     int   = 28
const PANEL_RADIUS:  float = 14.0
const BASKET_ROW_GAP: int  = 22
const ROW_LABEL_H:   int   = 18

# ─── Colours ──────────────────────────────────────────────────────────────────
const C_BG:          Color = Color(0.08, 0.08, 0.08, 0.92)
const C_SLOT_BG:     Color = Color(0.13, 0.13, 0.13, 1.00)
const C_SLOT_BORDER: Color = Color(0.28, 0.28, 0.28, 1.00)
const C_BTN_DROP:    Color = Color(0.55, 0.20, 0.20, 1.00)  ## Red for drop
const C_BTN_INV:     Color = Color(0.22, 0.33, 0.50, 1.00)
const C_BTN_TEXT:    Color = Color(0.90, 0.88, 0.84, 1.00)
const C_TITLE:       Color = Color(0.80, 0.78, 0.72, 1.00)
const C_EMPTY_TEXT:  Color = Color(0.35, 0.35, 0.35, 1.00)
const C_ROW_LABEL:   Color = Color(0.45, 0.43, 0.40, 1.00)
const C_BADGE_BG:    Color = Color(0.15, 0.40, 0.25, 1.00)
const C_BADGE_TEXT:  Color = Color(0.80, 1.00, 0.85, 1.00)

# ─── Nodes ────────────────────────────────────────────────────────────────────
var _root: Control           = null
var _panel: Panel            = null
var _viewports: Array        = []
var _vp_rects: Array         = []
var _drop_btns: Array        = []
var _inv_btns: Array         = []
var _badge_labels: Array     = []

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 10
	_build_ui()
	visible = false

# ─── Build UI ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.50)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	_root.add_child(backdrop)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color                   = C_BG
	ss.corner_radius_top_left     = int(PANEL_RADIUS)
	ss.corner_radius_top_right    = int(PANEL_RADIUS)
	ss.corner_radius_bottom_left  = int(PANEL_RADIUS)
	ss.corner_radius_bottom_right = int(PANEL_RADIUS)
	ss.border_width_left   = 1
	ss.border_width_right  = 1
	ss.border_width_top    = 1
	ss.border_width_bottom = 1
	ss.border_color = Color(0.30, 0.30, 0.30, 0.80)
	_panel.add_theme_stylebox_override("panel", ss)
	_root.add_child(_panel)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "BASKET CONTENTS"
	title.add_theme_color_override("font_color", C_TITLE)
	title.add_theme_font_size_override("font_size", 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(title)

	for i: int in 12:
		var vp := SubViewport.new()
		vp.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.transparent_bg  = true
		vp.own_world_3d    = true
		vp.disable_3d      = false
		_root.add_child(vp)

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.2
		vp.add_child(cam)
		cam.position = Vector3(0.8, 0.8, 0.8)
		cam.look_at(Vector3.ZERO, Vector3.UP)

		var light := OmniLight3D.new()
		light.position = Vector3(1.0, 1.5, 1.0)
		light.light_energy = 2.5
		light.omni_range = 8.0
		vp.add_child(light)

		var slot_bg: Panel = Panel.new()
		var slot_ss: StyleBoxFlat = StyleBoxFlat.new()
		slot_ss.bg_color                   = C_SLOT_BG
		slot_ss.corner_radius_top_left     = 6
		slot_ss.corner_radius_top_right    = 6
		slot_ss.corner_radius_bottom_left  = 6
		slot_ss.corner_radius_bottom_right = 6
		slot_ss.border_width_left   = 1
		slot_ss.border_width_right  = 1
		slot_ss.border_width_top    = 1
		slot_ss.border_width_bottom = 1
		slot_ss.border_color = C_SLOT_BORDER
		slot_bg.add_theme_stylebox_override("panel", slot_ss)
		slot_bg.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
		_panel.add_child(slot_bg)

		var tr: TextureRect = TextureRect.new()
		tr.texture = vp.get_texture()
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
		tr.position = slot_bg.position
		_panel.add_child(tr)

		var empty_lbl: Label = Label.new()
		empty_lbl.name = "EmptyLabel_%d" % i
		empty_lbl.text = "—"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", C_EMPTY_TEXT)
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
		_panel.add_child(empty_lbl)

		var badge: Label = Label.new()
		badge.name = "Badge_%d" % i
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
		badge.add_theme_color_override("font_color", C_BADGE_TEXT)
		badge.add_theme_font_size_override("font_size", 11)
		badge.size = Vector2(PREVIEW_SIZE - 4, 20)
		badge.visible = false
		_panel.add_child(badge)
		_badge_labels.append(badge)

		var drop_btn: Button = _make_icon_button("↓", "Drop", C_BTN_DROP, i, true)
		_panel.add_child(drop_btn)

		var inv_btn: Button = _make_icon_button("⊕", "Add to inventory", C_BTN_INV, i, false)
		_panel.add_child(inv_btn)

		_viewports.append(vp)
		_vp_rects.append(tr)
		_drop_btns.append(drop_btn)
		_inv_btns.append(inv_btn)

## Creates a square icon button with a hover tooltip.
func _make_icon_button(icon: String, tooltip: String, color: Color, slot_idx: int, is_drop: bool) -> Button:
	var btn: Button = Button.new()
	btn.text = icon
	btn.size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.tooltip_text = tooltip
	btn.add_theme_color_override("font_color", C_BTN_TEXT)
	btn.add_theme_font_size_override("font_size", 16)

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color                   = color
	ss.corner_radius_top_left     = int(BTN_SIZE * 0.25)
	ss.corner_radius_top_right    = int(BTN_SIZE * 0.25)
	ss.corner_radius_bottom_left  = int(BTN_SIZE * 0.25)
	ss.corner_radius_bottom_right = int(BTN_SIZE * 0.25)
	btn.add_theme_stylebox_override("normal", ss)

	var hover_ss: StyleBoxFlat = ss.duplicate()
	hover_ss.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover_ss)

	var pressed_ss: StyleBoxFlat = ss.duplicate()
	pressed_ss.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed_ss)

	if is_drop:
		btn.pressed.connect(func() -> void: _on_drop_pressed(slot_idx))
	else:
		btn.pressed.connect(func() -> void: _on_inv_pressed(slot_idx))

	return btn

# ─── Open / Close ─────────────────────────────────────────────────────────────
func open(basket: Node3D) -> void:
	_basket = basket
	is_open = true
	visible = true
	_layout_panel()
	_populate_slots()
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_root)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	_basket = null
	visible = false
	_clear_viewports()
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─── Layout panel ─────────────────────────────────────────────────────────────
func _layout_panel() -> void:
	var col_w:   int = PREVIEW_SIZE
	## Row height: preview + one button row (buttons are square, BTN_SIZE tall)
	var row_h:   int = PREVIEW_SIZE + int(BTN_SIZE) + 10
	var n_rows:  int = 4
	var n_cols:  int = 3
	var title_h: int = 32

	var panel_w: int = PANEL_PAD * 2 + n_cols * col_w + (n_cols - 1) * SLOT_GAP
	var panel_h: int = PANEL_PAD * 2 + title_h + n_rows * row_h + (n_rows - 1) * (BASKET_ROW_GAP + ROW_LABEL_H)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.size     = Vector2(panel_w, panel_h)
	_panel.position = (vp_size - _panel.size) * 0.5

	var title: Label = _panel.get_node("Title")
	title.position = Vector2(0, PANEL_PAD * 0.5)
	title.size = Vector2(panel_w, title_h)

	for child in _panel.get_children():
		if child.name.begins_with("RowLabel_"):
			child.queue_free()

	for row: int in 4:
		var row_y_base: int = PANEL_PAD + title_h + row * (row_h + BASKET_ROW_GAP + ROW_LABEL_H)

		var row_lbl: Label = Label.new()
		row_lbl.name = "RowLabel_%d" % row
		row_lbl.text = "Row %d" % (row + 1)
		row_lbl.add_theme_color_override("font_color", C_ROW_LABEL)
		row_lbl.add_theme_font_size_override("font_size", 10)
		row_lbl.position = Vector2(PANEL_PAD, row_y_base)
		row_lbl.size     = Vector2(panel_w - PANEL_PAD * 2, ROW_LABEL_H)
		_panel.add_child(row_lbl)

		for col: int in 3:
			var slot_idx: int = row * 3 + col
			var sx: float = PANEL_PAD + col * (col_w + SLOT_GAP)
			var sy: float = row_y_base + ROW_LABEL_H + 4
			_position_slot_visuals(slot_idx, sx, sy)

func _position_slot_visuals(slot_idx: int, sx: float, sy: float) -> void:
	var empty_lbl: Label = _panel.get_node_or_null("EmptyLabel_%d" % slot_idx)
	var badge: Label     = _panel.get_node_or_null("Badge_%d" % slot_idx)
	var tr: TextureRect  = _vp_rects[slot_idx] if slot_idx < _vp_rects.size() else null
	var drop: Button    = _drop_btns[slot_idx] if slot_idx < _drop_btns.size() else null
	var inv_b: Button    = _inv_btns[slot_idx]   if slot_idx < _inv_btns.size()   else null

	if tr != null:
		tr.position = Vector2(sx, sy)

	if tr != null:
		var tr_idx_in_parent: int = tr.get_index()
		if tr_idx_in_parent > 0:
			var slot_bg: Control = _panel.get_child(tr_idx_in_parent - 1)
			if slot_bg is Panel:
				slot_bg.position = Vector2(sx, sy)

	if empty_lbl != null:
		empty_lbl.position = Vector2(sx, sy)

	if badge != null:
		badge.position = Vector2(sx + 4, sy + 4)

	## Buttons sit centred below the slot preview.
	var btn_y: float = sy + PREVIEW_SIZE + 6.0

	if drop != null:
		drop.size = Vector2(BTN_SIZE, BTN_SIZE)
	if inv_b != null:
		inv_b.size = Vector2(BTN_SIZE, BTN_SIZE)

	## Positions: drop left-of-center, inv right-of-center (gap between them)
	var both_w: float  = BTN_SIZE * 2.0 + BTN_GAP
	var single_w: float = BTN_SIZE
	var center_x: float = sx + PREVIEW_SIZE * 0.5

	if drop != null:
		drop.position = Vector2(center_x - both_w * 0.5, btn_y)
	if inv_b != null:
		inv_b.position = Vector2(center_x - both_w * 0.5 + BTN_SIZE + BTN_GAP, btn_y)

	## Store center_x for drop-only repositioning when inv is hidden
	if drop != null:
		drop.set_meta("center_x", center_x)
		drop.set_meta("btn_y", btn_y)

# ─── Populate slots ────────────────────────────────────────────────────────────
func _populate_slots() -> void:
	if _basket == null:
		return
	_clear_viewports()
	for i: int in 12:
		_refresh_slot(i)

func _refresh_slot(slot_idx: int) -> void:
	if _basket == null:
		return
	var item = _basket.slots[slot_idx] if slot_idx < _basket.slots.size() else null
	_set_slot(slot_idx, item, 1 if item != null else 0)

func _set_slot(slot_idx: int, item, count: int) -> void:
	var empty_lbl: Label = _panel.get_node_or_null("EmptyLabel_%d" % slot_idx)
	var badge: Label     = _panel.get_node_or_null("Badge_%d" % slot_idx)
	var tr: TextureRect  = _vp_rects[slot_idx] if slot_idx < _vp_rects.size() else null
	var drop: Button    = _drop_btns[slot_idx] if slot_idx < _drop_btns.size() else null
	var inv_b: Button    = _inv_btns[slot_idx]   if slot_idx < _inv_btns.size()   else null

	var has_item: bool = (item != null and count > 0)

	if empty_lbl != null:
		empty_lbl.visible = not has_item
	if tr != null:
		tr.visible = has_item
	if drop != null:
		drop.visible = has_item

	## Inv button: only visible if item exists AND is pocket-sized
	var show_inv: bool = has_item and item != null and item.is_in_group("inventory_item")
	if inv_b != null:
		inv_b.visible = show_inv

	## Reposition drop button: center it alone when inv is hidden
	if drop != null and drop.has_meta("center_x"):
		var center_x: float = drop.get_meta("center_x")
		var btn_y: float    = drop.get_meta("btn_y")
		if show_inv:
			## Two buttons: drop left, inv right
			var both_w: float = BTN_SIZE * 2.0 + BTN_GAP
			drop.position = Vector2(center_x - both_w * 0.5, btn_y)
			if inv_b != null:
				inv_b.position = Vector2(center_x - both_w * 0.5 + BTN_SIZE + BTN_GAP, btn_y)
		else:
			## Single button: drop centred
			drop.position = Vector2(center_x - BTN_SIZE * 0.5, btn_y)

	if badge != null:
		## No stack badge for baskets (1 item per slot max)
		badge.visible = false

	if not has_item:
		_clear_viewport(slot_idx)
		return

	_populate_viewport(slot_idx, item)

func _populate_viewport(slot_idx: int, item: Node) -> void:
	if slot_idx >= _viewports.size():
		return
	var vp: SubViewport = _viewports[slot_idx]

	var to_free: Array = []
	for child in vp.get_children():
		if child is MeshInstance3D:
			to_free.append(child)
	for c in to_free:
		c.queue_free()

	var mesh_inst: MeshInstance3D = null
	if item.has_method("get_inventory_mesh"):
		var m: Mesh = item.get_inventory_mesh()
		if m != null:
			mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = m
	if mesh_inst == null:
		for child in item.get_children():
			if child is MeshInstance3D:
				mesh_inst = child.duplicate() as MeshInstance3D
				break
	if mesh_inst == null:
		return

	mesh_inst.rotation_degrees = Vector3(-20.0, 45.0, 0.0)
	mesh_inst.position = Vector3.ZERO
	vp.add_child(mesh_inst)

	if mesh_inst.mesh != null:
		var local_aabb: AABB   = mesh_inst.mesh.get_aabb()
		var basis: Basis       = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center

func _clear_viewport(slot_idx: int) -> void:
	if slot_idx >= _viewports.size():
		return
	var vp: SubViewport = _viewports[slot_idx]
	for child in vp.get_children():
		if child is MeshInstance3D:
			child.queue_free()

func _clear_viewports() -> void:
	for i: int in _viewports.size():
		_clear_viewport(i)

# ─── Button callbacks ─────────────────────────────────────────────────────────
func _on_drop_pressed(slot_idx: int) -> void:
	if _basket == null or interaction_system == null:
		return
	var item: RigidBody3D = _basket.remove_item(slot_idx)
	if item == null:
		return
	_refresh_slot(slot_idx)

func _on_inv_pressed(slot_idx: int) -> void:
	if _basket == null or inventory == null:
		return
	if inventory.is_full():
		_show_error("Inventory full")
		return
	var item: RigidBody3D = _basket.remove_item(slot_idx)
	if item == null:
		return
	## Match Shelf.retrieve_to_inventory's post-remove physics reset —
	## remove_item() above already re-enables physics/visibility/layers,
	## so this is just the inventory hand-off.
	inventory.add_item(item)
	_refresh_slot(slot_idx)

# ─── Error message ────────────────────────────────────────────────────────────
func _show_error(text: String) -> void:
	if inventory_hud != null and inventory_hud.has_method("show_error_message"):
		inventory_hud.show_error_message(text)

# ─── Backdrop click to close ──────────────────────────────────────────────────
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# ─── Block game input while open ─────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()