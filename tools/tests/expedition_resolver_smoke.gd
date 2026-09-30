extends SceneTree
## Headless contract smoke for surface expedition rules (no world needed).
## Run with:
## godot --headless --path . --script res://tools/tests/expedition_resolver_smoke.gd

const T := preload("res://scripts/world/hatch/ExpeditionTables.gd")
const R := preload("res://scripts/world/hatch/ExpeditionResolver.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)

func _run() -> void:
	var fit: Dictionary = {"health": 100.0, "energy": 100.0, "resilience": 0.5, "neuroticism": 0.5, "loyalty": 20.0}

	## Tables reference only real hazards/loot/destinations.
	for id: String in T.DESTINATION_ORDER:
		var d: Dictionary = T.DESTINATIONS[id]
		for h: String in d["hazards"]:
			_check(T.HAZARDS.has(h), "%s hazard %s exists" % [id, h])
		for l: String in d["loot"]:
			_check(T.LOOT_ITEMS.has(l), "%s loot %s exists" % [id, l])
		var req: String = d["requires"]
		_check(req == "" or T.DESTINATIONS.has(req), "%s requires a real destination" % id)
	for l: String in T.LOOT_ITEMS:
		var def: Dictionary = T.LOOT_ITEMS[l]
		var path: String = String(def.get("scene", def.get("script", "")))
		_check(ResourceLoader.exists(path), "loot %s resource exists at %s" % [l, path])

	## Determinism: same seed, same trip.
	var a: Dictionary = R.resolve(1234, "pharmacy", "balanced", fit, 0.0, [])
	var b: Dictionary = R.resolve(1234, "pharmacy", "balanced", fit, 0.0, [])
	_check(JSON.stringify(a) == JSON.stringify(b), "resolve is deterministic for a seed")

	## Approach dial moves risk and haul in the promised directions.
	var careful: float = R.trip_injury_chance("pharmacy", "careful", fit)
	var greedy: float = R.trip_injury_chance("pharmacy", "greedy", fit)
	_check(careful < greedy, "careful is safer than greedy")
	var hurt: Dictionary = fit.duplicate()
	hurt["health"] = 40.0
	_check(R.encounter_danger("pharmacy", "balanced", hurt) > R.encounter_danger("pharmacy", "balanced", fit),
		"a hurt resident is at more risk")
	_check(R.ineligible_reason({"health": 20.0, "energy": 100.0}) != "", "badly hurt residents can't go")

	## Statistical shape over many trips.
	var injured_careful: int = 0
	var injured_greedy: int = 0
	var loot_careful: int = 0
	var loot_greedy: int = 0
	var loot_depleted: int = 0
	var lost: int = 0
	for i: int in 2000:
		var c: Dictionary = R.resolve(i, "row_houses", "careful", fit, 0.0, [])
		var g: Dictionary = R.resolve(i, "row_houses", "greedy", fit, 0.0, [])
		var dep: Dictionary = R.resolve(i, "row_houses", "greedy", fit, T.DEPLETION_MAX, [])
		injured_careful += 1 if not (c["hazards"] as Array).is_empty() else 0
		injured_greedy += 1 if not (g["hazards"] as Array).is_empty() else 0
		loot_careful += (c["loot"] as Array).size()
		loot_greedy += (g["loot"] as Array).size()
		loot_depleted += (dep["loot"] as Array).size()
		lost += 1 if String(R.resolve(i, "field_hospital", "greedy", fit, 0.0, [])["fate"]) == "lost" else 0
		for need: String in ["hunger", "thirst", "energy"]:
			_check(float(c["needs"][need]) < 0.0, "trips drain %s" % need)
	_check(injured_careful < injured_greedy, "careful injures less often (%d vs %d)" % [injured_careful, injured_greedy])
	_check(loot_careful < loot_greedy, "greedy hauls more (%d vs %d)" % [loot_careful, loot_greedy])
	_check(loot_depleted < loot_greedy, "a picked-over site yields less")
	var predicted: float = R.trip_loss_chance("field_hospital", "greedy", fit) * 2000.0
	_check(absf(float(lost) - predicted) < 60.0, "forecast loss chance matches outcomes (%d vs %.0f of 2000)" % [lost, predicted])
	_check(R.trip_loss_chance("gas_station", "careful", fit) < 0.001, "short careful runs are effectively never fatal")

	## Loyalty: a resentful resident skims and may desert; a loyal one never deserts.
	var hostile: Dictionary = fit.duplicate()
	hostile["loyalty"] = -90.0
	var deserted: int = 0
	var skimmed: int = 0
	var loyal_deserted: int = 0
	for i: int in 1000:
		var o: Dictionary = R.resolve(i, "gas_station", "balanced", hostile, 0.0, [])
		deserted += 1 if String(o["fate"]) == "deserted" else 0
		skimmed += int(o["skimmed"])
		loyal_deserted += 1 if String(R.resolve(i, "gas_station", "balanced", fit, 0.0, [])["fate"]) == "deserted" else 0
	_check(deserted > 0 and skimmed > 0, "resentful residents skim and sometimes desert")
	_check(loyal_deserted == 0, "loyal residents never desert")

	## Discovery: first successful visit reveals what it points to, once.
	var found: bool = false
	for i: int in 50:
		var o: Dictionary = R.resolve(i, "row_houses", "careful", fit, 0.0, [])
		if String(o["fate"]) == "returned":
			found = (o["reveals"] as Array).has("pharmacy")
			break
	_check(found, "row houses reveal the pharmacy")
	_check((R.resolve(7, "row_houses", "careful", fit, 0.0, ["row_houses"])["reveals"] as Array).is_empty(),
		"a revisit reveals nothing new")

	## Loot specs roll real ranges; reports read plainly.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var water: Dictionary = R.loot_spec("water_bottle", rng)
	var q: float = float(water["state"]["quality"])
	_check(q >= 15.0 and q <= 60.0, "found water is untreated (%.1f)" % q)
	var seed_spec: Dictionary = R.loot_spec("seed", rng)
	_check(T.SEED_TYPES.has(String(seed_spec["state"]["seed_type"])), "seed packets hold a real seed type")
	var lines: Array[String] = R.report_lines("Mara", "pharmacy", a)
	_check(not lines.is_empty(), "every trip produces a report")

	if _failures == 0:
		print("PASS: expedition_resolver_smoke")
	quit(1 if _failures > 0 else 0)
