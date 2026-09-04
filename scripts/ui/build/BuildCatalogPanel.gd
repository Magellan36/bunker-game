class_name BuildCatalogPanel
extends PanelContainer

## Compact left-hand construction catalog. Selecting an item immediately
## enters the existing BuildModeController placement path; there is no second
## "Place selected item" confirmation step.

var hud: Node
var _category := "Structure"
var _subcategory := "All"
var _category_option: OptionButton
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _items: VBoxContainer
var _breadcrumb: Label
var _first_item: Button

func _ready() -> void:
	var nav := ControllerUINavigation.new()
	nav.ui_root = self
	add_child(nav)
	BunkerPanelStyle.panel(self)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(BunkerPanelStyle.margin(body, 16, 14, 16, 14))
	_build_header(body)
	_category_option = OptionButton.new()
	_category_option.custom_minimum_size.y = 44
	_category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.button(_category_option)
	for category in hud.CATEGORIES:
		_category_option.add_item(str(category))
	_category_option.select(maxi(0, hud.CATEGORIES.keys().find(_category)))
	_category_option.item_selected.connect(_category_changed)
	body.add_child(_category_option)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	body.add_child(_tabs)
	_breadcrumb = Label.new()
	BunkerPanelStyle.muted(_breadcrumb, 13)
	body.add_child(_breadcrumb)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("separation", 7)
	_scroll.add_child(_items)
	var instruction := Label.new()
	instruction.text = "Select an item to begin placement. Cost is charged when placed."
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BunkerPanelStyle.muted(instruction, 12)
	body.add_child(instruction)
	_rebuild_tabs()
	_rebuild_items()

func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	parent.add_child(header)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon("build")
	icon.self_modulate = BunkerPanelStyle.BLUE
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)
	var heading := Label.new()
	heading.text = "Build catalog"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.title(heading, 22)
	header.add_child(heading)
	var close := Button.new()
	close.custom_minimum_size = Vector2(42, 42)
	BunkerPanelStyle.icon_button(close, "close")
	close.tooltip_text = "Close catalog"
	close.pressed.connect(func(): hud.close_workspace_menu())
	header.add_child(close)

func open() -> void:
	show()
	_rebuild_items()
	_scroll.set_deferred("scroll_vertical", 0)
	if _first_item != null:
		_first_item.call_deferred("grab_focus")
	else:
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
		button.custom_minimum_size.y = 40
		BunkerPanelStyle.button(button)
		button.pressed.connect(_subcategory_changed.bind(str(group)))
		_tabs.add_child(button)

func _category_changed(index: int) -> void:
	_category = _category_option.get_item_text(index)
	_subcategory = "All"
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
	_first_item = null
	for child in _items.get_children():
		child.queue_free()
	_breadcrumb.text = _category if _subcategory == "All" else "%s  /  %s" % [_category, _subcategory]
	for item: Dictionary in _filtered():
		var row := _make_item_row(item)
		_items.add_child(row)
		if _first_item == null:
			_first_item = row

func _make_item_row(item: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 92)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	BunkerPanelStyle.button(button)
	button.pressed.connect(_choose.bind(int(item.tile_id)))
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	var inset := BunkerPanelStyle.margin(content, 8, 7, 10, 7)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	var preview_well := PanelContainer.new()
	preview_well.custom_minimum_size = Vector2(86, 76)
	preview_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_theme_stylebox_override("panel", BunkerPanelStyle.box(Color("343a39"), BunkerPanelStyle.BRASS.darkened(0.35), 5, 1))
	content.add_child(preview_well)
	var preview := TextureRect.new()
	preview.texture = hud.preview_texture(int(item.tile_id), false)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_child(BunkerPanelStyle.margin(preview, 5, 4, 5, 4))
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(copy)
	var name := Label.new()
	name.text = str(item.name)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BunkerPanelStyle.title(name, 17)
	copy.add_child(name)
	var price := Label.new()
	price.text = "$%s" % _money(int(item.price))
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_theme_font_size_override("font_size", 14)
	price.add_theme_color_override("font_color", BunkerPanelStyle.BRASS.lightened(0.32))
	copy.add_child(price)
	var arrow := TextureRect.new()
	arrow.texture = BunkerPanelStyle.icon("check")
	arrow.self_modulate = BunkerPanelStyle.BLUE
	arrow.custom_minimum_size = Vector2(24, 24)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(arrow)
	return button

func _choose(tile_id: int) -> void:
	hud.choose_build_item(tile_id)

func _money(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return raw + out
