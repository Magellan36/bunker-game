class_name BunkerItemCard
extends Button

var preview: TextureRect
var caption: Label
var badge: Label
var empty := true

func _ready() -> void:
	custom_minimum_size = Vector2(132, 122)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_mode = true
	clip_text = true
	BunkerPanelStyle.button(self)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	stack.add_theme_constant_override("separation", 2)
	add_child(stack)
	preview = TextureRect.new()
	preview.custom_minimum_size.y = 78
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(preview)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	badge = Label.new()
	badge.position = Vector2(8, 6)
	badge.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	badge.add_theme_font_size_override("font_size", 13)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

func display(item_title: String, texture: Texture2D, count: int = 1) -> void:
	empty = texture == null
	preview.texture = texture
	caption.text = item_title
	badge.text = "×%d" % count if count > 1 else ""
	queue_redraw()

func _draw() -> void:
	if not empty:
		return
	var center := Vector2(size.x * 0.5, 46.0)
	var radius := 21.0
	for i in range(12):
		var a0 := TAU * float(i) / 12.0
		var a1 := a0 + TAU / 24.0
		draw_arc(center, radius, a0, a1, 4, BunkerPanelStyle.BRASS.darkened(0.15), 2.0, true)
