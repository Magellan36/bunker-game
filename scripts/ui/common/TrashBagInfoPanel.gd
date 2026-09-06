extends CanvasLayer
## Compact, proximity-driven context card for a TrashBag and its preserved
## item records. It is informational only: normal world prompts continue to
## own pickup/use input, so this surface can never block movement or actions.

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")

const SCAN_RADIUS: float = 3.0
const SCAN_INTERVAL_SEC: float = 0.15
const ANCHOR_OFFSET: Vector3 = Vector3(0.0, 0.52, 0.0)
const PANEL_WIDTH: float = 330.0
const SCREEN_EDGE: float = 14.0
const WORLD_GAP: float = 14.0
const MAX_VISIBLE_ROWS: int = 4

var player_ref: Node3D = null

var _scan_timer: float = 0.0
var _bag: Node = null
var _contents_fingerprint: int = 0
var _was_held: bool = false

var _panel: PanelContainer = null
var _title: Label = null
var _context: Label = null
var _count_label: Label = null
var _list_box: VBoxContainer = null
var _overflow_label: Label = null


func _ready() -> void:
	layer = 50
	visible = false
	_build_panel()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "TrashItemContextPanel"
	_panel.custom_minimum_size.x = PANEL_WIDTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	C.apply_theme(_panel)
	C.shell(_panel, 9)
	add_child(_panel)

	var body: VBoxContainer = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 7)
	_panel.add_child(C.inset(body, 11, 10, 11, 9))

	var header: HBoxContainer = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 9)
	body.add_child(header)
	header.add_child(C.icon_well("trash", 38.0, S.BLUE))

	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_stack.add_theme_constant_override("separation", 0)
	header.add_child(title_stack)
	_context = _label("NEARBY • HEAVY ITEM", 9, S.BLUE)
	title_stack.add_child(_context)
	_title = _label("Trash bag", 17, S.IVORY)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_stack.add_child(_title)

	var count_panel: PanelContainer = PanelContainer.new()
	count_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_panel.custom_minimum_size = Vector2(72.0, 30.0)
	count_panel.add_theme_stylebox_override("panel", C.panel_box(
		Color("172a33"), S.BLUE.darkened(0.28), 14, 1, 7))
	header.add_child(count_panel)
	_count_label = _label("0 ITEMS", 10, S.BLUE.lightened(0.12))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_panel.add_child(_count_label)

	C.divider(body)
	_list_box = VBoxContainer.new()
	_list_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_box.add_theme_constant_override("separation", 5)
	body.add_child(_list_box)

	_overflow_label = _label("", 10, S.MUTED)
	_overflow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overflow_label.visible = false
	body.add_child(_overflow_label)


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


