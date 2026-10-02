extends Node
class_name BunkerPhase
## BunkerPhase.gd (Oct 2026)
## Owns the run's two acts. A new game starts in PRE_APOCALYPSE: the player
## shops, builds and wires with cash, the clock holds before Day 1, and the
## chosen survivors wait outside. Pressing Leave at the Surface Hatch seals
## the bunker (seal()): the shop closes for good, nothing new can be built,
## the survivors come in, and Day 1 starts. POST_APOCALYPSE then runs on what
## was prepared; demolished things drop salvage instead of refunding cash,
## and wire/pipe cost Metal from the Research Station.
##
## LEGACY is every world that didn't come through New Game: saves written
## before this feature, dev scenes run directly, and test harnesses. It keeps
## the old rules (cash economy, clock running, hatch open) so none of them
## change behaviour. F7 can move a dev world into either act.
##
## One instance, a child of MainWorld, found through the "bunker_phase"
## group. Other systems ask through the static helpers so a missing node
## (headless tools) reads as LEGACY. See docs/systems/phase/README.md.

signal phase_changed(phase: int)

enum Phase { LEGACY, PRE_APOCALYPSE, POST_APOCALYPSE }

const GROUP: StringName = &"bunker_phase"
## Game days after the seal before anyone can safely go topside.
const HATCH_LOCK_DAYS: float = 10.0
const NPC_SCENE_PATH: String = "res://scenes/npc/NPC.tscn"
const DRAFT_PATH: String = "res://scripts/ui/new_game/SurvivorDraft.gd"
## Before Day 1 supplies can be bought and stored but not put to use, and
## nothing wears out: no fuel burn, no water-quality loss, no filter or
## flashlight wear, no planting (Brannon, Oct 2026). Each system asks
## preparing(tree). Held-item use (eat, drink, refuel, filter swap, cooking,
## medical, planting...) is gated once in InteractionSystem through
## use_allowed(); an item opts back in with allows_use_before_day_one()
## (bottle refills at a dispenser, the flashlight switch, weapon reload).
const USE_LOCKED_TEXT: String = "Supplies can't be used until the apocalypse begins"
## Suffix for use prompts that are locked until Day 1.
const LOCKED_PROMPT_SUFFIX: String = "  ·  from Day 1"

var phase: int = Phase.LEGACY
## PlayerStats elapsed (real seconds) at the moment of the seal.
var sealed_at_elapsed: float = 0.0
## Survivors picked at New Game, waiting for the seal (SurvivorDraft
## candidate dicts, JSON-safe; display-only keys are dropped).
var pending_survivors: Array = []

var player_stats: PlayerStats = null
## MainWorld — residents are parented here, build mode is closed through it.
var world: Node = null


func _ready() -> void:
	add_to_group(GROUP)


# ─── Static queries (safe without a phase node) ─────────────────────────────
static func of(tree: SceneTree) -> BunkerPhase:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as BunkerPhase

static func preparing(tree: SceneTree) -> bool:
	var p: BunkerPhase = of(tree)
	return p != null and p.phase == Phase.PRE_APOCALYPSE

static func sealed(tree: SceneTree) -> bool:
	var p: BunkerPhase = of(tree)
	return p != null and p.phase == Phase.POST_APOCALYPSE

## Use-prompt helper: "[E] Eat (2/2)" → "[E] Eat (2/2)  ·  from Day 1"
## while preparing, so the prompt says why E won't work yet.
static func gate_prompt(tree: SceneTree, prompt: String) -> String:
	return prompt + LOCKED_PROMPT_SUFFIX if prompt != "" and preparing(tree) else prompt

## Whether a held item's E-use may run now.
static func use_allowed(tree: SceneTree, item: Object) -> bool:
	if not preparing(tree) or item == null:
		return true
	return item.has_method("allows_use_before_day_one") and bool(item.call("allows_use_before_day_one"))

## True (and tells the player why) when a held item's use must wait for Day 1.
static func block_use(tree: SceneTree, item: Object) -> bool:
	if use_allowed(tree, item):
		return false
	NotificationManager.feedback(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, USE_LOCKED_TEXT)
	return true


# ─── Queries ────────────────────────────────────────────────────────────────
func is_preparing() -> bool:
	return phase == Phase.PRE_APOCALYPSE

func is_sealed() -> bool:
	return phase == Phase.POST_APOCALYPSE

## Game days since the seal (0 outside POST_APOCALYPSE).
func days_since_seal() -> float:
	if not is_sealed() or player_stats == null:
		return 0.0
	return maxf(0.0, player_stats.get_elapsed() - sealed_at_elapsed) / player_stats.day_duration_seconds

