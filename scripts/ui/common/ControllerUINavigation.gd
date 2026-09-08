class_name ControllerUINavigation
extends Node
## ControllerUINavigation.gd
## Reusable gamepad navigation for Control-based UIs (Aug 2026).
##
## Attach as a child of any Control tree you want to drive with a
## controller (or point ui_root at it):
##   - D-pad:     moves focus one step in the pressed cardinal direction.
##   - Right stick: duplicates d-pad navigation and adjusts focused sliders.
##   - Left stick: never changes UI focus; it remains a gameplay axis.
##   - Scrollbars: are focusable controls; up/down scrolls while focused.
##   - A (ui_accept): activates the focused button (Godot default).
##   - B (ui_cancel): closes this UI (close_on_cancel, topmost-only).
## ui_root can be a Control or a CanvasLayer (e.g. a full-screen menu).
##
## This consumes joypad movement events in _input() BEFORE Godot's built-in
## focus navigation, for two reasons:
##   1. It lets the right stick pick a button by analog direction (not just
##      the four cardinal ui_* actions).
##   2. Consumed events never reach _unhandled_input handlers — so while a
##      UI with this node is open, the d-pad/stick cannot also trigger other
##      gamepad actions (e.g. InteractionSystem's inventory cycling).
##      Attach this node to any modal/full-screen UI that should own the pad.
##
## Mouse behavior remains native. Keyboard arrows remain native except while
## a scrollbar owns focus, where they adjust that scrollbar explicitly.

@export var ui_root: Node = null
@export var stick_deadzone: float = 0.6   ## stick magnitude needed to register a directional move
@export var move_repeat_delay: float = 0.22   ## seconds between auto-moves while a direction is held
## When true, B closes this UI (calls ui_root.close() if it has one, else
## hides it). Only the TOPMOST open controller UI closes on a B press, so
## e.g. B in the Settings panel (layer 210) closes Settings but not the
## Pause menu (layer 200) underneath. Set false for UIs that must not be
## closed by the pad (character creation).
@export var close_on_cancel: bool = true
## Deprecated compatibility property. Left-stick focus is hard-blocked on
## every UI; callers should leave this false.
@export var stick_navigation: bool = false
## Most UIs use the right stick as a second D-pad. Build Mode is the one
## deliberate exception: its existing virtual pointer owns the right stick,
## while this helper continues to provide spatial D-pad focus navigation.
@export var right_stick_navigation: bool = true
## Whether an active instance should pause a world-space virtual cursor.
## BuildWorkspace sets this false because its UI and build-world cursor are
## designed to coexist; modal inspectors and menus retain the safe default.
@export var blocks_world_cursor: bool = true
## Whether keyboard/mouse mode needs the OS cursor while this navigation
## surface is active. Build switches this off during world placement because
## its established in-world tool cursor owns pointing there; normal menus and
## inspectors retain the visible-cursor default.
@export var mouse_cursor_required: bool = true

const DPAD_UP: int    = 11
const DPAD_DOWN: int  = 12
const DPAD_LEFT: int  = 13
const DPAD_RIGHT: int = 14
## Group every attached nav registers in, used to determine the topmost
## open controller UI for B-close.
const NAV_GROUP: String = "controller_ui_nav"

## Minimum alignment (dot product) between the pressed direction and the
## candidate's direction for it to count — keeps a diagonal press from
## snapping to something almost directly behind the current focus.
const MIN_DIR_DOT: float = 0.3

## Slider d-pad hold-repeat (Aug 2026): a focused Slider owns horizontal
## d-pad (one step per press; left/right). Holding a direction for the first
## second does nothing extra, then repeats start and ACCELERATE toward
## SLIDER_MIN_INTERVAL (100 steps/sec) over SLIDER_RAMP_TIME.
const SLIDER_HOLD_DELAY: float    = 0.35
const SLIDER_START_INTERVAL: float = 0.12     ## ~5 steps/sec when repeat kicks in
const SLIDER_MIN_INTERVAL: float   = 0.05    ## 100 steps/sec
const SLIDER_RAMP_TIME: float      = 3.0     ## seconds of holding to reach max rate
## While held, each repeat's STEP also ramps from 1× the slider's step up to
## this multiplier — so the flow-rate slider (step = 1 mL/day) accelerates
## 1 → 500 mL/day per repeat, letting a player sweep a large range quickly.
const SLIDER_REPEAT_MAX_STEP_MULT: float = 500.0

