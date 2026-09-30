extends RefCounted
class_name NPCCrashOut
## NPCCrashOut.gd (Sep 2026) — when morale breaks, a resident crashes out
## (plans/NPC_MORALE_CRASHOUT_PLAN.md). Like RimWorld's mental breaks it runs
## its course: it can't be talked down, and orders are refused meanwhile.
##
## Risk: only below NPCMorale.CRASH_RISK_BELOW (25), growing the deeper
## morale sinks; Neurotic residents break sooner, Level-Headed later. A
## badly run bunker produces its first crash-out after ~3-5 game days.
##
## What it looks like depends on RELATIONSHIPS:
##   HOSTILE    — they despise someone (the player or a resident, grudges
##                included): confront and rant at them, then lash out at
##                the bunker (shut the generator off, destroy food, throw
##                things). Residents who share the grudge and are close to
##                breaking may join in. Attacking comes with the combat system
##                (ATTACK hook below).
##   OVERDRIVE  — low morale but they like the player: a frantic work binge
##                (no breaks, jobs first, faster), then they burn out.
##   BREAKDOWN  — neither: they find somewhere alone, slump against a wall
##                and fall apart. Harmless, but one less pair of hands.
## Afterwards: catharsis (a morale lift), a memory, and witnesses react.

enum Mode { NONE, HOSTILE, OVERDRIVE, BREAKDOWN }

const HOSTILE_AT: float = -40.0            ## relationship (incl. half the grudge) that turns a break hostile
const OVERDRIVE_AT: float = 40.0           ## relationship with the player for overdrive
const COOLDOWN_HOURS: float = 36.0
const CATHARSIS: float = 14.0
const DURATION: Dictionary = {Mode.HOSTILE: [2.0, 4.0], Mode.OVERDRIVE: [6.0, 10.0], Mode.BREAKDOWN: [3.0, 6.0]}
const MODE_NAMES: Dictionary = {Mode.HOSTILE: "hostile", Mode.OVERDRIVE: "overdrive", Mode.BREAKDOWN: "breakdown"}

## Combat: an ESCALATED hostile crash-out attacks with a weapon or fists
## (CrashOutActivity ARM/ATTACK phases, NPCCombat). Off = rant and sabotage only.
static var attack_enabled: bool = true   ## Sep 2026: weapons exist (NPCCombat)

var mode: Mode = Mode.NONE
var target_id: String = ""                 ## hostile: who they're furious at
var ends_at: float = -1.0
var started_at: float = -1.0
var joined_by: String = ""                 ## hostile: set when joining someone else's crash-out
var count: int = 0
## Episode progress lives here (not in the activity) so an interrupted and
## re-entered episode continues instead of starting over.
var confronted: bool = false
var sabotaged: int = 0
var _cooldown_until: float = -1.0
var _warned_at: float = -100.0

var _npc: NPC = null

func setup(npc: NPC) -> void:
	_npc = npc

func active() -> bool:
	return mode != Mode.NONE

func mode_name() -> String:
	return String(MODE_NAMES.get(mode, ""))

## Chance per game DAY of breaking at the current MOOD (0 when not at risk).
## Mood, not the slow baseline alone: a starving, exhausted resident is
## closer to snapping, and feeding them pulls them back.
func daily_risk() -> float:
	var m: float = _npc.mood
	if m >= NPCMorale.CRASH_RISK_BELOW:
		return 0.0
	var depth: float = (NPCMorale.CRASH_RISK_BELOW - m) / NPCMorale.CRASH_RISK_BELOW
	var trait_mult: float = lerpf(0.75, 1.35, _npc._trait("neuroticism")) * lerpf(1.2, 0.7, _npc._trait("resilience"))
	return clampf((0.18 + 1.0 * depth) * trait_mult, 0.0, 2.0)

## Pure roll (no side effects) — used by tick() and the morale timeline test.
func roll(h: float) -> bool:
	if active() or NPCClock.now() < _cooldown_until:
		return false
	var p: float = 1.0 - exp(-daily_risk() * h / 24.0)
	return randf() < p

func tick(h: float) -> void:
	var now: float = NPCClock.now()
	if active():
		if now >= ends_at:
			finish()
		return
	## Warning signs before it happens: a strained resident says so now and then.
	if _npc.mood < 32.0 and now - _warned_at > 6.0 and randf() < 0.25 * h:
		_warned_at = now
		_npc.bark_event("strained")
	if _npc.brain != null and (_npc.brain.is_sleeping() or _npc.is_passed_out()):
		return
	if roll(h):
		begin(_choose_mode())

func _choose_mode() -> Mode:
	var worst: Dictionary = worst_person()
	if not worst.is_empty() and float(worst["score"]) <= HOSTILE_AT:
		if _npc.social.is_cowed():
			_npc.log_event("crash", "Too cowed to lash out — it all came out as tears instead")
			return Mode.BREAKDOWN   ## insulted into line: the anger is bottled up, for now
		target_id = String(worst["id"])
		return Mode.HOSTILE
	if _npc.get_relationship("player") >= OVERDRIVE_AT and randf() < 0.75:
		return Mode.OVERDRIVE
	return Mode.BREAKDOWN

## The person this resident resents most: relationship + half their grudge memories.
func worst_person() -> Dictionary:
	var best: Dictionary = {}
	var ids: Array = _npc.relationships.keys()
	if not ids.has("player"):
		ids.append("player")
	for id: Variant in ids:
		var sid: String = String(id)
		if sid != "player" and _find(sid) == null:
			continue   ## someone no longer here
		var score: float = _npc.get_relationship(sid) + _npc.bonds.grudge_against(sid) * 0.5
		if best.is_empty() or score < float(best["score"]):
			best = {"id": sid, "score": score}
	return best

