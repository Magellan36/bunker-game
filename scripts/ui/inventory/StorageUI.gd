extends CanvasLayer
## StorageUI.gd
## Generic storage-container overlay menu (Aug 2026 "Storage UI
## Unification" pass) — ONE shared UI for any storage object (Shelving,
## Basket, and any future type: lockers, freezers, larger shelving units,
## etc.), replacing the former separate ShelfUI.gd/BasketUI.gd (476/470
## lines, 17 of 18 functions identical).
##
## THE CONTRACT — any storage object opened with this UI must implement:
##   get_ui_config() -> Dictionary        (see _DEFAULT_CONFIG below for every key)
##   get_slot_display(slot_idx: int) -> Array     -> [item_or_null, count]
##   take_for_carry(slot_idx: int, isys: Node) -> bool
##       Primary button. Concrete behavior is TYPE-SPECIFIC — Shelving hands
##       the item to the player's hold point ("Carry"), Basket drops it on
##       the ground ("Drop"). The method name is the historical/approved
##       one; treat it as "this storage type's primary retrieval action,"
##       not literally "carry" — see each type's own get_ui_config()
##       primary_button_icon/_tooltip for what it actually does.
##   take_for_inventory(slot_idx: int, inv: Node) -> bool
##       Secondary "⊕" button — always means "pop into the player's
##       inventory pocket," identical meaning for every storage type.
## That's the whole contract. Grid shape, row labels, capacity, stacking,
## and the primary button's icon/label/color/hands-empty-requirement are
## ALL read from get_ui_config() at open() time — nothing type-specific is
## hardcoded in this file. Adding a new storage type needs ZERO changes
## here, just a world-object script implementing the contract above.

# ─── Dependencies (injected by MainWorld) ─────────────────────────────────────
var interaction_system: Node   = null
var inventory: Node            = null
var inventory_hud: Node        = null

# ─── State ────────────────────────────────────────────────────────────────────
var _target: Node3D    = null
var is_open: bool      = false
var _config: Dictionary = {}

## Every key get_ui_config() may provide, with a safe fallback — read via
## _cfg(key) so a storage object's config dict only needs to specify keys
## that differ from these defaults.
const _DEFAULT_CONFIG: Dictionary = {
	"title": "STORAGE CONTENTS",
	"slot_count": 6,
	"grid_cols": 2,
	"grid_rows": 3,
	"display_order": [],                 ## [] = identity (visual pos i -> data slot i)
	"row_labels": [],                    ## [] = auto "Row N" labels
	"supports_stacking": false,
	"primary_button_icon": "↑",
	"primary_button_tooltip": "Take",
	"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
	"primary_requires_empty_hands": false,
	"closes_on_action": true,
}

func _cfg(key: String):
	return _config.get(key, _DEFAULT_CONFIG.get(key))

# ─── Layout constants (unchanged from the old ShelfUI.gd/BasketUI.gd) ────────
const PREVIEW_SIZE:  int   = 96
const SLOT_GAP:      int   = 18
const BTN_SIZE:      float = 36.0
const BTN_GAP:       float = 8.0
const PANEL_PAD:     int   = 28
const PANEL_RADIUS:  float = 14.0
const ROW_GAP:        int   = 22
const ROW_LABEL_H:   int   = 18

const C_BG:          Color = Color(0.08, 0.08, 0.08, 0.92)
const C_SLOT_BG:     Color = Color(0.13, 0.13, 0.13, 1.00)
const C_SLOT_BORDER: Color = Color(0.28, 0.28, 0.28, 1.00)
const C_BTN_INV:     Color = Color(0.22, 0.33, 0.50, 1.00)
const C_BTN_TEXT:    Color = Color(0.90, 0.88, 0.84, 1.00)
const C_TITLE:       Color = Color(0.80, 0.78, 0.72, 1.00)
const C_EMPTY_TEXT:  Color = Color(0.35, 0.35, 0.35, 1.00)
const C_ROW_LABEL:   Color = Color(0.45, 0.43, 0.40, 1.00)
const C_BADGE_TEXT:  Color = Color(0.80, 1.00, 0.85, 1.00)

# ─── Nodes — a dynamic pool, sized to the LARGEST slot_count opened so far.
## Extras beyond the current config's slot_count are hidden, never freed, so
## reopening a same-or-smaller storage type never rebuilds anything. ────────
var _root: Control       = null
var _panel: Panel        = null
var _pool_size: int      = 0
var _viewports: Array    = []
var _vp_rects: Array     = []
var _slot_bgs: Array     = []
var _empty_labels: Array = []
var _badge_labels: Array = []
var _primary_btns: Array = []
var _inv_btns: Array     = []

