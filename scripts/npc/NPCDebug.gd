extends RefCounted
class_name NPCDebug
## NPCDebug.gd  (NPC Pass 2, Part 7)
## Centralized, toggleable debug logging for the whole NPC system. Off by
## default; flip via the F7 "Toggle NPC Debug Logging" row (or call
## NPCDebug.enabled = true directly from anywhere for a quick one-off).
## Every log line is prefixed "[NPC:<name>]" or "[JobBoard]" so console
## output can be grepped/filtered per-NPC or per-system during a bug hunt.
##
## Deliberately NOT an autoload — it's pure static state on a global class,
## which is enough for a dev-only toggle and avoids one more autoload entry.

static var enabled: bool = false

static func _fmt(npc: Node) -> String:
	if npc != null and "npc_name" in npc:
		return "[NPC:%s]" % npc.npc_name
	return "[NPC:?]"

## Activity switches — call from NPCBrain._start()/_think() interrupt path.
static func log_activity(npc: Node, from_label: String, to_label: String) -> void:
	if not enabled:
		return
	print("%s activity: %s -> %s" % [_fmt(npc), from_label, to_label])

## Need crossing an interest threshold (e.g. dropping below 55/60) — call
## from _tick_needs() or an activity's score() the first time it goes live.
static func log_need_threshold(npc: Node, need_name: String, value: float) -> void:
	if not enabled:
		return
	print("%s %s dropped to %.1f" % [_fmt(npc), need_name, value])

## Stuck-recovery firing — call from NPC._recover_from_stuck().
static func log_stuck(npc: Node) -> void:
	if not enabled:
		return
	print("%s STUCK — aborting current activity and re-scoring" % _fmt(npc))

## Job lifecycle — call from JobBoard (_mark/claim/release) and JobActivity.
static func log_job(event: String, job: Dictionary, npc: Node = null) -> void:
	if not enabled:
		return
	var who: String = _fmt(npc) if npc != null else "[JobBoard]"
	print("%s job %s: %s (id=%s)" % [who, event, job.get("type", "?"), job.get("id", "?")])

## Mood tick breakdown (Part 20) — called from NPC._tick_mood every ~5s
## when enabled. Every contributing source is shown SEPARATELY (needs-pull,
## global social contagion, random drift) so a mood change is never
## ambiguous about why — this was an explicit requirement, not a nice-to-have.
static func log_mood(npc: Node, needs_delta: float, contagion_delta: float,
		drift_delta: float, mood_after: float) -> void:
	if not enabled:
		return
	print("%s mood: needs=%+.2f contagion=%+.2f drift=%+.2f -> %.1f" % [
		_fmt(npc), needs_delta, contagion_delta, drift_delta, mood_after])

## Irritability tick breakdown (Part 20) — same cadence/reasoning as log_mood.
static func log_irritability(npc: Node, need_contrib: float, mood_contrib: float,
		trait_mult: float, target: float, value_after: float) -> void:
	if not enabled:
		return
	print("%s irritability: needs_contrib=%.1f mood_contrib=%.1f trait_mult=%.2f target=%.1f -> %.1f" % [
		_fmt(npc), need_contrib, mood_contrib, trait_mult, target, value_after])

## Forgetfulness roll outcome (Part 20) — logs EVERY roll, not just
## successful diversions, so the chance itself (already folding in hunger/
## thirst/mood/trait) is visible even when nothing was triggered.
static func log_forgetfulness_roll(npc: Node, chance: float, triggered: bool) -> void:
	if not enabled:
		return
	var outcome: String = "DIVERTED to wandering" if triggered else "stayed on task"
	print("%s forgetfulness roll: chance=%.0f%% -> %s" % [_fmt(npc), chance * 100.0, outcome])

## Relationship tick (Part 22) — logs the full current relationships dict
## every ~5s tick when enabled, same cadence as log_mood/log_irritability.
static func log_relationship_tick(npc: Node) -> void:
	if not enabled:
		return
	print("%s relationships: %s" % [_fmt(npc), str(npc.relationships)])

