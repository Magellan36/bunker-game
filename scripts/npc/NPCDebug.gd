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

## One-shot full snapshot of every NPC — call from the F7 "Print NPC Debug
## State" row. Always prints regardless of `enabled` (it's an explicit,
## on-demand request, not continuous logging).
static func dump_all(tree: SceneTree) -> void:
	var npcs: Array = tree.get_nodes_in_group("npc")
	print("── NPC Debug Dump (%d NPCs) ──────────────────────────" % npcs.size())
	for npc: Node in npcs:
		if not is_instance_valid(npc):
			continue
		var activity: String = npc.brain.current_label() if ("brain" in npc and npc.brain != null) else "?"
		var held: String = npc.held_item.name if ("held_item" in npc and npc.held_item != null) else "none"
		print("  %s  pos=%s  E=%.0f H=%.0f T=%.0f  activity=%s  held=%s  stuck_recoveries=%d" % [
			npc.npc_name if "npc_name" in npc else "?",
			npc.global_position if "global_position" in npc else Vector3.ZERO,
			npc.energy if "energy" in npc else -1.0,
			npc.hunger if "hunger" in npc else -1.0,
			npc.thirst if "thirst" in npc else -1.0,
			activity,
			held,
			npc._stuck_recoveries if "_stuck_recoveries" in npc else -1,
		])
if "skills" in npc:
		var display: Dictionary = {}
		for k: String in npc.skills.keys():
			display[k] = int(round(float(npc.skills[k]) * 10.0))
		print("    skills: %s" % str(display))
	print("───────────────────────────────────────────────────────")