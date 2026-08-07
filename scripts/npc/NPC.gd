extends CharacterBody3D
class_name NPC
## NPC.gd  (rewritten in NPC Pass 2, Part 1 — navmesh locomotion)
## Wanders the dug-out bunker using real NavigationAgent3D pathfinding over
## BunkerNavMesh's runtime-baked navmesh, and can be talked to via [E].
##
## Collision note (unchanged from Pass 1): deliberately on Godot's DEFAULT
## collision_layer/collision_mask (1/1), like Player.gd. All placed solids
## use collision_layer = 5 (includes bit 1), so default collision already
## hits everything. Never set custom layers here.
##
## Locomotion split: the NavigationAgent3D provides the next XZ waypoint;
## _physics_process steers toward it and move_and_slide() + gravity own the
## actual motion and Y. Physics collision stays the hard guarantee — if the
## navmesh is momentarily stale (mid-rebake after a dig), the NPC bumps and
## re-targets instead of clipping.
##
## FUTURE WORK (unchanged contract from Pass 1):
##   - current_task / assign_task() / perform_task() — Part 4 fills these.

# ─── Tunables ─────────────────────────────────────────────────────────────
@export var move_speed: float = 2.2
@export var acceleration: float = 8.0
@export var npc_name: String = "Survivor"
@export var arrival_distance: float = 0.5
@export var idle_time_min: float = 1.5
@export var idle_time_max: float = 4.0

# ─── Names (Part 23) — fixed 10-name pool, randomly assigned at spawn ─────
## `npc_name` stays @export'd above with default "Survivor" — that default
## is also the sentinel _ready() checks to decide whether to randomize (a
## scene-placed or save-restored NPC that already has a real name is left
## alone). Collision-avoided against every other currently-live NPC so the
## Ask-About dialogue below can never be ambiguous about which NPC it
## means; if the whole pool is somehow already in use (11th+ NPC), repeats
## are allowed rather than failing.
const NPC_NAMES: Array[String] = [
	"Mara", "Dez", "Colton", "Priya", "Finch",
	"Sable", "Nolan", "Ruth", "Kwame", "Vera",
]

func _assign_random_name() -> void:
	var used: Array[String] = []
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other != self and is_instance_valid(other) and ("npc_name" in other):
			used.append(String(other.npc_name))
	var available: Array[String] = NPC_NAMES.filter(
		func(n: String) -> bool: return not used.has(n))
	if available.is_empty():
		available = NPC_NAMES
	npc_name = available[randi() % available.size()]

# ─── Node refs ────────────────────────────────────────────────────────────
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var nav_agent: NavigationAgent3D = null
var hold_point: Node3D = null       ## NPC's carry anchor (Part 3)
var held_item: RigidBody3D = null   ## what's in hand, via PickupableItem.pickup

# ─── State ────────────────────────────────────────────────────────────────
enum NPCState { IDLE, WANDERING }
var _state: NPCState = NPCState.IDLE
var _idle_timer: float = 0.0
var _stuck_check_timer: float = 0.0
var _stuck_check_last_pos: Vector3 = Vector3.ZERO

## FUTURE WORK: Part 4's task system. Do not wire anything into this yet.
var current_task: Node = null

# ─── Needs (Part 2) — 0..100, decay on the game clock ─────────────────────
var energy: float = 100.0
var hunger: float = 100.0   ## 100 = full, 0 = starving (matches PlayerStats' food convention)
var thirst: float = 100.0   ## 100 = hydrated

const ENERGY_DRAIN_PER_GAME_HOUR: float = 3.0
const HUNGER_DRAIN_PER_GAME_HOUR: float = 1.39  ## matches PlayerStats.food_drain_per_game_hour (Part 12 fix — was 3.4, a wrong number, not a deliberate 2.4x-faster choice)
const THIRST_DRAIN_PER_GAME_HOUR: float = 2.08  ## matches PlayerStats.water_drain_per_game_hour

# ─── Health (Part 14) ───────────────────────────────────────────────────────
var health: float = 100.0
## Only drains while Hunger OR Thirst sits at literal 0 (not 25%/50%) — each
## zeroed need contributes its own drain, so being out of both food AND
## water drains faster than being out of just one (Brannon's stacking rule).
## "Slowly," per spec: ~20 real-game-hours to fully die from one zeroed need.
const HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR: float = 5.0

## FUTURE WORK (crisis-response pass): what happens at 0 health (death? a
## collapse state beyond pass-out?) is intentionally out of scope here —
## health is clamped at 0 and nothing further happens yet.

# ─── Personality / mood / irritability (Part 20) ───────────────────────────
var generation_seed: int = 0

## 5 traits, 0.0–1.0, fully random at spawn, FIXED for the NPC's life (no
## mechanism changes them after generation — may become possible later).
## Only "resilience" and "optimism" drive concrete mechanics this pass (see
## _irritability_trait_mult()/_mood_recovery_trait_mult() below). The other
## three are generated and shown in the E-panel but mechanically inert:
## FUTURE WORK — sociability is wired (scales relationship-change rate,
## including Give/Takeaway/Snatch — see _sociability_trait_mult()).
## work_ethic could scale skill-gain rate or job willingness, neuroticism could scale mood's
## volatility (bigger swings from the same inputs). None of that is built.
var personality: Dictionary = {}
const PERSONALITY_TRAIT_KEYS: Array[String] = [
	"resilience", "sociability", "work_ethic", "neuroticism", "optimism",
]
## word band thresholds — shared by trait words AND the Irritable-trait
## breakpoint-shift classification below, so "has the Irritable trait" means
## exactly the same thing everywhere it's checked.
const TRAIT_BAND_LOW: float = 0.35
const TRAIT_BAND_HIGH: float = 0.65
const TRAIT_WORDS: Dictionary = {
	"resilience":  {"low": "Irritable",   "mid": "Even-Tempered", "high": "Level-Headed"},
	"sociability": {"low": "Distant",     "mid": "Reserved",      "high": "Open"},
	"work_ethic":  {"low": "Lazy",        "mid": "Steady",        "high": "Hard Worker"},
	"neuroticism": {"low": "Easygoing",   "mid": "Composed",      "high": "Neurotic"},
	"optimism":    {"low": "Pessimistic", "mid": "Realistic",     "high": "Optimistic"},
}

## ─── Identity (Part 22) — stable unique id, used as the relationship key ──
## Not the same thing as generation_seed (that's for personality/skill RNG,
## not identity). Auto-assigned on first _ready(); overwritten by
## MainWorld._restore_npcs() on load, which also calls _register_id() to
## keep the counter ahead of every restored id so a freshly-spawned NPC in
## the same session can never collide with one loaded from a save.
static var _next_npc_id: int = 1
var npc_id: String = ""

static func _register_id(id: String) -> void:
	if id.begins_with("npc_"):
		var n: int = id.substr(4).to_int()
		if n >= _next_npc_id:
			_next_npc_id = n + 1

# ─── Time-Skip Catch-Up (Aug 2026) ──────────────────────────────────────────
## Called once by each skip source (F7 Fast-Forward, sleep) right next to
## its existing skip_time_with_drain() call — see AdminMenu.gd/
## SleepOverlay.gd. Any FUTURE skip source needs to call this too; nothing
## here happens automatically off the game clock.
const MAX_CATCHUP_HOURS: float = 72.0   ## hard sanity ceiling regardless of what's requested

static func catch_up_all(hours: float) -> void:
	var h: float = clampf(hours, 0.0, MAX_CATCHUP_HOURS)
	if h <= 0.0:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var npcs: Array = tree.get_nodes_in_group("npc")

	## Mood contagion snapshot — average taken BEFORE any catch-up changes
	## anyone's mood, so every NPC pulls toward the same pre-skip picture
	## of the bunker rather than a moving target as each one gets processed.
	var mood_total: float = 0.0
	var mood_count: int = 0
	for n: Node in npcs:
		if is_instance_valid(n) and ("mood" in n):
			mood_total += float(n.mood)
			mood_count += 1
	var avg_mood_before: float = (mood_total / mood_count) if mood_count > 0 else 50.0

	## Harvest — snapshot every plant ready RIGHT NOW, once, before any
	## NPC starts consuming from the pool. One harvested plant = one
	## "job," NOT one JobBoard tray-job (a tray can hold several ready
	## plants at once — see JobBoard._scan_harvest()).
	var ready_plants: Array = []
	for tray: Node in tree.get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray) or not ("plant_refs" in tray):
			continue
		for plant in tray.plant_refs:
			if plant != null and is_instance_valid(plant) and plant.has_method("is_ready") and plant.is_ready():
				ready_plants.append(plant)

	var jobs_per_npc: int = int(floor(h))
	var pool_index: int = 0
	for n: Node in npcs:
		if not is_instance_valid(n):
			continue
		var completed: int = 0
		while completed < jobs_per_npc and pool_index < ready_plants.size():
			var plant: Node = ready_plants[pool_index]
			pool_index += 1
			if is_instance_valid(plant) and plant.has_method("is_ready") and plant.is_ready() and plant.has_method("harvest"):
				plant.harvest()
				completed += 1
		if n.has_method("catch_up_time"):
			n.catch_up_time(h, avg_mood_before)

## Chance any given trait slot is actually present (a notable quirk) at
## all, rather than baseline/absent. Not guaranteed per-NPC — an NPC
## could rarely end up with 0 traits or all 5, most land in between.
const TRAIT_PRESENCE_CHANCE: float = 0.55

func randomize_personality() -> void:
	personality = {}
	for k: String in PERSONALITY_TRAIT_KEYS:
		if randf() >= TRAIT_PRESENCE_CHANCE:
			continue   ## absent entirely — every _*_trait_mult()'s .get(key, 0.5) default already means baseline
		## A PRESENT trait is by definition not neutral — skew into the
		## low or high band, never the dead middle.
		personality[k] = randf_range(0.0, TRAIT_BAND_LOW) if randf() < 0.5 \
			else randf_range(TRAIT_BAND_HIGH, 1.0)