## Discrete relationship events (Part 24) — Give/Takeaway, as opposed to
## log_relationship_tick's continuous background drift. Always worth a
## line since these are deliberate player actions, not ambient ticking.
static func log_relationship_event(npc: Node, target_id: String, delta: float, reason: String) -> void:
	if not enabled:
		return
	var after: float = npc.get_relationship(target_id) if npc.has_method("get_relationship") else 0.0
	print("%s relationship event (%s): %s %+.1f -> %.1f" % [_fmt(npc), reason, target_id, delta, after])

## One-shot full snapshot of every NPC — call from the F7 "Print NPC Debug
## State" row. Always prints regardless of `enabled` (it's an explicit,
## on-demand request, not continuous logging). Part 19 — expanded from a
## single dense line per NPC to a full multi-line block covering every
## piece of state Part 14 added (health, status, forgetfulness chance,
## speed multiplier, pass-out) plus the personality/mood/seed stubs and the
## movement-lock flag (Part 13/18), so a single dump gives the complete
## picture during a bug hunt instead of needing several different checks.
static func dump_all(tree: SceneTree) -> void:
	var npcs: Array = tree.get_nodes_in_group("npc")
	print("═══ NPC Debug Dump (%d NPCs) ═══════════════════════════" % npcs.size())
	for npc: Node in npcs:
		if not is_instance_valid(npc):
			continue
		_dump_one(npc)
	print("═════════════════════════════════════════════════════════")

static func _dump_one(npc: Node) -> void:
	var npc_name: String = npc.npc_name if "npc_name" in npc else "?"
	var pos: Vector3 = npc.global_position if "global_position" in npc else Vector3.ZERO
	var activity: String = npc.brain.current_label() if ("brain" in npc and npc.brain != null) else "?"
	var held: String = npc.held_item.name if ("held_item" in npc and npc.held_item != null) else "none"
	var locked: bool = npc._movement_locked if "_movement_locked" in npc else false
	var stuck: int = npc._stuck_recoveries if "_stuck_recoveries" in npc else -1

	print("── %s ──────────────────────────────" % npc_name)
	print("  pos=%s  activity=%s  held=%s" % [pos, activity, held])
	print("  movement_locked=%s  stuck_recoveries=%d" % [locked, stuck])

	if "health" in npc and "energy" in npc and "hunger" in npc and "thirst" in npc:
		print("  Health=%.1f  Energy=%.1f  Hunger=%.1f  Thirst=%.1f" % [
			npc.health, npc.energy, npc.hunger, npc.thirst])

	if npc.has_method("get_status_speed_multiplier") and npc.has_method("is_passed_out"):
		print("  speed_multiplier=%.2f  passed_out=%s" % [
			npc.get_status_speed_multiplier(), npc.is_passed_out()])

	if npc.has_method("get_forgetfulness_chance"):
		print("  forgetfulness_chance=%.0f%%" % (npc.get_forgetfulness_chance() * 100.0))

	if npc.has_method("get_status_labels"):
		print("  status: %s" % ", ".join(npc.get_status_labels()))

	if "skills" in npc:
		var display: Dictionary = {}
		for k: String in npc.skills.keys():
			display[k] = int(round(float(npc.skills[k]) * 10.0))
		print("  skills: %s" % str(display))

	if "generation_seed" in npc and "mood" in npc and "personality" in npc:
		var words: String = ", ".join(npc.get_personality_words()) if npc.has_method("get_personality_words") else "?"
		print("  seed=%d  personality: %s" % [npc.generation_seed, words])
		print("  mood=%.1f  irritability=%.1f%% (%s)" % [
			npc.mood, npc.irritability if "irritability" in npc else -1.0,
			npc.get_irritability_label() if npc.has_method("get_irritability_label") else "?"])

	if "relationships" in npc and npc.has_method("get_relationship_label"):
		var rel_display: Dictionary = {}
		for k: String in npc.relationships.keys():
			rel_display[k] = "%.0f (%s)" % [npc.relationships[k], npc.get_relationship_label(k)]
		print("  relationships: %s" % str(rel_display))