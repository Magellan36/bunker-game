extends RefCounted
## SurvivorDraft.gd (Oct 2026)
## Data side of the New Game survivor selection (SurvivorSelectScreen.gd):
## rolls the candidates, does the food/water arithmetic, and turns a chosen
## candidate into the save dictionary NPC.apply_save_dict() restores — so the
## resident who walks into the bunker is exactly the one on the card.
##
## Candidates are rolled with NPC.gd's own randomizers (personality, age) on
## a detached NPC instance, so the trait/age distribution always matches the
## NPC system's. Constants are read from the scripts at runtime (no
## compile-time class references) so this works in --script tests too.

const NPC_SCRIPT_PATH: String = "res://scripts/npc/NPC.gd"
const FOOD_CAN_PATH: String = "res://scripts/world/items/FoodCan.gd"
const WATER_BOTTLE_PATH: String = "res://scripts/world/items/WaterBottle.gd"
const CANDIDATE_COUNT: int = 6
const MAX_PICKS: int = 3
const NOT_MANDATORY_CHANCE: float = 0.1

const ESTIMATE_TEXT: String = "Current bunker population would consume %s cans of food and %s bottles of water a day, on average."
const NOT_MANDATORY_SUFFIX: String = " This is not mandatory."


## Six distinct survivors. Each has at least one trait so one can be shown.
## Returns Array of {name, age, gender, seed, personality, words, revealed}.
static func roll(count: int = CANDIDATE_COUNT) -> Array[Dictionary]:
	var npc_script: GDScript = load(NPC_SCRIPT_PATH)
	var names: Array = (npc_script.get_script_constant_map()["NPC_NAMES"] as Array).duplicate()
	names.shuffle()
	var out: Array[Dictionary] = []
	for i: int in count:
		var probe: Node = npc_script.new()
		var words: Array = []
		for attempt: int in 24:
			probe.call("randomize_personality")
			words = probe.call("get_personality_words")
			if not words.is_empty():
				break
		probe.call("randomize_age")
		out.append({
			"name": String(names[i % names.size()]),
			"age": int(probe.get("age")),
			"gender": "male" if randi() % 2 == 0 else "female",
			"seed": randi(),
			"personality": (probe.get("personality") as Dictionary).duplicate(),
			"words": words.duplicate(),
			"revealed": randi() % maxi(words.size(), 1),
		})
		probe.free()
	return out


## Average daily cans and bottles for `people` (selected residents + the
## player). NPCs and the player drain needs at the same rates, so this is
## exact on average: daily drain / what one full item restores.
static func daily_consumption(people: int) -> Dictionary:
	var npc: Dictionary = (load(NPC_SCRIPT_PATH) as GDScript).get_script_constant_map()
	var can: Dictionary = (load(FOOD_CAN_PATH) as GDScript).get_script_constant_map()
	var bottle: Dictionary = (load(WATER_BOTTLE_PATH) as GDScript).get_script_constant_map()
	var food_per_can: float = float(can["FOOD_PER_BITE"]) * float(can["TOTAL_BITES"])
	var water_per_bottle: float = float(bottle["STANDARD_HYDRATION"]) \
		* float(bottle["MAX_FILL_ML"]) / float(bottle["STANDARD_DRINK_ML"])
	return {
		"cans": float(npc["HUNGER_DRAIN_PER_GAME_HOUR"]) * 24.0 / food_per_can * people,
		"bottles": float(npc["THIRST_DRAIN_PER_GAME_HOUR"]) * 24.0 / water_per_bottle * people,
	}


static func estimate_text(people: int, not_mandatory: bool) -> String:
	var use: Dictionary = daily_consumption(people)
	var text: String = ESTIMATE_TEXT % [_amount(use["cans"]), _amount(use["bottles"])]
	return text + NOT_MANDATORY_SUFFIX if not_mandatory else text


## 2.7 → "2.7", 4.0 → "4".
static func _amount(value: float) -> String:
	var rounded: float = snappedf(value, 0.1)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(roundf(rounded)))
	return "%.1f" % rounded


## Save-dictionary subset NPC.apply_save_dict() reads; everything else
## (needs, skills, relationships...) falls back to a fresh resident's values.
static func to_save_dict(candidate: Dictionary, position: Vector3, yaw: float) -> Dictionary:
	return {
		"pos": {"x": position.x, "y": position.y, "z": position.z},
		"rot_y": yaw,
		"name": candidate["name"],
		"seed": candidate["seed"],
		"age": candidate["age"],
		"gender": candidate["gender"],
		"personality": (candidate["personality"] as Dictionary).duplicate(),
	}
