class_name ShopPanel
extends PanelContainer

## Purpose-built desktop supply shop. This script owns presentation and
## session-local cart state only; BuildModeHUD and FarmingShopHelper remain
## authoritative for prices, funds, delivery, and object creation.

const CATEGORIES: Dictionary = {
	"Farming": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	"Food & water": [16, 17],
	"Fuel": [18],
	"Containers": [19, 20],
	"Cooking": [21],
}
const CATEGORY_ICONS: Dictionary = {
	"Farming": "plant",
	"Food & water": "water",
	"Fuel": "fuel",
	"Containers": "storage",
	"Cooking": "cooking",
}
const SUBCATEGORIES: Dictionary = {
	"Farming": {
		"All": [],
		"Seeds": [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
		"Soil & fertilizer": [1, 14, 15],
	},
	"Food & water": {"All": [], "Water": [16], "Food": [17]},
	"Fuel": {"All": []},
	"Containers": {"All": [], "Crates": [19], "Baskets": [20]},
	"Cooking": {"All": []},
}

var hud: Node
var cart: ShopCart = ShopCart.new()

var _category: String = "Farming"
var _subcategory: String = "All"
var _search: LineEdit
var _catalog_title: Label
var _catalog_meta: Label
var _subtabs: HBoxContainer
var _products: GridContainer
var _product_viewport: Control
var _product_scroll: ScrollContainer
var _cart_rows: VBoxContainer
var _cart_viewport: Control
var _cart_scroll: ScrollContainer
var _balance: Label
var _cart_count: Label
var _total_value: Label
var _remaining_value: Label
var _message_panel: PanelContainer
var _message_icon: TextureRect
var _message: Label
var _checkout: Button
var _category_buttons: Dictionary = {}
var _subcategory_buttons: Dictionary = {}
var _cart_focus_targets: Dictionary = {}
var _last_cash: int = -1


func _ready() -> void:
	BunkerUIComponents.apply_theme(self)
	BunkerUIComponents.shell(self)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	cart.changed.connect(_refresh_cart)
	_rebuild_subcategories()
	_rebuild_products()
	_refresh_cart()
	_set_message("Orders are delivered beside the player.", "neutral")


func _build_shell() -> void:
	var root := VBoxContainer.new()
	root.name = "ShopContent"
	root.add_theme_constant_override("separation", 10)
	add_child(BunkerUIComponents.inset(root, 18, 15, 18, 12))
	root.add_child(_build_header())
	BunkerUIComponents.divider(root)
	var columns := HBoxContainer.new()
	columns.name = "ShopWorkspace"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)
	columns.add_child(_build_category_rail())
	columns.add_child(_build_catalog())
	columns.add_child(_build_cart())
	BunkerUIComponents.divider(root)
	root.add_child(_build_footer())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	header.add_child(BunkerUIComponents.icon_well("shop", 50.0))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.text = "BUNKER SUPPLY"
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	titles.add_child(eyebrow)
	var heading := Label.new()
	heading.text = "Supply shop"
	BunkerPanelStyle.title(heading, 25)
	titles.add_child(heading)
	var description := Label.new()
	description.text = "Order provisions for immediate bunker delivery."
	BunkerPanelStyle.muted(description, 12)
	titles.add_child(description)
	header.add_child(_build_balance_card())
	var close := Button.new()
	close.name = "Close"
	close.text = ""
	close.tooltip_text = "Close shop"
	close.custom_minimum_size = Vector2(44, 44)
	BunkerPanelStyle.icon_button(close, "close")
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(func() -> void: hud.close_workspace_menu())
	header.add_child(close)
	return header


func _build_balance_card() -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(188, 50)
	card.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("172820"), BunkerPanelStyle.GREEN.darkened(0.30), 8, 1, 9))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon("storage")
	icon.self_modulate = BunkerPanelStyle.GREEN
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	var caption := Label.new()
	caption.text = "AVAILABLE CASH"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", BunkerPanelStyle.GREEN)
	copy.add_child(caption)
	_balance = Label.new()
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance.add_theme_font_size_override("font_size", 19)
	_balance.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.add_child(_balance)
	return card