func _ready() -> void:
	layer = 10
	_build_root()
	visible = false

func _build_root() -> void:
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
	ss.bg_color = C_BG
	ss.set_corner_radius_all(int(PANEL_RADIUS))
	ss.set_border_width_all(1)
	ss.border_color = Color(0.30, 0.30, 0.30, 0.80)
	_panel.add_theme_stylebox_override("panel", ss)
	_root.add_child(_panel)

	var title: Label = Label.new()
	title.name = "Title"
	title.add_theme_color_override("font_color", C_TITLE)
	title.add_theme_font_size_override("font_size", 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(title)

# ─── Pool management ──────────────────────────────────────────────────────────
func _ensure_pool_size(needed: int) -> void:
	while _pool_size < needed:
		_add_pool_slot()
		_pool_size += 1

func _add_pool_slot() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.transparent_bg = true
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
	slot_ss.bg_color = C_SLOT_BG
	slot_ss.set_corner_radius_all(6)
	slot_ss.set_border_width_all(1)
	slot_ss.border_color = C_SLOT_BORDER
	slot_bg.add_theme_stylebox_override("panel", slot_ss)
	slot_bg.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_panel.add_child(slot_bg)

	var tr: TextureRect = TextureRect.new()
	tr.texture = vp.get_texture()
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_panel.add_child(tr)

	var empty_lbl: Label = Label.new()
	empty_lbl.text = "—"
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_color_override("font_color", C_EMPTY_TEXT)
	empty_lbl.add_theme_font_size_override("font_size", 20)
	empty_lbl.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_panel.add_child(empty_lbl)

	var badge: Label = Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	badge.add_theme_color_override("font_color", C_BADGE_TEXT)
	badge.add_theme_font_size_override("font_size", 11)
	badge.size = Vector2(PREVIEW_SIZE - 4, 20)
	badge.visible = false
	_panel.add_child(badge)

	var slot_idx: int = _pool_size
	var primary_btn: Button = _make_icon_button(slot_idx, true)
	_panel.add_child(primary_btn)

	var inv_btn: Button = _make_icon_button(slot_idx, false)
	_panel.add_child(inv_btn)

	_viewports.append(vp)
	_vp_rects.append(tr)
	_slot_bgs.append(slot_bg)
	_empty_labels.append(empty_lbl)
	_badge_labels.append(badge)
	_primary_btns.append(primary_btn)
	_inv_btns.append(inv_btn)

## Icon/tooltip/color for the primary button are applied generically here
## and then OVERWRITTEN per the active config in _apply_primary_button_style()
## every time open() runs — a pool slot might have been built while a
## different storage type's config was active, so its style can't be baked
## in once at creation time the way the old separate files did.
func _make_icon_button(slot_idx: int, is_primary: bool) -> Button:
	var btn: Button = Button.new()
	btn.size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.add_theme_color_override("font_color", C_BTN_TEXT)
	btn.add_theme_font_size_override("font_size", 16)

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.set_corner_radius_all(int(BTN_SIZE * 0.25))
	btn.add_theme_stylebox_override("normal", ss)
	btn.add_theme_stylebox_override("hover", ss.duplicate())
	btn.add_theme_stylebox_override("pressed", ss.duplicate())

	if is_primary:
		btn.pressed.connect(func() -> void: _on_primary_pressed(slot_idx))
	else:
		btn.text = "⊕"
		btn.tooltip_text = "Add to inventory"
		var inv_ss: StyleBoxFlat = ss.duplicate()
		inv_ss.bg_color = C_BTN_INV
		btn.add_theme_stylebox_override("normal", inv_ss)
		var inv_hover: StyleBoxFlat = inv_ss.duplicate()
		inv_hover.bg_color = C_BTN_INV.lightened(0.2)
		btn.add_theme_stylebox_override("hover", inv_hover)
		var inv_pressed: StyleBoxFlat = inv_ss.duplicate()
		inv_pressed.bg_color = C_BTN_INV.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", inv_pressed)
		btn.pressed.connect(func() -> void: _on_inv_pressed(slot_idx))

	return btn

func _apply_primary_button_style() -> void:
	var icon: String = String(_cfg("primary_button_icon"))
	var tip: String  = String(_cfg("primary_button_tooltip"))
	var color: Color  = _cfg("primary_button_color")

	for btn: Button in _primary_btns:
		btn.text = icon
		btn.tooltip_text = tip
		var ss: StyleBoxFlat = StyleBoxFlat.new()
		ss.bg_color = color
		ss.set_corner_radius_all(int(BTN_SIZE * 0.25))
		btn.add_theme_stylebox_override("normal", ss)
		var hover: StyleBoxFlat = ss.duplicate()
		hover.bg_color = color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover)
		var pressed: StyleBoxFlat = ss.duplicate()
		pressed.bg_color = color.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", pressed)

