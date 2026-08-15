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

## Aug 2026 — call whenever a has_method()-gated ACTION call comes back
## false (something meant to happen, not a plain capability query with
## an already-planned fallback). Exists specifically because
## npc_deposit_trash() was called from two files behind exactly this
## kind of guard for an unknown length of time without ever being
## defined anywhere in the codebase — has_method() silently returning
## false is otherwise completely invisible, and the caller either had no
## fallback at all or one that looked like an ordinary occasional
## failure rather than a structural bug. Always fires (not gated on
## `enabled`) since this represents an actual code defect, not routine
## gameplay flow.
static func log_missing_method(caller_context: String, target: Object, method_name: String) -> void:
	push_warning("[NPCDebug] %s: %s does not implement expected method '%s()' — action silently skipped" \
		% [caller_context, (target.get_class() if target != null else "null"), method_name])

## Activity switches — call from NPCBrain._start()/_think() interrupt path.
static func log_activity(npc: Node, from_label: String, to_label: String) -> void:
	if not enabled:
		return
	print("%s activity: %s -> %s" % [_fmt(npc), from_label, to_label])

## Aug 2026 — logs the actual score comparison behind an interrupt
## decision, called right before log_activity() at the one place this
## decision is made (NPCBrain._think()). This is what answers "why did
## my NPC's job get dropped" directly, instead of needing to infer it
## from a bare label transition.
static func log_interrupt(npc: Node, from_label: String, from_score: float, to_label: String, to_score: float, margin: float) -> void:
	if not enabled:
		return
	print("%s INTERRUPTED: %s (score=%.2f) -> %s (score=%.2f, needed >%.2f)" \
		% [_fmt(npc), from_label, from_score, to_label, to_score, from_score + margin])

## Aug 2026 — canary for the exact bug class that produced the
## trash-delivery loop: an activity reports itself safe to interrupt
## (interruptible() == true) while the NPC is still physically holding
## an item. Not automatically wrong on its own (some activities are
## legitimately interruptible while holding something transient), but
## distinct and loud enough that a recurring pattern here is immediately
## greppable, instead of requiring a manual trace through scoring and
## interrupt logic to even notice — which is what this one took.
static func log_suspicious_interrupt(npc: Node, from_label: String, to_label: String) -> void:
	if not enabled:
		return
	print("%s ⚠ SUSPICIOUS INTERRUPT: %s reported interruptible() while still holding an item -> %s" \
		% [_fmt(npc), from_label, to_label])

## Need crossing an interest threshold (e.g. dropping below 55/60) — call
## from _tick_needs() or an activity's score() the first time it goes live.
static func log_need_threshold(npc: Node, need_name: String, value: float) -> void:
	if not enabled:
		return
	print("%s %s dropped to %.1f" % [_fmt(npc), need_name, value])

## Aug 2026 — context/info params added so the console shows WHAT was
## interrupted, not just that something was. `info` is whatever the
## current activity's debug_info() returned (empty for activities that
## don't implement it, e.g. Wander/Relax).
static func log_stuck(npc: Node, context: String = "?", info: Dictionary = {}) -> void:
	if not enabled:
		return
	var detail: String = ""
	if not info.is_empty():
		var parts: Array = []
		for key: String in info.keys():
			parts.append("%s=%s" % [key, str(info[key])])
		detail = " [%s]" % ", ".join(parts)
	print("%s STUCK while %s%s — aborting current activity and re-scoring" % [_fmt(npc), context, detail])

## Aug 2026 — logged when the same obstruction (or none identifiable)
## has kept an NPC stuck across multiple consecutive recovery attempts,
## and it's about to give up forcing a cleanup and nudge free instead.
static func log_stuck_escalation(npc: Node, obstruction: Node, streak: int) -> void:
	if not enabled:
		return
	var name: String = "?"
	if obstruction != null and obstruction.has_method("get_display_name"):
		name = obstruction.get_display_name()
	elif obstruction != null and "npc_name" in obstruction:
		name = "NPC:%s" % obstruction.npc_name   ## Aug 2026 — the new NPC-vs-NPC case, so this reads clearly instead of a raw Godot node name
	elif obstruction != null:
		name = str(obstruction.name)
	print("%s STUCK ESCALATION — %s failed to clear the stall %d times in a row, nudging free instead of retrying" \
		% [_fmt(npc), name, streak])

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

## Discrete mood events (Aug 2026) — one-time mood changes tied to a
## specific cause (currently just passing out), as opposed to
## log_mood()'s continuous per-tick needs/contagion/drift breakdown.
static func log_mood_event(npc: Node, delta: float, reason: String) -> void:
	if not enabled:
		return
	print("%s mood event (%s): %+.1f -> %.1f" % [_fmt(npc), reason, delta, npc.mood])

## Time-skip catch-up (Aug 2026) — one summary line per NPC per skip, so
## it's visible what the estimate produced without stepping through it.
static func log_catchup(npc: Node, hours: float) -> void:
	if not enabled:
		return
	print("%s catch-up (%.1fh skip): hunger=%.1f thirst=%.1f energy=%.1f mood=%.1f" \
		% [_fmt(npc), hours, npc.hunger, npc.thirst, npc.energy, npc.mood])

## Snatch (Part 30) — every stage gets its own line, specifically because
## the earlier version was hard to debug when it silently failed. Always
## logs when enabled, distinct from the continuous relationship tick log.
static func log_snatch(npc: Node, stage: String, detail: String) -> void:
	if not enabled:
		return
	print("%s SNATCH [%s]: %s" % [_fmt(npc), stage, detail])

