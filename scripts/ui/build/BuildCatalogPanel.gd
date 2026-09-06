class_name BuildCatalogPanel
extends PanelContainer

## Purpose-built construction catalog. This is deliberately not a device
## inspector or a reskinned legacy list: categories are immediate, previews
## are dominant, and placement state remains visible while the player works.

const CATEGORY_ICONS := {
	"Structure": "build",
	"Furniture": "storage",
	"Lighting": "power",
	"Power": "battery",
	"Water": "water",
	"Farming": "plant",
	"Cooking": "cooking",
}

var hud: Node

var _category: String = "Structure"
var _subcategory: String = "All"
var _category_grid: GridContainer
var _subcategory_row: HBoxContainer
var _subcategory_divider: HSeparator
var _scroll_viewport: Control
var _scroll: ScrollContainer
var _items: GridContainer
var _section_title: Label
var _section_meta: Label
var _cash_label: Label
var _mode_card: PanelContainer
var _mode_icon: TextureRect
var _mode_eyebrow: Label
var _mode_title: Label
var _mode_meta: Label
var _first_item: BuildCatalogCard
var _selected_tile_id: int = -1
var _selected_name: String = ""
var _selected_price: int = 0
var _last_cash: int = -1
var _category_buttons: Dictionary = {}
var _subcategory_buttons: Dictionary = {}
var _item_cards: Dictionary = {}


func _ready() -> void:
	BunkerUIComponents.apply_theme(self)
	BunkerUIComponents.shell(self)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var body := VBoxContainer.new()
	body.name = "Content"
	body.add_theme_constant_override("separation", 9)
	add_child(BunkerUIComponents.inset(body, 18, 16, 18, 14))
	BunkerUIComponents.header(body, "CONSTRUCTION", "Build catalog", "build",
		func() -> void: hud.close_workspace_menu())
	BunkerUIComponents.divider(body)
	_build_mode_card(body)
	_build_categories(body)
	_build_items(body)
	_build_footer(body)
	_rebuild_category_buttons()
	_rebuild_subcategories()
	_rebuild_items()
	_update_mode_card()


