extends CharacterBody3D
class_name NPC
## NPC.gd — a bunker resident.
##
## Composition (Sep 2026 structure):
##   brain      NPCBrain           utility-AI activity selection (NPCBrain.gd)
##   medical    NPCMedical         conditions / symptoms (Node child)
##   thoughts   NPCThoughts        event-driven mood modifiers
##   stuck      NPCStuckRecovery   travel-stall detection & safe recovery
##   job_state  NPCJobState        cross-session "this didn't work" memory
## This file owns the resident's state (needs, personality, mood,
## relationships...), locomotion, and the small public API activities and
## UI talk to. Long-form rationale for each system lives in
## docs/systems/npc/README.md.
##
## Collision: deliberately on Godot's DEFAULT layer/mask (1/1), like
## Player.gd. All placed solids use collision_layer = 5 (includes bit 1).
##
## Locomotion: the NavigationAgent3D provides the next XZ waypoint and
## avoidance; _physics_process steers toward it and move_and_slide() +
## gravity own the actual motion. Physics collision stays the hard
## guarantee — if the navmesh is momentarily stale the NPC bumps and
## NPCStuckRecovery re-paths instead of clipping.

# ─── Tunables ─────────────────────────────────────────────────────────────
@export var move_speed: float = 2.2
## Running (fleeing, chasing, rushing to help): 2.2 × 1.9 ≈ 4.2 m/s, the
## run clip's own pace, so the gait blend reads as a full run, not a jog.
const RUN_MULT: float = 1.9
@export var acceleration: float = 8.0
@export var npc_name: String = "Survivor"
@export var idle_time_min: float = 3.0   ## wander pauses: people mostly stand around in downtime
@export var idle_time_max: float = 8.0

## Shared need thresholds — "needs it" means the same thing everywhere.
const NEED_LOW: float = 55.0      ## below this a need is actively pressing
const NEED_SATED: float = 90.0    ## drink/eat until at least this when convenient
const NEED_CRITICAL: float = 15.0 ## wakes a sleeper, interrupts nearly anything

# ─── Names ────────────────────────────────────────────────────────────────
## `npc_name` defaults to "Survivor" — also the sentinel _ready() uses to
## decide whether to randomize. Collision-avoided against other live NPCs so
## "Ask about" is never ambiguous; repeats only once the pool is exhausted.
const NPC_NAMES: Array[String] = [
	"Mara", "Dez", "Colton", "Priya", "Finch",
	"Sable", "Nolan", "Ruth", "Kwame", "Vera",
	"Ines", "Theo", "Juno", "Abel", "Hana",
	"Ossian", "Lena", "Marek", "Tova", "Cyrus",
]

func _assign_random_name() -> void:
	var used: Array[String] = []
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other != self and is_instance_valid(other) and ("npc_name" in other):
			used.append(String(other.npc_name))
	var available: Array[String] = NPC_NAMES.filter(func(n: String) -> bool: return not used.has(n))
	if available.is_empty():
		available = NPC_NAMES
	npc_name = available[randi() % available.size()]

# ─── Node refs / components ───────────────────────────────────────────────
@onready var collision: CollisionShape3D = $CollisionShape3D

var nav_agent: NavigationAgent3D = null
var hold_point: Node3D = null       ## carry anchor
var held_item: RigidBody3D = null   ## what's in hand, via PickupableItem.pickup

var brain: NPCBrain = null
var medical: NPCMedical = null
var job_state: NPCJobState = NPCJobState.new()
var thoughts: NPCThoughts = NPCThoughts.new()
var morale_sys: NPCMorale = NPCMorale.new()   ## slow, condition-driven morale (see NPCMorale.gd)
var bonds: NPCBonds = NPCBonds.new()           ## relationship ledger + remembered big moments
var social: NPCSocial = NPCSocial.new()        ## how the player's conduct shapes relationships
var crash: NPCCrashOut = NPCCrashOut.new()     ## mental breaks when morale collapses
var combat: NPCCombat = NPCCombat.new()        ## taking hits, dying, attacking (NPCCombat.gd)
var stuck: NPCStuckRecovery = NPCStuckRecovery.new()

## True once apply_save_dict() has populated this NPC — _ready() must not
## re-randomize identity for a restored resident.
var _restored: bool = false

# ─── Needs — 0..100, decay on the game clock ──────────────────────────────
var energy: float = 100.0
var hunger: float = 100.0   ## 100 = full, 0 = starving (PlayerStats' food convention)
var thirst: float = 100.0   ## 100 = hydrated

## Needs-cap ceilings, written by NPCMedical (Infection). The current value
## is clamped against the cap every tick, not just blocked from rising.
var hunger_cap: float = 100.0
var thirst_cap: float = 100.0
var energy_cap: float = 100.0

const ENERGY_DRAIN_PER_GAME_HOUR: float = 3.0
const HUNGER_DRAIN_PER_GAME_HOUR: float = 1.39  ## == PlayerStats.food_drain_per_game_hour
const THIRST_DRAIN_PER_GAME_HOUR: float = 2.08  ## == PlayerStats.water_drain_per_game_hour

var health: float = 100.0
## Drains only while hunger or thirst sits at literal 0; each zeroed need
## stacks its own drain (~20 game hours to die from one).
const HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR: float = 5.0

# ─── Identity ───────────────────────────────────────────────────────────
## Stable unique id (relationship key). Assigned in _ready(); overwritten by
## apply_save_dict() on load, which also keeps the counter ahead of it.
static var _next_npc_id: int = 1
var npc_id: String = ""
var generation_seed: int = 0

static func _register_id(id: String) -> void:
	if id.begins_with("npc_"):
		var n: int = id.substr(4).to_int()
		if n >= _next_npc_id:
			_next_npc_id = n + 1

# ─── Age & birthday ───────────────────────────────────────────────────────
## 20–80, 66% in the 30–50 prime band; the rest split 25/75 between the
## 20–29 and 51–80 bands (proportional to band width). 65+ moves and works
## at 0.75x. On their birthday the age silently ticks up — nothing else
## happens, by design.
var age: int = 35
const AGE_ELDER_THRESHOLD: int = 65
const AGE_ELDER_MULT: float = 0.75
var _birthday_day_of_year: int = 1
var _birthday_last_checked_day: int = -1

func randomize_age() -> void:
	if randf() < 0.66:
		age = randi_range(30, 50)
	elif randf() < 0.25:
		age = randi_range(20, 29)
	else:
		age = randi_range(51, 80)

func is_elder() -> bool:
	return age >= AGE_ELDER_THRESHOLD

func get_age_speed_mult() -> float:
	return AGE_ELDER_MULT if is_elder() else 1.0

func get_age_work_mult() -> float:
	return AGE_ELDER_MULT if is_elder() else 1.0

func _check_birthday() -> void:
	var day: int = NPCClock.day()
	if day == _birthday_last_checked_day:
		return
	_birthday_last_checked_day = day
	if ((day - 1) % 365) + 1 == _birthday_day_of_year:
		age += 1

# ─── Daily rhythm ───────────────────────────────────────────────────────
## Everyone sleeps at night, but not all at the same minute: `chronotype`
## shifts this resident's bedtime/wake time (early birds ↔ night owls).
const BEDTIME_HOUR: float = 22.0
const WAKE_HOUR: float = 6.5
var chronotype: float = 0.0   ## hours, -1.5 .. +1.5

func get_bedtime() -> float:
	return BEDTIME_HOUR + chronotype

func get_wake_time() -> float:
	return WAKE_HOUR + chronotype * 0.7

func is_night_for_me() -> bool:
	return NPCClock.hour_in(NPCClock.hour_of_day(), get_bedtime(), get_wake_time())

## How strongly this resident wants to sleep right now, 0..1. Night makes
## sleep attractive even when not exhausted; in the day only real
## exhaustion does (a nap).
func get_sleep_drive() -> float:
	var tired: float = urgency(energy, 70.0, 5.0)
	var exhausted: float = urgency(energy, 28.0, 3.0)
	if is_night_for_me():
		## Nobody turns in for the night an hour before they'd get up anyway.
		var hours_left: float = fposmod(get_wake_time() - NPCClock.hour_of_day(), 24.0)
		if hours_left < 1.5:
			return exhausted
		if energy >= 92.0:
			return 0.0
		var drive: float = clampf(0.45 + 0.55 * tired, 0.0, 1.0)
		## Grab a bite / a drink before turning in, unless dead on their feet.
		if (hunger < 50.0 or thirst < 55.0) and exhausted < 0.5:
			drive *= 0.6
		return drive
	return exhausted

# ─── Personality ──────────────────────────────────────────────────────────
## 5 traits, 0..1, generated once. Each trait is present on ~55% of NPCs;
## a present trait is always clearly low or high, an absent one reads as
## the 0.5 baseline everywhere via personality.get(key, 0.5).
var personality: Dictionary = {}
const PERSONALITY_TRAIT_KEYS: Array[String] = [
	"resilience", "sociability", "work_ethic", "neuroticism", "optimism",
]
const TRAIT_BAND_LOW: float = 0.35
const TRAIT_BAND_HIGH: float = 0.65
const TRAIT_PRESENCE_CHANCE: float = 0.55
const TRAIT_WORDS: Dictionary = {
	"resilience":  {"low": "Irritable",   "mid": "Even-Tempered", "high": "Level-Headed"},
	"sociability": {"low": "Distant",     "mid": "Reserved",      "high": "Open"},
	"work_ethic":  {"low": "Lazy",        "mid": "Steady",        "high": "Hard Worker"},
	"neuroticism": {"low": "Easygoing",   "mid": "Composed",      "high": "Neurotic"},
	"optimism":    {"low": "Pessimistic", "mid": "Realistic",     "high": "Optimistic"},
}

## Passions (Sep 2026): some residents love one kind of work, stored as
## personality["passion"]. It pulls them toward that job whatever their
## work ethic: a Lazy Gourmand barely lifts a finger except to cook; a
## Hard-Working one works constantly, cooking first.
const PASSIONS: Dictionary = {"COOKING": "Gourmand", "GARDENING": "Gardener"}
const PASSION_JOBS: Dictionary = {"COOKING": ["COOKING"], "GARDENING": ["GARDENING", "HARVEST"]}
const PASSION_CHANCE: float = 0.3
const PASSION_MULT: float = 1.7

func randomize_personality() -> void:
	personality = {}
	for k: String in PERSONALITY_TRAIT_KEYS:
		if randf() >= TRAIT_PRESENCE_CHANCE:
			continue
		personality[k] = randf_range(0.0, TRAIT_BAND_LOW) if randf() < 0.5 else randf_range(TRAIT_BAND_HIGH, 1.0)
	if randf() < PASSION_CHANCE:
		personality["passion"] = PASSIONS.keys().pick_random()

func get_passion() -> String:
	return String(personality.get("passion", ""))

func is_passion_job(job_type: String) -> bool:
	return job_type in (PASSION_JOBS.get(get_passion(), []) as Array)

## Someone else who loves this job is up and about (not asleep, passed out
## or crashing out), so the rest leave it to them.
func _passion_holder_free(job_type: String) -> bool:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other != self and other is NPC and (other as NPC).is_passion_job(job_type) \
				and not other.is_passed_out() and (other.crash == null or not other.crash.active()) \
				and (other.brain == null or not other.brain.is_sleeping()):
			return true
	return false

func _trait(key: String) -> float:
	return float(personality.get(key, 0.5))

func get_trait_word(key: String) -> String:
	if not personality.has(key):
		return ""
	var v: float = float(personality[key])
	var bands: Dictionary = TRAIT_WORDS.get(key, {})
	if bands.is_empty():
		return ""
	if v < TRAIT_BAND_LOW:
		return bands["low"]
	elif v > TRAIT_BAND_HIGH:
		return bands["high"]
	return bands["mid"]

func get_personality_words() -> Array[String]:
	var out: Array[String] = []
	for k: String in PERSONALITY_TRAIT_KEYS:
		var w: String = get_trait_word(k)
		if w != "":
			out.append(w)
	if PASSIONS.has(get_passion()):
		out.append(String(PASSIONS[get_passion()]))
	return out

func has_irritable_trait() -> bool:
	return _trait("resilience") < TRAIT_BAND_LOW

func has_lazy_trait() -> bool:
	return _trait("work_ethic") < TRAIT_BAND_LOW

## Resilience: amplifies (Irritable) / dampens (Level-Headed) irritability
## and forgetfulness from the same conditions. 1.0 at baseline.
func _irritability_trait_mult() -> float:
	return lerp(1.5, 0.5, _trait("resilience"))

## Sociability: relationship-change magnitude (0.5x..1.5x).
func _sociability_trait_mult() -> float:
	return lerp(0.5, 1.5, _trait("sociability"))

## Sociability: how much THIS NPC's mood is pulled toward the group's.
func get_contagion_sociability_mult() -> float:
	return lerp(0.67, 1.33, _trait("sociability"))

