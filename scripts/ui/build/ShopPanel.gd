class_name ShopPanel
extends PanelContainer

## Desktop supply catalog layered over Build Mode. Shopping only stages an
## order; FarmingShopHelper and BuildModeHUD remain the purchase authorities.

var hud: Node
var cart := ShopCart.new()
var _category := "Farming"
var _subcategory := "All"
var _search: LineEdit
var _catalog_title: Label
var _subtabs: HBoxContainer
var _products: GridContainer
var _product_scroll: ScrollContainer
var _cart_rows: VBoxContainer
var _cart_scroll: ScrollContainer
var _balance: Label
var _cart_count: Label
var _total_value: Label
var _remaining_value: Label
var _message: Label
var _checkout: Button
var _category_buttons: Dictionary = {}

const CATEGORIES := {
	"Farming": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	"Food & water": [16, 17],
	"Fuel": [18],
	"Containers": [19, 20],
	"Cooking": [21],
}
const CATEGORY_ICONS := {
	"Farming": "food",
	"Food & water": "container",
	"Fuel": "power",
	"Containers": "storage",
	"Cooking": "cooking",
}
const SUBCATEGORIES := {
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

func _ready() -> void:
	BunkerPanelStyle.panel(self)
	_build_shell()
	cart.changed.connect(_refresh_cart)
	_rebuild_subcategories()
	_rebuild_products()
	_refresh_cart()

func _build_shell() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(BunkerPanelStyle.margin(root, 20, 16, 20, 14))
	root.add_child(_build_header())
	var rule := HSeparator.new()
	root.add_child(rule)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)
	columns.add_child(_build_category_rail())
	columns.add_child(_build_catalog())
	columns.add_child(_build_cart())
	root.add_child(_build_footer())

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var mark := TextureRect.new()
	mark.texture = BunkerPanelStyle.icon("shop")
	mark.self_modulate = BunkerPanelStyle.BLUE
	mark.custom_minimum_size = Vector2(46, 46)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(mark)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	var eyebrow := Label.new()
	eyebrow.text = "BUNKER SUPPLY"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	titles.add_child(eyebrow)
	var heading := Label.new()
	heading.text = "Bunker Supply Shop"
	BunkerPanelStyle.title(heading, 27)
	titles.add_child(heading)
	header.add_child(titles)
	var available := VBoxContainer.new()
	available.add_theme_constant_override("separation", 0)
	var available_caption := Label.new()
	available_caption.text = "AVAILABLE CASH"
	available_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BunkerPanelStyle.muted(available_caption, 11)
	available.add_child(available_caption)
	_balance = Label.new()
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance.add_theme_color_override("font_color", BunkerPanelStyle.GREEN)
	_balance.add_theme_font_size_override("font_size", 20)
	available.add_child(_balance)
	header.add_child(available)
	var close := Button.new()
	close.text = ""
	close.tooltip_text = "Close shop"
	close.custom_minimum_size = Vector2(44, 44)
	BunkerPanelStyle.icon_button(close, "close")
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(func(): hud.close_workspace_menu())
	header.add_child(close)
	return header

func _build_category_rail() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 220
	panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE, BunkerPanelStyle.BRASS.darkened(0.28), 7, 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(BunkerPanelStyle.margin(box, 12, 14, 12, 12))
	var label := Label.new()
	label.text = "CATEGORIES"
	BunkerPanelStyle.muted(label, 12)
	box.add_child(label)
	for category: String in CATEGORIES:
		var button := Button.new()
		button.text = ""
		button.toggle_mode = true
		button.button_pressed = category == _category
		button.custom_minimum_size.y = 58
		BunkerPanelStyle.button(button)
		_add_category_content(button, category, str(CATEGORY_ICONS[category]))
		button.pressed.connect(_set_category.bind(category))
		box.add_child(button)
		_category_buttons[category] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := Button.new()
	back.text = "Continue building"
	back.custom_minimum_size.y = 46
	BunkerPanelStyle.icon_button(back, "build")
	back.pressed.connect(func(): hud.open_construct_menu())
	box.add_child(back)
	return panel

