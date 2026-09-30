extends RefCounted
class_name NPCCombatDebug
## NPCCombatDebug.gd (Sep 2026) — dev tools for NPC combat and its colony
## side: fights, de-escalation, peacemakers, shunning, rescues. Driven from
## the F7 admin menu's "NPC COMBAT" section; everything here is static
## state and helpers, off by default, no cost when off.
##
## "A" is the resident nearest the player, "B" the next nearest (so stand
## beside the two you want to test).
##
## Log lines are prefixed "[Combat]" so they can be grepped; they print
## only while `enabled` (the F7 toggle), except the dump.

static var enabled: bool = false          ## verbose [Combat] console lines
static var overlay: bool = false          ## live combat readout above each resident
static var ignore_cooldown: bool = false  ## the colony-wide 8 h fist-fight cooldown never holds a fight back

## Forced outcomes (normal = the real odds).
enum Deesc { NORMAL, ALWAYS_BACK_DOWN, ALWAYS_TALKED_DOWN, NEVER }
static var deesc_mode: Deesc = Deesc.NORMAL
enum Peace { NORMAL, ALWAYS, NEVER }
static var peace_mode: Peace = Peace.NORMAL

const DEESC_NAMES: Array[String] = ["normal odds", "target always backs down", "friend always talks down", "never"]
const PEACE_NAMES: Array[String] = ["normal odds", "always (if anyone qualifies)", "never"]

static func trace(npc: Node, text: String) -> void:
	if not enabled:
		return
	var who: String = String(npc.get("npc_name")) if npc != null and "npc_name" in npc else "-"
	print("[Combat] t=%.2fh %s: %s" % [NPCClock.now(), who, text])

static func cycle_deesc() -> String:
	deesc_mode = ((int(deesc_mode) + 1) % DEESC_NAMES.size()) as Deesc
	return DEESC_NAMES[int(deesc_mode)]

static func cycle_peace() -> String:
	peace_mode = ((int(peace_mode) + 1) % PEACE_NAMES.size()) as Peace
	return PEACE_NAMES[int(peace_mode)]

# ─── Picking residents ──────────────────────────────────────────────────────
static func _player(tree: SceneTree) -> Node3D:
	return tree.get_first_node_in_group("player") as Node3D

## Living residents, nearest the player first.
static func by_distance(tree: SceneTree) -> Array[NPC]:
	var out: Array[NPC] = []
	for n: Node in tree.get_nodes_in_group("npc"):
		if n is NPC and not (n as NPC).is_dead():
			out.append(n as NPC)
	var p: Node3D = _player(tree)
	if p != null:
		out.sort_custom(func(a: NPC, b: NPC) -> bool:
			return a.global_position.distance_squared_to(p.global_position) < b.global_position.distance_squared_to(p.global_position))
	return out

static func _pair(tree: SceneTree) -> Array[NPC]:
	var all: Array[NPC] = by_distance(tree)
	if all.size() < 2:
		_say("Needs two residents near you (A = nearest, B = next nearest).")
		return []
	return [all[0], all[1]]

static func _one(tree: SceneTree) -> NPC:
	var all: Array[NPC] = by_distance(tree)
	if all.is_empty():
		_say("No living resident nearby.")
		return null
	return all[0]

static func _say(text: String) -> void:
	print("[Combat] %s" % text)
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO, text)

# ─── Scenario triggers (F7 rows) ────────────────────────────────────────────
## A crash-out at `target_id` with a set hatred: -55 = fist fight, -80 = weapon.
## Exact: past crash-outs and grudges are compensated so the tier hatred is
## `hatred` (pressing it again doesn't compound).
static func _start_rage(a: NPC, target_id: String, hatred: float) -> void:
	if a.crash.active():
		a.crash.finish()
	if a.brain != null:
		a.brain.stop_current()
	a.crash.count = 0   ## begin() makes it 1: no repeat shift
	a.combat.attacked_by = ""
	a.relationships[target_id] = clampf(hatred - a.bonds.grudge_against(target_id) * 0.5, NPC.RELATIONSHIP_MIN, NPC.RELATIONSHIP_MAX)
	a.crash.target_id = target_id
	a.crash.begin(NPCCrashOut.Mode.HOSTILE)
	trace(a, "debug: forced HOSTILE crash-out at %s, hatred %.0f" % [target_id, hatred])