## Work Ethic shapes autonomy (Sep 2026). Steady residents take jobs as
## they come; Hard Workers (1.3x) seek them out. The Lazy still work, just
## noticeably less and on their own terms:
##   - ordinary medium chores sometimes, when the mood takes them (a slow
##     per-resident swing in motivation over the day);
##   - small jobs (a light tidy-up) basically never, and big emergencies
##     half-expecting someone else to deal with it;
##   - never job-hunting: far-off jobs lose appeal fast (JobActivity);
##   - short stints (a cleaning session is half as long), then they knock
##     off for a couple of hours ("did my bit").
## A passion job (Gourmand → cooking, Gardener → farming) ignores all that
## and gets PASSION_MULT on top. Player pressure (NPCSocial.drive)
## overrides it for a few hours.
const LAZY_MOTIVATION_PERIOD_H: float = 7.0
const LAZY_BREAK_AFTER_WORK_H: float = 2.5
var _last_work_done_at: float = -100.0

## 0 = not lazy at all (Steady and up) .. 1 = thoroughly Lazy.
func get_sloth() -> float:
	return 1.0 - smoothstep(0.15, 0.5, _trait("work_ethic"))

func get_work_ethic_job_mult(raw: float = JOB_BASE_SCORE, job_type: String = "") -> float:
	var drive: float = social.drive() if social != null else 0.0
	var m: float = lerpf(1.0, 1.3, smoothstep(0.5, 0.9, _trait("work_ethic")))
	if job_type != "" and is_passion_job(job_type):
		return m * PASSION_MULT * (1.0 + 2.5 * drive)
	var sloth: float = get_sloth() * (1.0 - drive)   ## pushed hard, the excuses run out
	if sloth > 0.0:
		m *= 1.0 - 0.45 * sloth
		m *= 1.0 - 0.6 * sloth * (1.0 - smoothstep(8.0, 15.0, raw))   ## small jobs: not worth getting up for
		m *= 1.0 - 0.3 * sloth * smoothstep(35.0, 55.0, raw)          ## emergencies: someone else will
		## Motivation comes and goes (phase differs per resident).
		var phase: float = float(hash(npc_id) % 1000) / 1000.0 * TAU
		m *= 1.0 + 0.35 * sloth * sin(NPCClock.now() * TAU / LAZY_MOTIVATION_PERIOD_H + phase)
		## Did my bit — a break before the next one.
		var since: float = NPCClock.now() - _last_work_done_at
		m *= 1.0 - 0.7 * sloth * (1.0 - clampf(since / LAZY_BREAK_AFTER_WORK_H, 0.0, 1.0))
	return m * (1.0 + 2.5 * drive)

func get_work_ethic_passive_mult() -> float:
	if crash != null and crash.mode == NPCCrashOut.Mode.OVERDRIVE:
		return 0.3   ## overdrive: no breaks, only pacing between jobs
	var drive: float = social.drive() if social != null else 0.0
	return lerp(1.5, 0.7, social.ethic() if social != null else 0.5) * (1.0 - 0.8 * drive)

## Neuroticism: mood noise and the pass-out mood hit (0.5x..1.5x).
func neuroticism_trait_mult() -> float:
	return lerp(0.5, 1.5, _trait("neuroticism"))

## How strongly a thought lands: optimists feel good things more,
## neurotic residents feel bad things more.
func thought_weight(mood_delta: float) -> float:
	if mood_delta >= 0.0:
		return lerp(0.75, 1.25, _trait("optimism"))
	return lerp(0.75, 1.3, _trait("neuroticism"))

func add_thought(id: String, subject: String = "") -> void:
	var def: Dictionary = NPCThoughts.DEFS.get(id, {})
	if def.is_empty():
		return
	thoughts.add(id, subject, thought_weight(float(def["mood"])))
	## Meals and nights also shape the slow Food/Rest conditions of morale.
	if id.begins_with("ate_"):
		morale_sys.note_meal(id)
	elif id.begins_with("slept_") or id == "collapsed":
		morale_sys.note_sleep(id)

# ─── Utility helpers (shared by every activity's score()) ────────────────
## 0 while `value` ≥ `start`, 1 once `value` ≤ `full`, smoothstepped in
## between. The standard response curve for "the lower this gets, the more
## it matters" — replaces the old hard on/off need thresholds that made an
## NPC ignore hunger at 56 and drop everything for it at 54.
static func urgency(value: float, start: float, full: float) -> float:
	if value >= start:
		return 0.0
	if value <= full:
		return 1.0
	var t: float = (start - value) / (start - full)
	return t * t * (3.0 - 2.0 * t)

## Score scale (Sep 2026 — one scale for everything):
##   idle        ~5–15   (wander, relax, chat, give to a friend)
##   chores      ~15–35  (cleaning grows with clutter, gardening, cooking...)
##   urgent jobs ~35–60  (a generator about to run dry, a failing filter)
##   needs        0–100  (eat/drink/sleep follow urgency curves)
const JOB_BASE_SCORE: float = 20.0
const JOB_PRIORITY_WEIGHTS: Dictionary = {
	"HARVEST": 1.3,
	"REPLACE_FILTER": 1.0,
	"REFUEL": 1.0,
	"CLEANING": 1.0,     ## its clutter curve already encodes the low priority
	"GARDENING": 0.8,
	"COOKING": 0.95,
}
const JOB_PRIORITY_DEFAULT: float = 1.0
const JOB_SKILL: Dictionary = {
	"HARVEST": "farming", "GARDENING": "farming", "REPLACE_FILTER": "plumbing",
	"REFUEL": "electrical", "COOKING": "cooking", "CLEANING": "",
}

func get_job_priority_weight(job_type: String) -> float:
	return float(JOB_PRIORITY_WEIGHTS.get(job_type, JOB_PRIORITY_DEFAULT))

## Standard job score: base × priority × urgency × work ethic × a small
## skill preference × willingness (irritable people drag their feet).
func work_score(job_type: String, urgency_mult: float = 1.0, base: float = JOB_BASE_SCORE) -> float:
	var skill_key: String = String(JOB_SKILL.get(job_type, ""))
	var skill_pref: float = 1.0
	if skill_key != "" and skills.has(skill_key):
		skill_pref = lerp(0.9, 1.15, clampf((float(skills[skill_key]) - 0.6) / 1.4, 0.0, 1.0))
	var willingness: float = 1.0 - (irritability / 100.0) * 0.5
	var overdrive: float = 2.2 if crash != null and crash.mode == NPCCrashOut.Mode.OVERDRIVE else 1.0
	var raw: float = base * get_job_priority_weight(job_type) * urgency_mult
	if not is_passion_job(job_type) and _passion_holder_free(job_type):
		raw *= 0.6   ## "that's Ruth's thing" — leave it to the Gourmand/Gardener
	var shun: float = combat.shun_work_mult() if combat != null else 1.0   ## not beside someone who attacked them
	return raw * get_work_ethic_job_mult(raw, job_type) * skill_pref * willingness * overdrive * shun

## How fast this resident gets physical work done (age, injuries, skill).
## Every job's work timer multiplies its delta by this.
func get_work_speed_mult(skill_key: String = "") -> float:
	var m: float = get_age_work_mult()
	if crash != null and crash.mode == NPCCrashOut.Mode.OVERDRIVE:
		m *= 1.35   ## overdrive: frantic pace
	if social != null:
		m *= 1.0 + 0.25 * social.drive()   ## pushed hard, they hurry
	if medical != null:
		m *= medical.get_medical_job_speed_multiplier()
	if skill_key != "" and skills.has(skill_key):
		m *= lerp(0.85, 1.25, clampf((float(skills[skill_key]) - 0.6) / 1.4, 0.0, 1.0))
	if mood < 25.0:
		m *= 0.85
	return m

# ─── Mood (0..100) & irritability (fast, no bar) ──────────────────────────
## Displayed mood = MORALE (slow, NPCMorale — sustained bunker conditions)
## + a capped share of FEELINGS (NPCThoughts — today's moodlets, including
## hunger/thirst/exhaustion). Crash-outs read morale, not mood.
## Sep 2026: replaces "needs average + thoughts + random drift", which
## swung from content to miserable within a game day for no visible reason.
var mood: float = 65.0
const MOOD_FEELINGS_MIN: float = -25.0
const MOOD_FEELINGS_MAX: float = 15.0
const MOOD_FOLLOW_PER_GAME_HOUR: float = 10.0
const MOOD_TICK_INTERVAL: float = 5.0   ## real seconds — periodic, not per-frame
var _mood_tick_timer: float = 0.0

var morale: float:
	get: return morale_sys.morale if morale_sys != null else mood

var irritability: float = 0.0
const IRRITABILITY_NEED_WEIGHT: float = 1.2
const IRRITABILITY_MOOD_WEIGHT: float = 0.4
const IRRITABILITY_CHANGE_PER_GAME_HOUR: float = 20.0
const IRRITABILITY_BASE_BREAKPOINTS: Array[float] = [20.0, 45.0, 70.0, 90.0]
const IRRITABILITY_LABELS: Array[String] = ["Grumpy", "Frustrated", "Mad", "Rage"]
var _irritability_target: float = 0.0

## Irritable-trait NPCs cross each label 5% sooner; everyone else 10% later.
func _irritability_breakpoints() -> Array[float]:
	var mult: float = 0.95 if has_irritable_trait() else 1.10
	var out: Array[float] = []
	for b: float in IRRITABILITY_BASE_BREAKPOINTS:
		out.append(b * mult)
	return out

func get_irritability_label() -> String:
	var bp: Array[float] = _irritability_breakpoints()
	var label: String = ""
	for i: int in range(bp.size()):
		if irritability >= bp[i]:
			label = IRRITABILITY_LABELS[i]
	return label

func get_feelings() -> float:
	return clampf(thoughts.total(), MOOD_FEELINGS_MIN, MOOD_FEELINGS_MAX)

func get_mood_target() -> float:
	return clampf(morale_sys.morale + get_feelings(), 0.0, 100.0)

func _tick_social_and_mood(delta: float) -> void:
	_mood_tick_timer -= delta
	if _mood_tick_timer > 0.0:
		return
	var h: float = NPCClock.game_hours(MOOD_TICK_INTERVAL - _mood_tick_timer)
	_mood_tick_timer = MOOD_TICK_INTERVAL
	if h <= 0.0:
		return
	_update_proximity(h)
	thoughts.tick(h)
	_update_condition_thoughts()
	_tick_mood(h)
	bonds.tick(h)
	social.tick(h)
	crash.tick(h)
	_tick_irritability(h)
	_tick_relax_day(h)
	if gift_saturation > 0.0:
		gift_saturation = maxf(0.0, gift_saturation - GIFT_SATURATION_DECAY_PER_GAME_HOUR * h)
	_check_label_crossings()
	_check_birthday()
	if NPCDebug.enabled:
		NPCDebug.log_relationship_tick(self)

func _tick_mood(h: float) -> void:
	var before: float = mood
	morale_sys.tick(h, thoughts.total())
	mood = move_toward(mood, get_mood_target(), MOOD_FOLLOW_PER_GAME_HOUR * h)
	if NPCDebug.enabled:
		NPCDebug.log_mood(self, mood - before, 0.0, 0.0, mood)

func _tick_irritability(h: float) -> void:
	var need_contrib: float = maxf(0.0, 50.0 - energy) + maxf(0.0, 50.0 - hunger) + maxf(0.0, 50.0 - thirst)
	var mood_contrib: float = maxf(0.0, 50.0 - mood)
	var trait_mult: float = _irritability_trait_mult()
	_irritability_target = clampf(
		(need_contrib * IRRITABILITY_NEED_WEIGHT + mood_contrib * IRRITABILITY_MOOD_WEIGHT) * trait_mult, 0.0, 100.0)
	if social != null and social.is_cowed():
		_irritability_target = minf(_irritability_target * 0.4, 40.0)   ## put in their place: no tantrums
	irritability = move_toward(irritability, _irritability_target, IRRITABILITY_CHANGE_PER_GAME_HOUR * h)
	if NPCDebug.enabled:
		NPCDebug.log_irritability(self, need_contrib, mood_contrib, trait_mult, _irritability_target, irritability)

## Situational thoughts that hold while a condition lasts.
const CLUTTER_UPSETS_AT: int = 12
const LONELY_AFTER_HOURS: float = 30.0
var _last_social_time: float = -1.0   ## NPCClock hours of the last real conversation

func _update_condition_thoughts() -> void:
	## Acute needs are FEELINGS (fast, visible, explained) — not morale.
	thoughts.set_condition("starving", hunger < 15.0, thought_weight(-1.0))
	thoughts.set_condition("hungry", hunger >= 15.0 and hunger < 35.0, thought_weight(-1.0))
	thoughts.set_condition("parched", thirst < 15.0, thought_weight(-1.0))
	thoughts.set_condition("thirsty", thirst >= 15.0 and thirst < 35.0, thought_weight(-1.0))
	thoughts.set_condition("exhausted", energy < 15.0, thought_weight(-1.0))
	thoughts.set_condition("cluttered", JobBoard.get_total_clutter_count() >= CLUTTER_UPSETS_AT, thought_weight(-1.0))
	var hurting: bool = false
	if medical != null:
		for c: MedicalCondition in medical.active_conditions:
			if c.id in ["bleeding", "fractured", "broken", "burn"] or c.is_infected:
				hurting = true
				break
	thoughts.set_condition("in_pain", hurting, thought_weight(-1.0))
	var now: float = NPCClock.now()
	if _last_social_time < 0.0:
		_last_social_time = now
	var lonely: bool = _trait("sociability") >= 0.35 and now - _last_social_time > LONELY_AFTER_HOURS
	thoughts.set_condition("lonely", lonely, thought_weight(-1.0))

