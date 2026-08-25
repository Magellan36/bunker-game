extends StaticBody3D
class_name Chair
## Chair.gd
## Interactable chair. Player presses E nearby to sit; E again to stand.
## No animation yet — player capsule is repositioned and partially sunk into
## the seat while seated (see get_seat_transform()). Movement is frozen while
## seated, same convention Bed/SleepOverlay uses (player.set_physics_process).
## Chair's local -Z axis is its "front" (open, seat-facing) side — same
## forward-axis convention used by Bed/Generator ghost-arrow indicators.

const SEAT_Y: float       = 0.5625  ## was 0.45 → ×1.25
const SEAT_THICKNESS: float = 0.0625 ## was 0.05 → ×1.25
const BACK_HEIGHT: float  = 0.5625  ## was 0.45 → ×1.25
const LEG_HEIGHT: float   = SEAT_Y - SEAT_THICKNESS * 0.5   ## unchanged formula — auto-scales
const FOOTPRINT: float    = 0.625   ## was 0.50 → ×1.25

const COLOR_METAL: Color = Color(0.60, 0.62, 0.65, 1.0)   ## Matches Table.gd

const CHAIR_MODEL_PATH: String = "res://assets/models/wooden_chair.glb"
const CHAIR_MODEL_SCALE: Vector3 = Vector3(0.8946, 0.7102, 0.7667)

## Aug 2026 sit-animation pass — SUPERSEDED note, kept for history: this
## used to compensate for a baked root-offset bug in the sit clips (the
## imported sit pose dropped the pelvis to local y≈0.607 relative to the
## model origin, sinking the model into the seat unless masked here).
## That bug is now fixed at the SOURCE — the sit/stand_to_sit/sit_to_stand
## clips were re-exported from Blender with their Hips position data
## recentered so the seated pose lands exactly at the skeleton's own rest
## position (verified directly: sub-micron residual, consistent across
## all three clips), and the extraction pipeline strips the Hips position
## track entirely (same convention every other animation in this project
## already uses, since root motion is never consumed). See
## docs/systems/player-model/README.md "Sit animation root-offset fix"
## for the full writeup. Reset to 0 as the new baseline — the model
## should now land correctly with no compensation at all; re-tune
## in-editor only if the seat height/depth genuinely looks off once
## visually checked, not to mask a positioning bug.
const SEAT_RAISE: float   = 0.0
const SEAT_FORWARD: float = 0.0

## How far in front of the chair (along local +Z, away from the backrest)
## the player is placed on standing up. Bumped 0.65 → 0.85 (Aug 2026) so the
## sit_to_stand animation begins clearly in front of the chair, not on top of it.
const STAND_DIST: float   = 0.85

var _is_preview_only: bool = false   ## Same convention as Bed.gd/Shelving.gd — see those files' comment for the full writeup.

signal seat_requested()
signal stand_requested()

var _player_in_range: bool = false
var _player_seated: bool   = false

func _ready() -> void:
	_build_mesh()
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("chair")
	collision_layer = 5
	collision_mask  = 0

func _build_mesh() -> void:
	var packed: PackedScene = load(CHAIR_MODEL_PATH) if ResourceLoader.exists(CHAIR_MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = CHAIR_MODEL_SCALE
			_recenter_glb_mesh(model)
			_strip_model_collision(model)
			add_child(model)
	else:
		push_warning("Chair.gd: wooden_chair.glb missing at %s — falling back to no visual mesh" % CHAIR_MODEL_PATH)

	## Invisible collision box, same footprint/position seat_mi's
	## create_trimesh_collision() used to produce.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FOOTPRINT, SEAT_THICKNESS, FOOTPRINT)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, SEAT_Y, 0.0)
	add_child(col_shape)

## Recursively disables collision on every CollisionObject3D descendant of
## an instanced model. Duplicated per-file, matching the existing
## Table.gd/BuildStation.gd convention (no shared base to hang this on
## without a bigger refactor — out of scope here).
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer always wraps an imported scene in an extra
## generated root node representing the file's "Scene" — the file's real
## node (here, "chair01", carrying a stray (-4.1, 0, 0.8) scene-placement
## translation unrelated to the mesh's own shape) is nested one level
## below it. packed.instantiate() returns the wrapper, not that node, so
## zeroing the wrapper's position alone is a no-op. Recursively finds the
## actual MeshInstance3D descendant and zeros ITS local position — safe
## here since the mesh's own vertex data needs no recentering beyond
## removing this stray offset (see plan header re: the Z-axis asymmetry,
## which is real chair geometry, not something this should also correct).
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false

# ─── Interaction ────────────────────────────────────────────────────────────
func on_interact() -> void:
	if _npc_sitter != null and is_instance_valid(_npc_sitter):
		return   ## An NPC is sitting here — player can't stack on top
	if not _player_in_range:
		return
	if not _player_seated:
		seat_requested.emit()
	else:
		stand_requested.emit()

func get_prompt_text() -> String:
	if _player_seated:
		return "[E] Stand"
	return "[E] Sit"

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

func set_seated(seated: bool) -> void:
	_player_seated = seated


# ─── NPC occupancy (NPC Pass 2, Part 2 — additive; player flow untouched) ──
## The player path keeps using _player_seated via MainWorld._wire_chair.
## NPCs use this parallel claim so both kinds of sitter mutually exclude.
var _npc_sitter: Node = null

func is_seat_free() -> bool:
	if _player_seated:
		return false
	return _npc_sitter == null or not is_instance_valid(_npc_sitter)

func npc_try_sit(npc: Node) -> bool:
	if not is_seat_free():
		return false
	_npc_sitter = npc
	return true

func npc_stand(npc: Node) -> void:
	if _npc_sitter == npc:
		_npc_sitter = null

# ─── Positioning API (consumed by MainWorld — see Part 3) ──────────────────
## World transform the player should be moved to while seated. Anchored at the
## seat surface plus SEAT_RAISE (so the imported sit pose's pelvis lands on the
## seat instead of sinking into it) and nudged SEAT_FORWARD toward the chair's
## open front. See the constants' doc comment for the tuning rationale.
func get_seat_transform() -> Transform3D:
	var local_pos: Vector3 = Vector3(0.0, SEAT_Y + SEAT_RAISE, -SEAT_FORWARD)
	var world_pos: Vector3 = global_transform * local_pos
	var t: Transform3D = Transform3D(global_transform.basis, world_pos)
	return t

## World position the player should be moved to on standing — in front of the
## chair (local +Z, the open/non-backrest side), at floor height.
func get_stand_position() -> Vector3:
	var local_pos: Vector3 = Vector3(0.0, 0.0, STAND_DIST)
	return global_transform * local_pos

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(FOOTPRINT, SEAT_Y + BACK_HEIGHT, FOOTPRINT)
	return box