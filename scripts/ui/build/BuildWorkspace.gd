class_name BuildWorkspace
extends Control

var hud: Node
var catalog: BuildCatalogPanel
var shop: ShopPanel
var toolbar: HBoxContainer
var shop_button: Button
var summary: PanelContainer
var summary_label: Label
var _tool_buttons: Array[Button] = []
const TOOL_ORDER := [0, 3, 2, 1, 4, 5, 6]
const TOOL_NAMES := ["Build", "Move", "Duplicate", "Deconstruct", "Undo", "Wire", "Pipe"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	BunkerPanelStyle.apply(self)
	var banner := Label.new()
	banner.name = "Banner"
	banner.text = "BUILD MODE"
	banner.add_theme_font_size_override("font_size", 16)
	banner.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	banner.position = Vector2(24, 22)
	add_child(banner)
	shop_button = Button.new()
	shop_button.text = "Open supply shop"
	shop_button.toggle_mode = true
	BunkerPanelStyle.button(shop_button, true)
	shop_button.focus_mode = Control.FOCUS_NONE
	shop_button.pressed.connect(hud.open_shop_menu)
	add_child(shop_button)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	add_child(toolbar)
	for i in TOOL_ORDER.size():
		var button := Button.new()
		button.text = TOOL_NAMES[i]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(112, 48)
		BunkerPanelStyle.button(button)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(hud._on_toolbar_click.bind(TOOL_ORDER[i]))
		toolbar.add_child(button)
		_tool_buttons.append(button)
	summary = PanelContainer.new()
	summary.custom_minimum_size = Vector2(320, 106)
	summary.add_theme_stylebox_override("panel", BunkerPanelStyle.box(BunkerPanelStyle.BG, BunkerPanelStyle.BRASS, 8, 1))
	var summary_body := VBoxContainer.new()
	summary.add_child(BunkerPanelStyle.margin(summary_body, 14, 12, 14, 12))
	var summary_head := Label.new()
	summary_head.text = "READY TO PLACE"
	summary_head.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	summary_body.add_child(summary_head)
	summary_label = Label.new()
	BunkerPanelStyle.title(summary_label, 18)
	summary_body.add_child(summary_label)
	var reopen := Button.new()
	reopen.text = "Back to catalog"
	BunkerPanelStyle.button(reopen)
	reopen.focus_mode = Control.FOCUS_NONE
	reopen.pressed.connect(_back_to_catalog)
	summary_body.add_child(reopen)
	add_child(summary)
	catalog = BuildCatalogPanel.new()
	catalog.hud = hud
	add_child(catalog)
	shop = ShopPanel.new()
	shop.hud = hud
	add_child(shop)
	catalog.hide()
	shop.hide()
	summary.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	shop_button.position = Vector2(vp.x - 204, 20)
	shop_button.size = Vector2(180, 48)
	toolbar.position = Vector2(maxf(24, (vp.x - 826) * 0.5), vp.y - 76)
	toolbar.size = Vector2(826, 52)
	catalog.position = Vector2(24, 78)
	catalog.size = Vector2(minf(460, vp.x - 48), minf(740, vp.y - 174))
	var shop_size := Vector2(minf(1340, vp.x - 48), minf(820, vp.y - 48))
	shop.position = (vp - shop_size) * 0.5
	shop.size = shop_size
	summary.position = Vector2(24, 78)

func show_catalog() -> void:
	shop.hide()
	summary.hide()
	toolbar.show()
	shop_button.show()
	catalog.open()
	UIFade.fade_in(catalog)

func show_shop() -> void:
	catalog.hide()
	summary.hide()
	toolbar.hide()
	shop_button.hide()
	shop.open()
	UIFade.fade_in(shop)

func hide_menus() -> void:
	catalog.hide()
	shop.hide()
	toolbar.show()
	shop_button.show()

func placement_started(item_name: String, price: int) -> void:
	catalog.hide()
	shop.hide()
	summary_label.text = "%s   •   $%d" % [item_name, price]
	summary.show()
	UIFade.fade_in(summary)
	toolbar.show()
	shop_button.show()

func close_all() -> void:
	catalog.hide()
	shop.hide()
	summary.hide()

func refresh(active_tool: int, submenu_open: bool, submenu_source: String) -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = BuildWorkspace.TOOL_ORDER[i] == active_tool \
			or (BuildWorkspace.TOOL_ORDER[i] == 0 and submenu_open and submenu_source == "construct")
	shop_button.button_pressed = submenu_open and submenu_source == "farming"

func menu_open() -> bool:
	return catalog.visible or shop.visible

func covers(point: Vector2) -> bool:
	for control: Control in [catalog, shop, toolbar, shop_button, summary]:
		if control.visible and control.get_global_rect().has_point(point):
			return true
	return false

func _back_to_catalog() -> void:
	hud.cancel_requested.emit()
	show_catalog()
