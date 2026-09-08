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
var _first_item: BuildCatalogCard
var _selected_tile_id: int = -1
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
	_build_categories(body)
	_build_items(body)
	_rebuild_category_buttons()
	_rebuild_subcategories()
	_rebuild_items()



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
	_items = GridContainer.new()
	_items.name = "Objects"
	_items.columns = 2
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("h_separation", 8)
	_items.add_theme_constant_override("v_separation", 8)
	BunkerUIComponents.scroll_content(_scroll, _items, 3, 3, 3)


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
		## Native expand_icon scales against the text's remaining width, which
		## made long labels such as Structure squeeze their symbol while short
		## labels such as Power retained a large one. Keep every category on the
		## shared fixed icon canvas instead.
		button.expand_icon = false
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s objects" % category
		BunkerUIComponents.style_segment(button, true)
		button.add_theme_constant_override("icon_max_width", 16)
		button.add_theme_constant_override("h_separation", 3)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var chrome: StyleBox = button.get_theme_stylebox(state).duplicate()
			chrome.content_margin_left = 4
			chrome.content_margin_right = 4
			button.add_theme_stylebox_override(state, chrome)
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
	UIFade.content(_scroll_viewport)


func _subcategory_changed(group: String) -> void:
	if group == _subcategory:
		return
	_subcategory = group
	_update_subcategory_buttons()
	_rebuild_items()
	UIFade.content(_scroll_viewport)


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
	_update_selected_cards()
	hud.choose_build_item(tile_id)


func set_selected_item(tile_id: int, _item_name: String, _price: int) -> void:
	_selected_tile_id = tile_id
	_update_selected_cards()
	_reveal_selected.call_deferred()


func clear_placement_state() -> void:
	_selected_tile_id = -1
	_update_selected_cards()


func refresh_live() -> void:
	var cash := int(hud.available_cash())
	if cash != _last_cash:
		_last_cash = cash
		_cash_label.text = "%s AVAILABLE" % UIFormat.money(cash)


func _update_selected_cards() -> void:
	for tile_id_value: Variant in _item_cards.keys():
		var tile_id := int(tile_id_value)
		var card: BuildCatalogCard = _item_cards[tile_id] as BuildCatalogCard
		if card != null:
			card.set_selected(tile_id == _selected_tile_id)



func _reveal_selected() -> void:
	var card: BuildCatalogCard = _item_cards.get(_selected_tile_id) as BuildCatalogCard
	if card != null and card.is_visible_in_tree():
		_scroll.ensure_control_visible(card)