func get_trait_word(key: String) -> String:
	if not personality.has(key):
		return ""   ## baseline — no notable trait, nothing to show
	var v: float = float(personality[key])
	var bands: Dictionary = TRAIT_WORDS.get(key, {})
	if bands.is_empty():
		return ""
	if v < TRAIT_BAND_LOW:
		return bands["low"]
	elif v > TRAIT_BAND_HIGH:
		return bands["high"]
	return bands["mid"]   ## shouldn't be reachable given generation above; kept as a safe fallback

## E-panel display order — up to 5 descriptive words (only the traits that
## are actually present), never raw numbers.
func get_personality_words() -> Array[String]:
	var out: Array[String] = []
	for k: String in PERSONALITY_TRAIT_KEYS:
		var w: String = get_trait_word(k)
		if w != "":
			out.append(w)
	return out

func has_irritable_trait() -> bool:
	return float(personality.get("resilience", 0.5)) < TRAIT_BAND_LOW

## How much the Resilience trait amplifies (Irritable) or dampens
## (Level-Headed) irritability generation AND forgetfulness from the SAME
## need/mood conditions. 1.0 at neutral (0.5) resilience.
func _irritability_trait_mult() -> float:
	return lerp(1.5, 0.5, float(personality.get("resilience", 0.5)))

## Optimism scales mood RECOVERY speed only (not decline) — a pessimistic
## NPC takes longer to bounce back from a bad mood; an optimistic one
## recovers faster. 1.0 at neutral (0.5) optimism.
func _mood_recovery_trait_mult() -> float:
	return lerp(0.5, 1.5, float(personality.get("optimism", 0.5)))

# ─── Mood (Part 20) — 0..100, moves SLOWLY (day-scale, not minute-scale) ───
var mood: float = 100.0
## Needs at/above this average = "fine" — mood drifts back toward 100.
## Below it, mood's target tracks the needs average down proportionally.
const MOOD_FINE_THRESHOLD: float = 70.0
const MOOD_CHANGE_PER_GAME_HOUR: float = 4.0
## Fraction of the gap to the average of every OTHER NPC's mood closed per
## game-hour — global range by design (small bunkers; every NPC should be
## able to pull every other one, compounding into spirals either direction).
const MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR: float = 0.03
## Small random wobble — "more than noise, not enough to drastically shift
## moods" per spec. Symmetric, so it's pure noise on average, not a bias.
const MOOD_DRIFT_MAX_PER_GAME_HOUR: float = 1.0
const MOOD_TICK_INTERVAL: float = 5.0   ## periodic, not per-frame — cheap,
                                        ## and paces debug output sensibly
var _mood_tick_timer: float = 0.0

## Last tick's per-source contribution — inspectable so mood changes are
## NEVER ambiguous about why (Brannon's explicit requirement). Printed by
## NPCDebug every tick when debug logging is enabled.
var _mood_needs_delta: float = 0.0
var _mood_contagion_delta: float = 0.0
var _mood_drift_delta: float = 0.0

# ─── Irritability (Part 20) — 0..100%, reacts FASTER than mood, no UI bar ──
## Backend-only. Surfaces solely via get_status_labels()' Grumpy/Frustrated/
## Mad/Rage word (+ a debug-only % suffix) — never its own bar, per spec.
var irritability: float = 0.0
const IRRITABILITY_NEED_WEIGHT: float = 1.2    ## bigger weight than mood
const IRRITABILITY_MOOD_WEIGHT: float = 0.4    ## smaller weight than needs
const IRRITABILITY_CHANGE_PER_GAME_HOUR: float = 20.0   ## reacts much faster than mood
const IRRITABILITY_BASE_BREAKPOINTS: Array[float] = [20.0, 45.0, 70.0, 90.0]
const IRRITABILITY_LABELS: Array[String] = ["Grumpy", "Frustrated", "Mad", "Rage"]
var _irritability_target: float = 0.0   ## debug-inspectable

## Irritable-trait NPCs cross into each label tier 5% sooner; everyone else's
## thresholds are raised 10% (per spec — the "raise by 10% except Irritable,
## which lower by 5%" rule).
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

func _tick_mood_and_irritability(delta: float) -> void:
	_mood_tick_timer -= delta
	if _mood_tick_timer > 0.0:
		return
	_mood_tick_timer = MOOD_TICK_INTERVAL
	var h: float = game_hours(MOOD_TICK_INTERVAL)
	if h <= 0.0:
		return
	_tick_mood(h)
	_tick_irritability(h)
	_tick_relationships(h)
	_tick_relax_day(h)
	_check_contagion_log()
	_check_label_crossings()

func _tick_mood(h: float) -> void:
	var needs_avg: float = (energy + hunger + thirst) / 3.0
	var mood_target: float = 100.0 if needs_avg >= MOOD_FINE_THRESHOLD else needs_avg
	var rate: float = MOOD_CHANGE_PER_GAME_HOUR
	if mood_target > mood:
		rate *= _mood_recovery_trait_mult()
		## Part 21 — needs being only BARELY "fine" (just above
		## MOOD_FINE_THRESHOLD) mildly slow recovery too, not just a binary
		## on/off switch at the threshold. Comfortably-fine needs (near 100)
		## recover at full speed; needs right at the threshold recover ~15%
		## slower. Deliberately no status label — this is a background
		## nuance for a future tutorial to explain, not something that
		## needs surfacing moment-to-moment.
		var needs_headroom: float = clampf(
			(needs_avg - MOOD_FINE_THRESHOLD) / (100.0 - MOOD_FINE_THRESHOLD), 0.0, 1.0)
		rate *= lerp(0.85, 1.0, needs_headroom)
	var before: float = mood
	mood = move_toward(mood, mood_target, rate * h)
	_mood_needs_delta = mood - before

	before = mood
	var others: Array = get_tree().get_nodes_in_group("npc")
	var total: float = 0.0
	var count: int = 0
	for other: Node in others:
		if other == self or not is_instance_valid(other) or not ("mood" in other):
			continue
		total += float(other.mood)
		count += 1
	if count > 0:
		var avg_other: float = total / float(count)
		mood = clampf(mood + (avg_other - mood) * MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * h, 0.0, 100.0)
	_mood_contagion_delta = mood - before

	before = mood
	mood = clampf(mood + randf_range(-MOOD_DRIFT_MAX_PER_GAME_HOUR, MOOD_DRIFT_MAX_PER_GAME_HOUR) * neuroticism_trait_mult() * h, 0.0, 100.0)
	_mood_drift_delta = mood - before

	if NPCDebug.enabled:
		NPCDebug.log_mood(self, _mood_needs_delta, _mood_contagion_delta, _mood_drift_delta, mood)

func _tick_irritability(h: float) -> void:
	var need_contrib: float = maxf(0.0, 50.0 - energy) + maxf(0.0, 50.0 - hunger) + maxf(0.0, 50.0 - thirst)
	var mood_contrib: float = maxf(0.0, 50.0 - mood)
	var trait_mult: float = _irritability_trait_mult()
	var target: float = clampf(
		(need_contrib * IRRITABILITY_NEED_WEIGHT + mood_contrib * IRRITABILITY_MOOD_WEIGHT) * trait_mult,
		0.0, 100.0)
	_irritability_target = target
	irritability = move_toward(irritability, target, IRRITABILITY_CHANGE_PER_GAME_HOUR * h)

	if NPCDebug.enabled:
		NPCDebug.log_irritability(self, need_contrib, mood_contrib, trait_mult, target, irritability)

## FUTURE WORK (Crisis Response pass, explicitly deferred): mood reaching 0
## is meant to trigger a bunker-wide "Crisis" state, likely an end-game-
## adjacent scenario per Brannon's framing. Not built — mood just clamps at
## 0 and sits there for now, same as health's 0 floor.

# ─── Relationships (Part 22) — groundwork only, see docs/systems/npc/README ─
## Directional, from THIS NPC's perspective only. Key is either another
## NPC's npc_id, or the literal string "player". Value is -100..100, 0 =
## neutral/unacquainted (absent key reads as 0 via get_relationship() — no
## need to pre-populate every possible pair). No opposite-direction value is
## stored anywhere yet (see Future Work in the doc) — this is intentionally
## one-sided for now, same as mood's contagion is a live read of others'
## state rather than a stored pairwise value.
var relationships: Dictionary = {}
const RELATIONSHIP_MIN: float = -100.0
const RELATIONSHIP_MAX: float = 100.0
## 5 bands off 4 thresholds, same pattern as irritability's breakpoints.
const RELATIONSHIP_BAND_THRESHOLDS: Array[float] = [-60.0, -20.0, 20.0, 60.0]
const RELATIONSHIP_LABELS: Array[String] = ["Hostile", "Cold", "Neutral", "Friendly", "Close"]

## Baseline mechanic for this pass: passive proximity. Anything else
## (giving items, crisis help, compliance, etc. — see Future Work) plugs
## into _adjust_relationship() the exact same way once built.
const RELATIONSHIP_PROXIMITY_RANGE: float = 4.0   ## meters, XZ-only
## Reduced 2.0 → 0.15 (Aug 2026, Part 27) — the original value maxed a
## relationship out from ordinary cohabitation alone in ~2 in-game days,
## making every other relationship driver (Give/Takeaway, Sociability)
## irrelevant by comparison. At 0.15/hour, ~4 hrs/day of realistic
## overlap lands around "Friendly" (not maxed) after a full 100-day
## playthrough — see the plan doc for the full reasoning.
const RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR: float = 0.15

func get_relationship(target_id: String) -> float:
	return float(relationships.get(target_id, 0.0))

func get_relationship_label(target_id: String) -> String:
	var v: float = get_relationship(target_id)
	for i: int in range(RELATIONSHIP_BAND_THRESHOLDS.size()):
		if v < RELATIONSHIP_BAND_THRESHOLDS[i]:
			return RELATIONSHIP_LABELS[i]
	return RELATIONSHIP_LABELS[RELATIONSHIP_LABELS.size() - 1]

## Sociability trait tie-in (first mechanical use of the trait — previously
## generated/displayed only). Low sociability = slower to form bonds OR
## grudges either direction; high = faster both ways. Mirrors
## _mood_recovery_trait_mult()/_irritability_trait_mult()'s lerp pattern.
func _sociability_trait_mult() -> float:
	return lerp(0.5, 1.5, float(personality.get("sociability", 0.5)))


