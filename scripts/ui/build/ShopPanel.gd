class_name ShopPanel
extends PanelContainer

var hud: Node
var cart := ShopCart.new()
var _category := "Farming"
var _subcategory := "All"
var _search: LineEdit
var _subtabs: HBoxContainer
var _products: GridContainer
var _cart_rows: VBoxContainer
var _balance: Label
var _total: Label
var _remaining: Label
var _message: Label
var _checkout: Button
var _category_buttons: Dictionary = {}

const CATEGORIES := {
	"Farming": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	"Food & water": [16, 17], "Fuel": [18], "Containers": [19, 20], "Cooking": [21],
}
const SUBCATEGORIES := {
	"Farming": {"All": [], "Seeds": [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "Soil & fertilizer": [1, 14, 15]},
	"Food & water": {"All": [], "Water": [16], "Food": [17]},
	"Fuel": {"All": []}, "Containers": {"All": [], "Crates": [19], "Baskets": [20]},
	"Cooking": {"All": []},
}

func _ready() -> void:
	var nav := ControllerUINavigation.new()
	nav.ui_root = self
	add_child(nav)
	BunkerPanelStyle.panel(self)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(BunkerPanelStyle.margin(root, 20, 16, 20, 16))
	var header := HBoxContainer.new()
	root.add_child(header)
	var heading := Label.new()
	heading.text = "BUNKER SUPPLY"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerPanelStyle.title(heading, 25)
	header.add_child(heading)
	_balance = Label.new()
	BunkerPanelStyle.title(_balance, 18)
	header.add_child(_balance)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(42, 42)
	BunkerPanelStyle.button(close)
	close.pressed.connect(func(): hud.close_workspace_menu())
	header.add_child(close)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)
	var category_box := VBoxContainer.new()
	category_box.custom_minimum_size.x = 180
	columns.add_child(category_box)
	var cat_label := Label.new()
	cat_label.text = "CATEGORIES"
	BunkerPanelStyle.muted(cat_label, 13)
	category_box.add_child(cat_label)
	for category in CATEGORIES:
		var button := Button.new()
		button.text = str(category)
		button.toggle_mode = true
		button.button_pressed = category == _category
		BunkerPanelStyle.button(button)
		button.pressed.connect(_set_category.bind(str(category)))
		category_box.add_child(button)
		_category_buttons[category] = button
	var product_box := VBoxContainer.new()
	product_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(product_box)
	_search = LineEdit.new()
	_search.placeholder_text = "Search the catalog"
	_search.custom_minimum_size.y = 42
	_search.text_changed.connect(func(_text): _rebuild_products())
	product_box.add_child(_search)
	_subtabs = HBoxContainer.new()
	_subtabs.add_theme_constant_override("separation", 6)
	product_box.add_child(_subtabs)
	var product_scroll := ScrollContainer.new()
	product_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	product_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	product_scroll.follow_focus = true
	product_box.add_child(product_scroll)
	_products = GridContainer.new()
	_products.columns = 3
	_products.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_products.add_theme_constant_override("h_separation", 9)
	_products.add_theme_constant_override("v_separation", 9)
	product_scroll.add_child(_products)
	var cart_panel := PanelContainer.new()
	cart_panel.custom_minimum_size.x = 300
	cart_panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(BunkerPanelStyle.SURFACE, BunkerPanelStyle.BRASS.darkened(0.25), 7, 1))
	columns.add_child(cart_panel)
	var cart_body := VBoxContainer.new()
	cart_body.add_theme_constant_override("separation", 8)
	cart_panel.add_child(BunkerPanelStyle.margin(cart_body, 12, 12, 12, 12))
	var cart_title := Label.new()
	cart_title.text = "YOUR CART"
	BunkerPanelStyle.title(cart_title, 18)
	cart_body.add_child(cart_title)
	var cart_scroll := ScrollContainer.new()
	cart_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cart_scroll.follow_focus = true
	cart_body.add_child(cart_scroll)
	_cart_rows = VBoxContainer.new()
	_cart_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_scroll.add_child(_cart_rows)
	_total = Label.new()
	BunkerPanelStyle.title(_total, 20)
	cart_body.add_child(_total)
	_remaining = Label.new()
	BunkerPanelStyle.muted(_remaining, 14)
	cart_body.add_child(_remaining)
	_checkout = Button.new()
	_checkout.text = "Checkout"
	BunkerPanelStyle.button(_checkout, true)
	_checkout.pressed.connect(_checkout_order)
	cart_body.add_child(_checkout)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BunkerPanelStyle.muted(_message, 13)
	cart_body.add_child(_message)
	var footer := HBoxContainer.new()
	root.add_child(footer)
	var back := Button.new()
	back.text = "Continue building"
	BunkerPanelStyle.button(back)
	back.pressed.connect(func(): hud.open_construct_menu())
	footer.add_child(back)
	var hint := Label.new()
	hint.text = "Right stick / D-pad: navigate   •   Focus scrollbar + Up/Down: scroll"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BunkerPanelStyle.muted(hint, 12)
	footer.add_child(hint)
	cart.changed.connect(_refresh_cart)
	_rebuild_subcategories()
	_rebuild_products()
	_refresh_cart()

