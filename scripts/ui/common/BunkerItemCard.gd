class_name BunkerItemCard
extends Button

const PREVIEW_MOTION: GDScript = preload("res://scripts/ui/common/UIPreviewMotion.gd")

## Compact storage-slot card. Empty slots retain the approved dashed marker;
## occupied slots use the same preview-well/information-band grammar as the
## Build and Shop catalogs.

var preview: TextureRect
var caption: Label
var badge: Label
var empty_marker: Control
var empty: bool = true

var _badge_panel: PanelContainer
var _slot_eyebrow: Label


func _ready() -> void:
	text = ""
	toggle_mode = true
	clip_text = true
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BunkerUIComponents.style_segment(self)
	custom_minimum_size = Vector2(118, 144)
	add_theme_stylebox_override("normal", BunkerUIComponents.panel_box(
		Color("181e1d"), BunkerPanelStyle.BRASS.darkened(0.32), 8, 1, 5))
	add_theme_stylebox_override("hover", BunkerUIComponents.panel_box(
		Color("20292a"), BunkerPanelStyle.BLUE.darkened(0.24), 8, 1, 5))
	add_theme_stylebox_override("pressed", BunkerUIComponents.panel_box(
		Color("1b2e38"), BunkerPanelStyle.BLUE, 8, 2, 4))
	add_theme_stylebox_override("hover_pressed", BunkerUIComponents.panel_box(
		Color("203642"), BunkerPanelStyle.BLUE, 8, 2, 4))

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	var inset := BunkerUIComponents.inset(stack, 5, 5, 5, 5)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inset)

	var preview_well := PanelContainer.new()
	preview_well.name = "PreviewWell"
	preview_well.custom_minimum_size.y = 91
	preview_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("2a302f"), BunkerPanelStyle.BRASS.darkened(0.40), 6, 1, 4))
	stack.add_child(preview_well)
	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_child(preview_layer)
	preview = TextureRect.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.add_child(preview)
	empty_marker = Control.new()
	empty_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_marker.draw.connect(_draw_empty_marker)
	preview_layer.add_child(empty_marker)
	_badge_panel = PanelContainer.new()
	_badge_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge_panel.offset_left = -43
	_badge_panel.offset_top = 6
	_badge_panel.offset_right = -6
	_badge_panel.offset_bottom = 30
	_badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_panel.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("17232a"), BunkerPanelStyle.BLUE.darkened(0.22), 11, 1, 4))
	preview_layer.add_child(_badge_panel)
	badge = Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	badge.add_theme_font_size_override("font_size", 11)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_panel.add_child(badge)

	var info_band := PanelContainer.new()
	info_band.custom_minimum_size.y = 38
	info_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_band.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("202625"), BunkerPanelStyle.BRASS.darkened(0.44), 6, 1, 4))
	stack.add_child(info_band)
	var copy := VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_band.add_child(copy)
	_slot_eyebrow = Label.new()
	_slot_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_eyebrow.add_theme_font_size_override("font_size", 8)
	_slot_eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	_slot_eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_slot_eyebrow)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(caption)
	display("Empty slot", null, 0)


func display(item_title: String, texture: Texture2D, count: int = 1) -> void:
	var changed: bool = caption.text != item_title or empty != (texture == null)
	empty = texture == null
	PREVIEW_MOTION.swap(preview, empty_marker, texture, changed)
	caption.text = "Empty slot" if empty else item_title
	_slot_eyebrow.text = "AVAILABLE" if empty else "STORED ITEM"
	_slot_eyebrow.add_theme_color_override("font_color",
		BunkerPanelStyle.BRASS.lightened(0.12) if empty else BunkerPanelStyle.BLUE)
	caption.add_theme_color_override("font_color",
		BunkerPanelStyle.MUTED.darkened(0.12) if empty else BunkerPanelStyle.IVORY)
	badge.text = "×%d" % count
	_badge_panel.visible = not empty and count > 1
	if not changed:
		empty_marker.visible = empty
	empty_marker.queue_redraw()


func _draw_empty_marker() -> void:
	if not empty or empty_marker == null:
		return
	var center := empty_marker.size * 0.5
	var radius := 22.0
	for i in range(12):
		var a0 := TAU * float(i) / 12.0
		var a1 := a0 + TAU / 24.0
		empty_marker.draw_arc(center, radius, a0, a1, 4,
			BunkerPanelStyle.BRASS.darkened(0.10), 2.0, true)
