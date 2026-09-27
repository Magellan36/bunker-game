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
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

const PANEL_SIZE: Vector2 = Vector2(520.0, 250.0)
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
	UIPanelLifecycle.prepare_open(self)
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
	Input.mouse_mode = _previous_mouse_mode
	_restore_previous_focus()
	UIPanelLifecycle.dismiss(self, _root)


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
		and event.keycode in [KEY_ESCAPE, KEY_E]
	cancel_pressed = cancel_pressed or (event is InputEventJoypadButton \
		and event.pressed and event.button_index == JOY_BUTTON_B)
	if cancel_pressed:
		_cancel()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	# Quiet dialog (Sep 2026, QUIET_DESIGN_SYSTEM §3 "Dialog"): eyebrow, title,
	# message, one row of [key hints … Cancel  Confirm]. No icon well, no
	# bordered buttons. Cancel keeps default focus (never a destructive action).
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
	_panel.add_theme_stylebox_override("panel", Q.dialog_box())
	Q.avoid_toasts(_panel, true)
	_root.add_child(_panel)

	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_panel.add_child(body)

	_eyebrow = Q.eyebrow("Confirm", 12)
	body.add_child(_eyebrow)
	_title = Q.label("Confirm action", 22, Q.TEXT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_title)

	_message_card = PanelContainer.new()
	_message_card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(_message_card)
	_message = Q.label("", 15, Q.MUTED)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_card.add_child(_message)

	var gap: Control = Control.new()
	gap.custom_minimum_size.y = 8.0
	body.add_child(gap)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	var hints: HBoxContainer = HBoxContainer.new()
	hints.add_theme_constant_override("separation", 16)
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hints)
	C.key_hint(hints, "ENTER", "Select", "ENTER", "A")
	C.key_hint(hints, "ESC", "Cancel", "ESC", "B")
	_cancel_button = Button.new()
	_cancel_button.name = "Cancel"
	Q.nav_button(_cancel_button, 15, 40.0)
	_cancel_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel_button.add_theme_stylebox_override("focus", Q.focus_underline())
	_cancel_button.pressed.connect(_cancel)
	actions.add_child(_cancel_button)
	_confirm_button = Button.new()
	_confirm_button.name = "Confirm"
	Q.primary_action(_confirm_button, 15, 40.0)
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)

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
	# `symbol` is accepted for API compatibility; the quiet dialog has no icon.
	var eyebrow_text: String = "Confirm"
	var eyebrow_color: Color = Q.HEADING
	match _tone:
		"danger":
			eyebrow_text = "Cannot be undone"
			eyebrow_color = BunkerDesign.RED
		"purchase":
			eyebrow_text = "Confirm purchase"
		"warning":
			eyebrow_text = "Review change"
			eyebrow_color = BunkerDesign.WARNING
	_eyebrow.text = eyebrow_text.to_upper()
	_eyebrow.add_theme_color_override("font_color", eyebrow_color)
	Q.primary_action(_confirm_button, 15, 40.0, _tone == "danger")


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# Fit the content (no dead space under the actions), capped by PANEL_SIZE.
	_panel.custom_minimum_size = Vector2.ZERO
	var content_height: float = _panel.get_combined_minimum_size().y
	var requested_height: float = minf(maxf(content_height, 140.0), PANEL_SIZE.y)
	UIPanelLayout.fit(_panel, viewport_size,
		Vector2(PANEL_SIZE.x, requested_height), SCREEN_MARGIN)

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
