extends CanvasLayer
## Shared storage inspector for every shelving/container family.  World
## objects keep ownership of slots and transfers; this file only presents
## their existing contract, so physical-slot mappings remain authoritative.

var interaction_system: Node
var inventory: Node
var inventory_hud: Node
var is_open := false

var _target: Node3D
var _config := {}
var _root: Control
var _panel: PanelContainer
var _title: Label
var _capacity: Label
var _capacity_bar: ProgressBar
var _scroll: ScrollContainer
var _grid: GridContainer
var _selection_name: Label
var _selection_detail: Label
var _selection_panel: PanelContainer
var _selection_eyebrow: Label
var _state_row: HBoxContainer
var _state_label: Label
var _state_bar: ProgressBar
var _carry: Button
var _inventory: Button
var _close: Button
var _cards: Array[Button] = []
var _viewports: Array[SubViewport] = []
var _signatures: Array[String] = []
var _shown_ids: Array[int] = []
var _selected_visual := -1
var _proximity: Node
var _refresh_elapsed := 0.0

const DEFAULTS := {
	"title": "Storage", "slot_count": 6, "grid_cols": 2, "grid_rows": 3,
	"display_order": [], "supports_stacking": false,
	"primary_button_tooltip": "Carry item", "primary_requires_empty_hands": false,
	"closes_on_action": true,
}

func _ready() -> void:
	layer = 60
	_build()
	visible = false
	set_process(false)
	var nav := ControllerUINavigation.new()
	nav.ui_root = self
	add_child(nav)
	_proximity = (load("res://scripts/ui/common/UIProximityClose.gd") as GDScript).new()
	_proximity.ui = self
	add_child(_proximity)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 600)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	BunkerPanelStyle.panel(_panel)
	_root.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_panel.add_child(BunkerPanelStyle.margin(body, 16, 14, 16, 14))
	var header := HBoxContainer.new()
	body.add_child(header)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon("storage")
	icon.self_modulate = BunkerPanelStyle.BLUE
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.text = "STORAGE"
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	titles.add_child(eyebrow)
	_title = Label.new()
	BunkerPanelStyle.title(_title, 23)
	titles.add_child(_title)
	_close = Button.new()
	_close.text = ""
	_close.custom_minimum_size = Vector2(42, 42)
	BunkerPanelStyle.icon_button(_close, "close")
	_close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close.tooltip_text = "Close storage"
	_close.pressed.connect(close)
	header.add_child(_close)
	var cap_row := HBoxContainer.new()
	body.add_child(cap_row)
	var cap_label := Label.new()
	cap_label.text = "CAPACITY"
	BunkerPanelStyle.muted(cap_label, 13)
	cap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_row.add_child(cap_label)
	_capacity = Label.new()
	_capacity.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	cap_row.add_child(_capacity)
	_capacity_bar = ProgressBar.new()
	_capacity_bar.show_percentage = false
	_capacity_bar.custom_minimum_size.y = 7
	_capacity_bar.add_theme_stylebox_override("background", BunkerPanelStyle.box(BunkerPanelStyle.SURFACE_ALT, Color.TRANSPARENT, 3, 0))
	_capacity_bar.add_theme_stylebox_override("fill", BunkerPanelStyle.box(BunkerPanelStyle.BLUE, Color.TRANSPARENT, 3, 0))
	body.add_child(_capacity_bar)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	var divider := HSeparator.new()
	body.add_child(divider)
	_selection_panel = PanelContainer.new()
	_selection_panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE_ALT, BunkerPanelStyle.BRASS.darkened(0.28), 7, 1))
	body.add_child(_selection_panel)
	var selected_body := VBoxContainer.new()
	selected_body.add_theme_constant_override("separation", 4)
	_selection_panel.add_child(BunkerPanelStyle.margin(selected_body, 12, 9, 12, 9))
	_selection_eyebrow = Label.new()
	_selection_eyebrow.text = "SELECTED ITEM"
	_selection_eyebrow.add_theme_font_size_override("font_size", 10)
	_selection_eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	selected_body.add_child(_selection_eyebrow)
	_selection_name = Label.new()
	BunkerPanelStyle.title(_selection_name, 19)
	selected_body.add_child(_selection_name)
	_selection_detail = Label.new()
	BunkerPanelStyle.muted(_selection_detail, 14)
	_selection_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_body.add_child(_selection_detail)
	_state_row = HBoxContainer.new()
	_state_row.add_theme_constant_override("separation", 9)
	selected_body.add_child(_state_row)
	_state_label = Label.new()
	_state_label.custom_minimum_size.x = 72
	BunkerPanelStyle.muted(_state_label, 11)
	_state_row.add_child(_state_label)
	_state_bar = ProgressBar.new()
	_state_bar.show_percentage = false
	_state_bar.max_value = 100.0
	_state_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_bar.custom_minimum_size.y = 7
	_state_bar.add_theme_stylebox_override("background", BunkerPanelStyle.box(BunkerPanelStyle.BG, Color.TRANSPARENT, 3, 0))
	_state_bar.add_theme_stylebox_override("fill", BunkerPanelStyle.box(BunkerPanelStyle.BLUE, Color.TRANSPARENT, 3, 0))
	_state_row.add_child(_state_bar)
	_state_row.hide()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	_carry = Button.new()
	_carry.text = "Carry item"
	_carry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.icon_button(_carry, "move")
	_carry.pressed.connect(_take_for_carry)
	actions.add_child(_carry)
	_inventory = Button.new()
	_inventory.text = "Add to inventory"
	_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.icon_button(_inventory, "plus", true)
	_inventory.pressed.connect(_take_for_inventory)
	actions.add_child(_inventory)
	var hint := Label.new()
	hint.text = "A  Carry   •   Y  Inventory   •   B / Esc  Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BunkerPanelStyle.muted(hint, 12)
	body.add_child(hint)
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	if _panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	var width := minf(440.0, viewport.x - 48.0)
	var rows := ceili(float(int(_config.get("slot_count", 6))) / maxf(float(int(_config.get("grid_cols", 2))), 1.0))
	var desired := minf(760.0, 350.0 + float(rows) * 122.0)
	var height := minf(desired, viewport.y - 48.0)
	## In-world inspector rail: preserve the bunker view and keep the panel at
	## comfortable eye level rather than pinning it to a screen corner.
	_panel.position = Vector2(viewport.x - width - 24.0, (viewport.y - height) * 0.5)
	_panel.size = Vector2(width, height)