func _build_category_rail() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CategoryRail"
	panel.custom_minimum_size.x = 216
	panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("181e1d"), BunkerPanelStyle.BRASS.darkened(0.28), 8, 1, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(BunkerUIComponents.inset(box, 10, 12, 10, 10))
	var label := Label.new()
	label.text = "SHOP BY DEPARTMENT"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	box.add_child(label)
	for category_value: Variant in CATEGORIES.keys():
		var category := String(category_value)
		var button := Button.new()
		button.name = category
		button.text = ""
		button.toggle_mode = true
		BunkerUIComponents.style_segment(button)
		button.custom_minimum_size.y = 58
		_add_category_content(button, category,
			String(CATEGORY_ICONS.get(category, "shop")))
		button.pressed.connect(_set_category.bind(category))
		box.add_child(button)
		_category_buttons[category] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_update_category_buttons()
	return panel


func _build_catalog() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ProductCatalog"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("151a1a"), BunkerPanelStyle.BRASS.darkened(0.38), 8, 1, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(BunkerUIComponents.inset(box, 12, 12, 12, 10))
	var catalog_head := HBoxContainer.new()
	catalog_head.add_theme_constant_override("separation", 12)
	box.add_child(catalog_head)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 0)
	catalog_head.add_child(title_stack)
	_catalog_title = Label.new()
	_catalog_title.text = "Farming supplies"
	BunkerPanelStyle.title(_catalog_title, 20)
	title_stack.add_child(_catalog_title)
	_catalog_meta = Label.new()
	_catalog_meta.add_theme_font_size_override("font_size", 10)
	_catalog_meta.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	title_stack.add_child(_catalog_meta)
	_search = LineEdit.new()
	_search.placeholder_text = "Search this department"
	_search.custom_minimum_size = Vector2(220, 40)
	_search.right_icon = BunkerPanelStyle.icon("search")
	_search.expand_to_text_length = false
	BunkerPanelStyle.field(_search)
	_search.text_changed.connect(func(_text: String) -> void: _rebuild_products())
	catalog_head.add_child(_search)
	_subtabs = HBoxContainer.new()
	_subtabs.name = "Subcategories"
	_subtabs.add_theme_constant_override("separation", 6)
	box.add_child(_subtabs)
	BunkerUIComponents.divider(box)
	_product_viewport = Control.new()
	_product_viewport.name = "ProductViewport"
	_product_viewport.custom_minimum_size.y = 260
	_product_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_product_viewport.clip_contents = true
	box.add_child(_product_viewport)
	_product_scroll = ScrollContainer.new()
	_product_scroll.name = "CatalogScroll"
	_product_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_product_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_product_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_product_scroll.follow_focus = true
	_product_viewport.add_child(_product_scroll)
	var scroll_inset := MarginContainer.new()
	scroll_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_inset.add_theme_constant_override("margin_left", 2)
	scroll_inset.add_theme_constant_override("margin_top", 2)
	scroll_inset.add_theme_constant_override("margin_right", 10)
	scroll_inset.add_theme_constant_override("margin_bottom", 2)
	_product_scroll.add_child(scroll_inset)
	_products = GridContainer.new()
	_products.name = "Products"
	_products.columns = 3
	_products.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_products.add_theme_constant_override("h_separation", 9)
	_products.add_theme_constant_override("v_separation", 9)
	scroll_inset.add_child(_products)
	return panel


