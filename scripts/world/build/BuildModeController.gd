extends Node3D
class_name BuildModeController
## BuildModeController.gd
## Manages all build-mode logic: ghost preview, grid snapping, placement,
## deconstruction, duplication, move, and undo.
##
## ARCHITECTURE NOTE — Free Placement vs GridMap:
##   Floor tiles (tile_id = 0) remain GridMap-managed (BunkerLayout stamps them).
##   Player-placed walls and pillars (tile_id >= 1) are spawned as free
##   StaticBody3D + MeshInstance3D nodes so they support full 8-directional
##   (45° step) Y-axis rotation. These are tracked in _placed_objects.
##
## Lives as a child of the Player node.
## MainWorld wires: gridmap, build_hud, camera, world_node, rock_surround references after _ready.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var build_reach: float = 4.5   ## Max placement/removal distance
@export var ray_length:  float = 50.0  ## How far the placement raycast travels
@export var grid_size:   float = 0.25  ## Snap grid cell size (quarter-unit grid)

# ─── External refs (set by MainWorld) ─────────────────────────────────────────
var gridmap:      GridMap      = null   ## The BunkerLayout GridMap (floor only)
var build_hud:    CanvasLayer  = null   ## BuildModeHUD node
var camera:       Camera3D     = null   ## GameCamera
var world_node:   Node3D       = null   ## MainWorld — for spend_cash() / add_cash()
var rock_surround: Node3D      = null   ## RockSurround node — for dig mechanic

# ─── Tile IDs (must match BunkerLayout / BuildModeHUD) ────────────────────────
# ─── Debug ────────────────────────────────────────────────────────────────────
## Flip false to silence all [Undo]/[AdminSpawn]/[Build] diagnostic prints.
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

const TILE_FLOOR:    int = 0
const TILE_WALL:     int = 1
const TILE_PILLAR:   int = 2
const TILE_SHELVING: int = 3
const TILE_BED:      int = 4
const TILE_LIGHT:    int = 5
const TILE_GEN_S:    int = 6   ## Small generator  (1×1, 800W)
const TILE_GEN_M:    int = 7   ## Medium generator (1×2, 2000W)
const TILE_GEN_L:    int = 8   ## Large generator  (2×2, 5000W)
const TILE_WIRE:       int = 9   ## Wire segment (logical-only; no longer a placeable tile — kept for save-compat)
const TILE_TERMINAL:   int = 10  ## Power terminal — buildable dashboard panel
const TILE_HEAVY:      int = 11  ## Heavy load test consumer — 500 W, price $0
const TILE_BREAKER:    int = 12  ## Circuit breaker — trips/resets with E key
const TILE_BATTERY_S:  int = 13  ## Battery Bank Small  — 100 Wh, $150
const TILE_BATTERY_M:  int = 14  ## Battery Bank Medium — 300 Wh, $350
const TILE_BATTERY_L:  int = 15  ## Battery Bank Large  — 600 Wh, $600
const TILE_BREAKER_SMART: int = 16  ## Upgraded/"smart" breaker — self-trips to isolate on cross-zone exhaustion
const TILE_WATER_HOOKUP: int  = 17  ## Water system groundwork (July 2026) — wall-mounted source, wall-snapped, never deletable
const TILE_WATER_SINK: int    = 18  ## Water system groundwork — rudimentary test endpoint, mirrors TILE_HEAVY, price $0

## Y height at which player-placed objects sit (world units).
## Matches the GridMap PLACEMENT_ROW height so free objects align with
## GridMap-stamped walls visually.
const PLACEMENT_Y: float = 1.0   ## World Y matching GridMap wall cell Y=1, cell_size=1

## Shelving uses the same Y as walls/pillars so the physics overlap check
## doesn't falsely detect the floor as an obstacle.
const SHELF_PLACEMENT_Y: float = 0.8

## Wall lights share the same base-Y as walls — the WallLight node self-offsets
## its mesh and SpotLight to 3/4 height internally.
const LIGHT_PLACEMENT_Y: float = 1.0

## Water hookup (July 2026 groundwork pass, raised per playtest feedback) —
## mounted near the ceiling (walls are 3.0m tall — see tile_set.tscn), above
## wall-light height (2.5m), so its pipes read as running along the "ceiling"
## rather than through the room at head height. WaterHookup has no internal
## self-offset (unlike WallLight) — this IS its visual height directly.
## WaterPipeDrawMode.WATER_CEILING_Y must be kept equal to this (see that
## file's own comment — two independent constants, same value, since the
## water system stays standalone/no cross-file dependency on BuildModeController).
const WATER_HOOKUP_PLACEMENT_Y: float = 2.8

## Generator sits on the floor; lowered by TestCrate rendered height (0.477m) so
## it visually rests flush with the ground plane.  1.0 - 0.477 ≈ 0.523.
const GEN_PLACEMENT_Y: float = 0.523

## How far (XZ) from the cursor to search for a wall surface to snap the light to.
## Raycasts in 4 cardinal directions; snaps to the nearest wall within this range.
const LIGHT_WALL_SNAP_RANGE: float = 1.5

## Offset from wall hit point back toward room — keeps fixture from z-fighting.
## Very small: LAMP_D = 0.14 m, so 0.05 leaves the back face nearly flush.
const LIGHT_WALL_HALF_THICKNESS: float = 0.05

## Overlap check half-extents for lights. Much tighter than a wall/shelf — lights
## are thin and can sit close together along a wall.
const LIGHT_OVERLAP_RADIUS: float = 0.20

# ─── Rock dig ─────────────────────────────────────────────────────────────────
const ROCK_DIG_COST: int = 1500

# ─── 8-Directional rotation (45° steps) ──────────────────────────────────────
## Eight Y-axis angles, 45° apart. Stored as degrees for readability.
const EIGHT_DIR_ANGLES: Array[float] = [
	0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0
]

var _orient_index:        int   = 0   ## Current index into EIGHT_DIR_ANGLES
var _current_angle_deg:   float = 0.0 ## Current ghost rotation in degrees

# ─── State ────────────────────────────────────────────────────────────────────
var is_active:            bool  = false
var _active_tool:         int   = 0   ## Mirrors BuildModeHUD tool IDs (0=Construct …)
var _selected_tile:       int   = TILE_WALL
var _selected_tile_price: int   = 50
var _ghost_active:        bool  = false

var _ghost:       MeshInstance3D = null
var _ghost_valid: bool           = false

## True when ghost is invalid specifically because a structure occupies the cell.
var _ghost_blocked_by_occupation: bool = false

## Current ghost snap position in world space (updated every frame)
var _ghost_world_pos: Vector3 = Vector3.ZERO

# ─── Rock hover state ─────────────────────────────────────────────────────────
## Chunk currently under the cursor in Deconstruct mode (sentinel = (-9999,-9999))
var _hovered_rock_chunk: Vector2i = Vector2i(-9999, -9999)

## Wire segment currently hovered in Deconstruct mode (null = none)
var _hovered_wire_segment: Node3D = null

## Pending dig confirmation — true when the HUD confirm dialog is open
var _pending_dig_chunk: Vector2i = Vector2i(-9999, -9999)

# ─── Connectable-object dot overlays ─────────────────────────────────────────
## Light-blue billboard dots shown above wire-connectable objects while build
## mode is active, so players can see what's wireable at a glance.
## Keys = Node3D object, Values = MeshInstance3D dot node added as child.
var _connectable_dots: Dictionary = {}

# ─── Placed-object registry ───────────────────────────────────────────────────
## Each entry: {
##   node:         StaticBody3D    — the physics/mesh container
##   tile_id:      int             — TILE_WALL / TILE_PILLAR / TILE_SHELVING
##   price:        int             — purchase price (for refund)
##   world_pos:    Vector3         — exact placed position
##   angle_deg:    float           — Y rotation in degrees
##   player_placed: bool           — true = player built it (can modify); false = level pregen/autofill (locked)
## }
var _placed_objects: Array[Dictionary] = []

# ─── Undo stack ───────────────────────────────────────────────────────────────
## Each entry type:
##   "place"    — undo a placement (remove node + refund)
##   "remove"   — undo a deconstruct (re-spawn node + deduct cash)
##   "dig_rock" — undo a rock dig (restore chunk + refund ROCK_DIG_COST)
##   "move"     — undo a move (teleport node back to original position)
var _undo_stack: Array[Dictionary] = []
const MAX_UNDO: int = 50

# ─── Duplicate source ─────────────────────────────────────────────────────────
var _dupe_source_tile:  int   = TILE_WALL
var _dupe_source_angle: float = 0.0
var _dupe_source_price: int   = 50

# ─── Move tool state ─────────────────────────────────────────────────────────
## Phase 0 = idle (hover glow only)
## Phase 1 = object selected, ghost follows cursor, click confirms
var _move_phase:        int             = 0
var _move_source_body:  Node3D          = null   ## The object being moved
var _move_source_entry: Dictionary      = {}     ## Its _placed_objects entry
var _move_source_pos:   Vector3         = Vector3.ZERO  ## Original position (for undo)
var _move_ghost:        MeshInstance3D  = null   ## Green ghost following cursor

# ─── Wire Draw Mode ───────────────────────────────────────────────────────────
const TOOL_WIRE: int = 5   ## Wire draw tool (not a construct item)
var _wire_draw_mode: Node = null   ## WireDrawMode sub-controller

# ─── Water Pipe Draw Mode (July 2026 groundwork pass) ────────────────────────
## Mirrors the Wire Draw Mode setup immediately above — same instantiate-as-
## child-node, same forward-refs-every-frame, same delegate-all-input pattern.
## See scripts/world/water/WaterPipeDrawMode.gd for the tool itself.
const TOOL_WATER_PIPE: int = 6   ## Water pipe draw tool (not a construct item)
var _water_pipe_draw_mode: Node = null   ## WaterPipeDrawMode sub-controller

# ─── Ghost materials ──────────────────────────────────────────────────────────
var _mat_valid:   StandardMaterial3D = null
var _mat_invalid: StandardMaterial3D = null

## Blue-tinted hover material for Duplicate tool
var _mat_hover:   StandardMaterial3D = null

# ─── World surface materials (textured) ──────────────────────────────────────
## Applied to placed walls/pillars and GridMap floor tiles at runtime.
var _mat_wall:    StandardMaterial3D = null
var _mat_floor:   StandardMaterial3D = null

## Green highlight material used for Move-selected object (same as _mat_valid but
## stored separately for clarity — shares the same material instance)
## We reuse _mat_valid directly.

# ─── Hover tracking for Duplicate / Move tools ────────────────────────────────
var _hovered_placed_body: Node3D = null

## Cache of per-surface override materials captured just before hover glow is applied.
## Key: "{MeshInstance3D instance_id}_{surface_index}" → StandardMaterial3D (or null)
## Restored when hover clears so walls/pillars keep their concrete texture.
var _hover_restore_mats: Dictionary = {}

## BuildMaterials.gd — ghost-preview + world-surface material builders
## (Stage 10 slice). No state physically moved here; see BuildMaterials.gd
## header comment.
var _materials: BuildMaterials = null

## BuildUndoStack.gd — undo/redo push+pop logic (Stage 10 slice). No state
## physically moved here; see BuildUndoStack.gd header comment.
var _undo_manager: BuildUndoStack = null

## GhostPreview.gd — ghost/preview mesh + per-frame update (Stage 10 slice).
## No state physically moved here; see GhostPreview.gd header comment.
var _ghost_preview: GhostPreview = null

## MoveDuplicateTool.gd — move/duplicate tool logic (Stage 10 slice). No
## state physically moved here; see MoveDuplicateTool.gd header comment.
var _move_tool: MoveDuplicateTool = null