func begin(m: Mode, ally_of: NPC = null) -> void:
	mode = m
	started_at = NPCClock.now()
	confronted = false
	sabotaged = 0
	var span: Array = DURATION[m]
	ends_at = started_at + randf_range(float(span[0]), float(span[1]))
	count += 1
	joined_by = ally_of.npc_name if ally_of != null else ""
	var who: String = _npc.bonds.display_name(target_id).to_lower() if target_id == "player" else _npc.bonds.display_name(target_id)
	var headline: String = ""
	match m:
		Mode.HOSTILE:
			headline = "Crashed out — furious at %s" % ("you" if target_id == "player" else who)
			if ally_of != null:
				headline += " (siding with %s)" % ally_of.npc_name
			_npc.bark_event("crash_hostile")
		Mode.OVERDRIVE:
			headline = "Crashed out — went into overdrive to hold the bunker together"
			_npc.bark_event("crash_overdrive")
		Mode.BREAKDOWN:
			headline = "Crashed out — broke down, can't take it anymore"
			_npc.bark_event("crash_breakdown")
	var cause: Array[Dictionary] = _npc.morale_sys.get_reasons()
	var why: String = (" Mostly: %s." % String(cause[0]["text"]).to_lower()) if not cause.is_empty() else ""
	_npc.log_event("crash", "%s.%s" % [headline, why])
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
		"%s is crashing out (%s)" % [_npc.npc_name, _short()])
	if _npc.brain != null:
		_npc.brain.stop_current()   ## the crash-out takes over on the next think
	if m == Mode.HOSTILE and ally_of == null:
		_rally_allies()

func _short() -> String:
	match mode:
		Mode.HOSTILE:
			return "furious at %s" % ("you" if target_id == "player" else _npc.bonds.display_name(target_id))
		Mode.OVERDRIVE:
			return "overdrive"
	return "breakdown"

## Others who share the grudge and are close to breaking themselves may join.
func _rally_allies() -> void:
	for other: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if other == _npc or not (other is NPC) or other.crash.active():
			continue
		if other.mood >= 40.0 or other.get_relationship(target_id) > HOSTILE_AT * 0.75:
			continue
		if other.get_relationship(_npc.npc_id) < 20.0 or other.global_position.distance_to(_npc.global_position) > 15.0:
			continue
		if randf() < 0.5:
			other.crash.target_id = target_id
			other.crash.begin(Mode.HOSTILE, _npc)

func finish() -> void:
	var was: Mode = mode
	mode = Mode.NONE
	_cooldown_until = NPCClock.now() + COOLDOWN_HOURS
	## Catharsis — it's out of their system, for now.
	_npc.morale_sys.morale = minf(100.0, _npc.morale_sys.morale + CATHARSIS)
	match was:
		Mode.OVERDRIVE:
			_npc.bark(NPCDialogue.bark_line("calmed_overdrive"), true)
			_npc.energy = maxf(0.0, _npc.energy - 35.0)
			_npc.add_thought("burned_out")
			_npc.log_event("crash", "Came down from the overdrive — completely burned out")
		Mode.HOSTILE:
			_npc.bark(NPCDialogue.bark_line("calmed_hostile"), true)
			_npc.add_thought("vented_rage")
			_npc.log_event("crash", "Calmed down after lashing out")
		Mode.BREAKDOWN:
			_npc.bark(NPCDialogue.bark_line("calmed_breakdown"), true)
			_npc.add_thought("cried_it_out")
			_npc.log_event("crash", "Pulled themselves back together")
	_npc.bonds._remember("self", "Lost it on day %d" % (int(floor(started_at / 24.0)) + 1), -1.0)
	## Witnesses: fear/anger at someone who lashed out, sympathy for a breakdown.
	for w: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if w == _npc or not (w is NPC) or w.global_position.distance_to(_npc.global_position) > 12.0:
			continue
		if was == Mode.HOSTILE:
			w.bonds.relate(_npc.npc_id, -4.0, "lost it and wrecked things")
			w.morale_sys.note_shock(0.25)
		elif was == Mode.BREAKDOWN and w.get_relationship(_npc.npc_id) > 10.0:
			w.bonds.relate(_npc.npc_id, 1.5, "fell apart, and I felt for them")
	target_id = ""
	joined_by = ""

func blocks_commands() -> bool:
	return active()

func _find(id: String) -> NPC:
	for n: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if n is NPC and n.npc_id == id:
			return n
	return null

func target_node() -> Node3D:
	if target_id == "player":
		return _npc.get_tree().get_first_node_in_group("player") as Node3D
	return _find(target_id)

# ─── Save / load ────────────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"mode": int(mode), "target": target_id, "ends": ends_at, "start": started_at,
		"count": count, "cool": _cooldown_until, "joined": joined_by, "confronted": confronted, "sabotaged": sabotaged}

func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	mode = int(d.get("mode", 0)) as Mode
	target_id = String(d.get("target", ""))
	ends_at = float(d.get("ends", -1.0))
	started_at = float(d.get("start", -1.0))
	count = int(d.get("count", 0))
	_cooldown_until = float(d.get("cool", -1.0))
	joined_by = String(d.get("joined", ""))
	confronted = bool(d.get("confronted", false))
	sabotaged = int(d.get("sabotaged", 0))