static func force_brawl(tree: SceneTree) -> void:
	var p: Array[NPC] = _pair(tree)
	if p.is_empty():
		return
	_start_rage(p[0], p[1].npc_id, -55.0)
	_say("%s picks a fist fight with %s (rant first; de-escalation rolls apply)." % [p[0].npc_name, p[1].npc_name])

static func force_weapon_attack(tree: SceneTree) -> void:
	var p: Array[NPC] = _pair(tree)
	if p.is_empty():
		return
	FarmingShopHelper.spawn_scene_settled(tree.get_first_node_in_group("main_world"), "res://scenes/weapons/Bat.tscn",
		p[0].global_position + Vector3(0.8, 0.3, 0.0))
	_start_rage(p[0], p[1].npc_id, -80.0)
	_say("%s goes for the bat beside them to attack %s (escalated)." % [p[0].npc_name, p[1].npc_name])

static func force_brawl_player(tree: SceneTree) -> void:
	var a: NPC = _one(tree)
	if a != null:
		_start_rage(a, "player", -55.0)
		_say("%s picks a fist fight with you." % a.npc_name)

static func force_weapon_player(tree: SceneTree) -> void:
	var a: NPC = _one(tree)
	if a == null:
		return
	FarmingShopHelper.spawn_scene_settled(tree.get_first_node_in_group("main_world"), "res://scenes/weapons/Bat.tscn",
		a.global_position + Vector3(0.8, 0.3, 0.0))
	_start_rage(a, "player", -80.0)
	_say("%s grabs a bat and comes for you." % a.npc_name)

## The player hits A (tests flight/fight-back, witnesses, bystanders, and —
## if A is attacking someone — stepping in / rescue credit).
static func player_hits(tree: SceneTree, kind: String, dmg: float) -> void:
	var a: NPC = _one(tree)
	var pl: Node3D = _player(tree)
	if a == null or pl == null:
		return
	a.receive_weapon_hit({"damage": dmg, "position": a.global_position + Vector3.UP * 0.3,
		"direction": (a.global_position - pl.global_position).normalized(), "kind": kind, "source": pl, "collider": a})
	_say("You hit %s (%s, %d). Health now %.0f." % [a.npc_name, kind, int(dmg), a.health])

## A at death's door (20 health, bleeding) — treat them with a Bandage to
## test the "kept me alive" rescue.
static func make_critical(tree: SceneTree) -> void:
	var a: NPC = _one(tree)
	if a == null:
		return
	a.health = 20.0
	if a.medical != null:
		a.medical.spawn_bleeding(MedicalCondition.BodyPart.LEFT_ARM)
	_say("%s is at 20 health and bleeding. Treat them (F7 MEDICAL → Spawn Bandage) for a rescue." % a.npc_name)

## A remembers B attacking them (and dislikes them): while B is within 5 m,
## A's work scores drop ("Won't work next to B" in A's log).
static func force_shun(tree: SceneTree) -> void:
	var p: Array[NPC] = _pair(tree)
	if p.is_empty():
		return
	p[0].relationships[p[1].npc_id] = minf(p[0].get_relationship(p[1].npc_id), -40.0)
	p[0].bonds.relate(p[1].npc_id, -30.0, "attacked me (debug)", "%s attacked me with a fist" % p[1].npc_name, true)
	_say("%s now shuns %s for 48 h. Put %s near %s's work to see it (work x%.1f)." % [p[0].npc_name, p[1].npc_name,
		p[1].npc_name, p[0].npc_name, NPCCombat.SHUN_WORK_MULT])

## Every living resident likes every other (>= 50), is brave and unafraid,
## so a peacemaker and a talk-down are possible — pair with the forced modes.
static func make_friends_nearby(tree: SceneTree) -> void:
	var all: Array[NPC] = by_distance(tree)
	for x: NPC in all:
		for y: NPC in all:
			if x != y:
				x.relationships[y.npc_id] = maxf(x.get_relationship(y.npc_id), 50.0)
	for x: NPC in all:
		x.personality["resilience"] = maxf(x._trait("resilience"), 0.7)
		x.social.fear = 0.0
	_say("Everyone likes everyone (>= 50), resilience >= 0.7, no fear: anyone can talk down or step in.")

static func reset_cooldown() -> void:
	NPCCombat.last_fight_hours = -100.0
	_say("Colony fight cooldown cleared.")

static func stop_all_fights(tree: SceneTree) -> void:
	var n: int = 0
	for x: NPC in by_distance(tree):
		if x.crash.active() or x.combat.is_fleeing() or x.combat.break_up_id != "":
			x.combat.flee_until_msec = 0
			x.combat.break_up_id = ""
			x.combat.attacking_id = ""
			if x.crash.active():
				x.crash.ends_at = NPCClock.now()   ## NPCCrashOut ends it on its next check
			n += 1
	_say("Stopping %d crash-outs / flights." % n)

