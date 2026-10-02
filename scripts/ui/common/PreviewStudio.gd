extends Node
## PreviewStudio.gd (autoload, Sep 2026)
## The ONE 3D item-preview system: build catalog, shop, storage, status
## inventory, hotbar. Replaces per-slot SubViewports (≈60 in Build alone,
## built on every open — the entry lag) with:
##
##   • a small pool of offscreen STUDIO viewports that render each item once
##     into a cached static ImageTexture (mipmapped, transparent background);
##   • ONE shared SPINNER viewport that turns whichever item is hovered or
##     controller-selected. Only one live 3D preview exists at any time.
##
## Pose (fixes "some models look wrong at the set angle"): every item stands
## UPRIGHT in its authored orientation and is seen in a single product-shot
## view — a 3/4 yaw with the camera tilted down CAMERA_ELEVATION. The old
## kit rotated the model -45° on two axes AND looked down a diagonal, which
## laid walls and doors on their side while small props happened to read.
## Framing uses the item's spin envelope (a cylinder around its vertical
## axis), so a hovered item never grows, shrinks or clips as it turns.
## Per-item overrides (yaw / tilt / zoom) live in POSE_OVERRIDES.
##
## Anti-aliasing: statics render at SUPERSAMPLE× and are box-filtered down;
## the spinner uses FXAA. No MSAA anywhere — MSAA needs its own pipeline for
## every material, which cost ~3 s of compiles at load and would hitch the
## first hover of each item.
##
## Catalog items are registered while the LoadingScreen still covers the
## world (MainWorld awaits wait_idle()), so opening Build/Shop costs nothing.
## Live items (storage, hotbar) render on demand, a few per frame, and are
## cached by what is visibly on them — not by instance or live stats.
##
## API
##   texture(key) -> Texture2D                  cached static render or null
##   request(key, factory, urgent)              factory() -> NEW Node3D (owned)
##   request_item(item) -> String               key for a live world item
##   item_key(item) -> String
##   start_spin(key) -> Texture2D / stop_spin(key)
##   wait_idle(timeout)                         await in loading flows
##   signal preview_ready(key, texture)

signal preview_ready(key: String, texture: Texture2D)

const TEXTURE_SIZE: int = 256
const SUPERSAMPLE: int = 2
const SPINNER_SIZE: int = 192   ## ≥ the largest card well (shop, 130 px) at 1.4× UI scale
## Studios rendering in parallel. All are used behind the LoadingScreen;
## during play the frame budget below limits how many start per frame.
const STUDIO_COUNT: int = 8
const CAMERA_ELEVATION_DEG: float = 24.0
const DEFAULT_YAW_DEG: float = -38.0
const CAM_SIZE: float = 1.0
const FILL: float = 0.84
const SPIN_DEG_PER_SEC: float = 70.0
const SNAPSHOT_LIMIT: int = 160
## Render budget while the player can see the frame (ms); loading ignores it.
const FRAME_BUDGET_MS: float = 4.0

## Per-key pose corrections, found by reviewing the full contact sheet
## (tools/ui_capture/preview_contact_sheet.gd). yaw/tilt in degrees; tilt
## leans the item toward the camera (flat-lying items); zoom > 1 = larger.
const POSE_OVERRIDES: Dictionary = {
	## Walls: show the broad face at 3/4, not the thin end.
	"build:1": {"yaw": 52.0}, "build:25": {"yaw": 52.0}, "build:26": {"yaw": 52.0},
	## Wall-mounted terminal faces the other way in its authored model.
	"build:10": {"yaw": 142.0},
	## Floor-lying rugs and seed packets lean toward the camera to read.
	"build:40": {"tilt": 38.0}, "build:41": {"tilt": 38.0}, "build:42": {"tilt": 38.0},
	"shop:2": {"tilt": 48.0}, "shop:3": {"tilt": 48.0}, "shop:4": {"tilt": 48.0},
	"shop:5": {"tilt": 48.0}, "shop:6": {"tilt": 48.0}, "shop:7": {"tilt": 48.0},
	"shop:8": {"tilt": 48.0}, "shop:9": {"tilt": 48.0}, "shop:10": {"tilt": 48.0},
	"shop:11": {"tilt": 48.0}, "shop:12": {"tilt": 48.0}, "shop:13": {"tilt": 48.0},
}