# ─── Open / Close ─────────────────────────────────────────────────────────────
func open(target: Node3D) -> void:
	if target == null:
		return
	if not (target.has_method("get_ui_config") and target.has_method("get_slot_display")
			and target.has_method("take_for_carry") and target.has_method("take_for_inventory")):
		push_warning("StorageUI: target missing required contract method(s) — %s" % str(target))
		return

	_target = target
	_config = target.get_ui_config()
	is_open = true
	visible = true

	var title: Label = _panel.get_node("Title")
	title.text = String(_cfg("title"))

	_ensure_pool_size(int(_cfg("slot_count")))
	_apply_primary_button_style()
	_layout_panel()
	_populate_slots()

	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_root)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	_target = null
	visible = false
	_clear_all_viewports()
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─── Layout panel ─────────────────────────────────────────────────────────────
func _layout_panel() -> void:
	var cols: int = int(_cfg("grid_cols"))
	var rows: int = int(_cfg("grid_rows"))
	var col_w: int = PREVIEW_SIZE
	var row_h: int = PREVIEW_SIZE + int(BTN_SIZE) + 10
	var title_h: int = 32

	var panel_w: int = PANEL_PAD * 2 + cols * col_w + (cols - 1) * SLOT_GAP
	var panel_h: int = PANEL_PAD * 2 + title_h + rows * row_h + (rows - 1) * (ROW_GAP + ROW_LABEL_H)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.size     = Vector2(panel_w, panel_h)
	_panel.position = (vp_size - _panel.size) * 0.5

	var title: Label = _panel.get_node("Title")
	title.position = Vector2(0, PANEL_PAD * 0.5)
	title.size = Vector2(panel_w, title_h)

	for child in _panel.get_children():
		if child.name.begins_with("RowLabel_"):
			child.queue_free()

	var row_labels: Array = _cfg("row_labels")
	var slot_count: int = int(_cfg("slot_count"))

	## Hide every pool slot beyond this config's slot_count — _populate_slots()
	## (called right after this) sets correct visibility for every in-use
	## slot, so only the unused tail of the pool needs handling here.
	for i: int in _pool_size:
		if i >= slot_count:
			_vp_rects[i].visible     = false
			_slot_bgs[i].visible     = false
			_empty_labels[i].visible = false
			_primary_btns[i].visible = false
			_inv_btns[i].visible     = false
			_badge_labels[i].visible = false

	for row: int in rows:
		var row_y_base: int = PANEL_PAD + title_h + row * (row_h + ROW_GAP + ROW_LABEL_H)

		var label_text: String = row_labels[row] if row < row_labels.size() else "Row %d" % (row + 1)
		var row_lbl: Label = Label.new()
		row_lbl.name = "RowLabel_%d" % row
		row_lbl.text = label_text
		row_lbl.add_theme_color_override("font_color", C_ROW_LABEL)
		row_lbl.add_theme_font_size_override("font_size", 10)
		row_lbl.position = Vector2(PANEL_PAD, row_y_base)
		row_lbl.size     = Vector2(panel_w - PANEL_PAD * 2, ROW_LABEL_H)
		_panel.add_child(row_lbl)

		for col: int in cols:
			var visual_idx: int = row * cols + col
			if visual_idx >= slot_count:
				continue
			var sx: float = PANEL_PAD + col * (col_w + SLOT_GAP)
			var sy: float = row_y_base + ROW_LABEL_H + 4
			_position_slot_visuals(visual_idx, sx, sy)

func _data_slot_for(visual_idx: int) -> int:
	var display_order: Array = _cfg("display_order")
	if visual_idx < display_order.size():
		return int(display_order[visual_idx])
	return visual_idx