## WallSnapHelpers.gd — wall/breaker-snap raycasting (Stage 10 slice). No
## state physically moved here; see WallSnapHelpers.gd header comment.
var _wall_snap: WallSnapHelpers = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_materials = BuildMaterials.new(self)
	_undo_manager = BuildUndoStack.new(self)
	_ghost_preview = GhostPreview.new(self)
	_move_tool = MoveDuplicateTool.new(self)
	_wall_snap = WallSnapHelpers.new(self)
	_build_ghost_materials()
	_build_world_materials()
	_setup_wire_draw_mode()
	_setup_water_pipe_draw_mode()

	## Repaint world wire tubes the instant a player recolors a zone via its
	## Power Terminal (PowerManager.set_zone_color_override()) — without this,
	## world wires would only pick up the new color on the NEXT wire/breaker
	## placement (whenever _recolor_wire_zones() next runs on its own).
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null and not pm.zone_color_changed.is_connected(_on_zone_color_changed):
		pm.zone_color_changed.connect(_on_zone_color_changed)

func _on_zone_color_changed(_zone_key: String) -> void:
	_recolor_wire_zones()

# ─── Activation ───────────────────────────────────────────────────────────────
func enter_build_mode() -> void:
	is_active = true
	_ghost_active = false

	if build_hud != null and gridmap != null:
		build_hud.gridmap = gridmap

	if build_hud != null:
		build_hud.show_hud()
		## Re-run tool activation so the selected tool is actually live,
		## not just visually highlighted. This handles wire mode re-entry
		## and ensures any tool's init logic fires on every build-mode entry.
		_on_tool_selected(_active_tool)
		_connect_hud_signals()

	# Show all wire segments while in build mode
	get_tree().call_group("wire_segment", "set_visible", true)

	# Show connectable-object indicator dots
	_refresh_connectable_dots()

	# Sync WireDrawMode refs (camera/world_node may have been set after _ready)
	_update_wire_draw_refs()
	_update_water_pipe_draw_refs()

	set_process(true)

	## Recolour wire zones on every build-mode entry.
	## Wall lights register deferred (one frame after _rebuild_auto_wires), so
	## the initial recolor called from MainWorld fires before they exist in the
	## graph. Re-running it here ensures zones are correctly coloured whenever
	## the player opens the build panel, regardless of registration timing.
	call_deferred("_recolor_wire_zones")

func exit_build_mode() -> void:
	is_active = false
	_cancel_ghost()
	_cancel_move()
	_clear_hover_glow()

	if _active_tool == TOOL_WIRE and _wire_draw_mode != null:
		_wire_draw_mode.deactivate()
	if _active_tool == TOOL_WATER_PIPE and _water_pipe_draw_mode != null:
		_water_pipe_draw_mode.deactivate()

	if build_hud != null:
		build_hud.hide_hud()
		_disconnect_hud_signals()

	## Hide all wire segments when leaving build mode.
	get_tree().call_group("wire_segment", "set_visible", false)

	## Remove connectable-object dots.
	_clear_connectable_dots()

	set_process(false)

# ─── Signal wiring ────────────────────────────────────────────────────────────
func _connect_hud_signals() -> void:
	if build_hud == null:
		return
	if not build_hud.tool_selected.is_connected(_on_tool_selected):
		build_hud.tool_selected.connect(_on_tool_selected)
	if not build_hud.construct_item_chosen.is_connected(_on_construct_item_chosen):
		build_hud.construct_item_chosen.connect(_on_construct_item_chosen)
	if not build_hud.cancel_requested.is_connected(_on_cancel_requested):
		build_hud.cancel_requested.connect(_on_cancel_requested)
	if not build_hud.undo_requested.is_connected(_on_undo_requested):
		build_hud.undo_requested.connect(_on_undo_requested)
	# Rock dig confirm dialog signals
	if not build_hud.dig_confirmed.is_connected(_on_dig_confirmed):
		build_hud.dig_confirmed.connect(_on_dig_confirmed)
	if not build_hud.dig_cancelled.is_connected(_on_dig_cancelled):
		build_hud.dig_cancelled.connect(_on_dig_cancelled)

func _disconnect_hud_signals() -> void:
	if build_hud == null:
		return
	if build_hud.tool_selected.is_connected(_on_tool_selected):
		build_hud.tool_selected.disconnect(_on_tool_selected)
	if build_hud.construct_item_chosen.is_connected(_on_construct_item_chosen):
		build_hud.construct_item_chosen.disconnect(_on_construct_item_chosen)
	if build_hud.cancel_requested.is_connected(_on_cancel_requested):
		build_hud.cancel_requested.disconnect(_on_cancel_requested)
	if build_hud.undo_requested.is_connected(_on_undo_requested):
		build_hud.undo_requested.disconnect(_on_undo_requested)
	if build_hud.dig_confirmed.is_connected(_on_dig_confirmed):
		build_hud.dig_confirmed.disconnect(_on_dig_confirmed)
	if build_hud.dig_cancelled.is_connected(_on_dig_cancelled):
		build_hud.dig_cancelled.disconnect(_on_dig_cancelled)

# ─── HUD signal handlers ──────────────────────────────────────────────────────
func _on_tool_selected(tool_id: int) -> void:
	# Deactivate wire draw mode if switching away
	if _active_tool == TOOL_WIRE and tool_id != TOOL_WIRE and _wire_draw_mode != null:
		_wire_draw_mode.deactivate()
	# Deactivate water pipe draw mode if switching away
	if _active_tool == TOOL_WATER_PIPE and tool_id != TOOL_WATER_PIPE and _water_pipe_draw_mode != null:
		_water_pipe_draw_mode.deactivate()

	_active_tool = tool_id
	_cancel_ghost()
	_cancel_move()
	_clear_hover_glow()

	# Activate wire draw mode when switching to it
	if tool_id == TOOL_WIRE and _wire_draw_mode != null:
		_wire_draw_mode.activate()
	# Activate water pipe draw mode when switching to it
	if tool_id == TOOL_WATER_PIPE and _water_pipe_draw_mode != null:
		_water_pipe_draw_mode.activate()

func _on_construct_item_chosen(tile_id: int) -> void:
	## Exit wire draw mode if it was active when the player picks a construct item
	if _active_tool == TOOL_WIRE and _wire_draw_mode != null:
		_wire_draw_mode.deactivate()
	## Exit water pipe draw mode if it was active when the player picks a construct item
	if _active_tool == TOOL_WATER_PIPE and _water_pipe_draw_mode != null:
		_water_pipe_draw_mode.deactivate()

	_selected_tile = tile_id
	_selected_tile_price = 0
	if build_hud != null:
		_selected_tile_price = build_hud.get_item_price(tile_id)

	_active_tool  = 0
	_ghost_active = true
	_spawn_ghost()

	if build_hud != null:
		build_hud.set_active_tool(0)
		build_hud.set_ghost_active(true)

func _on_cancel_requested() -> void:
	_cancel_ghost()
	# If in move phase 1, cancel returns to hover phase
	if _move_phase == 1:
		_cancel_move_confirm()

func _on_undo_requested() -> void:
	_undo()

func _on_dig_confirmed() -> void:
	## Player confirmed the rock dig — spend cash and dig
	if _pending_dig_chunk == Vector2i(-9999, -9999):
		return
	var chunk_id: Vector2i = _pending_dig_chunk
	_pending_dig_chunk = Vector2i(-9999, -9999)

	if rock_surround == null or world_node == null:
		return
	if not rock_surround.is_chunk_active(chunk_id):
		return

	if not world_node.spend_cash(ROCK_DIG_COST):
		_show_hud_warning("Not enough cash — $1,500 required")
		return

	var center: Vector3 = rock_surround.get_chunk_center(chunk_id)
	rock_surround.deconstruct_chunk(chunk_id)
	_push_undo_dig_rock(chunk_id, center)
	_spawn_float_label_at_pos(center, ROCK_DIG_COST, false)

func _on_dig_cancelled() -> void:
	_pending_dig_chunk = Vector2i(-9999, -9999)

# ─── Ghost activation / deactivation ─────────────────────────────────────────
func _cancel_ghost() -> void:
	_ghost_active = false
	_destroy_ghost()
	if build_hud != null:
		build_hud.set_ghost_active(false)

# ─── Process ──────────────────────────────────────────────────────────────────
## Build and attach billboard dots above all wire-connectable objects.
## Called once on build mode entry; call again if new objects are placed.
func _refresh_connectable_dots() -> void:
	_clear_connectable_dots()

	## Connectable tile IDs — generators, terminal, wall lights, water hookup/sink
	const CONNECTABLE_TILES: Array[int] = [
		TILE_GEN_S, TILE_GEN_M, TILE_GEN_L, TILE_TERMINAL, TILE_LIGHT,
		TILE_WATER_HOOKUP, TILE_WATER_SINK
	]

	## Dot material — light blue, billboard, always-on-top
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color              = Color(0.45, 0.85, 1.0, 0.90)
	mat.emission_enabled          = true
	mat.emission                  = Color(0.45, 0.85, 1.0, 1.0)
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test             = true
	mat.render_priority           = 3
	mat.billboard_mode            = BaseMaterial3D.BILLBOARD_ENABLED

	for entry: Dictionary in _placed_objects:
		var tile_id: int = entry.get("tile_id", -1)
		if tile_id not in CONNECTABLE_TILES:
			continue
		var obj: Node3D = entry.get("node", null)
		if obj == null or not is_instance_valid(obj):
			continue

		var dot_mi: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		sphere.radial_segments = 8
		sphere.rings = 4
		dot_mi.mesh = sphere
		dot_mi.set_surface_override_material(0, mat)
		dot_mi.extra_cull_margin = 10.0
		## Position above the object. Lights are wall-mounted at ~1.5m — dot goes at 1.0
		## so it hovers at a natural height rather than sitting on the floor.
		## Water hookup sits near-ceiling already (see WATER_HOOKUP_PLACEMENT_Y) —
		## a small offset is enough. Water sink is a short ground box (~0.30m tall).
		var dot_y: float = 0.30
		if tile_id == TILE_LIGHT:
			dot_y = 1.0
		elif tile_id == TILE_WATER_HOOKUP:
			dot_y = 0.20
		elif tile_id == TILE_WATER_SINK:
			dot_y = 0.45
		dot_mi.position = Vector3(0.0, dot_y, 0.0)
		obj.add_child(dot_mi)
		_connectable_dots[obj] = dot_mi

func _clear_connectable_dots() -> void:
	for obj in _connectable_dots.keys():
		var dot = _connectable_dots[obj]
		# dot may already be freed if its parent object was removed
		if dot != null and is_instance_valid(dot):
			dot.get_parent().remove_child(dot)
			dot.queue_free()
	_connectable_dots.clear()

