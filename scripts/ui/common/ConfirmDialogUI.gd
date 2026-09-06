extends CanvasLayer
class_name ConfirmDialogUI
## Shared confirmation surface for build purchases, equipment replacement,
## settings restarts, and pause-menu exit. All callers use this one native
## Control implementation so confirmation UX cannot drift between systems.

signal confirmed()
signal cancelled()

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const NAV: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")

const PANEL_SIZE: Vector2 = Vector2(560.0, 304.0)
const SCREEN_MARGIN: Vector2 = Vector2(24.0, 24.0)

@export var stacking_layer: int = 70

var _is_open: bool = false
var _title_text: String = ""
var _message_text: String = ""
var _confirm_text: String = "Confirm"
var _cancel_text: String = "Cancel"
var _tone: String = "warning"
var _symbol: String = "warning"
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _previous_focus: WeakRef = null

var _root: Control = null
var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _icon_well: PanelContainer = null
var _icon: TextureRect = null
var _eyebrow: Label = null
var _title: Label = null
var _message_card: PanelContainer = null
var _message: Label = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _controller_nav: ControllerUINavigation = null


func _ready() -> void:
	layer = stacking_layer
	_build_interface()
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


## Optional arguments let each context communicate the real consequence while
## preserving the original two-argument API used by older callers.
## tone: "standard", "warning", "purchase", or "danger".
func open(title: String, message: String, confirm_label: String = "Confirm",
		cancel_label: String = "Cancel", tone: String = "warning",
		symbol: String = "warning") -> void:
	if not _is_open:
		_previous_mouse_mode = Input.mouse_mode
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		_previous_focus = weakref(focus_owner) if focus_owner != null else null
	_title_text = title
	_message_text = message
	_confirm_text = confirm_label
	_cancel_text = cancel_label
	_tone = tone
	_symbol = symbol
	_is_open = true
	visible = true
	_refresh_presentation()
	# A newly assigned wrapped message does not publish its final minimum size
	# until the container pass. Reapply the viewport-bounded dimensions on the
	# deferred frame, matching the proven first-open fix used by StorageUI.
	_layout()
	_layout.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIFade.fade_in(_root)
	## Confirmation dialogs should never default controller/keyboard focus to a
	## destructive action. Players can move right once to affirm deliberately.
	_cancel_button.call_deferred("grab_focus")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	_restore_previous_focus()


func is_open() -> bool:
	return _is_open


func _confirm() -> void:
	if not _is_open:
		return
	close()
	confirmed.emit()


func _cancel() -> void:
	if not _is_open:
		return
	close()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	var cancel_pressed: bool = event is InputEventKey and event.pressed \
		and event.keycode == KEY_ESCAPE
	cancel_pressed = cancel_pressed or (event is InputEventJoypadButton \
		and event.pressed and event.button_index == JOY_BUTTON_B)
	if cancel_pressed:
		_cancel()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "ConfirmationSurface"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	C.apply_theme(_root)
	add_child(_root)

	_backdrop = UIKit.build_modal_backdrop(0.48)
	_backdrop.name = "ModalBackdrop"
	_root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.name = "ConfirmationPanel"
	C.shell(_panel, 11)
	_root.add_child(_panel)

	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 11)
	_panel.add_child(C.inset(body, 20, 18, 20, 14))

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 13)
	body.add_child(header)

	_icon_well = C.icon_well("warning", 50.0, S.BRASS.lightened(0.25))
	header.add_child(_icon_well)
	_icon = _icon_well.get_node("Icon") as TextureRect

	var heading: VBoxContainer = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", 1)
	header.add_child(heading)
	_eyebrow = _label("CONFIRM ACTION", 11, S.BLUE)
	heading.add_child(_eyebrow)
	_title = _label("Confirm action", 24, S.IVORY)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_title)

	C.divider(body)

	_message_card = PanelContainer.new()
	_message_card.custom_minimum_size.y = 74.0
	body.add_child(_message_card)
	_message = _label("", 15, S.MUTED)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_card.add_child(C.inset(_message, 14, 10, 14, 10))

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	_cancel_button = Button.new()
	_cancel_button.name = "Cancel"
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.custom_minimum_size.y = 48.0
	_cancel_button.icon = S.icon("close")
	S.button(_cancel_button)
	_cancel_button.pressed.connect(_cancel)
	actions.add_child(_cancel_button)
	_confirm_button = Button.new()
	_confirm_button.name = "Confirm"
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.custom_minimum_size.y = 48.0
	_confirm_button.icon = S.icon("check")
	S.button(_confirm_button, true)
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 18)
	body.add_child(footer)
	C.key_hint(footer, "A / ENTER", "Select")
	C.key_hint(footer, "B / ESC", "Cancel")

	_controller_nav = NAV.new() as ControllerUINavigation
	_controller_nav.ui_root = self
	_controller_nav.close_on_cancel = false
	add_child(_controller_nav)


