class_name BunkerItemCard
extends Button

const PREVIEW_MOTION: GDScript = preload("res://scripts/ui/common/UIPreviewMotion.gd")
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

## Compact storage-slot tile (Sep 2026 quiet pass, `Q.tile`): a flat preview
## well and a centred caption, no borders. Selection = ACCENT underline +
## ivory name; the count reads as plain "×N" text. Empty slots keep a faint
## dotted ring so the grid's shape stays legible.

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
	custom_minimum_size = Vector2(118, 126)
	Q.tile(self)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	var inset := BunkerUIComponents.inset(stack, 6, 6, 6, 6)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inset)

	var preview_well := PanelContainer.new()
	preview_well.name = "PreviewWell"
	preview_well.custom_minimum_size.y = 78
	preview_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stack.add_child(preview_well)
	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_well.add_child(preview_layer)
	preview = TextureRect.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.add_child(preview)
	empty_marker = Control.new()
	empty_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_marker.draw.connect(_draw_empty_marker)
	preview_layer.add_child(empty_marker)
	## Count: plain text top-right (no pill). The panel stays as its holder.
	_badge_panel = PanelContainer.new()
	_badge_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge_panel.offset_left = -43
	_badge_panel.offset_top = 2
	_badge_panel.offset_right = -2
	_badge_panel.offset_bottom = 22
	_badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	preview_layer.add_child(_badge_panel)
	badge = Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", Q.MUTED)
	badge.add_theme_font_size_override("font_size", 13)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_panel.add_child(badge)

	var copy := VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.custom_minimum_size.y = 24
	copy.add_theme_constant_override("separation", 0)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(copy)
	_slot_eyebrow = Label.new()
	_slot_eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_slot_eyebrow)
	_slot_eyebrow.hide()
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Q.MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(caption)
	toggled.connect(func(_on: bool) -> void: _sync_caption())
	focus_entered.connect(_sync_caption)
	focus_exited.connect(_sync_caption)
	display("Empty", null, 0)


## `occupied`: 1/0 states it explicitly (PreviewStudio renders can arrive a
## frame later, so a null texture no longer means "empty"); -1 infers it
## from the texture as before.
func display(item_title: String, texture: Texture2D, count: int = 1, occupied: int = -1) -> void:
	var now_empty: bool = texture == null if occupied < 0 else occupied == 0
	var changed: bool = caption.text != item_title or empty != now_empty
	empty = now_empty
	PREVIEW_MOTION.swap(preview, empty_marker if empty else null, texture, changed)
	caption.text = "Empty" if empty else item_title
	_slot_eyebrow.text = ""
	badge.text = "×%d" % count
	_badge_panel.visible = not empty and count > 1
	if not changed:
		empty_marker.visible = empty
	empty_marker.queue_redraw()
	_sync_caption()


## PreviewStudio.bind_card target: the static render or the hover spinner.
func set_preview(texture: Texture2D) -> void:
	if empty:
		return
	PREVIEW_MOTION.swap(preview, null, texture)


## Name brightens when the tile is selected or focused; empty stays faint.
func _sync_caption() -> void:
	if caption == null:
		return
	var lit: bool = not empty and (button_pressed or has_focus())
	caption.add_theme_color_override("font_color", Q.FAINT if empty else (Q.TEXT if lit else Q.MUTED))


func _draw_empty_marker() -> void:
	if not empty or empty_marker == null:
		return
	var center := empty_marker.size * 0.5
	var radius := 16.0
	for i in range(12):
		var a0 := TAU * float(i) / 12.0
		var a1 := a0 + TAU / 36.0
		empty_marker.draw_arc(center, radius, a0, a1, 3, Color(Q.HEADING, 0.35), 1.5, true)
