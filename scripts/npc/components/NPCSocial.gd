extends RefCounted
class_name NPCSocial
## NPCSocial.gd (Sep 2026) — how the PLAYER's conduct shapes a resident's
## view of them (plans/NPC_MORALE_CRASHOUT_PLAN.md, "Relationship verbs").
## Every effect goes through NPCBonds.relate(), so it is logged with its
## reason and big moments become memories.
##
##   Leadership   workload (orders while exhausted/starving, too many orders),
##                pitching in with the work, favouritism, hoarding food,
##                sleeping in their bed, and daily BLAME for living conditions
##                (softened by visible effort to fix things).
##   Talk         check in · encourage · joke · vent · insult · threaten —
##                reception depends on traits and mood; each has a daily
##                cooldown so talking is meaningful, not a grind.
##   Promises     promise to fix what's weighing on them most; kept → a
##                lasting good memory, broken → a lasting bad one.
##   Take sides   in a feud between this resident and another.
##
## Harsh leadership PAYS in the short term (Brannon, Sep 2026) — otherwise
## nobody would choose it:
##   • PRESSURE (0..100, fades ~10/game hour) is WORK DRIVE: job scores
##     ×(1 + 2.5·drive), leisure ×(1 − 0.8·drive) and no breaks (relax/lean)
##     above 0.4, work speed ×(1 + 0.25·drive), and orders are accepted more
##     readily. Threaten +65 (and idle residents
##     get moving right away), Be firm +35, Insult +20, Encourage +3 for the
##     Lazy (+25 for Hard Workers — kindness motivates people who already
##     want to work). Repeated pressure in a day works less and less.
##   • COWED (24 h after an insult): no tantrums (irritability capped below
##     "Mad"), no food snatching, and a crash-out that would have been hostile
##     is bottled up as a breakdown instead.
##   The bill comes later: relationship, fear and 18-day grudges, which is
##   exactly what turns into hostile crash-outs when morale finally breaks.
##
## LAZY residents (Work Ethic low) prefer leisure over ordinary jobs, and
## refuse work orders by chance. Kindness barely moves them; firmness does.

const ORDERS_TOO_MANY: int = 6
const WORKED_ALONGSIDE_RANGE: float = 9.0
const WORKED_ALONGSIDE_GAP_HOURS: float = 0.33
const HOARD_GAP_HOURS: float = 8.0
const BLAME_THRESHOLD: float = -10.0       ## morale points from the bunker itself
const PROMISE_HOURS: float = 48.0
const TALK_COOLDOWN_HOURS: float = 20.0

const TALK_CHOICES: Array[Dictionary] = [
	{"id": "check_in",  "label": "Check in",   "tone": "kind"},
	{"id": "encourage", "label": "Encourage",  "tone": "kind"},
	{"id": "joke",      "label": "Joke",       "tone": "light"},
	{"id": "vent",      "label": "Vent",       "tone": "light"},
	{"id": "firm",      "label": "Be firm",    "tone": "firm"},
	{"id": "insult",    "label": "Insult",     "tone": "cruel"},
	{"id": "threaten",  "label": "Threaten",   "tone": "cruel"},
]
## Game hours before the same choice can be used again, by tone.
const TALK_COOLDOWN_BY_TONE: Dictionary = {"kind": 20.0, "light": 20.0, "firm": 4.0, "cruel": 8.0}

const PRESSURE_DECAY_PER_HOUR: float = 10.0
const COWED_HOURS: float = 24.0

## Conditions a promise can be about (NPCMorale ids) and how to phrase it.
const PROMISE_TEXT: Dictionary = {
	"light": "fix the lights", "power": "get the power running", "water": "clean up the water",
	"food": "get better food", "rest": "find me a proper bed", "space": "sort this place out",
	"safety": "keep us safe", "company": "make this place less lonely",
}