func _refresh_presentation() -> void:
	_title.text = _title_text
	_message.text = _message_text
	_message_card.visible = not _message_text.strip_edges().is_empty()
	_confirm_button.text = _confirm_text
	_cancel_button.text = _cancel_text
	_icon.texture = S.icon(_symbol)

	var accent: Color = S.BLUE
	var eyebrow_text: String = "CONFIRM ACTION"
	match _tone:
		"danger":
			accent = S.RED
			eyebrow_text = "IRREVERSIBLE ACTION"
			_style_confirm_button(accent, true)
		"purchase":
			accent = S.BRASS.lightened(0.34)
			eyebrow_text = "CONFIRM PURCHASE"
			_style_confirm_button(accent, false)
		"warning":
			accent = Color("e2a84f")
			eyebrow_text = "REVIEW CHANGE"
			_style_confirm_button(accent, false)
		_:
			_style_confirm_button(accent, false)
	_eyebrow.text = eyebrow_text
	_eyebrow.add_theme_color_override("font_color", accent)
	_icon.self_modulate = accent
	_message_card.add_theme_stylebox_override("panel", C.panel_box(
		Color("171d1c"), accent.darkened(0.48), 8, 1, 10))


func _style_confirm_button(accent: Color, danger: bool) -> void:
	var base: Color = Color("512923") if danger else accent.darkened(0.62)
	_confirm_button.add_theme_color_override("font_color", S.IVORY)
	_confirm_button.add_theme_color_override("font_hover_color", S.IVORY)
	_confirm_button.add_theme_color_override("font_pressed_color", S.IVORY)
	_confirm_button.add_theme_color_override("icon_normal_color", accent.lightened(0.16))
	_confirm_button.add_theme_color_override("icon_hover_color", S.IVORY)
	_confirm_button.add_theme_stylebox_override("normal", C.panel_box(base, accent.darkened(0.14), 7, 1, 10))
	_confirm_button.add_theme_stylebox_override("hover", C.panel_box(base.lightened(0.08), accent, 7, 1, 10))
	_confirm_button.add_theme_stylebox_override("pressed", C.panel_box(base.darkened(0.06), S.IVORY, 7, 2, 9))
	_confirm_button.add_theme_stylebox_override("focus", C.panel_box(Color.TRANSPARENT, S.IVORY, 8, 2))


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var requested_height: float = PANEL_SIZE.y if _message_card.visible else 224.0
	var target: Vector2 = Vector2(
		minf(PANEL_SIZE.x, maxf(360.0, viewport_size.x - SCREEN_MARGIN.x * 2.0)),
		minf(requested_height, maxf(200.0, viewport_size.y - SCREEN_MARGIN.y * 2.0))
	)
	_panel.custom_maximum_size = target
	_panel.position = (viewport_size - target) * 0.5
	_panel.size = target

func _restore_previous_focus() -> void:
	if _previous_focus == null:
		return
	var previous: Object = _previous_focus.get_ref()
	if previous is Control and is_instance_valid(previous):
		(previous as Control).call_deferred("grab_focus")
	_previous_focus = null


func _label(value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