func _process(_delta: float) -> void:
	if not is_active or camera == null:
		return

	if _ghost_active:
		_update_ghost()

	# ── Deconstruct overlay ──
	if _active_tool == 1 and build_hud != null:
		# Don't update hover while a confirm dialog is pending
		if build_hud.dig_confirm_open:
			pass
		else:
			var body: Node3D = _get_hovered_placed_body()

			## If the hovered body is a pregen structure, suppress the red box entirely
			## and fall through to wire/rock checks — pregen objects cannot be deconstructed.
			if body != null and body.has_meta("_is_pregen"):
				body = null

			if body != null:
				## Player-built object — show HUD red box overlay.
				build_hud.hovered_deconstruct_cell        = body.global_position
				build_hud.hovered_rock_chunk_world_pos    = Vector3(-9999.0, -9999.0, -9999.0)
				_hovered_rock_chunk   = Vector2i(-9999, -9999)
				## If we were previously highlighting a wire segment, clear it.
				if _hovered_wire_segment != null and is_instance_valid(_hovered_wire_segment):
					if _hovered_wire_segment.has_method("set_highlight_delete"):
						_hovered_wire_segment.set_highlight_delete(false)
				_hovered_wire_segment = null
			else:
				## Check for hovered wire segment before falling through to rock.
				var new_wire: Node3D = _get_hovered_wire_segment()

				## Clear highlight on previously highlighted wire if it changed.
				if _hovered_wire_segment != new_wire:
					if _hovered_wire_segment != null and is_instance_valid(_hovered_wire_segment):
						if _hovered_wire_segment.has_method("set_highlight_delete"):
							_hovered_wire_segment.set_highlight_delete(false)
					_hovered_wire_segment = new_wire
					if _hovered_wire_segment != null and _hovered_wire_segment.has_method("set_highlight_delete"):
						_hovered_wire_segment.set_highlight_delete(true)

				if _hovered_wire_segment != null:
					## Wire is hovered — suppress the HUD red box (the wire itself glows red).
					build_hud.hovered_deconstruct_cell        = Vector3(-9999.0, -9999.0, -9999.0)
					build_hud.hovered_rock_chunk_world_pos    = Vector3(-9999.0, -9999.0, -9999.0)
					_hovered_rock_chunk = Vector2i(-9999, -9999)
				else:
					build_hud.hovered_deconstruct_cell = Vector3(-9999.0, -9999.0, -9999.0)
					_hovered_rock_chunk = _get_hovered_rock_chunk()
					if _hovered_rock_chunk != Vector2i(-9999, -9999) and rock_surround != null:
						build_hud.hovered_rock_chunk_world_pos = rock_surround.get_chunk_center(_hovered_rock_chunk)
					else:
						build_hud.hovered_rock_chunk_world_pos = Vector3(-9999.0, -9999.0, -9999.0)
						_hovered_rock_chunk = Vector2i(-9999, -9999)
	elif build_hud != null:
		build_hud.hovered_deconstruct_cell        = Vector3(-9999.0, -9999.0, -9999.0)
		build_hud.hovered_rock_chunk_world_pos    = Vector3(-9999.0, -9999.0, -9999.0)
		_hovered_rock_chunk    = Vector2i(-9999, -9999)
		## Clear any lingering wire highlight when leaving deconstruct mode.
		if _hovered_wire_segment != null and is_instance_valid(_hovered_wire_segment):
			if _hovered_wire_segment.has_method("set_highlight_delete"):
				_hovered_wire_segment.set_highlight_delete(false)
		_hovered_wire_segment = null

	# ── Duplicate hover glow ──
	if _active_tool == 2:
		_update_hover_glow()
		if build_hud != null:
			if _hovered_placed_body != null:
				build_hud.hovered_dupe_rotate_pos = _hovered_placed_body.global_position
			else:
				build_hud.hovered_dupe_rotate_pos = Vector3(-9999.0, -9999.0, -9999.0)

	# ── Move tool (tool 3) ──
	elif _active_tool == 3:
		if _move_phase == 0:
			# Phase 0: just hover glow, like Duplicate
			_update_hover_glow()
			if build_hud != null:
				if _hovered_placed_body != null:
					build_hud.hovered_dupe_rotate_pos = _hovered_placed_body.global_position
				else:
					build_hud.hovered_dupe_rotate_pos = Vector3(-9999.0, -9999.0, -9999.0)
		elif _move_phase == 1:
			# Phase 1: move ghost follows cursor snap grid
			_update_move_ghost()
			if build_hud != null:
				build_hud.hovered_dupe_rotate_pos = Vector3(-9999.0, -9999.0, -9999.0)

	else:
		_clear_hover_glow()
		if build_hud != null:
			build_hud.hovered_dupe_rotate_pos = Vector3(-9999.0, -9999.0, -9999.0)

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	# Block all input while dig confirm dialog is open (except it handles its own input)
	if build_hud != null and build_hud.dig_confirm_open:
		return

	# ── Wire tool: delegate ALL input to WireDrawMode ────────────────────────
	# Handles mouse (LMB place, RMB cancel/exit) and keyboard (E/Escape = exit).
	if _active_tool == TOOL_WIRE and _wire_draw_mode != null:
		if _wire_draw_mode.handle_input(event):
			get_viewport().set_input_as_handled()
			return

	# ── Water pipe tool: delegate ALL input to WaterPipeDrawMode ─────────────
	if _active_tool == TOOL_WATER_PIPE and _water_pipe_draw_mode != null:
		if _water_pipe_draw_mode.handle_input(event):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _ghost_active and _active_tool == 0:
					_try_construct()
					get_viewport().set_input_as_handled()
					return
				match _active_tool:
					1:   _try_deconstruct();    get_viewport().set_input_as_handled()
					2:   _try_duplicate();      get_viewport().set_input_as_handled()
					3:   _try_move_click();     get_viewport().set_input_as_handled()

			MOUSE_BUTTON_RIGHT:
				if _ghost_active:
					_cancel_ghost()
				elif _active_tool == 3 and _move_phase == 1:
					# RMB cancels move confirmation, returns to phase 0
					_cancel_move_confirm()
				elif _active_tool == 2:
					_pick_dupe_source()
				else:
					_try_deconstruct()
				get_viewport().set_input_as_handled()

			MOUSE_BUTTON_WHEEL_UP:
				if _ghost_active:
					_rotate_cw()
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if _ghost_active:
					_rotate_ccw()
					get_viewport().set_input_as_handled()

# ─── Ghost management ─────────────────────────────────────────────────────────
# ─── Forwarded to GhostPreview.gd (Stage 10 slice) ────────────────────────────
## Only these 3 are still called from elsewhere in this file
## (_spawn_ghost/_update_ghost from tool-select + _process(); _destroy_ghost
## from _cancel_ghost() and internally from _spawn_ghost). _rebuild_ghost_mesh
## and _attach_ghost_direction_arrow are only called within GhostPreview
## itself, so need no wrapper. See GhostPreview.gd for the full cluster.
func _spawn_ghost() -> void:
	_ghost_preview._spawn_ghost()


func _destroy_ghost() -> void:
	_ghost_preview._destroy_ghost()


func _update_ghost() -> void:
	_ghost_preview._update_ghost()


# ─── Wire Draw Mode setup ─────────────────────────────────────────────────────
func _setup_wire_draw_mode() -> void:
	var wire_script: GDScript = load("res://scripts/world/power/WireDrawMode.gd")
	if wire_script == null:
		push_warning("[BuildModeController] WireDrawMode.gd not found")
		return
	_wire_draw_mode = Node.new()
	_wire_draw_mode.set_script(wire_script)
	_wire_draw_mode.name = "WireDrawMode"
	add_child(_wire_draw_mode)
	## Connect wire_placed signal so we can push an undo entry for every wire laid.
	if _wire_draw_mode.has_signal("wire_placed"):
		_wire_draw_mode.wire_placed.connect(_push_undo_wire)
	## Connect wire_nodes_connected so we can retroactively link nearby WallLights.
	if _wire_draw_mode.has_signal("wire_nodes_connected"):
		_wire_draw_mode.wire_nodes_connected.connect(_on_wire_nodes_connected)
	## Connect exit signal — E / Escape / RMB-phase0 deactivates wire tool and
	## returns to construct tool (tool_id 0) so cursor control is restored.
	if _wire_draw_mode.has_signal("wire_tool_exit_requested"):
		_wire_draw_mode.wire_tool_exit_requested.connect(_on_wire_tool_exit_requested)

## Called when player presses E / Escape / RMB-phase-0 inside wire draw mode.
## Exits wire tool and returns to construct tool (tool_id 0) so cursor is freed.
func _on_wire_tool_exit_requested() -> void:
	_on_tool_selected(0)
	## Tell BuildHUD to reflect the switch (deselects the wire button visually).
	if build_hud != null and build_hud.has_method("set_active_tool"):
		build_hud.set_active_tool(0)

func _update_wire_draw_refs() -> void:
	if _wire_draw_mode == null:
		return
	_wire_draw_mode.set("camera",     camera)
	_wire_draw_mode.set("world_node", world_node)
	_wire_draw_mode.set("build_hud",  build_hud)
	_wire_draw_mode.set("ray_length", ray_length)

# ─── Water Pipe Draw Mode setup (July 2026 groundwork pass) ─────────────────
## Identical shape to _setup_wire_draw_mode() immediately above.
func _setup_water_pipe_draw_mode() -> void:
	var pipe_script: GDScript = load("res://scripts/world/water/WaterPipeDrawMode.gd")
	if pipe_script == null:
		push_warning("[BuildModeController] WaterPipeDrawMode.gd not found")
		return
	_water_pipe_draw_mode = Node.new()
	_water_pipe_draw_mode.set_script(pipe_script)
	_water_pipe_draw_mode.name = "WaterPipeDrawMode"
	add_child(_water_pipe_draw_mode)
	if _water_pipe_draw_mode.has_signal("pipe_tool_exit_requested"):
		_water_pipe_draw_mode.pipe_tool_exit_requested.connect(_on_water_pipe_tool_exit_requested)

## Mirrors _on_wire_tool_exit_requested() — exits the pipe tool and returns to
## construct tool (tool_id 0) so cursor control is restored.
func _on_water_pipe_tool_exit_requested() -> void:
	_on_tool_selected(0)
	if build_hud != null and build_hud.has_method("set_active_tool"):
		build_hud.set_active_tool(0)

func _update_water_pipe_draw_refs() -> void:
	if _water_pipe_draw_mode == null:
		return
	_water_pipe_draw_mode.set("camera",     camera)
	_water_pipe_draw_mode.set("world_node", world_node)
	_water_pipe_draw_mode.set("build_hud",  build_hud)
	_water_pipe_draw_mode.set("ray_length", ray_length)

# ─── Bunker bounds check ──────────────────────────────────────────────────────
## Returns true if world-space XZ position is inside the valid placeable area:
## the pre-generated bunker interior + any dug rock extensions.
## We keep it simple: valid area = inside [OFFSET_X, OFFSET_X + bunker_depth] × [OFFSET_Z, OFFSET_Z + bunker_width].
## (Rock surround defines these exactly. Dug chunks extend the valid area, but they're
## inside the outer rock ring which itself lies just outside these bounds — so we give
## a generous outer margin of +1 cell to allow wall placement on the newly-revealed face.)
func _is_inside_bunker(pos: Vector3) -> bool:
	if rock_surround == null:
		return true   ## No bounds data — allow everywhere

	var ox: float = rock_surround.OFFSET_X
	var oz: float = rock_surround.OFFSET_Z
	var depth: int = rock_surround.bunker_depth
	var width: int = rock_surround.bunker_width

	## Tighter margin — 0.1 cells.  A margin of 1.0 was large enough to include
	## the exterior face of the original bunker walls, letting lights snap onto
	## the outside of the bunker.
	const MARGIN: float = 0.1
	var min_x: float = ox - MARGIN
	var max_x: float = ox + float(depth) + MARGIN
	var min_z: float = oz - MARGIN
	var max_z: float = oz + float(width) + MARGIN

	## Primary check — inside the original bunker rectangle.
	if pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z:
		return true

	## Secondary check — inside any DECONSTRUCTED (dug) chunk.
	## Dug areas extend beyond the original rectangle, so we look up the chunk
	## at this world position and return true only if it was dug out.
	if rock_surround.has_method("get_chunk_at_world_pos") and rock_surround.has_method("is_chunk_active"):
		var chunk_id: Vector2i = rock_surround.get_chunk_at_world_pos(pos)
		if chunk_id != Vector2i(-9999, -9999):
			## is_chunk_active returns TRUE when the chunk still has rock (not dug).
			## We want the OPPOSITE: a chunk is a valid building zone when it IS dug.
			if not rock_surround.is_chunk_active(chunk_id):
				return true   ## This area has been excavated — allow placement

	return false