var fear: float = 0.0                      ## 0..100 toward the player (threats, violence)
var pressure: float = 0.0                  ## 0..100 work drive from the player (see header)
var cowed_until: float = -1.0
var last_refusal: String = ""
var _pushes_today: int = 0
var _orders_day: int = -1
var _orders_today: int = 0
var _bad_orders: int = 0
var _effort_today: int = 0                 ## player work seen today (softens blame)
var _last_worked_seen: float = -100.0
var _last_hoard: float = -100.0
var _last_bed_intrusion: float = -100.0
var _talk_last: Dictionary = {}            ## choice id -> NPCClock hours
var promise: Dictionary = {}               ## {condition, text, deadline}
var _blame_day: int = -1

var _npc: NPC = null

func setup(npc: NPC) -> void:
	_npc = npc

# ─── Work drive, compliance ────────────────────────────────────────────────
func drive() -> float:
	return clampf(pressure / 100.0, 0.0, 1.0)

func is_cowed() -> bool:
	return NPCClock.now() < cowed_until

## 0 = Lazy .. 1 = Hard Worker (smoothed Work Ethic).
func ethic() -> float:
	if _npc == null:
		return 0.5
	return smoothstep(0.1, 0.7, _npc._trait("work_ethic"))

func is_lazy() -> bool:
	return _npc._trait("work_ethic") < 0.35

## Adds work drive. Firm/cruel pushes build tolerance within a day
## (diminishing returns); kind motivation doesn't, and isn't dulled by it.
func _push(amount: float, why: String, harsh: bool = true) -> float:
	_roll_day()
	var gained: float = amount / (1.0 + 0.5 * float(_pushes_today)) if harsh else amount
	if harsh:
		_pushes_today += 1
	pressure = minf(100.0, pressure + gained)
	if gained >= 5.0:
		_npc.log_event("drive", "Work drive +%d (%s)" % [int(round(gained)), why])
	return gained

## Chance this resident accepts a work order right now.
func order_acceptance() -> float:
	var p: float = lerpf(0.3, 1.0, smoothstep(0.1, 0.55, _npc._trait("work_ethic")))
	p += drive() * 1.0 + maxf(0.0, _npc.get_relationship("player")) / 100.0 * 0.3 + fear / 100.0 * 0.6
	return clampf(p, 0.05, 1.0)

# ─── Leadership ─────────────────────────────────────────────────────────────
## The player issued an order from the resident panel. Returns false when
## a (lazy) resident refuses a work order — see order_acceptance().
func on_player_command(activity: NPCActivity) -> bool:
	_roll_day()
	last_refusal = ""
	var is_work: bool = not (activity is CommandRestActivity or activity is EatActivity or activity is DrinkActivity)
	if is_work and randf() > order_acceptance():
		## Nagging works a little (each refusal adds a bit of pressure, up to
		## a modest ceiling) — it's no substitute for actually getting firm.
		if pressure < 12.0:
			pressure = minf(12.0, pressure + 3.0)
		last_refusal = NPCDialogue.bark_line("refuse_work")
		_npc.bonds.relate("player", -0.4, "kept nagging me to work")
		_npc.log_event("drive", "Refused your work order")
		return false
	_orders_today += 1
	var bonds: NPCBonds = _npc.bonds
	if activity is CommandRestActivity:
		if _npc.energy < 30.0:
			bonds.relate("player", 2.5, "told me to get some rest when I was worn out")
		return true
	if activity is EatActivity or activity is DrinkActivity:
		return true   ## looking after them is never an imposition
	var state: String = ""
	if _npc.energy < 20.0:
		state = "exhausted"
	elif _npc.hunger < 20.0:
		state = "starving"
	elif _npc.thirst < 20.0:
		state = "parched"
	if state != "":
		_bad_orders += 1
		var memorable: bool = _bad_orders >= 3
		bonds.relate("player", -3.0, "ordered me to work while I was %s" % state,
			"You work us into the ground" if memorable else "", memorable)
		if memorable:
			_bad_orders = 0
	elif _orders_today > ORDERS_TOO_MANY:
		bonds.relate("player", -1.0, "keep ordering me around")
	return true

