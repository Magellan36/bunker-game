extends RefCounted
## StorageProfile.gd (Oct 2026, Brannon) — where things belong in storage.
##
## Residents used to put things in the nearest storage with room, in its
## first free slot, so shelves came out jumbled. Now they use some sense:
##   - SIZE: small things (medicine, filters, seeds) go in drawers (End
##     Table, Dresser: LightStorage); bigger things go on shelves. On a
##     shelf, big things go low and small things high.
##   - HOME AREA: things used somewhere live near it. Fresh food, pots and
##     dishes go by the kitchen (stove); seeds, soil and fertilizer by the
##     garden (trays); fuel by the generator; filters by the purifier.
##     Medicine has no home: just small storage.
##   - STORES: bulk long-term supplies (food and water cases, cans, bottles)
##     are one family. They're kept together, leaning toward the kitchen,
##     each type in its own rows or shelf, and never split across the bunker
##     just because the water dispenser is far from the stove.
##   - LIKE WITH LIKE: a type keeps to its own shelf or rows; a family keeps
##     to one area of the bunker.
## Walking counts, but a home area is worth about 20 m of extra walk, and
## residents say why when they walk past nearer storage (why_here()).
##
## Used for tidying destinations (NPCJobQueries), the slot on a shelf
## (NPCItemUser.store_held) and re-organizing (ReorganizeActivity). No
## class_name on purpose: preloaded where used.

const SMALL: int = 0
const MEDIUM: int = 1
const LARGE: int = 2

## Item type key (shelf_item_type, else the script's file name) ->
## [size, family]. Weapons ("weapon_*") are tools. Anything unlisted:
## pocketable = medium misc, else large misc.
const PROFILES: Dictionary = {
	"antibiotics": [SMALL, "medical"], "bandage": [SMALL, "medical"], "splint": [SMALL, "medical"],
	"trauma_kit": [SMALL, "medical"],
	"purifier_filter": [SMALL, "water_tech"],
	"seed": [SMALL, "garden"], "fertilizer": [SMALL, "garden"],
	"empty_seed_bag": [SMALL, "garden"], "empty_fertilizer_bottle": [SMALL, "garden"],
	"bag_of_soil": [MEDIUM, "garden"], "basket": [MEDIUM, "garden"], "empty_bag": [MEDIUM, "garden"],
	"farm_produce": [MEDIUM, "kitchen"], "cooking_pot": [MEDIUM, "kitchen"], "DishItem": [MEDIUM, "kitchen"],
	"food_can": [MEDIUM, "stores"], "water_bottle": [MEDIUM, "stores"],
	"can_case": [LARGE, "stores"], "water_case": [LARGE, "stores"],
	"fuel_can": [MEDIUM, "fuel"],
	"flashlight": [SMALL, "tools"],
	"SalvageItem": [MEDIUM, "misc"], "test_crate": [LARGE, "misc"],
}

## family -> anchor groups (its home area) and how much being there is worth.
const FAMILIES: Dictionary = {
	"medical":    {"anchors": [], "weight": 0.0},
	"water_tech": {"anchors": ["water_purifier", "water_dispenser"], "weight": 4.0},
	"garden":     {"anchors": ["farming_tray"], "weight": 8.0},
	"kitchen":    {"anchors": ["stove"], "weight": 8.0},
	"stores":     {"anchors": ["stove"], "weight": 3.0},   ## "generally, or the kitchen"
	"fuel":       {"anchors": ["generator"], "weight": 6.0},
	"tools":      {"anchors": [], "weight": 0.0},
	"misc":       {"anchors": [], "weight": 0.0},
}

## How "by" its home area a storage is fades with distance: full within
## ANCHOR_NEAR, nothing past ANCHOR_FAR. (An on/off 6 m radius made one shelf
## in a compact bunker count as by the kitchen AND by the garden.)
const ANCHOR_NEAR: float = 2.5
const ANCHOR_FAR: float = 7.5
const HOME_SAYS_BY: float = 0.5           ## at least this much "by" it to say so
const AREA_RADIUS: float = 4.0            ## storage this close to another is the same area
const WALK_WEIGHT: float = 0.4            ## cost per metre: right by a home area (8) ≈ 20 m of walk
const SIZE_SMALL_ON_SHELF: float = 6.0
const SIZE_BIG_IN_DRAWER: float = 5.0     ## keep drawers for the small things
const SAME_FAMILY_BONUS: float = 4.0      ## × share of the storage holding that family
const OTHER_FAMILY_COST: float = 3.0      ## × share holding other families
const OTHER_TYPE_COST: float = 2.5        ## × share holding other types (one type per shelf when there's a choice)
const SAME_TYPE_BONUS: float = 2.0
const SAME_AREA_BONUS: float = 2.0        ## the family already lives in a storage right beside this one
const FAR_EXTRA_M: float = 4.0            ## walking this much past nearer storage gets explained

