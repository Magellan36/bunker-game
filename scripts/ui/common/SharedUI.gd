class_name SharedUI
extends RefCounted
## SharedUI.gd (Sep 2026)
## One prebuilt instance per inspector/workspace script, lent to whichever
## world object opens it. Building a panel costs 100–450 ms (script setup,
## theme work, first layout); before this every NEW device built its own on
## its first E-press, which was the "game pauses when a UI opens" hitch.
## Reopening an existing panel costs ~2 ms, so sharing one instance per type
## (only one inspector is ever open at a time) removes the hitch entirely,
## and prewarm() builds them all behind the LoadingScreen.
##
## Owner contract (world devices):
##   if <field> == null or not is_instance_valid(<field>):
##       <field> = SharedUI.acquire(PATH, self, &"<field>", {"sig": handler, ...})
##   The panel's `closed` signal sets the owner's <field> back to null, so a
##   device only ever holds the panel while its own view is open — every
##   existing `is_instance_valid(<field>)` guard keeps background devices
##   from pushing data into another device's view. Lending the panel to a
##   new owner closes the previous owner's view first (it hears `closed`
##   while still connected). On owner exit: close it if held; never free a
##   shared panel.

static var _instances: Dictionary = {}   ## script path -> CanvasLayer
static var _bound: Dictionary = {}       ## script path -> Array[[signal, Callable]]
static var _owners: Dictionary = {}      ## script path -> WeakRef


## The shared instance for `path`, created (and entered into the tree) on
## first use. Returns null if the script cannot be loaded.
static func instance(path: String) -> CanvasLayer:
	var ui: CanvasLayer = _instances.get(path) as CanvasLayer
	if ui != null and is_instance_valid(ui) and not ui.is_queued_for_deletion():
		return ui
	var script: GDScript = load(path) as GDScript
	if script == null:
		push_warning("SharedUI: %s not found" % path)
		return null
	ui = script.new() as CanvasLayer
	ui.name = path.get_file().get_basename()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(ui)
	_instances[path] = ui
	_bound.erase(path)
	_owners.erase(path)
	return ui


## Lends the shared panel to `owner`, moving `signals` (name -> Callable)
## connections to it and wiring `closed` to clear `owner.<field>`.
static func acquire(path: String, owner: Object, field: StringName,
		signals: Dictionary = {}) -> CanvasLayer:
	var ui: CanvasLayer = instance(path)
	if ui == null:
		return null
	var previous: Object = _owner_of(path)
	if previous != owner:
		if previous != null and ui.has_method("is_open") and bool(ui.call("is_open")) \
				and ui.has_method("close"):
			ui.call("close")   ## previous owner still connected: it hears `closed`
		for pair: Array in _bound.get(path, []):
			var sig: String = pair[0]
			var callable: Callable = pair[1]
			if ui.has_signal(sig) and ui.is_connected(sig, callable):
				ui.disconnect(sig, callable)
		_owners[path] = weakref(owner)
		var bound: Array = []
		var all_signals: Dictionary = signals.duplicate()
		if ui.has_signal("closed") and not field.is_empty():
			var owner_ref: WeakRef = weakref(owner)
			var clear := func(..._args: Array) -> void:
				var who: Object = owner_ref.get_ref()
				if who != null and who.get(field) == ui:
					who.set(field, null)
			## Runs after the owner's own `closed` handler (connected first).
			all_signals["closed"] = [all_signals.get("closed", Callable()), clear]
		for sig: String in all_signals:
			var handlers: Variant = all_signals[sig]
			for callable_value: Variant in (handlers if handlers is Array else [handlers]):
				var callable: Callable = callable_value as Callable
				if ui.has_signal(sig) and callable.is_valid() and not ui.is_connected(sig, callable):
					ui.connect(sig, callable)
					bound.append([sig, callable])
		_bound[path] = bound
	return ui


## True when `ui` is currently lent to `owner`.
static func owns(ui: Object, owner: Object) -> bool:
	if ui == null or not is_instance_valid(ui):
		return false
	for path: String in _instances:
		if _instances[path] == ui:
			return _owner_of(path) == owner
	return true   ## not a shared panel (e.g. created by a test): owner-private


## Owner leaving the world: close its view if it holds the panel.
static func release(ui: Object, owner: Object) -> void:
	if ui == null or not is_instance_valid(ui) or not owns(ui, owner):
		return
	if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
		ui.call("close")


## Builds every listed panel ahead of use (LoadingScreen). Each panel is
## briefly made visible — still hidden beneath the opaque loading layer — so
## its fonts, layout and draw pipelines are warm before the player sees it.
static func prewarm(paths: Array[String]) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var warmed: Array[CanvasLayer] = []
	for path: String in paths:
		var ui: CanvasLayer = instance(path)
		if ui != null:
			warmed.append(ui)
	await tree.process_frame
	## All at once: first-draw costs overlap instead of queuing frame by frame.
	var states: Array[bool] = []
	for ui: CanvasLayer in warmed:
		states.append(ui.visible)
		ui.visible = true
	await tree.process_frame
	await tree.process_frame
	for i: int in warmed.size():
		if is_instance_valid(warmed[i]):
			warmed[i].visible = states[i]


static func _owner_of(path: String) -> Object:
	var ref: WeakRef = _owners.get(path) as WeakRef
	return ref.get_ref() if ref != null else null