## Back to a clean slate for the next test: everyone healed and calm, no
## fights, fear, grudges from attacks, or cooldown.
static func reset_test(tree: SceneTree) -> void:
	for x: NPC in by_distance(tree):
		x.health = 100.0
		x.social.fear = 0.0
		x.combat.flee_until_msec = 0
		x.combat.break_up_id = ""
		x.combat.attacking_id = ""
		x.combat.attacked_by = ""
		x.combat.escalate = false
		x.crash.count = 0
		if x.crash.active():
			x.crash.ends_at = NPCClock.now()
		x.bonds.memories.assign(x.bonds.memories.filter(func(m: Dictionary) -> bool: return not String(m.get("text", "")).contains("attacked me")))
	NPCCombat.last_fight_hours = -100.0
	_say("Combat test reset: healed, calm, no fights, attack memories and cooldown cleared.")

static func kill_nearest(tree: SceneTree) -> void:
	var a: NPC = _one(tree)
	if a != null:
		a.combat.die("injuries", "")
		_say("%s died (debug)." % a.npc_name)

# ─── State ──────────────────────────────────────────────────────────────────
static func state_line(n: NPC) -> String:
	var parts: Array[String] = ["HP %d" % int(round(n.health))]
	if n.is_dead():
		return "DEAD — %s" % n.combat.describe_death()
	if n.crash.active():
		var tid: String = n.crash.target_id
		var hate: float = CrashOutActivity.tier_hatred(n) if tid != "" else 0.0
		var tier: String = "weapon" if hate <= CrashOutActivity.ESCALATE_BELOW else ("fists" if hate <= CrashOutActivity.BRAWL_BELOW else "rant")
		parts.append("%s → %s (hate %.0f: %s)" % [n.crash.mode_name(), n.bonds.display_name(tid) if tid != "" else "-", hate, tier])
	if n.combat.debug_phase != "":
		parts.append(n.combat.debug_phase)
	if n.combat.attacking_id != "":
		parts.append("ATTACKING %s" % n.bonds.display_name(n.combat.attacking_id))
	if n.combat.is_fleeing():
		parts.append("fleeing %s %.1fs" % [n.bonds.display_name(n.combat.flee_from) if n.combat.flee_from != "" else "?",
			(n.combat.flee_until_msec - Time.get_ticks_msec()) / 1000.0])
	if n.combat.break_up_id != "":
		parts.append("STEPPING IN on %s" % n.bonds.display_name(n.combat.break_up_id))
	var shunned: Array[String] = []
	for o: Node in n.get_tree().get_nodes_in_group("npc"):
		if o != n and o is NPC and n.combat.shuns(o as NPC):
			shunned.append((o as NPC).npc_name)
	if not shunned.is_empty():
		parts.append("shuns %s" % ", ".join(shunned))
	if n.social.fear > 1.0:
		parts.append("fear %d" % int(n.social.fear))
	var since: float = NPCClock.now() - n.combat.last_rescued_hours
	if since < NPCCombat.RESCUE_REPEAT_H:
		parts.append("rescued %.1fh ago" % since)
	return " | ".join(parts)

static func dump(tree: SceneTree) -> void:
	var cd: float = NPCCombat.FIGHT_COOLDOWN_H - (NPCClock.now() - NPCCombat.last_fight_hours)
	print("══════ NPC COMBAT STATE (t=%.2fh) ══════" % NPCClock.now())
	print("  colony fight cooldown: %s%s | de-escalation: %s | peacemakers: %s" % [
		"%.1fh left" % cd if cd > 0.0 else "clear", " (ignored)" if ignore_cooldown else "",
		DEESC_NAMES[int(deesc_mode)], PEACE_NAMES[int(peace_mode)]])
	for n: Node in tree.get_nodes_in_group("npc") + tree.get_nodes_in_group("npc_dead"):
		if n is NPC:
			print("  %-10s %s" % [(n as NPC).npc_name, state_line(n as NPC)])
			var mem: Array = (n as NPC).bonds.memories.slice(maxi(0, (n as NPC).bonds.memories.size() - 3))
			for m: Dictionary in mem:
				print("             memory: %s (%+.0f)" % [String(m["text"]), float(m["amount"])])
	_say("Combat state printed to the console.")
