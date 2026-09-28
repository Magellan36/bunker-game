extends RefCounted
class_name NPCBonds
## NPCBonds.gd (Sep 2026) — every relationship change, with its reason, and
## the "big moments" a resident remembers (plans/NPC_MORALE_CRASHOUT_PLAN.md).
##
## relate() is the ONE place relationships change. It:
##   • applies the change (NPC._adjust_relationship: sociability-scaled,
##     clamped),
##   • logs it in plain words on the resident's activity log
##     ("You shared your meal with me (+6.0)"),
##   • turns significant moments into named MEMORIES shown on the panel
##     ("Remembers: You took my food when I was starving (−8)").
## Small everyday drift (time spent together) isn't logged line by line; it
## is summed per person and reported once a game day.
##
## Negativity bias: bad memories last 3× longer than good ones (18 vs 6
## game days), so cruelty has lasting consequences and kindness has to be
## kept up.
##
## Also: third-party effects (seeing someone help or hurt a friend) and
## shared grievances (two residents who both despise the same person bond
## over it — how alliances against someone form).

const MEMORY_MIN: float = 5.0            ## |applied| at or above this becomes a named memory
const GOOD_MEMORY_DAYS: float = 6.0
const BAD_MEMORY_DAYS: float = 18.0
const MAX_MEMORIES: int = 24
const LOG_MIN: float = 0.5               ## smaller changes are summed into the daily line
const WITNESS_RANGE: float = 9.0
const GRIEVANCE_BELOW: float = -40.0

var memories: Array[Dictionary] = []     ## {target, name, text, amount, stamp, until}
var _small: Dictionary = {}              ## target id -> summed small change today
var _small_day: int = -1
var _grievances: Dictionary = {}         ## "otherId|targetId" -> true (bonded over it already)

var _npc: NPC = null

func setup(npc: NPC) -> void:
	_npc = npc

## The single entry point. `reason` is what the OTHER person did, as a verb
## phrase from this resident's point of view — "gave me water when I was
## parched" — so the log reads "You gave me water when I was parched
## (+15.0)". `memory` (optional) overrides the remembered line. Returns the
## applied change.
func relate(target_id: String, amount: float, reason: String, memory: String = "", force_memory: bool = false) -> float:
	if target_id == "" or target_id == _npc.npc_id or is_zero_approx(amount):
		return 0.0
	var applied: float = _npc._adjust_relationship(target_id, amount)
	if is_zero_approx(applied):
		return 0.0
	var who: String = display_name(target_id)
	var line: String = "%s %s" % [who, reason]
	if absf(applied) >= LOG_MIN:
		_npc.log_event("bond", "%s (%+.1f)" % [line, applied])
	else:
		_small[target_id] = float(_small.get(target_id, 0.0)) + applied
	if force_memory or absf(applied) >= MEMORY_MIN:
		_remember(target_id, memory if memory != "" else line, applied)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(_npc, target_id, amount, reason)
	return applied

func _remember(target_id: String, text: String, amount: float) -> void:
	var now: float = NPCClock.now()
	var days: float = GOOD_MEMORY_DAYS if amount > 0.0 else BAD_MEMORY_DAYS
	memories.append({"target": target_id, "name": display_name(target_id), "text": text,
		"amount": amount, "stamp": now, "until": now + days * 24.0})
	if memories.size() > MAX_MEMORIES:
		## Drop the faintest (smallest, oldest good memory first).
		var weakest: int = 0
		for i: int in memories.size():
			if _weight(memories[i]) < _weight(memories[weakest]):
				weakest = i
		memories.remove_at(weakest)
	_npc.log_event("memory", "Will remember: \"%s\"" % text)

static func _weight(m: Dictionary) -> float:
	return absf(float(m["amount"])) * (1.0 if float(m["amount"]) > 0.0 else 1.5)

