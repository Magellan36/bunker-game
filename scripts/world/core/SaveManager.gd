extends Node
## SaveManager.gd
## Autoload singleton — generic save/load infrastructure with numbered slots.
## Register as Autoload: Project > Project Settings > Autoload
## Name it exactly: SaveManager  (register AFTER WorldManager)
##
## DESIGN — pluggable field registry:
## Any system (PlayerStats, MainWorld cash, later: power grid, inventory,
## placed objects...) registers itself with a string key + a getter Callable +
## a setter Callable. SaveManager itself never hardcodes what a "save" contains
## — it just asks every registered field for its current value on save, and
## hands each field back its saved value on load. This means adding a new
## persisted system later is ~2 lines at the call site (register_field), with
## ZERO changes needed here.
##
## CURRENT FIELDS WIRED (deliberately minimal per project decision — power
## grid / inventory / placed objects are still evolving fast and are NOT
## persisted yet):
##   "player_position" — Vector3, player.global_position
##   "cash"             — int,     MainWorld._cash
##   "game_elapsed"      — float,   PlayerStats._elapsed (day/hour/minute derive
##                          from this automatically on load)
## MainWorld._ready() calls register_field() for each of these once its nodes
## exist — see MainWorld.gd "Save/Load field registration" section.
##
## FORWARD COMPATIBILITY: load_game() looks up each key present in the save
## file and calls the matching registered setter if one exists; unknown/
## missing keys are silently skipped. This means old saves keep loading fine
## even after more fields are added later, and saves made before a new field
## existed simply leave that field at its default.

const SAVE_SLOT_COUNT: int = 3
const SAVE_PATH_FORMAT: String = "user://save_slot_%d.json"

## key -> { "get": Callable, "set": Callable, "phase": int }
var _fields: Dictionary = {}

## Register a persistable field. Call once per field, typically from
## MainWorld._ready() (or any system's own _ready()) once the underlying node
## exists. Re-registering the same key overwrites the previous callbacks —
## safe to call again after a scene reload.
##
## `phase` (added Jul 2026, save/load world-state expansion) — controls the
## ORDER setters are applied on load_game() (ascending, ties broken by
## dictionary iteration order). save_game() is unaffected — every field's
## getter always runs, order doesn't matter for writing.
## World reconstruction is order-dependent: dug rock chunks must exist before
## placed objects can be restored onto them, devices must exist before wires/
## pipes can reconnect to them, etc. Default phase 0 is safe for anything with
## no ordering dependency.
##   Phase 0 — dug rock chunks
##   Phase 1 — placed objects (devices, with embedded per-device extra state)
##   Phase 2 — player-placed wires
##   Phase 3 — water pipes
##   Phase 4 — player_position/cash/game_elapsed (must come after the world
##             above exists, e.g. player shouldn't land inside undug rock)
func register_field(key: String, getter: Callable, setter: Callable, phase: int = 0) -> void:
	_fields[key] = {"get": getter, "set": setter, "phase": phase}

## Remove a field registration (e.g. if its owning node is being freed).
func unregister_field(key: String) -> void:
	_fields.erase(key)

## Returns true if the given slot (1-based, 1..SAVE_SLOT_COUNT) has a save file.
func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_PATH_FORMAT % slot)

## Returns a small metadata dict for UI display without loading the full save:
##   { "exists": bool, "timestamp": String, "day": int, "time_display": String }
## Returns { "exists": false } if the slot is empty or unreadable.
func get_slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {"exists": false}
	var f: FileAccess = FileAccess.open(SAVE_PATH_FORMAT % slot, FileAccess.READ)
	if f == null:
		return {"exists": false}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {"exists": false}
	var d: Dictionary = parsed as Dictionary
	var meta: Dictionary = d.get("_meta", {})
	return {
		"exists":       true,
		"timestamp":    meta.get("timestamp", "?"),
		"day":          meta.get("day", 1),
		"time_display": meta.get("time_display", "?"),
	}

## Gathers every registered field's current value, writes it to the given slot
## as JSON. Returns true on success.
func save_game(slot: int) -> bool:
	if slot < 1 or slot > SAVE_SLOT_COUNT:
		push_warning("SaveManager: save_game called with out-of-range slot %d" % slot)
		return false

	var data: Dictionary = {}
	for key: String in _fields:
		var cb: Callable = _fields[key]["get"]
		if cb.is_valid():
			data[key] = _to_json_value(cb.call())

	## Metadata for slot-picker UI (day/time snapshot + real-world timestamp).
	var meta: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(false, true),
	}
	var stats: Node = get_tree().get_first_node_in_group("player_stats")
	if stats != null:
		meta["day"] = stats.get("current_day")
		if stats.has_method("get_time_display"):
			meta["time_display"] = stats.call("get_time_display")
	data["_meta"] = meta

	var f: FileAccess = FileAccess.open(SAVE_PATH_FORMAT % slot, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: could not open save slot %d for writing" % slot)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

## Reads the given slot and applies every value to its matching registered
## field's setter. Unknown keys (not currently registered) and missing keys
## (registered but absent from an older save) are silently skipped.
## Returns true on success (file existed and parsed as a Dictionary).
func load_game(slot: int) -> bool:
	if not slot_exists(slot):
		push_warning("SaveManager: load_game called on empty slot %d" % slot)
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH_FORMAT % slot, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("SaveManager: save slot %d is corrupt or not a valid save" % slot)
		return false

	var data: Dictionary = parsed as Dictionary

	## Apply setters in ascending phase order — world reconstruction is
	## order-dependent (see register_field()'s own comment on phases).
	## Stable sort by phase; ties keep Dictionary.keys() iteration order.
	var keys: Array = []
	for key: String in data:
		if key != "_meta":
			keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = int(_fields.get(a, {}).get("phase", 0))
		var pb: int = int(_fields.get(b, {}).get("phase", 0))
		return pa < pb)

	for key: String in keys:
		if not _fields.has(key):
			continue   ## field not registered (removed feature, or older/newer version) — skip
		var cb: Callable = _fields[key]["set"]
		if cb.is_valid():
			cb.call(_from_json_value(data[key]))
	return true

## Public helpers — JSON can't natively carry Vector3, and custom fields
## (placed_objects, player_wires, water_pipes...) need to encode Vector3
## values NESTED inside arrays/dictionaries, where the automatic top-level
## _to_json_value()/_from_json_value() conversion below doesn't reach. Any
## system's getter/setter can call these directly instead of hand-rolling
## its own {x,y,z} dict shape.
func vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func dict_to_vec3(d: Dictionary) -> Vector3:
	return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))

## JSON can't natively represent Vector3/Vector2 — encode as a small dict with
## a type tag so _from_json_value can reconstruct the correct Godot type.
func _to_json_value(value: Variant) -> Variant:
	if value is Vector3:
		var v: Vector3 = value
		return {"__type": "Vector3", "x": v.x, "y": v.y, "z": v.z}
	if value is Vector2:
		var v2: Vector2 = value
		return {"__type": "Vector2", "x": v2.x, "y": v2.y}
	return value

func _from_json_value(value: Variant) -> Variant:
	if value is Dictionary and (value as Dictionary).has("__type"):
		var d: Dictionary = value as Dictionary
		match d.get("__type", ""):
			"Vector3":
				return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
			"Vector2":
				return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	return value
