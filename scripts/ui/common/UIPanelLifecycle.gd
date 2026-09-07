class_name UIPanelLifecycle
extends RefCounted
## Close gameplay/input immediately; finish only the presentation afterward.
## No screenshots, duplicate scenes, reparenting, new autoload or preview load.
const EXITING: StringName = &"ui_exiting"
const SAVED: StringName = &"ui_exit_controls"
const SURFACE: StringName = &"ui_exit_surface"

static func prepare_open(owner: CanvasLayer) -> void:
	owner.set_meta(EXITING, false)
	if owner.has_meta(SURFACE):
		var surface: CanvasItem = (owner.get_meta(SURFACE) as WeakRef).get_ref() as CanvasItem
		if is_instance_valid(surface):
			UIFade.cancel(surface)
			surface.modulate.a = 1.0
	_restore_controls(owner)
	for candidate: Node in owner.get_children():
		if candidate.has_method("mark_open"):
			candidate.call("mark_open")

static func dismiss(owner: CanvasLayer, surface: CanvasItem,
		on_hidden: Callable = Callable()) -> void:
	if owner.get_meta(EXITING, false) == true:
		return
	owner.set_meta(EXITING, true)
	owner.set_meta(SURFACE, weakref(surface))
	var saved: Array = []
	_disable_controls(owner, saved)
	owner.set_meta(SAVED, saved)
	UIFade.fade_out(surface, UIMotion.EXIT, _finish.bind(weakref(owner), on_hidden))

static func _disable_controls(node: Node, saved: Array) -> void:
	for child: Node in node.get_children():
		# A nested menu has its own lifecycle and close policy.
		if child is CanvasLayer:
			continue
		if child is Control:
			var control: Control = child as Control
			saved.append([weakref(control), control.mouse_filter, control.focus_mode])
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.focus_mode = Control.FOCUS_NONE
		_disable_controls(child, saved)

static func _restore_controls(owner: CanvasLayer) -> void:
	if not owner.has_meta(SAVED):
		return
	for record: Array in owner.get_meta(SAVED):
		var control: Control = (record[0] as WeakRef).get_ref() as Control
		if is_instance_valid(control):
			control.mouse_filter = int(record[1]) as Control.MouseFilter
			control.focus_mode = int(record[2]) as Control.FocusMode
	owner.remove_meta(SAVED)

static func _finish(reference: WeakRef, on_hidden: Callable = Callable()) -> void:
	var owner: CanvasLayer = reference.get_ref() as CanvasLayer
	if not is_instance_valid(owner) or owner.get_meta(EXITING, false) != true:
		return
	owner.visible = false
	_restore_controls(owner)
	owner.set_meta(EXITING, false)
	if on_hidden.is_valid():
		on_hidden.call()
