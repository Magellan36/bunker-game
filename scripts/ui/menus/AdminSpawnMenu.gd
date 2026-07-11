extends CanvasLayer
## AdminSpawnMenu.gd
## F10 developer spawn panel — lets you instantly spawn any built object
## in front of the player without going through Build Mode.
## Injected refs set by MainWorld._toggle_admin_spawn_menu().

# ─── Debug ────────────────────────────────────────────────────────────────────
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Injected by MainWorld ────────────────────────────────────────────────────
var world_node:       Node3D = null
var player:           Node3D = null
var build_controller: Node3D = null

# ─── State ───────────────────────────────────────────────────────────────────
var _visible_state: bool = false
var _panel:         Panel        = null
var _scroll:        ScrollContainer = null
var _vbox:          VBoxContainer = null

# ─── Tile catalogue (id → display name) ──────────────────────────────────────
const TILES: Array = [
	## [tile_id_or_special, label, group]
	["SECTION", "─── Structures ───", ""],
	[1,  "Wall",              "structure"],
	[2,  "Pillar",            "structure"],
	["SECTION", "─── Furniture ───", ""],
	[3,  "Shelving",          "furniture"],
	[4,  "Bed",               "furniture"],
	["SECTION", "─── Electrical ───", ""],
	[5,  "Wall Light",        "electrical"],
	[6,  "Generator (S)",     "electrical"],
	[7,  "Generator (M)",     "electrical"],
	[8,  "Generator (L)",     "electrical"],
	[10, "Power Terminal",    "electrical"],
	["SECTION", "─── Items ───", ""],
	["fuel_can",    "Fuel Can",   "item"],
	["flashlight",  "Flashlight", "item"],
	["water_bottle","Water Bottle","item"],
	["food_can",    "Food Can",   "item"],
]

# ─── Spawn distances ──────────────────────────────────────────────────────────
const SPAWN_DIST:  float = 2.0   ## How far in front of the player to spawn
const SPAWN_Y:     float = 0.0

func _ready() -> void:
	layer = 128   ## On top of everything
	_build_ui()
	visible = false

func toggle() -> void:
	_visible_state = not _visible_state
	visible = _visible_state
	if _visible_state:
		## Standing convention (July 2026) — see UIFade.gd.
		UIFade.fade_in(_panel)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ─── UI Construction ──────────────────────────────────────────────────────────
func _build_ui() -> void:
	## Semi-transparent dark background panel
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(260, 420)
	## Anchor to left-center of screen
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left   = 20.0
	_panel.offset_right  = 280.0
	_panel.offset_top    = -210.0
	_panel.offset_bottom = 210.0

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color          = Color(0.08, 0.08, 0.10, 0.92)
	style.border_color      = Color(0.30, 0.30, 0.35, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	## Header
	var header: Label = Label.new()
	header.text = "[F10]  Admin Spawn"
	header.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80, 1.0))
	header.add_theme_font_size_override("font_size", 13)
	header.position = Vector2(10, 8)
	_panel.add_child(header)

	var sep: HSeparator = HSeparator.new()
	sep.position = Vector2(8, 28)
	sep.size     = Vector2(244, 2)
	_panel.add_child(sep)

	## Scroll area for buttons
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(8, 36)
	_scroll.size     = Vector2(244, 368)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.custom_minimum_size = Vector2(230, 0)
	_vbox.add_theme_constant_override("separation", 3)
	_scroll.add_child(_vbox)

	## Populate buttons from TILES catalogue
	for entry: Array in TILES:
		var id: Variant = entry[0]
		var label: String = entry[1]

		if id is String and (id as String) == "SECTION":
			var sec: Label = Label.new()
			sec.text = label
			sec.add_theme_color_override("font_color", Color(0.45, 0.60, 0.55, 1.0))
			sec.add_theme_font_size_override("font_size", 10)
			sec.custom_minimum_size = Vector2(230, 18)
			_vbox.add_child(sec)
			continue

		var btn: Button = Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(230, 28)
		btn.add_theme_font_size_override("font_size", 12)

		var btn_style: StyleBoxFlat = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.16, 0.18, 0.90)
		btn_style.border_color = Color(0.28, 0.28, 0.32, 0.80)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style: StyleBoxFlat = btn_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.22, 0.30, 0.25, 0.95)
		hover_style.border_color = Color(0.45, 0.65, 0.50, 1.0)
		btn.add_theme_stylebox_override("hover", hover_style)

		## Capture id in closure — GDScript closures capture by reference,
		## so we bind id as a parameter to avoid the classic loop-closure bug.
		btn.pressed.connect(_on_spawn_pressed.bind(id))
		_vbox.add_child(btn)

# ─── Input: close on Escape or F10 ───────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _visible_state:
		return
	if event is InputEventKey and event.pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE \
				or (event as InputEventKey).keycode == KEY_F10:
			toggle()
			get_viewport().set_input_as_handled()

# ─── Spawn logic ──────────────────────────────────────────────────────────────
func _on_spawn_pressed(id: Variant) -> void:
	toggle()   ## Close menu first

	if player == null or world_node == null:
		push_warning("[AdminSpawn] refs not set")
		return

	## Spawn position: SPAWN_DIST ahead of the player (uses camera yaw if available)
	var yaw: float = 0.0
	if "camera_yaw_rad" in player:
		yaw = player.camera_yaw_rad
	else:
		yaw = player.rotation.y

	var forward: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	var spawn_pos: Vector3 = player.global_position + forward * SPAWN_DIST + Vector3(0.0, SPAWN_Y, 0.0)

	## Structural tiles — delegate to build_controller
	if id is int:
		_spawn_tile(id as int, spawn_pos)
		return

	## Named items — load their scenes directly
	match id:
		"fuel_can":       _spawn_scene("res://scenes/world/FuelCan.tscn",      spawn_pos)
		"flashlight":     _spawn_scene("res://scenes/world/Flashlight.tscn",   spawn_pos)
		"water_bottle":   _spawn_scene("res://scenes/world/WaterBottle.tscn",  spawn_pos)
		"food_can":       _spawn_scene("res://scenes/world/FoodCan.tscn",      spawn_pos)
		_:
			push_warning("[AdminSpawn] Unknown item id: %s" % str(id))

func _spawn_tile(tile_id: int, pos: Vector3) -> void:
	if build_controller == null or not build_controller.has_method("spawn_structure"):
		push_warning("[AdminSpawn] build_controller not ready")
		return
	build_controller.call("spawn_structure", tile_id, pos, 0.0)
	_wdbg("[AdminSpawn] Spawned tile %d at %s" % [tile_id, pos])

func _spawn_scene(path: String, pos: Vector3) -> void:
	if not ResourceLoader.exists(path):
		push_warning("[AdminSpawn] Scene not found: %s" % path)
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("[AdminSpawn] Failed to load: %s" % path)
		return
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		push_warning("[AdminSpawn] Instantiate failed: %s" % path)
		return
	## Freeze physics for one frame to avoid fall-through on spawn
	if node is RigidBody3D:
		var rb: RigidBody3D = node as RigidBody3D
		rb.freeze      = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	world_node.add_child(node)
	node.global_position = pos
	if node is RigidBody3D:
		node.call_deferred("_unfreeze_after_spawn")
	_wdbg("[AdminSpawn] Spawned %s at %s" % [path.get_file(), pos])
