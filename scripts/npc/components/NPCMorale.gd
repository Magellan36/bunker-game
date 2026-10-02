extends RefCounted
class_name NPCMorale
## NPCMorale.gd (Sep 2026) — the slow, long-term state of mind that decides
## whether a resident holds together (plans/NPC_MORALE_CRASHOUT_PLAN.md).
##
## Two layers:
##   MORALE   (this file) — moves by fractions of a point per game hour and
##            follows SUSTAINED bunker conditions: light, power, water
##            quality, food quality, rest, space, safety, company. A bad
##            day dents it; a bad week breaks it. Crash-outs read morale.
##   FEELINGS (NPCThoughts) — today's moodlets (a hot meal, a fight, hunger).
##            They colour the displayed mood right away, and — averaged over
##            a day — nudge morale a little: many cold-can days matter, one
##            doesn't.
## Displayed mood = morale + a capped share of feelings (NPC._tick_mood).
##
## Every condition is a rolling average in [-1, 1] (0 = acceptable), so a
## single blackout barely registers while days of darkness weigh heavily.
## "Reliability" (Oct 2026, Brannon) is the exception that catches what the
## averages miss: supplies that keep cutting out. Each lapse (the power
## going down, going hungry, needing a drink, a bad drink after good ones)
## counts, and the count fades over a couple of days. One lapse is nothing;
## a bunker where something fails every few hours wears people down even
## when, on average, they get what they need. It never touches how they
## feel about the player (that's NPCSocial's neglect: sustained, not flaky).
## Traits set sensitivity: Neurotic residents feel bad conditions more,
## Level-Headed ones less, Optimists enjoy good ones more, Open (sociable)
## ones care more about company.
##
## Transparency: get_reasons() explains the current target in plain words,
## and condition/band changes plus a daily summary go to the activity log.

const BASELINE: float = 62.0            ## morale target in an "acceptable" bunker
const RATE_DOWN: float = 0.6            ## points per game hour (before traits) — a bad week breaks people, a bad day doesn't
const RATE_UP: float = 0.6
const FEELINGS_SHARE: float = 0.35      ## how much the day-average of feelings pulls morale
const FEELINGS_TAU: float = 24.0
const CONTAGION_PER_HOUR: float = 0.02
const EVENT_ALPHA: float = 0.35         ## weight of one meal/drink/night in its running score

## id -> {label, weight (morale points at ±1), tau (game hours to adapt)}
const CONDITIONS: Dictionary = {
	"light":   {"label": "Light",   "weight": 12.0, "tau": 20.0},
	"power":   {"label": "Power",   "weight": 6.0,  "tau": 20.0},
	"water":   {"label": "Water",   "weight": 9.0,  "tau": 30.0},
	"food":    {"label": "Food",    "weight": 12.0, "tau": 30.0},
	"rest":    {"label": "Rest",    "weight": 10.0, "tau": 30.0},
	"space":   {"label": "Space",   "weight": 8.0,  "tau": 36.0},
	"safety":  {"label": "Safety",  "weight": 10.0, "tau": 36.0},
	"company": {"label": "Company", "weight": 9.0,  "tau": 36.0},
	"stability": {"label": "Reliability", "weight": 22.0, "tau": 4.0},
}

## Lapses (see header): kind -> share of "stability" when saturated. A
## kind saturates at LAPSE_SATURATE lapses in the fading window (≈ three a
## day, kept up).
const LAPSE_SHARE: Dictionary = {"power": 0.35, "food": 0.35, "water": 0.3}
const LAPSE_SATURATE: float = 6.0
const LAPSE_TAU: float = 48.0               ## game hours for a lapse to fade
const NEED_LAPSE_BELOW: float = 30.0        ## hunger/thirst under this = going without
const NEED_LAPSE_CLEAR: float = 45.0        ## …and back over this before the next one counts

