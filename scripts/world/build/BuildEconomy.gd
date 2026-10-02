class_name BuildEconomy
extends RefCounted
## BuildEconomy.gd (Oct 2026)
## What building costs and what demolishing gives back, by act
## (see BunkerPhase / docs/systems/phase/README.md):
##
##   LEGACY / PRE_APOCALYPSE — cash. Every existing spend/refund path is
##     unchanged; callers keep their own MainWorld.spend_cash()/add_cash().
##   POST_APOCALYPSE — no cash. Wire and pipe cost Metal taken straight from
##     the Research Station's reserve (one unit per WIRE_METRES_PER_METAL of
##     wire, PIPE_METRES_PER_METAL of pipe, rounded up). Anything demolished
##     drops salvage spheres (SalvageItem) the player carries to the chute.
##
## Static helpers only; state lives with its owners (ResearchStation holds
## the reserve, segments carry what they cost as "metal_paid" meta, undo
## entries carry their own currency). Balance numbers below are first-pass
## placeholders, flagged for Brannon's review.

const SALVAGE_SCRIPT: GDScript = preload("res://scripts/world/items/SalvageItem.gd")

## One Metal buys this much wire / pipe (pipe is the dearer of the two).
const WIRE_METRES_PER_METAL: float = 3.0
const PIPE_METRES_PER_METAL: float = 1.5
const METAL: String = "metal"
## Undo-entry currency tags.
const CURRENCY_CASH: String = "cash"
const CURRENCY_METAL: String = "metal"
const CURRENCY_SALVAGE: String = "salvage"

## Salvage per build tile: material -> units. Walls scale with their run
## (see salvage_for_tile). Anything missing falls back to Metal by price.
const TILE_SALVAGE: Dictionary = {
	2:  {"metal": 1},                       ## Pillar
	39: {"metal": 3},                       ## Bunker Door
	3:  {"metal": 2},                       ## Medium Shelf
	34: {"metal": 1},                       ## Small Shelf
	35: {"metal": 3},                       ## Large Shelf
	4:  {"organic": 2, "metal": 1},         ## Bed
	27: {"organic": 1},                     ## Small Table
	28: {"organic": 2},                     ## Medium Table
	29: {"organic": 1},                     ## Chair
	32: {"organic": 1},                     ## End Table
	33: {"organic": 2},                     ## Dresser
	36: {"metal": 1},                       ## Trash Can
	40: {"organic": 1},                     ## Carpet #1
	41: {"organic": 1},                     ## Carpet #2
	42: {"organic": 1},                     ## Carpet #3
	43: {"organic": 1, "metal": 1},         ## Drawers #1
	44: {"organic": 1, "metal": 1},         ## Drawers #2
	45: {"organic": 1, "metal": 1},         ## Drawers #3
	46: {"metal": 1, "plastic": 1},         ## Sink
	31: {"paper": 1},                       ## Poster
	5:  {"metal": 1},                       ## Light
	23: {"metal": 1, "plastic": 1},         ## Grow Light
	24: {"metal": 2, "plastic": 1},         ## Grow Light (Pro)
	6:  {"metal": 3},                       ## Gen S
	7:  {"metal": 4, "plastic": 1},         ## Gen M
	8:  {"metal": 6, "plastic": 2},         ## Gen L
	10: {"metal": 2, "plastic": 2},         ## Terminal
	11: {"metal": 1},                       ## Load Test
	12: {"metal": 1},                       ## Breaker
	16: {"metal": 1, "plastic": 1},         ## Breaker (Smart)
	13: {"metal": 1, "plastic": 1},         ## Battery S
	14: {"metal": 2, "plastic": 1},         ## Battery M
	15: {"metal": 3, "plastic": 2},         ## Battery L
	18: {"metal": 1},                       ## Test Sink
	19: {"plastic": 2, "metal": 1},         ## Dispenser
	20: {"plastic": 2, "metal": 1},         ## Purifier
	21: {"plastic": 2},                     ## Tray (1x1)
	22: {"plastic": 3},                     ## Tray (2x1)
	30: {"metal": 3},                       ## Stove
}
const WALL_TILES: Array[int] = [1, 25, 26]


# ─── Act ──────────────────────────────────────────────────────────────────
## True once the bunker is sealed: Metal and salvage instead of cash.
static func salvage_rules(tree: SceneTree) -> bool:
	return BunkerPhase.sealed(tree)

static func currency(tree: SceneTree) -> String:
	return CURRENCY_METAL if salvage_rules(tree) else CURRENCY_CASH


# ─── Metal costs ──────────────────────────────────────────────────────────
static func wire_metal(length_m: float) -> int:
	return maxi(1, ceili(length_m / WIRE_METRES_PER_METAL - 0.0001))

static func pipe_metal(length_m: float) -> int:
	return maxi(1, ceili(length_m / PIPE_METRES_PER_METAL - 0.0001))