# ─── Relationships ────────────────────────────────────────────────────────
## Directional, from THIS NPC's perspective. Key = another NPC's npc_id or
## "player". -100..100, 0 = neutral (absent key reads as 0).
var relationships: Dictionary = {}
const RELATIONSHIP_MIN: float = -100.0
const RELATIONSHIP_MAX: float = 100.0
const RELATIONSHIP_BAND_THRESHOLDS: Array[float] = [-60.0, -20.0, 20.0, 60.0]
const RELATIONSHIP_LABELS: Array[String] = ["Hostile", "Cold", "Neutral", "Friendly", "Close"]
## "Together" = within this XZ range AND in line of sight (Sep 2026 — a
## wall between two people no longer counts as spending time together).
const RELATIONSHIP_PROXIMITY_RANGE: float = 4.0
const RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR: float = 0.15

func get_relationship(target_id: String) -> float:
	return float(relationships.get(target_id, 0.0))

func get_relationship_label(target_id: String) -> String:
	var v: float = get_relationship(target_id)
	for i: int in range(RELATIONSHIP_BAND_THRESHOLDS.size()):
		if v < RELATIONSHIP_BAND_THRESHOLDS[i]:
			return RELATIONSHIP_LABELS[i]
	return RELATIONSHIP_LABELS[RELATIONSHIP_LABELS.size() - 1]

## Single mutation point for every relationship change. Returns the ACTUAL
## applied delta (post-sociability, post-clamp).
func _adjust_relationship(target_id: String, delta: float) -> float:
	if target_id == "" or target_id == npc_id:
		return 0.0
	var current: float = get_relationship(target_id)
	var new_value: float = clampf(current + delta * _sociability_trait_mult(), RELATIONSHIP_MIN, RELATIONSHIP_MAX)
	relationships[target_id] = new_value
	return new_value - current

## F7 debug — exact delta, bypassing sociability.
## Which resident (if any) is holding this item.
static func holder_of(tree: SceneTree, item: Node) -> NPC:
	for n: Node in tree.get_nodes_in_group("npc"):
		if n is NPC and n.held_item == item:
			return n
	return null

## Player-facing hooks (resident panel, InteractionSystem).
## Returns false when the order is refused (mid crash-out: it runs its course).
func on_player_command(activity: NPCActivity) -> bool:
	if crash.blocks_commands():
		social.last_refusal = "%s won't listen right now — they're crashing out." % npc_name
		bark(NPCDialogue.bark_line("seething" if crash.mode == NPCCrashOut.Mode.HOSTILE else "sob"), true)
		return false
	if not social.on_player_command(activity):
		bark(social.last_refusal, true)
		return false
	return true

## Why the last order was refused ("" if it wasn't).
func get_last_refusal() -> String:
	return social.last_refusal

## Resident panel: morale at a glance, with its reasons (NPCMorale).
func get_morale_summary() -> Dictionary:
	var reasons: Array[Dictionary] = []
	for r: Dictionary in morale_sys.get_reasons().slice(0, 3):
		reasons.append({"text": r["text"], "points": r["points"]})
	var crash_text: String = ""
	if crash.active():
		crash_text = "Crashing out — %s" % crash._short()
	return {"morale": morale_sys.morale, "band": morale_sys.get_band(), "trend": morale_sys.get_trend(),
		"reasons": reasons, "crash": crash_text, "at_risk": crash.daily_risk() > 0.0 and not crash.active()}

## Resident panel: the most significant remembered moments (biggest first).
func get_memory_summaries(limit: int = 3) -> Array[Dictionary]:
	var mems: Array[Dictionary] = bonds.get_memories()
	mems.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a["amount"]) > absf(b["amount"]))
	var out: Array[Dictionary] = []
	for m: Dictionary in mems.slice(0, limit):
		out.append({"text": m["text"], "amount": m["amount"], "about": m["name"]})
	return out

func is_crashing_out() -> bool:
	return crash.active()

## Debug / morale timeline test: would a crash-out start this step?
func debug_roll_crash_out(h: float) -> bool:
	return crash.roll(h)

func on_player_worked(pos: Vector3) -> void:
	social.on_player_worked(pos)

# ─── Player treating this resident (Bandage / Antibiotics / Splint) ────────
## Medical items declare NPC_TREATMENT; the player holding one near an
## injured resident sees "[E] Bandage Mara's left arm" and E applies it to
## the worst eligible injury (InteractionSystem), then the item spends its
## own charge. The resident remembers who patched them up.
const TREATMENTS: Dictionary = {
	"bleeding":    {"targets": "get_eligible_bleeding_targets", "apply": "treat_bleeding", "prompt": "[E] Bandage %s's %s", "what": "my bleeding %s"},
	"antibiotics": {"targets": "get_eligible_antibiotic_targets", "apply": "treat_open_wound_antibiotics", "prompt": "[E] Give %s antibiotics (%s wound)", "what": "the wound on my %s"},
	"splint":      {"targets": "get_eligible_splint_targets", "apply": "apply_splint", "prompt": "[E] Splint %s's %s", "what": "my %s"},
}
var _last_treated_hours: float = -100.0

func _treatment_target(item: Node) -> Dictionary:
	if item == null or not is_instance_valid(item) or not ("NPC_TREATMENT" in item) or medical == null:
		return {}
	var def: Dictionary = TREATMENTS.get(String(item.NPC_TREATMENT), {})
	if def.is_empty() or (item.has_method("has_charges_left") and not item.has_charges_left()):
		return {}
	var targets: Array = medical.call(String(def["targets"]))
	if targets.is_empty():
		return {}
	return {"def": def, "target": targets[0]}   ## worst first (NPCMedical sorts by severity)

## "" when this item can't help this resident right now.
func treatment_prompt(item: Node) -> String:
	var t: Dictionary = _treatment_target(item)
	if t.is_empty():
		return ""
	return String(t["def"]["prompt"]) % [npc_name, String(t["target"]["label"]).to_lower()]

func receive_treatment(item: Node) -> bool:
	var t: Dictionary = _treatment_target(item)
	if t.is_empty():
		return false
	var part: int = int(t["target"]["body_part"])
	var was_critical: bool = combat.is_critical()
	medical.call(String(t["def"]["apply"]), part)
	var where: String = String(t["target"]["label"]).to_lower()
	if item.has_method("spend_charge"):
		item.spend_charge()
	log_event("care", "Treated by you: %s" % (String(t["def"]["what"]) % where))
	bark_event("thanks")
	## Being cared for matters most the first time; repeat care still counts.
	var repeat: bool = NPCClock.now() - _last_treated_hours < 12.0
	_last_treated_hours = NPCClock.now()
	## Patching up someone at death's door is a rescue, not just care.
	if was_critical and combat.credit_rescue("kept me alive when I was dying"):
		return true
	on_treated_by_player(String(t["def"]["what"]) % where, repeat)
	return true

## Weapons contract (docs/systems/weapons/HANDOFF.md): WeaponItem calls this
## on the resident it hit. NPCCombat decides what the hit means.
func receive_weapon_hit(context: Dictionary) -> void:
	combat.receive_hit(context)
	if not combat.dead:
		NPCCombat.play_hit_reaction(self, context)

## Read by the shared AdventurerModelController: true plays the dying clip.
func is_dead() -> bool:
	return combat.dead

func on_treated_by_player(what: String = "my wounds", repeat: bool = false) -> void:
	if repeat:
		bonds.relate("player", 3.0, "took care of %s again" % what)
		return
	bonds.relate("player", 8.0, "patched up %s" % what, "You patched me up when I was hurt", true)
	NPCBonds.witnessed(get_tree(), "player", self, 3.0, "took care of %s" % npc_name)

## Carried out of danger, revived, defended from an attacker. Called via
## NPCCombat.credit_rescue (defended from an attacker, treated while
## critical); carrying/pulling from danger still needs a player-side verb.
func on_rescued_by_player(what: String = "saved my life") -> void:
	bonds.relate("player", 20.0, what, "You %s" % what, true)
	NPCBonds.witnessed(get_tree(), "player", self, 6.0, "saved %s" % npc_name)

func talk_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in NPCSocial.TALK_CHOICES:
		out.append({"id": c["id"], "label": c["label"], "tone": c["tone"], "why_not": social.talk_unavailable_reason(String(c["id"]))})
	return out

func talk_choice(choice: String) -> Dictionary:
	return social.talk(choice)

func debug_adjust_relationship(target_id: String, delta: float) -> void:
	relationships[target_id] = clampf(get_relationship(target_id) + delta, RELATIONSHIP_MIN, RELATIONSHIP_MAX)

func debug_adjust_player_relationship(delta: float) -> void:
	debug_adjust_relationship("player", delta)