## Plain-language reason per condition and band (for the panel and log).
const REASONS: Dictionary = {
	"light":   {"great": "The lights keep the dark away", "bad": "It's too dark down here", "terrible": "Living in the dark"},
	"power":   {"great": "The power has been steady", "bad": "The power keeps failing", "terrible": "No power for days"},
	"water":   {"great": "The water is clean", "bad": "The water tastes off", "terrible": "Drinking filthy water"},
	"food":    {"great": "Eating proper meals", "bad": "Nothing but cold cans", "terrible": "Going hungry"},
	"rest":    {"great": "Sleeping well", "bad": "Sleeping badly", "terrible": "Barely sleeping"},
	"space":   {"great": "The bunker feels livable", "bad": "Cramped and messy", "terrible": "No bed, no room, no order"},
	"safety":  {"great": "Feeling safe", "bad": "Feeling unsafe", "terrible": "Scared for my life"},
	"company": {"great": "Good people around", "bad": "Lonely down here", "terrible": "Surrounded by people I can't stand"},
	"stability": {"great": "Everything's been working", "bad": "Things keep breaking down", "terrible": "Nothing down here works for long"},
}
## The reliability reason names what keeps failing most (reason_text).
const LAPSE_REASONS: Dictionary = {
	"power": {"bad": "The power keeps cutting out", "terrible": "The power never stays on"},
	"food": {"bad": "Never sure when we'll eat next", "terrible": "Meals come and go, mostly go"},
	"water": {"bad": "The water's never the same twice", "terrible": "Never sure there'll be water to drink"},
}

## Morale bands (low → high) — crossings are logged.
const BANDS: Array[Dictionary] = [
	{"min": 0.0,  "name": "Breaking"},
	{"min": 25.0, "name": "Strained"},
	{"min": 35.0, "name": "Worn down"},
	{"min": 50.0, "name": "Getting by"},
	{"min": 70.0, "name": "Content"},
]
const CRASH_RISK_BELOW: float = 25.0

var morale: float = 65.0
var values: Dictionary = {}         ## condition -> rolling value [-1, 1]
var _event_scores: Dictionary = {"water": 0.0, "food": 0.0, "rest": 0.0}
var _feelings_avg: float = 0.0
var _shock: float = 0.0              ## recent trauma (a death, an attack) feeding "safety"
var _cond_band: Dictionary = {}      ## condition -> last logged band
var _band: String = ""
var _day_start: float = -1.0
var _day_index: int = -1
var _history: Array[float] = []      ## morale at the last few game hours (trend)
var _hour_accum: float = 0.0
var _lapses: Dictionary = {"power": 0.0, "food": 0.0, "water": 0.0}
var _power_ok: bool = true
var _hungry: bool = false
var _thirsty: bool = false
var _last_drink_ok: bool = true

var _npc: NPC = null
## Tests only: condition id -> fixed sample, used instead of the live world.
var sample_override: Dictionary = {}

var _loaded: bool = false

func setup(npc: NPC) -> void:
	_npc = npc
	for id: String in CONDITIONS.keys():
		values[id] = values.get(id, 0.0)
	if not _loaded:
		morale = randf_range(62.0, 72.0)

# ─── Events (called by the NPC when things happen) ─────────────────────────
func note_meal(kind: String) -> void:
	var s: float = {"ate_hot_meal": 0.8, "ate_fresh": 0.6, "ate_cold_can": -0.25}.get(kind, 0.0)
	_event_scores["food"] = lerpf(float(_event_scores["food"]), s, EVENT_ALPHA)

func note_drink(quality: float) -> void:
	_event_scores["water"] = lerpf(float(_event_scores["water"]), clampf((quality - 70.0) / 30.0, -1.0, 0.5), EVENT_ALPHA)
	## A bad drink after good ones is a lapse (steady bad water is the
	## "water" condition's job, not this).
	var ok: bool = quality >= 70.0
	if not ok and _last_drink_ok:
		note_lapse("water")
	_last_drink_ok = ok

## Something they rely on just failed (see header). Public for tests.
func note_lapse(kind: String) -> void:
	_lapses[kind] = float(_lapses.get(kind, 0.0)) + 1.0

func note_sleep(kind: String) -> void:
	var s: float = {"slept_in_bed": 0.5, "slept_in_chair": -0.4, "slept_on_floor": -0.8, "collapsed": -1.0}.get(kind, 0.0)
	_event_scores["rest"] = lerpf(float(_event_scores["rest"]), s, EVENT_ALPHA)

## A frightening event (someone died, an attack). 1.0 = worst.
func note_shock(amount: float) -> void:
	_shock = clampf(_shock + amount, 0.0, 1.5)

