extends RefCounted
class_name ExpeditionResolver
## ExpeditionResolver.gd
## Pure rules for surface expeditions — no scene tree access, so it runs in
## headless tests (tools/tests/expedition_resolver_smoke.gd).
##
## The whole trip is resolved ONCE, at departure, from a stored seed. The
## outcome rides in the save file, so reloading can't re-roll a bad trip,
## and the player learns what happened only when the resident gets back
## (or fails to). See docs/systems/hatch/README.md.

const T := preload("res://scripts/world/hatch/ExpeditionTables.gd")

## Snapshot of the resident taken at departure. Keys: health, energy,
## resilience, neuroticism, loyalty (relationship with the player).
static func resident_snapshot(npc: Node) -> Dictionary:
	var p: Dictionary = npc.get("personality") if "personality" in npc else {}
	var loyalty: float = 0.0
	if npc.has_method("get_relationship"):
		loyalty = float(npc.call("get_relationship", "player"))
	return {
		"health": float(npc.get("health")) if "health" in npc else 100.0,
		"energy": float(npc.get("energy")) if "energy" in npc else 100.0,
		"resilience": float(p.get("resilience", 0.5)),
		"neuroticism": float(p.get("neuroticism", 0.5)),
		"loyalty": loyalty,
	}

## Why this resident can't go right now, or "" if they can.
static func ineligible_reason(snapshot: Dictionary) -> String:
	if float(snapshot.get("health", 100.0)) < T.MIN_HEALTH_TO_SEND:
		return "too hurt to go topside"
	if float(snapshot.get("energy", 100.0)) < T.MIN_ENERGY_TO_SEND:
		return "too exhausted"
	return ""

## Planned round-trip hours for a destination + approach.
static func planned_hours(dest_id: String, approach_id: String) -> float:
	var dest: Dictionary = T.DESTINATIONS.get(dest_id, {})
	var approach: Dictionary = T.APPROACHES.get(approach_id, T.APPROACHES["balanced"])
	return float(dest.get("hours", 8.0)) * float(approach["hours_mult"])

## Per-encounter chance that something goes wrong. Shared by the forecast
## the UI shows and by resolve(), so the estimate is never a lie.
static func encounter_danger(dest_id: String, approach_id: String, snapshot: Dictionary) -> float:
	var dest: Dictionary = T.DESTINATIONS.get(dest_id, {})
	var approach: Dictionary = T.APPROACHES.get(approach_id, T.APPROACHES["balanced"])
	var danger: float = float(dest.get("danger", 0.25)) * float(approach["danger_mult"])
	var health: float = float(snapshot.get("health", 100.0))
	var energy: float = float(snapshot.get("energy", 100.0))
	danger += T.LOW_HEALTH_DANGER_BONUS * clampf(inverse_lerp(100.0, T.MIN_HEALTH_TO_SEND, health), 0.0, 1.0)
	danger += T.LOW_ENERGY_DANGER_BONUS * clampf(inverse_lerp(100.0, T.MIN_ENERGY_TO_SEND, energy), 0.0, 1.0)
	danger -= T.RESILIENCE_DANGER_SWING * (float(snapshot.get("resilience", 0.5)) - 0.5) * 2.0
	danger += T.NEUROTIC_DANGER_SWING * (float(snapshot.get("neuroticism", 0.5)) - 0.5) * 2.0
	return clampf(danger, 0.02, T.MAX_ENCOUNTER_DANGER)

## Chance of at least one hazard over the whole trip.
static func trip_injury_chance(dest_id: String, approach_id: String, snapshot: Dictionary) -> float:
	var per: float = encounter_danger(dest_id, approach_id, snapshot)
	var n: int = int(T.DESTINATIONS.get(dest_id, {}).get("encounters", 3))
	return 1.0 - pow(1.0 - per, n)

## Chance the resident never comes back from hazards alone (exact binomial:
## P(hazards >= LOST_MIN_HAZARDS) × LOST_CHANCE). Loyalty desertion is shown
## separately as a trust warning.
static func trip_loss_chance(dest_id: String, approach_id: String, snapshot: Dictionary) -> float:
	var p: float = encounter_danger(dest_id, approach_id, snapshot)
	var n: int = int(T.DESTINATIONS.get(dest_id, {}).get("encounters", 3))
	var at_least: float = 0.0
	for k: int in range(T.LOST_MIN_HAZARDS, n + 1):
		at_least += _binomial(n, k) * pow(p, k) * pow(1.0 - p, n - k)
	return at_least * T.LOST_CHANCE