## Work Ethic (Aug 2026) — ±30% score multiplier on JobActivity, applied
## directly. Passive/need activities (Wander, Sit, Lie, Eat, Drink) use
## get_work_ethic_passive_mult() below, its mirror image — so a Lazy NPC
## doesn't just work less, it visibly prefers wandering/relaxing/eating
## over an available job by the same margin, and Hard Worker is the
## opposite.
func get_work_ethic_job_mult() -> float:
	return lerp(0.7, 1.3, float(personality.get("work_ethic", 0.5)))

func get_work_ethic_passive_mult() -> float:
	return lerp(1.3, 0.7, float(personality.get("work_ethic", 0.5)))

## Neuroticism — scales mood's random per-tick drift AND the one-time
## mood drop on passing out. 0.5x (Easygoing) to 1.5x (Neurotic), 1.0x
## at baseline/absent. Public (no underscore) — called from NPCBrain.gd's
## PassedOutActivity, not just internally.
func neuroticism_trait_mult() -> float:
	return lerp(0.5, 1.5, float(personality.get("neuroticism", 0.5)))

# ─── Action Log (Aug 2026) ──────────────────────────────────────────────────
## Player-facing, curated log of MEANINGFUL things this NPC has done —
## deliberately NOT a record of routine activity switching (Wander→Eat→
## Wander etc.). Mirrors NotificationManager/NotificationHistoryUI's
## pattern (capped array + change signal + live-rebuilding scroll panel)
## but scoped to one NPC instead of a global feed.
signal action_logged

const ACTION_LOG_MAX_LEN: int = 100
const CONTAGION_LOG_THRESHOLD: float = 2.0   ## cumulative %, since the last log entry

var _action_log: Array[Dictionary] = []
var _contagion_log_accum: float = 0.0
var _last_irritability_label: String = ""
var _last_player_relationship_label: String = "Neutral"

## Single append point for every entry. Both timestamp flavors are
## captured now, not derived later: `fired_at_msec` for the live "Xs ago"
## display, `game_time` (a snapshot of the HUD clock string) for the
## hover tooltip.
func log_action(text: String) -> void:
	_action_log.append({
		"text": text,
		"fired_at_msec": Time.get_ticks_msec(),
		"game_time": _current_game_time_string(),
	})
	if _action_log.size() > ACTION_LOG_MAX_LEN:
		_action_log.pop_front()
	action_logged.emit()

## Newest-first, matching NotificationManager.get_history()'s convention.
func get_action_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = _action_log.duplicate()
	out.reverse()
	return out

func _current_game_time_string() -> String:
	var stats: Node = get_tree().get_first_node_in_group("player_stats")
	if stats != null and stats.has_method("get_time_display"):
		return stats.get_time_display()
	return "?"

## Contagion's own per-tick delta (_mood_contagion_delta, already tracked
## separately inside _tick_mood()) accumulates here; only logged once the
## cumulative drift since the last log crosses ±2%, so ambient contagion
## doesn't spam an entry every 5 seconds.
func _check_contagion_log() -> void:
	_contagion_log_accum += _mood_contagion_delta
	if absf(_contagion_log_accum) >= CONTAGION_LOG_THRESHOLD:
		var verb: String = "rose" if _contagion_log_accum > 0.0 else "fell"
		log_action("Mood %s %+.0f%% (Mood Contagion)" % [verb, _contagion_log_accum])
		_contagion_log_accum = 0.0

## Band-crossing detection — logs only on the actual crossing, not every
## tick the band is held. Irritability (Grumpy/Frustrated/Mad/Rage, and
## calming back down) and relationship-with-player
## (Hostile/Cold/Neutral/Friendly/Close) both already have clean labeled
## bands to compare against; mood doesn't (no small fixed set of bands),
## so it's deliberately not included here.
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

## Single mutation point for every relationship change, present and future
## — every new driver in Future Work calls this, never writes `relationships`
## directly, so the sociability multiplier and clamp are never bypassed.
## Now returns the ACTUAL applied delta (post-Sociability-multiplier,
## post-clamp) — callers that want to show the real number in the action
## log (not the pre-multiplier input) need this; everything that already
## ignores the return value keeps working unchanged.
func _adjust_relationship(target_id: String, delta: float) -> float:
	if target_id == "" or target_id == npc_id:
		return 0.0
	var current: float = get_relationship(target_id)
	var new_value: float = clampf(
		current + delta * _sociability_trait_mult(), RELATIONSHIP_MIN, RELATIONSHIP_MAX)
	relationships[target_id] = new_value
	return new_value - current

func _tick_relationships(h: float) -> void:
	var gain: float = RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR * h
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if NPCItemUser.flat_distance(global_position, other.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			_adjust_relationship(other.npc_id, gain)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		if NPCItemUser.flat_distance(global_position, player.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			_adjust_relationship("player", gain)
	if gift_saturation > 0.0:   ## Part 25 — same tick cadence as everything else here
		gift_saturation = maxf(0.0, gift_saturation - GIFT_SATURATION_DECAY_PER_GAME_HOUR * h)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_tick(self)

## Resets the daily relax budget once a full in-game day (24 game-hours)
## has elapsed. Same 5s tick cadence as everything else in this function.
func _tick_relax_day(h: float) -> void:
	_relax_day_clock += h
	if _relax_day_clock >= 24.0:
		_relax_day_clock = fmod(_relax_day_clock, 24.0)
		_relax_time_used_today = 0.0

## FUTURE WORK — see docs/systems/npc/README.md's Relationships section for
## the full list (item giving/taking, crisis-response helping behavior,
## command-compliance feel, personal-space avoidance scaling by
## relationship, unprompted gift-dropping, dialogue tone reflecting
## relationship, a Player→NPC reciprocal value). None of that is built —
## proximity is the only live driver this pass.

# ─── Give / Takeaway (Part 24) ──────────────────────────────────────────────
## Halved (Aug 2026, Part 27) — relationships should build from many
## interactions over a long playthrough (100+ in-game days), not swing on
## a handful of events. Kept symmetric between Give and Takeaway.
const GIVE_RELATIONSHIP_BONUS: float = 7.5
const TAKEAWAY_RELATIONSHIP_PENALTY: float = 7.5
## Matches EatActivity/DrinkActivity's own auto-trigger threshold
## (`npc.hunger >= 55.0`/`npc.thirst >= 55.0` → score 0) intentionally —
## "needs it" means the same thing everywhere in the NPC system.
const TAKEAWAY_NEED_THRESHOLD: float = 55.0

## Give (player → player-initiated hand-off). Called by InteractionSystem
## when the player presses E on this NPC while holding a giveable item.
## Consumed immediately rather than added to held_item — no queue, no
## "what if they're already full/mid-task" edge cases; this can fire even
## while the NPC is separately mid-Eat/DrinkActivity with something else
## in hand, since it never touches `held_item`.
##
## Gift burnout (Part 25): repeated gifts in a short window give
## progressively smaller boosts (`gift_saturation`, 0..1, decays back to 0
## over ~5 game-days via _tick_relationships()) — closes the "stand there
## feeding them nonstop" exploit. Never fully zero (GIFT_BONUS_FLOOR_MULT)
## so a burned-out gift still visibly does *something*, not a dead click.
##
## Give (Part 26 update — multi-charge items). Marking is now per-(item,
## NPC): `npc_gift_recipients` (Array of npc_id strings this exact item
## instance has already boosted). Same can/bottle CAN still boost several
## DIFFERENT NPCs once each — only a repeat boost to the SAME NPC is
## blocked. Meta is written BEFORE any consumption call that might free
## the node (DishItem/FarmProduceItem's consume_as_food() does), so this
## stays safe regardless of item type.
##
## Consumption always happens even on a repeat gift — still real feeding,
## just no relationship reward the second time. Single-serving items
## (Dish/Produce) are destroyed on first give exactly as before, so a
## repeat is structurally impossible for them; the recipient check exists
## mainly for FoodCan/WaterBottle, which persist across multiple gifts.
const GIFT_SATURATION_MAX: float = 1.0
const GIFT_SATURATION_PER_GIFT: float = 0.25          ## ~4 gifts in a row reaches full burnout
const GIFT_SATURATION_DECAY_PER_GAME_HOUR: float = 1.0 / (5.0 * 24.0)   ## full recovery over ~5 game-days
const GIFT_BONUS_FLOOR_MULT: float = 0.15             ## fully burned out still does *something*
var gift_saturation: float = 0.0

## Pure check, no side effects — called by InteractionSystem BEFORE it
## attempts the physical transfer, for Give.
func can_receive_item(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if held_item != null:
		return false   ## hands full
	return NPCItemUser.is_giveable(item)

## Called AFTER the item has already been physically transferred into
## held_item (by InteractionSystem.release_held_item_to_npc(), via
## Give's _try_give_to_nearest_npc()) — wires up the consumption activity
## and relationship/burnout bookkeeping. Does NOT touch held_item/pickup
## itself anymore; that's entirely the Player side's job now, since it's
## the only side with the inventory-slot context needed to clear it
## correctly.
## giver_id/giver_name default to the player — the existing player-Give
## call site (InteractionSystem.gd) calls this with no extra args and
## needs zero changes. NPC-to-NPC Give (GiveToFriendActivity below)
## passes the donor's npc_id/npc_name instead, so the relationship boost
## lands on the ACTUAL giver, not always "player".
func on_item_given(item: Node, giver_id: String = "player", giver_name: String = "Player") -> void:
	var recipients: Array = item.get_meta("npc_gift_recipients", [])
	var already_boosted: bool = recipients.has(npc_id)
	if not already_boosted:
		recipients.append(npc_id)
		item.set_meta("npc_gift_recipients", recipients)

	var activity: NPCActivity
	if NPCItemUser.is_edible(item):
		activity = NPCBrain.GivenEatActivity.new()
	else:
		activity = NPCBrain.GivenDrinkActivity.new()
	brain.force_command(activity)
	activity.begin_with_item(self, item)

	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, giver_id, 0.0,
				"re-gift, already boosted by this item — fed only, no bonus")
		log_action("%s gave %s to %s (fed only, no relationship change)" % [giver_name, item.get_display_name(), npc_name])
		return

	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	var applied: float = _adjust_relationship(giver_id, effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	log_action("%s gave %s to %s (%+.1f relationship)" % [giver_name, item.get_display_name(), npc_name, applied])
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, giver_id, effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)

# ─── Relationship Snatch (Part 29/30) ───────────────────────────────────────
const SNATCH_RELATIONSHIP_THRESHOLD: float = -50.0
const SNATCH_CHANCE_AT_THRESHOLD: float = 0.05   ## at exactly -50
const SNATCH_CHANCE_AT_MIN: float = 0.5          ## at -100 (fully hostile)

var _debug_force_snatch: bool = false   ## F7 test button only — one-shot

## Gives NPC the same get_held_item() interface Player already has, so
## SnatchActivity/find_snatch_target() can treat both as interchangeable
## targets without branching on type anywhere.
func get_held_item() -> Node:
	return held_item

## Generalized to any target_id (npc_id or "player") — same curve, just
## no longer hardcoded to the player specifically.
func get_snatch_chance_toward(target_id: String) -> float:
	var rel: float = get_relationship(target_id)
	if rel > SNATCH_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(SNATCH_RELATIONSHIP_THRESHOLD - rel) / (SNATCH_RELATIONSHIP_THRESHOLD - RELATIONSHIP_MIN),
		0.0, 1.0)
	return lerp(SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, t)

## Kept for the F7 debug button, which is still specifically about the player.
func get_snatch_chance() -> float:
	return get_snatch_chance_toward("player")

## Deterministic eligibility, no random roll — used by EatActivity/
## DrinkActivity's score() so they don't return 0 and get skipped
## entirely just because the player happens to be holding the only
## matching item in the bunker. The actual random roll only happens once
## the activity is entered, via find_snatch_target() below.
func is_player_snatch_eligible(need_filter: Callable) -> bool:
	if get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD:
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return false
	return need_filter.call(held)

## Deterministic eligibility, no random roll — used alongside is_player_snatch_eligible
## by EatActivity/DrinkActivity's score() so a hungry/thirsty NPC prefers
## snatching from a disliked target (player OR another NPC) over a plain
## search. Mirrors find_snatch_target()'s candidate pool for the trigger path.
func is_npc_snatch_eligible(need_filter: Callable) -> bool:
	if is_player_snatch_eligible(need_filter):
		return true
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD:
			continue
		var held: Node = other.held_item
		if held == null or not is_instance_valid(held):
			continue
		if need_filter.call(held):
			return true
	return false

## Called from EatActivity/DrinkActivity's enter()/_reacquire_or_finish().
## Generalized: considers the player AND every other NPC as candidates,
## uniformly — anyone (player or NPC) counts if their relationship with
## THIS NPC is <= threshold and they're currently holding a matching
## item. Ties broken by nearest, per spec. _debug_force_snatch still
## only ever targets the player specifically (see debug_force_snatch()).
func find_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false
	var force_npc: bool = _debug_force_npc_snatch
	_debug_force_npc_snatch = false

	if forced:
		var player: Node = get_tree().get_first_node_in_group("player")
		return player if player != null and is_instance_valid(player) else null

	var best: Node = null
	var best_d: float = INF

	if not force_npc:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and is_instance_valid(player) and player.has_method("get_held_item") \
				and get_relationship("player") <= SNATCH_RELATIONSHIP_THRESHOLD:
			var held: Node = player.get_held_item()
			if held != null and is_instance_valid(held) and need_filter.call(held):
				var d: float = NPCItemUser.flat_distance(global_position, (player as Node3D).global_position)
				if d < best_d:
					best_d = d
					best = player

	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if not force_npc and get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD:
			continue
		var held: Node = other.held_item
		if held == null or not is_instance_valid(held) or not need_filter.call(held):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other

	if best == null:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "no eligible disliked target holding a matching item")
		return null

	var target_id: String = "player" if best.is_in_group("player") else best.npc_id
	if force_npc:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "roll succeeded", "forced debug target=%s" % target_id)
		return best
	var chance: float = get_snatch_chance_toward(target_id)
	var roll: float = randf()
	if roll > chance:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "roll failed", "target=%s chance=%.2f roll=%.2f" % [target_id, chance, roll])
		return null
	if NPCDebug.enabled:
		NPCDebug.log_snatch(self, "roll succeeded", "target=%s chance=%.2f roll=%.2f" % [target_id, chance, roll])
	return best