# ─── Construct ────────────────────────────────────────────────────────────────
func _try_construct() -> void:
	if not _ghost_valid or gridmap == null:
		if _ghost_blocked_by_occupation:
			_show_hud_warning("Space is already occupied")
		return

	# Bounds check — reject placement outside the bunker/dig area
	if not _is_inside_bunker(_ghost_world_pos):
		_show_hud_warning("Cannot place outside the bunker")
		return

	if world_node != null:
		if not world_node.spend_cash(_selected_tile_price):
			return

	var placed_pos: Vector3 = _ghost_world_pos

	var body: Node3D = _spawn_placed_object(
		_selected_tile, placed_pos, _current_angle_deg
	)

	var entry: Dictionary = {
		"node":          body,
		"tile_id":       _selected_tile,
		"price":         _selected_tile_price,
		"world_pos":     placed_pos,
		"angle_deg":     _current_angle_deg,
		"player_placed": true,
	}
	_placed_objects.append(entry)

	## If this is a connectable tile, add its dot immediately (no full refresh needed).
	const CONNECTABLE_TILES_QUICK: Array[int] = [
		TILE_GEN_S, TILE_GEN_M, TILE_GEN_L, TILE_TERMINAL, TILE_LIGHT, TILE_HEAVY,
		TILE_BREAKER, TILE_BREAKER_SMART, TILE_BATTERY_S, TILE_BATTERY_M, TILE_BATTERY_L,
		TILE_WATER_HOOKUP, TILE_WATER_SINK
	]
	if _selected_tile in CONNECTABLE_TILES_QUICK:
		_refresh_connectable_dots()

	## Snapshot zone colors BEFORE breaker placement mutates zone topology.
	## This snapshot is stored in the undo entry and restored on undo so wire
	## colors revert exactly to their pre-placement state.
	## Applies to BOTH breaker variants — an upgraded breaker splits zones
	## identically to a standard one at placement time.
	var pre_place_color_snap: Dictionary = {}
	if _selected_tile == TILE_BREAKER or _selected_tile == TILE_BREAKER_SMART:
		var pm_snap: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if pm_snap != null:
			pre_place_color_snap = pm_snap.snapshot_zone_colors()

	_push_undo_place(body, _selected_tile, _selected_tile_price, placed_pos, pre_place_color_snap)
	_spawn_float_label_at_pos(placed_pos, _selected_tile_price, false)

	## If a breaker was just placed, recolour zones — the graph topology changed.
	## We restore the pre-placement snapshot first so get_wire_zones_with_colors()
	## can match surviving rep keys to their pre-split colors.  Without this, the
	## newly split zone has no registry entry and gets an arbitrary new color.
	## The restore + recolor must fire AFTER BreakerBox._register_wire_deferred()
	## (which runs call_deferred from add_child).  Since call_deferred is FIFO and
	## the breaker node's deferred was queued at add_child time (earlier this frame),
	## our deferred here fires after it — correct ordering guaranteed.
	## Applies to BOTH breaker variants (UpgradedBreakerBox extends BreakerBox
	## and its own _register_wire_deferred() calls super() first, same ordering).
	if _selected_tile == TILE_BREAKER or _selected_tile == TILE_BREAKER_SMART:
		var snap_for_recolor: Dictionary = pre_place_color_snap.duplicate()
		call_deferred("_restore_then_recolor", snap_for_recolor)

func _spawn_placed_object(tile_id: int, pos: Vector3, angle_deg: float) -> Node3D:
	## Creates the physics/mesh node at the given world position, rotated angle_deg around Y.

	# ── Bed: scene-based node ──────────────────────────────────────────────────
	if tile_id == TILE_BED:
		var bed_scene_path: String = "res://scenes/world/Bed.tscn"
		var bed_script_path: String = "res://scripts/world/furniture/Bed.gd"
		var bed_node: StaticBody3D

		# Try loading a Bed scene first; fall back to procedural box
		var packed: PackedScene = load(bed_scene_path) if ResourceLoader.exists(bed_scene_path) else null
		if packed != null:
			bed_node = packed.instantiate() as StaticBody3D
		else:
			# Procedural fallback: flat box (2m × 0.5m × 1m)
			bed_node = StaticBody3D.new()
			bed_node.collision_layer = 5
			bed_node.collision_mask  = 0
			var mi: MeshInstance3D = MeshInstance3D.new()
			var bm: BoxMesh = BoxMesh.new()
			bm.size = Vector3(2.0, 0.5, 1.0)
			mi.mesh = bm
			mi.position = Vector3(0.0, 0.25, 0.0)
			bed_node.add_child(mi)
			mi.create_trimesh_collision()
			for child in mi.get_children():
				if child is StaticBody3D:
					(child as StaticBody3D).collision_layer = 5
					(child as StaticBody3D).collision_mask  = 0
			# Apply wall material so it matches bunker aesthetic
			_apply_world_material(bed_node, TILE_WALL)

		# Attach Bed script if it exists and node doesn't already have one
		if ResourceLoader.exists(bed_script_path) and bed_node.get_script() == null:
			var bed_script: GDScript = load(bed_script_path)
			bed_node.set_script(bed_script)

		bed_node.set_meta("tile_id", tile_id)
		var parent: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		parent.add_child(bed_node)
		bed_node.global_position  = pos
		bed_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return bed_node

	# ── Shelving: script-based procedural node ─────────────────────────────────
	if tile_id == TILE_SHELVING:
		var shelving_script: GDScript = load("res://scripts/world/furniture/Shelving.gd")
		var shelf_node: StaticBody3D  = StaticBody3D.new()
		shelf_node.set_script(shelving_script)
		shelf_node.set_meta("tile_id", tile_id)

		var parent: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		parent.add_child(shelf_node)
		shelf_node.global_position  = pos
		shelf_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)

		var isys: Node = get_parent().get_node_or_null("InteractionSystem")
		if isys != null:
			shelf_node.set("_interaction_system", isys)

		var wn: Node = get_tree().get_first_node_in_group("world")
		if wn != null:
			var sui: Node = wn.get_node_or_null("ShelfUI")
			if sui != null:
				shelf_node.set("_shelf_ui", sui)

		return shelf_node

	# ── Wall light: script-based node (Node3D — no collision) ────────────────
	if tile_id == TILE_LIGHT:
		var light_script: GDScript = load("res://scripts/world/power/WallLight.gd")
		if light_script == null:
			push_error("BuildModeController: WallLight.gd failed to load — light will not register with PowerManager!")
		var light_node: Node3D = Node3D.new()
		if light_script != null:
			light_node.set_script(light_script)
		light_node.set_meta("tile_id", tile_id)

		var parent: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		parent.add_child(light_node)
		light_node.global_position  = pos
		light_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)

		## WallLight._ready() self-registers with PowerManager via its own _register_with_power_manager().
		## BuildModeController does NOT duplicate-register here — _ready() fires after add_child()
		## and handles it. Zone assignment: set power_zone on the node before it enters the tree
		## so _ready() picks it up. Default = "main" until room-zone system is wired in.
		## To assign a room zone later:
		##   light_node.set("power_zone", "dormitory")  ## call before add_child()

		return light_node

	# ── Generators: script-based procedural node ─────────────────────────────
	if tile_id == TILE_GEN_S or tile_id == TILE_GEN_M or tile_id == TILE_GEN_L:
		var gen_script: GDScript = load("res://scripts/world/power/GeneratorObject.gd")
		if gen_script == null:
			push_error("BuildModeController: GeneratorObject.gd failed to load — generator will not register with PowerManager!")
		var gen_node: StaticBody3D = StaticBody3D.new()
		if gen_script != null:
			gen_node.set_script(gen_script)
		var tier: int = 0
		if tile_id == TILE_GEN_M: tier = 1
		elif tile_id == TILE_GEN_L: tier = 2
		gen_node.set("generator_tier", tier)
		gen_node.set_meta("tile_id", tile_id)
		var gpar: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		gpar.add_child(gen_node)
		gen_node.global_position  = pos
		gen_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return gen_node

	# ── Power Terminal: wall-mounted dashboard panel ──────────────────────────
	if tile_id == TILE_TERMINAL:
		var term_script: GDScript = load("res://scripts/world/power/PowerTerminal.gd")
		var term_node: StaticBody3D = StaticBody3D.new()
		if term_script != null:
			term_node.set_script(term_script)
		term_node.set_meta("tile_id", TILE_TERMINAL)
		var tpar: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		tpar.add_child(term_node)
		term_node.global_position  = pos
		term_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return term_node

	## ── Heavy load test consumer ──────────────────────────────────────────────
	if tile_id == TILE_HEAVY:
		var hc_script: GDScript = load("res://scripts/world/items/HeavyConsumerTest.gd")
		var hc_node: StaticBody3D = StaticBody3D.new()
		if hc_script != null:
			hc_node.set_script(hc_script)
		hc_node.set_meta("tile_id", TILE_HEAVY)
		var hpar: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		hpar.add_child(hc_node)
		hc_node.global_position  = pos
		hc_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return hc_node

	## ── Water hookup (July 2026 groundwork pass) — wall-mounted source ───────
	if tile_id == TILE_WATER_HOOKUP:
		var wh_script: GDScript = load("res://scripts/world/water/WaterHookup.gd")
		var wh_node: StaticBody3D = StaticBody3D.new()
		if wh_script != null:
			wh_node.set_script(wh_script)
		wh_node.set_meta("tile_id", TILE_WATER_HOOKUP)
		var whpar: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		whpar.add_child(wh_node)
		wh_node.global_position  = pos
		wh_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return wh_node

	## ── Water test sink (July 2026 groundwork pass) — rudimentary endpoint ───
	if tile_id == TILE_WATER_SINK:
		var ws_script: GDScript = load("res://scripts/world/water/WaterTestSink.gd")
		var ws_node: StaticBody3D = StaticBody3D.new()
		if ws_script != null:
			ws_node.set_script(ws_script)
		ws_node.set_meta("tile_id", TILE_WATER_SINK)
		var wspar: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		wspar.add_child(ws_node)
		ws_node.global_position  = pos
		ws_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return ws_node

	## ── Circuit breaker (standard) ─────────────────────────────────────────────
	if tile_id == TILE_BREAKER:
		var brk_script: GDScript = load("res://scripts/world/power/BreakerBox.gd")
		var brk_node: StaticBody3D = StaticBody3D.new()
		if brk_script != null:
			brk_node.set_script(brk_script)
		brk_node.set_meta("tile_id", TILE_BREAKER)
		var brk_par: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		brk_par.add_child(brk_node)
		brk_node.global_position  = pos
		brk_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return brk_node

	## ── Circuit breaker (upgraded / "smart") ────────────────────────────────────
	## Identical spawn pattern to the standard breaker — only the script differs.
	## UpgradedBreakerBox.gd extends BreakerBox.gd and marks itself "upgraded"
	## with PowerManager once its deferred wire registration completes.
	if tile_id == TILE_BREAKER_SMART:
		var ubrk_script: GDScript = load("res://scripts/world/power/UpgradedBreakerBox.gd")
		var ubrk_node: StaticBody3D = StaticBody3D.new()
		if ubrk_script != null:
			ubrk_node.set_script(ubrk_script)
		ubrk_node.set_meta("tile_id", TILE_BREAKER_SMART)
		var ubrk_par: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		ubrk_par.add_child(ubrk_node)
		ubrk_node.global_position  = pos
		ubrk_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return ubrk_node

	## ── Battery bank (all three tiers) ────────────────────────────────────────
	if tile_id == TILE_BATTERY_S or tile_id == TILE_BATTERY_M \
			or tile_id == TILE_BATTERY_L:
		var bat_tier: int = 0
		if tile_id == TILE_BATTERY_M: bat_tier = 1
		elif tile_id == TILE_BATTERY_L: bat_tier = 2
		var bat_script: GDScript = load("res://scripts/world/power/BatteryBank.gd")
		var bat_node: StaticBody3D = StaticBody3D.new()
		if bat_script != null:
			bat_node.set_script(bat_script)
		bat_node.set("battery_tier", bat_tier)
		bat_node.set_meta("tile_id", tile_id)
		var bat_par: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		bat_par.add_child(bat_node)
		bat_node.global_position  = pos
		bat_node.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return bat_node

	# ── Wire segment: flat box placeholder ────────────────────────────────────
	if tile_id == TILE_WIRE:
		var wire_body: StaticBody3D = StaticBody3D.new()
		wire_body.collision_layer = 5
		wire_body.collision_mask  = 0
		wire_body.set_meta("tile_id", tile_id)
		var wire_mi: MeshInstance3D = MeshInstance3D.new()
		var wire_mesh: BoxMesh = BoxMesh.new()
		wire_mesh.size = Vector3(0.90, 0.06, 0.08)
		wire_mi.mesh   = wire_mesh
		wire_mi.position = Vector3(0.0, 0.03, 0.0)
		var wire_mat: StandardMaterial3D = StandardMaterial3D.new()
		wire_mat.albedo_color = Color(0.12, 0.12, 0.12, 1.0)
		wire_mi.set_surface_override_material(0, wire_mat)
		wire_body.add_child(wire_mi)
		wire_mi.create_trimesh_collision()
		for child in wire_mi.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).collision_layer = 5
				(child as StaticBody3D).collision_mask  = 0
		var wpar: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
		wpar.add_child(wire_body)
		wire_body.global_position  = pos
		wire_body.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		return wire_body

	# ── MeshLibrary tiles (wall / pillar) ──────────────────────────────────────
	var body: StaticBody3D = StaticBody3D.new()
	## Layer 1 (value 1) = default physics world — player CharacterBody3D collides here.
	## Layer 3 (value 4) = build-placed objects — hover raycast uses mask 4.
	## Combined: layer 1 + layer 3 = value 5.
	body.collision_layer   = 5
	body.collision_mask    = 0

	var mi: MeshInstance3D = MeshInstance3D.new()
	var lib: MeshLibrary   = gridmap.mesh_library
	if lib != null:
		var mesh: Mesh = lib.get_item_mesh(tile_id)
		if mesh != null:
			mi.mesh = mesh
			body.add_child(mi)
			mi.create_trimesh_collision()
			## create_trimesh_collision() spawns a child StaticBody3D inside mi.
			## Give it the same combined layer (5) so both the player AND the
			## hover raycast (mask 4) can detect it, with parent-walk fallback.
			for child in mi.get_children():
				if child is StaticBody3D:
					(child as StaticBody3D).collision_layer = 5
					(child as StaticBody3D).collision_mask  = 0
		else:
			body.add_child(mi)
	else:
		body.add_child(mi)

	body.set_meta("tile_id", tile_id)

	var scene_parent: Node = gridmap.get_parent() if gridmap != null else get_tree().get_root()
	scene_parent.add_child(body)

	body.global_position   = pos
	body.rotation_degrees  = Vector3(0.0, angle_deg, 0.0)

	## Apply world texture material (walls/pillars get concrete_wall)
	_apply_world_material(body, tile_id)

	return body