func _can_see(other: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)
	var to: Vector3 = other.global_position + Vector3(0.0, 0.5, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == other or not (hit.get("collider") is StaticBody3D)

## One pass over everyone nearby: relationship proximity gain and mood-
## contagion exposure (both use the same definition of "together").
const CONTAGION_EXPOSURE_GAIN_PER_GAME_HOUR: float = 0.5
const CONTAGION_EXPOSURE_DECAY_PER_GAME_HOUR: float = 0.2
const CONTAGION_EXPOSURE_MAX: float = 5.0
var _contagion_exposure: Dictionary = {}   ## other npc_id -> 0..CONTAGION_EXPOSURE_MAX

func _update_proximity(h: float) -> void:
	var gain: float = RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR * h
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not (other is NPC):
			continue
		var id: String = other.npc_id
		var together: bool = NPCItemUser.flat_distance(global_position, other.global_position) <= RELATIONSHIP_PROXIMITY_RANGE \
			and _can_see(other)
		var exposure: float = float(_contagion_exposure.get(id, 0.0))
		if together:
			bonds.relate(id, gain, "spent time with me")
			exposure = minf(CONTAGION_EXPOSURE_MAX, exposure + CONTAGION_EXPOSURE_GAIN_PER_GAME_HOUR * h)
		else:
			exposure = maxf(0.0, exposure - CONTAGION_EXPOSURE_DECAY_PER_GAME_HOUR * h)
		_contagion_exposure[id] = exposure
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null and NPCItemUser.flat_distance(global_position, player.global_position) <= RELATIONSHIP_PROXIMITY_RANGE \
			and _can_see(player):
		bonds.relate("player", gain, "spent time with me")

## Exposure-weighted average of other NPCs' moods (own mood if nobody's
## been around — a no-op target).
func _compute_weighted_contagion_target() -> float:
	var weighted_sum: float = 0.0
	var weight_total: float = 0.0
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not (other is NPC):
			continue
		var exposure: float = float(_contagion_exposure.get(other.npc_id, 0.0))
		if exposure <= 0.0:
			continue
		weighted_sum += float(other.morale) * exposure
		weight_total += exposure
	return weighted_sum / weight_total if weight_total > 0.0 else morale

## Exposure-weighted morale of the people this resident spends time with
## (NPCMorale pulls gently toward it — moods are contagious, slowly).
func contagion_target() -> float:
	return _compute_weighted_contagion_target()

# ─── Action log ─────────────────────────────────────────────────────────────
## Player-facing, curated log of MEANINGFUL things this NPC did — not a
## record of routine activity switching.
signal action_logged

const ACTION_LOG_MAX_LEN: int = 100
var _action_log: Array[Dictionary] = []
var _last_irritability_label: String = ""
var _last_player_relationship_label: String = "Neutral"

## Entries carry both a live-age stamp (fired_at_msec, for the UI's
## "Xs ago") and a game-time stamp (stamp_hours / game_time) that survives
## saving and loading.
func log_action(text: String) -> Dictionary:
	var entry: Dictionary = {
		"text": text,
		"fired_at_msec": Time.get_ticks_msec(),
		"stamp_hours": NPCClock.now(),
		"game_time": NPCClock.time_string(),
	}
	_action_log.append(entry)
	if _action_log.size() > ACTION_LOG_MAX_LEN:
		_action_log.pop_front()
	action_logged.emit()
	return entry

## A categorised log entry ("morale", "bond", "memory", "crash"...) — the UI
## can colour/filter by kind; the text is always plain English.
func log_event(kind: String, text: String) -> Dictionary:
	var entry: Dictionary = log_action(text)
	entry["kind"] = kind
	return entry

## Newest-first.
func get_action_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = _action_log.duplicate()
	out.reverse()
	return out

var _hostile_log_entry: Dictionary = {}
var _hostile_start_msec: int = 0

## Live "HOSTILE for Ns" entry, mutated in place during a snatch pursuit.
func start_hostile_log() -> void:
	_hostile_start_msec = Time.get_ticks_msec()
	_hostile_log_entry = log_action("%s HOSTILE for 0s" % npc_name)
	_hostile_log_entry["is_live_hostile"] = true

func update_hostile_log() -> void:
	if _hostile_log_entry.is_empty():
		return
	_hostile_log_entry["text"] = "%s HOSTILE for %ds" % [npc_name, int((Time.get_ticks_msec() - _hostile_start_msec) / 1000.0)]

func end_hostile_log() -> void:
	if not _hostile_log_entry.is_empty():
		_hostile_log_entry["text"] = "%s was HOSTILE for %ds" % [npc_name, int((Time.get_ticks_msec() - _hostile_start_msec) / 1000.0)]
		_hostile_log_entry["is_live_hostile"] = false
	_hostile_log_entry = {}

func _check_label_crossings() -> void:
	var irr_label: String = get_irritability_label()
	if irr_label != _last_irritability_label:
		if irr_label != "":
			log_action("Became \"%s\" (irritability)" % irr_label)
		elif _last_irritability_label != "":
			log_action("Calmed down (irritability)")
		_last_irritability_label = irr_label
	var rel_label: String = get_relationship_label("player")
	if rel_label != _last_player_relationship_label:
		log_action("Relationship with the player became \"%s\"" % rel_label)
		_last_player_relationship_label = rel_label

# ─── Give / Takeaway (player ↔ NPC, NPC → NPC) ────────────────────────────
const GIVE_RELATIONSHIP_BONUS: float = 7.5
const TAKEAWAY_RELATIONSHIP_PENALTY: float = 7.5
const TAKEAWAY_NEED_THRESHOLD: float = NEED_LOW
## Gift burnout — repeated gifts in a short window give smaller boosts
## (full recovery over ~5 game days), never fully zero.
const GIFT_SATURATION_MAX: float = 1.0
const GIFT_SATURATION_PER_GIFT: float = 0.25
const GIFT_SATURATION_DECAY_PER_GAME_HOUR: float = 1.0 / (5.0 * 24.0)
const GIFT_BONUS_FLOOR_MULT: float = 0.15
var gift_saturation: float = 0.0

## Pure check — called before the physical transfer. giver_id defaults to
## the player.
func can_receive_item(item: Node, giver_id: String = "player") -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if NPCItemUser.hands_full(self):
		return false
	if is_gift_blocked_from(giver_id):
		return false
	if brain != null and brain.is_sleeping():
		return false
	return NPCItemUser.is_giveable(item)

## Called AFTER the item is already in held_item (the giver's side did the
## transfer). Starts eating/drinking it and applies relationship/burnout.
## Per-(item, NPC) marking: the same can can boost several DIFFERENT NPCs
## once each, never the same NPC twice.
func on_item_given(item: Node, giver_id: String = "player", giver_name: String = "Player") -> void:
	var recipients: Array = item.get_meta("npc_gift_recipients", [])
	var already_boosted: bool = recipients.has(npc_id)
	if not already_boosted:
		recipients.append(npc_id)
		item.set_meta("npc_gift_recipients", recipients)
	var item_name: String = item.get_display_name() if item.has_method("get_display_name") else "something"

	var activity: NPCActivity = GivenEatActivity.new() if NPCItemUser.is_edible(item) else GivenDrinkActivity.new()
	brain.force_command(activity)
	activity.begin_with_item(self, item)

	if already_boosted:
		log_action("%s gave %s to %s (fed only, no relationship change)" % [giver_name, item_name, npc_name])
		return
	## Context multiplies (see plans/NPC_MORALE_CRASHOUT_PLAN.md): water for
	## someone parched, food in a shortage, a hot meal instead of a can.
	var ctx: Dictionary = _gift_context(item)
	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * float(ctx["mult"]) * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	var applied: float = bonds.relate(giver_id, effective_bonus, "gave me %s%s" % [ctx["what"], ctx["when"]])
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	NPCBonds.witnessed(get_tree(), giver_id, self, 3.0, "shared food with %s" % npc_name)
	if giver_id == "player":
		for other: Node in get_tree().get_nodes_in_group("npc"):
			if other != self and other is NPC:
				other.social.on_saw_player_feed(self)
	add_thought("received_gift", giver_name if giver_id != "player" else "You")
	if giver_id == "player":
		bark_event("thanks")
	else:
		bark_event("thanks_friend", giver_name)
	if is_zero_approx(applied):
		log_action("%s gave %s to %s" % [giver_name, item_name, npc_name])

## What a gift meant: {mult, what ("a hot meal"), when (" when I was starving")}.
func _gift_context(item: Node) -> Dictionary:
	var mult: float = 1.0
	var what: String = "something to eat"
	var food: bool = NPCItemUser.is_edible(item)
	if item is DishItem:
		mult *= 1.3
		what = "a hot meal"
	elif NPCItemUser.is_drinkable_bottle(item):
		what = "water"
	elif item is FarmProduceItem:
		what = "fresh food"
	var need: float = hunger if food else thirst
	var when: String = ""
	if need < 15.0:
		mult *= 2.0
		when = " when I was starving" if food else " when I was parched"
	elif need < 35.0:
		mult *= 1.5
		when = " when I was hungry" if food else " when I was thirsty"
	if food and _food_is_scarce():
		mult *= 1.5
		when += (" while food was scarce" if when == "" else ", while food was scarce")
	return {"mult": mult, "what": what, "when": when}

## Fewer edible items (loose or stored) than residents.
func _food_is_scarce() -> bool:
	var n: int = 0
	for it: Node in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(it) and NPCItemUser.is_edible(it):
			n += 1
	for shelf: Node in get_tree().get_nodes_in_group("shelving"):
		if "slots" in shelf:
			for stack in shelf.slots:
				if stack is Array:
					for it in stack:
						if it != null and is_instance_valid(it) and NPCItemUser.is_edible(it):
							n += 1
	return n < get_tree().get_nodes_in_group("npc").size()

## Takeaway gate: genuinely hungry/thirsty AND holding food/water now.
func is_consuming_from_need() -> bool:
	if not NPCItemUser.hands_full(self):
		return false
	if hunger >= TAKEAWAY_NEED_THRESHOLD and thirst >= TAKEAWAY_NEED_THRESHOLD:
		return false
	return NPCItemUser.is_edible(held_item) or NPCItemUser.is_drinkable_bottle(held_item)

## The player grabbed whatever this NPC was holding. Only a need-driven
## meal/drink costs relationship.
func on_item_taken_by_player() -> void:
	var was_need_triggered: bool = is_consuming_from_need()
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	if not was_need_triggered:
		return
	var starving: bool = hunger < 15.0 or thirst < 15.0
	bonds.relate("player", -TAKEAWAY_RELATIONSHIP_PENALTY * (1.5 if starving else 1.0),
		"took my %s while I was %s" % [item.get_display_name().to_lower(), "starving" if starving else "hungry"])
	add_thought("food_taken")
	bark_event("snatched")
	NPCBonds.witnessed(get_tree(), "player", self, -5.0, "took %s's food" % npc_name)

## Called on the VICTIM of an NPC snatch.
func on_item_snatched_by_npc(thief: NPC) -> void:
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	add_thought("got_snatched", thief.npc_name)
	bark_event("snatched")
	bonds.relate(thief.npc_id, -8.0, "snatched my food")
	NPCBonds.witnessed(get_tree(), thief.npc_id, self, -4.0, "snatched food from %s" % npc_name)

# ─── Snatch (hostile food/water grabs) ───────────────────────────────────
const SNATCH_RELATIONSHIP_THRESHOLD: float = -50.0
const SNATCH_CHANCE_AT_THRESHOLD: float = 0.05
const SNATCH_CHANCE_AT_MIN: float = 0.5
## Game hours (Sep 2026 — were real-time msec, which ignored pause/fast-forward).
const SNATCH_GIFT_COOLDOWN_HOURS: float = 1.0
const NPC_SNATCH_PAIR_COOLDOWN_HOURS: float = 1.0 / 6.0
var _snatch_cooldown_from: Dictionary = {}       ## victim_id -> NPCClock hours of last pursuit tick
var _npc_snatch_pair_cooldown: Dictionary = {}   ## other npc_id -> NPCClock hours
var _debug_force_snatch: bool = false
var _debug_force_npc_snatch: bool = false
var _debug_force_give: bool = false

func start_snatch_cooldown_against(victim_id: String) -> void:
	_snatch_cooldown_from[victim_id] = NPCClock.now()

func is_gift_blocked_from(giver_id: String) -> bool:
	return _snatch_cooldown_from.has(giver_id) \
		and NPCClock.now() - float(_snatch_cooldown_from[giver_id]) < SNATCH_GIFT_COOLDOWN_HOURS

func start_npc_snatch_pair_cooldown(other_id: String) -> void:
	_npc_snatch_pair_cooldown[other_id] = NPCClock.now()

func is_npc_snatch_pair_on_cooldown(other_id: String) -> bool:
	return _npc_snatch_pair_cooldown.has(other_id) \
		and NPCClock.now() - float(_npc_snatch_pair_cooldown[other_id]) < NPC_SNATCH_PAIR_COOLDOWN_HOURS

## Same interface as Player.get_held_item() so snatch code treats both alike.
func get_held_item() -> Node:
	return held_item

func _threshold_scaled_chance(value: float, threshold: float, extreme: float,
		chance_at_threshold: float, chance_at_extreme: float, direction: float) -> float:
	if (direction > 0.0 and value < threshold) or (direction < 0.0 and value > threshold):
		return 0.0
	var span: float = extreme - threshold
	if absf(span) < 0.0001:
		return chance_at_threshold
	return lerp(chance_at_threshold, chance_at_extreme, clampf((value - threshold) / span, 0.0, 1.0))

func get_snatch_chance_toward(target_id: String) -> float:
	return _threshold_scaled_chance(get_relationship(target_id), SNATCH_RELATIONSHIP_THRESHOLD,
		RELATIONSHIP_MIN, SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, -1.0)

## Deterministic eligibility (no roll) — lets Eat/Drink score > 0 when the
## only matching item is in a disliked person's hands.
func is_player_snatch_eligible(need_filter: Callable) -> bool:
	if get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD or social.is_cowed():
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_held_item"):
		return false
	var held: Node = player.get_held_item()
	return held != null and is_instance_valid(held) and need_filter.call(held)

func is_npc_snatch_eligible(need_filter: Callable) -> bool:
	if is_player_snatch_eligible(need_filter):
		return true
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not (other is NPC):
			continue
		if get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD:
			continue
		var held: Node = other.held_item
		if held != null and is_instance_valid(held) and need_filter.call(held):
			return true
	return false

## Nearest disliked person (player or NPC) holding a matching item, gated
## by one relationship-scaled roll. Called from Eat/Drink enter().
func find_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false
	var force_npc: bool = _debug_force_npc_snatch
	_debug_force_npc_snatch = false
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if forced:
		return player

	var best: Node3D = null
	var best_d: float = INF
	if not force_npc and player != null and player.has_method("get_held_item") \
			and get_relationship("player") <= SNATCH_RELATIONSHIP_THRESHOLD:
		var held: Node = player.get_held_item()
		if held != null and is_instance_valid(held) and need_filter.call(held):
			best_d = NPCItemUser.flat_distance(global_position, player.global_position)
			best = player
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not (other is NPC):
			continue
		if not force_npc and (get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD \
				or is_npc_snatch_pair_on_cooldown(other.npc_id)):
			continue
		var held2: Node = other.held_item
		if held2 == null or not is_instance_valid(held2) or not need_filter.call(held2):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	if best == null:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "no eligible disliked target holding a matching item")
		return null
	var target_id: String = "player" if best.is_in_group("player") else String(best.npc_id)
	if force_npc:
		return best
	var chance: float = get_snatch_chance_toward(target_id)
	var roll: float = randf()
	if NPCDebug.enabled:
		NPCDebug.log_snatch(self, "roll %s" % ("succeeded" if roll <= chance else "failed"),
			"target=%s chance=%.2f roll=%.2f" % [target_id, chance, roll])
	return best if roll <= chance else null

## F7 — force a snatch attempt against the player's held item.
func debug_force_snatch() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_held_item"):
		return false
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return false
	if NPCItemUser.is_edible(held):
		_debug_force_snatch = true
		brain.force_command(EatActivity.new())
		return true
	if NPCItemUser.is_drinkable_bottle(held):
		_debug_force_snatch = true
		brain.force_command(DrinkActivity.new())
		return true
	return false

## F7 — force a snatch against the nearest NPC holding food/water.
func debug_force_npc_snatch() -> bool:
	_debug_force_npc_snatch = true
	if find_snatch_target(Callable(NPCItemUser, "is_edible")) != null:
		_debug_force_npc_snatch = true
		brain.force_command(EatActivity.new())
		return true
	_debug_force_npc_snatch = true
	if find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle")) != null:
		_debug_force_npc_snatch = true
		brain.force_command(DrinkActivity.new())
		return true
	_debug_force_npc_snatch = false
	return false

# ─── Conversation ─────────────────────────────────────────────────────────
const TALK_RANGE: float = 3.0
## Friends will walk over to chat; everyone else only chats with whoever
## happens to be close.
const TALK_SEEK_RANGE: float = 12.0
const TALK_BASE_SCORE: float = 7.0
const TALK_COOLDOWN_MIN_HOURS: float = 0.5
const TALK_COOLDOWN_MAX_HOURS: float = 1.5
var _talk_cooldown_until: float = 0.0   ## NPCClock hours

func start_talk_cooldown() -> void:
	_talk_cooldown_until = NPCClock.now() + randf_range(TALK_COOLDOWN_MIN_HOURS, TALK_COOLDOWN_MAX_HOURS)

func is_talk_on_cooldown() -> bool:
	return NPCClock.now() < _talk_cooldown_until

## Mutual relationship (both directions averaged).
func mutual_relationship(other: Node) -> float:
	if other == null or not (other is NPC):
		return 0.0
	return (get_relationship(other.npc_id) + other.get_relationship(npc_id)) / 2.0