# ─── Tick ───────────────────────────────────────────────────────────────────
func tick(h: float, feelings: float) -> void:
	if h <= 0.0:
		return
	var samples: Dictionary = _sample()
	for id: String in CONDITIONS.keys():
		if not samples.has(id):
			continue   ## not sampled right now (e.g. light while asleep) — hold
		var tau: float = float(CONDITIONS[id]["tau"])
		values[id] = lerpf(float(values[id]), float(samples[id]), 1.0 - exp(-h / tau))
	_shock = maxf(0.0, _shock - h / 48.0)
	for k: String in _lapses.keys():
		_lapses[k] = float(_lapses[k]) * exp(-h / LAPSE_TAU)
	_feelings_avg = lerpf(_feelings_avg, feelings, 1.0 - exp(-h / FEELINGS_TAU))

	var target: float = get_target()
	var rate: float = RATE_DOWN * _down_mult() if target < morale else RATE_UP * _up_mult()
	morale = move_toward(morale, target, rate * h)
	morale = clampf(morale + (_npc.contagion_target() - morale) * CONTAGION_PER_HOUR * _npc.get_contagion_sociability_mult() * h, 0.0, 100.0)

	_hour_accum += h
	if _hour_accum >= 1.0:
		_hour_accum = 0.0
		_history.append(morale)
		if _history.size() > 12:
			_history.pop_front()
	_log_changes()

func get_target() -> float:
	var t: float = BASELINE + _feelings_avg * FEELINGS_SHARE
	for id: String in CONDITIONS.keys():
		t += contribution(id)
	return clampf(t, 0.0, 100.0)

## Morale points this condition currently adds (+) or costs (−).
func contribution(id: String) -> float:
	var v: float = float(values.get(id, 0.0))
	var w: float = float(CONDITIONS[id]["weight"])
	if id == "company":
		w *= lerpf(0.6, 1.4, _npc._trait("sociability"))
	return w * (v * 0.5 * _pos_mult() if v > 0.0 else v * _neg_mult())

# ─── Condition sampling (all [-1, 1], 0 = acceptable) ──────────────────────
func _sample() -> Dictionary:
	var out: Dictionary = {}
	var asleep: bool = _npc.brain != null and _npc.brain.is_sleeping()
	if not asleep:
		out["light"] = _sample_light()
	out["power"] = float(sample_override.get("power", _sample_power()))
	_track_lapses(float(out["power"]))
	## Event-driven conditions, pulled down while the need goes unmet.
	out["food"] = _with_need(float(_event_scores["food"]), _npc.hunger)
	out["water"] = _with_need(float(_event_scores["water"]), _npc.thirst)
	out["rest"] = _with_need(float(_event_scores["rest"]), _npc.energy)
	out["space"] = _sample_space()
	out["safety"] = _sample_safety()
	out["company"] = _sample_company()
	out["stability"] = -instability()
	for k: String in sample_override.keys():
		out[k] = float(sample_override[k])
	return out

## 0 (nothing failing) .. 1 (everything failing several times a day).
func instability() -> float:
	var s: float = 0.0
	for k: String in LAPSE_SHARE.keys():
		s += float(LAPSE_SHARE[k]) * minf(1.0, float(_lapses.get(k, 0.0)) / LAPSE_SATURATE)
	return clampf(s, 0.0, 1.0)

## Lapses seen in the live world: the grid dropping out, and going hungry
## or thirsty (with a margin, so hovering at the line counts once).
func _track_lapses(power_sample: float) -> void:
	var power_ok: bool = power_sample >= 0.0
	if _power_ok and not power_ok:
		note_lapse("power")
	_power_ok = power_ok
	if not _hungry and _npc.hunger < NEED_LAPSE_BELOW:
		_hungry = true
		note_lapse("food")
	elif _hungry and _npc.hunger > NEED_LAPSE_CLEAR:
		_hungry = false
	if not _thirsty and _npc.thirst < NEED_LAPSE_BELOW:
		_thirsty = true
		note_lapse("water")
	elif _thirsty and _npc.thirst > NEED_LAPSE_CLEAR:
		_thirsty = false

static func _with_need(score: float, need: float) -> float:
	if need >= 30.0:
		return score
	return lerpf(score, -1.0, (30.0 - need) / 30.0)

func _sample_light() -> float:
	var best: float = -1.0   ## dark
	var tree: SceneTree = _npc.get_tree()
	for l: Node in tree.get_nodes_in_group("wall_lights"):
		if not (l is Node3D) or not bool(l.get("_is_powered")):
			continue
		var d: float = (l as Node3D).global_position.distance_to(_npc.global_position)
		if d > 9.0 or not _npc._can_see(l as Node3D):
			continue
		best = maxf(best, -0.3 if bool(l.get("_is_shed")) else 0.5)
		if best >= 0.5:
			break
	return best

