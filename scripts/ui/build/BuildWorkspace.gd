class_name BuildWorkspace
extends Control

## Desktop construction workspace. Gameplay authority remains in BuildModeHUD
## and BuildModeController; this file owns only the visual shell, focusable
## controls, and their presentation states.

const TOOL_ORDER := [0, 3, 2, 1, 4, 5, 6]
const TOOL_NAMES := ["Build", "Move", "Duplicate", "Demolish", "Undo", "Wire", "Pipe"]
const TOOL_ICONS := ["build", "move", "duplicate", "demolish", "undo", "wire", "pipe"]

var hud: Node
var catalog: BuildCatalogPanel
var shop: ShopPanel
var toolbar: HBoxContainer
var shop_button: Button
## Retained as inert compatibility handles for older probes/integrations.
var summary: PanelContainer
var summary_label: Label

var _banner_panel: PanelContainer
var _banner: Label
var _banner_subtitle: Label
var _toolbar_panel: PanelContainer
var _helper_panel: PanelContainer
var _helper_row: HBoxContainer
var _grid_label: Label
var _tool_buttons: Array[Button] = []
var _tool_icon_wells: Array[PanelContainer] = []
var _tool_icons: Array[TextureRect] = []
var _controller_nav: ControllerUINavigation
var _pointer_focus: Control
var _last_pointer_position := Vector2(-1000, -1000)
var _placement_was_active: bool = false
var _controller_hints: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	BunkerUIComponents.apply_theme(self)
	_build_banner()
	_build_shop_button()
	_build_toolbar()
	_build_helper()
	_build_compatibility_summary()
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
	_controller_nav = ControllerUINavigation.new()
	_controller_nav.ui_root = self
	_controller_nav.close_on_cancel = false
	## Build Mode deliberately keeps its established right-stick pointer;
	## hovering a Control transfers focus and A activates it.
	_controller_nav.right_stick_navigation = false
	_controller_nav.blocks_world_cursor = false
	add_child(_controller_nav)
	get_viewport().size_changed.connect(_layout)
	_controller_hints = InputMode.is_controller()
	_rebuild_helper_hints()
	_layout()
	set_process(true)


func _build_banner() -> void:
	_banner_panel = PanelContainer.new()
	_banner_panel.name = "BuildModePlate"
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("111615ef"), BunkerPanelStyle.BRASS.darkened(0.14), 8, 1, 7))
	add_child(_banner_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	_banner_panel.add_child(row)
	row.add_child(BunkerUIComponents.icon_well("build", 36.0))
	var copy := VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	_banner = Label.new()
	_banner.text = "BUILD MODE"
	_banner.add_theme_font_size_override("font_size", 17)
	_banner.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.add_child(_banner)
	_banner_subtitle = Label.new()
	_banner_subtitle.text = "CONSTRUCTION"
	_banner_subtitle.add_theme_font_size_override("font_size", 10)
	_banner_subtitle.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	copy.add_child(_banner_subtitle)


func _build_shop_button() -> void:
	shop_button = Button.new()
	shop_button.name = "SupplyShop"
	shop_button.toggle_mode = true
	shop_button.custom_minimum_size = Vector2(230, 60)
	shop_button.tooltip_text = "Open the supply shop"
	BunkerUIComponents.style_segment(shop_button)
	shop_button.add_theme_stylebox_override("normal", BunkerUIComponents.panel_box(
		Color("17232a"), BunkerPanelStyle.BLUE.darkened(0.22), 8, 1, 8))
	shop_button.add_theme_stylebox_override("hover", BunkerUIComponents.panel_box(
		Color("1d303a"), BunkerPanelStyle.BLUE, 8, 1, 8))
	shop_button.add_theme_stylebox_override("pressed", BunkerUIComponents.panel_box(
		BunkerPanelStyle.BLUE_DARK, BunkerPanelStyle.BLUE, 8, 2, 7))
	shop_button.pressed.connect(hud.open_shop_menu)
	add_child(shop_button)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	var inset := BunkerUIComponents.inset(content, 10, 7, 11, 7)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_button.add_child(inset)
	content.add_child(BunkerUIComponents.icon_well("shop", 40.0))
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	content.add_child(copy)
	var eyebrow := Label.new()
	eyebrow.text = "SUPPLIES"
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(eyebrow)
	var title := Label.new()
	title.text = "Open shop"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(title)
	var arrow := TextureRect.new()
	arrow.texture = BunkerPanelStyle.icon("arrow")
	arrow.self_modulate = BunkerPanelStyle.IVORY
	arrow.custom_minimum_size = Vector2(22, 22)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(arrow)


func _build_toolbar() -> void:
	_toolbar_panel = PanelContainer.new()
	_toolbar_panel.name = "ToolDock"
	_toolbar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar_panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("111615f5"), BunkerPanelStyle.BRASS.darkened(0.09), 10, 1, 8))
	add_child(_toolbar_panel)
	toolbar = HBoxContainer.new()
	toolbar.name = "Tools"
	toolbar.add_theme_constant_override("separation", 6)
	_toolbar_panel.add_child(toolbar)
	for i: int in range(TOOL_ORDER.size()):
		var button := _make_tool_button(TOOL_NAMES[i], TOOL_ICONS[i])
		button.pressed.connect(hud._on_toolbar_click.bind(TOOL_ORDER[i]))
		toolbar.add_child(button)
		_tool_buttons.append(button)