func _build_cart() -> Control:
	var panel := PanelContainer.new()
	panel.name = "OrderSummary"
	panel.custom_minimum_size.x = 332
	panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("181e1d"), BunkerPanelStyle.BRASS.darkened(0.22), 8, 1, 8))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	panel.add_child(BunkerUIComponents.inset(body, 12, 12, 12, 11))
	var cart_head := HBoxContainer.new()
	body.add_child(cart_head)
	var cart_copy := VBoxContainer.new()
	cart_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_copy.add_theme_constant_override("separation", 0)
	cart_head.add_child(cart_copy)
	var eyebrow := Label.new()
	eyebrow.text = "ORDER SUMMARY"
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	cart_copy.add_child(eyebrow)
	var cart_title := Label.new()
	cart_title.text = "Your cart"
	BunkerPanelStyle.title(cart_title, 20)
	cart_copy.add_child(cart_title)
	_cart_count = Label.new()
	_cart_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cart_count.add_theme_font_size_override("font_size", 11)
	_cart_count.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	cart_head.add_child(_cart_count)
	BunkerUIComponents.divider(body)
	_cart_viewport = Control.new()
	_cart_viewport.name = "CartViewport"
	_cart_viewport.custom_minimum_size.y = 150
	_cart_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cart_viewport.clip_contents = true
	body.add_child(_cart_viewport)
	_cart_scroll = ScrollContainer.new()
	_cart_scroll.name = "CartScroll"
	_cart_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cart_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cart_scroll.follow_focus = true
	_cart_viewport.add_child(_cart_scroll)
	var cart_inset := MarginContainer.new()
	cart_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_inset.add_theme_constant_override("margin_right", 9)
	_cart_scroll.add_child(cart_inset)
	_cart_rows = VBoxContainer.new()
	_cart_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cart_rows.add_theme_constant_override("separation", 7)
	cart_inset.add_child(_cart_rows)
	BunkerUIComponents.divider(body)
	var totals := PanelContainer.new()
	totals.name = "OrderTotals"
	totals.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("202625"), BunkerPanelStyle.BRASS.darkened(0.28), 7, 1, 9))
	var total_box := VBoxContainer.new()
	total_box.add_theme_constant_override("separation", 8)
	totals.add_child(total_box)
	_total_value = _add_value_row(total_box, "TOTAL", 21, BunkerPanelStyle.IVORY)
	_remaining_value = _add_value_row(
		total_box, "CASH AFTER PURCHASE", 14, BunkerPanelStyle.MUTED)
	body.add_child(totals)
	_checkout = Button.new()
	_checkout.text = "Checkout"
	_checkout.custom_minimum_size.y = 52
	BunkerPanelStyle.icon_button(_checkout, "check", true)
	_checkout.pressed.connect(_checkout_order)
	body.add_child(_checkout)
	_build_message(body)
	return panel


func _build_message(parent: VBoxContainer) -> void:
	_message_panel = PanelContainer.new()
	_message_panel.name = "OrderMessage"
	parent.add_child(_message_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_message_panel.add_child(row)
	_message_icon = TextureRect.new()
	_message_icon.custom_minimum_size = Vector2(19, 19)
	_message_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_message_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_message_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_message_icon)
	_message = Label.new()
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 11)
	row.add_child(_message)


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	BunkerUIComponents.key_hint(footer, "A", "Select")
	BunkerUIComponents.key_hint(footer, "D-PAD", "Navigate")
	BunkerUIComponents.key_hint(footer, "SCROLLBAR", "Scroll")
	BunkerUIComponents.key_hint(footer, "B", "Close")
	return footer


func open() -> void:
	show()
	_refresh_financials()
	_rebuild_products()
	_refresh_cart()
	_product_scroll.set_deferred("scroll_vertical", 0)
	_cart_scroll.set_deferred("scroll_vertical", 0)
	if InputMode.is_controller():
		var category_button: Button = _category_buttons.get(_category) as Button
		if category_button != null:
			category_button.call_deferred("grab_focus")
	else:
		_search.call_deferred("grab_focus")


func close() -> void:
	hud.close_workspace_menu()


func _process(_delta: float) -> void:
	if visible:
		_refresh_financials()


func _set_category(category: String) -> void:
	_category = category
	_subcategory = "All"
	_catalog_title.text = "%s supplies" % category
	_update_category_buttons()
	_rebuild_subcategories()
	_rebuild_products()


func _update_category_buttons() -> void:
	for category_value: Variant in _category_buttons.keys():
		var category := String(category_value)
		var button: Button = _category_buttons[category] as Button
		button.set_pressed_no_signal(category == _category)


func _rebuild_subcategories() -> void:
	if _subtabs == null:
		return
	_subcategory_buttons.clear()
	for child: Node in _subtabs.get_children():
		_subtabs.remove_child(child)
		child.queue_free()
	var sections: Dictionary = SUBCATEGORIES[_category] as Dictionary
	for subsection_value: Variant in sections.keys():
		var subsection := String(subsection_value)
		var button := Button.new()
		button.text = subsection
		button.toggle_mode = true
		button.button_pressed = subsection == _subcategory
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BunkerUIComponents.style_segment(button, true)
		button.pressed.connect(_set_subcategory.bind(subsection))
		_subtabs.add_child(button)
		_subcategory_buttons[subsection] = button
	_update_subcategory_buttons()


func _update_subcategory_buttons() -> void:
	for subsection_value: Variant in _subcategory_buttons.keys():
		var subsection := String(subsection_value)
		var button: Button = _subcategory_buttons[subsection] as Button
		button.set_pressed_no_signal(subsection == _subcategory)


