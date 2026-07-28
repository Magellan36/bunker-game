extends Node3D
class_name WaterPipeElbow
## WaterPipeElbow.gd
## Joint-fitting visual for a "corner"-role WaterGraph node. Covers every
## real junction shape a strictly-axis-aligned pipe network can produce:
## a 2-way 90° bend (incl. a horizontal-run-to-vertical-drop transition),
## a 3-way T-split, a 4-way "+" crossing, and (edge case, see
## docs/systems/water/README.md) a degree-2 COLLINEAR remnant left behind
## after deleting one leg of a former T-split/crossing — shown as a plain
## straight splice, not a bent fitting.
##
## Does NOT compute its own leg directions — WaterManager.
## refresh_all_pipe_joint_visuals() (the single owner of graph-mutation
## timing) resolves them and calls rebuild_visual() directly, matching this
## project's "managers own graph state, node scripts own their own visuals"
## convention (see WaterPipeSegment.gd's set_quality_color()/set_purified()
## for the same split).
##
## Zero manual offset math — every flange/disc is already baked into these
## fitting scenes ~0.22m from their own center; we only ever pick ONE whole
## scene and rotate it so its local stub arms line up with the real legs.

const SCENE_ELBOW:    String = "res://scenes/world/water/WaterPipeElbowCouplerModel.tscn"
const SCENE_TSPLIT:   String = "res://scenes/world/water/WaterPipeTSplitCouplerModel.tscn"
const SCENE_CROSS:    String = "res://scenes/world/water/WaterPipePlusCrossCouplerModel.tscn"
const SCENE_STRAIGHT: String = "res://scenes/world/water/WaterPipeCouplerModel.tscn"

## Graph node key this fitting is registered under. Set directly by
## whichever call site spawns/finds this instance (unchanged contract —
## see WaterManager.refresh_all_pipe_joint_visuals(), WaterPurifier.
## revert_to_corner(), WaterManager.restore_pipe_network()).
var node_key: String = ""

## Currently-instanced fitting scene root, tracked so rebuild_visual() can
## always tear down and rebuild fresh rather than attempting an in-place
## partial update (simplest correct approach — see plan §3).
var _fitting_instance: Node3D = null

func _ready() -> void:
	visible = true
	add_to_group("water_pipe_elbow")
	## Deliberately builds NO visual here. A freshly-created instance sits
	## invisible (zero children) until the very next
	## WaterManager.refresh_all_pipe_joint_visuals() sweep calls
	## rebuild_visual() with this node's real, fully-registered leg
	## directions — this is intentional, not a bug: at the moment most
	## call sites create a WaterPipeElbow, this node's edges have not been
	## registered into the graph yet (see WaterPipeDrawMode.gd's placement
	## loop — nodes are created before edges in the same operation).

## Called by WaterManager.refresh_all_pipe_joint_visuals() every time ANY
## pipe-graph mutation finishes (placement, T-split, crossing, edge delete/
## refund, undo, purifier revert/replace/insert, save/load) — see
## docs/systems/water/README.md for the exact trigger-point list. Always
## fully tears down and rebuilds, even if the resulting scene type is
## unchanged, for simplicity/correctness (this never fires per-frame, so
## the rebuild cost is irrelevant).
func rebuild_visual(leg_dirs: Array[Vector3]) -> void:
	if _fitting_instance != null and is_instance_valid(_fitting_instance):
		_fitting_instance.queue_free()
	_fitting_instance = null

	var picked: Dictionary = pick_fitting(leg_dirs)
	if picked.is_empty():
		return   ## degree 0/1, or a malformed/unsupported set — no visual, see plan §1.5/§1.6

	var scene: PackedScene = load(picked["scene_path"])
	if scene == null:
		push_warning("WaterPipeElbow.rebuild_visual: failed to load %s" % picked["scene_path"])
		return

	var instance: Node3D = scene.instantiate()
	add_child(instance)
	## Position stays at this WRAPPER node's own global_position (set once,
	## at spawn time, by whichever call site created this WaterPipeElbow —
	## never touched here). Rotation lives on the CHILD instance's LOCAL
	## transform — same split WaterPipeSegment.gd already uses for its own
	## _mesh_instance child (wrapper = position only, child = rotation).
	instance.transform = Transform3D(picked["basis"], Vector3.ZERO)
	_fitting_instance = instance