## Why-here phrases (labels, logs) and dialogue keys.
const PHRASES: Dictionary = {
	"garden": "by the garden", "kitchen": "by the kitchen", "generator": "by the generator",
	"purifier": "by the water purifier", "stores": "with the other stores", "drawer": "in a drawer",
	"same": "with the others like it",
}
const FAMILY_REASON: Dictionary = {"garden": "garden", "kitchen": "kitchen", "fuel": "generator", "water_tech": "purifier"}

# ─── Item facts ──────────────────────────────────────────────────────────────
static func key_of(item: Node) -> String:
	if item == null:
		return ""
	if "shelf_item_type" in item:
		return str(item.shelf_item_type)
	var s: Script = item.get_script() as Script
	return s.resource_path.get_file().get_basename() if s != null else item.get_class()

static func _profile(item: Node) -> Array:
	var key: String = key_of(item)
	var p: Variant = PROFILES.get(key)
	if p != null:
		return p
	if key.begins_with("weapon"):
		return [MEDIUM, "tools"]
	return [MEDIUM, "misc"] if item != null and item.is_in_group("inventory_item") else [LARGE, "misc"]

static func size_of(item: Node) -> int:
	return int(_profile(item)[0])

static func family_of(item: Node) -> String:
	return String(_profile(item)[1])

# ─── Storage facts ───────────────────────────────────────────────────────────
## Every storage residents organize (shelves, drawers), not trash cans.
static func storages(tree: SceneTree) -> Array:
	var out: Array = []
	for s: Node in tree.get_nodes_in_group("shelving"):
		if is_instance_valid(s) and s is Node3D and s.has_method("npc_try_place_item") \
				and not s.is_in_group("trash_receptacle") and not bool(s.get("_is_preview_only")):
			out.append(s)
	return out

static func is_drawer(storage: Node) -> bool:
	return storage is LightStorage

