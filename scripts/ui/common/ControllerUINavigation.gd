class_name ControllerUINavigation
extends Node
## ControllerUINavigation.gd
## Reusable gamepad navigation for Control-based UIs (Aug 2026).
##
## Attach as a child of any Control tree you want to drive with a
## controller (or point ui_root at it):
##   - D-pad:     moves focus one step in the pressed cardinal direction.
##   - Left stick: moves focus toward whichever button is nearest in the
##                 direction the stick points ("best guess"), and repeats
##                 while the stick is held.
##   - A (ui_accept): activates the focused button (Godot default).
##   - B (ui_cancel): closes this UI (close_on_cancel, topmost-only).
## ui_root can be a Control or a CanvasLayer (e.g. a full-screen menu).
##
## This consumes joypad movement events in _input() BEFORE Godot's built-in
## focus navigation, for two reasons:
##   1. It lets the left stick pick a button by ANALOG direction (not just
##      the 4-cardinal ui_* actions), which is the "best guess" behavior.
##   2. Consumed events never reach _unhandled_input handlers — so while a
##      UI with this node is open, the d-pad/stick cannot also trigger other
##      gamepad actions (e.g. InteractionSystem's inventory cycling).
##      Attach this node to any modal/full-screen UI that should own the pad.
##
## Keyboard (arrow keys) and mouse are intentionally left to Godot's built-in
## focus/hover — only joypad input is handled here.

@export var ui_root: Node = null
@export var stick_deadzone: float = 0.6   ## stick magnitude needed to register a directional move
@export var move_repeat_delay: float = 0.22   ## seconds between auto-moves while a direction is held
## When true, B closes this UI (calls ui_root.close() if it has one, else
## hides it). Only the TOPMOST open controller UI closes on a B press, so
## e.g. B in the Settings panel (layer 210) closes Settings but not the
## Pause menu (layer 200) underneath. Set false for UIs that must not be
## closed by the pad (character creation).
@export var close_on_cancel: bool = true
## When true, the left stick also drives focus (analog "best guess").
## In-game UIs are d-pad-only (left stick stays reserved for movement), so
## this defaults to false; the character creation menu opts in.
@export var stick_navigation: bool = false

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
const SLIDER_HOLD_DELAY: float    = 1.0
const SLIDER_START_INTERVAL: float = 0.2     ## ~5 steps/sec when repeat kicks in
const SLIDER_MIN_INTERVAL: float   = 0.01    ## 100 steps/sec
const SLIDER_RAMP_TIME: float      = 3.0     ## seconds of holding to reach max rate
## While held, each repeat's STEP also ramps from 1× the slider's step up to
## this multiplier — so the flow-rate slider (step = 1 mL/day) accelerates
## 1 → 500 mL/day per repeat, letting a player sweep a large range quickly.
const SLIDER_REPEAT_MAX_STEP_MULT: float = 500.0

var _move_cooldown: float = 0.0

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
	## Ensure A = confirm and B = cancel on the Godot built-in actions.
	## This project's ui_accept/ui_cancel were customized to keyboard-only,
	## so a focused button would never activate from the pad without this.
	## Idempotent — only adds the joypad event if it's missing.
	_ensure_action_button("ui_accept", JOY_BUTTON_A)
	_ensure_action_button("ui_cancel", JOY_BUTTON_B)

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
		_slider_repeat_dir = 0
		return
	if not _is_topmost():
		## A higher-layer controller UI is open — it owns the pad.
		_slider_repeat_dir = 0
		return
	_tick_slider_repeat(delta)
	_try_stick_move()

func _input(event: InputEvent) -> void:
	if not _active():
		return
	## A HIGHER-layer open controller UI owns the pad while it's open —
	## back off (consume nothing) so it receives d-pad/B/A (e.g. the pause
	## menu's nav must not eat B/d-pad while a confirm dialog is stacked
	## above it).
	if not _is_topmost():
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
			if dir.y == 0.0 and _is_focused_slider():
				## A focused Slider owns horizontal d-pad (Aug 2026): one step
				## now, then a held direction auto-repeats with acceleration —
				## see _tick_slider_repeat().
				_adjust_focused_slider(int(dir.x))
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
	## Left stick — consume the raw motion so Godot's built-in 4-directional
	## focus navigation doesn't also act; the actual move is polled in
	## _process() so a held stick keeps repeating.
	if event is InputEventJoypadMotion and (event.axis == JOY_AXIS_LEFT_X or event.axis == JOY_AXIS_LEFT_Y):
		get_viewport().set_input_as_handled()

func _active() -> bool:
	if ui_root == null or not ui_root.is_inside_tree():
		return false
	return _node_visible(ui_root)

## Public wrapper for the visibility check — other systems ask "is this UI
## open right now?" via this (e.g. InteractionSystem gates A's world
## fall-through while ANY controller-nav UI is open, so a press can't open a
## different UI by mistake).
func is_active() -> bool:
	return _active()

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
		if oroot != null and oroot.is_inside_tree() and _node_visible(oroot):
			var other_layer: int = other.call("_effective_layer")
			if other_layer > my_layer:
				return false
	return true

func _try_stick_move() -> void:
	if not stick_navigation:
		return
	if _move_cooldown > 0.0:
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() < stick_deadzone:
		return
	_move_focus(stick.normalized())

## Moves focus to the control most in `dir`. Nearest-ahead scoring (Aug 2026):
## among candidates within MIN_DIR_DOT of the pressed direction, the CLOSEST
## wins, with a 2x penalty on off-axis distance — so a slightly-farther
## on-column button beats a near diagonal one, and pressing up from a bottom
## row (e.g. a priority ◄/►) lands on the nearest button in the row above
## instead of leaping to a far-away vertically-aligned one (the old
## "most-aligned wins" rule, which caused the bottom-row jump). Pressing
## toward an empty edge stays put. First press (no current focus) accepts
## anything in the general direction and falls back to the first focusable.
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

	var ndir: Vector2 = dir.normalized()
	var best: Control = null
	var best_along: float = INF
	var best_perp: float = INF
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
		## Nearest-ahead (Aug 2026): the CLOSEST candidate in the pressed
		## direction wins — forward distance (along) is the PRIMARY key and
		## horizontal offset (perp) only breaks ties. This keeps vertical
		## lists (graphics settings' stacked option rows) stepping exactly
		## one row at a time even when controls sit at different X positions
		## (wide OptionButtons vs. narrow CheckBoxes), while bottom-row
		## priority buttons still land on the nearest button above instead of
		## leaping to a far-away vertically-aligned one.
		var along: float = delta.dot(ndir)
		var perp: float = (delta - ndir * along).length()
		if along < best_along or (along == best_along and perp < best_perp):
			best_along = along
			best_perp  = perp
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

func _start_slider_repeat(dir: int) -> void:
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
	if not _is_focused_slider():
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
	_slider_step_mult = lerpf(1.0, SLIDER_REPEAT_MAX_STEP_MULT, t)
	_slider_repeat_timer -= delta
	if _slider_repeat_timer <= 0.0:
		_adjust_focused_slider(_slider_repeat_dir, _slider_step_mult)
		_slider_repeat_timer = _slider_interval

func _collect_focusables() -> Array:
	var out: Array = []
	_collect_focusables_into(ui_root, out)
	return out

func _collect_focusables_into(node: Node, out: Array) -> void:
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