class_name BuildWorkspace
extends Control

## Presentation shell for BuildModeHUD. Gameplay authority remains in the
## existing HUD signals and BuildModeController.

var hud: Node
var catalog: BuildCatalogPanel
var shop: ShopPanel
var toolbar: HBoxContainer
var shop_button: Button
var summary: PanelContainer
var summary_label: Label
var _banner: Label
var _toolbar_panel: PanelContainer
var _helper_panel: PanelContainer
var _grid_label: Label
var _tool_buttons: Array[Button] = []

const TOOL_ORDER := [0, 3, 2, 1, 4, 5, 6]
const TOOL_NAMES := ["Build", "Move", "Duplicate", "Demolish", "Undo", "Wire", "Pipe"]
const TOOL_ICONS := ["build", "move", "duplicate", "demolish", "undo", "wire", "pipe"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	BunkerPanelStyle.apply(self)
	_build_banner()
	_build_shop_button()
	_build_toolbar()
	_build_helper()
	_build_summary()
	catalog = BuildCatalogPanel.new()
	catalog.hud = hud
	add_child(catalog)
	shop = ShopPanel.new()
	shop.hud = hud
	add_child(shop)
	catalog.hide()
	shop.hide()
	summary.hide()
	_helper_panel.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.text = "BUILD MODE"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	add_child(_banner)

func _build_shop_button() -> void:
	shop_button = Button.new()
	shop_button.text = "Open shop"
	shop_button.toggle_mode = true
	shop_button.custom_minimum_size = Vector2(170, 54)
	BunkerPanelStyle.icon_button(shop_button, "shop", true)
	shop_button.focus_mode = Control.FOCUS_NONE
	shop_button.pressed.connect(hud.open_shop_menu)
	add_child(shop_button)

func _build_toolbar() -> void:
	_toolbar_panel = PanelContainer.new()
	_toolbar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar_panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(Color("121716e8"), BunkerPanelStyle.BRASS.darkened(0.08), 7, 1))
	add_child(_toolbar_panel)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	_toolbar_panel.add_child(BunkerPanelStyle.margin(toolbar, 8, 8, 8, 8))
	for i in TOOL_ORDER.size():
		var button := _make_tool_button(TOOL_NAMES[i], TOOL_ICONS[i])
		button.pressed.connect(hud._on_toolbar_click.bind(TOOL_ORDER[i]))
		toolbar.add_child(button)
		_tool_buttons.append(button)