static func _binomial(n: int, k: int) -> float:
	var r: float = 1.0
	for i: int in k:
		r = r * float(n - i) / float(i + 1)
	return r

static func risk_word(chance: float) -> String:
	if chance < 0.2: return "Low"
	if chance < 0.4: return "Moderate"
	if chance < 0.6: return "High"
	return "Severe"

static func haul_word(dest_id: String, approach_id: String, depletion: float) -> String:
	var mult: float = float(T.APPROACHES.get(approach_id, T.APPROACHES["balanced"])["loot_mult"]) * (1.0 - depletion)
	var rolls: Array = T.DESTINATIONS.get(dest_id, {}).get("loot_rolls", [2, 4])
	var expected: float = (float(rolls[0]) + float(rolls[1])) * 0.5 * mult
	if expected < 1.8: return "Slim"
	if expected < 3.2: return "Fair"
	if expected < 4.6: return "Good"
	return "Rich"

## Resolves a whole trip. Returns:
## {
##   hazards:   [{id, text, injury, part}]    in the order they happened
##   loot:      [loot id, ...]                what they carried home
##   skimmed:   int                           items kept back (low loyalty)
##   needs:     {hunger, thirst, energy, health}  deltas (negative) to apply
##   extra_hours: float                       delay beyond the planned return
##   fate:      "returned" | "lost" | "deserted"
##   reveals:   [destination id, ...]         newly discovered places
## }
static func resolve(seed_value: int, dest_id: String, approach_id: String, snapshot: Dictionary,
		depletion: float, visited: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dest: Dictionary = T.DESTINATIONS.get(dest_id, {})
	var approach: Dictionary = T.APPROACHES.get(approach_id, T.APPROACHES["balanced"])
	var hours: float = planned_hours(dest_id, approach_id)

	## Encounters.
	var danger: float = encounter_danger(dest_id, approach_id, snapshot)
	var hazards: Array = []
	var loot_lost_fraction: float = 0.0
	for i: int in int(dest.get("encounters", 3)):
		if rng.randf() >= danger:
			continue
		var hazard_id: String = _weighted_pick(rng, dest.get("hazards", {}))
		var hz: Dictionary = T.HAZARDS.get(hazard_id, {})
		var parts: Array = hz.get("parts", [])
		var part: String = String(parts[rng.randi_range(0, parts.size() - 1)]) if not parts.is_empty() else ""
		var text: String = String(hz.get("text", "got hurt"))
		if text.contains("%s"):
			text = text % ("their " + part.to_lower().replace("_", " "))
		hazards.append({"id": hazard_id, "text": text, "injury": String(hz.get("injury", "none")), "part": part})
		loot_lost_fraction = maxf(loot_lost_fraction, float(hz.get("loot_loss", 0.0)))

	## Loot.
	var rolls: Array = dest.get("loot_rolls", [2, 4])
	var draws: float = float(rng.randi_range(int(rolls[0]), int(rolls[1])))
	draws *= float(approach["loot_mult"]) * (1.0 - clampf(depletion, 0.0, T.DEPLETION_MAX))
	draws *= 1.0 - loot_lost_fraction
	var count: int = int(floor(draws))
	if rng.randf() < draws - floor(draws):
		count += 1
	var loot: Array = []
	for i: int in count:
		loot.append(_weighted_pick(rng, dest.get("loot", {})))

	## Loyalty: a resident who resents you may keep some of it.
	var skimmed: int = 0
	var loyalty: float = float(snapshot.get("loyalty", 0.0))
	if loyalty < T.SKIM_BELOW and not loot.is_empty():
		skimmed = int(round(float(loot.size()) * T.SKIM_FRACTION))
		for i: int in skimmed:
			loot.remove_at(rng.randi_range(0, loot.size() - 1))

	## Needs over the trip + any exposure hazard.
	var needs: Dictionary = {
		"hunger": -hours * T.NPC_HUNGER_PER_HOUR * T.TRIP_NEED_DRAIN_MULT,
		"thirst": -hours * T.NPC_THIRST_PER_HOUR * T.TRIP_NEED_DRAIN_MULT,
		"energy": -hours * T.NPC_ENERGY_PER_HOUR * T.TRIP_NEED_DRAIN_MULT,
		"health": 0.0,
	}
	for h: Dictionary in hazards:
		var extra: Dictionary = T.HAZARDS.get(h["id"], {}).get("needs", {})
		for k: String in extra.keys():
			needs[k] = float(needs.get(k, 0.0)) - float(extra[k])

	## Bad trips: late, lost, or gone for good.
	var extra_hours: float = 0.0
	if hazards.size() >= 2:
		var delay_chance: float = T.DELAY_CHANCE_PER_EXTRA_HAZARD * float(hazards.size() - 1)
		if rng.randf() < delay_chance:
			extra_hours = hours * rng.randf_range(T.DELAY_HOURS_MULT[0], T.DELAY_HOURS_MULT[1])
	var fate: String = "returned"
	if hazards.size() >= T.LOST_MIN_HAZARDS and rng.randf() < T.LOST_CHANCE:
		fate = "lost"
	elif loyalty < T.DESERT_BELOW:
		var desert: float = minf(T.DESERT_CHANCE_MAX, (T.DESERT_BELOW - loyalty) * T.DESERT_CHANCE_PER_POINT)
		if rng.randf() < desert:
			fate = "deserted"

	## Discovery: the first visit to a place can point to the next one.
	var reveals: Array = []
	if fate == "returned":
		for other_id: String in T.DESTINATION_ORDER:
			var req: String = String(T.DESTINATIONS[other_id].get("requires", ""))
			if req == dest_id and not visited.has(dest_id):
				reveals.append(other_id)

	return {
		"hazards": hazards, "loot": loot, "skimmed": skimmed, "needs": needs,
		"extra_hours": extra_hours, "fate": fate, "reveals": reveals,
	}

## Builds the item spec (ItemSaveData.spawn format) for one loot id, rolling
## any [min, max] state ranges.
static func loot_spec(loot_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var def: Dictionary = T.LOOT_ITEMS.get(loot_id, {})
	if def.is_empty():
		return {}
	var spec: Dictionary = {}
	if def.has("scene"):
		spec["scene"] = def["scene"]
	if def.has("script"):
		spec["script"] = def["script"]
	if def.has("state"):
		var state: Dictionary = {}
		for k: String in (def["state"] as Dictionary).keys():
			var v: Variant = def["state"][k]
			if v is Array and (v as Array).size() == 2:
				var a: Array = v
				if typeof(a[0]) == TYPE_INT:
					state[k] = rng.randi_range(int(a[0]), int(a[1]))
				else:
					state[k] = rng.randf_range(float(a[0]), float(a[1]))
			elif v is String and v == "@seed":
				state[k] = T.SEED_TYPES[rng.randi_range(0, T.SEED_TYPES.size() - 1)]
			else:
				state[k] = v
		spec["state"] = state
	return spec

## One plain-language report, written from the outcome. Pillar 3: every
## injury, lost item and reveal has its cause spelled out.
static func report_lines(npc_name: String, dest_id: String, outcome: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var dest_name: String = String(T.DESTINATIONS.get(dest_id, {}).get("name", dest_id))
	var fate: String = String(outcome.get("fate", "returned"))
	for h: Dictionary in outcome.get("hazards", []):
		lines.append("%s %s." % [npc_name, h["text"]])
	if fate == "lost":
		lines.append("%s never came back from the %s." % [npc_name, dest_name])
		return lines
	if fate == "deserted":
		lines.append("%s took what they found at the %s and didn't come back." % [npc_name, dest_name])
		return lines
	if float(outcome.get("extra_hours", 0.0)) > 0.0:
		lines.append("Pinned down by trouble, %s came back %d hours late." % [npc_name, int(round(float(outcome["extra_hours"])))])
	var loot: Array = outcome.get("loot", [])
	if loot.is_empty():
		lines.append("Came back from the %s empty-handed." % dest_name)
	else:
		lines.append("Brought back: %s." % summarize_loot(loot))
	if int(outcome.get("skimmed", 0)) > 0:
		lines.append("The haul looked light. %s wouldn't meet your eyes." % npc_name)
	for r: String in outcome.get("reveals", []):
		lines.append("Found a note pointing to the %s." % String(T.DESTINATIONS[r]["name"]))
	return lines

static func summarize_loot(loot: Array) -> String:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for id: Variant in loot:
		var key: String = String(id)
		if not counts.has(key):
			order.append(key)
		counts[key] = int(counts.get(key, 0)) + 1
	var parts: PackedStringArray = []
	for key: String in order:
		var name: String = String(T.LOOT_ITEMS.get(key, {}).get("name", key))
		parts.append("%s ×%d" % [name, counts[key]] if int(counts[key]) > 1 else name)
	return ", ".join(parts)

static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total: float = 0.0
	for k: Variant in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return ""
	var roll: float = rng.randf() * total
	for k: Variant in weights.keys():
		roll -= float(weights[k])
		if roll <= 0.0:
			return String(k)
	return String(weights.keys().back())
