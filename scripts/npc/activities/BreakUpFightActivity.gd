extends NPCActivity
## BreakUpFightActivity.gd (Sep 2026) — a resident steps in to break up a
## fist fight: walks over, gets between them and pulls the brawler off.
##
## Fights are a rare emergency in a colony, and people who live together
## stop them. CrashOutActivity picks a peacemaker from the onlookers (brave
## enough, and a friend of one of the two) and sets
## `combat.break_up_id` on them; this carries it out. Pulling someone off
## sets `combat.separated` on the brawler, whose crash-out then
## disengages. The victim is grateful; a brawler who liked the peacemaker
## takes it, one who didn't resents it a little.

const REACH: float = 1.4
const GIVE_UP_SECONDS: float = 10.0

var _timer: float = 0.0

func score(npc: NPC) -> float:
	return 900.0 if _brawler(npc) != null else 0.0

func label() -> String:
	return "Breaking up a fight"

func interruptible() -> bool:
	return false

func backoff_on_futile() -> bool:
	return false

func enter(npc: NPC) -> void:
	_timer = 0.0
	npc.bark_event("hurt")   ## "Stop!" and the like

func tick(npc: NPC, delta: float) -> void:
	_timer += delta
	var b: NPC = _brawler(npc)
	if b == null or _timer > GIVE_UP_SECONDS:
		NPCCombatDebug.trace(npc, "stops stepping in (%s)" % ("fight already over" if b == null else "gave up after %.0fs" % GIVE_UP_SECONDS))
		npc.combat.break_up_id = ""
		npc.combat.rushing = false
		return
	var d: float = NPCItemUser.flat_distance(npc.global_position, b.global_position)
	if d > REACH:
		npc.combat.rushing = d > REACH + 0.5   ## run over to stop it
		npc.set_nav_target(b.global_position)
		npc.nav_steer(delta)
		return
	npc.combat.rushing = false
	npc.halt_movement(delta)
	_separate(npc, b)

func done(npc: NPC) -> bool:
	return npc.combat.break_up_id == ""

func exit(npc: NPC) -> void:
	npc.combat.rushing = false
	npc.combat.break_up_id = ""

func attention_target(npc: NPC) -> Node3D:
	return _brawler(npc)

## The brawler they set out to stop, while that fight is still on.
func _brawler(npc: NPC) -> NPC:
	if npc.combat.break_up_id == "" or npc.combat.dead:
		return null
	var b: NPC = npc.crash._find(npc.combat.break_up_id)
	if b == null or b.is_dead() or b.combat.attacking_id == "":
		return null
	return b

func _separate(npc: NPC, b: NPC) -> void:
	var victim: NPC = npc.crash._find(b.combat.attacking_id)
	NPCCombatDebug.trace(npc, "SEPARATED %s from %s" % [b.npc_name, victim.npc_name if victim != null else "the player"])
	b.combat.separated = true
	b.combat.separated_by = npc.npc_name
	npc.combat.break_up_id = ""
	npc.log_event("bond", "Pulled %s off %s" % [b.npc_name, victim.npc_name if victim != null else "someone"])
	if victim != null and victim != npc:
		victim.bonds.relate(npc.npc_id, 12.0, "pulled %s off me" % b.npc_name,
			"%s pulled %s off me" % [npc.npc_name, b.npc_name], true)
	## A friend holding them back is forgiven; anyone else is resented a bit.
	b.bonds.relate(npc.npc_id, 2.0 if b.get_relationship(npc.npc_id) >= 30.0 else -5.0, "held me back from %s" % (victim.npc_name if victim != null else "a fight"))
	if victim != null:   ## those who care about the victim think well of the peacemaker
		NPCBonds.witnessed(npc.get_tree(), npc.npc_id, victim, 5.0, "pulled %s off %s" % [b.npc_name, victim.npc_name])