## F7 debug trigger — forces THIS NPC to attempt a snatch against the
## player right now via the normal EatActivity/DrinkActivity entry path
## (same "Go eat something"-style force_command pattern), bypassing
## relationship/chance but still requiring a real matching held item.
func debug_force_snatch() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return false
	if NPCItemUser.is_edible(held):
		_debug_force_snatch = true
		brain.force_command(NPCBrain.EatActivity.new())
		return true
	if NPCItemUser.is_drinkable_bottle(held):
		_debug_force_snatch = true
		brain.force_command(NPCBrain.DrinkActivity.new())
		return true
	return false

## F7 debug — sets relationship-with-player directly, bypassing the
## Sociability multiplier _adjust_relationship() normally applies, so the
## F7 buttons produce an exact, predictable ±25 for testing.
func debug_adjust_player_relationship(delta: float) -> void:
	var current: float = get_relationship("player")
	relationships["player"] = clampf(current + delta, RELATIONSHIP_MIN, RELATIONSHIP_MAX)

# ─── Debug force buttons (Aug 2026) — one-shot flags mirroring _debug_force_snatch ───
var _debug_force_give: bool = false
var _debug_force_npc_snatch: bool = false

## Force this NPC into a talk session right now via its normal TalkActivity
## entry path (finds the nearest free partner within TALK_RANGE).
func debug_force_talk() -> bool:
	var partner: Node = find_talk_partner()
	if partner == null:
		return false
	brain.force_command(NPCBrain.TalkActivity.new())
	return true

## Force this NPC to fetch+deliver to the nearest eligible friend right
## now via its normal GiveToFriendActivity path, bypassing the chance roll
## but still requiring a real needy friend and a matching loose item.
func debug_force_give_to_friend() -> bool:
	if not has_needy_friend():
		return false
	_debug_force_give = true
	brain.force_command(NPCBrain.GiveToFriendActivity.new())
	return true

## Force this NPC to snatch the nearest eligible DISLIKED NPC's matching
## item right now (bypassing chance/relation), via the Eat/Drink snatch
## entry path. Player is deliberately NOT a candidate here — this button
## exists to test the NPC-target branch.
func debug_force_npc_snatch() -> bool:
	_debug_force_npc_snatch = true
	var target: Node = find_snatch_target(Callable(NPCItemUser, "is_edible"))
	if target != null:
		brain.force_command(NPCBrain.EatActivity.new())
		return true
	_debug_force_npc_snatch = true
	target = find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
	if target != null:
		brain.force_command(NPCBrain.DrinkActivity.new())
		return true
	_debug_force_npc_snatch = false
	return false

## Takeaway gate. True only while genuinely hungry/thirsty AND actually
## holding a food/drink item right now — recomputed live rather than
## captured at the moment of pickup. Functionally identical to a captured
## flag for the few-second holding window (need doesn't recover until the
## bite/sip actually lands, which is the exact moment this gate exists to
## intercept), and it correctly excludes a player-forced "Go eat
## something" command issued while the NPC wasn't actually hungry —
## `_talk_menu`'s command buttons use this SAME EatActivity/DrinkActivity
## class, so there's no separate "forced" flag to check; live need level
## is the only signal that's actually true either way.
func is_consuming_from_need() -> bool:
	if held_item == null or not is_instance_valid(held_item):
		return false
	if hunger >= TAKEAWAY_NEED_THRESHOLD and thirst >= TAKEAWAY_NEED_THRESHOLD:
		return false
	return NPCItemUser.is_edible(held_item) or NPCItemUser.is_drinkable_bottle(held_item)

## Called by InteractionSystem the instant the player successfully grabs
## ANY item this NPC was holding (Part 25 — takeaway is no longer limited
## to need-triggered consumption; see InteractionSystem's _try_pickup()).
## Clears the stale held_item reference and releases its claim regardless
## of what it was — EatActivity/DrinkActivity's tick()/eat_held_step()/
## _finish_bottle() and JobActivity's fetch/work/complete paths were all
## checked and already no-op cleanly on a null/mismatched held_item (see
## docs/systems/npc/README.md for the one accepted quirk this leaves: a
## stolen job material lets that job silently "complete" without its
## actual effect landing).
##
## The relationship ding, however, still only applies when the item taken
## was a genuinely need-triggered food/water consumption — evaluated
## BEFORE clearing held_item, since is_consuming_from_need() needs it
## still set. Taking a job material away has no relationship consequence.
func on_item_taken_by_player() -> void:
	var was_need_triggered: bool = is_consuming_from_need()
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	if not was_need_triggered:
		return   ## job material etc. — no relationship consequence, and deliberately not logged either (not meaningful enough)
	var applied: float = _adjust_relationship("player", -TAKEAWAY_RELATIONSHIP_PENALTY)
	log_action("Player took %s from %s (%+.1f relationship)" % [item.get_display_name(), npc_name, applied])
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -TAKEAWAY_RELATIONSHIP_PENALTY, "item taken mid-consumption")

## Called on the VICTIM when another NPC successfully snatches from them
## (NPCItemUser.snatch_from()). Relationship-neutral, same as the player
## version — this is a consequence of an already-bad relationship, not a
## new event that further sours it.
func on_item_snatched_by_npc(thief: NPC) -> void:
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	log_action("%s snatched an item from %s" % [thief.npc_name, npc_name])

# ─── Talking (Aug 2026) ──────────────────────────────────────────────────
const TALK_RANGE: float = 3.0
const TALK_BASE_SCORE: float = 5.5   ## same tier as Relax/Wander
const TALK_RELATIONSHIP_NEUTRAL_LOW: float = -15.0
const TALK_RELATIONSHIP_NEUTRAL_HIGH: float = 15.0
const TALK_SCORE_MULT_MAX: float = 2.5   ## at relationship +100
const TALK_SCORE_MULT_MIN: float = 0.2   ## at relationship -100

