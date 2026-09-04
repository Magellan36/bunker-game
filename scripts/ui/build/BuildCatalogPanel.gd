class_name BuildCatalogPanel
extends PanelContainer

var hud: Node
var _category := "Structure"
var _subcategory := "All"
var _selected_id := -1
var _category_option: OptionButton
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _items: VBoxContainer
var _details: Label
var _place: Button

func _ready() -> void:
	var nav := ControllerUINavigation.new()
	nav.ui_root = self
	add_child(nav)
	BunkerPanelStyle.panel(self)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(BunkerPanelStyle.margin(body))
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading := Label.new()
	heading.text = "BUILD CATALOG"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.title(heading, 23)
	header.add_child(heading)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(42, 42)
	BunkerPanelStyle.button(close)
	close.pressed.connect(func(): hud.close_workspace_menu())
	header.add_child(close)
	_category_option = OptionButton.new()
	_category_option.custom_minimum_size.y = 44
	for category in hud.CATEGORIES:
		_category_option.add_item(str(category))
	_category_option.item_selected.connect(_category_changed)
	body.add_child(_category_option)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	body.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("separation", 7)
	_scroll.add_child(_items)
	_details = Label.new()
	_details.text = "Select an item to review its price."
	BunkerPanelStyle.muted(_details, 14)
	body.add_child(_details)
	_place = Button.new()
	_place.text = "Place selected item"
	_place.disabled = true
	BunkerPanelStyle.button(_place, true)
	_place.pressed.connect(_place_selected)
	body.add_child(_place)
	_rebuild_tabs()
	_rebuild_items()

func open() -> void:
	show()
	_rebuild_items()
	_category_option.call_deferred("grab_focus")

func close() -> void:
	hud.close_workspace_menu()

func _groups(category: String) -> Dictionary:
	if category == "Furniture":
		return {"All": [], "Storage": [3, 34, 35, 32, 33, 36], "Tables": [27, 28, 29], "Living": [4, 31]}
	if category == "Power":
		return {"All": [], "Generation": [6, 7, 8], "Batteries": [13, 14, 15], "Control": [10, 11, 12, 16]}
	return {"All": []}

func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for group in _groups(_category):
		var button := Button.new()
		button.text = str(group)
		button.toggle_mode = true
		button.button_pressed = group == _subcategory
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BunkerPanelStyle.button(button)
		button.pressed.connect(_subcategory_changed.bind(str(group)))
		_tabs.add_child(button)

func _category_changed(index: int) -> void:
	_category = _category_option.get_item_text(index)
	_subcategory = "All"
	_selected_id = -1
	_rebuild_tabs()
	_rebuild_items()

func _subcategory_changed(group: String) -> void:
	_subcategory = group
	_rebuild_tabs()
	_rebuild_items()

func _filtered() -> Array:
	var source: Array = hud.CATEGORIES.get(_category, [])
	var ids: Array = _groups(_category).get(_subcategory, [])
	if ids.is_empty():
		return source
	return source.filter(func(item: Dictionary): return int(item.tile_id) in ids)

func _rebuild_items() -> void:
	if _items == null:
		return
	for child in _items.get_children():
		child.queue_free()
	for item: Dictionary in _filtered():
		var row := Button.new()
		row.text = "%s\n$%s" % [item.name, _money(int(item.price))]
		row.icon = hud.preview_texture(int(item.tile_id), false)
		row.add_theme_constant_override("icon_max_width", 78)
		row.expand_icon = true
		row.custom_minimum_size.y = 74
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.toggle_mode = true
		row.button_pressed = int(item.tile_id) == _selected_id
		BunkerPanelStyle.button(row)
		row.pressed.connect(_select.bind(item))
		_items.add_child(row)
	_place.disabled = _selected_id < 0

func _select(item: Dictionary) -> void:
	_selected_id = int(item.tile_id)
	_details.text = "%s   •   $%s   •   Select Place to begin construction." % [item.name, _money(int(item.price))]
	_rebuild_items()
	_place.disabled = false
	_place.grab_focus()

func _place_selected() -> void:
	if _selected_id >= 0:
		hud.choose_build_item(_selected_id)

func _money(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return raw + out