func _ensure_pool(needed: int) -> void:
	while _cards.size() < needed:
		var index := _cards.size()
		var viewport := ItemPreviewKit.build_viewport(_root, 192, 1.28)
		PreviewPresentation.configure(viewport)
		_viewports.append(viewport)
		_signatures.append("")
		_shown_ids.append(0)
		var card := BunkerItemCard.new()
		card.pressed.connect(_select.bind(index))
		card.focus_entered.connect(_select.bind(index))
		_grid.add_child(card)
		_cards.append(card)

func open(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	for required in [&"get_ui_config", &"get_slot_display", &"take_for_carry", &"take_for_inventory"]:
		if not target.has_method(required):
			push_warning("StorageUI: target is missing %s" % required)
			return
	_target = target
	_config = DEFAULTS.duplicate(true)
	_config.merge(target.get_ui_config(), true)
	var slots := maxi(1, int(_config["slot_count"]))
	_ensure_pool(slots)
	_grid.columns = maxi(1, int(_config["grid_cols"]))
	_title.text = str(_config["title"]).replace("_", " ").capitalize()
	var primary_word := str(_config.get("primary_button_tooltip", "Carry"))
	_carry.text = primary_word if "item" in primary_word.to_lower() else primary_word + " item"
	_selected_visual = -1
	visible = true
	is_open = true
	set_process(true)
	if _proximity != null:
		_proximity.bind(target)
	_refresh(true)
	_layout()
	_scroll.scroll_vertical = 0
	_close.call_deferred("grab_focus")
	UIFade.fade_in(_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	visible = false
	is_open = false
	set_process(false)
	if _proximity != null:
		_proximity.unbind()
	_target = null
	_selected_visual = -1
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.1:
		_refresh_elapsed = 0.0
		_refresh(false)

func _data_index(visual: int) -> int:
	var order: Array = _config.get("display_order", [])
	return int(order[visual]) if visual >= 0 and visual < order.size() else visual

func _slot(visual: int) -> Array:
	if _target == null or not is_instance_valid(_target):
		return [null, 0]
	var value: Array = _target.get_slot_display(_data_index(visual))
	return value if value.size() >= 2 else [null, 0]

func _refresh(force: bool) -> void:
	if _target == null or not is_instance_valid(_target):
		close()
		return
	var slots := int(_config["slot_count"])
	var occupied := 0
	for i in _cards.size():
		var card: Button = _cards[i]
		card.visible = i < slots
		if i >= slots:
			continue
		var shown := _slot(i)
		var item: Node = shown[0]
		var count := int(shown[1])
		if item != null and is_instance_valid(item):
			occupied += 1
		var sig := ItemPresentation.signature(item, count)
		if force or sig != _signatures[i]:
			var new_id := item.get_instance_id() if item != null and is_instance_valid(item) else 0
			if i == _selected_visual and _shown_ids[i] != 0 and new_id != _shown_ids[i]:
				_selected_visual = -1
			_signatures[i] = sig
			_shown_ids[i] = new_id
			if item != null and is_instance_valid(item):
				PreviewPresentation.set_item(_viewports[i], item)
				card.display(ItemPresentation.title(item), _viewports[i].get_texture(), count)
				card.focus_mode = Control.FOCUS_ALL
			else:
				ItemPreviewKit.clear(_viewports[i])
				card.display("Empty", null, 0)
				card.focus_mode = Control.FOCUS_NONE
		if i == _selected_visual:
			card.button_pressed = true
	_capacity.text = "%d / %d" % [occupied, slots]
	_capacity_bar.max_value = slots
	_capacity_bar.value = occupied
	_refresh_selection()

func _select(index: int) -> void:
	_selected_visual = index
	for i in _cards.size():
		_cards[i].button_pressed = i == index
	_refresh_selection()

func _selection_valid() -> bool:
	if _selected_visual < 0:
		return false
	var shown := _slot(_selected_visual)
	var item: Node = shown[0]
	return item != null and is_instance_valid(item) and item.get_instance_id() == _shown_ids[_selected_visual]

func _refresh_selection() -> void:
	if not _selection_valid():
		_selection_name.text = "Select an item"
		_selection_detail.text = "Choose a stored object to see its name and actions."
		_state_row.hide()
		_carry.disabled = true
		_inventory.disabled = true
		return
	var shown := _slot(_selected_visual)
	var item: Node = shown[0]
	_selection_name.text = ItemPresentation.title(item)
	_selection_detail.text = ItemPresentation.detail(item, int(shown[1]))
	_refresh_item_state(item)
	var hands_blocked: bool = bool(_config.get("primary_requires_empty_hands", false)) \
		and interaction_system != null and "held_item" in interaction_system \
		and interaction_system.get("held_item") != null
	_carry.disabled = hands_blocked
	_inventory.disabled = inventory == null or (inventory.has_method("is_full") and inventory.is_full())

func _refresh_item_state(item: Node) -> void:
	_state_row.hide()
	if item == null or not is_instance_valid(item):
		return
	if item.has_method("get_bottle_badge_info"):
		var info: Dictionary = item.call("get_bottle_badge_info")
		var quality := clampf(float(info.get("quality", 0.0)), 0.0, 100.0)
		_state_label.text = "QUALITY"
		_state_bar.value = quality
		var color := BunkerPanelStyle.GREEN if quality >= 70.0 else (BunkerPanelStyle.BRASS.lightened(0.25) if quality >= 35.0 else BunkerPanelStyle.RED)
		_state_bar.add_theme_stylebox_override("fill", BunkerPanelStyle.box(color, Color.TRANSPARENT, 3, 0))
		_state_row.show()
	elif "_charges" in item and "_max_charges" in item and int(item.get("_max_charges")) > 0:
		_state_label.text = "REMAINING"
		_state_bar.value = 100.0 * float(item.get("_charges")) / float(item.get("_max_charges"))
		_state_bar.add_theme_stylebox_override("fill", BunkerPanelStyle.box(BunkerPanelStyle.BLUE, Color.TRANSPARENT, 3, 0))
		_state_row.show()
	elif "_fuel_remaining" in item:
		_state_label.text = "FUEL"
		_state_bar.value = clampf(float(item.get("_fuel_remaining")), 0.0, 100.0)
		_state_bar.add_theme_stylebox_override("fill", BunkerPanelStyle.box(BunkerPanelStyle.BRASS.lightened(0.28), Color.TRANSPARENT, 3, 0))
		_state_row.show()
	elif "_battery" in item:
		_state_label.text = "BATTERY"
		_state_bar.value = clampf(float(item.get("_battery")), 0.0, 100.0)
		_state_bar.add_theme_stylebox_override("fill", BunkerPanelStyle.box(BunkerPanelStyle.BLUE, Color.TRANSPARENT, 3, 0))
		_state_row.show()

func _take_for_carry() -> void:
	if not _selection_valid() or _carry.disabled:
		return
	if _target.take_for_carry(_data_index(_selected_visual), interaction_system):
		if bool(_config.get("closes_on_action", true)):
			close()
		else:
			_refresh(true)

func _take_for_inventory() -> void:
	if not _selection_valid() or _inventory.disabled:
		return
	if _target.take_for_inventory(_data_index(_selected_visual), inventory):
		## Deliberately remain open: players can move several items per session.
		_refresh(true)
		_focus_nearest_occupied()
		if inventory_hud != null and inventory_hud.has_method("refresh_previews"):
			inventory_hud.refresh_previews()

func _focus_nearest_occupied() -> void:
	for offset in range(_cards.size()):
		var i := (_selected_visual + offset) % _cards.size()
		if i < int(_config["slot_count"]) and _cards[i].focus_mode != Control.FOCUS_NONE:
			_select(i)
			_cards[i].grab_focus()
			return
	_selected_visual = -1
	_close.grab_focus()

func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventJoypadButton) or not event.pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus in _cards:
		return
	if event.button_index == JOY_BUTTON_A:
		_take_for_carry()
		get_viewport().set_input_as_handled()
	elif event.button_index == JOY_BUTTON_Y:
		_take_for_inventory()
		get_viewport().set_input_as_handled()