## How much this NPC wants to chat with `other` right now (idle-tier score).
func get_social_score(other: Node) -> float:
	var rel: float = mutual_relationship(other)
	var rel_mult: float = 1.0
	if rel > 15.0:
		rel_mult = lerp(1.0, 2.5, clampf((rel - 15.0) / 85.0, 0.0, 1.0))
	elif rel < -15.0:
		rel_mult = lerp(1.0, 0.2, clampf((-15.0 - rel) / 85.0, 0.0, 1.0))
	var lonely_mult: float = 1.5 if thoughts.has("lonely") else 1.0
	var social: float = lerp(0.7, 1.3, _trait("sociability"))
	return TALK_BASE_SCORE * rel_mult * social * lonely_mult * get_work_ethic_passive_mult()

## Friends talk longer.
func get_talk_length_mult(other: Node) -> float:
	return lerp(0.8, 1.5, clampf((mutual_relationship(other) + 20.0) / 120.0, 0.0, 1.0))

## Nearest free NPC in TALK_RANGE — or, for friends, within TALK_SEEK_RANGE
## (TalkActivity walks over first).
func find_talk_partner() -> Node:
	var best: Node = null
	var best_value: float = -INF
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not (other is NPC) or not other.is_available_to_talk():
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		var rel: float = mutual_relationship(other)
		var reach: float = TALK_SEEK_RANGE if rel >= 20.0 else TALK_RANGE
		if d > reach:
			continue
		var value: float = rel * 0.05 - d   ## prefer close, then liked
		if value > best_value:
			best_value = value
			best = other
	return best

func is_available_to_talk() -> bool:
	if brain == null or brain.is_relaxing() or brain.is_talking() or brain.is_sleeping() or crash.active():
		return false
	if is_talk_on_cooldown() or is_passed_out() or in_sit_sequence():
		return false
	return brain.is_current_interruptible() and not NPCItemUser.hands_full(self)

## Called on the partner by the initiator's TalkActivity.
func start_talk_session(initiator: NPC) -> bool:
	if not is_available_to_talk():
		return false
	brain.force_command(TalkActivity.new(initiator, false))
	return true

## Ends this NPC's side of a conversation (called by the other side).
func end_talk_session() -> void:
	if brain != null and brain.is_talking():
		brain.end_talk_if_talking()

## One shared conversation outcome for both participants. Chance of a good
## chat depends on how they already feel about each other, both moods,
## both tempers, and how compatible their personalities are.
func resolve_conversation(partner: NPC) -> void:
	var p_good: float = 0.55
	p_good += clampf(mutual_relationship(partner) / 200.0, -0.25, 0.25)
	p_good += ((mood + partner.mood) / 2.0 - 60.0) / 250.0
	p_good -= (irritability + partner.irritability) / 400.0
	p_good += _compatibility(partner) * 0.15
	p_good = clampf(p_good, 0.1, 0.9)
	var good: bool = randf() < p_good
	var magnitude: float = randf_range(1.0, 3.0)
	for pair: Array in [[self, partner], [partner, self]]:
		var a: NPC = pair[0]
		var b: NPC = pair[1]
		a.bonds.relate(b.npc_id, magnitude if good else -magnitude,
			"had a good talk with me" if good else "got into an argument with me")
		a.add_thought("good_chat" if good else "bad_chat", b.npc_name)
		a._last_social_time = NPCClock.now()

## -1..1 — shared outlook (optimism) and energy (sociability) help; two
## irritable people grate on each other.
func _compatibility(other: NPC) -> float:
	var c: float = 0.0
	c += 0.5 - absf(_trait("optimism") - other._trait("optimism"))
	c += ((_trait("sociability") + other._trait("sociability")) / 2.0 - 0.5)
	if has_irritable_trait() and other.has_irritable_trait():
		c -= 0.6
	return clampf(c, -1.0, 1.0)

# ─── Give-to-Friend ───────────────────────────────────────────────────────
const GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD: float = 25.0
const GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD: float = 0.05
const GIVE_TO_FRIEND_CHANCE_AT_MAX: float = 0.5
const GIVE_TO_FRIEND_BASE_SCORE: float = 12.0

func get_give_to_friend_chance(rel: float) -> float:
	return _threshold_scaled_chance(rel, GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD,
		RELATIONSHIP_MAX, GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD, GIVE_TO_FRIEND_CHANCE_AT_MAX, 1.0)

func _is_needy(other: Node) -> bool:
	return float(other.hunger) < NEED_LOW or float(other.thirst) < NEED_LOW

## Cheap, deterministic — used by GiveToFriendActivity.score().
func has_needy_friend() -> bool:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other != self and other is NPC and get_relationship(other.npc_id) >= GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD \
				and _is_needy(other):
			return true
	return false

## Nearest needy friend + a matching loose item, gated by one roll.
func find_friend_to_help() -> Dictionary:
	var best: NPC = null
	var best_d: float = INF
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not (other is NPC) or get_relationship(other.npc_id) < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD \
				or not _is_needy(other):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	if best == null:
		return {}
	var need_filter: Callable = Callable(NPCItemUser, "is_edible") if best.hunger <= best.thirst \
		else Callable(NPCItemUser, "is_drinkable_bottle")
	var item: Node = NPCItemUser.find_loose_item(self, need_filter)
	if item == null:
		return {}
	var forced_give: bool = _debug_force_give
	_debug_force_give = false
	if not forced_give and randf() > get_give_to_friend_chance(get_relationship(best.npc_id)):
		return {}
	return {"friend": best, "item": item}

## F7 — force a talk / a give-to-friend through the normal activity paths.
func debug_force_talk() -> bool:
	if find_talk_partner() == null:
		return false
	brain.force_command(TalkActivity.new())
	return true

func debug_force_give_to_friend() -> bool:
	if not has_needy_friend():
		return false
	_debug_force_give = true
	brain.force_command(GiveToFriendActivity.new())
	return true

# ─── Jobs (facade for the talk-menu UI) ───────────────────────────────────
## Refuel gate for autonomous work (sessions top off everything < 100%).
const REFUEL_URGENT_BELOW: float = 40.0

## Specific reasons a job can't run, mapped to player text by NPCTalkMenuUI.
func get_cleaning_unavailable_reason() -> String:
	return NPCJobQueries.get_cleaning_unavailable_reason(self)

func get_refuel_unavailable_reason() -> String:
	return NPCJobQueries.get_refuel_unavailable_reason(self)

func get_cooking_unavailable_reason() -> String:
	return NPCJobQueries.get_cooking_unavailable_reason(self)

func is_trash_item(item: Node) -> bool:
	return NPCJobQueries.is_trash_item(self, item)

# ─── Skills — 0.6..2.0; bias job choice, speed up work; grow with use ─────
var skills: Dictionary = {
	"farming": 1.0, "plumbing": 1.0, "electrical": 1.0, "construction": 1.0, "cooking": 1.0,
}

func randomize_skills() -> void:
	for k: String in skills.keys():
		skills[k] = randf_range(0.6, 1.4)

func gain_skill(key: String, amount: float = 0.01) -> void:
	if skills.has(key):
		skills[key] = minf(2.0, float(skills[key]) + amount)

## Called by jobs when a unit of work lands — grows the skill and, for
## residents who take pride in work, lifts the mood a little.
func on_work_done(skill_key: String = "") -> void:
	_last_work_done_at = NPCClock.now()
	if skill_key != "":
		gain_skill(skill_key)
	## Working alongside someone slowly builds a bond (summed into the
	## daily "Time together" line, not logged per task).
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other != self and other is NPC and other.brain != null and other.brain.current_activity() != null \
				and other.brain.current_activity().is_work() \
				and NPCItemUser.flat_distance(other.global_position, global_position) < 6.0:
			bonds.relate(other.npc_id, 0.3, "worked alongside me")
			other.bonds.relate(npc_id, 0.3, "worked alongside me")
	if _trait("work_ethic") >= 0.5:
		add_thought("productive")

# ─── Relaxing ─────────────────────────────────────────────────────────────
## Daily relax budget (game hours), with randomized gaps between sessions
## so breaks spread through the day instead of chaining.
const RELAX_BUDGET_BASELINE: float = 3.0
const RELAX_BUDGET_LAZY: float = 6.0
const RELAX_MIN_GAP_HOURS: float = 1.5
const RELAX_MAX_GAP_HOURS: float = 3.0
var _relax_cooldown_hours: float = 0.0
var _relax_time_used_today: float = 0.0
var _relax_day_clock: float = 0.0
var _relax_job_request_count: int = 0

func get_relax_daily_budget() -> float:
	return RELAX_BUDGET_LAZY if has_lazy_trait() else RELAX_BUDGET_BASELINE

func get_relax_time_remaining_today() -> float:
	return maxf(0.0, get_relax_daily_budget() - _relax_time_used_today)

func is_relax_on_cooldown() -> bool:
	return _relax_cooldown_hours > 0.0

func start_relax_cooldown() -> void:
	_relax_cooldown_hours = randf_range(RELAX_MIN_GAP_HOURS, RELAX_MAX_GAP_HOURS)

func spend_relax_time(h: float) -> void:
	_relax_time_used_today += h

func is_relaxing() -> bool:
	return brain != null and brain.is_relaxing()

func reset_relax_job_requests() -> void:
	_relax_job_request_count = 0

func _tick_relax_day(h: float) -> void:
	_relax_day_clock += h
	if _relax_day_clock >= 24.0:
		_relax_day_clock = fmod(_relax_day_clock, 24.0)
		_relax_time_used_today = 0.0
	_relax_cooldown_hours = maxf(0.0, _relax_cooldown_hours - h)

## First job request during a break is refused; the second complies at a
## small relationship cost.
func request_job_while_relaxing() -> bool:
	_relax_job_request_count += 1
	if _relax_job_request_count <= 1:
		return false
	bonds.relate("player", -3.0, "pulled me off my break to work")
	add_thought("break_interrupted")
	return true

func get_relaxing_refusal_line() -> String:
	return NPCDialogue.relaxing_refusal()

# ─── Dialogue (see NPCDialogue.gd) ────────────────────────────────────────
func get_dialogue_line() -> String:
	return NPCDialogue.greeting(self)

func get_relationship_dialogue_line(target_id: String) -> String:
	return NPCDialogue.about(self, target_id)

## Other live NPCs, for the talk menu's "Ask about" buttons.
func get_other_npc_topics() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other != self and other is NPC:
			out.append({"id": String(other.npc_id), "name": String(other.npc_name)})
	return out

## Current thoughts for the resident panel: [{"text", "mood"}], strongest first.
func get_thought_summaries() -> Array[Dictionary]:
	return thoughts.describe()

# ─── Lifecycle ────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")

	if npc_id == "":
		npc_id = "npc_%d" % _next_npc_id
		_next_npc_id += 1
	NPC._register_id(npc_id)
	if npc_name == "Survivor":
		_assign_random_name()

	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	## Path points sit on the floor (y≈0.5) while this node's origin is the
	## capsule CENTER — desired distances must exceed that vertical offset
	## or no waypoint can ever register as reached.
	nav_agent.path_desired_distance = 1.1
	nav_agent.target_desired_distance = 1.1
	nav_agent.path_max_distance = 3.0
	nav_agent.radius = 0.4               ## matches BunkerNavMesh.agent_radius
	nav_agent.avoidance_enabled = true   ## routes around heavy items' obstacles and other NPCs
	## Godot's defaults suit big outdoor crowds. In a bunker room, weighing
	## agents 50 m away (and a 1 s horizon against obstacles of 0 s) made
	## residents slow down and swerve for people nowhere near them.
	nav_agent.neighbor_distance = 5.0
	nav_agent.max_neighbors = 12
	nav_agent.time_horizon_agents = 1.5
	nav_agent.time_horizon_obstacles = 1.0
	nav_agent.avoidance_priority = AVOIDANCE_PRIORITY_STATIONARY
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(nav_agent)

	hold_point = Node3D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(0.0, 0.9, -0.8)
	add_child(hold_point)

	if not _restored:
		generation_seed = randi()
		randomize_personality()
		randomize_skills()
		randomize_age()
		_birthday_day_of_year = randi_range(1, 365)
		_birthday_last_checked_day = NPCClock.day()
		chronotype = randf_range(-1.5, 1.5)
		_relax_cooldown_hours = randf_range(1.0, RELAX_MIN_GAP_HOURS)

	brain = NPCBrain.new()
	brain.setup(self)
	stuck.setup(self)
	morale_sys.setup(self)
	bonds.setup(self)
	social.setup(self)
	crash.setup(self)
	combat.setup(self)
	if not morale_sys._loaded:
		mood = morale_sys.morale   ## fresh resident; a loaded one keeps its saved mood
	_mood_tick_timer = randf() * MOOD_TICK_INTERVAL   ## stagger across NPCs

	medical = NPCMedical.new()
	medical.name = "NPCMedical"
	add_child(medical)
	medical.setup(self)
	if not _pending_medical_save.is_empty():
		medical.from_save(_pending_medical_save)
		_pending_medical_save = []
	combat.apply_loaded_death()   ## a saved body stays a body

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
	## An activity released a chair/bed but asked us to finish the stand-up
	## animation before moving. The model's stand-up ends wherever the clip
	## leaves the body, so settle there (navmesh-snapped) rather than at the
	## activity's requested spot — no visible pop.
	if _stand_pos_pending and not in_sit_sequence():
		_stand_pos_pending = false
		var model: Node = get_node_or_null("CharacterModel")
		var body_pos: Vector3 = model.get_stand_end_position() \
			if model != null and model.has_method("get_stand_end_position") else Vector3.INF
		place_standing_at(body_pos if body_pos != Vector3.INF else _pending_stand_pos)

	if combat.dead:
		## A body: no needs, no brain — just gravity (the model plays the dying clip).
		if not is_on_floor():
			velocity.y -= _gravity * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if health <= 0.0:
		combat.check_neglect_death()
		return
	var prof: bool = NPCDebug.profile
	var t: int = Time.get_ticks_usec() if prof else 0
	if prof:
		NPCDebug.prof_frames += 1
	_validate_held_item()
	_tick_needs(delta)
	_tick_social_and_mood(delta)
	if prof:
		t = NPCDebug.prof_lap("needs+social", t)
	_steered_this_frame = false
	if brain != null:
		brain.tick(delta)
	if not _steered_this_frame:
		_publish_stationary()   ## nobody walked us this frame — don't leave a stale velocity for others to dodge
	if prof:
		t = NPCDebug.prof_lap("brain+activity", t)

	## While mid sit/lie sequence the model controller owns the position
	## (eased approach → seat); gravity and move_and_slide would fight it.
	if in_sit_sequence():
		_publish_stationary()
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	if not _movement_locked:
		var real: Vector3 = get_real_velocity()
		_turn_toward_travel(Vector2(real.x, real.z), delta)
	if prof:
		t = NPCDebug.prof_lap("move_and_slide", t)
	_handle_physics_pushes(delta)
	if prof:
		t = NPCDebug.prof_lap("physics_pushes", t)
	stuck.tick(delta)
	if prof:
		NPCDebug.prof_lap("stuck_recovery", t)

