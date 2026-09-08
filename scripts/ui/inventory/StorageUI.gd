extends CanvasLayer
## Shared storage inspector for every shelving/container family.  World
## objects keep ownership of slots and transfers; this file only presents
## their existing contract, so physical-slot mappings remain authoritative.


const DEFAULTS := {
	"title": "Storage", "slot_count": 6, "grid_cols": 2, "grid_rows": 3,
	"display_order": [], "supports_stacking": false,
	"primary_button_tooltip": "Carry item", "primary_requires_empty_hands": false,
	"closes_on_action": true,
}

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
var _scroll_viewport: Control
var _scroll: ScrollContainer
var _grid: GridContainer
var _selection_name: Label
var _selection_detail: Label
var _selection_panel: PanelContainer
var _selection_eyebrow: Label
var _state_row: HBoxContainer
var _state_meter: ItemStateMeter
var _footer_hint: Label
var _carry: Button
var _inventory: Button
var _close: Button
var _cards: Array[Button] = []
var _viewports: Array[SubViewport] = []
var _signatures: Array[String] = []
var _shown_ids: Array[int] = []
var _selected_visual := -1
var _proximity: Node
var _controller_nav: ControllerUINavigation
var _refresh_elapsed := 0.0

func _ready() -> void:
	layer = 60
	_build()
	visible = false
	set_process(false)
	_controller_nav = ControllerUINavigation.new()
	_controller_nav.ui_root = self
	add_child(_controller_nav)
	_proximity = (load("res://scripts/ui/common/UIProximityClose.gd") as GDScript).new()
	_proximity.ui = self
	add_child(_proximity)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	BunkerUIComponents.apply_theme(_panel)
	BunkerUIComponents.shell(_panel)
	_root.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	_panel.add_child(BunkerUIComponents.inset(body, 16, 14, 16, 12))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	body.add_child(header)
	header.add_child(BunkerUIComponents.icon_well("storage", 44.0))
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
	BunkerUIComponents.divider(body)
	var capacity_panel := PanelContainer.new()
	capacity_panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("17232a"), BunkerPanelStyle.BLUE.darkened(0.32), 7, 1, 8))
	body.add_child(capacity_panel)
	var capacity_body := VBoxContainer.new()
	capacity_body.add_theme_constant_override("separation", 5)
	capacity_panel.add_child(capacity_body)
	var cap_row := HBoxContainer.new()
	capacity_body.add_child(cap_row)
	var cap_label := Label.new()
	cap_label.text = "STORAGE CAPACITY"
	cap_label.add_theme_font_size_override("font_size", 11)
	cap_label.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	cap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_row.add_child(cap_label)
	_capacity = Label.new()
	_capacity.add_theme_font_size_override("font_size", 14)
	_capacity.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	cap_row.add_child(_capacity)
	var contents_heading: Dictionary = BunkerUIComponents.section_header(body, "Contents")
	(contents_heading["meta"] as Label).text = "SELECT AN ITEM"
	_scroll_viewport = Control.new()
	_scroll_viewport.name = "StorageViewport"
	_scroll_viewport.custom_minimum_size.y = 144
	_scroll_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_viewport.clip_contents = true
	body.add_child(_scroll_viewport)
	_scroll = ScrollContainer.new()
	_scroll.name = "StorageScroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll_viewport.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	BunkerUIComponents.scroll_content(_scroll, _grid)
	BunkerUIComponents.divider(body)
	_selection_panel = PanelContainer.new()
	_selection_panel.add_theme_stylebox_override("panel", BunkerUIComponents.status_style(false))
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
	_state_meter = ItemStateMeter.new()
	_state_row.add_child(_state_meter)
	_state_row.hide()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	_carry = Button.new()
	_carry.text = "Carry item"
	_carry.custom_minimum_size.y = 36
	_carry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.icon_button(_carry, "move")
	_carry.pressed.connect(_take_for_carry)
	actions.add_child(_carry)
	_inventory = Button.new()
	_inventory.text = "Add to inventory"
	_inventory.custom_minimum_size.y = 36
	_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.icon_button(_inventory, "plus", true)
	_inventory.pressed.connect(_take_for_inventory)
	actions.add_child(_inventory)
	_footer_hint = Label.new()
	_footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BunkerPanelStyle.muted(_footer_hint, 12)
	body.add_child(_footer_hint)

	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	if _panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	var rows := ceili(float(int(_config.get("slot_count", 6))) \
		/ maxf(float(int(_config.get("grid_cols", 2))), 1.0))
	var desired := minf(760.0, 340.0 + float(rows) * 152.0)
	## In-world inspector rail: preserve the bunker view and keep the panel at
	## comfortable eye level rather than pinning it to a screen corner.
	UIPanelLayout.fit(_panel, viewport, Vector2(440.0, desired),
		Vector2(24.0, 24.0), 1.0, 0.5)

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
	UIPanelLifecycle.prepare_open(self)
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
	_layout.call_deferred()
	_scroll.set_deferred("scroll_vertical", 0)
	if InputMode.is_controller():
		_focus_initial_item.call_deferred()
	else:
		_close.call_deferred("grab_focus")
	UIFade.fade_in(_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not is_open:
		return
	is_open = false
	set_process(false)
	if _proximity != null:
		_proximity.unbind()
	_target = null
	_selected_visual = -1
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UIPanelLifecycle.dismiss(self, _panel)

func _process(delta: float) -> void:
	_footer_hint.text = "[A] Select · D-pad / R-stick: navigate · [B] Close" if InputMode.is_controller() else "Enter / Space: select · Esc / E: close"

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
	_configure_focus_neighbors()
	_refresh_selection()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and focus in _cards and focus.focus_mode == Control.FOCUS_NONE:
		_focus_nearest_occupied.call_deferred()

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
	return item != null and is_instance_valid(item) \
		and item.get_instance_id() == _shown_ids[_selected_visual]

func _refresh_selection() -> void:
	if not _selection_valid():
		_selection_panel.add_theme_stylebox_override(
			"panel", BunkerUIComponents.status_style(false))
		_selection_eyebrow.text = "NO ITEM SELECTED"
		_selection_name.text = "Select an item"
		_selection_detail.text = "Choose a stored object to see its name and actions."
		_state_row.hide()
		_carry.disabled = true
		_inventory.disabled = true
		return
	_selection_panel.add_theme_stylebox_override(
		"panel", BunkerUIComponents.status_style(true))
	_selection_eyebrow.text = "SELECTED ITEM"
	var shown := _slot(_selected_visual)
	var item: Node = shown[0]
	_selection_name.text = ItemPresentation.title(item)
	_selection_detail.text = ItemPresentation.detail(item, int(shown[1]))
	_refresh_item_state(item)
	var hands_blocked: bool = bool(_config.get("primary_requires_empty_hands", false)) \
		and interaction_system != null and "held_item" in interaction_system \
		and interaction_system.get("held_item") != null
	_carry.disabled = hands_blocked
	_inventory.disabled = inventory == null \
		or (inventory.has_method("is_full") and inventory.is_full())

func _refresh_item_state(item: Node) -> void:
	_state_meter.state = ItemPresentation.hud_state(item)
	_state_row.visible = String(_state_meter.state.get("kind", "none")) != "none"
	_state_meter.queue_redraw()

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


func _focus_initial_item() -> void:
	for i in int(_config.get("slot_count", 0)):
		if i < _cards.size() and _cards[i].focus_mode != Control.FOCUS_NONE:
			_select(i)
			_cards[i].grab_focus()
			return
	_close.grab_focus()


func _configure_focus_neighbors() -> void:
	## The slot grid can contain non-focusable empty cells. Explicit geometry
	## keeps horizontal D-pad motion in its row instead of letting a nearby
	## lower card win the generic spatial search.
	var count := mini(int(_config.get("slot_count", 0)), _cards.size())
	var columns := maxi(1, int(_config.get("grid_cols", 2)))
	var active: Array[int] = []
	for index in count:
		if _cards[index].visible and _cards[index].focus_mode != Control.FOCUS_NONE:
			active.append(index)
	for index in active:
		var card: Button = _cards[index]
		var row := floori(float(index) / float(columns))
		var column := index % columns
		var left := _find_focus_slot(active, row, column, columns, Vector2i.LEFT)
		var right := _find_focus_slot(active, row, column, columns, Vector2i.RIGHT)
		var up := _find_focus_slot(active, row, column, columns, Vector2i.UP)
		var down := _find_focus_slot(active, row, column, columns, Vector2i.DOWN)
		card.focus_neighbor_left = card.get_path_to(_cards[left]) if left >= 0 else NodePath(".")
		card.focus_neighbor_right = card.get_path_to(_cards[right]) if right >= 0 else (card.get_path_to(_scroll.get_v_scroll_bar()) if _scroll.get_v_scroll_bar().visible else NodePath("."))
		card.focus_neighbor_top = card.get_path_to(_cards[up]) if up >= 0 else card.get_path_to(_close)
		var lower_action: Button = _carry if column < ceili(float(columns) * 0.5) else _inventory
		card.focus_neighbor_bottom = card.get_path_to(_cards[down]) if down >= 0 \
			else card.get_path_to(lower_action)
	var first := active[0] if not active.is_empty() else -1
	var last_left := _last_focus_slot(active, columns, 0)
	var last_right := _last_focus_slot(active, columns, mini(1, columns - 1))
	_close.focus_neighbor_bottom = _close.get_path_to(_cards[first]) if first >= 0 else _close.get_path_to(_carry)
	_carry.focus_neighbor_left = NodePath(".")
	_carry.focus_neighbor_right = _carry.get_path_to(_inventory)
	_carry.focus_neighbor_top = _carry.get_path_to(_cards[last_left]) if last_left >= 0 else _carry.get_path_to(_close)
	_carry.focus_neighbor_bottom = NodePath(".")
	_inventory.focus_neighbor_left = _inventory.get_path_to(_carry)
	_inventory.focus_neighbor_right = NodePath(".")
	_inventory.focus_neighbor_top = _inventory.get_path_to(_cards[last_right]) if last_right >= 0 else _inventory.get_path_to(_close)
	_inventory.focus_neighbor_bottom = NodePath(".")


func _find_focus_slot(active: Array[int], row: int, column: int, columns: int,
		direction: Vector2i) -> int:
	var best := -1
	var best_distance := 1_000_000
	for candidate in active:
		var candidate_row := floori(float(candidate) / float(columns))
		var candidate_column := candidate % columns
		var matches := (direction.x < 0 and candidate_row == row and candidate_column < column) \
			or (direction.x > 0 and candidate_row == row and candidate_column > column) \
			or (direction.y < 0 and candidate_column == column and candidate_row < row) \
			or (direction.y > 0 and candidate_column == column and candidate_row > row)
		if not matches:
			continue
		var distance := absi(candidate_column - column) + absi(candidate_row - row)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _last_focus_slot(active: Array[int], columns: int, preferred_column: int) -> int:
	var best := -1
	for candidate in active:
		if candidate % columns == preferred_column and candidate > best:
			best = candidate
	return best if best >= 0 else (active[-1] if not active.is_empty() else -1)

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