## Flat 1.0x between -15 and +15 (your framing: "neutral" band); scales
## continuously beyond that rather than a hard binary jump, same reasoning
## every other trait/relationship multiplier in this file uses.
func get_talk_score_mult(other_id: String) -> float:
	var rel: float = get_relationship(other_id)
	if rel > TALK_RELATIONSHIP_NEUTRAL_HIGH:
		var t: float = clampf((rel - TALK_RELATIONSHIP_NEUTRAL_HIGH) / (RELATIONSHIP_MAX - TALK_RELATIONSHIP_NEUTRAL_HIGH), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MAX, t)
	elif rel < TALK_RELATIONSHIP_NEUTRAL_LOW:
		var t: float = clampf((TALK_RELATIONSHIP_NEUTRAL_LOW - rel) / (TALK_RELATIONSHIP_NEUTRAL_LOW - RELATIONSHIP_MIN), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MIN, t)
	return 1.0

## Nearest NPC within TALK_RANGE who's actually free to talk right now.
func find_talk_partner() -> Node:
	var best: Node = null
	var best_d: float = TALK_RANGE
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if not other.has_method("is_available_to_talk") or not other.is_available_to_talk():
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best

func is_available_to_talk() -> bool:
	if brain == null:
		return false
	if brain.is_relaxing() or brain.is_talking():
		return false
	return brain.is_current_interruptible()

## Called on the partner by the initiator's TalkActivity. Forces the
## partner into their own (non-initiator) TalkActivity instance.
func start_talk_session(initiator: NPC) -> bool:
	if not is_available_to_talk():
		return false
	brain.force_command(NPCBrain.TalkActivity.new(initiator, false))
	return true

## Called on the partner when the initiator's session timer ends, OR on
## either side if interrupted some other way — ends the local session
## and logs it from this NPC's own perspective.
func end_talk_session() -> void:
	if brain == null or not brain.is_talking():
		return
	var partner_name: String = brain.get_talk_partner_name()
	log_action("Talked to %s" % partner_name)
	brain.end_talk_if_talking()

# ─── Give-to-Friend (Aug 2026) ──────────────────────────────────────────────
const GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD: float = 25.0
const GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD: float = 0.05   ## at exactly +25
const GIVE_TO_FRIEND_CHANCE_AT_MAX: float = 0.5          ## at +100 — same curve shape as Snatch, mirrored direction
const GIVE_TO_FRIEND_BASE_SCORE: float = 5.5

func get_give_to_friend_chance(rel: float) -> float:
	if rel < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(rel - GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD) / (RELATIONSHIP_MAX - GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD),
		0.0, 1.0)
	return lerp(GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD, GIVE_TO_FRIEND_CHANCE_AT_MAX, t)

## Cheap, deterministic (no item search, no roll) — used by
## GiveToFriendActivity.score() so the full search only runs on enter().
func has_needy_friend() -> bool:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
			continue
		if float(other.hunger) < 55.0 or float(other.thirst) < 55.0:
			return true
	return false

## Full search: nearest needy friend (relationship-eligible, matching
## need low) with a matching item actually available in the world, gated
## by one probability roll scaled to that friend's relationship. Returns
## {} if nothing qualifies.
func find_friend_to_help() -> Dictionary:
	var best: Node = null
	var best_d: float = INF
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
			continue
		if not (float(other.hunger) < 55.0 or float(other.thirst) < 55.0):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	if best == null:
		return {}

	var need_filter: Callable = Callable(NPCItemUser, "is_edible") if float(best.hunger) < float(best.thirst) \
		else Callable(NPCItemUser, "is_drinkable_bottle")
	## if only one need is actually low, make sure the filter matches THAT one
	if float(best.hunger) < 55.0 and not (float(best.thirst) < 55.0):
		need_filter = Callable(NPCItemUser, "is_edible")
	elif float(best.thirst) < 55.0 and not (float(best.hunger) < 55.0):
		need_filter = Callable(NPCItemUser, "is_drinkable_bottle")

	var item: Node = NPCItemUser.find_loose_item(self, need_filter)
	if item == null:
		return {}

	var chance: float = get_give_to_friend_chance(get_relationship(best.npc_id))
	var forced_give: bool = _debug_force_give
	_debug_force_give = false
	if not forced_give and randf() > chance:
		return {}

	return {"friend": best, "item": item}


# ─── Skills (Part 4) — score multipliers for job selection; grow with use ──
var skills: Dictionary = {
	"farming": 1.0, "plumbing": 1.0, "electrical": 1.0, "construction": 1.0,
}

func randomize_skills() -> void:
	for k: String in skills.keys():
		skills[k] = randf_range(0.6, 1.4)

func gain_skill(key: String, amount: float = 0.01) -> void:
	if skills.has(key):
		skills[key] = minf(2.0, float(skills[key]) + amount)

# ─── Brain ────────────────────────────────────────────────────────────────
var brain: NPCBrain = null

var _stats_ref: Node = null

## Real-seconds → game-hours for this frame, via the shared compressed clock.
func game_hours(delta: float) -> float:
	if _stats_ref == null or not is_instance_valid(_stats_ref):
		_stats_ref = get_tree().get_first_node_in_group("player_stats")
	if _stats_ref == null or _stats_ref._seconds_per_game_hour <= 0.0:
		return 0.0
	return delta / _stats_ref._seconds_per_game_hour

func _tick_needs(delta: float) -> void:
	var h: float = game_hours(delta)
	if h <= 0.0:
		return
	energy = maxf(0.0, energy - ENERGY_DRAIN_PER_GAME_HOUR * h)
	hunger = maxf(0.0, hunger - HUNGER_DRAIN_PER_GAME_HOUR * h)
	thirst = maxf(0.0, thirst - THIRST_DRAIN_PER_GAME_HOUR * h)

	var health_drain: float = 0.0
	if hunger <= 0.0:
		health_drain += HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR
	if thirst <= 0.0:
		health_drain += HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR
	if health_drain > 0.0:
		health = maxf(0.0, health - health_drain * h)

## Decelerate to a stop — used by activities when standing still.
## Part 13 — every stationary phase in the game (job work, eating, drinking,
## the idle pause between wander legs) already calls this every frame. It
## now also raises _movement_locked, so a late-arriving avoidance callback
## (see _on_velocity_computed below) can never overwrite the halt with a
## stale travel-direction velocity.
var _movement_locked: bool = false

func halt_movement(delta: float) -> void:
	_movement_locked = true
	velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
	velocity.z = lerp(velocity.z, 0.0, acceleration * delta)

## One-time hard stop for the exact instant an NPC snaps into a seated/lying
## position (SitActivity, LieActivity) — those states return early every
## frame afterward and never call halt_movement() again, so they need an
## explicit lock at the moment of transition rather than relying on a
## per-frame call.
func lock_movement() -> void:
	_movement_locked = true
	velocity.x = 0.0
	velocity.z = 0.0

func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")

	if npc_id == "":
		npc_id = "npc_%d" % _next_npc_id
		_next_npc_id += 1
	NPC._register_id(npc_id)

	if npc_name == "Survivor":
		_assign_random_name()

	## Agent built in code (no scene edit needed; scene stays Pass-1 shape).
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	## Reached-checks are 3D. Path points sit on the floor (y≈0.5) while this
	## node's origin is the capsule CENTER (y≈1.4) — a constant ~0.9 vertical
	## offset. Desired distances must exceed it or no waypoint can ever
	## register as reached (the Part 1–8 wall-sticking root cause). 1.1
	## leaves ~0.63 of effective XZ arrival tolerance. (Part 9)
	nav_agent.path_desired_distance = 1.1
	nav_agent.target_desired_distance = 1.1
	nav_agent.path_max_distance = 3.0
	nav_agent.radius = 0.4               ## matches BunkerNavMesh.agent_radius (Part 8)
	## Real dynamic avoidance (Part 11) — routes around heavy items'
	## NavigationObstacle3D (PickupableItem.gd) AND every other NPC's own
	## agent continuously, replacing Part 10.1's reactive post-collision
	## steering hack entirely.
	nav_agent.avoidance_enabled = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(nav_agent)

	## Carry anchor — chest-height, slightly forward; items follow it with
	## the same PickupableItem physics the player's HoldPoint gets.
	hold_point = Node3D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(0.0, 0.9, -0.8)
	add_child(hold_point)

	_enter_idle()

	generation_seed = randi()
	randomize_personality()
	randomize_skills()
	brain = NPCBrain.new()
	brain.setup(self)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	_tick_needs(delta)
	_tick_mood_and_irritability(delta)
	_tick_stuck_recovery(delta)

	if current_task != null:
		perform_task(delta)
	elif brain != null:
		brain.tick(delta)
	else:
		_process_wander(delta)   ## fallback only — brain owns behavior now

	move_and_slide()
	_handle_physics_pushes(delta)
	_check_stuck(delta)

# ─── Navigation primitives (used by wander now; by every activity later) ──
## Point the agent at a world position. Y is flattened — paths are XZ-only.
func set_nav_target(world_pos: Vector3) -> void:
	if nav_agent != null:
		## Snap target to the real floor plane (0.5), not y=0 — keeps the
		## vertical offset to this node's origin at ~0.9, inside the 1.1
		## desired-distance budget above. (Part 9)
		nav_agent.target_position = Vector3(world_pos.x, 0.5, world_pos.z)

func nav_finished() -> bool:
	return nav_agent == null or nav_agent.is_navigation_finished()

## Steer toward the agent's next waypoint. Call once per physics frame while
## traveling; pairs with move_and_slide() in _physics_process. With real
## avoidance (Part 11) this no longer sets velocity directly — it submits
## the PREFERRED velocity to the NavigationAgent3D, which factors in every
## nearby NavigationObstacle3D (heavy items) and other NPC agents, then
## calls back into _on_velocity_computed() with the safe, adjusted velocity
## to actually apply. Every activity keeps calling this exact same function,
## so no activity code needs to know avoidance exists at all.
func nav_steer(delta: float) -> void:
	_movement_locked = false   ## actively requesting movement again (Part 13)
	_last_steer_delta = delta
	if nav_agent == null or nav_agent.is_navigation_finished():
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
		return
	var next: Vector3 = nav_agent.get_next_path_position()
	var dir: Vector3 = next - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	nav_agent.set_velocity(dir * move_speed * get_status_speed_multiplier())   ## Part 14