var _textures: Dictionary = {}        ## key -> ImageTexture
var _factories: Dictionary = {}       ## key -> Callable (kept for re-render / spin)
var _snapshots: Dictionary = {}       ## key -> Node3D (detached model, reusable)
var _snapshot_order: Array[String] = []
var _queue: Array[String] = []
var _queued: Dictionary = {}
var _studios: Array[Dictionary] = []  ## {vp, stage, pivot, tilter, key, state, stamp}
var _spinner: Dictionary = {}
var _spin_key: String = ""
var _loading_mode: bool = false
var _cards: Dictionary = {}          ## key -> Array[Control] bound via bind_card
var _spin_card: Control = null
var _headless: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	for i: int in STUDIO_COUNT:
		_studios.append(_make_rig("Studio%d" % i, TEXTURE_SIZE * SUPERSAMPLE))
	_spinner = _make_rig("Spinner", SPINNER_SIZE)
	(_spinner["vp"] as SubViewport).screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


## Detached snapshots live outside the tree; free them so quitting is clean.
func _exit_tree() -> void:
	for model: Variant in _snapshots.values():
		if is_instance_valid(model) and (model as Node3D).get_parent() == null:
			(model as Node3D).free()
	_snapshots.clear()
	_snapshot_order.clear()
	_factories.clear()
	_cards.clear()


# ── Public API ───────────────────────────────────────────────────────────────

func texture(key: String) -> Texture2D:
	return _textures.get(key) as Texture2D


func has_texture(key: String) -> bool:
	return _textures.has(key)


## Queues a render. `factory` returns a NEW detached Node3D the studio will
## own (set any preview-only guards before returning it). Returns the cached
## texture immediately when it exists.
func request(key: String, factory: Callable, urgent: bool = false) -> Texture2D:
	if factory.is_valid():
		_factories[key] = factory
	if _textures.has(key):
		return _textures[key]
	_enqueue(key, urgent)
	return null


## Live world items (storage, hotbar): copies the item's visible geometry now
## (cheap mesh references) and queues a render keyed by what is visible.
func request_item(item: Node, urgent: bool = true) -> String:
	if item == null or not is_instance_valid(item) or not (item is Node3D):
		return ""
	var key: String = item_key(item)
	if _textures.has(key) or _queued.has(key):
		return key
	var snapshot: Node3D = _copy_visuals(item as Node3D)
	if snapshot == null:
		return ""
	_store_snapshot(key, snapshot)
	_enqueue(key, urgent)
	return key


## Visual identity of a live item: script + title + its visible meshes and
## materials. Stable while a flashlight drains; changes when a case loses a
## can or a seed packet is a different species.
func item_key(item: Node) -> String:
	if item == null or not is_instance_valid(item):
		return ""
	var parts: PackedStringArray = []
	var script: Script = item.get_script() as Script
	parts.append(script.resource_path.get_file() if script != null else item.get_class())
	parts.append(ItemPresentation.title(item))
	if item.has_method("get_inventory_mesh"):
		var mesh: Mesh = item.get_inventory_mesh()
		if mesh != null:
			parts.append("m%d" % mesh.get_instance_id())
			return "item:" + "|".join(parts)
	var stack: Array[Node] = [item]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D and (node as GeometryInstance3D).visible:
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var mi := node as MeshInstance3D
				parts.append("m%d/%d" % [mi.mesh.get_instance_id(),
					mi.material_override.get_instance_id() if mi.material_override != null else 0])
			elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
				parts.append("mm%d" % (node as MultiMeshInstance3D).multimesh.get_instance_id())
		for child: Node in node.get_children():
			stack.append(child)
	return "item:" + str(hash("|".join(parts)))


## Turns the item for `key` in the shared spinner and returns its live
## texture (null if the model is not available yet — keep the static one).
func start_spin(key: String) -> Texture2D:
	if key.is_empty():
		return null
	if _spin_key == key:
		return (_spinner["vp"] as SubViewport).get_texture()
	stop_spin(_spin_key)
	var model: Node3D = _snapshot_for(key)
	if model == null or model.get_parent() != null:
		return null   ## not built yet, or a studio is rendering it this frame
	_spin_key = key
	_mount(_spinner, model, key)
	var vp: SubViewport = _spinner["vp"]
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp.get_texture()