static var _open_serial: int = 0
var _open_order: int = 0
## Optional context-specific tabs (Build switches between tools and categories).
var tab_provider: Callable
var _held_focus: WeakRef
var _stick_hold_time: float = 0.0
var _was_active: bool = false
var _move_cooldown: float = 0.0
var _stick_direction := Vector2.ZERO
var _prepare_elapsed := 0.0

## Slider auto-repeat state.
var _slider_repeat_dir: int    = 0
var _slider_hold_time: float   = 0.0
var _slider_interval: float    = SLIDER_START_INTERVAL
var _slider_repeat_timer: float = 0.0
var _slider_step_mult: float   = 1.0

func _ready() -> void:
	if ui_root == null:
		ui_root = get_parent()
	if ui_root == null:
		push_warning("ControllerUINavigation: no ui_root set — parent it under a Control/CanvasLayer or set ui_root.")
	add_to_group(NAV_GROUP)
	mark_open()
	if ui_root.has_signal("visibility_changed"):
		ui_root.connect("visibility_changed", _on_visibility_changed)
	## Ensure A = confirm and B = cancel on the Godot built-in actions.
	## This project's ui_accept/ui_cancel were customized to keyboard-only,
	## so a focused button would never activate from the pad without this.
	## Idempotent — only adds the joypad event if it's missing.
	_ensure_action_button("ui_accept", JOY_BUTTON_A)
	_ensure_action_button("ui_cancel", JOY_BUTTON_B)

func mark_open() -> void:
	_open_serial += 1
	_open_order = _open_serial
	_move_cooldown = 0.0
	_slider_repeat_dir = 0
	_stick_hold_time = 0.0

func _on_visibility_changed() -> void:
	if _active():
		mark_open()