func _make_tool_button(caption: String, symbol: String) -> Button:
	var button := Button.new()
	button.name = caption
	button.tooltip_text = caption
	BunkerUIComponents.style_tool(button)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	var inset := BunkerUIComponents.inset(stack, 7, 5, 7, 4)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	var icon_well := PanelContainer.new()
	icon_well.custom_minimum_size = Vector2(38, 34)
	icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("29302f"), BunkerPanelStyle.BRASS.darkened(0.44), 5, 1, 5))
	stack.add_child(icon_well)
	var icon := TextureRect.new()
	icon.name = "ToolIcon"
	icon.texture = BunkerPanelStyle.icon(symbol)
	icon.self_modulate = BunkerPanelStyle.IVORY
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_child(icon)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	_tool_icon_wells.append(icon_well)
	_tool_icons.append(icon)
	return button


func _build_helper() -> void:
	_helper_panel = PanelContainer.new()
	_helper_panel.name = "PlacementHelper"
	_helper_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_helper_panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("111615ef"), BunkerPanelStyle.BRASS.darkened(0.2), 8, 1, 6))
	add_child(_helper_panel)
	_helper_row = HBoxContainer.new()
	_helper_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_helper_row.add_theme_constant_override("separation", 18)
	_helper_panel.add_child(_helper_row)


func _rebuild_helper_hints() -> void:
	for child: Node in _helper_row.get_children():
		child.queue_free()
	if _controller_hints:
		BunkerUIComponents.key_hint(_helper_row, "A", "Place")
		BunkerUIComponents.key_hint(_helper_row, "LT / RT", "Rotate")
		BunkerUIComponents.key_hint(_helper_row, "B", "Cancel")
	else:
		BunkerUIComponents.key_hint(_helper_row, "LMB", "Place")
		BunkerUIComponents.key_hint(_helper_row, "WHEEL", "Rotate")
		BunkerUIComponents.key_hint(_helper_row, "RMB", "Cancel")
	var separator := VSeparator.new()
	separator.custom_minimum_size.x = 1
	_helper_row.add_child(separator)
	_grid_label = Label.new()
	_grid_label.add_theme_font_size_override("font_size", 12)
	_grid_label.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	_helper_row.add_child(_grid_label)


func _build_compatibility_summary() -> void:
	summary = PanelContainer.new()
	summary.name = "LegacySummaryHandle"
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_label = Label.new()
	summary.add_child(summary_label)
	add_child(summary)
	summary.hide()


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_banner_panel.position = Vector2((viewport_size.x - 286.0) * 0.5, 18)
	_banner_panel.size = Vector2(286, 52)
	shop_button.position = Vector2(viewport_size.x - 254, 18)
	shop_button.size = Vector2(230, 60)

	var toolbar_size := Vector2(minf(700.0, viewport_size.x - 48.0), 82)
	_toolbar_panel.position = Vector2(maxf(24.0, (viewport_size.x - toolbar_size.x) * 0.5),
		viewport_size.y - toolbar_size.y - 18.0)
	_toolbar_panel.size = toolbar_size
	var helper_size := Vector2(minf(720.0, viewport_size.x - 48.0), 42)
	_helper_panel.position = Vector2(maxf(24.0, (viewport_size.x - helper_size.x) * 0.5),
		_toolbar_panel.position.y - helper_size.y - 10.0)
	_helper_panel.size = helper_size

	var catalog_top := 88.0
	var catalog_bottom := _helper_panel.position.y - 14.0
	var catalog_height := minf(610.0, maxf(420.0, catalog_bottom - catalog_top))
	var catalog_size := Vector2(minf(488.0, viewport_size.x - 48.0), catalog_height)
	catalog.custom_maximum_size = catalog_size
	catalog.position = Vector2(24, catalog_top + maxf(0.0,
		(catalog_bottom - catalog_top - catalog_height) * 0.5))
	catalog.size = catalog_size

	var shop_size := Vector2(minf(1380.0, viewport_size.x - 96.0),
		minf(780.0, viewport_size.y - 120.0))
	shop.custom_maximum_size = shop_size
	shop.position = (viewport_size - shop_size) * 0.5
	shop.size = shop_size