# ─── Daily upkeep ───────────────────────────────────────────────────────────
func tick(_h: float) -> void:
	var now: float = NPCClock.now()
	for i: int in range(memories.size() - 1, -1, -1):
		var m: Dictionary = memories[i]
		if now >= float(m["until"]):
			memories.remove_at(i)
			if float(m["amount"]) < 0.0:
				_npc.log_event("memory", "Has mostly let go of: \"%s\"" % String(m["text"]))
	var day: int = int(floor(now / 24.0))
	if _small_day < 0:
		_small_day = day
	elif day != _small_day:
		_small_day = day
		var parts: Array[String] = []
		for id: String in _small.keys():
			var v: float = float(_small[id])
			if absf(v) >= 0.2:
				parts.append("%s %+.1f" % [display_name(id), v])
		if not parts.is_empty():
			_npc.log_event("bond", "Time together today: %s" % ", ".join(parts))
		_small.clear()
		_check_shared_grievances()

## Two residents who both despise the same person bond over it (once per
## pair and target). This is how two of them end up siding against the player.
func _check_shared_grievances() -> void:
	for other: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if other == _npc or not (other is NPC):
			continue
		for target_id: String in _npc.relationships.keys():
			if target_id == other.npc_id or _npc.get_relationship(target_id) > GRIEVANCE_BELOW:
				continue
			if other.get_relationship(target_id) > GRIEVANCE_BELOW:
				continue
			var key: String = "%s|%s" % [other.npc_id, target_id]
			if _grievances.has(key):
				continue
			_grievances[key] = true
			var whom: String = "you" if target_id == "player" else display_name(target_id)
			relate(other.npc_id, 4.0, "can't stand %s either" % whom,
				"%s gets it — we both can't stand %s" % [other.npc_name, whom], true)

# ─── Third-party effects ────────────────────────────────────────────────────
## Someone (`actor_id`) helped or hurt `victim` in view of others: residents
## who care about the victim (friends) or resent them (enemies) shift their
## view of the actor accordingly.
static func witnessed(tree: SceneTree, actor_id: String, victim: Node3D, amount: float, what: String) -> void:
	var victim_id: String = "player" if victim.is_in_group("player") else String(victim.get("npc_id"))
	for w: Node in tree.get_nodes_in_group("npc"):
		if not (w is NPC) or w == victim or String(w.npc_id) == actor_id:
			continue
		if NPCItemUser.flat_distance(w.global_position, victim.global_position) > WITNESS_RANGE or not w._can_see(victim):
			continue
		var care: float = w.get_relationship(victim_id) / 100.0   ## friend +, enemy −
		if absf(care) < 0.15:
			continue
		var delta: float = amount * care * 0.6
		w.bonds.relate(actor_id, delta, "%s in front of me" % what)

# ─── Queries ────────────────────────────────────────────────────────────────
## Newest first; optionally only memories about one person.
func get_memories(target_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in memories:
		if target_id == "" or m["target"] == target_id:
			out.append(m)
	out.reverse()
	return out

## Sum of remembered grudges against someone (negative number or 0).
func grudge_against(target_id: String) -> float:
	var g: float = 0.0
	for m: Dictionary in memories:
		if m["target"] == target_id and float(m["amount"]) < 0.0:
			g += float(m["amount"])
	return g

func display_name(target_id: String) -> String:
	if target_id == "player":
		return "You"
	for other: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if other is NPC and String(other.npc_id) == target_id:
			return String(other.npc_name)
	return "someone"

static func _capital(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

# ─── Save / load ────────────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"memories": memories.duplicate(true), "small": _small.duplicate(), "small_day": _small_day,
		"griev": _grievances.keys()}

func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	memories.clear()
	for m: Variant in d.get("memories", []):
		if m is Dictionary:
			memories.append((m as Dictionary).duplicate())
	_small = (d.get("small", {}) as Dictionary).duplicate()
	_small_day = int(d.get("small_day", -1))
	_grievances.clear()
	for k: Variant in d.get("griev", []):
		_grievances[String(k)] = true