## Splits `total` across parts in proportion to `weights` (largest remainder),
## so per-segment shares always add back up to exactly what was paid.
static func split(total: int, weights: Array[float]) -> Array[int]:
	var out: Array[int] = []
	var sum: float = 0.0
	for w: float in weights:
		sum += maxf(0.0, w)
	if weights.is_empty():
		return out
	if sum <= 0.0:
		for i: int in weights.size():
			out.append(total if i == 0 else 0)
		return out
	var given: int = 0
	var remainders: Array = []
	for i: int in weights.size():
		var exact: float = float(total) * maxf(0.0, weights[i]) / sum
		var whole: int = int(floor(exact))
		out.append(whole)
		given += whole
		remainders.append([exact - float(whole), i])
	remainders.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for k: int in total - given:
		out[int(remainders[k % remainders.size()][1])] += 1
	return out


# ─── The reserve (Research Station) ─────────────────────────────────────────
static func station(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group("research_station") if tree != null else null

## Metal the player can spend now (excludes what running research still needs).
static func metal_available(tree: SceneTree) -> int:
	var s: Node = station(tree)
	if s == null or not s.has_method("available_material"):
		return 0
	return int(s.call("available_material", METAL))

static func spend_metal(tree: SceneTree, amount: int) -> bool:
	if amount <= 0:
		return true
	var s: Node = station(tree)
	if s == null or not s.has_method("spend_material"):
		return false
	return bool(s.call("spend_material", METAL, amount))

## Puts Metal back in the reserve; whatever the reserve can't hold drops as
## salvage at `world_pos` so nothing is lost.
static func return_metal(tree: SceneTree, amount: int, world_pos: Vector3) -> void:
	if amount <= 0:
		return
	var s: Node = station(tree)
	var added: int = 0
	if s != null and s.has_method("add_material"):
		added = int(s.call("add_material", METAL, amount))
	if added > 0:
		float_text(tree, world_pos, "+%s" % metal_text(added), true)
	if amount - added > 0:
		drop_salvage(tree, world_pos, {METAL: amount - added})

static func metal_text(amount: int) -> String:
	return "%d Metal" % amount


# ─── Salvage ──────────────────────────────────────────────────────────────
## What demolishing a build tile gives back. `price` is what the registry
## recorded (walls record their whole run, so longer walls give more).
static func salvage_for_tile(tile_id: int, price: int) -> Dictionary:
	if WALL_TILES.has(tile_id):
		return {METAL: clampi(roundi(float(price) / 100.0), 1, 6)}
	if TILE_SALVAGE.has(tile_id):
		return (TILE_SALVAGE[tile_id] as Dictionary).duplicate()
	return {METAL: clampi(roundi(float(price) / 150.0), 1, 4)}

## Wire/pipe salvage: exactly what the segment cost if it was laid with
## Metal, else the whole units of Metal its length is worth (rounded down, so
## salvaging can never earn more than laying cost).
static func salvage_for_segment(segment: Node, length_m: float, metres_per_metal: float) -> Dictionary:
	var units: int
	if segment != null and segment.has_meta("metal_paid"):
		units = int(segment.get_meta("metal_paid"))
	else:
		units = int(floor(length_m / metres_per_metal + 0.0001))
	return {METAL: units} if units > 0 else {}

## Spawns one sphere per material at `world_pos` with a small pop, plus a
## floating "+2 Metal · +1 Plastic" readout. Returns the spawned items.
static func drop_salvage(tree: SceneTree, world_pos: Vector3, salvage: Dictionary) -> Array[Node]:
	var out: Array[Node] = []
	if tree == null or salvage.is_empty():
		return out
	var parent: Node = tree.get_first_node_in_group("world")
	if parent == null:
		parent = tree.current_scene
	if parent == null:
		return out
	var parts: Array[String] = []
	var materials: Array = salvage.keys()
	materials.sort()
	var n: int = 0
	for material: Variant in materials:
		var units: int = int(salvage[material])
		if units <= 0:
			continue
		var item: RigidBody3D = SALVAGE_SCRIPT.new()
		item.set("salvage_material", String(material))
		item.set("salvage_units", units)
		parent.add_child(item)
		var angle: float = TAU * float(n) / float(maxi(1, materials.size())) + randf_range(-0.4, 0.4)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * (0.18 if materials.size() > 1 else 0.0)
		item.global_position = world_pos + Vector3(0.0, 0.55, 0.0) + offset
		item.linear_velocity = offset.normalized() * 1.1 + Vector3(0.0, 2.2, 0.0) if offset != Vector3.ZERO \
			else Vector3(0.0, 2.2, 0.0)
		out.append(item)
		parts.append("+%d %s" % [units, String(material).capitalize()])
		n += 1
	if not parts.is_empty():
		float_text(tree, world_pos, "  ·  ".join(parts), true)
	return out


# ─── Feedback ─────────────────────────────────────────────────────────────
## Screen-space float over a world point (green = gained, red = spent).
static func float_text(tree: SceneTree, world_pos: Vector3, text: String, positive: bool) -> void:
	if tree == null:
		return
	var viewport: Viewport = tree.root
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	var hud: Node = tree.get_first_node_in_group("hud")
	if camera == null or hud == null or not hud.has_method("spawn_float_text"):
		return
	if camera.is_position_behind(world_pos):
		return
	hud.call("spawn_float_text", camera.unproject_position(world_pos), text, positive)
