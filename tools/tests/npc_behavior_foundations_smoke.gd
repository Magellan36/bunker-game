extends SceneTree
## Cheap source/scene contracts for the NPC polish foundations. The full
## tools/godot_check.sh run provides runtime import and world-boot coverage.

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_text: String = _read("res://scenes/npc/NPC.tscn")
	_check(scene_text.contains("[sub_resource type=\"CapsuleShape3D\" id=\"CapsuleShape3D_npc1\"]\nradius = 0.4\nheight = 1.8"),
		"physical capsule dimensions remain explicit")

	var brain_text: String = _read("res://scripts/npc/NPCBrain.gd")
	_check(brain_text.contains("CookingActivity.new(),"),
		"autonomous cooking remains registered")
	_check(brain_text.contains("var margin: float = _current.switch_margin()"),
		"brain uses incumbent-specific switching hysteresis")
	_check(brain_text.contains("_deferred_intent")
			and brain_text.contains("RESUME_INTENT_LIFETIME_HOURS"),
		"brain retains at most one bounded safe resume intention")
	_check(brain_text.contains("NPCMetrics.gd")
			and brain_text.contains("utility_rejected_switch_margin"),
		"decision instrumentation remains attached to the brain boundary")
	_check(brain_text.contains("func begin_player_interaction")
			and brain_text.contains("func end_player_interaction")
			and brain_text.contains("Talking to player")
			and not brain_text.contains("_current.exit(_npc)\n\t_player_interaction_active = true"),
		"player conversation pauses the live activity rather than replacing it")
	_check(brain_text.contains("PLAYER_INTERACTION_RESUME_GRACE")
			and brain_text.contains("_has_critical_need"),
		"player conversation resumes with anti-thrash grace and critical-need escape")
	_check(brain_text.contains("NPCClearPathActivity")
			and brain_text.contains("paused_activity")
			and brain_text.contains("begin_navigation_recovery"),
		"path clearing pauses and later resumes the exact live utility activity")

	var attention_text: String = _read("res://scripts/npc/NPCAttentionController.gd")
	_check(attention_text.contains("class_name NPCAttentionController")
			and attention_text.contains("WeakRef")
			and attention_text.contains("body_turn_allowed"),
		"attention controller preserves the short-lived stimulus contract")
	_check(attention_text.contains("conversation_partner")
			and attention_text.contains("player_conversation")
			and attention_text.contains("player_proximity")
			and attention_text.contains("moving_resident")
			and attention_text.contains("ambient_glance"),
		"attention arbitration covers social, player, resident, and ambient targets")
	_check(attention_text.contains("BODY_YAW_THRESHOLD")
			and attention_text.contains("_stationary_for")
			and attention_text.contains("_angular_velocity")
			and attention_text.contains("can_attention_turn_body"),
		"whole-body attention fallback is thresholded, stationary, and smoothed")

	var metrics_text: String = _read("res://scripts/npc/NPCMetrics.gd")
	_check(metrics_text.contains("static var enabled: bool = false")
			and metrics_text.contains("RECENT_EVENT_CAPACITY: int = 64")
			and metrics_text.contains("static func observe"),
		"NPC metrics are bounded, aggregate, and disabled by default")

	var wander_text: String = _read("res://scripts/npc/activities/WanderActivity.gd")
	_check(wander_text.contains("return 0.25"),
		"wandering yields readily to meaningful behavior")
	_check(wander_text.contains("MIN_TRIP_DISTANCE: float = 3.0"),
		"wander legs reject trivial nearby destinations")
	_check(wander_text.contains("LANDMARK_GROUPS"),
		"free time uses semantic world landmarks")
	_check(wander_text.contains("Going to see %s"),
		"sociable residents can form a visit intention")
	_check(wander_text.contains("SOCIAL_STOP_OFFSET: float = 1.2"),
		"social travel finishes inside the existing Talk range")
	_check(wander_text.contains("SOCIAL_FOLLOW_RESUME_DISTANCE")
			and wander_text.contains("SOCIAL_SETTLE_TIME")
			and wander_text.contains("_follow_speed_scale"),
		"social following uses hysteresis, settling, and pace matching")
	_check(wander_text.contains("NPC_COMPANIONSHIP.should_follow(npc)"),
		"companionship assigns one follower instead of mutual chasing")
	_check(wander_text.contains("RESERVATION_META"),
		"free-time destinations are reserved against crowd convergence")
	_check(wander_text.contains("\"activity\": \"free_time\""),
		"free-time intentions expose structured diagnostics")
	_check(wander_text.contains("_agenda_beats_remaining")
			and wander_text.contains("make_resume_intent"),
		"free time uses bounded agendas and safe continuity hooks")
	_check(not wander_text.contains("npc.look_at("),
		"wander presentation no longer snaps whole-body facing")
	var talk_text: String = _read("res://scripts/npc/activities/TalkActivity.gd")
	_check(not talk_text.contains("npc.look_at(")
			and talk_text.contains("conversation_partner")
			and talk_text.contains("is_player_interacting")
			and talk_text.contains("face_world_position"),
		"conversation facing uses the guaranteed locomotion-rate path")

	var case_fetch_text: String = _read("res://scripts/npc/NPCCaseFetch.gd")
	_check(case_fetch_text.contains("npc_take_one")
			and case_fetch_text.contains("_dispensed.pickup(npc.hold_point)")
			and case_fetch_text.contains("npc.held_item = _dispensed"),
		"case provisions move directly from their case into the NPC held state")
	_check(not case_fetch_text.contains("grab_loose(npc, _case")
			and not case_fetch_text.contains("grab_from_shelf(npc, _origin_shelf")
			and not case_fetch_text.contains("RESHELVE")
			and not case_fetch_text.contains("WAIT_POST_EJECT"),
		"case access no longer picks up, ejects, returns, or re-paths to provisions")
	var can_case_text: String = _read("res://scripts/world/items/CanCase.gd")
	var water_case_text: String = _read("res://scripts/world/items/WaterCase.gd")
	_check(can_case_text.contains("func npc_take_one")
			and water_case_text.contains("func npc_take_one")
			and can_case_text.contains("toward_npc * 0.35")
			and water_case_text.contains("toward_npc * 0.35"),
		"both case types dispense from a collision-safe NPC-facing offset")

	var profile_script: GDScript = load("res://scripts/npc/NPCBehaviorProfile.gd") as GDScript
	var profile_a: RefCounted = profile_script.new()
	profile_a.setup(71237, {
		"sociability": 0.8, "work_ethic": 0.2, "resilience": 0.6,
	})
	var profile_b: RefCounted = profile_script.new()
	profile_b.setup(71237, {
		"sociability": 0.8, "work_ethic": 0.2, "resilience": 0.6,
	})
	_check(profile_a.debug_info() == profile_b.debug_info(),
		"behavior signatures are deterministic for saved identity data")
	_check(profile_a.preferred_social_distance < 1.2 and profile_a.sitting_affinity > 0.4,
		"existing traits coherently shape social distance and sitting preference")

	var relax_text: String = _read("res://scripts/npc/activities/RelaxActivity.gd")
	_check(relax_text.contains("get_leisure_sitting_hours")
			and relax_text.contains("ACTIVE_SCORE_FLOOR")
			and relax_text.contains("func interruptible() -> bool:\n")
			and relax_text.contains("\treturn true"),
		"prolonged leisure sitting remains utility-interruptible")
	var relax_activity: RefCounted = (load(
		"res://scripts/npc/activities/RelaxActivity.gd") as GDScript).new()
	_check(relax_activity.interruptible() and relax_activity.label() == "Sitting around",
		"idle sitting is explicitly visible and safe to preempt")

	var nav_text: String = _read("res://scripts/npc/BunkerNavMesh.gd")
	_check(nav_text.contains("mesh.agent_radius = 0.5"),
		"navigation bake retains wall clearance beyond the physical capsule")

	var npc_text: String = _read("res://scripts/npc/NPC.gd")
	_check(npc_text.contains("NavigationServer3D.map_get_closest_point"),
		"navigation targets and recovery project onto the navigation map")
	_check(npc_text.contains("if not _soft_repath_attempted"),
		"stuck recovery repaths before cancelling an intention")
	_check(npc_text.contains("func cancel_navigation()"),
		"completed intentions clear stale navigation")
	_check(npc_text.contains("nav_agent.path_height_offset = -0.9"),
		"navigation waypoints are raised to NPC body height")
	_check(npc_text.contains("nav_agent.max_speed = _last_requested_nav_speed")
			and npc_text.contains("safe_xz.normalized() * _last_requested_nav_speed"),
		"avoidance cannot accelerate an NPC beyond requested movement speed")
	_check(npc_text.contains("var blend: float = clampf(acceleration * delta, 0.0, 1.0)")
			and npc_text.contains("velocity.x = lerp(velocity.x, 0.0, blend)")
			and npc_text.contains("halt_movement(delta)\n\t\t_last_requested_nav_speed = 0.0"),
		"large transition stops cannot extrapolate through zero and reverse velocity")
	_check(not npc_text.contains("_nudge_free_of_obstruction"),
		"no stuck-recovery branch relocates residents")
	_check(npc_text.contains("NPCDynamicObstacleMap")
			and npc_text.contains("dynamic_detour")
			and npc_text.contains("begin_navigation_recovery")
			and not npc_text.contains("force_command(CleaningActivity.new(stuck_item))"),
		"physics-clutter recovery uses bounded detour/clear overlays instead of Cleaning")
	_check(npc_text.contains("_navigation_remaining_distance")
			and npc_text.contains("_stuck_ref_remaining_distance"),
		"stuck detection measures advancement along the route, not lateral displacement")
	_check(not npc_text.contains("global_position +="),
		"physics pushes do not bypass CharacterBody movement")
	_check(npc_text.contains("func _capture_navigation_trace")
			and npc_text.contains("preferred_velocity")
			and npc_text.contains("safe_velocity_raw")
			and npc_text.contains("achieved_velocity")
			and npc_text.contains("nearby_physics_items"),
		"opt-in navigation diagnostics preserve requested, avoided, achieved, contact, and obstacle state")
	var debug_text: String = _read("res://scripts/npc/NPCDebug.gd")
	_check(debug_text.contains("navigation_trace_enabled: bool = false")
			and debug_text.contains("dump_navigation_state"),
		"navigation flight recording remains observational and disabled by default")
	_check(npc_text.contains("claim_interaction_slot")
			and npc_text.contains("_door_passage_allows"),
		"locomotion uses shared interaction-slot and bottleneck coordination")
	_check(npc_text.contains("func get_navigation_route_cost")
			and npc_text.contains("NavigationServer3D.map_get_path"),
		"interaction slots are ranked by real navigation route cost")
	_check(npc_text.contains("func is_interaction_position_clear")
			and npc_text.contains("PhysicsShapeQueryParameters3D")
			and npc_text.contains("intersect_shape"),
		"interaction slots reject live physics obstructions")
	_check(npc_text.contains("NPCAttentionController")
			and npc_text.contains("func get_attention_task_stimulus")
			and npc_text.contains("func can_attention_turn_body"),
		"each resident owns an independent attention helper")
	_check(npc_text.contains("brain.begin_player_interaction()")
			and npc_text.contains("func end_player_interaction")
			and npc_text.contains("func face_world_position"),
		"NPC UI lifecycle brackets the reversible brain pause")

	var obstacle_map_text: String = _read("res://scripts/npc/NPCDynamicObstacleMap.gd")
	var clear_path_text: String = _read("res://scripts/npc/activities/NPCClearPathActivity.gd")
	var pickupable_text: String = _read("res://scripts/world/items/PickupableItem.gd")
	_check(obstacle_map_text.contains("func corridor_blockers")
			and obstacle_map_text.contains("func choose_detour")
			and obstacle_map_text.contains("func choose_drop_position")
			and obstacle_map_text.contains("is_soft_navigation_clutter"),
		"dynamic occupancy owns corridor, detour, and verified drop queries")
	_check(pickupable_text.contains("func is_soft_navigation_clutter")
			and pickupable_text.contains("if is_soft_navigation_clutter():")
			and pickupable_text.contains("shove_small_items_near")
			and pickupable_text.contains("travel * 0.82")
			and pickupable_text.contains("intersect_shape(params, 64)"),
		"small clutter skips avoidance and parts in the character's travel direction")
	_check(clear_path_text.contains("MAX_DURATION")
			and clear_path_text.contains("_resume_target")
			and clear_path_text.contains("choose_drop_position")
			and clear_path_text.contains("suspend_navigation_for_overlay")
			and clear_path_text.contains("Phase.SHOVE")
			and clear_path_text.contains("apply_central_impulse"),
		"clear-path overlay is bounded, can shove through packed clutter, and restores its route")
	var obstacle_map_script: GDScript = load(
		"res://scripts/npc/NPCDynamicObstacleMap.gd") as GDScript
	_check(is_equal_approx(obstacle_map_script.segment_parameter(
		Vector3(5.0, 0.0, 0.0), Vector3.ZERO, Vector3(10.0, 0.0, 0.0)), 0.5),
		"dynamic corridor geometry projects points along a route")
	_check(is_equal_approx(obstacle_map_script.distance_to_segment(
		Vector3(5.0, 0.0, 2.0), Vector3.ZERO, Vector3(10.0, 0.0, 0.0)), 2.0),
		"dynamic corridor geometry measures lateral clearance deterministically")

	var slot_text: String = _read("res://scripts/npc/NPCInteractionSlots.gd")
	_check(slot_text.contains("get_navigation_route_cost")
			and slot_text.contains("is_interaction_position_clear"),
		"slot arbitration combines route reachability with physical standing clearance")

	var slot_script: GDScript = load("res://scripts/npc/NPCInteractionSlots.gd") as GDScript
	var slot_target := Node3D.new()
	var slot_owner_a := Node3D.new()
	var slot_owner_b := Node3D.new()
	root.add_child(slot_target)
	root.add_child(slot_owner_a)
	root.add_child(slot_owner_b)
	var exclusive_candidates: Array[Dictionary] = [{
		"slot_id": &"left",
		"claim_group": &"one_user",
		"transform": Transform3D.IDENTITY,
	}]
	var lease_a: Dictionary = slot_script.claim_best(
		slot_owner_a, slot_target, &"test", 1.0, exclusive_candidates)
	var lease_b: Dictionary = slot_script.claim_best(
		slot_owner_b, slot_target, &"test", 1.0, exclusive_candidates)
	_check(not lease_a.is_empty() and lease_b.is_empty(),
		"exclusive interaction alternatives cannot be double-claimed")
	slot_script.release(lease_a, slot_owner_a)
	lease_b = slot_script.claim_best(
		slot_owner_b, slot_target, &"test", 1.0, exclusive_candidates)
	_check(not lease_b.is_empty(), "released interaction slots become available immediately")
	slot_script.release_owner(slot_owner_b)
	slot_owner_a.free()
	slot_owner_b.free()
	slot_target.free()

	var door_script: GDScript = load("res://scripts/npc/NPCDoorCoordinator.gd") as GDScript
	var portal := Node3D.new()
	var door_owners: Array[Node3D] = [Node3D.new(), Node3D.new(), Node3D.new()]
	var passage_a: Dictionary = door_script.request(door_owners[0], portal, 1)
	var passage_b: Dictionary = door_script.request(door_owners[1], portal, 1)
	var passage_wait: Dictionary = door_script.request(door_owners[2], portal, -1)
	_check(not passage_a.is_empty() and not passage_b.is_empty() and passage_wait.is_empty(),
		"doorways batch one direction and queue opposing residents")
	door_script.release_owner(door_owners[0])
	door_script.release_owner(door_owners[1])
	passage_wait = door_script.request(door_owners[2], portal, -1)
	_check(not passage_wait.is_empty(), "oldest opposing doorway waiter progresses next")
	for owner: Node3D in door_owners:
		door_script.release_owner(owner)
		owner.free()
	portal.free()

	var sit_text: String = _read("res://scripts/npc/activities/SitActivity.gd")
	var lie_text: String = _read("res://scripts/npc/activities/LieActivity.gd")
	var relax_lie_text: String = _read("res://scripts/npc/activities/RelaxLieActivity.gd")
	_check(not sit_text.contains("npc.global_position ="),
		"chair transitions never snap the NPC root")
	_check(not lie_text.contains("npc.global_position =")
			and not relax_lie_text.contains("npc.global_position ="),
		"bed transitions never snap the NPC root")
	_check(npc_text.contains("var sleeping_bed: Node3D = null")
			and lie_text.contains("NPC.NAV_PRECISE_TARGET_DISTANCE"),
		"bed use navigates precisely and uses the authored animation lifecycle")
	_check(sit_text.contains("claim_group\": &\"seat")
			and lie_text.contains("claim_group\": &\"bed"),
		"chair and bed approaches are exclusively reserved before travel")
	var stove_text: String = _read("res://scripts/world/cooking/Stove.gd")
	var generator_text: String = _read("res://scripts/world/power/GeneratorObject.gd")
	var shelving_text: String = _read("res://scripts/world/furniture/Shelving.gd")
	_check(stove_text.contains("func get_npc_interaction_slots")
			and generator_text.contains("func get_npc_interaction_slots")
			and shelving_text.contains("func get_npc_interaction_slots"),
		"major workstations publish authored approach geometry")

	var query_text: String = _read("res://scripts/npc/queries/NPCJobQueries.gd")
	_check(query_text.contains("_has_fetchable_cooking_item"),
		"autonomous cooking requires real supplies")
	_check(query_text.contains("_stove_can_complete_cooking"),
		"autonomous cooking rejects unpowerable stoves")

	var cleaning_text: String = _read("res://scripts/npc/activities/CleaningActivity.gd")
	_check(cleaning_text.contains("func _begin_basket_delivery"),
		"produce collection transitions from basket filling to delivery")
	_check(cleaning_text.contains("NPCItemUser.release_item(_basket)"),
		"cleaning releases basket claims on exit")
	_check(cleaning_text.contains("LEG_TIMEOUT_SEC: float = 18.0")
			and cleaning_text.contains("interaction leg timed out"),
		"cleaning cannot hold an unreachable item claim indefinitely")
	_check(cleaning_text.contains("func _set_interaction_approach")
			and cleaning_text.contains("reached pickup slot but item remained"),
		"cleaning approaches reachable object sides and abandons invalid arrivals")
	_check(cleaning_text.contains(
			"PICKUP_APPROACH_DISTANCE: float = NPCItemUser.PICKUP_RANGE - 0.35"),
		"pickup slots include the precise-navigation arrival tolerance")

	_finish()


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check(false, "can read %s" % path)
		return ""
	return file.get_as_text()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("NPC_BEHAVIOR_FOUNDATIONS: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("NPC_BEHAVIOR_FOUNDATIONS_OK")
		quit(0)
	else:
		print("NPC_BEHAVIOR_FOUNDATIONS_FAIL: %d" % _failures)
		quit(1)