## The item in hand must actually be in THIS NPC's hand. An item knocked
## out of the carry (a bump, a wall), consumed, freed, or grabbed by someone
## else used to leave a stale held_item behind — the NPC then "carried"
## nothing forever and every activity that checks hands misbehaved.
func _validate_held_item() -> void:
	if held_item == null:
		return
	if not is_instance_valid(held_item) or held_item.is_queued_for_deletion():
		held_item = null
		return
	var in_hand: bool = true
	if "is_held" in held_item and not held_item.is_held:
		in_hand = false
	elif "_hold_point" in held_item and held_item._hold_point != hold_point:
		in_hand = false
	if not in_hand:
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(self, "lost held item", "%s is no longer in hand — clearing reference" % NPCSessionActivity.display_name(held_item))
		NPCItemUser.release_item(held_item)
		held_item = null

## Real-seconds → game-hours via the shared compressed clock.
func game_hours(delta: float) -> float:
	return NPCClock.game_hours(delta)

func _tick_needs(delta: float) -> void:
	var h: float = game_hours(delta)
	if h <= 0.0:
		return
	var energy_drain: float = ENERGY_DRAIN_PER_GAME_HOUR
	energy = clampf(energy - energy_drain * h, 0.0, energy_cap)
	hunger = clampf(hunger - HUNGER_DRAIN_PER_GAME_HOUR * h, 0.0, hunger_cap)
	thirst = clampf(thirst - THIRST_DRAIN_PER_GAME_HOUR * h, 0.0, thirst_cap)
	var health_drain: float = 0.0
	if hunger <= 0.0:
		health_drain += HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR
	if thirst <= 0.0:
		health_drain += HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR
	if health_drain > 0.0:
		health = maxf(0.0, health - health_drain * h)

func is_passed_out() -> bool:
	return energy <= 0.0

# ─── Locomotion ───────────────────────────────────────────────────────────
var _movement_locked: bool = false
var _last_steer_delta: float = 0.0
var _requested_speed: float = 0.0

# ─── Doors ──────────────────────────────────────────────────────────────────
## BunkerDoor exposes a NavigationLink through the doorway, so routes may
## cross a closed door. Approaching one, a resident asks it to open and waits;
## NPCDoorCoordinator keeps opposite-direction residents from meeting inside
## the doorway. A door that won't open (the player keeps shutting it, a
## preview door) gives up after DOOR_GIVE_UP_SEC and the activity is dropped.
const NPC_DOOR_COORDINATOR: GDScript = preload("res://scripts/npc/NPCDoorCoordinator.gd")
const DOOR_GIVE_UP_SEC: float = 8.0
var _door_lease: Dictionary = {}
var _door_wait: float = 0.0
var door_blocked: bool = false
var _door_queued: bool = false

func is_waiting_at_door() -> bool:
	return _door_wait > 0.0

func _door_passage_allows(next_path_point: Vector3, delta: float) -> bool:
	var allowed: bool = _door_passage_check(next_path_point)
	if allowed:
		_door_wait = 0.0
		return true
	_door_wait += delta
	if NPCDebug.enabled and int(_door_wait) != int(_door_wait - delta):
		var dd: Node = get_tree().get_first_node_in_group("npc_bottleneck")
		print("[door] t=%.1f %s waiting %.0fs lease=%s pos=%s door_open=%s info=%s anim=%s req=%s" % [Time.get_ticks_msec() / 1000.0, npc_name, _door_wait, _door_lease.keys(), global_position.snapped(Vector3.ONE * 0.01),
			dd.is_open() if dd != null else "-", dd.get_npc_portal_info() if dd != null else {}, dd.get("_animating") if dd != null else "-", dd.get("_npc_open_requested") if dd != null else "-"])
	if _door_wait >= DOOR_GIVE_UP_SEC:
		_door_wait = 0.0
		_release_door_passage()
		door_blocked = true   ## NPCBrain abandons the activity at its next tick
		return false
	return false

func _door_passage_check(next_path_point: Vector3) -> bool:
	if not _door_lease.is_empty():
		var door_ref: WeakRef = _door_lease.get("door_ref") as WeakRef
		var door: Node3D = door_ref.get_ref() as Node3D if door_ref != null else null
		if Time.get_ticks_msec() >= int(_door_lease.get("expires", 0)) or door == null or not is_instance_valid(door):
			_release_door_passage()
		else:
			var info: Dictionary = door.get_npc_portal_info()
			var local: Vector3 = door.to_local(global_position)
			var direction: int = int(_door_lease.get("direction", 0))
			if local.x * direction >= float(info.get("exit_distance", 0.9)):
				_release_door_passage()   ## through
			elif not bool(info.get("open", false)):
				_release_door_passage()
				door.request_npc_open(self)
				return false
			else:
				return true
	var best_door: Node3D = null
	var best_direction: int = 0
	var best_plane: float = INF
	var target: Vector3 = nav_agent.target_position
	for candidate: Node in get_tree().get_nodes_in_group("npc_bottleneck"):
		if not (candidate is Node3D) or not candidate.has_method("get_npc_portal_info"):
			continue
		var door: Node3D = candidate as Node3D
		var info: Dictionary = door.get_npc_portal_info()
		var here: Vector3 = door.to_local(global_position)
		if absf(here.x) > float(info.get("wait_distance", 1.15)) or absf(here.z) > float(info.get("half_width", 0.9)) + 0.45:
			continue
		var target_local: Vector3 = door.to_local(target)
		var travel_x: float = target_local.x - here.x
		if absf(travel_x) < 0.2:
			travel_x = door.to_local(next_path_point).x - here.x
		var direction: int = 1 if travel_x > 0.0 else -1
		if here.x * direction >= 0.0 or target_local.x * direction <= 0.0:
			continue   ## route doesn't cross this door's plane
		if absf(here.x) < best_plane:
			best_plane = absf(here.x)
			best_door = door
			best_direction = direction
	if best_door == null:
		if _door_queued:
			_door_queued = false
			NPC_DOOR_COORDINATOR.release_owner(self)   ## no longer crossing — leave the line
		return true
	_door_queued = true
	if not bool(best_door.get_npc_portal_info().get("open", false)):
		if best_door.has_method("request_npc_open"):
			best_door.request_npc_open(self)
		return false
	_door_lease = NPC_DOOR_COORDINATOR.request(self, best_door, best_direction)
	return not _door_lease.is_empty()

func _exit_tree() -> void:
	_release_door_passage()

func _release_door_passage() -> void:
	if not _door_lease.is_empty():
		NPC_DOOR_COORDINATOR.release(_door_lease, self)
	NPC_DOOR_COORDINATOR.release_owner(self)   ## also drops a queued request
	_door_lease = {}
	_door_queued = false

## The chair/bed this NPC occupies, mirroring Player.gd so the shared
## AdventurerModelController drives the same sit / lie-down animations.
var seated_chair: Node3D = null
var sleeping_bed: Node3D = null

## The bed this resident thinks of as theirs (LieActivity goes back to it).
## Persisted by position; resolved lazily after a load.
var home_bed: Node = null:
	get:
		if home_bed == null and _home_bed_pos != Vector3.INF and is_inside_tree():
			for b: Node in get_tree().get_nodes_in_group("bed"):
				if b is Node3D and (b as Node3D).global_position.distance_to(_home_bed_pos) < 0.75:
					home_bed = b
					break
			_home_bed_pos = Vector3.INF
		return home_bed
var _home_bed_pos: Vector3 = Vector3.INF

## Where to stand once the stand-up animation finishes (see _physics_process).
var _pending_stand_pos: Vector3 = Vector3.ZERO
var _stand_pos_pending: bool = false

## Stand up at `pos` once the stand-up animation finishes (or right away
## if no sit sequence is playing).
func request_stand_at(pos: Vector3) -> void:
	_pending_stand_pos = pos
	_stand_pos_pending = true

## Puts the NPC on its feet at the nearest walkable spot to `pos`, at real
## standing height. Furniture stand points are FLOOR-level positions; the
## old code assigned them straight to this node's origin (the capsule
## centre), burying half the body in the floor — physics then pushed the
## NPC down through it. That was how residents "fell out of the world"
## after sitting or sleeping.
func place_standing_at(pos: Vector3) -> void:
	var snapped: Vector3 = stuck.snap_to_navmesh(pos)
	if snapped == Vector3.INF:
		snapped = Vector3(pos.x, standing_height(), pos.z)
	global_position = snapped
	velocity = Vector3.ZERO
	stuck.reset()

## True while seated / in bed, or while the model is still playing the
## stand-up clip after leaving.
func in_sit_sequence() -> bool:
	if seated_chair != null or sleeping_bed != null:
		return true
	var model: Node = get_node_or_null("CharacterModel")
	if model != null and model.has_method("is_sit_sequence_active"):
		return model.is_sit_sequence_active()
	return false

func is_movement_locked() -> bool:
	return _movement_locked

## Point the agent at a world position (XZ; Y snapped to the floor plane).
func set_nav_target(world_pos: Vector3) -> void:
	if nav_agent != null:
		nav_agent.target_position = Vector3(world_pos.x, 0.5, world_pos.z)

func nav_finished() -> bool:
	return nav_agent == null or nav_agent.is_navigation_finished()

## Arrival at the END of the computed path counts as arrived even when the
## requested target lies beyond it (inside furniture, off the navmesh).
## Otherwise the agent never reports "finished", the last waypoint sits
## under the resident's feet, and steering toward it flips direction every
## frame — the resident spins on the spot.
const PATH_END_ARRIVE: float = 0.45
func _at_path_end() -> bool:
	if nav_agent.get_current_navigation_path().is_empty():
		return false
	return NPCItemUser.flat_distance(global_position, nav_agent.get_final_position()) < PATH_END_ARRIVE

func _finish_navigation() -> void:
	nav_agent.target_position = Vector3(global_position.x, 0.5, global_position.z)

## Forces a fresh path to the current target (stale path after a rebake).
func repath() -> void:
	if nav_agent != null:
		var t: Vector3 = nav_agent.target_position
		nav_agent.target_position = global_position
		nav_agent.target_position = t

## Steer toward the next waypoint. Submits a PREFERRED velocity; avoidance
## answers in _on_velocity_computed() with the safe one to apply.
func nav_steer(delta: float) -> void:
	_steered_this_frame = true
	_movement_locked = false
	_last_steer_delta = delta
	if nav_agent == null or nav_agent.is_navigation_finished():
		if not _door_lease.is_empty():
			_release_door_passage()
		_door_wait = 0.0
		_publish_stationary()
		_decelerate(delta)
		return
	var next: Vector3 = nav_agent.get_next_path_position()   ## also refreshes a dirty path
	if _at_path_end():
		_finish_navigation()
		_publish_stationary()
		_decelerate(delta)
		return
	if not _door_passage_allows(next, delta):
		halt_movement(delta)   ## movement lock also pauses stuck detection while queued
		return
	var dir: Vector3 = next - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_requested_speed = move_speed * get_status_speed_multiplier()
	nav_agent.max_speed = _requested_speed   ## avoidance may never return more than we asked for
	nav_agent.avoidance_priority = AVOIDANCE_PRIORITY_MOVING
	nav_agent.set_velocity(dir.normalized() * _requested_speed)
	_published_moving = true

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if _movement_locked:
		return   ## a stationary phase began after this request — stale
	## Cap at the requested pace: with the agent's default max_speed (10 m/s),
	## a retarget amid other agents could otherwise produce a brief surge.
	var safe_xz: Vector2 = Vector2(safe_velocity.x, safe_velocity.z).limit_length(_requested_speed)
	last_safe_speed = safe_xz.length()
	safe_velocity.x = safe_xz.x
	safe_velocity.z = safe_xz.y
	var w: float = minf(acceleration * _last_steer_delta, 1.0)
	velocity.x = lerp(velocity.x, safe_velocity.x, w)
	velocity.z = lerp(velocity.z, safe_velocity.z, w)

