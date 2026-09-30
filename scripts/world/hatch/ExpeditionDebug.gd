extends RefCounted
## ExpeditionDebug.gd (Sep 2026) — F7 → EXPEDITIONS: dev tools for testing
## the Surface Hatch without waiting hours of game time or rolling for the
## outcome you want. Uses only SurfaceHatch's public state (active,
## discovered, depletion, reports) and API (launch, get_candidates), the
## same way tools/tests/surface_hatch_world_smoke.gd does. Nothing here
## ships as gameplay.
##
## "Resident" = the living resident nearest the player (stand beside who
## you want to send). "Next trip" = the expedition that's due back soonest.

const T := preload("res://scripts/world/hatch/ExpeditionTables.gd")

static func _hatch(tree: SceneTree) -> Node:
	var h: Node = tree.get_first_node_in_group("surface_hatch")
	if h == null:
		_say("No Surface Hatch in this world.")
	return h

static func _say(text: String) -> void:
	print("[Expedition] %s" % text)
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO, text)

static func _nearest_resident(tree: SceneTree) -> Node:
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	var best: Node = null
	var best_d: float = INF
	for n: Node in tree.get_nodes_in_group("npc"):
		if not (n is Node3D) or (n.has_method("is_dead") and n.is_dead()):
			continue
		var d: float = (n as Node3D).global_position.distance_to(player.global_position) if player != null else 0.0
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		_say("No resident nearby to send.")
	return best

## The trip due back soonest (or null).
static func _next_trip(hatch: Node) -> Dictionary:
	var best: Dictionary = {}
	for r: Dictionary in hatch.get("active"):
		if best.is_empty() or float(r["return_h"]) < float(best["return_h"]):
			best = r
	if best.is_empty():
		_say("Nobody is topside.")
	return best

# ─── F7 rows ────────────────────────────────────────────────────────────────
## Stand the player at the foot of the ladder (then press E to open it).
static func go_to_hatch(tree: SceneTree) -> void:
	var hatch: Node = _hatch(tree)
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	if hatch == null or player == null:
		return
	var fwd: Vector3 = (hatch as Node3D).global_transform.basis.z.normalized()
	player.global_position = (hatch as Node3D).global_position + fwd * 1.4 + Vector3(0.0, 1.0, 0.0)
	_say("At the hatch. Press E to open it.")

## Send the nearest resident (healed and rested so they're eligible) to the
## first known destination with the given approach.
static func send_nearest(tree: SceneTree, approach_id: String) -> void:
	var hatch: Node = _hatch(tree)
	var npc: Node = _nearest_resident(tree)
	if hatch == null or npc == null:
		return
	var reason: String = String(hatch.call("launch_block_reason"))
	if reason != "":
		_say(reason)
		return
	var dests: Array = hatch.call("get_available_destinations")
	if dests.is_empty():
		_say("No known destinations. Use 'Reveal All Destinations'.")
		return
	npc.set("health", maxf(float(npc.get("health")), 80.0))
	npc.set("energy", maxf(float(npc.get("energy")), 80.0))
	var who: String = String(npc.get("npc_name"))
	var dest: String = String(dests[0])
	if bool(hatch.call("launch", npc, dest, approach_id)):
		_say("%s went topside to the %s (%s)." % [who, T.DESTINATIONS[dest]["name"], T.APPROACHES[approach_id]["name"]])
	else:
		_say("%s couldn't be sent (not a candidate?)." % who)

## Every trip comes back right now, with the outcome it already rolled.
static func return_all_now(tree: SceneTree) -> void:
	var hatch: Node = _hatch(tree)
	if hatch == null:
		return
	var n: int = 0
	for r: Dictionary in hatch.get("active"):
		r["return_h"] = NPCClock.now() - 0.1
		r["due_h"] = minf(float(r["due_h"]), NPCClock.now() - 0.1)
		if String(r["outcome"].get("fate", "returned")) != "returned":
			r["due_h"] = NPCClock.now() - T.WRITE_OFF_AFTER_HOURS - 0.1   ## resolve the loss now too
		n += 1
	_say("%d trip%s resolving now (as rolled)." % [n, "" if n == 1 else "s"])

