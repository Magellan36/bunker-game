extends NPCActivity
class_name PassedOutActivity
## Forced collapse at 0 Energy (Part 14). Never chosen via normal scoring
## — NPCBrain.tick() force-starts this directly, bypassing _think()
## entirely, since it must preempt anything mid-activity. Regenerates
## Energy slowly while "lying there," slower than a bed OR a chair —
## passing out is a bad outcome, not a rest strategy. Only ends once
## Energy is completely full again, per spec.
##
## FUTURE WORK: this only rotates the NPC in place as a first-pass
## "collapsed" visual (mirrors the lie-flat trick LieActivity uses on a
## bed) — it doesn't yet drop them to a true floor-lying Y position or
## play any real collapse animation. Revisit once there's a proper
## reference for what that should look like.
const REGEN_PER_GAME_HOUR: float = 15.0   ## slower than SitActivity (25) and LieActivity (45) on purpose
## Wakes at 15, not full — deliberately leaves them still needing real
## rest afterward. Also the intended hook for a future "administer an
## energy item to wake them faster" player action: something reaching
## into this state and pushing energy toward 15 should end this the
## same way natural regen does, no separate code path needed.
const WAKE_ENERGY: float = 15.0

var _orig_rotation: Vector3 = Vector3.ZERO

func label() -> String:
	return "Passed Out"

func score(_npc: NPC) -> float:
	return 0.0   ## never selected via normal scoring — force-started only

func interruptible() -> bool:
	return false

func enter(npc: NPC) -> void:
	_orig_rotation = npc.rotation
	npc.lock_movement()
	npc.rotation = Vector3(_orig_rotation.x, _orig_rotation.y,
		_orig_rotation.z + deg_to_rad(90.0))
	## Mood hit on collapse — lower bound fixed at 1%, upper bound is
	## 10% scaled by Neuroticism (baseline 10%, Neurotic 15%,
	## Easygoing 5%). One-time, applied here at the moment of
	## collapse, not repeated per-tick while passed out.
	var mood_drop: float = randf_range(1.0, 10.0 * npc.neuroticism_trait_mult())
	npc.mood = clampf(npc.mood - mood_drop, 0.0, 100.0)
	if NPCDebug.enabled:
		NPCDebug.log_mood_event(npc, -mood_drop, "passed out")
	npc.log_action("Passed out (0 energy)")

func tick(npc: NPC, delta: float) -> void:
	npc.energy = minf(100.0, npc.energy + REGEN_PER_GAME_HOUR * npc.game_hours(delta))

func done(npc: NPC) -> bool:
	return npc.energy >= WAKE_ENERGY

func exit(npc: NPC) -> void:
	npc.log_action("Woke up")
	npc.rotation = _orig_rotation