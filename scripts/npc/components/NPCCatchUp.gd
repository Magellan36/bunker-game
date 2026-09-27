extends RefCounted
class_name NPCCatchUp
## NPCCatchUp.gd (Sep 2026; formerly inline in NPC.gd) — approximates what
## every NPC did during an instant time skip (currently the F7 "Fast-forward
## 24h" button; the real sleep path fast-forwards the live simulation via
## Engine.time_scale and needs none of this). Any future INSTANT skip
## source must call NPC.catch_up_all(hours) right next to its own
## PlayerStats.skip_time_with_drain() call.
##
## Simulated hour by hour (cheap: ≤72 steps per NPC) so needs, sleep and
## meals interleave the way they would have live: residents sleep through
## the night hours in their schedule, eat/drink from REAL world items when
## they get low (an empty bunker means they go hungry), and pass out if
## energy hits zero.

const MAX_CATCHUP_HOURS: float = 72.0
## Per-item restore estimates — only used to decide WHEN to consume; the
## real restore always comes from the item's own consume/bite/drink call.
const EAT_BELOW: float = 45.0
const DRINK_BELOW: float = 50.0
const SLEEP_REGEN_NET_PER_HOUR: float = 7.0   ## bed sleep regen minus waking drain

static func catch_up_all(hours: float) -> void:
	var h: float = clampf(hours, 0.0, MAX_CATCHUP_HOURS)
	if h <= 0.0:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var npcs: Array = tree.get_nodes_in_group("npc")

	## Contagion snapshot BEFORE anyone changes, so everyone pulls toward the
	## same pre-skip picture of the bunker.
	var mood_total: float = 0.0
	var mood_count: int = 0
	for n: Node in npcs:
		if n is NPC:
			mood_total += n.mood
			mood_count += 1
	var avg_mood_before: float = (mood_total / mood_count) if mood_count > 0 else 50.0

	## Harvest — one ready plant = one job, shared round-robin across NPCs.
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
		if not (n is NPC):
			continue
		var completed: int = 0
		while completed < jobs_per_npc and pool_index < ready_plants.size():
			var plant: Node = ready_plants[pool_index] as Node
			pool_index += 1
			if is_instance_valid(plant) and plant.is_ready() and plant.has_method("harvest"):
				plant.harvest()
				completed += 1
		catch_up_npc(n, h, avg_mood_before)

static func catch_up_npc(npc: NPC, h: float, avg_mood_before: float) -> void:
	if h <= 0.0:
		return
	## Whatever it was doing is over — cleanly.
	if npc.brain != null:
		npc.brain.stop_current()
	var start_hour: float = NPCClock.hour_of_day() - h   ## the clock has already advanced
	var slept_hours: float = 0.0
	var passed_out: bool = false
	var needs_sum: float = 0.0
	var steps: int = int(ceil(h))
	for i: int in steps:
		var dt: float = minf(1.0, h - float(i))
		var hour: float = fposmod(start_hour + float(i) + 0.5, 24.0)
		npc.hunger = maxf(0.0, npc.hunger - NPC.HUNGER_DRAIN_PER_GAME_HOUR * dt)
		npc.thirst = maxf(0.0, npc.thirst - NPC.THIRST_DRAIN_PER_GAME_HOUR * dt)
		var night: bool = NPCClock.hour_in(hour, npc.get_bedtime(), npc.get_wake_time())
		if passed_out:
			npc.energy = minf(100.0, npc.energy + (PassedOutActivity.REGEN_PER_GAME_HOUR - NPC.ENERGY_DRAIN_PER_GAME_HOUR) * dt)
			if npc.energy >= PassedOutActivity.WAKE_ENERGY:
				passed_out = false
		elif night and npc.energy < 100.0:
			npc.energy = minf(100.0, npc.energy + SLEEP_REGEN_NET_PER_HOUR * dt)
			slept_hours += dt
		else:
			npc.energy -= NPC.ENERGY_DRAIN_PER_GAME_HOUR * dt
			if npc.energy <= 0.0:
				npc.energy = 0.0
				passed_out = true
				var drop: float = randf_range(1.0, 10.0 * npc.neuroticism_trait_mult())
				npc.mood = clampf(npc.mood - drop, 0.0, 100.0)
				npc.add_thought("collapsed")
		if not night or passed_out:
			if npc.hunger < EAT_BELOW:
				_eat_something(npc)
			if npc.thirst < DRINK_BELOW:
				_drink_something(npc)
		if npc.hunger <= 0.0 or npc.thirst <= 0.0:
			var zeroed: int = (1 if npc.hunger <= 0.0 else 0) + (1 if npc.thirst <= 0.0 else 0)
			npc.health = maxf(0.0, npc.health - NPC.HEALTH_DRAIN_PER_ZEROED_NEED_PER_GAME_HOUR * zeroed * dt)
		needs_sum += (npc.energy + npc.hunger + npc.thirst) / 3.0 * dt
		npc.thoughts.tick(dt)
	if slept_hours >= 3.0:
		npc.add_thought("slept_in_bed" if _has_bed() else "slept_on_floor")
	npc._tick_relax_day(h)
	if npc.medical != null:
		npc.medical.catch_up(h)
	_catch_up_mood(npc, h, avg_mood_before)
	if NPCDebug.enabled:
		NPCDebug.log_catchup(npc, h)

static func _has_bed() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree != null and not tree.get_nodes_in_group("bed").is_empty()

static func _eat_something(npc: NPC) -> void:
	var item: Node = NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))
	if item == null:
		var shelf: Dictionary = NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_edible"))
		item = shelf.get("item")
	if item == null:
		return
	if item is DishItem:
		npc.hunger = minf(100.0, npc.hunger + item.consume_as_food())
		npc.add_thought("ate_hot_meal")
	elif item is FarmProduceItem:
		npc.hunger = minf(100.0, npc.hunger + item.consume_as_food())
		npc.add_thought("ate_fresh")
	elif item.has_method("take_bite"):
		while item.has_bites_left() and npc.hunger < 85.0:
			npc.hunger = minf(100.0, npc.hunger + item.take_bite())
		npc.add_thought("ate_cold_can")

static func _drink_something(npc: NPC) -> void:
	var item: Node = NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_drinkable_bottle"))
	if item == null:
		item = NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_drinkable_bottle")).get("item")
	if item == null or not item.has_method("take_drink"):
		return
	while NPCItemUser.is_drinkable_bottle(item) and npc.thirst < NPC.NEED_SATED:
		npc.thirst = minf(100.0, npc.thirst + item.take_drink())

## Needs pull and contagion evaluated once with a large h. Random drift is a
## random walk — its spread grows with √hours, not hours (the old linear
## version could swing a 24 h skip's mood by ±36 from noise alone).
static func _catch_up_mood(npc: NPC, h: float, avg_mood_before: float) -> void:
	var target: float = npc.get_mood_target()
	var rate: float = NPC.MOOD_CHANGE_PER_GAME_HOUR
	if target > npc.mood:
		rate *= npc._mood_recovery_trait_mult()
	npc.mood = move_toward(npc.mood, target, rate * h)
	var blend: float = clampf(NPC.MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * npc.get_contagion_sociability_mult() * h, 0.0, 1.0)
	npc.mood = clampf(npc.mood + (avg_mood_before - npc.mood) * blend, 0.0, 100.0)
	npc.mood = clampf(npc.mood + randf_range(-1.0, 1.0) * NPC.MOOD_DRIFT_MAX_PER_GAME_HOUR * npc.neuroticism_trait_mult() * sqrt(h), 0.0, 100.0)