func _build_catalog() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	var catalog_head := HBoxContainer.new()
	catalog_head.add_theme_constant_override("separation", 12)
	_catalog_title = Label.new()
	_catalog_title.text = "Farming supplies"
	_catalog_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.title(_catalog_title, 20)
	catalog_head.add_child(_catalog_title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search supplies"
	_search.custom_minimum_size = Vector2(240, 40)
	BunkerPanelStyle.field(_search)
	_search.text_changed.connect(func(_text: String): _rebuild_products())
	catalog_head.add_child(_search)
	box.add_child(catalog_head)
	_subtabs = HBoxContainer.new()
	_subtabs.add_theme_constant_override("separation", 6)
	box.add_child(_subtabs)
	_product_scroll = ScrollContainer.new()
	_product_scroll.name = "CatalogScroll"
	_product_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_product_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_product_scroll.follow_focus = true
	box.add_child(_product_scroll)
	_products = GridContainer.new()
	_products.columns = 3
	_products.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_products.add_theme_constant_override("h_separation", 10)
	_products.add_theme_constant_override("v_separation", 10)
	_product_scroll.add_child(_products)
	return box

func _build_cart() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 340
	panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE, BunkerPanelStyle.BRASS.darkened(0.20), 7, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	panel.add_child(BunkerPanelStyle.margin(body, 14, 14, 14, 14))
	var cart_head := HBoxContainer.new()
	var cart_title := Label.new()
	cart_title.text = "Your cart"
	cart_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.title(cart_title, 19)
	cart_head.add_child(cart_title)
	_cart_count = Label.new()
	_cart_count.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	cart_head.add_child(_cart_count)
	body.add_child(cart_head)
	_cart_scroll = ScrollContainer.new()
	_cart_scroll.name = "CartScroll"
	_cart_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cart_scroll.follow_focus = true
	body.add_child(_cart_scroll)
	_cart_rows = VBoxContainer.new()
	_cart_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cart_rows.add_theme_constant_override("separation", 8)
	_cart_scroll.add_child(_cart_rows)
	var divider := HSeparator.new()
	body.add_child(divider)
	var totals := PanelContainer.new()
	totals.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE_ALT, BunkerPanelStyle.BRASS.darkened(0.3), 6, 1))
	var total_box := VBoxContainer.new()
	total_box.add_theme_constant_override("separation", 8)
	totals.add_child(BunkerPanelStyle.margin(total_box, 12, 10, 12, 10))
	_total_value = _add_value_row(total_box, "TOTAL", 20, BunkerPanelStyle.IVORY)
	_remaining_value = _add_value_row(total_box, "CASH AFTER PURCHASE", 14, BunkerPanelStyle.MUTED)
	body.add_child(totals)
	_checkout = Button.new()
	_checkout.text = "Checkout"
	_checkout.custom_minimum_size.y = 52
	BunkerPanelStyle.icon_button(_checkout, "check", true)
	_checkout.pressed.connect(_checkout_order)
	body.add_child(_checkout)
	_message = Label.new()
	_message.text = "Orders are delivered beside the player."
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 34
	BunkerPanelStyle.muted(_message, 12)
	body.add_child(_message)
	return panel

func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	var hint := Label.new()
	hint.text = "Right stick pointer or D-pad  Navigate   •   A  Select   •   Focus scrollbar + Up / Down  Scroll   •   B  Close"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BunkerPanelStyle.muted(hint, 12)
	footer.add_child(hint)
	return footer

func open() -> void:
	show()
	_refresh_balance()
	_rebuild_products()
	_refresh_cart()
	_product_scroll.scroll_vertical = 0
	if InputMode.is_controller():
		var category_button := _category_buttons.get(_category) as Button
		if category_button != null:
			category_button.call_deferred("grab_focus")
	else:
		_search.call_deferred("grab_focus")

func close() -> void:
	hud.close_workspace_menu()

func _process(_delta: float) -> void:
	if visible:
		_refresh_balance()

func _set_category(category: String) -> void:
	_category = category
	_subcategory = "All"
	_catalog_title.text = "%s supplies" % category
	for key: String in _category_buttons:
		(_category_buttons[key] as Button).button_pressed = key == category
	_rebuild_subcategories()
	_rebuild_products()

func _rebuild_subcategories() -> void:
	if _subtabs == null:
		return
	for child: Node in _subtabs.get_children():
		child.queue_free()
	for subsection: String in SUBCATEGORIES[_category]:
		var button := Button.new()
		button.text = subsection
		button.toggle_mode = true
		button.button_pressed = subsection == _subcategory
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BunkerPanelStyle.button(button)
		button.pressed.connect(_set_subcategory.bind(subsection))
		_subtabs.add_child(button)

func _set_subcategory(subsection: String) -> void:
	_subcategory = subsection
	_rebuild_subcategories()
	_rebuild_products()

func _rebuild_products() -> void:
	if _products == null:
		return
	for child: Node in _products.get_children():
		child.queue_free()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var item_ids: Array = SUBCATEGORIES[_category][_subcategory]
	if item_ids.is_empty():
		item_ids = CATEGORIES[_category]
	for item_id: int in item_ids:
		var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
		if not query.is_empty() and query not in str(info.name).to_lower():
			continue
		_products.add_child(_make_product_card(item_id, info))
	_product_scroll.scroll_vertical = 0

func _make_product_card(item_id: int, info: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(184, 230)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE, BunkerPanelStyle.BRASS.darkened(0.28), 7, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(BunkerPanelStyle.margin(body, 9, 9, 9, 9))
	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size.y = 120
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		Color("303635"), Color("505a57"), 6, 1))
	var preview := TextureRect.new()
	preview.texture = hud.preview_texture(item_id, true)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_child(preview)
	body.add_child(preview_frame)
	var item_name := Label.new()
	item_name.text = str(info.name)
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item_name.add_theme_font_size_override("font_size", 16)
	item_name.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	body.add_child(item_name)
	var add := Button.new()
	add.text = ""
	add.custom_minimum_size.y = 42
	BunkerPanelStyle.button(add, true)
	_add_purchase_content(add, _money(int(info.price)))
	add.pressed.connect(_add.bind(item_id))
	body.add_child(add)
	return card