func _ensure_action_button(action: String, idx: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == idx:
			return
	var ne := InputEventJoypadButton.new()
	ne.button_index = idx
	InputMap.action_add_event(action, ne)

func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown -= delta
	if not _active():
		_was_active = false
		_slider_repeat_dir = 0
		return
	if not _is_topmost():
		## A higher-layer controller UI is open — it owns the pad.
		_slider_repeat_dir = 0
		return
	if not _was_active:
		_was_active = true
		mark_open()
	_stick_hold_time += delta
	_prepare_elapsed += delta
	if _prepare_elapsed >= 0.25:
		_prepare_elapsed = 0.0
		_prepare_scrollbars(ui_root)
	_tick_slider_repeat(delta)
	if right_stick_navigation:
		_try_stick_move(delta)

func _input(event: InputEvent) -> void:
	if not _active():
		return
	## A HIGHER-layer open controller UI owns the pad while it's open —
	## back off (consume nothing) so it receives d-pad/B/A (e.g. the pause
	## menu's nav must not eat B/d-pad while a confirm dialog is stacked
	## above it).
	if not _is_topmost():
		return
	## PopupMenu is its own temporary focus surface. Let its native d-pad,
	## A/B, and keyboard behavior run; only consume right-stick motion here
	## because _process() mirrors that motion onto the popup's focused item.
	var open_popup := _visible_popup()
	if open_popup != null:
		if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X,
				JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			get_viewport().set_input_as_handled()
		return
	## Godot's default ui_left/right/up/down actions include the left stick.
	## Consume those motion events before GUI focus sees them. Input action
	## state is still polled by Player, so ordinary inspector movement and
	## walk-away closing remain intact.
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and close_on_cancel \
			and event.keycode in [KEY_ESCAPE, KEY_E]:
		get_viewport().set_input_as_handled()
		_close_ui()
		return
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		if _cycle_tabs(-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1):
			get_viewport().set_input_as_handled()
			return
	## B — close/cancel this UI. Only the topmost open controller UI closes
	## (see _is_topmost), so stacked UIs cancel one at a time. B is consumed
	## ONLY when it actually closes — a close_on_cancel=false nav lets B fall
	## through to the UI's own _unhandled_input (e.g. ConfirmDialogUI needs B
	## to emit its cancelled signal).
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed:
		if close_on_cancel:
			get_viewport().set_input_as_handled()
			_close_ui()
		return
	## D-pad — direct cardinal move, one step per press.
	if event is InputEventJoypadButton and event.pressed:
		var dir := Vector2.ZERO
		match event.button_index:
			DPAD_UP:    dir = Vector2(0.0, -1.0)
			DPAD_DOWN:  dir = Vector2(0.0, 1.0)
			DPAD_LEFT:  dir = Vector2(-1.0, 0.0)
			DPAD_RIGHT: dir = Vector2(1.0, 0.0)
		if dir != Vector2.ZERO:
			if _adjust_focused_range(dir, 1.0):
				## A focused Slider owns horizontal d-pad (Aug 2026): one step
				## now, then a held direction auto-repeats with acceleration —
				## see _tick_slider_repeat().
				if dir.y == 0.0 and _is_focused_slider():
					_start_slider_repeat(int(dir.x))
				get_viewport().set_input_as_handled()
				return
			## If this UI has no focusable controls (hand-drawn panels), let
			## d-pad fall through so the UI can handle it itself.
			if _collect_focusables().is_empty():
				return
			_move_focus(dir)
			get_viewport().set_input_as_handled()
			return
	## Right stick owns analog UI navigation.
	## focus navigation doesn't also act; the actual move is polled in
	## _process() so a held stick keeps repeating.
	if right_stick_navigation and event is InputEventJoypadMotion and \
			(event.axis == JOY_AXIS_RIGHT_X or event.axis == JOY_AXIS_RIGHT_Y):
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed:
		var key_dir := Vector2.ZERO
		match event.keycode:
			KEY_UP: key_dir = Vector2.UP
			KEY_DOWN: key_dir = Vector2.DOWN
			KEY_LEFT: key_dir = Vector2.LEFT
			KEY_RIGHT: key_dir = Vector2.RIGHT
		if key_dir != Vector2.ZERO and _adjust_focused_range(key_dir, 1.0):
			get_viewport().set_input_as_handled()
			return

func _active() -> bool:
	if not is_instance_valid(ui_root) or not ui_root.is_inside_tree():
		return false
	if ui_root.get_meta(&"ui_exiting", false) == true:
		return false
	if ui_root.has_method("is_open"):
		return ui_root.call("is_open") == true and _node_visible(ui_root)
	if "is_open" in ui_root:
		return ui_root.get("is_open") == true and _node_visible(ui_root)
	return _node_visible(ui_root)

## Public wrapper for the visibility check — other systems ask "is this UI
## open right now?" via this (e.g. InteractionSystem gates A's world
## fall-through while ANY controller-nav UI is open, so a press can't open a
## different UI by mistake).
func is_active() -> bool:
	return _active()

## Public close request used when another exclusive workspace takes ownership
## (for example Build Mode dismissing an open Storage inspector). Keeping the
## dispatch here preserves each screen's own close cleanup and exit animation.
func request_close() -> void:
	_close_ui()

static func owns_directional_input(tree: SceneTree) -> bool:
	if tree == null:
		return false
	for candidate: Node in tree.get_nodes_in_group(NAV_GROUP):
		if candidate.has_method("is_active") and bool(candidate.call("is_active")):
			return true
	return false

## True only when an active navigation surface explicitly needs the world
## cursor paused. This is narrower than owns_directional_input(): Build Mode
## still owns D-pad focus while allowing its right-stick pointer to move.
static func blocks_world_cursor_input(tree: SceneTree) -> bool:
	if tree == null:
		return false
	for candidate: Node in tree.get_nodes_in_group(NAV_GROUP):
		if candidate.has_method("is_active") and bool(candidate.call("is_active")) \
				and bool(candidate.get("blocks_world_cursor")):
			return true
	return false

## Robust visibility check that works for both Control roots and
## CanvasLayer roots (CanvasLayer is a Node, NOT a CanvasItem — it has no
## is_visible_in_tree()).
func _node_visible(n: Node) -> bool:
	if n is Control:
		return (n as Control).is_visible_in_tree()
	if "visible" in n:
		return bool(n.get("visible"))
	return false

## Closes the UI the nav drives. Prefers a real close() method (proper
## cleanup like unlocking player movement / restoring mouse mode); falls back
## to hide() for simple show/hide UIs.
func _close_ui() -> void:
	if ui_root == null:
		return
	if ui_root.has_method("close"):
		ui_root.call("close")
	elif ui_root.has_method("hide"):
		ui_root.call("hide")

## Effective render-layer of this nav's UI: walks up from ui_root to the
## nearest CanvasLayer and returns its layer (0 for plain Controls).
func _effective_layer() -> int:
	var n: Node = ui_root
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0

## True when this nav's UI is the topmost OPEN controller UI — no other
## visible nav UI has a higher effective layer. Used so B closes only the
## topmost UI when several are stacked (pause + settings).
func _is_topmost() -> bool:
	var my_layer := _effective_layer()
	for other: Node in get_tree().get_nodes_in_group(NAV_GROUP):
		if other == self or not "ui_root" in other:
			continue
		var oroot: Node = other.get("ui_root")
		if is_instance_valid(oroot) and other.call("is_active") == true:
			var other_layer: int = other.call("_effective_layer")
			if other_layer > my_layer or (other_layer == my_layer and int(other.get("_open_order")) > _open_order):
				return false
	return true

func _try_stick_move(_delta: float) -> void:
	if _move_cooldown > 0.0:
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() < stick_deadzone:
		_stick_direction = Vector2.ZERO
		_stick_hold_time = 0.0
		return
	var direction := Vector2(signf(stick.x), 0.0) if absf(stick.x) > absf(stick.y) else Vector2(0.0, signf(stick.y))
	if direction != _stick_direction:
		_stick_hold_time = 0.0
	_stick_direction = direction
	var popup := _visible_popup()
	if popup != null:
		_move_popup(popup, int(direction.y if direction.y != 0.0 else direction.x))
		_move_cooldown = move_repeat_delay
		return
	if not _adjust_focused_range(direction, _range_multiplier(_stick_hold_time)):
		_move_focus(direction)
	else:
		_move_cooldown = 0.07

func _visible_popup() -> PopupMenu:
	if ui_root == null:
		return null
	var focus := get_viewport().gui_get_focus_owner()
	if focus is OptionButton:
		var focused_popup := (focus as OptionButton).get_popup()
		if focused_popup.visible:
			return focused_popup
	for focusable in _collect_focusables():
		if focusable is OptionButton:
			var popup := (focusable as OptionButton).get_popup()
			if popup.visible:
				return popup
	for candidate in ui_root.find_children("*", "PopupMenu", true, false):
		if candidate is PopupMenu and (candidate as PopupMenu).visible:
			return candidate as PopupMenu
	return null

func _move_popup(popup: PopupMenu, direction: int) -> void:
	var count := popup.get_item_count()
	if direction == 0 or count == 0:
		return
	var index := popup.get_focused_item()
	if index < 0:
		index = 0 if direction > 0 else count - 1
	for _attempt in count:
		index = wrapi(index + direction, 0, count)
		if not popup.is_item_disabled(index) and not popup.is_item_separator(index):
			popup.set_focused_item(index)
			return

## Prefer controls in the same visible row/column, then the nearest diagonal.
## Explicit neighbors remain authoritative for physical slot grids.
func _move_focus(dir: Vector2) -> void:
	if _move_cooldown > 0.0:
		return
	var focusables := _collect_focusables()
	if focusables.is_empty():
		return
	var current := get_viewport().gui_get_focus_owner()
	var has_current: bool = current is Control and current.is_inside_tree() and _is_descendant(current as Control, ui_root)
	var from := Vector2.ZERO
	if has_current:
		from = (current as Control).get_global_rect().get_center()
		var explicit: Control = _explicit_neighbor(current as Control, dir)
		if explicit != null:
			if explicit != current:
				explicit.grab_focus()
			_move_cooldown = move_repeat_delay
			return

	var ndir: Vector2 = dir.normalized()
	var best: Control = null
	var best_score: float = INF
	## Anchor for the no-current-focus case: the UI root's center when it's a
	## Control, else the origin (CanvasLayer roots have no rect).
	var base := Vector2.ZERO
	if ui_root is Control:
		base = (ui_root as Control).get_global_rect().get_center()
	for entry in focusables:
		var c: Control = entry as Control
		if c == null or (has_current and c == current):
			continue
		var to: Vector2 = c.get_global_rect().get_center()
		var delta: Vector2 = to - (from if has_current else base)
		var dist: float = delta.length()
		if dist < 0.001:
			continue
		var dot: float = delta.normalized().dot(ndir)
		if not has_current:
			## No current focus — accept anything in the general direction.
			dot = maxf(dot, 0.0)
		if dot < MIN_DIR_DOT:
			continue
		var along: float = delta.dot(ndir)
		var perp: float = (delta - ndir * along).length()
		var score: float = along + perp * 4.0
		# Controls overlapping on the perpendicular axis belong to the same
		# visual row/column. Prefer that lane before crossing into another.
		if has_current:
			var here: Rect2 = current.get_global_rect()
			var there: Rect2 = c.get_global_rect()
			var aligned: bool = (there.position.y < here.end.y and there.end.y > here.position.y) \
				if dir.x != 0 else (there.position.x < here.end.x and there.end.x > here.position.x)
			if not aligned:
				score += 10000.0
		if score < best_score:
			best_score = score
			best = c

	if best == null:
		## Nothing valid in that direction: fall back to the first focusable
		## when there is no current focus, otherwise stay put.
		if not has_current and not focusables.is_empty():
			best = focusables[0]
	if best == null:
		return
	best.grab_focus()
	_move_cooldown = move_repeat_delay


func _explicit_neighbor(current: Control, dir: Vector2) -> Control:
	var path := NodePath()
	if absf(dir.x) > absf(dir.y):
		path = current.focus_neighbor_right if dir.x > 0.0 else current.focus_neighbor_left
	else:
		path = current.focus_neighbor_bottom if dir.y > 0.0 else current.focus_neighbor_top
	if path.is_empty():
		return null
	if path == NodePath("."):
		return current
	var candidate: Control = current.get_node_or_null(path) as Control
	if candidate == null or candidate.focus_mode == Control.FOCUS_NONE \
			or not candidate.is_visible_in_tree():
		return current
	if "disabled" in candidate and bool(candidate.get("disabled")):
		return current
	return candidate

# ─── Slider d-pad support (Aug 2026) ──────────────────────────────────────────
func _is_focused_slider() -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	return f is Slider

func _adjust_focused_slider(dir: int, step_mult: float = 1.0) -> void:
	var f: Control = get_viewport().gui_get_focus_owner()
	if not (f is Slider):
		return
	var sl: Slider = f as Slider
	var step: float = sl.step if sl.step > 0.0 else 1.0
	sl.value = clampf(sl.value + step * step_mult * float(dir), sl.min_value, sl.max_value)

func _adjust_focused_range(dir: Vector2, multiplier: float) -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is VScrollBar:
		var bar := focus as VScrollBar
		if dir.y == 0.0:
			return false
		UIScrollMotion.step_by(bar, 42.0 * multiplier * dir.y)
		return true
	if focus is HScrollBar:
		var bar := focus as HScrollBar
		if dir.x == 0.0:
			return false
		UIScrollMotion.step_by(bar, 42.0 * multiplier * dir.x)
		return true
	if focus is Slider:
		var vertical := focus is VSlider
		var component := -dir.y if vertical else dir.x
		if component == 0.0:
			return false
		_adjust_focused_slider(int(component), multiplier)
		return true
	return false

func _prepare_scrollbars(node: Node) -> void:
	if node is ScrollContainer:
		var scroll := node as ScrollContainer
		for bar: ScrollBar in [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]:
			if not bar.has_meta(&"shared_scrollbar_skin"):
				bar.set_meta(&"shared_scrollbar_skin", true)
				for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
					bar.add_theme_stylebox_override(state, BunkerControlTheme.scrollbar_style(state))
			var useful := bar.visible and bar.max_value > bar.page + 0.5
			bar.focus_mode = Control.FOCUS_ALL if useful else Control.FOCUS_NONE
			if not bar.has_meta(&"scroll_drag_wired"):
				bar.set_meta(&"scroll_drag_wired", true)
				bar.gui_input.connect(UIScrollMotion.on_drag.bind(bar))
			if useful:
				bar.custom_minimum_size.x = maxf(bar.custom_minimum_size.x, 16.0)
				bar.add_theme_stylebox_override("focus", BunkerPanelStyle.box(Color.TRANSPARENT, BunkerPanelStyle.IVORY, 5, 2))
	for child in node.get_children():
		_prepare_scrollbars(child)

func _start_slider_repeat(dir: int) -> void:
	_held_focus = weakref(get_viewport().gui_get_focus_owner())
	_slider_repeat_dir   = dir
	_slider_hold_time    = 0.0
	_slider_interval     = SLIDER_START_INTERVAL
	_slider_repeat_timer = 0.0
	_slider_step_mult    = 1.0

## Polled every frame: while a d-pad direction is held on a focused Slider,
## nothing happens during the first SLIDER_HOLD_DELAY (the initial press
## already stepped once), then the value repeats at an interval that ramps
## from SLIDER_START_INTERVAL up to SLIDER_MIN_INTERVAL (100 steps/sec) while
## each step simultaneously ramps from 1× the slider's step up to
## SLIDER_REPEAT_MAX_STEP_MULT (e.g. 1 → 500 mL/day on the flow-rate slider).
func _tick_slider_repeat(delta: float) -> void:
	if _slider_repeat_dir == 0:
		return
	if not _is_focused_slider() or _held_focus == null or _held_focus.get_ref() != get_viewport().gui_get_focus_owner():
		_slider_repeat_dir = 0
		return
	var held_btn: int = JOY_BUTTON_DPAD_LEFT if _slider_repeat_dir < 0 else JOY_BUTTON_DPAD_RIGHT
	if not Input.is_joy_button_pressed(0, held_btn):
		_slider_repeat_dir = 0
		return
	_slider_hold_time += delta
	if _slider_hold_time < SLIDER_HOLD_DELAY:
		return
	var t: float = clampf((_slider_hold_time - SLIDER_HOLD_DELAY) / SLIDER_RAMP_TIME, 0.0, 1.0)
	_slider_interval  = lerpf(SLIDER_START_INTERVAL, SLIDER_MIN_INTERVAL, t)
	_slider_step_mult = _range_multiplier(_slider_hold_time)
	_slider_repeat_timer -= delta
	if _slider_repeat_timer <= 0.0:
		_adjust_focused_slider(_slider_repeat_dir, _slider_step_mult)
		_slider_repeat_timer = _slider_interval

func _collect_focusables() -> Array:
	var out: Array = []
	_collect_focusables_into(ui_root, out)
	return out

func _collect_focusables_into(node: Node, out: Array) -> void:
	# Godot owns scrollbars as internal children; get_children() omits them.
	# Register them explicitly so spatial navigation can actually reach them.
	if node is ScrollContainer:
		for bar: ScrollBar in [node.get_v_scroll_bar(), node.get_h_scroll_bar()]:
			if bar.focus_mode != Control.FOCUS_NONE and bar.is_visible_in_tree():
				out.append(bar)
	if node is Control:
		var c := node as Control
		if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() \
				and not (c is Container):
			## Containers (VBox/Grid/SubViewportContainer, etc.) are never
			## activation targets — e.g. SubViewportContainer defaults to
			## FOCUS_ALL and would otherwise steal the highlight.
			var disabled := false
			if "disabled" in c:
				disabled = c.disabled
			if not disabled:
				out.append(c)
	for child in node.get_children():
		_collect_focusables_into(child, out)

func _is_descendant(node: Control, root: Node) -> bool:
	var p: Node = node
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false


func _range_multiplier(held_seconds: float) -> float:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if not (focus is Slider):
		return 1.0
	var slider: Slider = focus as Slider
	var increment: float = slider.step if slider.step > 0 else 1.0
	# At full acceleration a repeat moves at most 1% of this range. Small
	# counts retain one-unit precision; high-resolution flow sliders accelerate.
	var max_multiplier: float = maxf(1.0, (slider.max_value - slider.min_value) * 0.01 / increment)
	var ramp: float = clampf((held_seconds - SLIDER_HOLD_DELAY) / SLIDER_RAMP_TIME, 0.0, 1.0)
	return maxf(1.0, floorf(lerpf(1.0, max_multiplier, ramp)))


func _cycle_tabs(direction: int) -> bool:
	var tabs: Array = tab_provider.call() if tab_provider.is_valid() else []
	if tabs.is_empty():
		for control in _collect_focusables():
			if control.has_meta(&"ui_tab"):
				tabs.append(control)
	if tabs.is_empty():
		return false
	var index: int = 0
	for i in tabs.size():
		if tabs[i].button_pressed:
			index = i
	var target: Button = tabs[wrapi(index + direction, 0, tabs.size())]
	target.pressed.emit()
	target.grab_focus()
	return true
