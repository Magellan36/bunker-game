class_name ShopProductCard
extends Button

const PREVIEW_MOTION: GDScript = preload("res://scripts/ui/common/UIPreviewMotion.gd")

## One-click supply card used by ShopPanel. The card itself is the action:
## there is no ambiguous select-then-add workflow or nested button.

var item_id: int = -1
var item_name: String = ""
var item_price: int = 0

var _preview: TextureRect
var _preview_fallback: TextureRect
var _name_label: Label
var _price_label: Label


func _ready() -> void:
	text = ""
	clip_text = true
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerUIComponents.style_segment(self)
	custom_minimum_size = Vector2(208, 244)
	add_theme_stylebox_override("normal", BunkerUIComponents.panel_box(
		Color("181e1d"), BunkerPanelStyle.BRASS.darkened(0.30), 9, 1, 6))
	add_theme_stylebox_override("hover", BunkerUIComponents.panel_box(
		Color("20292a"), BunkerPanelStyle.BLUE.darkened(0.22), 9, 1, 6))
	add_theme_stylebox_override("pressed", BunkerUIComponents.panel_box(
		Color("1b2e38"), BunkerPanelStyle.BLUE, 9, 2, 5))
	add_theme_stylebox_override("focus", BunkerUIComponents.panel_box(
		Color.TRANSPARENT, BunkerPanelStyle.IVORY, 10, 2))

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 6)
	var inset := BunkerUIComponents.inset(stack, 7, 7, 7, 7)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inset)

	var preview_well := PanelContainer.new()
	preview_well.name = "PreviewWell"
	preview_well.custom_minimum_size.y = 130
	preview_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("2a302f"), BunkerPanelStyle.BRASS.darkened(0.38), 7, 1, 5))
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
	_preview_fallback.texture = BunkerPanelStyle.icon("shop")
	_preview_fallback.self_modulate = BunkerPanelStyle.MUTED.darkened(0.25)
	_preview_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fallback_inset := BunkerUIComponents.inset(_preview_fallback, 46, 32, 46, 32)
	fallback_inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_layer.add_child(fallback_inset)

	var identity := VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 0)
	stack.add_child(identity)
	var eyebrow := Label.new()
	eyebrow.text = "SUPPLY ITEM"
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(eyebrow)
	_name_label = Label.new()
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(_name_label)

	var action_band := PanelContainer.new()
	action_band.custom_minimum_size.y = 43
	action_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_band.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		BunkerPanelStyle.BLUE_DARK, BunkerPanelStyle.BLUE.darkened(0.12), 6, 1, 7))
	stack.add_child(action_band)
	var action := HBoxContainer.new()
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.add_theme_constant_override("separation", 7)
	action_band.add_child(action)
	var plus := TextureRect.new()
	plus.texture = BunkerPanelStyle.icon("plus")
	plus.self_modulate = BunkerPanelStyle.BLUE
	plus.custom_minimum_size = Vector2(20, 20)
	plus.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plus.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.add_child(plus)
	var action_label := Label.new()
	action_label.text = "ADD TO CART"
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_label.add_theme_font_size_override("font_size", 12)
	action_label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.add_child(action_label)
	_price_label = Label.new()
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_price_label.add_theme_font_size_override("font_size", 14)
	_price_label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	_price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.add_child(_price_label)


func configure(id: int, title: String, price: int, texture: Texture2D) -> void:
	item_id = id
	item_name = title
	item_price = price
	_name_label.text = title
	_price_label.text = _money(price)
	tooltip_text = "%s — %s\nAdd one to cart" % [title, _money(price)]
	PREVIEW_MOTION.swap(_preview, _preview_fallback, texture)


func _money(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return "$" + raw + out