func _set_subcategory(subsection: String) -> void:
	_subcategory = subsection
	_update_subcategory_buttons()
	_rebuild_products()


func _rebuild_products() -> void:
	if _products == null:
		return
	for child: Node in _products.get_children():
		_products.remove_child(child)
		child.queue_free()
	var query: String = _search.text.strip_edges().to_lower() if _search != null else ""
	var sections: Dictionary = SUBCATEGORIES[_category] as Dictionary
	var item_ids: Array = sections[_subcategory] as Array
	if item_ids.is_empty():
		item_ids = CATEGORIES[_category] as Array
	var shown: int = 0
	for item_value: Variant in item_ids:
		var item_id := int(item_value)
		var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
		if not query.is_empty() and query not in String(info["name"]).to_lower():
			continue
		var card := ShopProductCard.new()
		_products.add_child(card)
		card.configure(item_id, String(info["name"]), int(info["price"]),
			hud.preview_texture(item_id, true))
		card.pressed.connect(_add.bind(item_id))
		shown += 1
	_catalog_meta.text = "%d ITEM%s AVAILABLE" % [shown, "" if shown == 1 else "S"]
	_product_scroll.set_deferred("scroll_vertical", 0)


func _add(item_id: int) -> void:
	var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
	if cart.change(item_id, 1):
		_set_message("%s added to your cart." % String(info["name"]), "positive")
	else:
		_set_message("Cart capacity reached.", "warning")


func _refresh_cart() -> void:
	if _cart_rows == null:
		return
	var focus_key := _focused_cart_key()
	var prior_scroll := _cart_scroll.scroll_vertical
	_cart_focus_targets.clear()
	for child: Node in _cart_rows.get_children():
		_cart_rows.remove_child(child)
		child.queue_free()
	var count: int = 0
	for item_id_value: Variant in cart.lines.keys():
		var item_id := int(item_id_value)
		var quantity := cart.quantity(item_id)
		count += quantity
		_cart_rows.add_child(_make_cart_row(item_id, quantity))
	if cart.lines.is_empty():
		_cart_rows.add_child(_build_empty_cart())
	_cart_count.text = "%d ITEM%s" % [count, "" if count == 1 else "S"]
	_refresh_financials()
	if not focus_key.is_empty():
		_restore_cart_focus.call_deferred(focus_key, prior_scroll)


func _build_empty_cart() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 104
	panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("1b2221"), BunkerPanelStyle.BRASS.darkened(0.40), 7, 1, 8))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon("shop")
	icon.self_modulate = BunkerPanelStyle.MUTED.darkened(0.18)
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var empty := Label.new()
	empty.text = "Your cart is empty"
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_theme_font_size_override("font_size", 14)
	empty.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	box.add_child(empty)
	var instruction := Label.new()
	instruction.text = "Choose an item from the catalog."
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BunkerPanelStyle.muted(instruction, 11)
	box.add_child(instruction)
	return panel


func _make_cart_row(item_id: int, quantity: int) -> Control:
	var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("202625"), BunkerPanelStyle.BRASS.darkened(0.34), 7, 1, 7))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	frame.add_child(body)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	var preview_well := PanelContainer.new()
	preview_well.custom_minimum_size = Vector2(58, 52)
	preview_well.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("2a302f"), BunkerPanelStyle.BRASS.darkened(0.40), 5, 1, 4))
	top.add_child(preview_well)
	var preview := TextureRect.new()
	preview.texture = hud.preview_texture(item_id, true)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_child(preview)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	top.add_child(copy)
	var name := Label.new()
	name.text = String(info["name"])
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 14)
	name.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.add_child(name)
	var each := Label.new()
	each.text = "%s each" % _money(int(info["price"]))
	BunkerPanelStyle.muted(each, 11)
	copy.add_child(each)
	var line_total := Label.new()
	line_total.text = _money(int(info["price"]) * quantity)
	line_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line_total.add_theme_font_size_override("font_size", 14)
	line_total.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	top.add_child(line_total)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	body.add_child(controls)
	var quantity_label := Label.new()
	quantity_label.text = "QTY"
	quantity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_label.add_theme_font_size_override("font_size", 10)
	quantity_label.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	controls.add_child(quantity_label)
	var minus := _quantity_button("minus", "Remove one")
	_register_cart_focus(minus, "%d:minus" % item_id)
	minus.pressed.connect(cart.change.bind(item_id, -1))
	controls.add_child(minus)
	var amount := Label.new()
	amount.text = str(quantity)
	amount.custom_minimum_size.x = 30
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	controls.add_child(amount)
	var plus := _quantity_button("plus", "Add one")
	_register_cart_focus(plus, "%d:plus" % item_id)
	plus.pressed.connect(cart.change.bind(item_id, 1))
	controls.add_child(plus)
	var remove := _quantity_button("close", "Remove item", true)
	_register_cart_focus(remove, "%d:remove" % item_id)
	remove.pressed.connect(cart.remove.bind(item_id))
	controls.add_child(remove)
	return frame