func _add(item_id: int) -> void:
	var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
	_message.text = "%s added to your cart." % str(info.name) if cart.change(item_id, 1) \
		else "Cart capacity reached."

func _refresh_cart() -> void:
	if _cart_rows == null:
		return
	for child: Node in _cart_rows.get_children():
		child.queue_free()
	var count := 0
	for item_id_value: Variant in cart.lines:
		var item_id := int(item_id_value)
		var quantity := cart.quantity(item_id)
		count += quantity
		_cart_rows.add_child(_make_cart_row(item_id, quantity))
	if cart.lines.is_empty():
		var empty := Label.new()
		empty.text = "Your cart is empty.\nChoose supplies from the catalog."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 92
		BunkerPanelStyle.muted(empty, 13)
		_cart_rows.add_child(empty)
	_cart_count.text = "%d ITEM%s" % [count, "" if count == 1 else "S"]
	var total := cart.total(FarmingShopHelper.SHOP_ITEM_INFO)
	_total_value.text = _money(total)
	_remaining_value.text = _money(hud.available_cash() - total)
	_remaining_value.add_theme_color_override("font_color",
		BunkerPanelStyle.RED if total > hud.available_cash() else BunkerPanelStyle.MUTED)
	_checkout.disabled = cart.lines.is_empty() or hud.available_cash() < total
	_refresh_balance()

func _make_cart_row(item_id: int, quantity: int) -> Control:
	var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE_ALT, BunkerPanelStyle.BRASS.darkened(0.36), 6, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	frame.add_child(BunkerPanelStyle.margin(body, 8, 8, 8, 8))
	var top := HBoxContainer.new()
	var preview_well := PanelContainer.new()
	preview_well.custom_minimum_size = Vector2(54, 48)
	preview_well.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		Color("303635"), Color("505a57"), 5, 1))
	var preview := TextureRect.new()
	preview.texture = hud.preview_texture(item_id, true)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_child(preview)
	top.add_child(preview_well)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new()
	name.text = str(info.name)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.add_child(name)
	var each := Label.new()
	each.text = "%s each" % _money(int(info.price))
	BunkerPanelStyle.muted(each, 12)
	copy.add_child(each)
	top.add_child(copy)
	var line_total := Label.new()
	line_total.text = _money(int(info.price) * quantity)
	line_total.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	top.add_child(line_total)
	body.add_child(top)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	var minus := Button.new()
	minus.text = ""
	minus.custom_minimum_size = Vector2(38, 36)
	BunkerPanelStyle.icon_button(minus, "minus")
	minus.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	minus.pressed.connect(cart.change.bind(item_id, -1))
	controls.add_child(minus)
	var amount := Label.new()
	amount.text = str(quantity)
	amount.custom_minimum_size.x = 34
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	controls.add_child(amount)
	var plus := Button.new()
	plus.text = ""
	plus.custom_minimum_size = Vector2(38, 36)
	BunkerPanelStyle.icon_button(plus, "plus")
	plus.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.pressed.connect(cart.change.bind(item_id, 1))
	controls.add_child(plus)
	var remove := Button.new()
	remove.text = "Remove"
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.custom_minimum_size.y = 36
	BunkerPanelStyle.icon_button(remove, "close", false, true)
	remove.pressed.connect(cart.remove.bind(item_id))
	controls.add_child(remove)
	body.add_child(controls)
	return frame

func _refresh_balance() -> void:
	if _balance != null:
		_balance.text = _money(hud.available_cash())

func _checkout_order() -> void:
	var result: Dictionary = hud.checkout_order(cart.lines.duplicate())
	_message.text = str(result.get("message", "Checkout unavailable."))
	if bool(result.get("ok", false)):
		cart.clear()
	_refresh_cart()

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
	row.add_theme_constant_override("separation", 10)
	var inset := BunkerPanelStyle.margin(row, 12, 8, 10, 8)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(38, 38)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", BunkerPanelStyle.box(BunkerPanelStyle.BLUE_DARK, BunkerPanelStyle.BLUE.darkened(0.25), 6, 1))
	row.add_child(well)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon(symbol)
	icon.self_modulate = BunkerPanelStyle.BLUE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(BunkerPanelStyle.margin(icon, 7, 7, 7, 7))
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var arrow := TextureRect.new()
	arrow.texture = BunkerPanelStyle.icon("arrow")
	arrow.self_modulate = BunkerPanelStyle.BRASS.lightened(0.2)
	arrow.custom_minimum_size = Vector2(18, 18)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)

func _add_purchase_content(button: Button, price: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	var inset := BunkerPanelStyle.margin(row, 10, 7, 10, 7)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon("plus")
	icon.self_modulate = BunkerPanelStyle.IVORY
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var copy := Label.new()
	copy.text = "Add to cart"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.add_theme_font_size_override("font_size", 14)
	copy.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)
	var value := Label.new()
	value.text = price
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)

func _add_value_row(parent: VBoxContainer, caption: String, font_size: int, color: Color) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11 if font_size > 16 else 10)
	label.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	row.add_child(label)
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	row.add_child(value)
	return value