## Whole days left before the hatch opens (0 once it's open, and always 0
## outside POST_APOCALYPSE).
func hatch_days_remaining() -> int:
	if not is_sealed():
		return 0
	return maxi(0, int(ceil(HATCH_LOCK_DAYS - days_since_seal() - 0.0001)))

## True when residents can be sent topside.
func hatch_open() -> bool:
	return phase == Phase.LEGACY or (is_sealed() and hatch_days_remaining() == 0)

## "3 days until it is safe to travel" / "1 day until ...".
func hatch_wait_text() -> String:
	var days: int = maxi(1, hatch_days_remaining())
	return "%d day%s until it is safe to travel" % [days, "" if days == 1 else "s"]

func pending_names() -> Array[String]:
	var out: Array[String] = []
	for c: Variant in pending_survivors:
		if c is Dictionary:
			out.append(String((c as Dictionary).get("name", "")))
	return out

## Everyone who will be in the bunker after the seal besides the player:
## residents already inside (since Oct 2026 the New Game picks arrive during
## preparation) plus anyone still waiting (preparation saves from before).
func resident_names() -> Array[String]:
	var out: Array[String] = []
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(npc) and not npc.is_queued_for_deletion() \
				and not (npc.has_method("is_dead") and bool(npc.call("is_dead"))):
			out.append(String(npc.get("npc_name")))
	out.append_array(pending_names())
	return out


## What the bunker holds right now — loose, stored or carried — for the Leave
## panel's readiness check:
## full-can, full-bottle and full-fuel-can equivalents (fractional) plus the
## people who will be eating — the player and every resident.
func supply_snapshot() -> Dictionary:
	var seen: Dictionary = {}
	## Loose items are "pickup"; anything put away on a shelf, in light
	## storage (dresser, end table...) or in a basket leaves "pickup" and
	## joins "shelved" — both count. Trash-bag records are trash, not stock.
	var items: Array = []
	items.append_array(get_tree().get_nodes_in_group("pickup"))
	items.append_array(get_tree().get_nodes_in_group("shelved"))
	var inventory: Node = world.get("inventory_manager") as Node if world != null else null
	if inventory != null and "slots" in inventory:
		items.append_array(inventory.get("slots") as Array)
	var cans: float = 0.0
	var bottles: float = 0.0
	var fuel: float = 0.0
	for item: Variant in items:
		if item == null or not is_instance_valid(item) or seen.has((item as Object).get_instance_id()):
			continue
		seen[(item as Object).get_instance_id()] = true
		var obj: Object = item as Object
		var kind: String = String(obj.get("shelf_item_type")) if "shelf_item_type" in obj else ""
		match kind:
			"food_can":
				cans += float(obj.get("_bites_left")) / float(_const(obj, "TOTAL_BITES", 2))
			"can_case":
				cans += float(obj.get("can_count"))
			"water_bottle":
				bottles += float(obj.get("current_fill_mL")) / float(_const(obj, "MAX_FILL_ML", 750.0))
			"water_case":
				bottles += float(obj.get("bottle_count"))
			"fuel_can":
				fuel += float(obj.get("_fuel_remaining")) / float(_const(obj, "FUEL_UNITS_TOTAL", 100.0))
	var people: int = resident_names().size() + 1
	var draft: GDScript = load(DRAFT_PATH) as GDScript
	var use: Dictionary = draft.call("daily_consumption", people) if draft != null else {}
	return {
		"people": people,
		"cans": cans,
		"bottles": bottles,
		"fuel_cans": fuel,
		"food_days": cans / maxf(0.001, float(use.get("cans", 1.0))),
		"water_days": bottles / maxf(0.001, float(use.get("bottles", 1.0))),
	}


static func _const(obj: Object, key: String, fallback: Variant) -> Variant:
	var script: Script = obj.get_script() as Script
	return script.get_script_constant_map().get(key, fallback) if script != null else fallback


# ─── Transitions ────────────────────────────────────────────────────────────
## New Game: the bunker is being prepared. Holds the clock at its start.
func begin_preparation() -> void:
	phase = Phase.PRE_APOCALYPSE
	sealed_at_elapsed = 0.0
	_apply_clock()
	phase_changed.emit(phase)

## Survivors waiting outside until the seal. Since Oct 2026 New Game spawns
## its picks straight away (they help set up), so this only matters for
## preparation saves made before that change, F7 and tests.
func queue_survivors(candidates: Array) -> void:
	pending_survivors.clear()
	for c: Variant in candidates:
		if not (c is Dictionary):
			continue
		var d: Dictionary = c
		pending_survivors.append({
			"name": d.get("name", ""),
			"seed": d.get("seed", 0),
			"age": d.get("age", 30),
			"gender": d.get("gender", "male"),
			"personality": (d.get("personality", {}) as Dictionary).duplicate(true),
		})

