extends NPCActivity
class_name NPCSessionActivity
## NPCSessionActivity.gd (Aug 2026) — shared base for every "sustained
## session" job (fetch → travel → apply → loop until nothing's left):
## CleaningActivity, RefuelActivity, GardeningActivity, and any future
## job of the same shape. Extracted after finding the SAME two bug
## classes independently in each hand-written implementation:
##   1. Interruption mid-task — PutAwayHeldItemActivity's flat score
##      could win the very next think-cycle and abort a fetch/travel in
##      progress. Found and fixed three separate times before this
##      refactor existed to prevent a fourth.
##   2. Unbounded retry with no exclusion tracking — retrying the exact
##      same doomed target forever because nothing recorded "already
##      tried this, it doesn't work." Caused a frame-stall in Cleaning
##      and a genuine stack-overflow crash in Gardening.
## This class does NOT dictate HOW a subclass picks/fetches/applies a
## target — each job's selection logic stays bespoke in its own file,
## since Cleaning/Refuel/Gardening genuinely need different shapes
## there (raycasted item selection vs. a generator sweep vs. per-cell
## claims). What it enforces is the handful of things that turned out
## to matter every single time.

## Aug 2026 — every session activity is non-interruptible BY DEFAULT.
## None of the three built so far have ever had a genuinely safe
## mid-session gap except Cleaning's own deliberate exception (see
## CleaningActivity.interruptible() — a real "between items" gap where
## nothing's held and nothing's claimed). Override only with a comment
## explaining the specific safe window, matching that precedent.
func interruptible() -> bool:
	return false

## "target key" -> true, THIS SESSION ONLY. Deliberately just a
## Dictionary, not a typed structure — each job's natural key shape
## differs (item instance_id, "trayid:cell", generator instance_id...).
## Reset in each subclass's own enter() — this base can't know when a
## "session" starts for a given job, that's still the subclass's call.
var _skipped: Dictionary = {}

func _is_skipped(key: String) -> bool:
	return _skipped.has(key)

func _mark_skipped(key: String) -> void:
	_skipped[key] = true

## Aug 2026 — every session activity's debug_info() MUST include an
## "activity" key naming itself (both debug dumps key off this). The
## base default makes a missing override immediately obvious in the
## dump instead of silently showing nothing — exactly the kind of gap
## that let the three Command wrapper classes go unnoticed until this
## pass (see NPCCommandWrapperActivity.gd).
func debug_info() -> Dictionary:
	return {"activity": "session (debug_info() not overridden — see NPCSessionActivity.gd)"}

## Shared "point 1m out from the target, toward the NPC" approach-point
## math — was hand-copied identically into Refuel and Gardening
## already. Cleaning doesn't need it (its targets are loose items
## approached directly, not stationary trays/generators approached
## from a direction).
static func approach_point(npc: NPC, target: Node, distance: float = 1.0) -> Vector3:
	var t3: Node3D = target as Node3D
	var to_npc: Vector3 = npc.global_position - t3.global_position
	to_npc.y = 0.0
	if to_npc.length() < 0.01:
		to_npc = Vector3(0.0, 0.0, 1.0)   ## degenerate case: npc exactly at center
	return t3.global_position + to_npc.normalized() * distance

## Shared item-name fallback — was hand-copied (as _display_name()) into
## both Cleaning and Gardening already.
static func display_name(item: Node) -> String:
	if item == null:
		return "?"
	return item.get_display_name() if item.has_method("get_display_name") else str(item.name)

## Call from the END of every subclass's own exit() — not automatic,
## since a subclass's exit() always has its own claim-release work to
## do first that this base can't know about (item claims, cell claims,
## work-banner hiding...). Zeroes velocity (stops the "NPC coasts into
## a wall" artifact a mid-session interruption used to leave behind —
## root-caused from a live debug capture) and logs the exact state at
## exit when debug logging is on and the session didn't end cleanly.
static func on_session_exit(npc: NPC, activity_name: String, finished_cleanly: bool, state_detail: String) -> void:
	if NPCDebug.enabled and not finished_cleanly:
		NPCDebug.log_cleaning(npc, "%s exited early" % activity_name, state_detail)
	npc.velocity = Vector3.ZERO