func _sample_power() -> float:
	var pm: Node = _npc.get_tree().get_first_node_in_group("power_manager")
	if pm == null or not pm.has_method("get_grid_state_string"):
		return 0.0
	match String(pm.get_grid_state_string()):
		"ONLINE": return 0.3
		"OVERLOADED": return 0.0
		"BROWNOUT": return -0.6
		"TRIPPED": return -0.8
	return -1.0   ## OFFLINE — no generation at all

func _sample_space() -> float:
	var tree: SceneTree = _npc.get_tree()
	var residents: int = maxi(1, tree.get_nodes_in_group("npc").size())
	var beds: int = tree.get_nodes_in_group("bed").size()
	var s: float = 0.3 if beds >= residents else -0.8 * (1.0 - float(beds) / float(residents))
	var clutter: int = JobBoard.get_total_clutter_count()
	if clutter >= 25:
		s -= 0.6
	elif clutter >= 12:
		s -= 0.3
	return clampf(s, -1.0, 0.5)

## Sep 2026 (Brannon): real danger inside the bunker makes EVERYONE feel
## unsafe — a body lying anywhere (worse in sight), a recent weapon fight
## (fading over a game day), living alongside someone who attacked them —
## on top of pain, low health and fresh shocks.
func _sample_safety() -> float:
	var s: float = 0.2
	if _npc.thoughts != null and _npc.thoughts.has("in_pain"):
		s = -0.5
	if _npc.health < 50.0:
		s = minf(s, -0.8)
	var bodies: Array[Node3D] = NPCCombat.bodies(_npc.get_tree())
	if not bodies.is_empty():
		s = minf(s, -0.6)
		for b: Node3D in bodies:
			if _npc.global_position.distance_to(b.global_position) < 10.0 and _npc._can_see(b):
				s = minf(s, -0.9)
				break
	s -= 0.9 * NPCCombat.weapon_fight_fear()
	if _npc.combat.lives_with_attacker():
		s = minf(s, -0.4)
	return clampf(s - _shock, -1.0, 0.5)

func _sample_company() -> float:
	if _npc.thoughts != null and _npc.thoughts.has("lonely"):
		return -0.7
	var total: float = 0.0
	var n: int = 0
	for other: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if other != _npc and other is NPC:
			total += _npc.get_relationship(other.npc_id)
			n += 1
	total += _npc.get_relationship("player")
	n += 1
	return clampf(total / float(n) / 40.0, -1.0, 0.6)

# ─── Traits ─────────────────────────────────────────────────────────────────
func _neg_mult() -> float:
	return lerpf(0.85, 1.25, _npc._trait("neuroticism")) * lerpf(1.15, 0.85, _npc._trait("resilience"))

func _pos_mult() -> float:
	return lerpf(0.8, 1.3, _npc._trait("optimism"))

func _down_mult() -> float:
	return lerpf(0.85, 1.2, _npc._trait("neuroticism")) * lerpf(1.1, 0.9, _npc._trait("resilience"))

func _up_mult() -> float:
	return lerpf(0.8, 1.3, _npc._trait("optimism"))

# ─── Explanations ───────────────────────────────────────────────────────────
static func band_of(value: float) -> String:
	var name: String = BANDS[0]["name"]
	for b: Dictionary in BANDS:
		if value >= float(b["min"]):
			name = b["name"]
	return name

func get_band() -> String:
	return band_of(morale)

static func _cond_band_of(v: float) -> String:
	if v >= 0.3:
		return "great"
	if v <= -0.65:
		return "terrible"
	if v <= -0.25:
		return "bad"
	return "ok"

func reason_text(id: String) -> String:
	var band: String = _cond_band_of(float(values.get(id, 0.0)))
	if id == "stability" and band in ["bad", "terrible"]:
		var worst: String = ""
		for k: String in LAPSE_SHARE.keys():
			if worst == "" or float(LAPSE_SHARE[k]) * float(_lapses[k]) > float(LAPSE_SHARE[worst]) * float(_lapses[worst]):
				worst = k
		return String(LAPSE_REASONS[worst][band])
	return String(REASONS[id].get(band, CONDITIONS[id]["label"]))