# ─── Deconstruct ──────────────────────────────────────────────────────────────
func _try_deconstruct() -> void:
	# ── Attempt rock chunk dig first ──
	if _hovered_rock_chunk != Vector2i(-9999, -9999) and rock_surround != null:
		_try_dig_rock()
		return

	# ── Wire segment deconstruct ──
	if _hovered_wire_segment != null and is_instance_valid(_hovered_wire_segment):
		_try_deconstruct_wire(_hovered_wire_segment)
		return

	# ── Standard placed-object deconstruct ──
	var body: Node3D = _get_hovered_placed_body()
	if body == null:
		return

	var player: Node3D = get_parent()
	if player.global_position.distance_to(body.global_position) > build_reach:
		return

	var entry_idx: int = -1
	for i: int in _placed_objects.size():
		if _placed_objects[i]["node"] == body:
			entry_idx = i
			break
	if entry_idx == -1:
		return

	var entry: Dictionary = _placed_objects[entry_idx]

	# Guard: level-placed objects (pregen / autofill) cannot be deconstructed
	if not entry.get("player_placed", true):
		_show_hud_warning("Cannot modify level structure")
		return

	# Guard: the water hookup can never be removed, only relocated (Move tool).
	# See scripts/world/water/WaterHookup.gd file header — no "return to
	# inventory" flow exists for it by design.
	if entry.get("tile_id", -1) == TILE_WATER_HOOKUP:
		_show_hud_warning("Water hookup cannot be removed — use Move instead")
		return

	var refund: int         = entry["price"]
	var placed_pos: Vector3 = entry["world_pos"]

	_push_undo_remove(entry["tile_id"], refund, placed_pos, entry["angle_deg"])

	if body.has_method("eject_all_items"):
		body.eject_all_items()

	## Unregister from power grid before freeing
	if entry["tile_id"] == TILE_LIGHT:
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if pm != null:
			pm.unregister_consumer(str(body.get_instance_id()))
	elif entry["tile_id"] == TILE_GEN_S or entry["tile_id"] == TILE_GEN_M \
			or entry["tile_id"] == TILE_GEN_L:
		## GeneratorObject._exit_tree() handles its own unregister_generator +
		## unregister_wire_node calls, but we can also call explicitly for safety.
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if pm != null:
			var gid: String = str(body.get_instance_id())
			pm.unregister_generator(gid)
			pm.unregister_wire_node(gid)
	elif entry["tile_id"] == TILE_HEAVY:
		## HeavyConsumerTest._exit_tree() self-unregisters, but call explicitly too.
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if pm != null:
			var hid: String = str(body.get_instance_id())
			pm.unregister_consumer(hid)
			pm.unregister_wire_node(hid)
	elif entry["tile_id"] == TILE_BREAKER or entry["tile_id"] == TILE_BREAKER_SMART:
		## BreakerBox._exit_tree() self-unregisters via its own _exit_tree()
		## (UpgradedBreakerBox inherits it unmodified — same cleanup applies).
		## No explicit PM call needed here — script handles cleanup.
		pass
	elif entry["tile_id"] == TILE_BATTERY_S or entry["tile_id"] == TILE_BATTERY_M \
			or entry["tile_id"] == TILE_BATTERY_L:
		## BatteryBank._exit_tree() self-unregisters.  No explicit PM call needed.
		pass

	var deconstructed_tile: int = entry["tile_id"]
	_placed_objects.remove_at(entry_idx)
	body.queue_free()

	## Cascade: free any wire segments whose wire-node was registered to this object.
	## The object's wire_key was unregistered above; PM now has no node for those
	## edges. Find all WireSegment scene nodes whose edge_id references an edge
	## that is no longer in PowerManager and free them.
	_remove_dangling_wire_segments()

	## If a breaker was removed, zone topology changed — recolour remaining wires.
	## Connect to tree_exited so _recolor fires AFTER _exit_tree() has finished
	## calling unregister_breaker (which re-stitches the wire edge).  Using
	## call_deferred races against _exit_tree and produces stale colors.
	if deconstructed_tile == TILE_BREAKER or deconstructed_tile == TILE_BREAKER_SMART:
		body.tree_exited.connect(_recolor_wire_zones, CONNECT_ONE_SHOT)

	if refund > 0 and world_node != null:
		world_node.add_cash(refund)

	# If a wall or pillar was destroyed, remove any lights that were mounted on it.
	# A light is "on" this structure if its XZ is within LIGHT_WALL_SNAP_RANGE of it.
	if entry["tile_id"] == TILE_WALL or entry["tile_id"] == TILE_PILLAR:
		_remove_unsupported_lights_near(placed_pos)

	_spawn_float_label_at_pos(placed_pos, refund, true)

# ─── Rock dig ─────────────────────────────────────────────────────────────────
func _try_dig_rock() -> void:
	if rock_surround == null:
		return
	var chunk_id: Vector2i = _hovered_rock_chunk
	if chunk_id == Vector2i(-9999, -9999):
		return
	if not rock_surround.is_chunk_active(chunk_id):
		return

	var center: Vector3 = rock_surround.get_chunk_center(chunk_id)
	var player: Node3D  = get_parent()
	var rock_reach: float = build_reach * 3.0
	if player.global_position.distance_to(center) > rock_reach:
		return

	# Instead of digging immediately, open the confirm dialog in the HUD
	_pending_dig_chunk = chunk_id
	if build_hud != null:
		build_hud.open_dig_confirm()

# ─── Wire deconstruct helpers ─────────────────────────────────────────────────

## Cost per metre constant — matches WireDrawMode.COST_PER_M.
const WIRE_COST_PER_M: float = 8.0