## Leave: seal the bunker and start Day 1. Returns the residents who came in.
## Presentation (fade, message) belongs to SealTransition; this is the rules.
func seal() -> Array[Node]:
	if is_sealed():
		return []
	_close_build_mode()
	## Cash has no use after the seal; it's gone, not just hidden.
	if world != null and world.has_method("set_cash"):
		world.call("set_cash", 0)
	phase = Phase.POST_APOCALYPSE
	if player_stats != null:
		player_stats.set_elapsed(player_stats.get_start_elapsed())
		sealed_at_elapsed = player_stats.get_elapsed()
	_apply_clock()
	var arrived: Array[Node] = _spawn_pending_survivors()
	phase_changed.emit(phase)
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
		"The hatch is sealed", -1.0, true, "Day 1. The shop is closed and nothing new can be built.")
	return arrived

## Dev (F7): back to preparation without touching the world.
func dev_set_phase(next: int) -> void:
	if next == Phase.POST_APOCALYPSE:
		if phase == Phase.LEGACY:
			phase = Phase.PRE_APOCALYPSE
		seal()
		return
	phase = next
	_apply_clock()
	phase_changed.emit(phase)

## Dev (F7): open the hatch now by moving the seal back in time.
func dev_open_hatch() -> void:
	if is_sealed() and player_stats != null:
		sealed_at_elapsed = player_stats.get_elapsed() - HATCH_LOCK_DAYS * player_stats.day_duration_seconds


# ─── Internals ──────────────────────────────────────────────────────────────
func _apply_clock() -> void:
	if player_stats != null:
		player_stats.clock_running = phase != Phase.PRE_APOCALYPSE

func _close_build_mode() -> void:
	if world == null:
		return
	if bool(world.get("_build_mode_active")) and world.has_method("_toggle_build_mode"):
		world.call("_toggle_build_mode")
	var controller: Node = world.get("_build_controller") as Node
	if controller != null and "_undo_stack" in controller:
		## Nothing bought with cash can be refunded after the seal.
		(controller.get("_undo_stack") as Array).clear()

## Residents come in at the foot of the hatch ladder, side by side, facing
## the player. Same restore path SurvivorSelectScreen and saves use.
func _spawn_pending_survivors() -> Array[Node]:
	var spawned: Array[Node] = []
	if pending_survivors.is_empty() or world == null:
		pending_survivors.clear()
		return spawned
	var scene := load(NPC_SCENE_PATH) as PackedScene
	var draft: GDScript = load(DRAFT_PATH) as GDScript
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if scene == null or draft == null:
		return spawned
	var hatch := get_tree().get_first_node_in_group("surface_hatch") as Node3D
	var origin: Vector3
	var forward: Vector3
	if hatch != null:
		forward = hatch.global_transform.basis.z
		origin = hatch.global_position + forward * 2.1
	elif player != null:
		forward = -player.global_transform.basis.z
		origin = player.global_position + forward * 2.3
	else:
		return spawned
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var look_at: Vector3 = player.global_position if player != null else origin - forward
	var map: RID = world.get_world_3d().navigation_map if world is Node3D else RID()
	var count: int = pending_survivors.size()
	for k: int in count:
		var spot: Vector3 = origin + right * ((float(k) - float(count - 1) * 0.5) * 1.2)
		if map.is_valid():
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, spot)
			if snapped != Vector3.ZERO and snapped.distance_to(spot) < 3.0:
				spot = Vector3(snapped.x, spot.y, snapped.z)
		spot.y = (player.global_position.y if player != null else origin.y) + 0.3
		var to_player: Vector3 = look_at - spot
		var yaw: float = atan2(-to_player.x, -to_player.z)
		var npc: Node3D = scene.instantiate()
		npc.call("apply_save_dict", draft.call("to_save_dict", pending_survivors[k], spot, yaw))
		world.add_child(npc)
		spawned.append(npc)
	pending_survivors.clear()
	return spawned


# ─── Save/Load (SaveManager "bunker_phase", phase 4, on_missing) ────────────
func get_save_data() -> Dictionary:
	return {
		"phase": phase,
		"sealed_at": sealed_at_elapsed,
		"pending_survivors": pending_survivors.duplicate(true),
	}

## `null` = a save from before this feature: LEGACY rules.
func apply_save_data(data: Variant) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	phase = clampi(int(d.get("phase", Phase.LEGACY)), Phase.LEGACY, Phase.POST_APOCALYPSE)
	sealed_at_elapsed = float(d.get("sealed_at", 0.0))
	pending_survivors = (d.get("pending_survivors", []) as Array).duplicate(true)
	_apply_clock()
	phase_changed.emit(phase)