## The player finished a timed job (refuel, repair, farm...) somewhere.
func on_player_worked(pos: Vector3) -> void:
	_roll_day()
	var player: Node3D = _npc.get_tree().get_first_node_in_group("player") as Node3D
	if player == null or _npc.global_position.distance_to(pos) > WORKED_ALONGSIDE_RANGE or not _npc._can_see(player):
		return
	_effort_today += 1
	var now: float = NPCClock.now()
	if now - _last_worked_seen < WORKED_ALONGSIDE_GAP_HOURS:
		return
	_last_worked_seen = now
	_npc.bonds.relate("player", 0.6, "pitched in with the work")

## Someone else got fed by the player right in front of this hungry resident.
func on_saw_player_feed(other: NPC) -> void:
	if other == _npc or (_npc.hunger >= 35.0 and _npc.thirst >= 35.0):
		return
	if _npc.global_position.distance_to(other.global_position) > 8.0 or not _npc._can_see(other):
		return
	_npc.bonds.relate("player", -2.0, "fed %s but not me" % other.npc_name)

func tick(_h: float) -> void:
	_roll_day()
	var now: float = NPCClock.now()
	var player: Node3D = _npc.get_tree().get_first_node_in_group("player") as Node3D
	## Hoarding: going hungry while the player walks around with food.
	if player != null and _npc.hunger < 20.0 and now - _last_hoard > HOARD_GAP_HOURS \
			and _npc.global_position.distance_to(player.global_position) < 7.0 and _player_has_food():
		_last_hoard = now
		_npc.bonds.relate("player", -4.0, "had food on you while I went hungry")
	## Sleeping in their bed.
	var bed: Node = _npc.home_bed
	if bed != null and is_instance_valid(bed) and bool(bed.get("_player_sleeping")) \
			and now - _last_bed_intrusion > 12.0:
		_last_bed_intrusion = now
		_npc.bonds.relate("player", -2.0, "slept in my bed")
	fear = maxf(0.0, fear - 1.5 * _h)   ## fear fades (~3 game days from full)
	pressure = maxf(0.0, pressure - PRESSURE_DECAY_PER_HOUR * _h)
	_npc.thoughts.set_condition("under_pressure", drive() >= 0.3, _npc.thought_weight(-1.0))
	_npc.thoughts.set_condition("cowed", is_cowed(), _npc.thought_weight(-1.0))
	_tick_promise(now)

## Once a game day: blame the leader for sustained bad living conditions,
## unless they've visibly been working on it.
func _daily_blame() -> void:
	var m: NPCMorale = _npc.morale_sys
	var worst: String = ""
	var bad: float = 0.0
	for id: String in ["light", "power", "water", "food", "space"]:
		var c: float = m.contribution(id)
		if c < 0.0:
			bad += c
			if worst == "" or c < m.contribution(worst):
				worst = id
	if bad > BLAME_THRESHOLD:
		return
	var amount: float = clampf(-bad / 10.0, 1.0, 3.0) - 0.5 * float(_effort_today)
	if amount <= 0.2:
		_npc.log_event("bond", "Things are rough, but at least you're trying to fix them")
		return
	_npc.bonds.relate("player", -amount, "let us live like this (%s)" % m.reason_text(worst).to_lower())

func _roll_day() -> void:
	var day: int = int(floor(NPCClock.now() / 24.0))
	if _orders_day < 0:
		_orders_day = day
		_blame_day = day
	if day != _orders_day:
		_orders_day = day
		_orders_today = 0
		_pushes_today = 0
		if _blame_day != day:
			_blame_day = day
			_daily_blame()
		_effort_today = 0

func _player_has_food() -> bool:
	var player: Node = _npc.get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_held_item"):
		var held: Node = player.get_held_item()
		if held != null and is_instance_valid(held) and NPCItemUser.is_edible(held):
			return true
	var inv: Node = _npc.get_tree().get_first_node_in_group("inventory_manager")
	if inv != null and "slots" in inv:
		for it in inv.slots:
			if it != null and is_instance_valid(it) and NPCItemUser.is_edible(it):
				return true
	return false

