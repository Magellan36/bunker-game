extends StaticBody3D
class_name BuildStation
## BuildStation.gd
## Singleton object — spawns once at world-center at game start (see
## MainWorld._spawn_initial_build_station()), never purchasable, never
## deconstructable, movable only via the Move tool. The in-fiction entry
## point into Build Mode (F1 remains a dev/admin shortcut alongside it,
## unchanged).
##
## Uses the plain "interactable" contract (get_interact_prompt/on_interact)
## for ENTERING build mode — completely standard E-dispatch, same as any
## other interactable. EXITING build mode is a different mechanism entirely,
## owned by BuildModeController itself (see that file) — InteractionSystem's
## whole dispatch pipeline is disabled while build mode is active, so this
## script has no role in the exit interaction at all.

## Injected directly by MainWorld at spawn time (this object is never routed
## through BuildModeController.spawn_structure()'s generic injection block,
## since it's exclusively spawned by MainWorld's own dedicated function).
var _main_world: Node = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()

func get_interact_prompt() -> String:
	return "[E] Enter Build Mode"

func on_interact() -> void:
	if _main_world != null and _main_world.has_method("_toggle_build_mode"):
		_main_world._toggle_build_mode()

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, 1.1, 0.0)

# ─── Model — human-built tool cart (Sep 2026), replaces the old wooden_table.glb ──
func _build_mesh() -> void:
	const LEG_HEIGHT: float = 0.72
	const TABLETOP_THICKNESS: float = 0.05

	## The tool cart model is pre-scaled at export to exactly the BuildStation
	## footprint/height (1.90 × 0.77 × 0.90, base at y=0), so scale is Vector3.ONE.
	const MODEL_PATH: String = "res://assets/models/build_station.glb"
	const MODEL_SCALE: Vector3 = Vector3.ONE

	var packed: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = MODEL_SCALE
			BuildMaterials.recenter_glb_mesh(model)
			BuildMaterials.strip_model_collision(model)
			add_child(model)
	else:
		push_warning("BuildStation.gd: model missing at %s — falling back to no visual" % MODEL_PATH)

	## Invisible collision box, same dimensions/position the procedural
	## tabletop's create_trimesh_collision() used to produce.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.90, TABLETOP_THICKNESS, 0.90)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, LEG_HEIGHT + 0.025, 0.0)
	add_child(col_shape)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.90, 0.85, 0.90)
	return box