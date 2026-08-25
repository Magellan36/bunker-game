extends Node
## InputMode.gd (Aug 2026) — tracks whether the player is currently using a
## gamepad (controller mode) or keyboard/mouse, LAST-INPUT-WINS. UI layers
## (e.g. InteractPrompt) read is_controller() to swap key-cap icons for Xbox
## button icons.

var _controller_mode: bool = false
## While true, mouse-MOTION events are ignored for mode-flipping. Used by the
## build-mode controller cursor, which warps the OS mouse on behalf of the
## right stick — warping emits REAL mouse-motion events that would otherwise
## flap the mode between controller and mouse every frame (and flicker every
## UI prompt). A real mouse BUTTON (or key press) still flips to mouse mode.
var _suppress_mouse_motion: bool = false
## Last mouse mode before controller-mode cursor-hiding kicked in — restored
## (once) when the player switches back to mouse/keyboard so the cursor
## reappears where a UI left it.
var _stashed_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _was_controller: bool = false

## Mouse-motion deadzone (Aug 2026): while using the controller, a tiny
## accidental mouse nudge must NOT flip to mouse/keyboard mode — it was
## flapping the mode (and flashing every prompt + the cursor) on the
## slightest jitter. Events below MOUSE_MOTION_MIN_PX are ignored entirely
## (sub-pixel jitter); the rest accumulate over a short window and only
## crossing MOUSE_MOTION_THRESHOLD_PX within it (a deliberate move) flips.
## A mouse BUTTON or key press still flips immediately — those are
## deliberate.
const MOUSE_MOTION_MIN_PX: float       = 1.0
const MOUSE_MOTION_THRESHOLD_PX: float = 4.0
const MOUSE_MOTION_WINDOW_SEC: float   = 0.25

var _mouse_move_accum: float = 0.0
var _mouse_move_timer: float = 0.0

func is_controller() -> bool:
	return _controller_mode

func is_keyboard() -> bool:
	return not _controller_mode

func set_suppress_mouse_motion(v: bool) -> void:
	_suppress_mouse_motion = v

func _process(delta: float) -> void:
	## Decay the mouse-motion accumulation window — if no qualifying motion
	## arrives within the window, drop the partial count so slow jitter
	## can't creep up to the threshold.
	if _mouse_move_timer > 0.0:
		_mouse_move_timer -= delta
		if _mouse_move_timer <= 0.0:
			_mouse_move_accum = 0.0
	## Hide the OS cursor while a controller is the active device. UIs set
	## MOUSE_MODE_VISIBLE on open, which would otherwise draw the system
	## cursor over every menu in controller mode (build mode already hides
	## it and draws its own crosshair). On the switch back to mouse/keyboard
	## the stashed mode is restored once.
	if _controller_mode:
		if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
			_stashed_mouse_mode = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif _was_controller:
		Input.mouse_mode = _stashed_mouse_mode
	_was_controller = _controller_mode

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_controller_mode = true
		_mouse_move_accum = 0.0
	elif event is InputEventKey or event is InputEventMouseButton:
		_controller_mode = false
		_mouse_move_accum = 0.0
	elif event is InputEventMouseMotion and not _suppress_mouse_motion:
		var mm := event as InputEventMouseMotion
		if mm.relative.length() >= MOUSE_MOTION_MIN_PX:
			_mouse_move_accum += mm.relative.length()
			_mouse_move_timer = MOUSE_MOTION_WINDOW_SEC
			if _mouse_move_accum >= MOUSE_MOTION_THRESHOLD_PX:
				_controller_mode = false
				_mouse_move_accum = 0.0