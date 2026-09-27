extends RigidBody3D
## PickupItem.gd
## Base script for any object the player can pick up and carry.
## Attach to: RigidBody3D root of any carriable object scene.
## All carriable items in the game should extend or instance this pattern.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var item_name: String = "Item"
@export var carry_offset: Vector3 = Vector3(0.0, 0.0, -1.2)  # Relative to player hold point
@export var tween_speed: float = 0.18                          # Seconds to snap into hands

# ─── Signals ──────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()

# ─── State ────────────────────────────────────────────────────────────────────
var is_held: bool = false
var _tween: Tween = null

func _ready() -> void:
	## Legacy pickup base: register once after authored scene children exist.
	GraphicsSettings.register_dynamic_shadow_root(self)

# ─── Pickup ───────────────────────────────────────────────────────────────────
func pickup(hold_point: Node3D) -> void:
	is_held = true
	freeze = true                    # Disable physics while carried
	collision_layer = 0              # Stop colliding with world while held
	collision_mask = 0

	# Reparent to the player's hold point so it moves with them
	var old_transform: Transform3D = global_transform
	get_parent().remove_child(self)
	hold_point.add_child(self)
	global_transform = old_transform

	# Tween smoothly into the hold position — the "jump to hands" feel
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)   # TRANS_BACK gives a slight overshoot = satisfying snap
	_tween.tween_property(self, "position", Vector3.ZERO, tween_speed)
	_tween.parallel().tween_property(self, "rotation", Vector3.ZERO, tween_speed)

	## Dynamic shadow gate (Sep 2026) — a held item must never cast a shadow
	## unless dynamic shadows (Layer 2) is ON. Gate immediately at pickup so a
	## freshly spawned item doesn't flash a shadow; reparenting under the
	## holder hides it from the world-walk gate, so this is the only gating it
	## gets while held. Reuses BuildModeController's gate for a consistent
	## authored cast_shadow capture.
	var _mw: Node = get_tree().get_first_node_in_group("main_world")
	var _bc: Node = _mw.get("_build_controller") if _mw != null else null
	if _bc != null and _bc.has_method("_apply_dynamic_shadow_to_node"):
		_bc.call("_apply_dynamic_shadow_to_node", self)

	picked_up.emit()

# ─── Drop ─────────────────────────────────────────────────────────────────────
func drop(world_parent: Node3D, drop_position: Vector3) -> void:
	is_held = false

	# Reparent back to world
	var _old: Transform3D = global_transform
	get_parent().remove_child(self)
	world_parent.add_child(self)
	global_transform.origin = drop_position

	# Re-enable physics
	freeze = false
	collision_layer = 1
	collision_mask = 1

	# Small downward impulse so it settles naturally
	apply_central_impulse(Vector3(0.0, -1.5, 0.0))

	dropped.emit()

# ─── Place (precise) ──────────────────────────────────────────────────────────
func place(world_parent: Node3D, place_position: Vector3, place_rotation: Vector3 = Vector3.ZERO) -> void:
	is_held = false

	get_parent().remove_child(self)
	world_parent.add_child(self)
	global_transform.origin = place_position
	rotation = place_rotation

	freeze = true                    # Placed items stay static by default
	collision_layer = 1
	collision_mask = 1

	dropped.emit()
