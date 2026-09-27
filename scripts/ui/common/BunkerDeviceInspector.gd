extends CanvasLayer
## Shared lifecycle for ordinary world-device inspectors ONLY.
## Always non-pausing; left stick/WASD remain gameplay movement. Every open
## binds a device or world position to the mandatory walk-away close helper.
signal closed

const W: GDScript = preload("res://scripts/ui/common/BunkerInspectorWidgets.gd")
const PRIORITY: GDScript = preload("res://scripts/ui/common/BunkerPriorityControl.gd")
const SHELL: PackedScene = preload("res://scenes/ui/common/DeviceInspectPanel.tscn")
const NAV: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const PROXIMITY: GDScript = preload("res://scripts/ui/common/UIProximityClose.gd")
const FADE: GDScript = preload("res://scripts/ui/common/UIFade.gd")
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

var _view: Control
var _details: VBoxContainer
var _statuses: HBoxContainer
var _footer: VBoxContainer
var _close_btn: Button
var _controller_nav: Node
var _proximity: Node
var _is_open: bool = false
var _previous_focus: WeakRef
var _refresh_elapsed: float = 0.0
var _controller_hints: bool = false
var _rail: Control
## Water/farm APIs are polled at their existing 10Hz, while open only.
## Signal-driven inspectors override this to 0 and call refresh themselves.
var refresh_interval: float = 0.1

func _ready() -> void:
	layer = 60
	visible = false
	_view = SHELL.instantiate() as Control
	add_child(_view)
	_details = _view.get_node("%Details") as VBoxContainer
	_statuses = _view.get_node("%StatusRow") as HBoxContainer
	_footer = _view.get_node("%Footer") as VBoxContainer
	_close_btn = _view.get_node("%Close") as Button
	var toast_shield: Control = _view.get_node_or_null("%Panel") as Control
	Q.avoid_toasts(toast_shield if toast_shield != null else _view, false)  # never covered by toasts
	_quiet_shell()
	_close_btn.pressed.connect(close)
	_controller_nav = NAV.new()
	_controller_nav.ui_root = self
	_controller_nav.stick_navigation = false
	add_child(_controller_nav)
	_proximity = PROXIMITY.new()
	_proximity.ui = self
	add_child(_proximity)
	_build_content()
	_view.call("_apply_metrics")
	set_process(false)

## Sep 2026 quiet pass: restyles the shared DeviceInspectPanel.tscn in the
## quiet language (QUIET_DESIGN_SYSTEM.md archetype B) without changing its
## node contract. Header = brass eyebrow + title + text "Close"; hairline
## dividers; quiet scrollbar; a FocusRail behind the content shows focus;
## key hints replace the old sentence footer.
func _quiet_shell() -> void:
	_rail = W.quiet_shell(_view, _close_btn)
	_footer.set_meta("ui_gap", 12)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

func _on_focus_changed(control: Control) -> void:
	if _is_open and control != null and _view.is_ancestor_of(control):
		## "Close" carries its own quiet wash; the rail marks content targets.
		_rail.call("set_target", null if control == _close_btn else control)

func _build_content() -> void:
	pass

func _refresh_data() -> void:
	pass

func _open_device(title: String, domain: String, _symbol: String, target: Node3D = null,
		anchor: Vector3 = Vector3.INF, height: float = 740.0) -> void:
	if not _is_open:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	if is_instance_valid(target):
		_proximity.bind_target(target)
	else:
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		var position: Vector3 = anchor
		if not position.is_finite():
			position = player.global_position if is_instance_valid(player) else Vector3.ZERO
		_proximity.bind_position(position)
	(_view.get_node("%Title") as Label).text = title
	(_view.get_node("%Eyebrow") as Label).text = domain.to_upper()
	_view.set("panel_height", height)
	_is_open = true
	UIPanelLifecycle.prepare_open(self)
	visible = true
	_refresh_elapsed = 0.0
	_refresh_data()
	_update_input_hints()
	## Only the panel height changes per device; full metrics (theme edits →
	## ~45 ms relayout) rerun on resize via the layout's own `resized` hook.
	_view.call("_fit_panel")
	_close_btn.grab_focus()
	_rail.call("set_target", null)
	_rail.call("snap")
	(_view.get_node("%DetailsScroll") as ScrollContainer).set_deferred("scroll_vertical", 0)
	set_process(true)
	FADE.fade_in(_view)

func is_open() -> bool:
	return _is_open

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if _proximity != null:
		_proximity.unbind()
	for node: Node in _view.find_children("*", "OptionButton", true, false):
		(node as OptionButton).get_popup().hide()
	set_process(false)
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and _view.is_ancestor_of(focus):
		focus.release_focus()
		if _previous_focus != null:
			var previous: Control = _previous_focus.get_ref() as Control
			if is_instance_valid(previous) and previous.is_visible_in_tree():
				previous.grab_focus()
	UIPanelLifecycle.dismiss(self, _view)
	closed.emit()

func _process(delta: float) -> void:
	if _controller_hints != InputMode.is_controller():
		_update_input_hints()
	if refresh_interval <= 0.0:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= refresh_interval:
		_refresh_elapsed = 0.0
		_refresh_data()

func _update_input_hints() -> void:
	_controller_hints = InputMode.is_controller()
	var hint: Label = _view.get_node("%NavigationHint") as Label
	hint.text = "[A] Select · D-pad / R-stick: navigate · [B] Close" if _controller_hints else "Enter / Space: select · Esc / E: close"
	hint.add_theme_color_override("font_color", Q.MUTED)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not _controller_nav._is_topmost():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()

func _add_priority(parent: Node, callback: Callable) -> VBoxContainer:
	var control: VBoxContainer = PRIORITY.new()
	control.name = "Priority"
	parent.add_child(control)
	control.priority_requested.connect(callback)
	return control