## Faces the way the resident ACTUALLY moved this frame (post-collision),
## at a human turn rate. Pressed against a wall or another resident they
## barely move, so they don't turn — the old code faced whatever avoidance
## suggested each frame, and a blocked resident flip-flopped between
## suggestions: the "spinning in a corner" look. Slow drift (< a third of
## walking pace) never turns the body, and the rate cap keeps any residual
## jitter far below a visible spin.
const TURN_RATE: float = 7.0   ## rad/s (~a full turn in 0.9 s)
func _turn_toward_travel(dir: Vector2, delta: float) -> void:
	if dir.length() < maxf(_requested_speed, 0.5) * 0.35:
		return
	var target_yaw: float = atan2(-dir.x, -dir.y)
	var diff: float = angle_difference(rotation.y, target_yaw)
	var step: float = diff * minf(12.0 * delta, 1.0)
	var max_step: float = TURN_RATE * delta
	rotation.y += clampf(step, -max_step, max_step)

func _decelerate(delta: float) -> void:
	var w: float = minf(acceleration * delta, 1.0)   ## never extrapolate (a >1 weight reverses velocity)
	velocity.x = lerp(velocity.x, 0.0, w)
	velocity.z = lerp(velocity.z, 0.0, w)

## Avoidance only knows what each agent last PUBLISHED. A resident who
## stopped without publishing a zero velocity kept "walking" in everyone
## else's prediction, so neighbours slowed and swerved around a ghost.
## Stationary residents also get right of way (walkers go around them).
const AVOIDANCE_PRIORITY_MOVING: float = 0.5
const AVOIDANCE_PRIORITY_STATIONARY: float = 1.0
var _published_moving: bool = false
var last_safe_speed: float = 0.0   ## debug: speed avoidance granted last frame
var _steered_this_frame: bool = false

func _publish_stationary() -> void:
	if not _published_moving or nav_agent == null:
		return
	_published_moving = false
	_requested_speed = 0.0
	nav_agent.avoidance_priority = AVOIDANCE_PRIORITY_STATIONARY
	nav_agent.set_velocity(Vector3.ZERO)

## Decelerate to a stop; raises the movement lock so a late avoidance
## callback can't overwrite the halt with a stale travel velocity.
func halt_movement(delta: float) -> void:
	_publish_stationary()
	_movement_locked = true
	_decelerate(delta)

## One-time hard stop (sitting down, lying down, talking).
func lock_movement() -> void:
	_publish_stationary()
	_movement_locked = true
	velocity.x = 0.0
	velocity.z = 0.0

## Close-quarters footwork (fighting): walk straight toward `target`
## and settle at `stop_at` metres from it, easing off as the gap closes;
## step back a little if crowded. Bypasses the navmesh and avoidance
## (they'd steer around the very person being approached) and leaves
## facing to the caller (face_toward), so the body doesn't turn with the
## small corrective steps. Only for short distances in open floor.
func steer_direct(target: Vector3, stop_at: float, delta: float) -> void:
	_steered_this_frame = true
	_movement_locked = true   ## ignore stale avoidance answers; facing is the caller's
	var to: Vector3 = target - global_position
	to.y = 0.0
	var dist: float = to.length()
	var gap: float = dist - stop_at
	var want: Vector3 = Vector3.ZERO
	if dist > 0.01:
		var pace: float = move_speed * get_status_speed_multiplier()
		if gap > 0.05:
			want = to / dist * pace * clampf(gap / 0.6, 0.2, 1.0)
		elif gap < -0.12:
			want = -to / dist * minf(0.6, pace * 0.5)   ## crowded: ease back
	var w: float = minf(acceleration * delta, 1.0)
	velocity.x = lerp(velocity.x, want.x, w)
	velocity.z = lerp(velocity.z, want.z, w)
	if nav_agent != null:
		## Others still avoid us; our own avoidance answer is ignored (locked).
		nav_agent.avoidance_priority = AVOIDANCE_PRIORITY_MOVING
		nav_agent.set_velocity(Vector3(velocity.x, 0.0, velocity.z))
		_published_moving = want != Vector3.ZERO
		_requested_speed = want.length()

## Smoothly turn to face a world point (weight 1.0 = snap).
func face_toward(world_pos: Vector3, weight: float) -> void:
	var d: Vector3 = world_pos - global_position
	d.y = 0.0
	if d.length() < 0.4:
		return   ## something underfoot: its bearing flips as we shift — don't chase it (spin)
	var target_yaw: float = atan2(-d.x, -d.z)
	if weight >= 0.999:
		rotation.y = target_yaw   ## deliberate one-shot facing (arriving at a job)
		return
	## Gradual facing is capped at a human turn rate so repeated re-facing
	## (tracking someone walking around) can't whip the body around.
	var diff: float = angle_difference(rotation.y, target_yaw) * clampf(weight, 0.0, 1.0)
	var max_step: float = TURN_RATE * get_physics_process_delta_time() * 1.5
	rotation.y += clampf(diff, -max_step, max_step)

## Travel speed the NPC should currently achieve (for stall detection).
func get_expected_travel_speed() -> float:
	return move_speed * get_status_speed_multiplier()

## Capsule-centre height when standing on the bunker floor.
func standing_height() -> float:
	var shape: Shape3D = collision.shape if collision != null else null
	var half: float = 1.0
	if shape is CapsuleShape3D:
		half = (shape as CapsuleShape3D).height * 0.5
	return NPCStuckRecovery.FLOOR_Y + half + collision.position.y if collision != null else 1.5

## Stuck recovery: may this NPC clear `item` out of its own way right now?
func can_clear_obstruction(item: RigidBody3D) -> bool:
	return not NPCItemUser.hands_full(self) and not job_state.is_cleaning_blacklisted(item.get_instance_id()) \
		and (brain == null or brain.is_current_interruptible())

## Abandons whatever this NPC is doing and benches that activity for a bit.
func abandon_current_activity(reason: String, bench_seconds: float) -> void:
	if brain != null:
		brain.abandon_current(reason, bench_seconds)

# ─── Physics clutter push-through ─────────────────────────────────────────
## Light loose items (cans, bottles, produce) have no nav obstacle and are
## meant to be walked through: shove them aside. Heavy items have obstacles
## and are routed around; if one is still touched, a token shove only.
const LIGHT_PUSH_IMPULSE: float = 1.5
const HEAVY_PUSH_MASS: float = 3.0

func _handle_physics_pushes(delta: float) -> void:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if not (body is RigidBody3D) or (("is_held" in body) and body.is_held):
			continue
		var rb: RigidBody3D = body as RigidBody3D
		var away: Vector3 = -col.get_normal()
		away.y = 0.0
		if away.length() <= 0.01:
			continue
		if rb.mass < HEAVY_PUSH_MASS:
			rb.apply_central_impulse(away.normalized() * LIGHT_PUSH_IMPULSE)
			var blocked: Vector3 = velocity - get_real_velocity()
			blocked.y = 0.0
			if blocked.length() > 0.01:
				var step: Vector3 = blocked * delta
				if not test_move(global_transform, step):
					global_position += step
		else:
			rb.apply_central_impulse(away.normalized() * LIGHT_PUSH_IMPULSE / rb.mass)

# ─── Status: speed, forgetfulness, labels ─────────────────────────────────
## Each factor multiplies; low on several things at once compounds.
func get_status_speed_multiplier() -> float:
	var energy_mult: float = 0.65 if energy < 25.0 else (0.85 if energy < 50.0 else 1.0)
	var hunger_mult: float = 0.90 if hunger < 25.0 else 1.0
	var thirst_mult: float = 0.90 if thirst < 25.0 else 1.0
	var mood_mult: float = 0.85 if mood <= 25.0 else 1.0
	var medical_mult: float = medical.get_medical_speed_multiplier() if medical != null else 1.0
	var adrenaline: float = RUN_MULT if combat.is_fleeing() or combat.rushing else 1.0   ## running for it / charging in
	return energy_mult * hunger_mult * thirst_mult * mood_mult * get_age_speed_mult() * medical_mult * adrenaline

## Chance to divert from a job into forgetful wandering: averaged across
## hunger/thirst/mood/energy tiers, scaled by resilience.
func get_forgetfulness_chance() -> float:
	var avg: float = (_need_forget_tier(hunger) + _need_forget_tier(thirst)
		+ _tier(mood, [0.25, 0.12, 0.05]) + _tier(energy, [0.15, 0.08, 0.03])) / 4.0
	return clampf(avg * _irritability_trait_mult(), 0.0, 1.0)

func _need_forget_tier(v: float) -> float:
	return _tier(v, [0.45, 0.20, 0.08])

func _tier(v: float, chances: Array) -> float:
	if v <= 0.0:
		return chances[0]
	elif v < 25.0:
		return chances[1]
	elif v < 50.0:
		return chances[2]
	return 0.0

func _forgetfulness_reasons() -> Array[String]:
	var reasons: Array[String] = []
	_reason(reasons, hunger, ["Starving", "Very Hungry", "Hungry"])
	_reason(reasons, thirst, ["Dehydrated", "Very Thirsty", "Mildly Dehydrated"])
	_reason(reasons, energy, ["Exhausted", "Very Tired", "Low Energy"])
	_reason(reasons, mood, ["Miserable", "Very Unhappy", "Unhappy"])
	return reasons

func _reason(out: Array[String], v: float, words: Array) -> void:
	if v <= 0.0:
		out.append(words[0])
	elif v < 25.0:
		out.append(words[1])
	elif v < 50.0:
		out.append(words[2])

func _slow_reasons() -> Array[String]:
	var reasons: Array[String] = []
	if energy < 25.0: reasons.append("Very Tired")
	elif energy < 50.0: reasons.append("Tired")
	if hunger < 25.0: reasons.append("Very Hungry")
	if thirst < 25.0: reasons.append("Very Thirsty")
	if mood <= 25.0: reasons.append("Very Low Mood")
	if is_elder(): reasons.append("Age")
	if medical != null and medical.get_medical_speed_multiplier() < 1.0: reasons.append("Injured")
	return reasons

## Human-readable status for the resident panel — display only.
func get_status_labels() -> Array[String]:
	var labels: Array[String] = []
	if is_passed_out():
		labels.append("Passed out (exhausted)")
	elif brain != null and brain.is_sleeping():
		labels.append("Asleep")
	else:
		var slow_mult: float = get_status_speed_multiplier()
		if slow_mult < 1.0:
			var reasons: Array[String] = _slow_reasons()
			if not reasons.is_empty():
				labels.append("%s (%s)" % ["Noticeably Slowed" if slow_mult <= 0.65 else "Slightly Slowed", ", ".join(reasons)])
	var forget_chance: float = get_forgetfulness_chance()
	var forget_reasons: Array[String] = _forgetfulness_reasons()
	if not forget_reasons.is_empty() and forget_chance > 0.0:
		var word: String = "Very Forgetful" if forget_chance >= 0.25 else ("Forgetful" if forget_chance >= 0.12 else "Occasionally Forgetful")
		labels.append("%s (%s)" % [word, ", ".join(forget_reasons)])
	if hunger <= 0.0 or thirst <= 0.0:
		labels.append("Losing health (starving/dehydrated)")
	var irr_label: String = get_irritability_label()
	if irr_label != "":
		labels.append("%s (%.0f%%)" % [irr_label, irritability] if NPCDebug.enabled else irr_label)
	if labels.is_empty():
		labels.append("Doing fine")
	return labels

# ─── Interaction ──────────────────────────────────────────────────────────
func get_interact_prompt() -> String:
	return "[E] Talk to %s" % npc_name

func on_interact() -> void:
	_open_talk_menu()

var _talk_menu: CanvasLayer = null

func _open_talk_menu() -> void:
	if _talk_menu == null or not is_instance_valid(_talk_menu):
		var ui_script: GDScript = load("res://scripts/ui/npc/NPCTalkMenuUI.gd")
		if ui_script == null:
			push_warning("[NPC] NPCTalkMenuUI.gd not found")
			return
		_talk_menu = CanvasLayer.new()
		_talk_menu.set_script(ui_script)
		_talk_menu.name = "NPCTalkMenuUI"
		get_tree().get_root().add_child(_talk_menu)
	if _talk_menu.has_method("open"):
		_talk_menu.open(npc_name, self)

# ─── Overhead: name/activity, speech/sleep indicator, work banner ─────────
## Work banner facade — registers with the shared InteractPrompt renderer so
## NPC and player job cards are the same real UI.
var _work_prompt_renderer: Node = null
var _work_banner_visible: bool = false

func show_work_banner() -> void:
	_work_banner_visible = true

func update_work_banner(action: String, progress: float) -> void:
	if not _work_banner_visible:
		return
	var renderer: Node = _get_work_prompt_renderer()
	if renderer != null and renderer.has_method("set_world_job"):
		renderer.call("set_world_job", self, action, progress)

func hide_work_banner() -> void:
	if not _work_banner_visible:
		return
	_work_banner_visible = false
	var renderer: Node = _get_work_prompt_renderer()
	if renderer != null and renderer.has_method("clear_world_job"):
		renderer.call("clear_world_job", self)