func _quantity_button(symbol: String, tooltip: String, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = ""
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(36, 34)
	BunkerPanelStyle.icon_button(button, symbol, false, danger)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button


func _register_cart_focus(button: Button, key: String) -> void:
	button.set_meta("shop_cart_focus", key)
	_cart_focus_targets[key] = button


func _focused_cart_key() -> String:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and focus.has_meta("shop_cart_focus"):
		return String(focus.get_meta("shop_cart_focus"))
	return ""


func _restore_cart_focus(key: String, scroll_position: int) -> void:
	if not is_visible_in_tree():
		return
	_cart_scroll.scroll_vertical = scroll_position
	var target: Button = _cart_focus_targets.get(key) as Button
	if target != null and is_instance_valid(target):
		target.grab_focus()
		return
	for candidate_value: Variant in _cart_focus_targets.values():
		var candidate: Button = candidate_value as Button
		if candidate != null and is_instance_valid(candidate):
			candidate.grab_focus()
			return
	_checkout.grab_focus()


func _refresh_financials() -> void:
	if _balance == null:
		return
	var cash := int(hud.available_cash())
	var total := cart.total(FarmingShopHelper.SHOP_ITEM_INFO)
	if cash != _last_cash:
		_last_cash = cash
		_balance.text = _money(cash)
	_total_value.text = _money(total)
	_remaining_value.text = _money(cash - total)
	_remaining_value.add_theme_color_override("font_color",
		BunkerPanelStyle.RED if total > cash else BunkerPanelStyle.MUTED)
	_checkout.disabled = cart.lines.is_empty() or cash < total


func _checkout_order() -> void:
	var result: Dictionary = hud.checkout_order(cart.lines.duplicate())
	var succeeded := bool(result.get("ok", false))
	_set_message(String(result.get("message", "Checkout unavailable.")),
		"positive" if succeeded else "warning")
	if succeeded:
		cart.clear()
	else:
		_refresh_financials()


func _set_message(text: String, tone: String) -> void:
	if _message_panel == null:
		return
	_message.text = text
	var background := Color("1b2221")
	var border := BunkerPanelStyle.BRASS.darkened(0.34)
	var accent := BunkerPanelStyle.MUTED
	var symbol := "container"
	if tone == "positive":
		background = Color("172820")
		border = BunkerPanelStyle.GREEN.darkened(0.28)
		accent = BunkerPanelStyle.GREEN
		symbol = "check"
	elif tone == "warning":
		background = Color("30211f")
		border = BunkerPanelStyle.RED.darkened(0.20)
		accent = BunkerPanelStyle.RED
		symbol = "warning"
	_message_panel.add_theme_stylebox_override("panel",
		BunkerUIComponents.panel_box(background, border, 7, 1, 8))
	_message_icon.texture = BunkerPanelStyle.icon(symbol)
	_message_icon.self_modulate = accent
	_message.add_theme_color_override("font_color", accent)


func _money(value: int) -> String:
	var sign_text := "-" if value < 0 else ""
	var raw := str(absi(value))
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return sign_text + "$" + raw + out


func _add_category_content(button: Button, caption: String, symbol: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	var inset := BunkerUIComponents.inset(row, 8, 6, 8, 6)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	row.add_child(BunkerUIComponents.icon_well(symbol, 36.0))
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var arrow := TextureRect.new()
	arrow.texture = BunkerPanelStyle.icon("arrow")
	arrow.self_modulate = BunkerPanelStyle.BRASS.lightened(0.18)
	arrow.custom_minimum_size = Vector2(17, 17)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)


func _add_value_row(parent: VBoxContainer, caption: String,
		font_size: int, color: Color) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10 if font_size <= 16 else 11)
	label.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	row.add_child(label)
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	row.add_child(value)
	return value