func _position_slot_visuals(visual_idx: int, sx: float, sy: float) -> void:
	var tr: TextureRect   = _vp_rects[visual_idx]
	var slot_bg: Panel    = _slot_bgs[visual_idx]
	var empty_lbl: Label  = _empty_labels[visual_idx]
	var badge: Label       = _badge_labels[visual_idx]
	var primary: Button    = _primary_btns[visual_idx]
	var inv_b: Button      = _inv_btns[visual_idx]

	slot_bg.position    = Vector2(sx, sy)
	tr.position          = Vector2(sx, sy)
	empty_lbl.position   = Vector2(sx, sy)
	badge.position        = Vector2(sx + 4, sy + 4)

	var btn_y: float = sy + PREVIEW_SIZE + 6.0
	primary.size = Vector2(BTN_SIZE, BTN_SIZE)
	inv_b.size    = Vector2(BTN_SIZE, BTN_SIZE)

	var both_w: float   = BTN_SIZE * 2.0 + BTN_GAP
	var center_x: float = sx + PREVIEW_SIZE * 0.5

	primary.position = Vector2(center_x - both_w * 0.5, btn_y)
	inv_b.position     = Vector2(center_x - both_w * 0.5 + BTN_SIZE + BTN_GAP, btn_y)

	primary.set_meta("center_x", center_x)
	primary.set_meta("btn_y", btn_y)

# ─── Populate slots ────────────────────────────────────────────────────────────
func _populate_slots() -> void:
	if _target == null:
		return
	_clear_all_viewports()
	var slot_count: int = int(_cfg("slot_count"))
	for i: int in slot_count:
		_refresh_slot(i)

func _refresh_slot(visual_idx: int) -> void:
	if _target == null:
		return
	var data_idx: int = _data_slot_for(visual_idx)
	var display: Array = _target.get_slot_display(data_idx)
	var item = display[0] if display.size() > 0 else null
	var count: int = int(display[1]) if display.size() > 1 else 0
	_set_slot(visual_idx, item, count)

func _set_slot(visual_idx: int, item, count: int) -> void:
	var empty_lbl: Label = _empty_labels[visual_idx]
	var badge: Label       = _badge_labels[visual_idx]
	var tr: TextureRect    = _vp_rects[visual_idx]
	var primary: Button    = _primary_btns[visual_idx]
	var inv_b: Button       = _inv_btns[visual_idx]

	var has_item: bool = (item != null and count > 0)

	empty_lbl.visible = not has_item
	tr.visible          = has_item
	primary.visible      = has_item

	var show_inv: bool = has_item and item != null and item.is_in_group("inventory_item")
	inv_b.visible = show_inv

	if primary.has_meta("center_x"):
		var center_x: float = primary.get_meta("center_x")
		var btn_y: float    = primary.get_meta("btn_y")
		if show_inv:
			var both_w: float = BTN_SIZE * 2.0 + BTN_GAP
			primary.position = Vector2(center_x - both_w * 0.5, btn_y)
			inv_b.position     = Vector2(center_x - both_w * 0.5 + BTN_SIZE + BTN_GAP, btn_y)
		else:
			primary.position = Vector2(center_x - BTN_SIZE * 0.5, btn_y)

	if bool(_cfg("supports_stacking")) and has_item and count > 1:
		badge.text    = "×%d" % count
		badge.visible = true
	else:
		badge.visible = false

	if not has_item:
		_clear_viewport(visual_idx)
		return

	_populate_viewport(visual_idx, item)

func _populate_viewport(visual_idx: int, item: Node) -> void:
	var vp: SubViewport = _viewports[visual_idx]

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
		var local_aabb: AABB    = mesh_inst.mesh.get_aabb()
		var basis: Basis        = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center

func _clear_viewport(visual_idx: int) -> void:
	var vp: SubViewport = _viewports[visual_idx]
	for child in vp.get_children():
		if child is MeshInstance3D:
			child.queue_free()

func _clear_all_viewports() -> void:
	for i: int in _pool_size:
		_clear_viewport(i)

# ─── Button callbacks ─────────────────────────────────────────────────────────
func _on_primary_pressed(visual_idx: int) -> void:
	if _target == null or interaction_system == null:
		return
	if bool(_cfg("primary_requires_empty_hands")) and interaction_system.held_item != null:
		_show_error("Hands full")
		return
	var data_idx: int = _data_slot_for(visual_idx)
	var ok: bool = _target.take_for_carry(data_idx, interaction_system)
	if not ok:
		return
	if bool(_cfg("closes_on_action")):
		close()
	else:
		_refresh_slot(visual_idx)

func _on_inv_pressed(visual_idx: int) -> void:
	if _target == null or inventory == null:
		return
	if inventory.is_full():
		_show_error("Inventory full")
		return
	var data_idx: int = _data_slot_for(visual_idx)
	var ok: bool = _target.take_for_inventory(data_idx, inventory)
	if not ok:
		return
	if bool(_cfg("closes_on_action")):
		close()
	else:
		_refresh_slot(visual_idx)

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
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") \
			or event.is_action_pressed("store_item"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