func _build_mode_card(parent: VBoxContainer) -> void:
	_mode_card = PanelContainer.new()
	_mode_card.name = "PlacementState"
	_mode_card.add_theme_stylebox_override("panel", BunkerUIComponents.status_style(false))
	parent.add_child(_mode_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_mode_card.add_child(row)
	_mode_icon = TextureRect.new()
	_mode_icon.texture = BunkerPanelStyle.icon("plus")
	_mode_icon.self_modulate = BunkerPanelStyle.BLUE
	_mode_icon.custom_minimum_size = Vector2(28, 28)
	_mode_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mode_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mode_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_mode_icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	_mode_eyebrow = Label.new()
	_mode_eyebrow.add_theme_font_size_override("font_size", 11)
	_mode_eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	copy.add_child(_mode_eyebrow)
	_mode_title = Label.new()
	_mode_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mode_title.add_theme_font_size_override("font_size", 16)
	_mode_title.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.add_child(_mode_title)
	_mode_meta = Label.new()
	_mode_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_meta.add_theme_font_size_override("font_size", 12)
	_mode_meta.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	row.add_child(_mode_meta)


func _build_categories(parent: VBoxContainer) -> void:
	var heading: Dictionary = BunkerUIComponents.section_header(parent, "Build category")
	_cash_label = heading["meta"] as Label
	_category_grid = GridContainer.new()
	_category_grid.name = "Categories"
	_category_grid.columns = 4
	_category_grid.add_theme_constant_override("h_separation", 6)
	_category_grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(_category_grid)
	_subcategory_divider = BunkerUIComponents.divider(parent)
	_subcategory_row = HBoxContainer.new()
	_subcategory_row.name = "Subcategories"
	_subcategory_row.add_theme_constant_override("separation", 6)
	parent.add_child(_subcategory_row)


func _build_items(parent: VBoxContainer) -> void:
	var heading: Dictionary = BunkerUIComponents.section_header(parent, "Available objects")
	_section_title = heading["title"] as Label
	_section_meta = heading["meta"] as Label
	## A plain Control deliberately breaks minimum-size propagation from the
	## tall object grid. Without this boundary, VBoxContainer expands the
	## entire rail to the grid's full height instead of assigning a viewport.
	_scroll_viewport = Control.new()
	_scroll_viewport.name = "ObjectViewport"
	_scroll_viewport.custom_minimum_size.y = 176
	_scroll_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_viewport.clip_contents = true
	parent.add_child(_scroll_viewport)
	_scroll = ScrollContainer.new()
	_scroll.name = "ObjectScroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll_viewport.add_child(_scroll)
	var focus_inset := MarginContainer.new()
	focus_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_inset.add_theme_constant_override("margin_left", 3)
	focus_inset.add_theme_constant_override("margin_top", 3)
	focus_inset.add_theme_constant_override("margin_right", 9)
	focus_inset.add_theme_constant_override("margin_bottom", 3)
	_scroll.add_child(focus_inset)
	_items = GridContainer.new()
	_items.name = "Objects"
	_items.columns = 2
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("h_separation", 8)
	_items.add_theme_constant_override("v_separation", 8)
	focus_inset.add_child(_items)


func _build_footer(parent: VBoxContainer) -> void:
	BunkerUIComponents.divider(parent)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	parent.add_child(footer)
	var charge_icon := TextureRect.new()
	charge_icon.texture = BunkerPanelStyle.icon("check")
	charge_icon.self_modulate = BunkerPanelStyle.BRASS.lightened(0.3)
	charge_icon.custom_minimum_size = Vector2(18, 18)
	charge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	charge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	charge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(charge_icon)
	var instruction := Label.new()
	instruction.text = "Placement is charged only when the object is built"
	instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_font_size_override("font_size", 12)
	instruction.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	footer.add_child(instruction)


func _rebuild_category_buttons() -> void:
	_category_buttons.clear()
	for child: Node in _category_grid.get_children():
		child.queue_free()
	for category_value: Variant in hud.CATEGORIES.keys():
		var category := String(category_value)
		var button := Button.new()
		button.name = category
		button.text = category
		button.icon = BunkerPanelStyle.icon(String(CATEGORY_ICONS.get(category, "build")))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s objects" % category
		BunkerUIComponents.style_segment(button, true)
		button.pressed.connect(_category_changed.bind(category))
		_category_grid.add_child(button)
		_category_buttons[category] = button
	_update_category_buttons()


func _groups(category: String) -> Dictionary:
	if category == "Furniture":
		return {
			"All": [],
			"Storage": [3, 34, 35, 32, 33, 36],
			"Tables": [27, 28, 29],
			"Living": [4, 31],
		}
	if category == "Power":
		return {
			"All": [],
			"Generation": [6, 7, 8],
			"Batteries": [13, 14, 15],
			"Control": [10, 11, 12, 16],
		}
	return {"All": []}


func _rebuild_subcategories() -> void:
	_subcategory_buttons.clear()
	for child: Node in _subcategory_row.get_children():
		_subcategory_row.remove_child(child)
		child.queue_free()
	var groups: Dictionary = _groups(_category)
	var show_subcategories := groups.size() > 1
	_subcategory_row.visible = show_subcategories
	_subcategory_divider.visible = show_subcategories
	if not show_subcategories:
		_subcategory = "All"
		return
	if not groups.has(_subcategory):
		_subcategory = "All"
	for group_value: Variant in groups.keys():
		var group := String(group_value)
		var button := Button.new()
		button.text = group
		button.toggle_mode = true
		button.button_pressed = group == _subcategory
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BunkerUIComponents.style_segment(button, true)
		button.pressed.connect(_subcategory_changed.bind(group))
		_subcategory_row.add_child(button)
		_subcategory_buttons[group] = button
	_update_subcategory_buttons()


func _update_subcategory_buttons() -> void:
	for group_value: Variant in _subcategory_buttons.keys():
		var group := String(group_value)
		var button: Button = _subcategory_buttons[group] as Button
		button.set_pressed_no_signal(group == _subcategory)


func _update_category_buttons() -> void:
	for category_value: Variant in _category_buttons.keys():
		var category := String(category_value)
		var button: Button = _category_buttons[category] as Button
		button.set_pressed_no_signal(category == _category)


func _category_changed(category: String) -> void:
	if category == _category:
		return
	_category = category
	_subcategory = "All"
	_update_category_buttons()
	_rebuild_subcategories()
	_rebuild_items()


func _subcategory_changed(group: String) -> void:
	if group == _subcategory:
		return
	_subcategory = group
	_update_subcategory_buttons()
	_rebuild_items()


func _filtered() -> Array:
	var source_value: Variant = hud.CATEGORIES.get(_category, [])
	var source: Array = source_value as Array
	var ids_value: Variant = _groups(_category).get(_subcategory, [])
	var ids: Array = ids_value as Array
	if ids.is_empty():
		return source
	return source.filter(func(item: Dictionary) -> bool:
		return int(item["tile_id"]) in ids)


func _rebuild_items() -> void:
	if _items == null:
		return
	_first_item = null
	_item_cards.clear()
	for child: Node in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	var filtered: Array = _filtered()
	_section_title.text = (_subcategory if _subcategory != "All" else _category).to_upper()
	_section_meta.text = "%d OBJECT%s" % [filtered.size(), "" if filtered.size() == 1 else "S"]
	for item_value: Variant in filtered:
		var item: Dictionary = item_value as Dictionary
		var tile_id := int(item["tile_id"])
		var card := BuildCatalogCard.new()
		_items.add_child(card)
		card.configure(tile_id, String(item["name"]), int(item["price"]),
			hud.preview_texture(tile_id, false))
		card.set_selected(tile_id == _selected_tile_id)
		card.pressed.connect(_choose.bind(tile_id))
		_item_cards[tile_id] = card
		if _first_item == null:
			_first_item = card
	_scroll.set_deferred("scroll_vertical", 0)


func open() -> void:
	show()
	refresh_live()
	_scroll.set_deferred("scroll_vertical", 0)
	if _first_item != null:
		_first_item.call_deferred("grab_focus")


func close() -> void:
	hud.close_workspace_menu()


func _choose(tile_id: int) -> void:
	_selected_tile_id = tile_id
	var card: BuildCatalogCard = _item_cards.get(tile_id) as BuildCatalogCard
	if card != null:
		_selected_name = card.item_name
		_selected_price = card.item_price
	_update_selected_cards()
	_update_mode_card()
	hud.choose_build_item(tile_id)


func set_selected_item(tile_id: int, item_name: String, price: int) -> void:
	_selected_tile_id = tile_id
	_selected_name = item_name
	_selected_price = price
	_update_selected_cards()
	_update_mode_card()
	_reveal_selected.call_deferred()


func clear_placement_state() -> void:
	_selected_tile_id = -1
	_selected_name = ""
	_selected_price = 0
	_update_selected_cards()
	_update_mode_card()


func refresh_live() -> void:
	var cash := int(hud.available_cash())
	if cash != _last_cash:
		_last_cash = cash
		_cash_label.text = "$%s AVAILABLE" % _money(cash)
	if _selected_tile_id >= 0:
		_mode_meta.add_theme_color_override("font_color",
			BunkerPanelStyle.RED if cash < _selected_price else BunkerPanelStyle.GREEN)


func _update_selected_cards() -> void:
	for tile_id_value: Variant in _item_cards.keys():
		var tile_id := int(tile_id_value)
		var card: BuildCatalogCard = _item_cards[tile_id] as BuildCatalogCard
		if card != null:
			card.set_selected(tile_id == _selected_tile_id)


func _update_mode_card() -> void:
	var placing := _selected_tile_id >= 0
	_mode_card.add_theme_stylebox_override("panel", BunkerUIComponents.status_style(placing))
	_mode_icon.texture = BunkerPanelStyle.icon("check" if placing else "plus")
	_mode_icon.self_modulate = BunkerPanelStyle.GREEN if placing else BunkerPanelStyle.BLUE
	if placing:
		_mode_meta.show()
		_mode_eyebrow.text = "PLACING NOW"
		_mode_eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.GREEN)
		_mode_title.text = _selected_name
		_mode_meta.text = "$%s" % _money(_selected_price)
		_mode_meta.add_theme_color_override("font_color", BunkerPanelStyle.GREEN)
	else:
		_mode_meta.hide()
		_mode_eyebrow.text = "READY"
		_mode_eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
		_mode_title.text = "Choose an object to begin"
		_mode_meta.text = ""
		_mode_meta.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)


func _reveal_selected() -> void:
	var card: BuildCatalogCard = _item_cards.get(_selected_tile_id) as BuildCatalogCard
	if card != null and card.is_visible_in_tree():
		_scroll.ensure_control_visible(card)


func _money(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return raw + out