var _last_steer_delta: float = 0.0

## Godot calls this once avoidance has computed a safe velocity from the
## preferred one submitted in nav_steer(). Fires synchronously within the
## same physics frame under local (non-multithreaded) avoidance, which is
## what a single-region setup like this one uses.
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if _movement_locked:
		return   ## a stationary phase (Part 13) started after this request was
		         ## submitted — the request is stale, ignore it
	velocity.x = lerp(velocity.x, safe_velocity.x, acceleration * _last_steer_delta)
	velocity.z = lerp(velocity.z, safe_velocity.z, acceleration * _last_steer_delta)
	if Vector2(safe_velocity.x, safe_velocity.z).length() > 0.05:
		rotation.y = atan2(-safe_velocity.x, -safe_velocity.z)

# ─── Wander state machine ─────────────────────────────────────────────────
func _enter_idle() -> void:
	_state = NPCState.IDLE
	_idle_timer = randf_range(idle_time_min, idle_time_max)
	velocity.x = 0.0
	velocity.z = 0.0

func _enter_wandering() -> void:
	_state = NPCState.WANDERING
	var world: Node = get_tree().get_first_node_in_group("main_world")
	if world != null and world.has_method("get_random_cleared_cell_center"):
		set_nav_target(world.get_random_cleared_cell_center())
	_stuck_check_timer = 0.0
	_stuck_check_last_pos = global_position

func _process_wander(delta: float) -> void:
	match _state:
		NPCState.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_wandering()
		NPCState.WANDERING:
			if nav_finished():
				_enter_idle()
			else:
				nav_steer(delta)

## Safety net for stale-navmesh moments (mid-rebake) or physics shoves:
## if wandering but not actually moving, give up this leg and re-idle.
func _check_stuck(delta: float) -> void:
	if _state != NPCState.WANDERING or current_task != null:
		return
	_stuck_check_timer += delta
	if _stuck_check_timer >= 1.5:
		if global_position.distance_to(_stuck_check_last_pos) < 0.15:
			_enter_idle()
		else:
			_stuck_check_timer = 0.0
			_stuck_check_last_pos = global_position

# ─── Future task hook (stub — Part 4 fills this) ──────────────────────────
func assign_task(task: Node) -> void:
	current_task = task

func perform_task(_delta: float) -> void:
	pass  ## FUTURE WORK

# ─── Interaction (contract unchanged from Pass 1) ─────────────────────────
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


# ─── Overhead work banner (Part 4) — GeneratorObject fuel-banner style ─────
var _work_banner: Label3D = null

func show_work_banner() -> void:
	if _work_banner == null:
		_work_banner = Label3D.new()
		_work_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_work_banner.fixed_size = true
		_work_banner.pixel_size = 0.0009
		_work_banner.font_size = 40
		_work_banner.outline_size = 8
		_work_banner.position = Vector3(0.0, 1.55, 0.0)
		_work_banner.modulate = Color(0.95, 0.85, 0.45, 1.0)
		add_child(_work_banner)
	_work_banner.visible = true

func update_work_banner(action: String, progress: float) -> void:
	if _work_banner == null:
		return
	var filled: int = clampi(int(round(progress * 5.0)), 0, 5)
	_work_banner.text = "%s %s%s" % [action,
		"▓".repeat(filled), "░".repeat(5 - filled)]

func hide_work_banner() -> void:
	if _work_banner != null:
		_work_banner.visible = false


# ─── Overhead name/activity label (Part 5) ─────────────────────────────────
## Always-on small billboard: "Name — Activity". Sits ABOVE the Part-4 work
## banner (which shows only during job work phases, below this).
var _overhead_label: Label3D = null
var _overhead_timer: float = 0.0

func _process(delta: float) -> void:
	_overhead_timer -= delta
	if _overhead_timer > 0.0:
		return
	_overhead_timer = 0.5
	if _overhead_label == null:
		_overhead_label = Label3D.new()
		_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_overhead_label.fixed_size = true
		_overhead_label.pixel_size = 0.0007
		_overhead_label.font_size = 34
		_overhead_label.outline_size = 8
		_overhead_label.position = Vector3(0.0, 1.85, 0.0)
		_overhead_label.modulate = Color(0.88, 0.90, 0.92, 0.95)
		add_child(_overhead_label)
	var activity: String = brain.current_label() if brain != null else "Idle"
	_overhead_label.text = "%s — %s" % [npc_name, activity]
	_update_relationship_debug_label()

# ─── Debug relationship visualizer (Part 24) ────────────────────────────────
## Piggybacks the existing "Toggle NPC Debug Logging" F7 row (NPCDebug.
## enabled) rather than adding a 13th row — floating readout above each
## NPC's head of who they know and how they feel. Deliberately plain text;
## this is a debug stand-in for the real in-fiction relationship UI that
## belongs in a later pass once relationships are baked into the game for
## good, not the final thing.
var _relationship_debug_label: Label3D = null

func _update_relationship_debug_label() -> void:
	if not NPCDebug.enabled:
		if _relationship_debug_label != null:
			_relationship_debug_label.visible = false
		return
	if _relationship_debug_label == null:
		_relationship_debug_label = Label3D.new()
		_relationship_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_relationship_debug_label.fixed_size = true
		_relationship_debug_label.pixel_size = 0.0006
		_relationship_debug_label.font_size = 28
		_relationship_debug_label.outline_size = 6
		_relationship_debug_label.position = Vector3(0.0, 2.15, 0.0)
		_relationship_debug_label.modulate = Color(0.55, 0.85, 1.0, 0.95)   ## pale blue — visually distinct from the other two overhead labels
		add_child(_relationship_debug_label)
	_relationship_debug_label.visible = true
	var lines: Array[String] = []
	for target_id: String in relationships.keys():
		var display: String = "You" if target_id == "player" else _name_for_relationship_id(target_id)
		lines.append("%s: %+.0f (%s)" % [display, relationships[target_id], get_relationship_label(target_id)])
	if gift_saturation > 0.0:   ## Part 25
		lines.append("Gift burnout: %d%%" % int(round(gift_saturation * 100.0)))
	_relationship_debug_label.text = "\n".join(lines) if not lines.is_empty() else "(no relationships yet)"

func _name_for_relationship_id(target_id: String) -> String:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(other) and ("npc_id" in other) and String(other.npc_id) == target_id:
			return String(other.npc_name)
	return target_id


# ─── Stuck recovery (Part 7) ────────────────────────────────────────────────
## Fires only while the nav agent has an active, unfinished target — i.e.
## during any activity's travel phase. Idle/consume/work-in-place moments
## are correctly stationary and never flagged. If the NPC hasn't displaced
## STUCK_MIN_DISPLACEMENT in STUCK_CHECK_INTERVAL seconds while trying to
## travel, hard-abort the current activity so the brain re-scores fresh —
## every activity's exit() already releases jobs/chairs/items cleanly, so
## this is always a safe, non-destructive reset.
const STUCK_CHECK_INTERVAL: float = 1.0
const STUCK_MIN_DISPLACEMENT: float = 0.15

var _stuck_timer: float = 0.0
var _stuck_ref_pos: Vector3 = Vector3.ZERO
var _stuck_recoveries: int = 0   ## exposed for the Part 7 debug dump

func _tick_stuck_recovery(delta: float) -> void:
	## Part 18 — gate on _movement_locked, not nav_finished(). Drink/Eat/
	## Job-work all stop the NPC via their OWN range checks (PICKUP_RANGE,
	## USE_RANGE, WORK_RANGE), completely decoupled from the nav_agent's own
	## arrival threshold — an NPC can correctly halt for a totally
	## legitimate reason while nav_finished() still reports false, because
	## nothing ever told the nav_agent navigation was "done." That mismatch
	## was firing false stuck-aborts mid-drink/mid-eat/mid-work, which is
	## what was actually causing the drop-and-repeat loop (exit() drops
	## whatever's held). _movement_locked is raised by every halt_movement()/
	## lock_movement() call — i.e., every legitimate stationary reason — and
	## cleared only when nav_steer() next runs to resume real travel, so
	## it's a direct read of "an activity wants me still" instead of an
	## indirect, frequently-wrong guess from the navigation layer.
	if nav_agent == null or _movement_locked:
		_stuck_timer = 0.0
		_stuck_ref_pos = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	var moved: float = global_position.distance_to(_stuck_ref_pos)
	_stuck_timer = 0.0
	_stuck_ref_pos = global_position
	if moved < STUCK_MIN_DISPLACEMENT:
		_recover_from_stuck()

func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0


# ─── Physics-clutter push-through (Part 10, simplified in Part 11) ─────────
## Only light items reach this now — heavy items have a real
## NavigationObstacle3D (PickupableItem.gd, Part 11) and NPCs route around
## their current position proactively via avoidance, so they rarely collide
## at all. This still shoves+corrects for light loose items (FoodCan,
## WaterBottle, produce, ...), which intentionally have no obstacle and are
## meant to be walked straight through rather than routed around.
const LIGHT_PUSH_IMPULSE: float = 1.5   ## shove strength on light items
const HEAVY_PUSH_MASS: float = 3.0      ## mirrors PickupableItem.HEAVY_OBSTACLE_MASS —
                                        ## anything at/above this got an obstacle and
                                        ## should rarely reach this code at all; if it
                                        ## still does (avoidance is a preference, not a
                                        ## guarantee), give it a small acknowledging
                                        ## shove but let normal collision resistance stand

func _handle_physics_pushes(delta: float) -> void:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if not (body is RigidBody3D):
			continue
		if ("is_held" in body) and body.is_held:
			continue   ## someone's carrying it — not clutter, ignore
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
				global_position += blocked * delta
		else:
			rb.apply_central_impulse(away.normalized() * LIGHT_PUSH_IMPULSE / rb.mass)


