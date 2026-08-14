extends CanvasLayer
## TrashBagInfoPanel.gd
## Ambient hover info panel for Trash Bags (new UI category, Aug 2026) —
## proximity-driven, non-modal, non-input-blocking. Distinct from both the
## single-line E/F prompt (text-only) and the fully modal StorageUI panels
## (explicit trigger + input capture): this one has no "open" state, just a
## per-tick proximity scan that toggles visibility and positions the panel
## next to whatever Trash Bag is nearest to the player.
##
## Created once by MainWorld (mirrors _setup_storage_ui()'s pattern) and
## injected with a player_ref. Scans on a short timer (a proximity check
## doesn't need 60Hz precision); positions every frame while a bag is shown.
##
## Shows, top to bottom:
##   1. The bag's own existing prompt line — get_prompt_text() (pickup
##      prompt) when on the ground/shelf, or get_display_name() when it's
##      the one already in the player's hands (a held item has no "nearby
##      pickup" prompt, so the name reads naturally there instead).
##   2. One line per disposed item: display_name plus a single most-
##      relevant data field when one exists. Full structured detail lives
##      in TrashBag.contents and is what later features consume
##      programmatically — this panel only needs to be legible at a glance.

const SCAN_RADIUS: float       = 3.0
const SCAN_INTERVAL_SEC: float = 0.15
const ANCHOR_OFFSET: Vector3   = Vector3(0.0, 0.4, 0.0)

const FONT_SIZE_TITLE: int = 14
const FONT_SIZE_ROW:    int = 12

const COLOR_BG:      Color = Color(0.08, 0.08, 0.10, 0.92)
const COLOR_BORDER:  Color = Color(0.45, 0.45, 0.50, 0.70)
const COLOR_TITLE:   Color = Color(0.92, 0.92, 0.95, 1.00)
const COLOR_ROW:     Color = Color(0.80, 0.80, 0.84, 0.95)
const COLOR_EMPTY:   Color = Color(0.55, 0.55, 0.60, 0.85)

var player_ref: Node3D = null   ## Injected by MainWorld — player position source

var _scan_timer: float = 0.0
var _bag: Node = null

var _panel: PanelContainer = null
var _top_label: Label = null
var _list_box: VBoxContainer = null

func _ready() -> void:
	layer   = 50   ## above the F/E prompt layer, below modal panels
	visible = false
	_build_panel()

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   ## never blocks E/F/click input
	_panel.add_theme_stylebox_override("panel", _make_stylebox())

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	_top_label = Label.new()
	_top_label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	_top_label.add_theme_color_override("font_color", COLOR_TITLE)
	vbox.add_child(_top_label)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 1)
	vbox.add_child(_list_box)

	add_child(_panel)

func _make_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color    = COLOR_BG
	sb.border_color = COLOR_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 6.0
	sb.content_margin_right  = 6.0
	sb.content_margin_top    = 4.0
	sb.content_margin_bottom = 4.0
	return sb

func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL_SEC:
		_scan_timer = 0.0
		_refresh_bag()
	if _bag == null or not is_instance_valid(_bag):
		_bag = null
		visible = false
		return
	_position_panel()

## Timer-driven scan for the nearest Trash Bag (held or on the ground/
## shelf) within SCAN_RADIUS of the player.
func _refresh_bag() -> void:
	if player_ref == null:
		return
	var player_pos: Vector3 = player_ref.global_position
	var best: Node = null
	var best_d: float = SCAN_RADIUS
	for bag: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(bag) or not (bag is TrashBag):
			continue
		var d: float = (bag as Node3D).global_position.distance_to(player_pos)
		if d < best_d:
			best_d = d
			best = bag
	if best == _bag:
		return
	_bag = best
	if _bag == null:
		visible = false
		return
	_rebuild_contents()
	visible = true

func _position_panel() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var world_pos: Vector3 = (_bag as Node3D).global_position + ANCHOR_OFFSET
	if camera.is_position_behind(world_pos):
		visible = false
		return
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	_panel.reset_size()
	_panel.position = screen_pos - _panel.size / 2.0
	visible = true

## Rebuilds the content rows for the newly-selected bag.
func _rebuild_contents() -> void:
	for c: Node in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()

	if _bag == null:
		return

	## Top line — the bag's own existing prompt text, or its display name
	## when it's the one the player is already holding (no pickup prompt
	## applies to a held item).
	if player_ref != null and player_ref.has_method("get_held_item") \
			and player_ref.get_held_item() == _bag:
		_top_label.text = _bag.get_display_name()
	else:
		_top_label.text = _bag.get_prompt_text()

	var contents: Array = _bag.contents
	if contents.is_empty():
		_list_box.add_child(_make_row("Empty", COLOR_EMPTY))
		return
	for rec: Dictionary in contents:
		var line: String = String(rec.get("display_name", "Unknown"))
		var rel: String = _relevant_field(rec.get("data", {}))
		if not rel.is_empty():
			line += "  —  %s" % rel
		_list_box.add_child(_make_row(line, COLOR_ROW))

func _make_row(text: String, color: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_ROW)
	lbl.add_theme_color_override("font_color", color)
	return lbl

## One short human field from a bag record's data dict — the most
## relevant stateful field (quality/charge/fill/etc.) if one is present,
## else the first scalar (bool/int/float) value. Names/types that are
## noisy to render at a glance (item_name, shelf_item_type, …) are never
## chosen.
const RELEVANT_FIELD_PRIORITY: Array[String] = [
	"quality", "charge", "current_fill_mL", "fuel_remaining",
	"bites_left", "durability", "fill_value",
]

func _relevant_field(data: Dictionary) -> String:
	for key: String in RELEVANT_FIELD_PRIORITY:
		if data.has(key):
			return "%s: %s" % [key, str(data[key])]
	for key: Variant in data:
		var v: Variant = data[key]
		if v is bool or v is int or v is float:
			return "%s: %s" % [key, str(v)]
	return ""