func open() -> void:
	show()
	_refresh_balance()
	_rebuild_products()
	_refresh_cart()
	_search.call_deferred("grab_focus")

func close() -> void:
	hud.close_workspace_menu()

func _process(_delta: float) -> void:
	if visible:
		_refresh_balance()

func _set_category(category: String) -> void:
	_category = category
	_subcategory = "All"
	for key in _category_buttons:
		(_category_buttons[key] as Button).button_pressed = key == category
	_rebuild_subcategories()
	_rebuild_products()

func _rebuild_subcategories() -> void:
	if _subtabs == null:
		return
	for child in _subtabs.get_children():
		child.queue_free()
	for subsection in SUBCATEGORIES[_category]:
		var button := Button.new()
		button.text = str(subsection)
		button.toggle_mode = true
		button.button_pressed = subsection == _subcategory
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BunkerPanelStyle.button(button)
		button.pressed.connect(_set_subcategory.bind(str(subsection)))
		_subtabs.add_child(button)

func _set_subcategory(subsection: String) -> void:
	_subcategory = subsection
	_rebuild_subcategories()
	_rebuild_products()

func _rebuild_products() -> void:
	if _products == null:
		return
	for child in _products.get_children():
		child.queue_free()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var item_ids: Array = SUBCATEGORIES[_category][_subcategory]
	if item_ids.is_empty():
		item_ids = CATEGORIES[_category]
	for item_id: int in item_ids:
		var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[item_id]
		if not query.is_empty() and query not in str(info.name).to_lower():
			continue
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(150, 190)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var frame := PanelContainer.new()
		frame.custom_minimum_size.y = 116
		frame.add_theme_stylebox_override("panel", BunkerPanelStyle.box(BunkerPanelStyle.SURFACE_ALT, BunkerPanelStyle.BRASS.darkened(0.3), 6, 1))
		var preview := TextureRect.new()
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture = hud.preview_texture(item_id, true)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(preview)
		card.add_child(frame)
		var name := Label.new()
		name.text = str(info.name)
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
		card.add_child(name)
		var price := Label.new()
		price.text = "$%d" % int(info.price)
		price.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
		card.add_child(price)
		var add := Button.new()
		add.text = "Add to cart"
		BunkerPanelStyle.button(add)
		add.pressed.connect(_add.bind(item_id))
		card.add_child(add)
		_products.add_child(card)

func _add(item_id: int) -> void:
	_message.text = "Added to cart." if cart.change(item_id, 1) else "Cart limit reached."

func _refresh_cart() -> void:
	if _cart_rows == null:
		return
	for child in _cart_rows.get_children():
		child.queue_free()
	for item_id in cart.lines:
		var info: Dictionary = FarmingShopHelper.SHOP_ITEM_INFO[int(item_id)]
		var row := VBoxContainer.new()
		var name := Label.new()
		name.text = "%s   $%d" % [info.name, int(info.price) * cart.quantity(int(item_id))]
		name.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
		row.add_child(name)
		var controls := HBoxContainer.new()
		for specification in [["−", -1], [str(cart.quantity(int(item_id))), 0], ["+", 1], ["Remove", 99]]:
			var button := Button.new()
			button.text = specification[0]
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			BunkerPanelStyle.button(button)
			if int(specification[1]) == 99:
				button.pressed.connect(cart.remove.bind(int(item_id)))
			elif int(specification[1]) != 0:
				button.pressed.connect(cart.change.bind(int(item_id), int(specification[1])))
			else:
				button.disabled = true
			controls.add_child(button)
		row.add_child(controls)
		_cart_rows.add_child(row)
	var total := cart.total(FarmingShopHelper.SHOP_ITEM_INFO)
	_total.text = "Total   $%d" % total
	_remaining.text = "Cash after checkout   $%d" % maxi(0, hud.available_cash() - total)
	_checkout.disabled = cart.lines.is_empty() or hud.available_cash() < total
	_refresh_balance()

func _refresh_balance() -> void:
	if _balance != null:
		_balance.text = "$%d available" % hud.available_cash()

func _checkout_order() -> void:
	var result: Dictionary = hud.checkout_order(cart.lines.duplicate())
	_message.text = str(result.get("message", "Checkout unavailable."))
	if bool(result.get("ok", false)):
		cart.clear()
	_refresh_cart()
