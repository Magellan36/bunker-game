extends RefCounted
class_name NPCActivity
## NPCActivity.gd  (NPC Pass 2, Part 2)
## Base class for one thing an NPC can be doing. Subclasses live inline in
## NPCBrain.gd (wander/sit) and later parts add more (eat/drink/jobs).
## Lifecycle, driven by NPCBrain:
##   score(npc)     — static-ish utility score; higher wins. Called on think
##                    ticks for every candidate. Return <= 0.0 for "not now".
##   enter(npc)     — begin (set nav target etc).
##   tick(npc, dt)  — called every physics frame while active.
##   done(npc)      — return true when finished; brain then re-scores.
##   interruptible()— may a higher-scoring candidate cancel this mid-run?
##   exit(npc)      — cleanup (always called, on finish OR interrupt).
##   label()        — short display string ("Wandering", "Sitting"...), used
##                    by UI in Part 5.
##   begin_with_item(npc, item) — Part 28 — optional; only Given* activities
##                    (a player Give hand-off) implement this. Called once,
##                    right after enter(), whenever this activity is
##                    reached either via NPC.receive_item_from_player()'s
##                    force_command() sequence, or via a take_handoff()
##                    transition (Part 30) from another activity.
##   take_handoff()  — Part 30 — optional. Return a specific NPCActivity
##                    to switch to immediately (checked every tick, right
##                    after tick() runs), instead of finishing via done()
##                    and leaving the choice to normal think-cycle
##                    scoring. Used for SnatchActivity handing off to
##                    GivenEatActivity/GivenDrinkActivity on a successful
##                    grab. Returning non-null MUST be a one-shot — clear
##                    your own reference before returning it, so it never
##                    fires twice.

func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"
func begin_with_item(_npc: NPC, _item: Node) -> void: pass
func take_handoff() -> NPCActivity: return null

## Optional presentation hook. The attention controller may look toward this
## live world target, but utility scoring and lifecycle decisions never depend
## on whether attention is enabled or where it is looking.
func attention_target(_npc: NPC) -> Node3D: return null

## Optional safe-continuity hooks. Activities return semantic data only—never
## live Node references, animation phases, claims, or paths. The brain keeps at
## most one entry and offers it again only after normal utility selection has
## returned to an idle boundary.
func make_resume_intent(_npc: NPC) -> Dictionary: return {}
func resume_from_intent(_npc: NPC, _intent: Dictionary) -> bool: return false
func is_resume_candidate() -> bool: return false

## How much better a challenger must score before this activity yields.
## Purposeful activities keep a little inertia so near-tied utilities do not
## flap every think tick. Passive activities override this with a smaller
## value: idling should yield readily when the NPC finds something to do.
func switch_margin() -> float: return 2.0

## Optional (Aug 2026) — structured debug snapshot for NPCDebug's on-demand
## dumps. Empty Dictionary means "nothing interesting to show" (the
## default, for every activity that doesn't override this). An activity
## that DOES override it should include an "activity" String key so a
## dump can filter to just the activity type it cares about (see
## CleaningActivity.debug_info() for the pattern).
func debug_info() -> Dictionary: return {}

## Recovery-watchdog contract.  The brain samples this semantic snapshot at a
## low frequency; changing timers/phases count as real activity progress even
## when the body is correctly standing still.  Activities may override either
## hook, but the phase convention below covers the shared travel vocabulary.
func watchdog_progress_token(_npc: NPC) -> String:
	return str(debug_info())

func watchdog_expects_movement(_npc: NPC) -> bool:
	var phase: String = String(debug_info().get("phase", "")).to_lower()
	return phase in [
		"approach", "carrying", "deliver", "fetch", "fetching", "relocating",
		"seek", "travel", "travelling", "travel_to_storage", "travel_to_stove",
	]

## Only genuinely open-ended stationary states opt out of the broad lifecycle
## timeout. Their travel/approach phases remain watched.
func watchdog_allows_long_stationary(_npc: NPC) -> bool: return false

## Stable instrumentation identity. Unlike label(), this does not change with
## an activity's phase ("Getting food" -> "Eating"), so session spans and
## transition summaries remain groupable.
func debug_type() -> String:
	var script: Script = get_script() as Script
	var path: String = script.resource_path if script != null else ""
	return path.get_file().get_basename() if not path.is_empty() else get_class()

## Optional explanation for the score already computed by NPCBrain. This hook
## is called only while session capture is enabled and must remain observational.
func debug_score_reason(_npc: NPC, computed_score: float) -> StringName:
	return &"eligible" if computed_score > 0.0 else &"no_current_opportunity"