## Raycast for a wire segment under the cursor.
## WireSegments are Node3D (no physics body) — we use a proximity scan
## against the camera ray instead of a physics raycast.
func _get_hovered_wire_segment() -> Node3D:
	if camera == null:
		return null

	var vp: Viewport       = get_viewport()
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3    = camera.project_ray_normal(mouse_pos)

	var best_ws: Node3D  = null
	var best_dist: float = 0.35   ## Max perpendicular distance to ray (metres)

	for node: Node in get_tree().get_nodes_in_group("wire_segment"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var ws: Node3D = node as Node3D
		## Pregen wires are protected — skip so they never show the red hover highlight.
		if ws.has_meta("_is_pregen"):
			continue
		## Point-to-ray distance check
		var to_ws: Vector3 = ws.global_position - ray_origin
		var proj: float    = to_ws.dot(ray_dir)
		if proj < 0.0 or proj > ray_length:
			continue
		var closest_on_ray: Vector3 = ray_origin + ray_dir * proj
		var perp_dist: float = ws.global_position.distance_to(closest_on_ray)
		if perp_dist < best_dist:
			best_dist = perp_dist
			best_ws   = ws

	return best_ws

## Deconstruct a specific wire segment: unregister edge from PM, refund, free node.
func _try_deconstruct_wire(ws: Node3D) -> void:
	if not is_instance_valid(ws):
		return

	## Pregen wires are part of the bunker structure — block deletion.
	if ws.has_meta("_is_pregen"):
		return

	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager

	## Calculate refund from segment length × cost-per-metre
	var edge_id: String = ws.get("edge_id") if ws.get("edge_id") != null else ""
	var pt_a: Vector3   = ws.get("point_a") if ws.get("point_a") != null else Vector3.ZERO
	var pt_b: Vector3   = ws.get("point_b") if ws.get("point_b") != null else Vector3.ZERO
	var length: float   = pt_a.distance_to(pt_b)
	var refund: int     = int(length * WIRE_COST_PER_M)

	## Unregister from PowerManager
	if pm != null and not edge_id.is_empty():
		pm.unregister_wire_edge(edge_id)

	## Refund and float label
	if refund > 0 and world_node != null:
		world_node.add_cash(refund)
		_spawn_float_label_at_pos(ws.global_position, refund, true)

	## Clear the red highlight before freeing — avoids stale material on a dead node.
	if ws.has_method("set_highlight_delete"):
		ws.set_highlight_delete(false)
	_hovered_wire_segment = null
	ws.queue_free()

	## Wire removed — zone topology changed, recolour remaining wires.
	call_deferred("_recolor_wire_zones")

## After an object is deconstructed, scan for wire segments whose PM edges no
## longer exist (the object's wire node was just unregistered) and free them.
func _remove_dangling_wire_segments() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return

	for node: Node in get_tree().get_nodes_in_group("wire_segment"):
		if not is_instance_valid(node):
			continue
		var ws: Node3D  = node as Node3D
		var edge_id: String = ws.get("edge_id") if ws.get("edge_id") != null else ""
		if edge_id.is_empty():
			continue
		## Player-placed wire segments use a "pw_" stable key, not a PM edge ID.
		## Their edge_id is re-registered by MainWorld PassD after every rebuild,
		## so they will never appear in _wire_edges during the rebuild window.
		## Skip them here — MainWorld owns their lifecycle.
		if edge_id.begins_with("pw_"):
			continue
		## Check if PM still has this edge
		var pm_edges: Dictionary = pm.get("_wire_edges") if pm.get("_wire_edges") != null else {}
		if not pm_edges.has(edge_id):
			ws.queue_free()

# ─── Rock hover raycast ───────────────────────────────────────────────────────
func _get_hovered_rock_chunk() -> Vector2i:
	if rock_surround == null or camera == null:
		return Vector2i(-9999, -9999)

	var vp: Viewport       = get_viewport()
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var from: Vector3      = camera.project_ray_origin(mouse_pos)
	var dir: Vector3       = camera.project_ray_normal(mouse_pos)
	var to: Vector3        = from + dir * ray_length

	var space: PhysicsDirectSpaceState3D   = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 16
	query.hit_back_faces = false
	var player: Node3D = get_parent()
	if player.has_method("get_rid"):
		query.exclude = [player.get_rid()]

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return Vector2i(-9999, -9999)

	var hit_pos: Vector3 = result["position"]
	var chunk_id: Vector2i = rock_surround.get_chunk_at_world_pos(hit_pos)
	if not rock_surround.is_chunk_active(chunk_id):
		return Vector2i(-9999, -9999)

	return chunk_id

# ─── Duplicate ────────────────────────────────────────────────────────────────
# ─── Forwarded to MoveDuplicateTool.gd (Stage 10 slice) ───────────────────────
## These 6 are still called from elsewhere in this file (_try_duplicate/
## _pick_dupe_source/_try_move_click from input handling; _update_move_ghost
## from _process(); _cancel_move_confirm/_cancel_move from tool-switch/exit/
## undo-request paths). _move_select, _spawn_move_ghost, _move_confirm, and
## _destroy_move_ghost are only called within MoveDuplicateTool itself, so
## need no wrapper. See MoveDuplicateTool.gd for the full cluster.
func _try_duplicate() -> void:
	_move_tool._try_duplicate()


func _pick_dupe_source() -> void:
	_move_tool._pick_dupe_source()


func _try_move_click() -> void:
	_move_tool._try_move_click()


func _update_move_ghost() -> void:
	_move_tool._update_move_ghost()


func _cancel_move_confirm() -> void:
	_move_tool._cancel_move_confirm()


func _cancel_move() -> void:
	_move_tool._cancel_move()


# ─── Rotation of ghost ────────────────────────────────────────────────────────
func _rotate_cw() -> void:
	_orient_index       = (_orient_index + 1) % EIGHT_DIR_ANGLES.size()
	_current_angle_deg  = EIGHT_DIR_ANGLES[_orient_index]

func _rotate_ccw() -> void:
	_orient_index       = (_orient_index - 1 + EIGHT_DIR_ANGLES.size()) % EIGHT_DIR_ANGLES.size()
	_current_angle_deg  = EIGHT_DIR_ANGLES[_orient_index]

# ─── Undo ─────────────────────────────────────────────────────────────────────
# ─── Forwarded to BuildUndoStack.gd (Stage 10 slice) ──────────────────────────
## All 6 are called from elsewhere in this file (_undo from
## _on_undo_requested(); the 5 push helpers from construct/deconstruct/dig/
## move/wire placement code). See BuildUndoStack.gd for the full cluster.
func _undo() -> void:
	_undo_manager._undo()


func _push_undo_place(body: Node3D, tile_id: int, price: int, pos: Vector3,
		zone_color_snap: Dictionary = {}) -> void:
	_undo_manager._push_undo_place(body, tile_id, price, pos, zone_color_snap)


func _push_undo_remove(tile_id: int, price: int, pos: Vector3, angle_deg: float) -> void:
	_undo_manager._push_undo_remove(tile_id, price, pos, angle_deg)


func _push_undo_dig_rock(chunk_id: Vector2i, center: Vector3) -> void:
	_undo_manager._push_undo_dig_rock(chunk_id, center)


func _push_undo_move(body: Node3D, reg_entry: Dictionary, old_pos: Vector3) -> void:
	_undo_manager._push_undo_move(body, reg_entry, old_pos)


func _push_undo_wire(seg_node: Node3D, edge_id: String, cost: int, midpoint: Vector3) -> void:
	_undo_manager._push_undo_wire(seg_node, edge_id, cost, midpoint)



## Called by WireDrawMode after a wire is placed — both endpoints and their
## world positions. Notifies any WallLight or BreakerBox (incl. the upgraded
## variant) near either endpoint so they can retroactively link to the wire
## (objects placed before wire drawn).
func _on_wire_nodes_connected(key_a: String, pos_a: Vector3, key_b: String, pos_b: Vector3) -> void:
	for entry: Dictionary in _placed_objects:
		var tid: int = entry.get("tile_id", -1)
		if tid != TILE_LIGHT and tid != TILE_BREAKER and tid != TILE_BREAKER_SMART:
			continue
		var obj_node: Node3D = entry.get("node", null) as Node3D
		if obj_node == null or not is_instance_valid(obj_node):
			continue
		if obj_node.has_method("notify_wire_placed"):
			obj_node.call("notify_wire_placed", key_a, pos_a)
			obj_node.call("notify_wire_placed", key_b, pos_b)
	## Recolour wire zones any time a new wire segment is placed.
	_recolor_wire_zones()

## ─── Wire zone colourisation ─────────────────────────────────────────────────
## Assigns a distinct colour to each wire zone (graph segment between breakers)
## so the player can see which consumers/runs belong to which zone in build mode.
##
## Zones are computed by PowerManager.get_wire_zones() — a BFS graph partition
## that treats breaker nodes as cut-points. If no breakers exist all wires get
## the default colour (Color.TRANSPARENT = revert to WireSegment default).
##
## ZONE COLORING RULE:
##   A zone is only coloured when it is ENCLOSED — meaning every wire path
##   leaving that zone terminates at a breaker node (not an open wire end).
##   In practice: only colour zones that have 2+ edges that touch a breaker.
##   A zone with only one breaker boundary (dead-end spur) stays default.
##   This means:
##     0 breakers → no colouring at all
##     1 breaker  → no colouring (all zones have ≤ 1 breaker boundary)
##     2 breakers → the segment BETWEEN them is coloured; outer runs stay default
##
## Call this after ANY wire or breaker is placed or removed.
## Restore zone color registry from snapshot then recolor.
## Called deferred after a breaker is placed so the pre-split registry state
## is available to get_wire_zones_with_colors() when it re-assigns colors.
func _restore_then_recolor(snap: Dictionary) -> void:
	if not snap.is_empty():
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if pm != null:
			pm.restore_zone_colors(snap)
	_recolor_wire_zones()


func _recolor_wire_zones() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return

	## ── 0. RECONCILE GEOMETRY FIRST ──────────────────────────────────────────
	## Force every scene tube to span its logical edge's TRUE endpoints before
	## we color anything.  This makes the visual layer a pure derivative of the
	## power graph — a zone seam can never drift from the breaker, because the
	## mesh is re-derived from the graph on every grid change.  (One-mesh-per-
	## edge + orphan cleanup is enforced inside reconcile_wire_visuals.)
	pm.reconcile_wire_visuals()

	## ── 0b. SHOW reconciled/spawned tubes (build-mode parity) ────────────────
	## reconcile_wire_visuals() may have spawned fresh tubes (which default to
	## visible=false in WireSegment._ready) or re-shown ones it rebuilt.  On
	## build-mode ENTRY this is handled by the call_group broadcast, but after
	## an in-place wire/breaker/object placement no broadcast runs — so the new
	## portion stays invisible and looks "deleted" until the player re-enters
	## build mode.  Re-broadcasting visibility here (only while build mode is
	## active) makes placement behave identically to a fresh build-mode entry.
	## Gated on is_active so wires stay hidden in play mode.
	if is_active:
		get_tree().call_group("wire_segment", "set_visible", true)

	## Palette comes from PowerManager (single source of truth) at alpha 0.60.
	## Use pm.zone_color_at(index) — no local palette copy.

	## ── 1. Build PM edge map ─────────────────────────────────────────────────
	var all_pm_edges: Dictionary = {}   ## edge_id → edge dict
	for edge: Dictionary in (pm.get_wire_edges() as Array):
		all_pm_edges[edge.get("id", "")] = edge

	## ── 2. Build edge_id → Color map from zones ──────────────────────────────
	var edge_color_map: Dictionary = {}   ## edge_id (+ reverse alias) → Color

	var zones: Array[Dictionary] = pm.get_wire_zones_with_colors()

	for zone: Dictionary in zones:
		var cidx: int   = zone.get("color_index", zone.get("index", 0))
		var zkey: String = String(zone.get("zone_key", ""))
		var eids: Array = zone.get("edge_ids", [])
		## zone_display_color() checks the player's color override (set via a
		## Power Terminal's color-picker UI) before falling back to the
		## algorithmic palette — world wires must match the terminal's swatch.
		var col: Color  = pm.zone_display_color(zkey, cidx, 0.60)
		for eid: String in eids:
			edge_color_map[eid] = col
			## Reverse-direction alias so b__a lookups also resolve.
			var parts: Array = eid.lstrip("e_").split("__")
			if parts.size() == 2:
				var rev: String = "e_%s__%s" % [parts[1], parts[0]]
				if rev != eid:
					edge_color_map[rev] = col

	## ── 3. Color every scene WireSegment ─────────────────────────────────────
	## Each logical edge now owns exactly ONE scene tube — every spawn path in
	## PowerManager._split_wire_edge_at() reuses an existing mesh before creating
	## a new one (Step 2 root-cause fix), and unregister_breaker() frees the
	## redundant M→B tube on re-stitch.  The old dedup "SAFETY NET" that
	## queue_free()'d duplicates here is therefore no longer needed.
	## We still track seen edge_ids so the section-4 fallback knows which edges
	## the group pass already handled.
	var seen_edge_ids: Dictionary = {}   ## edge_id → kept Node
	for wn: Node in get_tree().get_nodes_in_group("wire_segment"):
		if not is_instance_valid(wn):
			continue
		var eid: String = wn.get("edge_id") if wn.get("edge_id") != null else ""

		if not eid.is_empty():
			seen_edge_ids[eid] = wn

		if not wn.has_method("set_zone_color"):
			continue
		if edge_color_map.has(eid):
			wn.call("set_zone_color", edge_color_map[eid])
		else:
			## No zone color resolved — revert to the WireSegment default.
			wn.call("set_zone_color", Color.TRANSPARENT)

	## ── 4. Fallback: color PM edges whose node isn't in the group yet ────────
	for edge: Dictionary in (pm.get_wire_edges() as Array):
		var eid2: String  = edge.get("id", "")
		var raw2: Variant = edge.get("node", null)
		if raw2 == null or not is_instance_valid(raw2):
			continue
		var enode: Node = raw2 as Node
		if not enode.has_method("set_zone_color"):
			continue
		if seen_edge_ids.has(eid2):
			continue   ## already handled in the group pass
		if edge_color_map.has(eid2):
			enode.call("set_zone_color", edge_color_map[eid2])
		else:
			enode.call("set_zone_color", Color.TRANSPARENT)


## Called by WireDrawMode via signal after a wire is successfully placed.
## Snapshots the zone color registry at this instant (before _recolor_wire_zones
## has had a chance to call get_wire_zones_with_colors and mutate the registry).
## This snapshot is used by the undo handler to restore colors to their exact
## pre-placement state when the wire is removed.
# ─── Public: auto-fill spawn ─────────────────────────────────────────────────
## `is_true_pregen` distinguishes the ORIGINAL 4 pregen boundary walls/pillars
## (spawned once by BunkerPregen.generate()) from autofill walls/pillars spawned
## by the dig solver (WireGraphBuilder.gd) along expanded-area boundaries.
## Both still get `_is_pregen` (level structure — not deletable, doesn't block
## placement, protected from wire deletion — see all `has_meta("_is_pregen")`
## call sites in this file) so NONE of that existing behavior changes.
## `_is_true_pregen` is ONLY read by WallSnapHelpers._is_pregen_interior_face()
## to gate the strict original-rectangle math to the walls it's actually valid
## for — see WallSnapHelpers.gd header comment for the full bug this fixes.
func spawn_structure(tile_id: int, pos: Vector3, angle_deg: float, is_true_pregen: bool = false) -> Node3D:
	if gridmap == null:
		return null
	var body: Node3D = _spawn_placed_object(tile_id, pos, angle_deg)
	## Tag the node so Deconstruct-mode hover can skip it without a _placed_objects lookup.
	if body != null:
		body.set_meta("_is_pregen", true)
		if is_true_pregen:
			body.set_meta("_is_true_pregen", true)
	_placed_objects.append({
		"node":          body,
		"tile_id":       tile_id,
		"price":         0,
		"world_pos":     pos,
		"angle_deg":     angle_deg,
		"player_placed": false,   ## Level-spawned — locked from player modification
	})
	return body

func remove_placed_object(node: Node3D) -> void:
	for i: int in _placed_objects.size():
		if _placed_objects[i]["node"] == node:
			_placed_objects.remove_at(i)
			return

## When a wall or pillar is deconstructed, remove any lights that were mounted
## on it. A light is considered supported by a structure if its XZ position is
## within LIGHT_WALL_SNAP_RANGE of the structure's position.
## Player-placed lights are refunded; pregen lights are destroyed silently.
func _remove_unsupported_lights_near(wall_pos: Vector3) -> void:
	var to_remove: Array[int] = []
	for i: int in _placed_objects.size():
		var entry: Dictionary = _placed_objects[i]
		if entry.get("tile_id", -1) != TILE_LIGHT:
			continue
		var p: Vector3 = entry["world_pos"]
		var dx: float = absf(p.x - wall_pos.x)
		var dz: float = absf(p.z - wall_pos.z)
		if dx <= LIGHT_WALL_SNAP_RANGE and dz <= LIGHT_WALL_SNAP_RANGE:
			to_remove.append(i)

	for i: int in range(to_remove.size() - 1, -1, -1):
		var idx: int          = to_remove[i]
		var entry: Dictionary = _placed_objects[idx]
		var node: Node3D      = entry["node"]
		var refund: int       = entry.get("price", 0) if entry.get("player_placed", true) else 0

		_placed_objects.remove_at(idx)
		if is_instance_valid(node):
			## Unregister from power grid before freeing (_remove_unsupported_lights_near)
			var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
			if pm != null:
				pm.unregister_consumer(str(node.get_instance_id()))
			node.queue_free()
		if refund > 0 and world_node != null:
			world_node.add_cash(refund)
			_spawn_float_label_at_pos(entry["world_pos"], refund, true)

## Scans all placed lights whose XZ position falls within the given world-space
## rectangle [x_min, x_max] × [z_min, z_max] and removes them.
## Player-placed lights are refunded; pregen lights (player_placed=false) are not.
## Called by MainWorld._on_chunk_deconstructed() before the perimeter solve.
## Removes all player-placed circuit breakers whose world position falls within
## [x_min..x_max, z_min..z_max].  Called by MainWorld._on_chunk_deconstructed
## before _rebuild_auto_wires so that PM's breaker registry is clean when the
## fresh wire graph is built.
##
## BreakerBox._exit_tree() self-unregisters via pm.unregister_breaker(), which
## also re-stitches the wire edge on both sides of the removed breaker — the
## two previously-split zones merge naturally, same as when the player manually
## removes a breaker with the deconstruct tool.  Zone color for the merged zone
## is assigned naturally by get_wire_zones_with_colors() during the subsequent
## _recolor_wire_zones() call in _rebuild_auto_wires.
## Returns true if at least one breaker was removed (zone topology changed).
func remove_breakers_in_bounds(x_min: float, x_max: float, z_min: float, z_max: float) -> bool:
	var to_remove: Array[int] = []
	for i: int in _placed_objects.size():
		var entry: Dictionary = _placed_objects[i]
		var rb_tid: int = entry.get("tile_id", -1)
		if rb_tid != TILE_BREAKER and rb_tid != TILE_BREAKER_SMART:
			continue
		var p: Vector3 = entry["world_pos"]
		if p.x >= x_min and p.x <= x_max and p.z >= z_min and p.z <= z_max:
			to_remove.append(i)

	if to_remove.is_empty():
		return false

	## Iterate in reverse so removals don't shift earlier indices.
	var any_removed: bool = false
	for i: int in range(to_remove.size() - 1, -1, -1):
		var idx: int          = to_remove[i]
		var entry: Dictionary = _placed_objects[idx]
		var node: Node3D      = entry["node"]
		var refund: int       = entry.get("price", 0) if entry.get("player_placed", true) else 0

		_placed_objects.remove_at(idx)
		if is_instance_valid(node):
			## BreakerBox._exit_tree() fires automatically on queue_free(),
			## calling pm.unregister_breaker() and re-stitching the wire edge.
			node.queue_free()
			any_removed = true

		if refund > 0 and world_node != null:
			world_node.add_cash(refund)
			_spawn_float_label_at_pos(entry["world_pos"], refund, true)

	## _rebuild_auto_wires (called by MainWorld immediately after) handles
	## recolor. No extra recolor needed here.
	return any_removed

func remove_lights_in_bounds(x_min: float, x_max: float, z_min: float, z_max: float) -> void:
	var to_remove: Array[int] = []
	for i: int in _placed_objects.size():
		var entry: Dictionary = _placed_objects[i]
		if entry.get("tile_id", -1) != TILE_LIGHT:
			continue
		var p: Vector3 = entry["world_pos"]
		if p.x >= x_min and p.x <= x_max and p.z >= z_min and p.z <= z_max:
			to_remove.append(i)

	## Iterate in reverse so removals don't shift earlier indices
	for i: int in range(to_remove.size() - 1, -1, -1):
		var idx: int      = to_remove[i]
		var entry: Dictionary = _placed_objects[idx]
		var node: Node3D  = entry["node"]
		var refund: int   = entry.get("price", 0) if entry.get("player_placed", true) else 0

		_placed_objects.remove_at(idx)
		if is_instance_valid(node):
			## Unregister from power grid before freeing (remove_lights_in_bounds)
			var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
			if pm != null:
				pm.unregister_consumer(str(node.get_instance_id()))
			node.queue_free()

		if refund > 0 and world_node != null:
			world_node.add_cash(refund)
			_spawn_float_label_at_pos(entry["world_pos"], refund, true)

# ─── Hover glow (Duplicate / Move phase-0 tools) ────────────────────────────
func _update_hover_glow() -> void:
	var body: Node3D = _get_hovered_placed_body()

	# Never glow level-structure objects (player_placed: false)
	if body != null:
		var is_player_placed: bool = true
		for entry: Dictionary in _placed_objects:
			if entry["node"] == body:
				is_player_placed = entry.get("player_placed", true)
				break
		if not is_player_placed:
			body = null   ## Treat as if nothing is hovered

	if body == _hovered_placed_body:
		return

	_clear_hover_glow()
	_hovered_placed_body = body
	if body == null:
		return

	_apply_material_recursive(body, _mat_hover)

func _clear_hover_glow() -> void:
	if _hovered_placed_body == null:
		return
	if not is_instance_valid(_hovered_placed_body):
		_hovered_placed_body = null
		_hover_restore_mats.clear()
		return
	_apply_material_recursive(_hovered_placed_body, null)
	_hover_restore_mats.clear()
	_hovered_placed_body = null

## Recursively applies mat to every MeshInstance3D under root.
## If mat is null we are clearing hover — restore the per-surface "restore" materials
## that were cached in _hover_restore_mats before the glow was applied.
func _apply_material_recursive(root: Node, mat: StandardMaterial3D) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.mesh != null:
				for s: int in mi.mesh.get_surface_count():
					if mat == null:
						# Restore: pull from cache; fall back to null if not cached
						var key: String = "%s_%d" % [mi.get_instance_id(), s]
						var restore: StandardMaterial3D = _hover_restore_mats.get(key, null) as StandardMaterial3D
						mi.set_surface_override_material(s, restore)
					else:
						# Applying glow: cache current override first
						var key: String = "%s_%d" % [mi.get_instance_id(), s]
						_hover_restore_mats[key] = mi.get_surface_override_material(s)
						mi.set_surface_override_material(s, mat)
		# Recurse — handles GLB sub-scenes and nested nodes
		if child.get_child_count() > 0:
			_apply_material_recursive(child, mat)

# ─── Raycasting ───────────────────────────────────────────────────────────────
func _raycast_to_grid() -> Dictionary:
	if camera == null:
		return {}
	var vp: Viewport       = get_viewport()
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var from: Vector3      = camera.project_ray_origin(mouse_pos)
	var dir: Vector3       = camera.project_ray_normal(mouse_pos)
	var to: Vector3        = from + dir * ray_length

	var space: PhysicsDirectSpaceState3D   = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.hit_back_faces = false
	var player: Node3D = get_parent()
	if player.has_method("get_rid"):
		query.exclude = [player.get_rid()]
	return space.intersect_ray(query)

## Raycast and return the first placed StaticBody3D hit (or null).
## Checks collision layer 4 (build-placed objects).
## Also handles the create_trimesh_collision() child body case.
func _get_hovered_placed_body() -> Node3D:
	if camera == null:
		return null
	var vp: Viewport       = get_viewport()
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var from: Vector3      = camera.project_ray_origin(mouse_pos)
	var dir: Vector3       = camera.project_ray_normal(mouse_pos)
	var to: Vector3        = from + dir * ray_length

	var space: PhysicsDirectSpaceState3D   = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4   ## Layer 3 bit = value 4 — placed objects only
	## hit_back_faces NOT set false — trimesh walls have outward-facing normals;
	## their interior (room-facing) surface is a "back face" and would be missed.
	var player: Node3D = get_parent()
	if player.has_method("get_rid"):
		query.exclude = [player.get_rid()]

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider = result.get("collider")

	## Walk up the node tree from the hit collider until we find a node that's
	## registered in _placed_objects. This handles:
	##   • Direct hit on placed StaticBody3D (walls, pillars, shelves)
	##   • Hit on create_trimesh_collision() child: PlacedBody→MeshInstance3D→TrimeshSB3D
	##   • Hit on GLB sub-mesh children of Shelving
	if collider != null:
		var node = collider
		while node != null:
			for entry: Dictionary in _placed_objects:
				if entry["node"] == node:
					return entry["node"] as Node3D
			node = node.get_parent()

	return null

# ─── Grid snapping ────────────────────────────────────────────────────────────
## Returns true if there is a wall or pillar surface within 0.6 units in the
## direction the light faces (its "back" direction, opposite to facing).
## angle_deg is the Y rotation of the ghost — "facing" is +Z rotated by angle_deg,
## so the wall is in the -Z direction (behind the fixture).
func _has_wall_surface_behind(pos: Vector3, angle_deg: float) -> bool:
	var angle_rad: float = deg_to_rad(angle_deg)
	# Facing direction: rotated +Z
	var facing: Vector3 = Vector3(sin(angle_rad), 0.0, cos(angle_rad))
	# Wall is BEHIND the fixture → cast in the facing direction (light face points outward,
	# wall is on the back side which is the same as the facing direction for a wall-mount).
	# 0.35 = roughly one wall depth — the auto-snap pushes lights flush to the wall,
	# so this is just a sanity check that something is actually there.
	var check_dist: float = 0.35
	var light_y: float    = pos.y + 1.5   ## Sample at lamp height

	var from_pt: Vector3 = Vector3(pos.x, light_y, pos.z)
	var to_pt:   Vector3 = from_pt + facing * check_dist

	var space: PhysicsDirectSpaceState3D   = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pt, to_pt)
	query.collision_mask = 5   ## Hits both player-layer (1) and placed-objects (4)
	## hit_back_faces NOT set to false — player-placed trimesh walls have outward
	## normals so their room-facing surface is a "back face". Manual check below.
	var player: Node3D = get_parent()
	if player.has_method("get_rid"):
		query.exclude = [player.get_rid()]

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return false

	# Confirm the hit normal opposes the ray direction — i.e. it's an interior-facing surface.
	# This rejects side/back faces of walls even if the trimesh collision exposes them.
	var hit_normal: Vector3 = result.get("normal", Vector3.ZERO)
	if hit_normal.dot(facing) >= 0.0:
		return false  ## Normal points same way as ray = back/side face = reject

	# Confirm the hit body is a wall or pillar (tile_id 1 or 2)
	var collider = result.get("collider")
	if collider == null:
		return false
	var node = collider
	while node != null:
		if node.has_meta("tile_id"):
			var tid: int = node.get_meta("tile_id")
			return tid == TILE_WALL or tid == TILE_PILLAR
		node = node.get_parent()

	# Also accept GridMap geometry (bunker pregen walls)
	return true