func _make_tool_button(caption: String, symbol: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(106, 78)
	button.focus_mode = Control.FOCUS_NONE
	BunkerPanelStyle.button(button)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	var inset := BunkerPanelStyle.margin(stack, 8, 7, 8, 5)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon(symbol)
	icon.self_modulate = BunkerPanelStyle.IVORY
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	return button

func _build_helper() -> void:
	_helper_panel = PanelContainer.new()
	_helper_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_helper_panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(Color("121716ed"), BunkerPanelStyle.BRASS.darkened(0.16), 7, 1))
	add_child(_helper_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	_helper_panel.add_child(BunkerPanelStyle.margin(row, 16, 8, 16, 8))
	for hint_text in ["LMB  Place", "Wheel  Rotate", "RMB  Cancel"]:
		var hint := Label.new()
		hint.text = hint_text
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
		row.add_child(hint)
	_grid_label = Label.new()
	_grid_label.add_theme_font_size_override("font_size", 13)
	_grid_label.add_theme_color_override("font_color", BunkerPanelStyle.BRASS.lightened(0.35))
	row.add_child(_grid_label)

func _build_summary() -> void:
	summary = PanelContainer.new()
	summary.custom_minimum_size = Vector2(360, 110)
	summary.add_theme_stylebox_override("panel", BunkerPanelStyle.box(Color("121716f2"), BunkerPanelStyle.BRASS, 7, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	summary.add_child(BunkerPanelStyle.margin(body, 14, 11, 14, 11))
	var summary_head := Label.new()
	summary_head.text = "READY TO PLACE"
	summary_head.add_theme_font_size_override("font_size", 12)
	summary_head.add_theme_color_override("font_color", BunkerPanelStyle.GREEN)
	body.add_child(summary_head)
	summary_label = Label.new()
	BunkerPanelStyle.title(summary_label, 18)
	body.add_child(summary_label)
	var reopen := Button.new()
	reopen.text = "Back to catalog"
	reopen.custom_minimum_size.y = 36
	BunkerPanelStyle.icon_button(reopen, "undo")
	reopen.focus_mode = Control.FOCUS_NONE
	reopen.pressed.connect(_back_to_catalog)
	body.add_child(reopen)
	add_child(summary)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_banner.position = Vector2((vp.x - 220.0) * 0.5, 20)
	_banner.size = Vector2(220, 34)
	shop_button.position = Vector2(vp.x - 194, 18)
	shop_button.size = Vector2(170, 54)
	var toolbar_size := Vector2(818, 94)
	_toolbar_panel.position = Vector2(maxf(24, (vp.x - toolbar_size.x) * 0.5), vp.y - toolbar_size.y - 18)
	_toolbar_panel.size = toolbar_size
	var helper_size := Vector2(620, 42)
	_helper_panel.position = Vector2(maxf(24, (vp.x - helper_size.x) * 0.5), _toolbar_panel.position.y - 50)
	_helper_panel.size = helper_size
	catalog.position = Vector2(24, 70)
	catalog.size = Vector2(minf(440, vp.x - 48), minf(760, vp.y - 184))
	var shop_size := Vector2(minf(1560, vp.x - 64), minf(900, vp.y - 64))
	shop.position = (vp - shop_size) * 0.5
	shop.size = shop_size
	summary.position = Vector2(24, 78)
	summary.size = Vector2(360, 110)

func show_catalog() -> void:
	shop.hide()
	summary.hide()
	_helper_panel.hide()
	_toolbar_panel.show()
	shop_button.show()
	catalog.open()
	UIFade.fade_in(catalog)

func show_shop() -> void:
	catalog.hide()
	summary.hide()
	_helper_panel.hide()
	_toolbar_panel.hide()
	shop_button.hide()
	shop.open()
	UIFade.fade_in(shop)

func hide_menus() -> void:
	catalog.hide()
	shop.hide()
	_toolbar_panel.show()
	shop_button.show()

func placement_started(item_name: String, price: int) -> void:
	catalog.hide()
	shop.hide()
	summary_label.text = "%s   •   $%s" % [item_name, _money(price)]
	summary.show()
	_helper_panel.show()
	UIFade.fade_in(summary)
	_toolbar_panel.show()
	shop_button.show()

func close_all() -> void:
	catalog.hide()
	shop.hide()
	summary.hide()
	_helper_panel.hide()

func refresh(active_tool: int, submenu_open: bool, submenu_source: String,
		placement_active: bool = false, grid_size: float = 0.25) -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = TOOL_ORDER[i] == active_tool \
			or (TOOL_ORDER[i] == 0 and submenu_open and submenu_source == "construct")
		var icon := _tool_buttons[i].find_child("TextureRect", true, false) as TextureRect
		if icon != null:
			icon.self_modulate = BunkerPanelStyle.IVORY
	shop_button.button_pressed = submenu_open and submenu_source == "farming"
	_grid_label.text = "Grid  %.2f m" % grid_size
	_helper_panel.visible = placement_active and not menu_open()
	if not placement_active and summary.visible:
		summary.hide()

func menu_open() -> bool:
	return catalog.visible or shop.visible

func covers(point: Vector2) -> bool:
	for control: Control in [catalog, shop, _toolbar_panel, shop_button, summary, _helper_panel]:
		if control.visible and control.get_global_rect().has_point(point):
			return true
	return false

func _back_to_catalog() -> void:
	hud.cancel_requested.emit()
	show_catalog()

func _money(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return raw + out