# ─── Talk choices ──────────────────────────────────────────────────────────
## Is this choice available now? ("" = yes, otherwise why not).
func talk_unavailable_reason(choice: String) -> String:
	if _npc.brain != null and _npc.brain.is_sleeping():
		return "asleep"
	if _npc.crash != null and _npc.crash.active():
		return "crashing out"
	var last: float = float(_talk_last.get(choice, -1000.0))
	var tone: String = "kind"
	for c: Dictionary in TALK_CHOICES:
		if c["id"] == choice:
			tone = String(c["tone"])
	if NPCClock.now() - last < float(TALK_COOLDOWN_BY_TONE.get(tone, TALK_COOLDOWN_HOURS)):
		return "not again so soon"
	return ""

## Performs a talk choice. Returns {"line": reply, "delta": applied}.
func talk(choice: String) -> Dictionary:
	if talk_unavailable_reason(choice) != "":
		return {"line": "", "delta": 0.0}
	_talk_last[choice] = NPCClock.now()
	var bonds: NPCBonds = _npc.bonds
	var mood: float = _npc.mood
	var low: bool = mood < 40.0
	var d: float = 0.0
	var outcome: String = choice
	match choice:
		"check_in":
			d = bonds.relate("player", 4.0 if low else 1.5, "checked in on me when I was struggling" if low else "checked in on me")
			outcome = "check_in_low" if low else "check_in"
			_npc._last_social_time = NPCClock.now()
		"encourage":
			var lands: bool = randf() < clampf(0.45 + _npc._trait("optimism") * 0.4 + (0.2 if low else 0.0), 0.1, 0.9)
			d = bonds.relate("player", 2.5 if lands else 0.5, "cheered me up" if lands else "tried to cheer me up")
			if lands:
				_npc.add_thought("encouraged")
			## Kindness motivates people who already want to work; the Lazy
			## just like you a bit more.
			_push(lerpf(3.0, 25.0, ethic()) * (1.0 if lands else 0.5), "you encouraged me", false)
			outcome = "encourage_good" if lands else "encourage_flat"
			if is_lazy():
				outcome = "encourage_lazy"
		"joke":
			var p: float = 0.3 + _npc._trait("sociability") * 0.45 + (mood - 50.0) / 200.0 - (0.2 if _npc.has_irritable_trait() else 0.0)
			var lands: bool = randf() < clampf(p, 0.1, 0.9)
			d = bonds.relate("player", 2.5 if lands else -1.5, "made me laugh" if lands else "joked at the worst time")
			if lands:
				_npc.add_thought("laughed")
			outcome = "joke_good" if lands else "joke_bad"
		"vent":
			var hard: bool = _npc.morale < 50.0
			d = bonds.relate("player", 2.0 if hard else 0.5, "get how hard it is down here" if hard else "complained with me about the bunker")
			outcome = "vent_hard" if hard else "vent"
		"firm":
			## Getting on someone's case: lazy people expect it; hard workers resent it.
			d = bonds.relate("player", lerpf(-1.5, -3.5, ethic()), "got on my case about work")
			_push(35.0, "you got firm with me")
			outcome = "firm_lazy" if is_lazy() else "firm_worker"
			_get_moving()
		"insult":
			d = bonds.relate("player", -randf_range(6.0, 9.0), "insulted me", "You insulted me to my face", true)
			_npc.add_thought("insulted")
			NPCBonds.witnessed(_npc.get_tree(), "player", _npc, -3.0, "insulted %s" % _npc.npc_name)
			cowed_until = NPCClock.now() + COWED_HOURS
			_npc.irritability = minf(_npc.irritability, 30.0)
			_push(20.0, "you put me in my place")
			_npc.log_event("drive", "Put in their place — won't act out for a while")
		"threaten":
			d = bonds.relate("player", -10.0, "threatened me", "You threatened me", true)
			fear = minf(100.0, fear + 35.0)
			_npc.add_thought("threatened")
			NPCBonds.witnessed(_npc.get_tree(), "player", _npc, -5.0, "threatened %s" % _npc.npc_name)
			_push(65.0, "you threatened me")
			_get_moving()
	return {"line": NPCDialogue.talk_reply(_npc, outcome), "delta": d}