func _snap_to_grid(world_pos: Vector3) -> Vector3:
	return Vector3(
		roundf(world_pos.x / grid_size) * grid_size,
		world_pos.y,
		roundf(world_pos.z / grid_size) * grid_size
	)

# ─── Float label helper ───────────────────────────────────────────────────────
func _spawn_float_label_at_pos(world_pos: Vector3, amount: int, positive: bool) -> void:
	if camera == null or amount == 0:
		return
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	var main_world: Node3D  = get_parent().get_parent() as Node3D
	if main_world == null:
		return
	var main_hud: Node = main_world.get_node_or_null("HUD")
	if main_hud == null:
		return
	if main_hud.has_method("spawn_float_label"):
		main_hud.spawn_float_label(screen_pos, amount, positive)

# ─── Soft warning helper ──────────────────────────────────────────────────────
func _show_hud_warning(text: String) -> void:
	var main_world: Node3D = get_parent().get_parent() as Node3D
	if main_world == null:
		return
	var main_hud: Node = main_world.get_node_or_null("HUD")
	if main_hud != null and main_hud.has_method("show_soft_warning"):
		main_hud.show_soft_warning(text)

# ─── Overlap detection ────────────────────────────────────────────────────────
## Tile-aware wrapper: lights use a tighter overlap radius so they can sit
## close together along a wall without blocking each other.
func _is_position_occupied_for_tile(pos: Vector3, tile_id: int) -> bool:
	if tile_id == TILE_LIGHT:
		# Lights only check registry overlap at a tighter radius; no physics shape
		# check needed since they have no collision.
		for entry: Dictionary in _placed_objects:
			if entry.get("tile_id", -1) != TILE_LIGHT:
				continue
			var p: Vector3 = entry["world_pos"]
			if abs(p.x - pos.x) < LIGHT_OVERLAP_RADIUS and abs(p.z - pos.z) < LIGHT_OVERLAP_RADIUS:
				return true
		return false
	if tile_id == TILE_SHELVING:
		# Shelves are StaticBody3D on layer 1 — the physics shape query would
		# hit the shelf's own collider, giving a false "occupied" positive.
		# Registry check + GridMap check (done before this call) are sufficient.
		var threshold: float = grid_size * 0.9
		for entry: Dictionary in _placed_objects:
			if entry.get("tile_id", -1) != TILE_SHELVING:
				continue
			var p: Vector3 = entry["world_pos"]
			if abs(p.x - pos.x) < threshold and abs(p.z - pos.z) < threshold:
				return true
		return false
	if tile_id == TILE_BED:
		# Beds are StaticBody3D — same false-positive issue as shelving.
		# Skip physics shape query; registry + GridMap checks are sufficient.
		var threshold: float = grid_size * 0.9
		for entry: Dictionary in _placed_objects:
			if entry.get("tile_id", -1) != TILE_BED:
				continue
			var p: Vector3 = entry["world_pos"]
			if abs(p.x - pos.x) < threshold and abs(p.z - pos.z) < threshold:
				return true
		return false
	if tile_id == TILE_GEN_S or tile_id == TILE_GEN_M or tile_id == TILE_GEN_L:
		# Generators sit on the floor (Y=0). The physics shape query hits the
		# floor collider and the generator's own StaticBody3D, causing false
		# "space occupied" positives. Use registry-only overlap check instead.
		var threshold: float = grid_size * 0.9
		for entry: Dictionary in _placed_objects:
			var et: int = entry.get("tile_id", -1)
			if et != TILE_GEN_S and et != TILE_GEN_M and et != TILE_GEN_L:
				continue
			var p: Vector3 = entry["world_pos"]
			if abs(p.x - pos.x) < threshold and abs(p.z - pos.z) < threshold:
				return true
		# Still block placement inside GridMap walls/pillars
		if gridmap != null:
			var cell_x: int = roundi(pos.x)
			var cell_z: int = roundi(pos.z)
			for cy: int in [0, 1]:
				var cell_item: int = gridmap.get_cell_item(Vector3i(cell_x, cy, cell_z))
				if cell_item == TILE_WALL or cell_item == TILE_PILLAR:
					return true
		return false
	return _is_position_occupied(pos, tile_id)