# ─── Pure math helpers (static, no state) — see plan §3 for full reasoning ──

static func snap_to_axis(dir: Vector3) -> Vector3:
	var ax: float = absf(dir.x)
	var ay: float = absf(dir.y)
	var az: float = absf(dir.z)
	if ax >= ay and ax >= az:
		return Vector3(signf(dir.x), 0.0, 0.0)
	elif ay >= ax and ay >= az:
		return Vector3(0.0, signf(dir.y), 0.0)
	else:
		return Vector3(0.0, 0.0, signf(dir.z))

static func basis_from_two(d1: Vector3, d2: Vector3) -> Basis:
	return Basis(d1, d2, d1.cross(d2).normalized())

static func _axis_index_of(dir: Vector3) -> int:
	if absf(dir.x) > 0.5:
		return 0
	elif absf(dir.y) > 0.5:
		return 1
	else:
		return 2

static func pick_fitting(leg_dirs: Array[Vector3]) -> Dictionary:
	var n: int = leg_dirs.size()
	if n < 2:
		return {}

	if n == 2:
		var d1: Vector3 = leg_dirs[0]
		var d2: Vector3 = leg_dirs[1]
		if d1.is_equal_approx(-d2):
			## Collinear remnant — see §5.1. Build a basis whose local +Y
			## (the straight-coupler model's own through-axis) points along
			## the shared line; pick any perpendicular helper for local X.
			var helper: Vector3 = Vector3.UP if absf(d1.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			var x_axis: Vector3 = helper.cross(d1).normalized()
			return { "scene_path": SCENE_STRAIGHT, "basis": Basis(x_axis, d1, x_axis.cross(d1).normalized()) }
		return { "scene_path": SCENE_ELBOW, "basis": basis_from_two(d1, d2) }

	if n == 3 or n == 4:
		## Group by axis, find every axis that has BOTH signs present
		## (a straight-through pair) vs. an axis with only one sign present
		## (a lone branch — only possible/expected when n == 3).
		var by_axis: Dictionary = {}   ## axis_index -> Array[Vector3]
		for d: Vector3 in leg_dirs:
			var ax: int = _axis_index_of(d)
			if not by_axis.has(ax):
				by_axis[ax] = []
			by_axis[ax].append(d)

		var pair_dirs: Array = []      ## one representative Vector3ies per straight-through pair
		var lone_dir: Vector3 = Vector3.ZERO
		var has_lone: bool = false
		for ax: int in by_axis:
			var dirs_on_axis: Array = by_axis[ax]
			if dirs_on_axis.size() == 2 and dirs_on_axis[0].is_equal_approx(-dirs_on_axis[1]):
				pair_dirs.append(dirs_on_axis[0])
			elif dirs_on_axis.size() == 1:
				lone_dir = dirs_on_axis[0]
				has_lone = true
			else:
				push_warning("WaterPipeElbow.pick_fitting: malformed leg set %s" % [leg_dirs])
				return {}

		if n == 3 and pair_dirs.size() == 1 and has_lone:
			return { "scene_path": SCENE_TSPLIT, "basis": basis_from_two(pair_dirs[0], lone_dir) }
		if n == 4 and pair_dirs.size() == 2 and not has_lone:
			return { "scene_path": SCENE_CROSS, "basis": basis_from_two(pair_dirs[0], pair_dirs[1]) }

		push_warning("WaterPipeElbow.pick_fitting: unexpected leg structure %s" % [leg_dirs])
		return {}

	push_warning("WaterPipeElbow.pick_fitting: unsupported degree %d" % n)
	return {}