func show_catalog() -> void:
	shop.hide()
	summary.hide()
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


func placement_started(tile_id: int, item_name: String, price: int) -> void:
	shop.hide()
	summary.hide()
	catalog.set_selected_item(tile_id, item_name, price)
	catalog.show()
	_helper_panel.show()
	_toolbar_panel.show()
	shop_button.show()


func close_all() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	catalog.clear_placement_state()
	catalog.hide()
	shop.hide()
	summary.hide()
	_helper_panel.hide()
	## Shop hides the shared tool dock and shortcut while it owns the screen.
	## Restore those baseline controls during shutdown so no hidden child state
	## can leak into the next Build Mode session.
	_toolbar_panel.show()
	shop_button.show()
	_pointer_focus = null
	_last_pointer_position = Vector2(-1000, -1000)
	_placement_was_active = false


func refresh(active_tool: int, submenu_open: bool, submenu_source: String,
		placement_active: bool = false, grid_size: float = 0.25) -> void:
	for i: int in range(_tool_buttons.size()):
		var active: bool = TOOL_ORDER[i] == active_tool \
			or (TOOL_ORDER[i] == 0 and submenu_open and submenu_source == "construct")
		_tool_buttons[i].set_pressed_no_signal(active)
		_tool_icons[i].self_modulate = BunkerPanelStyle.BLUE if active else BunkerPanelStyle.IVORY
		_tool_icon_wells[i].add_theme_stylebox_override("panel",
			BunkerUIComponents.panel_box(
				BunkerPanelStyle.BLUE_DARK if active else Color("29302f"),
				BunkerPanelStyle.BLUE if active else BunkerPanelStyle.BRASS.darkened(0.44),
				5, 1, 5))
	shop_button.set_pressed_no_signal(submenu_open and submenu_source == "farming")
	var controller_now := InputMode.is_controller()
	if controller_now != _controller_hints:
		_controller_hints = controller_now
		_rebuild_helper_hints()
	_grid_label.text = "GRID  %.2f M" % grid_size
	_helper_panel.visible = placement_active
	_banner_subtitle.text = "OBJECT PLACEMENT" if placement_active else "CONSTRUCTION"
	_banner_subtitle.add_theme_color_override("font_color",
		BunkerPanelStyle.GREEN if placement_active else BunkerPanelStyle.BLUE)
	if _placement_was_active and not placement_active and catalog != null:
		catalog.clear_placement_state()
	_placement_was_active = placement_active
	if catalog != null and catalog.visible:
		catalog.refresh_live()


func menu_open() -> bool:
	return catalog.visible or shop.visible


func covers(point: Vector2) -> bool:
	for control: Control in [catalog, shop, _toolbar_panel, shop_button, _helper_panel]:
		if control.visible and control.get_global_rect().has_point(point):
			return true
	return false


func _process(_delta: float) -> void:
	if not visible or not InputMode.is_controller():
		return
	var pointer := get_viewport().get_mouse_position()
	if pointer.distance_squared_to(_last_pointer_position) < 0.25:
		return
	_last_pointer_position = pointer
	var hovered := _focusable_at(self, pointer)
	if hovered != null:
		if hovered != _pointer_focus:
			hovered.grab_focus()
			_pointer_focus = hovered
	else:
		var current := get_viewport().gui_get_focus_owner()
		if current != null and is_ancestor_of(current):
			current.release_focus()
			_pointer_focus = null


func _focusable_at(node: Node, point: Vector2) -> Control:
	var children: Array[Node] = node.get_children()
	children.reverse()
	for child: Node in children:
		if child is Control and not (child as Control).is_visible_in_tree():
			continue
		var nested := _focusable_at(child, point)
		if nested != null:
			return nested
		if child is Control:
			var control := child as Control
			if control.focus_mode != Control.FOCUS_NONE \
					and control.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and control.get_global_rect().has_point(point):
				return control
	return null
