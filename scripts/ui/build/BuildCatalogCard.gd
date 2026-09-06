class_name BuildCatalogCard
extends Button

const PREVIEW_MOTION: GDScript = preload("res://scripts/ui/common/UIPreviewMotion.gd")

## Presentation-only construction card.  BuildCatalogPanel owns selection and
## BuildModeHUD owns the actual placement transaction.

var tile_id: int = -1
var item_name: String = ""
var item_price: int = 0

var _preview: TextureRect
var _preview_fallback: TextureRect
var _name_label: Label
var _price_label: Label
var _selected_badge: PanelContainer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_mode = true
	clip_text = true
	clip_contents = true
	BunkerUIComponents.style_segment(self)
	## style_segment() establishes shared button defaults, including a compact
	## minimum height. Set the construction-card height afterwards so the
	## preview and information band are contained by the GridContainer instead
	## of visually spilling into the next row.
	custom_minimum_size = Vector2(0, 166)
	add_theme_stylebox_override("normal", BunkerUIComponents.panel_box(
		Color("181e1d"), BunkerPanelStyle.BRASS.darkened(0.30), 8, 1, 6))
	add_theme_stylebox_override("hover", BunkerUIComponents.panel_box(
		Color("20292a"), BunkerPanelStyle.BLUE.darkened(0.25), 8, 1, 6))
	add_theme_stylebox_override("pressed", BunkerUIComponents.panel_box(
		Color("1b2e38"), BunkerPanelStyle.BLUE, 8, 2, 5))
	add_theme_stylebox_override("hover_pressed", BunkerUIComponents.panel_box(
		Color("203642"), BunkerPanelStyle.BLUE, 8, 2, 5))

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	var card_inset := BunkerUIComponents.inset(stack, 6, 6, 6, 6)
	card_inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card_inset)

	var preview_well := PanelContainer.new()
	preview_well.name = "PreviewWell"
	preview_well.custom_minimum_size.y = 102
	preview_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("2a302f"), BunkerPanelStyle.BRASS.darkened(0.38), 6, 1, 5))
	stack.add_child(preview_well)
	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_child(preview_layer)
	_preview = TextureRect.new()
	_preview.name = "Preview"
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.add_child(_preview)
	_preview_fallback = TextureRect.new()
	_preview_fallback.name = "PreviewFallback"
	_preview_fallback.texture = BunkerPanelStyle.icon("build")
	_preview_fallback.self_modulate = BunkerPanelStyle.MUTED.darkened(0.25)
	_preview_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fallback_inset := BunkerUIComponents.inset(_preview_fallback, 28, 18, 28, 18)
	fallback_inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_layer.add_child(fallback_inset)

	_selected_badge = PanelContainer.new()
	_selected_badge.name = "SelectedBadge"
	_selected_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_selected_badge.position = Vector2(-33, 6)
	_selected_badge.size = Vector2(27, 27)
	_selected_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_badge.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("183023"), BunkerPanelStyle.GREEN.darkened(0.12), 13, 1, 5))
	var check := TextureRect.new()
	check.texture = BunkerPanelStyle.icon("check")
	check.self_modulate = BunkerPanelStyle.GREEN
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_badge.add_child(check)
	preview_layer.add_child(_selected_badge)

	var info_band := PanelContainer.new()
	info_band.name = "InformationBand"
	info_band.custom_minimum_size.y = 45
	info_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_band.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("202625"), BunkerPanelStyle.BRASS.darkened(0.44), 6, 1, 5))
	stack.add_child(info_band)
	var copy := HBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 8)
	info_band.add_child(copy)
	var name_stack := VBoxContainer.new()
	name_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	name_stack.add_theme_constant_override("separation", 0)
	copy.add_child(name_stack)
	var action_label := Label.new()
	action_label.text = "PLACE OBJECT"
	action_label.add_theme_font_size_override("font_size", 9)
	action_label.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_stack.add_child(action_label)
	_name_label = Label.new()
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_stack.add_child(_name_label)
	var price_badge := PanelContainer.new()
	price_badge.custom_minimum_size.x = 50
	price_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_badge.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("17232a"), BunkerPanelStyle.BLUE.darkened(0.28), 5, 1, 5))
	copy.add_child(price_badge)
	_price_label = Label.new()
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_price_label.add_theme_font_size_override("font_size", 13)
	_price_label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	_price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_badge.add_child(_price_label)
	set_selected(false)


func configure(id: int, title: String, price: int, texture: Texture2D) -> void:
	tile_id = id
	item_name = title
	item_price = price
	_name_label.text = title
	_price_label.text = "$%s" % _money(price)
	tooltip_text = "%s — $%s\nSelect to begin placement" % [title, _money(price)]
	set_preview(texture)


func set_preview(texture: Texture2D) -> void:
	PREVIEW_MOTION.swap(_preview, _preview_fallback, texture)


func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	if _selected_badge != null:
		_selected_badge.visible = selected


func _money(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return raw + out