## Cleaning (Aug 2026) — mirrors log_snatch()'s staged pattern.
static func log_cleaning(npc: Node, stage: String, detail: String) -> void:
	if not enabled:
		return
	print("%s CLEANING [%s]: %s" % [_fmt(npc), stage, detail])

## One-shot full Cleaning-system snapshot — call from the F7 "Print NPC
## Cleaning Debug State" row. Always prints regardless of `enabled` (an
## explicit on-demand request, same convention as dump_all()). Covers:
## JobBoard's caches (including WHY something isn't ready yet — per-item
## remaining idle time, and trash blocked by a missing receptacle),
## every storage destination's current occupancy, and every NPC currently
## mid-clean with its exact phase/item/destination/session progress.
static func dump_cleaning_state(tree: SceneTree) -> void:
	print("═══ NPC Cleaning Debug Dump ═══════════════════════════")
	var snap: Dictionary = JobBoard.get_cleaning_debug_snapshot()
	print("Idle gate: %.1fs%s" % [
		float(snap["idle_gate_sec"]),
		" (DEBUG override active — real gameplay uses 90s)" if bool(snap["idle_gate_is_debug"]) else ""])
	print("Ready now — trash: %d   organizable: %d" % [int(snap["trash_count"]), int(snap["organizable_count"])])
	if int(snap["trash_blocked_by_no_receptacle"]) > 0:
		print("  ⚠ %d trash item(s) exist but no trash_receptacle in the level — permanently blocked until one's added" \
			% int(snap["trash_blocked_by_no_receptacle"]))

	var pending: Array = snap["pending"]
	if pending.is_empty():
		print("Pending (tracked, not yet idle-eligible): none")
	else:
		print("Pending (tracked, not yet idle-eligible): %d" % pending.size())
		for p: Dictionary in pending:
			print("  - %s: %.1fs elapsed / %.1fs remaining" % [p["name"], p["elapsed_sec"], p["remaining_sec"]])

	print("── Destinations (\"shelving\" group) ──")
	var dest_count: int = 0
	for candidate: Node in tree.get_nodes_in_group("shelving"):
		if not is_instance_valid(candidate):
			continue
		dest_count += 1
		print("  %s: %s" % [candidate.name, _describe_storage_room(candidate)])
	if dest_count == 0:
		print("  (none — no shelf/End Table/Dresser exists anywhere in the level)")

	print("── NPCs currently cleaning ──")
	var any_cleaning: bool = false
	for npc: Node in tree.get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or not ("brain" in npc) or npc.brain == null:
			continue
		if not npc.brain.has_method("get_current_activity_debug_info"):
			continue
		var info: Dictionary = npc.brain.get_current_activity_debug_info()
		if info.is_empty() or String(info.get("activity", "")) != "cleaning":
			continue
		any_cleaning = true
		var npc_name: String = npc.npc_name if "npc_name" in npc else "?"
		print("  %s: phase=%s item=%s is_trash=%s destination=%s session=%.0fs/%.0fs%s" % [
			npc_name, info.get("phase", "?"), info.get("item", ""), info.get("is_trash", false),
			info.get("destination", ""), info.get("session_elapsed", 0.0), info.get("session_duration", 0.0),
			" (forced/stuck-recovery)" if info.get("forced", false) else ""])
	if not any_cleaning:
		print("  (none)")
	print("═════════════════════════════════════════════════════════")

## Duck-typed room description — Shelving.gd uses `slots` (Array of
## per-slot stacks), LightStorage.gd (End Table/Dresser) uses `stored`
## (flat Array, null = empty slot). Anything joining "shelving" without
## either shape just reports as unknown rather than erroring.
static func _describe_storage_room(candidate: Node) -> String:
	if "slots" in candidate and candidate.slots is Array:
		var used: int = 0
		for stack in candidate.slots:
			if stack is Array and not stack.is_empty():
				used += 1
		return "shelf, %d/%d slots used" % [used, candidate.slots.size()]
	if "stored" in candidate and candidate.stored is Array:
		var used2: int = 0
		for slot in candidate.stored:
			if slot != null:
				used2 += 1
		var label: String = candidate.display_name if "display_name" in candidate else "storage"
		return "%s, %d/%d used" % [label, used2, candidate.stored.size()]
	return "(unknown storage type)"

## Aug 2026 — one-shot snapshot of EVERY NPC's current activity and its
## full debug_info(), whatever that activity is. dump_cleaning_state()
## stays Cleaning-specific (JobBoard caches, storage occupancy) — this
## is the general-purpose complement for diagnosing Gardening/Refuel/
## anything else without needing a dedicated dump per activity type.
## Always prints regardless of `enabled` (an explicit on-demand request,
## same convention as dump_all()/dump_cleaning_state()).
static func dump_job_state(tree: SceneTree) -> void:
	print("═══ NPC Job Debug Dump ════════════════════════════════")
	var any_npc: bool = false
	for npc: Node in tree.get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		any_npc = true
		var npc_name: String = npc.npc_name if "npc_name" in npc else "?"
		var label: String = npc.brain.current_label() if ("brain" in npc and npc.brain != null) else "?"
		var info: Dictionary = {}
		if "brain" in npc and npc.brain != null and npc.brain.has_method("get_current_activity_debug_info"):
			info = npc.brain.get_current_activity_debug_info()
		if info.is_empty():
			print("  %s: %s" % [npc_name, label])
		else:
			var parts: Array = []
			for key: String in info.keys():
				parts.append("%s=%s" % [key, str(info[key])])
			print("  %s: %s [%s]" % [npc_name, label, ", ".join(parts)])
	if not any_npc:
		print("  (no NPCs)")
	print("═════════════════════════════════════════════════════════")

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