class_name UIFade
extends RefCounted
## One interruptible alpha transition per surface. Callers retain visibility,
## input and gameplay ownership. Reopening cancels stale close callbacks.
const DEFAULT_DURATION: float = UIMotion.ENTER
const TWEEN_META: StringName = &"bunker_alpha_tween"

static func cancel(target: CanvasItem) -> void:
	if not is_instance_valid(target):
		return
	var previous: Variant = target.get_meta(TWEEN_META) if target.has_meta(TWEEN_META) else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	if target.has_meta(TWEEN_META):
		target.remove_meta(TWEEN_META)

static func fade_in(target: CanvasItem, duration: float = DEFAULT_DURATION) -> void:
	if not is_instance_valid(target):
		return
	cancel(target)
	# Snapshot values must precede this call. Never ease from another host.
	BunkerSmoothProgressBar.snap_tree(target)
	target.modulate.a = 0.0 if UIMotion.duration(duration) > 0.0 else 1.0
	_to(target, 1.0, duration)

static func content(target: CanvasItem) -> void:
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	cancel(target)
	# Keep details readable throughout; do not shift containers or hitboxes.
	target.modulate.a = 0.82 if not UIMotion.reduced() else 1.0
	_to(target, 1.0, UIMotion.CONTENT)

static func fade_out(target: CanvasItem, duration: float = UIMotion.EXIT,
		on_complete: Callable = Callable()) -> void:
	if not is_instance_valid(target):
		return
	cancel(target)
	_to(target, 0.0, duration, on_complete)

static func _to(target: CanvasItem, alpha: float, seconds: float,
		completed: Callable = Callable()) -> void:
	var duration: float = UIMotion.duration(seconds)
	if duration <= 0.0 or not target.is_inside_tree():
		target.modulate.a = alpha
		if completed.is_valid():
			completed.call()
		return
	var tween: Tween = target.create_tween()
	target.set_meta(TWEEN_META, tween)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(target, "modulate:a", alpha, duration).set_trans(
		Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if completed.is_valid():
		tween.tween_callback(completed)