func _get_work_prompt_renderer() -> Node:
	if _work_prompt_renderer == null or not is_instance_valid(_work_prompt_renderer):
		_work_prompt_renderer = get_tree().get_first_node_in_group("interact_prompt")
	return _work_prompt_renderer

## DEBUG nameplate ("Name — Activity"). A development overlay only — not
## part of the shipping look (NPCDebug.show_nameplates turns it off). It
## steps aside whenever a speech bubble is up so the two never stack.
var _overhead_label: Label3D = null
var _overhead_timer: float = 0.0
var _speaking: bool = false
var _bubble: NPCSpeechBubble = null

## TalkActivity turn-taking: a small "typing" pill over whoever holds the
## floor when they aren't saying a readable line.
func set_speaking(on: bool) -> void:
	_speaking = on

func _get_bubble() -> NPCSpeechBubble:
	if _bubble == null:
		_bubble = NPCSpeechBubble.new()
		_bubble.name = "SpeechBubble"
		add_child(_bubble)
		_bubble.setup(self)
	return _bubble

# ─── Barks — short floating speech lines ──────────────────────────────────
## Event barks (bark()) are rate-limited per NPC; the ambient greeting when
## the player walks up has its own longer cooldown (game time) so walking
## past the same resident doesn't repeat itself.
const BARK_DURATION: float = 3.2
const BARK_MIN_GAP_SEC: float = 6.0
const GREET_RANGE: float = 3.2
const GREET_COOLDOWN_HOURS: float = 1.0
var _last_bark_msec: int = -100000
var _last_greet_hours: float = -100.0
var _greet_check: float = 0.0

func bark(text: String, force: bool = false) -> void:
	if combat.dead:
		return
	if text == "" or (brain != null and brain.is_sleeping() and not force):
		return
	if not force and Time.get_ticks_msec() - _last_bark_msec < int(BARK_MIN_GAP_SEC * 1000.0):
		return
	_last_bark_msec = Time.get_ticks_msec()
	_get_bubble().say(text, BARK_DURATION)

## A conversation line: not rate-limited like event barks (TalkActivity
## paces turns itself).
func say_line(text: String) -> void:
	if text != "":
		_get_bubble().say(text, BARK_DURATION)

func bark_event(kind: String, subject: String = "") -> void:
	bark(NPCDialogue.bark_line(kind, subject))

func _update_bark(delta: float) -> void:
	## Ambient greeting: the player walks up to an idle-ish resident.
	_greet_check -= delta
	if _greet_check > 0.0:
		return
	_greet_check = 0.5
	if brain == null or not brain.is_current_interruptible() or brain.is_talking() or brain.is_sleeping():
		return
	if NPCClock.now() - _last_greet_hours < GREET_COOLDOWN_HOURS:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or NPCItemUser.flat_distance(global_position, player.global_position) > GREET_RANGE:
		return
	_last_greet_hours = NPCClock.now()
	if randf() < 0.7:
		bark(NPCDialogue.greeting_bark(self))

func _process(delta: float) -> void:
	var t: int = Time.get_ticks_usec() if NPCDebug.profile else 0
	_process_overhead(delta)
	if NPCDebug.profile:
		NPCDebug.prof_lap("overhead(_process)", t)

func _process_overhead(delta: float) -> void:
	var bubble: NPCSpeechBubble = _get_bubble()
	bubble.set_sleeping(brain != null and (brain.is_sleeping() or is_passed_out()))
	bubble.set_typing(_speaking)
	bubble.tick(delta)
	_update_bark(delta)
	_update_debug_nameplate(delta, bubble.is_showing())
	_update_combat_debug_label(delta)

func _update_debug_nameplate(delta: float, bubble_up: bool) -> void:
	if not NPCDebug.show_nameplates:
		if _overhead_label != null:
			_overhead_label.visible = false
		_update_relationship_debug_label()
		return
	if _overhead_label == null:
		_overhead_label = _make_label3d(26, 6, Vector3(0.0, 1.85, 0.0), Color(0.70, 0.73, 0.76, 0.8), 0.0006)
	## Fade out of the way while a bubble is up.
	var target_a: float = 0.0 if bubble_up else 0.8
	_overhead_label.modulate.a = move_toward(_overhead_label.modulate.a, target_a, delta * 4.0)
	_overhead_label.visible = _overhead_label.modulate.a > 0.01
	_overhead_timer -= delta
	if _overhead_timer > 0.0:
		return
	_overhead_timer = 0.5
	_overhead_label.text = "%s — %s" % [npc_name, brain.current_label() if brain != null else "Idle"]
	_update_relationship_debug_label()

func _make_label3d(font_size: int, outline: int, pos: Vector3, color: Color, pixel: float) -> Label3D:
	var l: Label3D = Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = pixel
	l.font_size = font_size
	l.outline_size = outline
	l.position = pos
	l.modulate = color
	add_child(l)
	return l

## Debug-only combat readout (F7 NPC COMBAT → overlay): health, crash-out
## tier and phase, who they're attacking/fleeing/stopping, shunning, fear.
var _combat_debug_label: Label3D = null
var _combat_debug_timer: float = 0.0

func _update_combat_debug_label(delta: float) -> void:
	if not NPCCombatDebug.overlay:
		if _combat_debug_label != null:
			_combat_debug_label.visible = false
		return
	if _combat_debug_label == null:
		_combat_debug_label = _make_label3d(26, 6, Vector3(0.0, 2.1, 0.0), Color(1.0, 0.72, 0.45, 0.95), 0.0006)
	_combat_debug_label.visible = true
	_combat_debug_timer -= delta
	if _combat_debug_timer > 0.0:
		return
	_combat_debug_timer = 0.25
	_combat_debug_label.text = NPCCombatDebug.state_line(self)

## Debug-only floating readout of relationships (NPCDebug.enabled).
var _relationship_debug_label: Label3D = null

func _update_relationship_debug_label() -> void:
	if not NPCDebug.enabled:
		if _relationship_debug_label != null:
			_relationship_debug_label.visible = false
		return
	if _relationship_debug_label == null:
		_relationship_debug_label = _make_label3d(28, 6, Vector3(0.0, 2.35, 0.0), Color(0.55, 0.85, 1.0, 0.95), 0.0006)
	_relationship_debug_label.visible = true
	var lines: Array[String] = []
	for target_id: String in relationships.keys():
		var display: String = "You" if target_id == "player" else _name_for_relationship_id(target_id)
		lines.append("%s: %+.0f (%s)" % [display, relationships[target_id], get_relationship_label(target_id)])
	if gift_saturation > 0.0:
		lines.append("Gift burnout: %d%%" % int(round(gift_saturation * 100.0)))
	lines.append("mood %.0f → %.0f | %s" % [mood, get_mood_target(), brain.last_switch_reason if brain != null else ""])
	_relationship_debug_label.text = "\n".join(lines)

func _name_for_relationship_id(target_id: String) -> String:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other is NPC and String(other.npc_id) == target_id:
			return String(other.npc_name)
	return target_id

# ─── Persistence ──────────────────────────────────────────────────────────
## Everything that makes this resident THEM survives a save/load (Sep 2026 —
## previously personality, age, health, medical conditions, the action log
## and more were silently re-rolled or reset on every load).
func get_save_dict() -> Dictionary:
	var log_out: Array = []
	for e: Dictionary in _action_log:
		log_out.append({"text": e.get("text", ""), "stamp_hours": e.get("stamp_hours", NPCClock.now()),
			"game_time": e.get("game_time", ""), "kind": e.get("kind", "")})
	return {
		"pos": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
		"rot_y": rotation.y,
		"name": npc_name, "npc_id": npc_id, "seed": generation_seed,
		"energy": energy, "hunger": hunger, "thirst": thirst, "health": health,
		"mood": mood, "irritability": irritability,
		"personality": personality.duplicate(), "skills": skills.duplicate(),
		"age": age, "birthday": _birthday_day_of_year, "birthday_checked": _birthday_last_checked_day,
		"chronotype": chronotype,
		"relationships": relationships.duplicate(),
		"contagion_exposure": _contagion_exposure.duplicate(),
		"gift_saturation": gift_saturation,
		"relax_used": _relax_time_used_today, "relax_day_clock": _relax_day_clock,
		"relax_cooldown": _relax_cooldown_hours,
		"talk_cooldown_until": _talk_cooldown_until,
		"last_social_time": _last_social_time,
		"snatch_cooldowns": _snatch_cooldown_from.duplicate(),
		"snatch_pair_cooldowns": _npc_snatch_pair_cooldown.duplicate(),
		"thoughts": thoughts.to_save(),
		"morale": morale_sys.to_save(),
		"bonds": bonds.to_save(),
		"social": social.to_save(),
		"crash": crash.to_save(),
		"combat": combat.to_save(),
		"action_log": log_out,
		"last_irritability_label": _last_irritability_label,
		"last_player_rel_label": _last_player_relationship_label,
		"medical": medical.to_save() if medical != null else [],
		"gender": String(get_meta("_adventurer_random_gender", "")),
		"home_bed_pos": _vec_dict((home_bed as Node3D).global_position) if home_bed != null and is_instance_valid(home_bed) else {},
	}

static func _vec_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

var _pending_medical_save: Array = []

## Call BEFORE add_child() so _ready() keeps the restored identity. Missing
## keys (older saves) fall back to fresh values.
func apply_save_dict(d: Dictionary) -> void:
	_restored = true
	var p: Dictionary = d.get("pos", {})
	position = Vector3(float(p.get("x", 0.0)), float(p.get("y", 1.5)), float(p.get("z", 0.0)))
	rotation.y = float(d.get("rot_y", 0.0))
	npc_name = String(d.get("name", npc_name))
	npc_id = String(d.get("npc_id", ""))
	NPC._register_id(npc_id)
	generation_seed = int(d.get("seed", randi()))
	energy = float(d.get("energy", 100.0))
	hunger = float(d.get("hunger", 100.0))
	thirst = float(d.get("thirst", 100.0))
	health = float(d.get("health", 100.0))
	mood = float(d.get("mood", 100.0))
	irritability = float(d.get("irritability", 0.0))
	if d.has("personality"):
		personality = (d["personality"] as Dictionary).duplicate()
	else:
		randomize_personality()   ## pre-Sep-2026 save — nothing to restore
	for k: String in skills.keys():
		skills[k] = float((d.get("skills", {}) as Dictionary).get(k, randf_range(0.6, 1.4)))
	age = int(d.get("age", 0))
	if age <= 0:
		randomize_age()
	_birthday_day_of_year = int(d.get("birthday", randi_range(1, 365)))
	_birthday_last_checked_day = int(d.get("birthday_checked", -1))
	chronotype = float(d.get("chronotype", randf_range(-1.5, 1.5)))
	relationships = (d.get("relationships", {}) as Dictionary).duplicate()
	_contagion_exposure = (d.get("contagion_exposure", {}) as Dictionary).duplicate()
	gift_saturation = float(d.get("gift_saturation", 0.0))
	_relax_time_used_today = float(d.get("relax_used", 0.0))
	_relax_day_clock = float(d.get("relax_day_clock", 0.0))
	_relax_cooldown_hours = float(d.get("relax_cooldown", 1.0))
	_talk_cooldown_until = float(d.get("talk_cooldown_until", 0.0))
	_last_social_time = float(d.get("last_social_time", -1.0))
	_snatch_cooldown_from = (d.get("snatch_cooldowns", {}) as Dictionary).duplicate()
	_npc_snatch_pair_cooldown = (d.get("snatch_pair_cooldowns", {}) as Dictionary).duplicate()
	thoughts.from_save(d.get("thoughts", []))
	morale_sys.from_save(d.get("morale", {}))
	bonds.from_save(d.get("bonds", {}))
	social.from_save(d.get("social", {}))
	crash.from_save(d.get("crash", {}))
	combat.from_save(d.get("combat", {}))
	if is_inside_tree() and medical != null:
		combat.apply_loaded_death()
	_last_irritability_label = String(d.get("last_irritability_label", ""))
	_last_player_relationship_label = String(d.get("last_player_rel_label", get_relationship_label("player")))
	_action_log.clear()
	var now_msec: int = Time.get_ticks_msec()
	var now_h: float = NPCClock.now()
	for e: Variant in d.get("action_log", []):
		if e is Dictionary:
			var stamp: float = float(e.get("stamp_hours", now_h))
			var age_sec: float = maxf(0.0, (now_h - stamp) * NPCClock.seconds_per_game_hour())
			_action_log.append({"text": String(e.get("text", "")), "stamp_hours": stamp,
				"game_time": String(e.get("game_time", "")), "kind": String(e.get("kind", "")),
				"fired_at_msec": now_msec - int(age_sec * 1000.0)})
	_pending_medical_save = d.get("medical", [])
	var gender: String = String(d.get("gender", ""))
	if gender != "":
		set_meta("_adventurer_random_gender", gender)   ## read by the model controller in its _ready()
	var hb: Dictionary = d.get("home_bed_pos", {})
	if not hb.is_empty():
		_home_bed_pos = Vector3(float(hb.get("x", 0.0)), float(hb.get("y", 0.0)), float(hb.get("z", 0.0)))

# ─── Time-skip catch-up (see NPCCatchUp.gd) ───────────────────────────────
static func catch_up_all(hours: float) -> void:
	NPCCatchUp.catch_up_all(hours)

func catch_up_time(h: float, avg_mood_before: float) -> void:
	NPCCatchUp.catch_up_npc(self, h, avg_mood_before)