## Pressure works NOW: someone idling drops it and re-thinks this frame.
func _get_moving() -> void:
	var b: NPCBrain = _npc.brain
	if b == null or _npc.crash.active():
		return
	var cur: NPCActivity = b.current_activity()
	if cur == null or not (cur.is_work() or cur.is_need()):
		b.stop_current()

# ─── Promises ───────────────────────────────────────────────────────────────
## What the player could promise to fix: the condition weighing on them most.
func promise_offer() -> Dictionary:
	if not promise.is_empty():
		return {}
	var worst: String = ""
	for r: Dictionary in _npc.morale_sys.get_reasons():
		if float(r["points"]) < -2.0 and PROMISE_TEXT.has(String(r["id"])):
			worst = String(r["id"])
			break
	if worst == "":
		return {}
	return {"condition": worst, "text": "I'll %s" % PROMISE_TEXT[worst]}

func make_promise() -> String:
	var offer: Dictionary = promise_offer()
	if offer.is_empty():
		return ""
	promise = {"condition": offer["condition"], "text": PROMISE_TEXT[offer["condition"]],
		"deadline": NPCClock.now() + PROMISE_HOURS}
	_npc.log_event("bond", "You promised to %s (within 2 days)" % promise["text"])
	return NPCDialogue.talk_reply(_npc, "promise")

func _tick_promise(now: float) -> void:
	if promise.is_empty():
		return
	var v: float = float(_npc.morale_sys.values.get(String(promise["condition"]), 0.0))
	if v > -0.1:
		_npc.bonds.relate("player", 7.0, "kept your promise to %s" % promise["text"],
			"You kept your promise to %s" % promise["text"], true)
		promise = {}
	elif now >= float(promise["deadline"]):
		_npc.bonds.relate("player", -9.0, "promised to %s and didn't" % promise["text"],
			"You promised to %s and never did" % promise["text"], true)
		promise = {}

# ─── Taking sides ───────────────────────────────────────────────────────────
## Residents this one is feuding with (for "Take their side against …").
func feuds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if other != _npc and other is NPC and _npc.get_relationship(other.npc_id) <= -20.0:
			out.append({"id": other.npc_id, "name": other.npc_name})
	return out

func take_side_against(other_id: String) -> String:
	var other: NPC = null
	for n: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if n is NPC and n.npc_id == other_id:
			other = n
	if other == null or talk_unavailable_reason("side_" + other_id) != "":
		return ""
	_talk_last["side_" + other_id] = NPCClock.now()
	_npc.bonds.relate("player", 4.0, "took my side against %s" % other.npc_name,
		"You stood up for me against %s" % other.npc_name, true)
	other.bonds.relate("player", -4.0, "sided with %s against me" % _npc.npc_name,
		"You sided with %s against me" % _npc.npc_name, true)
	return NPCDialogue.talk_reply(_npc, "side")

# ─── Save / load ────────────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"fear": fear, "pressure": pressure, "cowed": cowed_until, "pushes": _pushes_today, "orders_day": _orders_day, "orders": _orders_today, "bad_orders": _bad_orders,
		"effort": _effort_today, "talk": _talk_last.duplicate(), "promise": promise.duplicate(),
		"blame_day": _blame_day, "hoard": _last_hoard, "bed": _last_bed_intrusion}

func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	fear = float(d.get("fear", 0.0))
	pressure = float(d.get("pressure", 0.0))
	cowed_until = float(d.get("cowed", -1.0))
	_pushes_today = int(d.get("pushes", 0))
	_orders_day = int(d.get("orders_day", -1))
	_orders_today = int(d.get("orders", 0))
	_bad_orders = int(d.get("bad_orders", 0))
	_effort_today = int(d.get("effort", 0))
	_talk_last = (d.get("talk", {}) as Dictionary).duplicate()
	promise = (d.get("promise", {}) as Dictionary).duplicate()
	_blame_day = int(d.get("blame_day", -1))
	_last_hoard = float(d.get("hoard", -100.0))
	_last_bed_intrusion = float(d.get("bed", -100.0))