## Energy contributes its OWN single progressive tier (25% tier REPLACES the
## 50% tier's penalty, doesn't stack on top of it). Hunger/Thirst only
## affect speed at <25% each. Mood adds its own small penalty at ≤25% — all
## multiply together, so low on several at once compounds. (Unchanged by
## Part 21 — only the LABEL format below changes, not this math.)
func get_status_speed_multiplier() -> float:
	var energy_mult: float = 1.0
	if energy < 25.0:
		energy_mult = 0.65   ## "noticeably slower"
	elif energy < 50.0:
		energy_mult = 0.85   ## "slightly slower"
	var hunger_mult: float = 0.90 if hunger < 25.0 else 1.0
	var thirst_mult: float = 0.90 if thirst < 25.0 else 1.0
	var mood_mult: float = 0.85 if mood <= 25.0 else 1.0
	return energy_mult * hunger_mult * thirst_mult * mood_mult

## Chance [0..1] to divert from a job into 20s of forgetful wandering.
## Part 21 rewrite: AVERAGED across Hunger, Thirst, Mood, and (new) Energy
## instead of probabilistic-OR-combined — OR-combination made three only-
## moderate sources compound to a much higher chance than any one alone
## (~49% from three ~20% sources), which was mechanically why forgetfulness
## felt like it could take over. A straight average is far gentler (the
## same three sources average to ~20%) and matches the intent: a mild,
## readable guide on effectiveness, not a system that dominates. Energy's
## tiers are deliberately small — it stays mostly a speed stat, this is
## just a mild secondary contribution. Averaged result is then scaled by
## the Resilience trait, same as before.
func get_forgetfulness_chance() -> float:
	var p_hunger: float = _forgetfulness_tier_chance(hunger)
	var p_thirst: float = _forgetfulness_tier_chance(thirst)
	var p_mood: float = _mood_forgetfulness_tier_chance(mood)
	var p_energy: float = _energy_forgetfulness_tier_chance(energy)
	var avg: float = (p_hunger + p_thirst + p_mood + p_energy) / 4.0
	return clampf(avg * _irritability_trait_mult(), 0.0, 1.0)

func _forgetfulness_tier_chance(need_value: float) -> float:
	if need_value <= 0.0:
		return 0.45   ## "very forgetful"
	elif need_value < 25.0:
		return 0.20   ## "more often"
	elif need_value < 50.0:
		return 0.08   ## "sometimes"
	return 0.0

func _mood_forgetfulness_tier_chance(mood_value: float) -> float:
	if mood_value <= 0.0:
		return 0.25
	elif mood_value < 25.0:
		return 0.12
	elif mood_value < 50.0:
		return 0.05
	return 0.0

## Part 21 — energy's new, deliberately mild forgetfulness contribution.
## Roughly a third of the needs' scale; energy's primary job stays speed.
func _energy_forgetfulness_tier_chance(energy_value: float) -> float:
	if energy_value <= 0.0:
		return 0.15
	elif energy_value < 25.0:
		return 0.08
	elif energy_value < 50.0:
		return 0.03
	return 0.0

func is_passed_out() -> bool:
	return energy <= 0.0

## Part 21 — the specific phrase(s) currently contributing to forgetfulness,
## for the single combined label's parenthetical. Independent of the trait
## multiplier (that only scales the roll chance/tier boundary, not which
## reasons get listed) and independent of averaging (lists ANY active
## source, regardless of how much the average dilutes its effective weight).
func _forgetfulness_reasons() -> Array[String]:
	var reasons: Array[String] = []
	if hunger <= 0.0: reasons.append("Starving")
	elif hunger < 25.0: reasons.append("Very Hungry")
	elif hunger < 50.0: reasons.append("Hungry")
	if thirst <= 0.0: reasons.append("Dehydrated")
	elif thirst < 25.0: reasons.append("Very Thirsty")
	elif thirst < 50.0: reasons.append("Mildly Dehydrated")
	if energy <= 0.0: reasons.append("Exhausted")
	elif energy < 25.0: reasons.append("Very Tired")
	elif energy < 50.0: reasons.append("Low Energy")
	if mood <= 0.0: reasons.append("Miserable")
	elif mood < 25.0: reasons.append("Very Unhappy")
	elif mood < 50.0: reasons.append("Unhappy")
	return reasons

## Part 21 — same idea for the Slow label's parenthetical (speed math itself
## is unchanged; this only decides which reason phrases to list alongside
## the single combined "Slightly/Noticeably Slowed" word).
func _slow_reasons() -> Array[String]:
	var reasons: Array[String] = []
	if energy < 25.0: reasons.append("Very Tired")
	elif energy < 50.0: reasons.append("Tired")
	if hunger < 25.0: reasons.append("Very Hungry")
	if thirst < 25.0: reasons.append("Very Thirsty")
	if mood <= 25.0: reasons.append("Very Low Mood")
	return reasons

## Human-readable summary for the E-panel's Status line — display only,
## does not drive any behavior itself (that's the functions above). Part 21
## rewrite: Forgetfulness and Slowing each collapse to ONE label with every
## contributing cause listed in parentheses (e.g. "Very Forgetful (Starving,
## Dehydrated, Miserable)"), instead of one separate line per cause.
func get_status_labels() -> Array[String]:
	var labels: Array[String] = []

	if is_passed_out():
		labels.append("Passed out (exhausted)")
	else:
		var slow_mult: float = get_status_speed_multiplier()
		if slow_mult < 1.0:
			var reasons: Array[String] = _slow_reasons()
			if not reasons.is_empty():
				var word: String = "Noticeably Slowed" if slow_mult <= 0.65 else "Slightly Slowed"
				labels.append("%s (%s)" % [word, ", ".join(reasons)])

	var forget_chance: float = get_forgetfulness_chance()
	var forget_reasons: Array[String] = _forgetfulness_reasons()
	if not forget_reasons.is_empty():
		if forget_chance >= 0.25:
			labels.append("Very Forgetful (%s)" % ", ".join(forget_reasons))
		elif forget_chance >= 0.12:
			labels.append("Forgetful (%s)" % ", ".join(forget_reasons))
		elif forget_chance > 0.0:
			labels.append("Occasionally Forgetful (%s)" % ", ".join(forget_reasons))

	if hunger <= 0.0 or thirst <= 0.0:
		labels.append("Losing health (starving/dehydrated)")

	## Irritability — Grumpy/Frustrated/Mad/Rage. Percentage suffix is
	## debug-only (gated on NPCDebug.enabled) — dev tool, removed for the
	## final game per Brannon's instruction; shipped play only ever shows
	## the word.
	var irr_label: String = get_irritability_label()
	if irr_label != "":
		if NPCDebug.enabled:
			labels.append("%s (%.0f%%)" % [irr_label, irritability])
		else:
			labels.append(irr_label)

	if labels.is_empty():
		labels.append("Doing fine")
	return labels

# ─── Dialogue (Part 20) — mood/irritability-aware, first pass only ─────────
## Deliberately simple: a handful of candidate lines per tier, picked fresh
## each time Talk is pressed. Lays groundwork for a real dialogue system
## later rather than building one now.
const DIALOGUE_ANGRY: Array[String] = [
	"\"What do you want.\"",
	"\"Not now.\"",
	"\"I'm this close to losing it.\"",
]
const DIALOGUE_FRUSTRATED: Array[String] = [
	"\"...Yeah?\"",
	"\"Can this wait?\"",
]
const DIALOGUE_GRUMPY: Array[String] = [
	"\"Hm. What.\"",
	"\"Yeah, yeah.\"",
]
const DIALOGUE_LOW_MOOD: Array[String] = [
	"\"...\"",
	"\"I don't really feel like talking.\"",
]
const DIALOGUE_HAPPY: Array[String] = [
	"\"Hey! Good to see you.\"",
	"\"What's up?\"",
]
const DIALOGUE_NEUTRAL: Array[String] = [
	"\"...\"",
	"\"Yeah?\"",
]

func get_dialogue_line() -> String:
	var irr_label: String = get_irritability_label()
	var pool: Array[String] = DIALOGUE_NEUTRAL
	if irr_label == "Rage" or irr_label == "Mad":
		pool = DIALOGUE_ANGRY
	elif irr_label == "Frustrated":
		pool = DIALOGUE_FRUSTRATED
	elif irr_label == "Grumpy":
		pool = DIALOGUE_GRUMPY
	elif mood < 25.0:
		pool = DIALOGUE_LOW_MOOD
	elif mood >= 75.0:
		pool = DIALOGUE_HAPPY
	return pool[randi() % pool.size()]

# ─── Relationship Q&A Dialogue (Part 23) ────────────────────────────────────
## "What do you think of X?" — the player-facing readout for the Relationships
## pass's data (previously debug-only via NPCDebug). Deliberately separate
## from get_dialogue_line()'s ambient Talk-line pools above: this is asked
## explicitly about a specific target and answers from that specific
## relationship value, not from the asked NPC's own mood/irritability.
## Replies are intentionally name-agnostic text (the question already named
## the target) so pools stay reusable for any target, player or NPC alike.
const RELATIONSHIP_DIALOGUE_HOSTILE: Array[String] = [
	"\"I hate them.\"",
	"\"Let's not talk about that.\"",
	"\"Stay out of it.\"",
]
const RELATIONSHIP_DIALOGUE_COLD: Array[String] = [
	"\"Not a fan, honestly.\"",
	"\"We don't really get along.\"",
	"\"Could be better.\"",
]
const RELATIONSHIP_DIALOGUE_NEUTRAL: Array[String] = [
	"\"They're alright, I guess.\"",
	"\"Can't say much either way.\"",
	"\"Haven't really thought about it.\"",
]
const RELATIONSHIP_DIALOGUE_FRIENDLY: Array[String] = [
	"\"They're pretty cool.\"",
	"\"I like them.\"",
	"\"Good to have around.\"",
]
const RELATIONSHIP_DIALOGUE_CLOSE: Array[String] = [
	"\"They're really cool!\"",
	"\"Honestly? One of my favorites here.\"",
	"\"I really like them.\"",
]