func _refresh_bag() -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		visible = false
		return
	var player_position: Vector3 = player_ref.global_position
	var nearest: Node = null
	var nearest_distance: float = SCAN_RADIUS
	for candidate: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(candidate) or not (candidate is TrashBag):
			continue
		var distance: float = (candidate as Node3D).global_position.distance_to(player_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate

	var held: bool = nearest != null and _player_holds(nearest)
	var fingerprint: int = _bag_fingerprint(nearest)
	var changed_bag: bool = nearest != _bag
	var changed_contents: bool = fingerprint != _contents_fingerprint
	var changed_context: bool = held != _was_held
	_bag = nearest
	_contents_fingerprint = fingerprint
	_was_held = held
	if _bag == null:
		visible = false
		return
	if changed_bag or changed_contents or changed_context:
		_rebuild_contents()
		if changed_bag:
			UIFade.fade_in(_panel, 0.12)
	visible = true


func _position_panel() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _bag == null or not (_bag is Node3D):
		visible = false
		return
	var world_position: Vector3 = (_bag as Node3D).global_position + ANCHOR_OFFSET
	if camera.is_position_behind(world_position):
		visible = false
		return
	var screen_position: Vector2 = camera.unproject_position(world_position)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.reset_size()
	var panel_size: Vector2 = _panel.size
	var desired: Vector2 = Vector2(
		screen_position.x - panel_size.x * 0.5,
		screen_position.y - panel_size.y - WORLD_GAP
	)
	desired.x = clampf(desired.x, SCREEN_EDGE, maxf(SCREEN_EDGE, viewport_size.x - panel_size.x - SCREEN_EDGE))
	desired.y = clampf(desired.y, SCREEN_EDGE, maxf(SCREEN_EDGE, viewport_size.y - panel_size.y - SCREEN_EDGE))
	_panel.position = desired
	visible = true


func _rebuild_contents() -> void:
	for child: Node in _list_box.get_children():
		child.queue_free()
	if _bag == null:
		return

	var contents: Array = _bag.get("contents") as Array
	var display_name: String = "Trash bag"
	if _bag.has_method("get_display_name"):
		display_name = String(_bag.call("get_display_name"))
		var count_suffix: int = display_name.find(" (")
		if count_suffix >= 0:
			display_name = display_name.left(count_suffix)
	_title.text = display_name
	_context.text = "HELD • HEAVY ITEM" if _was_held else "NEARBY • HEAVY ITEM"
	_count_label.text = "%d %s" % [contents.size(), "ITEM" if contents.size() == 1 else "ITEMS"]

	if contents.is_empty():
		_list_box.add_child(_empty_row())
		_overflow_label.visible = false
		return

	var shown: int = mini(contents.size(), MAX_VISIBLE_ROWS)
	for index: int in range(shown):
		var record: Dictionary = contents[index] as Dictionary
		_list_box.add_child(_item_row(record))
	var hidden: int = contents.size() - shown
	_overflow_label.text = "+ %d more item%s" % [hidden, "" if hidden == 1 else "s"]
	_overflow_label.visible = hidden > 0


func _empty_row() -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.y = 48.0
	card.add_theme_stylebox_override("panel", C.panel_box(
		Color("171d1c"), S.BRASS.darkened(0.46), 7, 1, 8))
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var marker: Control = Control.new()
	marker.custom_minimum_size = Vector2(28.0, 28.0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(_draw_empty_marker.bind(marker))
	row.add_child(marker)
	var label: Label = _label("Empty — ready to be reused", 12, S.MUTED.darkened(0.08))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return card


func _draw_empty_marker(marker: Control) -> void:
	var center: Vector2 = marker.size * 0.5
	for segment: int in range(10):
		var start_angle: float = TAU * float(segment) / 10.0
		var end_angle: float = start_angle + TAU / 20.0
		marker.draw_arc(center, 9.0, start_angle, end_angle, 4,
			S.BRASS.lightened(0.08), 1.5, true)


func _item_row(record: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.y = 54.0
	card.add_theme_stylebox_override("panel", C.panel_box(
		Color("1a211f"), S.BRASS.darkened(0.42), 7, 1, 7))
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	card.add_child(C.inset(row, 8, 6, 9, 6))

	var icon: TextureRect = TextureRect.new()
	icon.texture = S.icon(_record_icon(record))
	icon.self_modulate = S.BLUE.lightened(0.05)
	icon.custom_minimum_size = Vector2(27.0, 27.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	var item_name: Label = _label(String(record.get("display_name", "Unknown item")), 13, S.IVORY)
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(item_name)
	var detail_text: String = _item_detail(record.get("data", {}) as Dictionary)
	var detail: Label = _label(detail_text if not detail_text.is_empty() else "Discarded item", 10, S.MUTED)
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(detail)
	return card


func _record_icon(record: Dictionary) -> String:
	var item_type: String = String(record.get("item_type", "")).to_lower()
	var data: Dictionary = record.get("data", {}) as Dictionary
	var material: String = String(data.get("material", "")).to_lower()
	if "water" in item_type:
		return "water"
	if "food" in item_type or "dish" in item_type or material == "organic":
		return "food"
	if "fuel" in item_type:
		return "fuel"
	if "filter" in item_type:
		return "condition"
	if "bandage" in item_type:
		return "bandage"
	if "battery" in item_type or "flashlight" in item_type:
		return "battery"
	return "container"


func _item_detail(data: Dictionary) -> String:
	var details: Array[String] = []
	if data.has("current_fill_mL"):
		details.append("%d mL" % int(round(float(data["current_fill_mL"]))))
	if data.has("stored_water_quality"):
		details.append("%d%% quality" % int(round(float(data["stored_water_quality"]))))
	elif data.has("filter_quality"):
		details.append("%d%% quality" % int(round(float(data["filter_quality"]))))
	elif data.has("_fuel_remaining"):
		details.append("%d%% fuel" % int(round(float(data["_fuel_remaining"]))))
	elif data.has("_battery"):
		details.append("%d%% charge" % int(round(float(data["_battery"]))))
	elif data.has("_charges_left"):
		var remaining: int = int(data["_charges_left"])
		var maximum: int = int(data.get("_max_charges", remaining))
		details.append("%d / %d uses" % [remaining, maximum])
	elif data.has("_charges"):
		var charges: int = int(data["_charges"])
		var max_charges: int = int(data.get("_max_charges", charges))
		details.append("%d / %d uses" % [charges, max_charges])
	elif data.has("_bites_left"):
		var servings: int = int(data["_bites_left"])
		details.append("%d serving%s left" % [servings, "" if servings == 1 else "s"])
	elif data.has("fill_value"):
		details.append("%d%% full" % int(round(float(data["fill_value"]))))

	if details.size() < 2 and data.has("material"):
		var material: String = String(data["material"]).capitalize()
		if not material.is_empty():
			details.append(material)
	return "  •  ".join(details)


func _player_holds(candidate: Node) -> bool:
	return player_ref != null and player_ref.has_method("get_held_item") \
		and player_ref.call("get_held_item") == candidate


func _bag_fingerprint(candidate: Node) -> int:
	if candidate == null or not is_instance_valid(candidate) or not ("contents" in candidate):
		return 0
	return hash(candidate.get("contents"))


func _label(value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
