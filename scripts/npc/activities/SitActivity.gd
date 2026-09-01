extends NPCActivity
class_name SitActivity
## Walk to the nearest free chair, sit (full animated Adventurer sit sequence,
## matching the player), recover Energy, stand when rested.
##
## Aug 2026 — port of the player's sit sequence to NPCs. The shared
## AdventurerModelController already drives the stand_to_sit / sit /
## sit_to_stand clips for an NPC (it reads the NPC's seated_chair the same way
## it reads the player's). What was missing was the positional side: the
## controller eases the body between an APPROACH point (near the chair front)
## and the SEAT over each transition clip, lowers it, and clamps the feet — but
## the NPC activities never set _chair_approach_pos/_chair_seat_pos, so they
## stayed Vector3.ZERO and the eased slide fought the old instant snap.
##
## This class now sets those anchors exactly like MainWorld._wire_chair() does
## for the player, and drives a three-state lifecycle (SEEK -> SEATED ->
## STANDING) so the NPC eases INTO the chair over stand_to_sit and OUT over
## sit_to_stand before walking off — the exact same sequence the player gets,
## both genders (the controller resolves the right male/female clips). NPC
## physics (gravity/move_and_slide) is frozen during the sequence via
## NPC.in_sit_sequence() so it doesn't fight the eased position, mirroring the
## player's set_physics_process(false).
const SIT_UNTIL_ENERGY: float = 90.0
const ENERGY_REGEN_PER_GAME_HOUR: float = 25.0
## ~half a chair width in front of the seat — matches MainWorld._wire_chair's
## APPROACH_OFFSET so the slide distance/pacing matches the player's.
const APPROACH_OFFSET: float = 0.4

enum SState { SEEK, SEATED, STANDING }

var _chair: Node = null
var _state: SState = SState.SEEK

func label() -> String:
	match _state:
		SState.SEEK: return "Finding a seat"
		SState.STANDING: return "Standing up"
		_: return "Resting"

func score(npc: NPC) -> float:
	if npc.energy >= 60.0:
		return 0.0
	if _find_free_chair(npc) == null:
		return 0.0
	return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()   ## 40..100 as energy falls 60→0

func interruptible() -> bool:
	## Once committed to sitting/standing, finish it — mirrors the player, who
	## also can't be yanked out mid-sequence (only commands / pass-out can).
	return _state == SState.SEEK

func enter(npc: NPC) -> void:
	_chair = _find_free_chair(npc)
	_state = SState.SEEK
	if _chair == null:
		return
	npc.set_nav_target((_chair as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _chair == null or not is_instance_valid(_chair):
		## Chair vanished mid-sit — clear the seat and let the controller finish
		## the stand-up on its own (in_sit_sequence() frees physics once done).
		## For the standalone (non-exit) case there's no stand position to snap
		## to, so just leave the NPC where the controller settles it.
		if _state != SState.SEEK and npc.seated_chair != null:
			npc.seated_chair = null
		_chair = null
		_state = SState.SEEK
		return
	match _state:
		SState.SEEK:
			npc.nav_steer(delta)
			var chair_pos: Vector3 = (_chair as Node3D).global_position
			var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
				.distance_to(Vector2(chair_pos.x, chair_pos.z))
			if npc.nav_finished() or flat_dist < 0.9:
				## Claim + start the animated sit-down (mirrors the player seat
				## flow; the controller owns the eased approach→seat motion).
				if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
					_begin_sit(npc)
					_state = SState.SEATED
				else:
					_chair = null   ## someone took it — done() ends us; rescore
		SState.SEATED:
			_regen_energy(npc, delta)
			if _should_stand(npc):
				_begin_stand(npc)
				_state = SState.STANDING
		SState.STANDING:
			if not npc.in_sit_sequence():
				## sit_to_stand finished — place the NPC in front of the chair
				## and release it, exactly like the player's stand completion.
				npc.global_position = (_chair as Node3D).get_stand_position()
				_release_chair(npc)
				_state = SState.SEEK

func done(npc: NPC) -> bool:
	## Done once we've stood up and released the chair (back in SEEK with no
	## chair), or if we never found a chair to begin with.
	return _chair == null

func exit(npc: NPC) -> void:
	## Cleanup on interrupt / command / session-end. If mid-sit, request an
	## ANIMATED stand-up and let the NPC finish it (pending-stand snap in
	## NPC._physics_process), so even an exit() doesn't teleport the NPC.
	if _state != SState.SEEK and _chair != null and is_instance_valid(_chair):
		npc.seated_chair = null
		npc.set("_pending_stand_pos", (_chair as Node3D).get_stand_position())
		npc.set("_stand_pos_pending", true)
	_release_chair(npc)
	_state = SState.SEEK

## Claim + start the animated sit-down. Positions the NPC at the approach
## point (standing height preserved), sets the controller's approach/seat
## anchors exactly like MainWorld._wire_chair, then sets seated_chair to kick
## off the controller's sitting_down phase — no instant snap to the seat.
func _begin_sit(npc: NPC) -> void:
	var t: Transform3D = (_chair as Node3D).get_seat_transform()
	npc.rotation.y = t.basis.get_euler().y
	var approach_pos: Vector3 = t.origin + t.basis.z * APPROACH_OFFSET
	approach_pos.y = npc.global_position.y
	npc.global_position = approach_pos
	var model: Node = npc.get_node_or_null("CharacterModel")
	if model != null:
		model.set("_chair_approach_pos", approach_pos)
		model.set("_chair_seat_pos", Vector3(t.origin.x, approach_pos.y, t.origin.z))
	npc.seated_chair = _chair   ## starts the controller's sitting_down phase
	npc.lock_movement()

## Start the animated stand-up. Clearing seated_chair makes the controller
## play sit_to_stand and ease seat→approach; NPC.in_sit_sequence() keeps
## physics frozen until it finishes, then the STANDING state places the NPC.
func _begin_stand(npc: NPC) -> void:
	npc.seated_chair = null

## Energy regen while seated. Overridable — RelaxSitActivity scales it down.
func _regen_energy(npc: NPC, delta: float) -> void:
	npc.energy = minf(100.0, npc.energy
		+ ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))

## Whether the seated NPC should stand. Overridable — RelaxSitActivity never
## stands on energy alone (its session timer owns the exit instead).
func _should_stand(npc: NPC) -> bool:
	return npc.energy >= SIT_UNTIL_ENERGY

func _release_chair(npc: NPC) -> void:
	if _chair != null and is_instance_valid(_chair):
		if _chair.has_method("npc_stand"):
			_chair.npc_stand(npc)
	_chair = null

func _find_free_chair(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for c: Node in npc.get_tree().get_nodes_in_group("chair"):
		if not is_instance_valid(c):
			continue
		if c.has_method("is_seat_free") and not c.is_seat_free():
			continue
		var c_pos: Vector3 = (c as Node3D).global_position
		var d: float = Vector2(c_pos.x, c_pos.z) \
			.distance_to(Vector2(npc.global_position.x, npc.global_position.z))
		if d < best_d:
			best_d = d
			best = c
	return best