func stop_spin(key: String) -> void:
	if key.is_empty() or key != _spin_key:
		return
	_unmount(_spinner)
	(_spinner["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	_spin_key = ""


func spinning_key() -> String:
	return _spin_key


# ── Cards (hover / controller-select spin) ───────────────────────────────────
## Binds a card: `apply(texture)` receives the static render at rest, the
## live spinner while the card is hovered or focused (controller selection),
## and new renders as they complete. Call again whenever the card's item
## changes. An empty key clears the card.
func bind_card(control: Control, key: String, apply: Callable) -> void:
	var old_key: String = str(control.get_meta(&"studio_key", ""))
	if old_key != key:
		_forget_card(control, old_key)
		if _spin_card == control:
			_end_card_spin()
	control.set_meta(&"studio_key", key)
	control.set_meta(&"studio_apply", apply)
	if not key.is_empty():
		var cards: Array = _cards.get(key, [])
		if not cards.has(control):
			cards.append(control)
		_cards[key] = cards
	if not control.has_meta(&"studio_bound"):
		control.set_meta(&"studio_bound", true)
		control.mouse_entered.connect(_card_on.bind(control))
		control.focus_entered.connect(_card_focused.bind(control))
		control.mouse_exited.connect(_card_off.bind(control))
		control.focus_exited.connect(_card_off.bind(control))
		control.tree_exiting.connect(_card_gone.bind(control))
	if _spin_card != control:
		apply.call(texture(key) if not key.is_empty() else null)
	if control.is_inside_tree() and (control.has_focus() or _is_hovered(control)):
		_card_on(control)


func _card_on(control: Control) -> void:
	var key: String = str(control.get_meta(&"studio_key", ""))
	if key.is_empty() or UIMotion.reduced():
		return
	if _spin_card == control and _spin_key == key:
		return
	_end_card_spin()
	var live: Texture2D = start_spin(key)
	if live == null:
		return
	_spin_card = control
	(control.get_meta(&"studio_apply") as Callable).call(live)


## Focus means "selected" only for a controller; with a mouse, panels park
## focus on their first card and that card must not spin by itself.
func _card_focused(control: Control) -> void:
	if _controller_active():
		_card_on(control)


func _card_off(control: Control) -> void:
	if _spin_card != control:
		return
	if is_instance_valid(control) and control.is_inside_tree() \
			and ((control.has_focus() and _controller_active()) or _is_hovered(control)):
		return
	_end_card_spin()


func _controller_active() -> bool:
	var input_mode: Node = get_node_or_null(^"/root/InputMode")
	return input_mode != null and bool(input_mode.call("is_controller"))


func _card_gone(control: Control) -> void:
	_forget_card(control, str(control.get_meta(&"studio_key", "")))
	if _spin_card == control:
		stop_spin(_spin_key)
		_spin_card = null


func _end_card_spin() -> void:
	var card: Control = _spin_card
	_spin_card = null
	stop_spin(_spin_key)
	if card != null and is_instance_valid(card):
		var key: String = str(card.get_meta(&"studio_key", ""))
		(card.get_meta(&"studio_apply") as Callable).call(texture(key))


func _forget_card(control: Control, key: String) -> void:
	if key.is_empty() or not _cards.has(key):
		return
	var cards: Array = _cards[key]
	cards.erase(control)
	if cards.is_empty():
		_cards.erase(key)


func _is_hovered(control: Control) -> bool:
	if control is BaseButton:
		return (control as BaseButton).is_hovered()
	return control.get_global_rect().has_point(control.get_global_mouse_position())


func _deliver(key: String, tex: Texture2D) -> void:
	for control_value: Variant in _cards.get(key, []).duplicate():
		var control := control_value as Control
		if control == null or not is_instance_valid(control) or control == _spin_card:
			continue
		(control.get_meta(&"studio_apply") as Callable).call(tex)


func pending_count() -> int:
	var busy: int = 0
	for studio: Dictionary in _studios:
		if not String(studio["key"]).is_empty():
			busy += 1
	return _queue.size() + busy


func is_idle() -> bool:
	return pending_count() == 0


## Renders everything queued as fast as possible (no frame budget), for the
## loading screen. Returns when idle or after `timeout` seconds.
func wait_idle(timeout: float = 12.0) -> void:
	_loading_mode = true
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not is_idle() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_loading_mode = false


# ── Render loop ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _spin_key.is_empty() and not UIMotion.reduced():
		var pivot: Node3D = _spinner["pivot"]
		pivot.rotation_degrees.y += SPIN_DEG_PER_SEC * delta
	var started: int = Time.get_ticks_usec()
	for studio: Dictionary in _studios:
		match String(studio["state"]):
			"settle":
				## One frame in the tree lets models finish deferred mesh builds.
				_frame(studio)
				(studio["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
				studio["state"] = "render"
				studio["stamp"] = Engine.get_frames_drawn()
			"render":
				## Headless (dummy renderer) never draws frames: finish at once.
				if _headless or Engine.get_frames_drawn() > int(studio["stamp"]):
					_collect(studio)
	for studio: Dictionary in _studios:
		if _queue.is_empty():
			break
		if String(studio["state"]) != "idle":
			continue
		if not _loading_mode and (Time.get_ticks_usec() - started) / 1000.0 > FRAME_BUDGET_MS:
			break
		_start(studio, _queue.pop_front())


func _enqueue(key: String, urgent: bool) -> void:
	if _queued.has(key):
		if urgent:
			_queue.erase(key)
			_queue.push_front(key)
		return
	_queued[key] = true
	if urgent:
		_queue.push_front(key)
	else:
		_queue.append(key)


func _start(studio: Dictionary, key: String) -> void:
	_queued.erase(key)
	if _textures.has(key):
		return
	var model: Node3D = _snapshot_for(key)
	if model == null:
		return
	if key == _spin_key:
		return   ## spinner owns it this moment; a later request re-queues
	_mount(studio, model, key)
	studio["state"] = "settle"


func _collect(studio: Dictionary) -> void:
	var key: String = studio["key"]
	var vp: SubViewport = studio["vp"]
	var image: Image = null if _headless else vp.get_texture().get_image()
	_unmount(studio)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	studio["state"] = "idle"
	if image == null or image.is_empty():
		return
	for _i: int in range(1, SUPERSAMPLE):
		image.shrink_x2()   ## box filter: the supersample resolve
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_textures[key] = tex
	_deliver(key, tex)
	preview_ready.emit(key, tex)


# ── Models ───────────────────────────────────────────────────────────────────

func _snapshot_for(key: String) -> Node3D:
	var model: Node3D = _snapshots.get(key) as Node3D
	if model != null and is_instance_valid(model):
		_snapshot_order.erase(key)
		_snapshot_order.append(key)
		return model
	var factory: Callable = _factories.get(key, Callable())
	if not factory.is_valid():
		return null
	var built: Variant = factory.call()
	if not (built is Node3D):
		return null
	model = built as Node3D
	model.process_mode = Node.PROCESS_MODE_DISABLED
	_store_snapshot(key, model)
	return model


func _store_snapshot(key: String, model: Node3D) -> void:
	var old: Node3D = _snapshots.get(key) as Node3D
	if old != null and old != model and is_instance_valid(old) and old.get_parent() == null:
		old.free()
	_snapshots[key] = model
	_snapshot_order.erase(key)
	_snapshot_order.append(key)
	while _snapshot_order.size() > SNAPSHOT_LIMIT:
		var evict: String = _snapshot_order.pop_front()
		var node: Node3D = _snapshots.get(evict) as Node3D
		_snapshots.erase(evict)
		if node != null and is_instance_valid(node) and node.get_parent() == null:
			node.free()


## Copies visible MeshInstance3D / MultiMeshInstance3D geometry of a live,
## in-tree item into a detached wrapper (no scripts, bodies or collision).
## Visibility is judged INSIDE the item: a stored item's root is hidden
## (InventoryManager), which must not hide every mesh under it — that left
## stored items with no preview at all. Only parts the item itself hides
## (an emptied case's missing cans, a closed lid variant) are skipped.
func _copy_visuals(item: Node3D) -> Node3D:
	if not item.is_inside_tree():
		return null
	var wrapper := Node3D.new()
	if item.has_method("get_inventory_mesh"):
		var mesh: Mesh = item.get_inventory_mesh()
		if mesh != null:
			var only := MeshInstance3D.new()
			only.mesh = mesh
			wrapper.add_child(only)
			return wrapper
	var inverse: Transform3D = item.global_transform.affine_inverse()
	var stack: Array[Node] = [item]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != item and node is Node3D and not (node as Node3D).visible:
			continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var src := node as MeshInstance3D
			var copy := MeshInstance3D.new()
			copy.mesh = src.mesh
			copy.material_override = src.material_override
			for surface: int in src.mesh.get_surface_count():
				copy.set_surface_override_material(surface, src.get_surface_override_material(surface))
			copy.transform = inverse * src.global_transform
			wrapper.add_child(copy)
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var msrc := node as MultiMeshInstance3D
			var mcopy := MultiMeshInstance3D.new()
			mcopy.multimesh = msrc.multimesh
			mcopy.material_override = msrc.material_override
			mcopy.transform = inverse * msrc.global_transform
			wrapper.add_child(mcopy)
		for child: Node in node.get_children():
			stack.append(child)
	if wrapper.get_child_count() == 0:
		wrapper.free()
		return null
	return wrapper


# ── Rigs ─────────────────────────────────────────────────────────────────────

func _make_rig(rig_name: String, px: int) -> Dictionary:
	var vp := SubViewport.new()
	vp.name = rig_name
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d3dc")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)
	var elevation: float = deg_to_rad(CAMERA_ELEVATION_DEG)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.near = 0.05
	cam.far = 20.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, sin(elevation), cos(elevation)) * 6.0, Vector3.ZERO, Vector3.UP)
	## Warm key from the upper left, cool rim from behind (the bunker lamp).
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color("f4e2c0")
	key_light.light_energy = 1.25
	key_light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	vp.add_child(key_light)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9cc3e0")
	rim.light_energy = 0.55
	rim.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	vp.add_child(rim)
	var stage := Node3D.new()
	stage.name = "Stage"
	vp.add_child(stage)
	var pivot := Node3D.new()
	stage.add_child(pivot)
	var tilter := Node3D.new()
	pivot.add_child(tilter)
	return {"vp": vp, "stage": stage, "pivot": pivot, "tilter": tilter,
		"key": "", "state": "idle", "stamp": 0}


func _mount(rig: Dictionary, model: Node3D, key: String) -> void:
	_unmount(rig)
	var tilter: Node3D = rig["tilter"]
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	tilter.add_child(model)
	model.process_mode = Node.PROCESS_MODE_DISABLED
	## Factory models may join world groups in _ready (preview guards miss
	## some); group scans must never see preview copies.
	GhostModelBuilder.strip_groups(model)
	## World tags (status text, floating names) never belong in a preview.
	for label: Node in model.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	rig["key"] = key
	_frame(rig)


func _unmount(rig: Dictionary) -> void:
	var tilter: Node3D = rig["tilter"]
	for child: Node in tilter.get_children():
		tilter.remove_child(child)
	rig["key"] = ""


## Upright product-shot framing sized to the spin envelope (see header).
func _frame(rig: Dictionary) -> void:
	var key: String = rig["key"]
	var pivot: Node3D = rig["pivot"]
	var tilter: Node3D = rig["tilter"]
	var pose: Dictionary = POSE_OVERRIDES.get(key, {})
	pivot.scale = Vector3.ONE
	pivot.rotation_degrees = Vector3.ZERO
	tilter.position = Vector3.ZERO
	tilter.rotation_degrees = Vector3(float(pose.get("tilt", 0.0)), 0.0, 0.0)
	var bounds: AABB = _bounds_in(pivot, tilter)
	if bounds.size == Vector3.ZERO:
		return
	var center: Vector3 = bounds.get_center()
	tilter.position = -center
	var radius: float = 0.0
	for i: int in 8:
		var corner: Vector3 = bounds.get_endpoint(i) - center
		radius = maxf(radius, Vector2(corner.x, corner.z).length())
	var elevation: float = deg_to_rad(CAMERA_ELEVATION_DEG)
	var width: float = 2.0 * radius
	var height: float = bounds.size.y * cos(elevation) + 2.0 * radius * sin(elevation)
	var extent: float = maxf(width, height)
	if extent > 0.0001:
		pivot.scale = Vector3.ONE * (FILL * CAM_SIZE * float(pose.get("zoom", 1.0)) / extent)
	pivot.rotation_degrees.y = float(pose.get("yaw", DEFAULT_YAW_DEG))


## Combined bounds of every visual under `content`, expressed in `space`.
func _bounds_in(space: Node3D, content: Node3D) -> AABB:
	var inverse: Transform3D = space.global_transform.affine_inverse()
	var combined := AABB()
	var found: bool = false
	var stack: Array[Node] = [content]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var local := AABB()
		var has_box: bool = false
		## Any visible model geometry counts (meshes, multimeshes). Label3D
		## world tags (status text, floating names) are hidden in previews.
		if node is GeometryInstance3D and not (node is Label3D) and (node as GeometryInstance3D).visible:
			local = (node as GeometryInstance3D).get_aabb()
			has_box = local.size != Vector3.ZERO
		if has_box:
			var box: AABB = (inverse * (node as Node3D).global_transform) * local
			combined = box if not found else combined.merge(box)
			found = true
		for child: Node in node.get_children():
			stack.append(child)
	return combined if found else AABB()