func get_relationship_dialogue_line(target_id: String) -> String:
	var pool: Array[String] = RELATIONSHIP_DIALOGUE_NEUTRAL
	match get_relationship_label(target_id):
		"Hostile":  pool = RELATIONSHIP_DIALOGUE_HOSTILE
		"Cold":     pool = RELATIONSHIP_DIALOGUE_COLD
		"Friendly": pool = RELATIONSHIP_DIALOGUE_FRIENDLY
		"Close":    pool = RELATIONSHIP_DIALOGUE_CLOSE
	return pool[randi() % pool.size()]

# ─── Relaxing (Aug 2026) ─────────────────────────────────────────────────
const RELAX_BUDGET_BASELINE: float = 1.0   ## game-hours/day
const RELAX_BUDGET_LAZY: float = 2.0

var _relax_time_used_today: float = 0.0
var _relax_day_clock: float = 0.0   ## game-hours since the last daily reset; wraps at 24
var _relax_job_request_count: int = 0

func has_lazy_trait() -> bool:
	return float(personality.get("work_ethic", 0.5)) < TRAIT_BAND_LOW

func get_relax_daily_budget() -> float:
	return RELAX_BUDGET_LAZY if has_lazy_trait() else RELAX_BUDGET_BASELINE

func get_relax_time_remaining_today() -> float:
	return maxf(0.0, get_relax_daily_budget() - _relax_time_used_today)

func spend_relax_time(h: float) -> void:
	_relax_time_used_today += h

func is_relaxing() -> bool:
	return brain != null and brain.is_relaxing()

func reset_relax_job_requests() -> void:
	_relax_job_request_count = 0

## Called by NPCTalkMenuUI before forcing a job-type command on an NPC
## that's currently relaxing. First call this relax session refuses
## (returns false — caller shows the refusal line, job does NOT happen).
## Second+ call complies, but costs the player -3 relationship.
func request_job_while_relaxing() -> bool:
	_relax_job_request_count += 1
	if _relax_job_request_count <= 1:
		return false
	var applied: float = _adjust_relationship("player", -3.0)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -3.0, "pulled from relaxing to do a job")
	log_action("Player interrupted %s's relaxation (%+.1f relationship)" % [npc_name, applied])
	return true

const RELAXING_REFUSAL_LINES: Array[String] = [
	"\"I'm relaxing right now.\"",
	"\"Can it wait? I'm on a break.\"",
	"\"Give me a minute, I'm resting.\"",
]
func get_relaxing_refusal_line() -> String:
	return RELAXING_REFUSAL_LINES[randi() % RELAXING_REFUSAL_LINES.size()]

## Per-item restore estimates used ONLY to compute how many real items to
## consume during catch-up — the actual restore applied always comes from
## the real item's own consume_as_food()/take_bite()/take_drink() call,
## never this constant directly. Rough averages across the giveable item
## types (dish/produce/can-bite ≈ 45 hunger; STANDARD_HYDRATION = 21.5).
const CATCHUP_MEAL_RESTORE_ESTIMATE: float = 45.0
const CATCHUP_DRINK_RESTORE_ESTIMATE: float = 21.5
## Matches PassedOutActivity.REGEN_PER_GAME_HOUR (NPCBrain.gd) — duplicated
## here since that constant lives on a different class; keep these in sync
## if that value ever changes.
const CATCHUP_PASSED_OUT_REGEN_PER_GAME_HOUR: float = 15.0

## Entry point called by NPC.catch_up_all() for each NPC. Order matters:
## needs/energy run first so mood's needs-driven target reflects the
## post-catch-up state, not stale pre-skip numbers.
func catch_up_time(h: float, avg_mood_before: float) -> void:
	if h <= 0.0:
		return
	var needs_avg_before: float = (energy + hunger + thirst) / 3.0
	_catch_up_hunger_and_thirst(h)
	_catch_up_energy(h)
	_catch_up_relax_budget(h)
	var needs_avg_after: float = (energy + hunger + thirst) / 3.0
	_catch_up_mood(h, avg_mood_before, (needs_avg_before + needs_avg_after) / 2.0)
	if NPCDebug.enabled:
		NPCDebug.log_catchup(self, h)

## Full drain for the duration, then an ESTIMATE of how many real meals/
## drinks would've been needed to offset that — actually consumed from
## real available world items (capped by whatever's actually there; an
## empty bunker just means the NPC goes hungry, same as it should). This
## is deliberately an approximation of WHEN — we don't simulate which
## specific hour they'd have eaten, only roughly how many real items
## would have been used.
func _catch_up_hunger_and_thirst(h: float) -> void:
	hunger = maxf(0.0, hunger - HUNGER_DRAIN_PER_GAME_HOUR * h)
	var meals_needed: int = int(floor((HUNGER_DRAIN_PER_GAME_HOUR * h) / CATCHUP_MEAL_RESTORE_ESTIMATE))
	for i in range(meals_needed):
		if hunger >= 90.0:
			break   ## already comfortably fed from what's been eaten so far
		var item: Node = NPCItemUser.find_loose_item(self, Callable(NPCItemUser, "is_edible"))
		if item == null:
			break   ## nothing available — stays hungry, same as reality
		if item is DishItem or item is FarmProduceItem:
			hunger = minf(100.0, hunger + item.consume_as_food())
		elif item.has_method("take_bite"):
			hunger = minf(100.0, hunger + item.take_bite())

	thirst = maxf(0.0, thirst - THIRST_DRAIN_PER_GAME_HOUR * h)
	var drinks_needed: int = int(floor((THIRST_DRAIN_PER_GAME_HOUR * h) / CATCHUP_DRINK_RESTORE_ESTIMATE))
	for i in range(drinks_needed):
		if thirst >= 90.0:
			break
		var item: Node = NPCItemUser.find_loose_item(self, Callable(NPCItemUser, "is_drinkable_bottle"))
		if item == null:
			break
		if item.has_method("take_drink"):
			thirst = minf(100.0, thirst + item.take_drink())

## Straight drain; if it would have crossed 0 partway through, applies
## the SAME neuroticism-scaled mood drop PassedOutActivity.enter() uses
## (once, not per-hour) and regenerates the remaining time at its rate —
## ties directly into the pass-out mechanic instead of inventing a
## separate energy-recovery model for catch-up specifically.
func _catch_up_energy(h: float) -> void:
	var drain: float = ENERGY_DRAIN_PER_GAME_HOUR * h
	if drain <= energy:
		energy -= drain
		return
	var hours_until_zero: float = energy / ENERGY_DRAIN_PER_GAME_HOUR
	var remaining_hours: float = h - hours_until_zero
	var mood_drop: float = randf_range(1.0, 10.0 * neuroticism_trait_mult())
	mood = clampf(mood - mood_drop, 0.0, 100.0)
	if NPCDebug.enabled:
		NPCDebug.log_mood_event(self, -mood_drop, "passed out (time-skip catch-up)")
	energy = minf(100.0, 0.0 + CATCHUP_PASSED_OUT_REGEN_PER_GAME_HOUR * remaining_hours)

## Deducts today's relax budget proportionally to how much of a day the
## skip covered — a 6h skip removes 25% of the daily budget (baseline:
## 60min → 45min remaining), 12h removes 50% (→ 30min). This is what
## stops an NPC "banking" a full untouched hour across a skip and
## dumping it all in one greedy session right after waking. Runs
## _tick_relax_day() FIRST so a skip crossing a full day boundary resets
## to a fresh budget as it should, then applies the proportional
## deduction only to whatever fractional day remains after that.
func _catch_up_relax_budget(h: float) -> void:
	_tick_relax_day(h)
	var effective_hours: float = fmod(h, 24.0) if h >= 24.0 else h
	var budget: float = get_relax_daily_budget()
	var fraction: float = clampf(effective_hours / 24.0, 0.0, 1.0)
	_relax_time_used_today = clampf(_relax_time_used_today + budget * fraction, 0.0, budget)

## Needs-driven pull and random drift are _tick_mood()'s own formulas,
## evaluated once with a large h instead of accumulating over many small
## ticks — both are simple enough (move_toward, flat random range) that
## batching doesn't lose meaningful accuracy. `needs_avg_blend` is the
## average of pre- and post-catch-up needs, a rough stand-in for "how
## needs behaved across the whole window" rather than just the endpoint
## (needs dipped low mid-skip then got restored — using only the end
## value would understate how much that dip should have dragged mood).
## Contagion is a single blended pull toward the PRE-skip bunker average
## (avg_mood_before, snapshotted once in catch_up_all()), scaled by
## elapsed time and clamped so it can't overshoot past that average —
## deliberately approximate, not a real per-NPC-pair simulation.
func _catch_up_mood(h: float, avg_mood_before: float, needs_avg_blend: float) -> void:
	var mood_target: float = 100.0 if needs_avg_blend >= MOOD_FINE_THRESHOLD else needs_avg_blend
	var rate: float = MOOD_CHANGE_PER_GAME_HOUR
	if mood_target > mood:
		rate *= _mood_recovery_trait_mult()
	mood = move_toward(mood, mood_target, rate * h)

	var blend: float = clampf(MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * h, 0.0, 1.0)
	mood = clampf(mood + (avg_mood_before - mood) * blend, 0.0, 100.0)

	mood = clampf(mood + randf_range(-MOOD_DRIFT_MAX_PER_GAME_HOUR, MOOD_DRIFT_MAX_PER_GAME_HOUR)
		* neuroticism_trait_mult() * h, 0.0, 100.0)

## List of every OTHER currently-live NPC, for building one Ask-About button
## per NPC in NPCTalkMenuUI. The player is handled separately in the UI
## (fixed "What do you think of me?" button, target_id "player") since
## there's always exactly one and it isn't in the "npc" group.
## FUTURE WORK: currently lists every live NPC regardless of whether the
## player/NPC has ever "met" them — no acquaintance gating exists yet.
func get_other_npc_topics() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other):
			continue
		if not ("npc_id" in other) or not ("npc_name" in other):
			continue
		out.append({"id": String(other.npc_id), "name": String(other.npc_name)})
	return out