## Forwarded to WallSnapHelpers.gd (Stage 10 slice) — called from
## GhostPreview.gd's _update_ghost() via _owner._snap_light_to_wall()/
## _owner._snap_breaker_to_wall(). _is_pregen_interior_face is internal-only
## to WallSnapHelpers, no wrapper needed. See WallSnapHelpers.gd for the
## full cluster.
func _snap_light_to_wall(base_pos: Vector3) -> Dictionary:
	return _wall_snap._snap_light_to_wall(base_pos)


func _snap_breaker_to_wall(base_pos: Vector3) -> Dictionary:
	return _wall_snap._snap_breaker_to_wall(base_pos)


## Forwarded to WallSnapHelpers._snap_to_nearest_wall() (generic version added
## July 2026 for the water-system groundwork pass) — called from
## GhostPreview.gd for TILE_WATER_HOOKUP initial placement and from
## MoveDuplicateTool.gd for TILE_WATER_HOOKUP moves. See WallSnapHelpers.gd.
func _snap_to_nearest_wall(base_pos: Vector3, cast_y_offset: float,
		pullback_dist: float, snap_range: float) -> Dictionary:
	return _wall_snap._snap_to_nearest_wall(base_pos, cast_y_offset, pullback_dist, snap_range)




## Returns per-tile physics half-extents (XZ) for the overlap check.
## Tile footprints match their actual visual size so large objects (beds,
## generators) don't clip walls through an undersized collision box.
static func _tile_half_extents(tile_id: int) -> Vector2:
	match tile_id:
		TILE_WALL:     return Vector2(0.44, 0.44)  ## 1×1 cell — tightened from 0.48 to allow flush placement against pregen walls
		TILE_PILLAR:   return Vector2(0.24, 0.24)  ## 0.5×0.5
		TILE_BED:      return Vector2(0.95, 0.48)  ## 2×1
		TILE_SHELVING: return Vector2(0.48, 0.18)  ## 1×0.4
		TILE_GEN_S:    return Vector2(0.41, 0.41)  ## 0.85×0.85
		TILE_GEN_M:    return Vector2(0.41, 0.91)  ## 0.85×1.85
		TILE_GEN_L:    return Vector2(0.91, 0.91)  ## 1.85×1.85
		TILE_TERMINAL: return Vector2(0.34, 0.04)  ## 0.7×0.08 thin panel
		TILE_HEAVY:    return Vector2(0.29, 0.29)  ## 0.6×0.6 box
		_:             return Vector2(0.40, 0.40)  ## generic fallback


func _is_position_occupied(pos: Vector3, tile_id: int = -1) -> bool:
	## Only player-placed objects block new placement.
	## Pregen/autofill structures (player_placed=false) are skipped here —
	## they're level geometry and the physics query below (which walks parent
	## ancestry for _is_pregen) is the correct gate. Blocking them via the
	## registry produced false positives when snapping flush to a pregen wall.
	const PLAYER_THRESHOLD_FACTOR:  float = 1.5   ## 0.375 m

	for entry: Dictionary in _placed_objects:
		## Skip pregen/autofill — only player-placed objects count here.
		if not entry.get("player_placed", true):
			continue
		var t: float = grid_size * PLAYER_THRESHOLD_FACTOR
		var p: Vector3 = entry["world_pos"]
		if abs(p.x - pos.x) < t and abs(p.z - pos.z) < t:
			return true

	## GridMap cell check: only block placement when hitting a WALL or PILLAR tile.
	## GridMap occupancy check: only block for WALL/PILLAR tiles at wall height.
	## IMPORTANT: pregen walls live exactly ON the half-unit boundary (e.g. x=-12.5).
	## roundi(-12.5) → -12 or -13 (rounds to even) which may or may not land on the
	## wall cell.  More critically, a player placing against a pregen wall will have
	## their snap position within 0.5 of the wall face — we must NOT block that.
	## Rule: only reject if the rounded cell centre is within 0.3 m of pos XZ,
	## meaning pos is genuinely inside the wall cell rather than just adjacent.
	if gridmap != null:
		var cell_x: int   = roundi(pos.x)
		var cell_z: int   = roundi(pos.z)
		var cell_cx: float = float(cell_x)   ## GridMap cell centre X
		var cell_cz: float = float(cell_z)   ## GridMap cell centre Z
		## Only reject if we're well inside the cell (not just touching its face).
		## Threshold 0.55 m = original 0.30 + 0.25 stricter margin so player walls
		## cannot be placed as flush/overlapping with pregen bunker walls.
		if absf(pos.x - cell_cx) < 0.55 and absf(pos.z - cell_cz) < 0.55:
			for cy: int in [0, 1]:
				var cell_item: int = gridmap.get_cell_item(Vector3i(cell_x, cy, cell_z))
				if cell_item == TILE_WALL or cell_item == TILE_PILLAR:
					return true

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state != null:
		## Use tile-specific footprint so large objects don't clip walls/each-other.
		var he: Vector2 = _tile_half_extents(tile_id) if tile_id >= 0 \
				else Vector2(0.40, 0.40)
		var box := BoxShape3D.new()
		## Height 0.9 m — tall enough to catch placed objects but starting at Y+0.15
		## above the floor surface so we don't hit the floor collider itself.
		box.size = Vector3(he.x * 2.0, 0.90, he.y * 2.0)

		## Raise the query centre above floor level so floor colliders are excluded.
		var query_pos: Vector3 = Vector3(pos.x, pos.y + 0.20, pos.z)

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape          = box
		query.transform      = Transform3D(Basis.IDENTITY, query_pos)
		query.collision_mask = 1
		var player: Node3D = get_parent()
		if player is CollisionObject3D:
			query.exclude = [player.get_rid()]

		var hits: Array[Dictionary] = space_state.intersect_shape(query, 8)
		for hit: Dictionary in hits:
			## Skip pregen/autofill StaticBody3D nodes — they are level structure
			## and the player is allowed to snap right up against them.
			## IMPORTANT: create_trimesh_collision() spawns a CHILD StaticBody3D
			## that doesn't inherit the parent's "_is_pregen" meta. Walk up the
			## ancestor chain to check any parent for the meta flag.
			var body: Object = hit.get("collider", null)
			## If collider is null (shouldn't happen but guard anyway), skip it.
			if body == null:
				continue
			var node: Node = body as Node
			var is_pregen: bool = false
			while node != null:
				if node.has_meta("_is_pregen"):
					is_pregen = true
					break
				node = node.get_parent()
			## Only block placement when the hit collider is a player-placed object.
			if not is_pregen:
				return true

	return false

# ─── Ghost materials ──────────────────────────────────────────────────────────
# ─── Forwarded to BuildMaterials.gd (Stage 10 slice) ──────────────────────────
## Only these 3 are still called from elsewhere in this file
## (_build_ghost_materials/_build_world_materials from _ready(),
## _apply_world_material from bed-wiring + _spawn_placed_object).
## _apply_wall_material_recursive is only called from within BuildMaterials
## itself, so it needs no wrapper. See BuildMaterials.gd for the full cluster.
func _build_ghost_materials() -> void:
	_materials._build_ghost_materials()


func _build_world_materials() -> void:
	_materials._build_world_materials()


func _apply_world_material(body: Node3D, tile_id: int) -> void:
	_materials._apply_world_material(body, tile_id)




## Returns the world XZ position of the nearest PowerManager wire node within
## `radius` metres of `pos` (XZ only). Returns Vector3.INF if none found.
## _nearest_wire_node_xz removed — wire-node XZ override caused lights and
## breakers to be displaced off the wall face. Wire connections are established
## by BreakerBox._auto_connect_to_nearby_wires() at registration time instead.