## [{id, text, points}] sorted by impact (largest first), non-trivial only.
func get_reasons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in CONDITIONS.keys():
		var p: float = contribution(id)
		if absf(p) >= 1.0 and _cond_band_of(float(values[id])) != "ok":
			out.append({"id": id, "text": reason_text(id), "points": p})
	if absf(_feelings_avg * FEELINGS_SHARE) >= 1.0:
		out.append({"id": "feelings", "text": "How the last day has felt", "points": _feelings_avg * FEELINGS_SHARE})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a["points"]) > absf(b["points"]))
	return out

## -1 falling, 0 steady, +1 rising (over the last few game hours).
func get_trend() -> int:
	if _history.size() < 3:
		return 0
	var d: float = morale - _history[0]
	return 1 if d > 1.0 else (-1 if d < -1.0 else 0)

func _log_changes() -> void:
	## Condition band changes ("It's too dark down here").
	for id: String in CONDITIONS.keys():
		var b: String = _cond_band_of(float(values[id]))
		var prev: String = String(_cond_band.get(id, "ok"))
		if b != prev:
			_cond_band[id] = b
			if b != "ok":
				_npc.log_event("morale", "%s (morale %+.0f)" % [reason_text(id), contribution(id)])
			elif prev in ["bad", "terrible"]:
				_npc.log_event("morale", "%s is no longer weighing on me" % String(CONDITIONS[id]["label"]))
	## Morale band crossings.
	var band: String = get_band()
	if _band == "":
		_band = band
	elif band != _band:
		var worse: bool = _band_index(band) < _band_index(_band)
		var why: Array[Dictionary] = get_reasons()
		var cause: String = ""
		if not why.is_empty():
			var top: Dictionary = why[0] if (worse == (float(why[0]["points"]) < 0.0)) else {}
			if not top.is_empty():
				cause = " — mostly: %s" % String(top["text"]).to_lower()
		_npc.log_event("morale", "Morale %s to \"%s\" (%d)%s" % ["fell" if worse else "rose", band, int(round(morale)), cause])
		_band = band
	## Daily summary.
	var day: int = int(floor(NPCClock.now() / 24.0))
	if _day_index < 0:
		_day_index = day
		_day_start = morale
	elif day != _day_index:
		var delta: float = morale - _day_start
		if absf(delta) >= 1.0:
			var parts: Array[String] = []
			for r: Dictionary in get_reasons().slice(0, 2):
				parts.append("%s %+.0f" % [String(r["text"]).to_lower(), float(r["points"])])
			_npc.log_event("morale", "Morale %s %d → %d over the day%s" % ["rose" if delta > 0.0 else "fell",
				int(round(_day_start)), int(round(morale)), (" (%s)" % ", ".join(parts)) if not parts.is_empty() else ""])
		_day_index = day
		_day_start = morale

static func _band_index(name: String) -> int:
	for i: int in BANDS.size():
		if BANDS[i]["name"] == name:
			return i
	return 0

# ─── Save / load ────────────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"morale": morale, "values": values.duplicate(), "events": _event_scores.duplicate(),
		"feel": _feelings_avg, "shock": _shock, "cond_band": _cond_band.duplicate(), "band": _band,
		"day": _day_index, "day_start": _day_start, "lapses": _lapses.duplicate(),
		"lapse_state": [_power_ok, _hungry, _thirsty, _last_drink_ok]}

func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	_loaded = true
	morale = float(d.get("morale", morale))
	var v: Dictionary = d.get("values", {})
	for id: String in CONDITIONS.keys():
		values[id] = float(v.get(id, values.get(id, 0.0)))
	var e: Dictionary = d.get("events", {})
	for k: String in _event_scores.keys():
		_event_scores[k] = float(e.get(k, _event_scores[k]))
	_feelings_avg = float(d.get("feel", 0.0))
	_shock = float(d.get("shock", 0.0))
	_cond_band = (d.get("cond_band", {}) as Dictionary).duplicate()
	_band = String(d.get("band", ""))
	_day_index = int(d.get("day", -1))
	_day_start = float(d.get("day_start", morale))
	var l: Dictionary = d.get("lapses", {})
	for k: String in _lapses.keys():
		_lapses[k] = float(l.get(k, 0.0))
	var st: Array = d.get("lapse_state", [])
	if st.size() == 4:
		_power_ok = bool(st[0])
		_hungry = bool(st[1])
		_thirsty = bool(st[2])
		_last_drink_ok = bool(st[3])