## What's in it, one entry per PLACE: a shelf slot counts once however many
## cans are stacked in it; a drawer counts each item. `exclude` (the item
## being placed or moved) doesn't count, unless others share its stack.
static func contents(storage: Node, exclude: Node = null) -> Array:
	var out: Array = []
	if "slots" in storage:
		for stack: Array in storage.slots:
			if stack.is_empty() or not is_instance_valid(stack[0]):
				continue
			if exclude != null and stack.size() == 1 and stack[0] == exclude:
				continue
			out.append(stack[0])
	elif "stored" in storage:
		for it: Variant in storage.stored:
			if it != null and is_instance_valid(it) and it != exclude:
				out.append(it)
	return out

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Per-frame cache of the slow facts (which families each storage holds,
## which home areas it's in): re-planning asks them thousands of times.
static var _cache_frame: int = -1
static var _fams_at: Dictionary = {}     ## storage instance id -> {family: true}
static var _home_at: Dictionary = {}     ## "id:family" -> 0..1 how much it's by the home area
static var _all: Array = []

static func _cache(tree: SceneTree) -> void:
	var f: int = Engine.get_physics_frames()
	if f == _cache_frame:
		return
	_cache_frame = f
	_fams_at.clear()
	_home_at.clear()
	_all = storages(tree)
	for st: Node in _all:
		var fams: Dictionary = {}
		for it: Node in contents(st):
			fams[family_of(it)] = true
		_fams_at[st.get_instance_id()] = fams

## 0..1: how much this storage is "by" the family's home area.
static func home_factor(storage: Node3D, family: String) -> float:
	_cache(storage.get_tree())
	var k: String = "%d:%s" % [storage.get_instance_id(), family]
	if _home_at.has(k):
		return float(_home_at[k])
	var best: float = INF
	for g: String in FAMILIES.get(family, {}).get("anchors", []):
		for a: Node in storage.get_tree().get_nodes_in_group(g):
			if a is Node3D:
				best = minf(best, _flat((a as Node3D).global_position, storage.global_position))
	var f: float = clampf((ANCHOR_FAR - best) / (ANCHOR_FAR - ANCHOR_NEAR), 0.0, 1.0) if best < INF else 0.0
	_home_at[k] = f
	return f

static func near_home(storage: Node3D, family: String) -> bool:
	return home_factor(storage, family) >= HOME_SAYS_BY

## Does this family already live in another storage right beside this one?
## (Counts the item being placed if it's in one of them: close enough, and
## it only nudges toward keeping things where they already are.)
static func family_in_area(storage: Node3D, family: String, _exclude: Node = null) -> bool:
	_cache(storage.get_tree())
	for other: Node in _all:
		if other == storage or not is_instance_valid(other) \
				or _flat((other as Node3D).global_position, storage.global_position) > AREA_RADIUS:
			continue
		if (_fams_at.get(other.get_instance_id(), {}) as Dictionary).has(family):
			return true
	return false

# ─── Scoring ─────────────────────────────────────────────────────────────────
## How wrong a place this storage is for the item (lower is better; no
## walking included). Negative = a good fit.
static func fit_cost(item: Node, storage: Node3D) -> float:
	var size: int = size_of(item)
	var fam: String = family_of(item)
	var drawer: bool = is_drawer(storage)
	var c: float = 0.0
	if size == SMALL and not drawer:
		c += SIZE_SMALL_ON_SHELF
	elif size != SMALL and drawer:
		c += SIZE_BIG_IN_DRAWER
	c -= float(FAMILIES[fam]["weight"]) * home_factor(storage, fam)
	var here: Array = contents(storage, item)
	if not here.is_empty():
		var n: float = float(here.size())
		var same_fam: int = 0
		var same_type: int = 0
		var key: String = key_of(item)
		for it: Node in here:
			if family_of(it) == fam:
				same_fam += 1
			if key_of(it) == key:
				same_type += 1
		var w: float = 0.5 if drawer else 1.0   ## drawers hide their contents: mixing matters less
		c += w * (-SAME_FAMILY_BONUS * same_fam / n + OTHER_FAMILY_COST * (n - same_fam) / n)
		if not drawer:
			c += OTHER_TYPE_COST * (n - same_type) / n
			if same_type > 0:
				c -= SAME_TYPE_BONUS
	if fam != "misc" and family_in_area(storage, fam, item):
		c -= SAME_AREA_BONUS
	return c

## Total cost of taking the item there from `from` (tidying destinations).
static func place_cost(item: Node, storage: Node3D, from: Vector3) -> float:
	return WALK_WEIGHT * _flat(from, storage.global_position) + fit_cost(item, storage)

## The main reason this storage suits the item ("" if nothing stands out).
static func reason(item: Node, storage: Node3D) -> String:
	var fam: String = family_of(item)
	if FAMILY_REASON.has(fam) and near_home(storage, fam):
		return String(FAMILY_REASON[fam])
	if fam == "stores":
		for it: Node in contents(storage, item):
			if family_of(it) == "stores":
				return "stores"
		if family_in_area(storage, fam, item) or near_home(storage, fam):
			return "stores"
	if size_of(item) == SMALL and is_drawer(storage):
		return "drawer"
	for it: Node in contents(storage, item):
		if key_of(it) == key_of(item):
			return "same"
	return ""

## Walking past nearer storage that had room? Then say why ("" otherwise).
static func why_here(from: Vector3, item: Node, storage: Node3D) -> String:
	if item == null or storage == null:
		return ""
	var d_here: float = _flat(from, storage.global_position)
	for other: Node in storages(storage.get_tree()):
		if other == storage or not other.has_method("has_room_for") or not other.has_room_for(item):
			continue
		if _flat(from, (other as Node3D).global_position) + FAR_EXTRA_M <= d_here:
			return reason(item, storage)
	return ""

# ─── Slot on a shelf ─────────────────────────────────────────────────────────
## Best slot for the item on this shelf (-1: let the shelf pick). Tops up
## its own stack first; otherwise big things low, small things high, its
## own type beside it, and a fresh row rather than a mixed one.
static func best_shelf_slot(shelf: Node, item: Node) -> int:
	if not ("slots" in shelf) or not shelf.has_method("can_place_in_slot"):
		return -1
	var slots: Array = shelf.slots
	var spt: int = maxi(1, int(shelf.slots_per_tier))
	var tiers: int = int(ceil(float(slots.size()) / float(spt)))
	var key: String = shelf._get_item_type(item)
	for i: int in slots.size():
		if not (slots[i] as Array).is_empty() and shelf.can_place_in_slot(item, i):
			return i
	var size: int = size_of(item)
	var fam: String = family_of(item)
	var pref: int = 0 if size == LARGE else (tiers - 1 if size == SMALL else mini(1, tiers - 1))
	var best: int = -1
	var best_s: float = INF
	for i: int in slots.size():
		if not (slots[i] as Array).is_empty():
			continue
		var tier: int = i / spt
		var col: int = i % spt
		var s: float = absf(float(tier - pref))
		for c: int in spt:
			var j: int = tier * spt + c
			if c == col or j >= slots.size() or (slots[j] as Array).is_empty():
				continue
			var other: Node = slots[j][0]
			if shelf._get_item_type(other) == key:
				s -= 3.0 if absi(c - col) == 1 else 1.5
			elif family_of(other) == fam:
				s += 1.25
			else:
				s += 1.5
		for dt: int in [-1, 1]:
			var j2: int = (tier + dt) * spt + col
			if tier + dt >= 0 and j2 < slots.size() and not (slots[j2] as Array).is_empty() \
					and shelf._get_item_type(slots[j2][0]) == key:
				s -= 0.5
		if s < best_s:
			best_s = s
			best = i
	return best

# ─── Re-organizing (ReorganizeActivity) ──────────────────────────────────────
## A stored item may move when another storage with room fits it clearly
## better. Only single moves into free space (never swaps or chains), so the
## bunker never passes through a messier state; each is worth at least
## REORG_MIN_GAIN. Never touches what the player placed in the last game
## day, or an item moved recently.
const REORG_MIN_GAIN: float = 4.0
const PLAYER_PIN_HOURS: float = 24.0
const REORG_ITEM_GAP_MS: int = 20 * 60 * 1000
const MOVES_REFRESH_MS: int = 3000
const MOVE_WALK_WEIGHT: float = 0.1
static var _moves: Array = []
static var _moves_at_ms: int = -100000

static func pinned(item: Node) -> bool:
	if item.has_meta("player_placed_h") and NPCClock.now() - float(item.get_meta("player_placed_h")) < PLAYER_PIN_HOURS:
		return true
	return Time.get_ticks_msec() - int(item.get_meta("_reorg_ms", -REORG_ITEM_GAP_MS * 2)) < REORG_ITEM_GAP_MS

## Moves worth making, best first: [{item, from, slot, to, gain, reason}].
## Cached for a few seconds (all residents share one view, so they agree).
static func moves(tree: SceneTree) -> Array:
	var now: int = Time.get_ticks_msec()
	if now - _moves_at_ms < MOVES_REFRESH_MS:
		return _moves
	_moves_at_ms = now
	_moves = []
	_cache(tree)
	var all: Array = _all.duplicate()
	for src: Node in all:
		var sources: Array = []   ## [item, slot]
		if "slots" in src:
			for i: int in (src.slots as Array).size():
				var stack: Array = src.slots[i]
				if not stack.is_empty() and is_instance_valid(stack.back()):
					sources.append([stack.back(), i])   ## only the top of a stack comes off
		elif "stored" in src:
			for i: int in (src.stored as Array).size():
				var it: Variant = src.stored[i]
				if it != null and is_instance_valid(it):
					sources.append([it, i])
		for pair: Array in sources:
			var item: Node = pair[0]
			if pinned(item):
				continue
			var current: float = fit_cost(item, src)
			var best: Node = null
			var best_c: float = INF
			for dst: Node in all:
				if dst == src or not dst.has_method("has_room_for") or not dst.has_room_for(item):
					continue
				var c: float = fit_cost(item, dst) + MOVE_WALK_WEIGHT * _flat((src as Node3D).global_position, (dst as Node3D).global_position)
				if c < best_c:
					best_c = c
					best = dst
			if best != null and current - best_c >= REORG_MIN_GAIN:
				_moves.append({"item": item, "from": src, "slot": pair[1], "to": best,
					"gain": current - best_c, "reason": reason(item, best)})
	_moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["gain"]) > float(b["gain"]))
	return _moves

## Forget the cache (a move just happened, or a test changed storage).
static func invalidate() -> void:
	_moves_at_ms = -100000
	_cache_frame = -1