## Rewrite the soonest trip's outcome, then bring it back now.
##   "safe": back unhurt with a full haul; "injured": back with a cut arm;
##   "lost": never comes back; "deserted": leaves the bunker for good.
static func force_next(tree: SceneTree, kind: String) -> void:
	var hatch: Node = _hatch(tree)
	if hatch == null:
		return
	var r: Dictionary = _next_trip(hatch)
	if r.is_empty():
		return
	var o: Dictionary = r["outcome"]
	match kind:
		"safe":
			o["fate"] = "returned"
			o["hazards"] = []
			o["loot"] = ["food_can", "water_bottle", "seed", "scrap_metal", "fuel_can"]
		"injured":
			o["fate"] = "returned"
			o["hazards"] = [{"id": "glass", "text": "cut their left arm on broken glass", "injury": "open_wound", "part": "LEFT_ARM"}]
		"lost", "deserted":
			o["fate"] = kind
	r["return_h"] = NPCClock.now() - 0.1
	r["due_h"] = NPCClock.now() - 0.1 - (T.WRITE_OFF_AFTER_HOURS if kind in ["lost", "deserted"] else 0.0)
	_say("%s's trip forced: %s (resolves within a second)." % [r["npc_name"], kind])

## Make the soonest trip overdue (tests the overdue notice) without resolving it.
static func make_overdue(tree: SceneTree) -> void:
	var hatch: Node = _hatch(tree)
	if hatch == null:
		return
	var r: Dictionary = _next_trip(hatch)
	if r.is_empty():
		return
	r["due_h"] = NPCClock.now() - 0.1
	r["return_h"] = maxf(float(r["return_h"]), NPCClock.now() + 2.0)
	r["overdue_noted"] = false
	_say("%s is now overdue (back in ~2 game hours)." % r["npc_name"])

static func reveal_all(tree: SceneTree) -> void:
	var hatch: Node = _hatch(tree)
	if hatch == null:
		return
	var disc: Array = hatch.get("discovered")
	for id: String in T.DESTINATION_ORDER:
		if not disc.has(id):
			disc.append(id)
	hatch.emit_signal("expeditions_changed")
	_say("All %d destinations known." % T.DESTINATION_ORDER.size())

static func reset_depletion(tree: SceneTree) -> void:
	var hatch: Node = _hatch(tree)
	if hatch == null:
		return
	(hatch.get("depletion") as Dictionary).clear()
	hatch.emit_signal("expeditions_changed")
	_say("Every site is fully stocked again.")

static func dump(tree: SceneTree) -> void:
	var hatch: Node = _hatch(tree)
	if hatch == null:
		return
	var now: float = NPCClock.now()
	print("══════ EXPEDITIONS (t=%.2fh) ══════" % now)
	print("  known: %s" % ", ".join(hatch.call("get_available_destinations")))
	for id: String in T.DESTINATION_ORDER:
		print("  %-15s depletion %.2f" % [id, float(hatch.call("get_depletion", id))])
	for r: Dictionary in hatch.get("active"):
		var o: Dictionary = r["outcome"]
		print("  TOPSIDE %s → %s (%s): due in %.1fh, back in %.1fh, fate %s, hazards %d, loot %s" % [r["npc_name"], r["dest"],
			r["approach"], float(r["due_h"]) - now, float(r["return_h"]) - now, o.get("fate", "?"),
			(o.get("hazards", []) as Array).size(), str(o.get("loot", []))])
	for c: Dictionary in hatch.call("get_candidates"):
		print("  candidate %s%s" % [c["npc"].get("npc_name"), "" if String(c.get("reason", "")) == "" else " — " + String(c["reason"])])
	for rep: Dictionary in (hatch.get("reports") as Array).slice(0, 3):
		print("  report: %s" % rep["title"])
	_say("Expedition state printed to the console.")
