extends CanvasLayer
## BuildModeHUD.gd
## Full build-mode overlay:
##   - Pulsing teal screen border
##   - "BUILD MODE" banner + red cancel X button (top-left)
##   - Bottom toolbar: Construct / Deconstruct / Duplicate / Move / Undo
##   - Construct submenu: vertical panel above toolbar with 3D previews, names, prices
##   - Hammer cursor following the mouse
##   - Rock dig confirm dialog (Yes / No)

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tool_selected(tool_id: int)
signal construct_item_chosen(tile_id: int)   ## Emitted when player picks from submenu
## Farming System plan §8.1 — a genuinely different toolbar tool (buy → spawn
## near player, not ghost-preview placement). Emitted when the player picks a
## Soil/Seeds item from the Farming shop submenu (see FARMING_SHOP_ITEMS).
signal farming_item_chosen(item_id: int)
signal cancel_requested()                     ## Red X or RMB — cancel active ghost
signal undo_requested()                       ## Undo button clicked — instant action
signal dig_confirmed()                        ## Player confirmed a rock dig
signal dig_cancelled()                        ## Player declined a rock dig
## Aug 2026 — D-pad up/down (build submenu closed) requests a grid-size step.
## +1 = coarser, -1 = finer. BuildModeController owns the actual cycling.
signal grid_size_step_requested(amount: int)

# ─── Tool IDs ─────────────────────────────────────────────────────────────────
const TOOL_CONSTRUCT:   int = 0
const TOOL_DECONSTRUCT: int = 1
const TOOL_DUPLICATE:   int = 2
const TOOL_MOVE:        int = 3
const TOOL_UNDO:        int = 4
const TOOL_WIRE:        int = 5   ## Wire draw — click A → click B to place wire
const TOOL_WATER_PIPE:  int = 6   ## Water pipe draw (July 2026 groundwork pass) — click A → click B, auto-elbow at corners
const TOOL_FARMING:     int = 7   ## Farming shop (Jul 2026) — buy → spawn near player, no ghost preview

# ─── Construct-able items — organised by category ─────────────────────────────
## Two-level menu: pick category → pick item.
## tile_id must match BuildModeController constants.
const CATEGORIES: Dictionary = {
	"Structure": [
		{ "tile_id": 1, "name": "Wall",         "price": 50  },
		{ "tile_id": 25, "name": "Half-Wall",   "price": 30  },
		{ "tile_id": 26, "name": "Quarter-Wall","price": 15  },
		{ "tile_id": 2, "name": "Pillar",       "price": 25  },
	],
	"Furniture": [
		{ "tile_id": 3, "name": "Medium Shelf", "price": 75  },
		{ "tile_id": 34, "name": "Small Shelf", "price": 45  },
		{ "tile_id": 35, "name": "Large Shelf", "price": 180 },
		{ "tile_id": 4, "name": "Bed",     "price": 150 },
		{ "tile_id": 27, "name": "Small Table",  "price": 60  },
		{ "tile_id": 28, "name": "Medium Table", "price": 110 },
		{ "tile_id": 29, "name": "Chair",        "price": 45  },
		{ "tile_id": 32, "name": "End Table",    "price": 60  },
		{ "tile_id": 33, "name": "Dresser",      "price": 150 },
		{ "tile_id": 36, "name": "Trash Can",    "price": 50  },
		{ "tile_id": 31, "name": "Poster",       "price": 20  },
	],
	"Lighting": [
		{ "tile_id": 5, "name": "Light",   "price": 50  },
		## Grow lights (Jul 2026, Farming System) — structurally just another
		## light fixture to the build system, per plan §5.1. Prices are
		## placeholders, unreviewed — flagged for a future balance pass, same
		## convention this project already applies to new device pricing.
		{ "tile_id": 23, "name": "Grow Light",       "price": 180 },
		{ "tile_id": 24, "name": "Grow Light (Pro)", "price": 350 },
	],
	"Power": [
		{ "tile_id": 6,  "name": "Gen S",     "price": 1200  },
		{ "tile_id": 7,  "name": "Gen M",     "price": 3500  },
		{ "tile_id": 8,  "name": "Gen L",     "price": 12000 },
		{ "tile_id": 10, "name": "Terminal",  "price": 2500  },
		{ "tile_id": 11, "name": "Load Test", "price": 0     },
		{ "tile_id": 12, "name": "Breaker",   "price": 80    },
		{ "tile_id": 16, "name": "Breaker (Smart)", "price": 240 },
		{ "tile_id": 13, "name": "Battery S", "price": 150   },
		{ "tile_id": 14, "name": "Battery M", "price": 350   },
		{ "tile_id": 15, "name": "Battery L", "price": 600   },
	],
	"Water": [
		## July 2026 groundwork pass. Test Sink price is a placeholder (plan
		## does not specify economics for this pass — flagged for a future
		## balance pass). Hookup (tile_id 17) intentionally NOT listed here —
		## exactly one hookup exists per game (auto-placed at start by
		## MainWorld._spawn_initial_water_hookup(), see docs/systems/water/
		## README.md) and is relocatable only via the Move tool, never
		## re-purchasable from this menu (Step 2 plan, July 2026).
		{ "tile_id": 18, "name": "Test Sink", "price": 0   },
		## Water Dispenser (Jul 2026, demand/priority pass) — the first real
		## water-consuming device. Price is a placeholder (plan does not
		## specify economics for this pass, same caveat as Test Sink above) —
		## flagged for a future balance pass.
		{ "tile_id": 19, "name": "Dispenser", "price": 250 },
		## Purifier (Jul 2026) — attaches directly onto an existing pipe run,
		## no floor/wall snap (see WaterPurifierAttach.gd / GhostPreview.gd's
		## TILE_WATER_PURIFIER branch). $240 fixed price, refunded on delete.
		{ "tile_id": 20, "name": "Purifier",  "price": 240 },
	],
	"Farming": [
		## Farming System (Jul 2026) — the two tray tiles only. Grow lights
		## live in "Lighting" above (plan §5.1); Soil/Seeds are sold through
		## the separate Farming toolbar tool's shop (FARMING_SHOP_ITEMS below),
		## NOT this menu — see plan §0.2's "naming collision" note.
		{ "tile_id": 21, "name": "Tray (1x1)", "price": 150 },
		{ "tile_id": 22, "name": "Tray (2x1)", "price": 275 },
	],
	"Cooking": [
		## Cooking System (Aug 2026) — Stove only. Cooking Pot is a carryable
		## item, bought through the Farming toolbar's shop instead (see
		## FARMING_SHOP_ITEMS "Miscellaneous" below), same reasoning as Basket.
		{ "tile_id": 30, "name": "Stove", "price": 500 },
	],
}

## Farming toolbar tool's shop (Jul 2026, plan §8.2) — a SEPARATE dict from
## CATEGORIES since these aren't placeable/ghost-preview tiles at all, just
## carryable items bought and spawned near the player (see
## Farming shop (Jul 2026) — buy → spawn near player, no ghost preview.
## Uses same flat category structure as CATEGORIES so the existing
## two-level submenu works unchanged.
const FARMING_SHOP_ITEMS: Dictionary = {
	"Soil": [
		{ "tile_id": 1, "name": "Bag of Soil",       "price": 100 },
		{ "tile_id": 14, "name": "Normal Fertilizer", "price": 300 },
		{ "tile_id": 15, "name": "Pro Fertilizer",    "price": 400 },
	],
"Seeds": [
		{ "tile_id": 2, "name": "Tomato Seeds", "price": 25 },
		{ "tile_id": 3, "name": "Onion Seeds",  "price": 25 },
		{ "tile_id": 4,  "name": "Basil Seeds",        "price": 25 },
		{ "tile_id": 5,  "name": "Strawberry Seeds",   "price": 25 },
		{ "tile_id": 6,  "name": "Carrot Seeds",       "price": 25 },
		{ "tile_id": 7,  "name": "Chili Pepper Seeds", "price": 25 },   ## Aug 2026 fix — was 6 (duplicate of Carrot), cascaded every id below down by one
		{ "tile_id": 8,  "name": "Bell Pepper Seeds",  "price": 25 },   ## Aug 2026 fix — was 7
		{ "tile_id": 9,  "name": "Garlic Seeds",       "price": 25 },   ## Aug 2026 fix — was 8
		{ "tile_id": 10, "name": "Potato Seeds",       "price": 25 },   ## Aug 2026 fix — was 9
		{ "tile_id": 11, "name": "Blueberry Seeds",    "price": 25 },   ## Aug 2026 fix — was 10
		{ "tile_id": 12, "name": "Corn Seeds",         "price": 25 },   ## Aug 2026 fix — was 11
		{ "tile_id": 13, "name": "Pumpkin Seeds",      "price": 25 },   ## Aug 2026 fix — was 12 (13 was never used by anything before this fix)
	],
	"Resources": [
		{ "tile_id": 16, "name": "Water Case", "price": 80  },
		{ "tile_id": 17, "name": "Can Case",   "price": 60  },
		{ "tile_id": 18, "name": "Fuel Can",   "price": 120 },
	],
	"Miscellaneous": [
		{ "tile_id": 19, "name": "Crate", "price": 40 },
		{ "tile_id": 20, "name": "Basket", "price": 100 },
		## Cooking Pot (Aug 2026) — price is a placeholder, unreviewed —
		## flagged for a future balance pass, same convention this project
		## already applies to new device/item pricing.
		{ "tile_id": 21, "name": "Cooking Pot", "price": 120 },
	],
}

## Item preview source per shop item_id (Jul 2026) — mirrors
## FarmingShopHelper.SHOP_ITEM_INFO's item_ids exactly, but only needs to
## know how to build a throwaway instance for rendering a preview, not how
## to actually spawn/sell the item. "scene": load this .tscn. "script": call
## .new() on this script (used for the procedurally-built items that don't
## have their own .tscn).
const PREVIEW_SOURCES: Dictionary = {
	1:  { "scene": "res://scripts/world/items/BagOfSoilItem.gd", "is_script": true },
	## Aug 2026 fix — each seed now carries its own seed_type so
	## _refresh_shop_previews() below can set it on the instance before
	## _ready() runs, exactly matching FarmProduceItem's existing
	## produce_type handling. Without this every seed defaulted to
	## SeedItem.gd's "tomato" fallback and looked identical. Values match
	## FarmingShopHelper.SHOP_ITEM_INFO's "type" field exactly for each id.
	2:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "tomato" },
	3:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "onion" },
	4:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "basil" },
	5:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "strawberry" },
	6:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "carrot" },
	7:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "chili_pepper" },
	8:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "bell_pepper" },
	9:  { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "garlic" },
	10: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "potato" },
	11: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "blueberry" },
	12: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "corn" },
	13: { "scene": "res://scripts/world/items/SeedItem.gd", "is_script": true, "seed_type": "pumpkin" },
	14: { "scene": "res://scripts/world/items/FertilizerItem.gd", "is_script": true },
	15: { "scene": "res://scripts/world/items/FertilizerItem.gd", "is_script": true },
	16: { "scene": "res://scenes/world/WaterCase.tscn", "is_script": false },
	17: { "scene": "res://scenes/world/CanCase.tscn",   "is_script": false },
	18: { "scene": "res://scenes/world/FuelCan.tscn",   "is_script": false },
	19: { "scene": "res://scenes/world/TestCrate.tscn", "is_script": false },
	20: { "scene": "res://scenes/world/Basket.tscn", "is_script": false },
	21: { "scene": "res://scenes/world/CookingPot.tscn", "is_script": false },
}

## Flat list used only for legacy compat (3D preview viewports, etc.)
## Generated from CATEGORIES at runtime — do NOT edit directly.
var CONSTRUCT_ITEMS: Array = []

## Helper: look up price for a tile_id across all categories.
func get_item_price(tile_id: int) -> int:
	for cat_items: Array in CATEGORIES.values():
		for item: Dictionary in cat_items:
			if item["tile_id"] == tile_id:
				return item["price"]
	return 0

func available_cash() -> int:
	if shop_wallet != null and shop_wallet.has_method("get_cash"):
		return int(shop_wallet.get_cash())
	return 0

func checkout_order(lines: Dictionary) -> Dictionary:
	if shop_service != null and shop_service.has_method("checkout_order"):
		return shop_service.checkout_order(lines)
	return {"ok": false, "message": "The supply service is unavailable."}

func preview_texture(item_id: int, shop: bool = false) -> Texture2D:
	if shop:
		var shop_index := PREVIEW_SOURCES.keys().find(item_id)
		return _shop_vp_textures[shop_index] if shop_index >= 0 and shop_index < _shop_vp_textures.size() else null
	for i in CONSTRUCT_ITEMS.size():
		if int(CONSTRUCT_ITEMS[i].tile_id) == item_id:
			return _sub_vp_textures[i] if i < _sub_vp_textures.size() else null
	return null

func choose_build_item(tile_id: int) -> void:
	var selected_name := "Build item"
	var selected_price := get_item_price(tile_id)
	for item: Dictionary in CONSTRUCT_ITEMS:
		if int(item.tile_id) == tile_id:
			selected_name = str(item.name)
			break
	_placement_menu = {"source": "construct", "level": "items", "category": _active_category}
	construct_item_chosen.emit(tile_id)
	## Keep the catalog available during placement so another object is one
	## click away. World placement remains available anywhere outside the rail.
	_submenu_open = true
	_submenu_source = "construct"
	if _workspace != null:
		_workspace.placement_started(tile_id, selected_name, selected_price)

func open_shop_menu() -> void:
	cancel_requested.emit()
	active_tool = TOOL_FARMING
	tool_selected.emit(TOOL_FARMING)
	_open_submenu("farming")

func close_workspace_menu() -> void:
	_close_submenu()

func pointer_over_ui(point: Vector2) -> bool:
	return _workspace != null and _workspace.covers(point)

func _warm_preview_pool() -> void:
	## Viewports are created during _ready; population is staggered during
	## idle frames so the first user-open has no synchronous construction hit.
	for attempt in 120:
		if gridmap != null and gridmap.mesh_library != null:
			break
		await get_tree().process_frame
	if gridmap != null and gridmap.mesh_library != null:
		await _build_submenu_previews_staggered()

# ─── Visual constants ──────────────────────────────────────────────────────────
## Project blue identity color for the build-mode screen border.
const ACCENT:       Color = Color(0.40, 0.75, 1.00, 1.0)
const BORDER_W:     float = 4.0
const BORDER_INSET: float = 6.0

const BANNER_BG:    Color = Color(0.06, 0.14, 0.04, 0.88)
const BANNER_TEXT:  Color = Color(0.251, 0.443, 0.435, 1.0)

## Toolbar
const SLOT_W:       float = 100.0
const SLOT_H:       float = 56.0
const SLOT_GAP:     float = 8.0
const SLOT_CORNER:  float = 8.0
const COLOR_BG:     Color = Color(0.10, 0.10, 0.10, 0.82)
const COLOR_BORDER: Color = Color(0.25, 0.25, 0.25, 0.90)
const COLOR_SEL:    Color = Color(0.251, 0.443, 0.435, 1.0)
const COLOR_TEXT:   Color = Color(0.80, 0.78, 0.72, 0.95)
const TOOL_LABELS:  Array = ["Construct", "Deconstruct", "Duplicate", "Move", "Undo", "Wire", "Pipe", "Shop"]
const TOOL_ICONS:   Array = ["🧱", "🔨", "📋", "✥", "↩", "🔌", "🚰", "🛒"]

# ─── Controller prompt icons (Aug 2026) ───────────────────────────────────────
## LB/RB tab-cycle badges on the toolbar (LB top-left of Construct, RB
## top-right of Shop), shown in controller mode. Same 32px as ResearchStation.
## Legacy hand-drawn toolbar badges. The toolbar is now native Controls, so
## these are intentionally not loaded (avoids retaining unused image assets).
var XBOX_LB_ICON: Texture2D = null
var XBOX_RB_ICON: Texture2D = null
const TOOL_BADGE_SIZE: float = 20.0

## Submenu
const SUB_W:        float = 160.0
const SUB_ITEM_H:   float = 72.0   ## Height per row in submenu
const SUB_VP_SIZE:  int   = 192    ## High-res pooled texture, downscaled in cards
const SUB_GAP:      float = 6.0
const SUB_PAD:      float = 10.0
const SUB_BG:       Color = Color(0.08, 0.10, 0.07, 0.94)
const SUB_BORDER:   Color = Color(0.251, 0.443, 0.435, 0.60)
const PRICE_COLOR:  Color = Color(0.35, 0.95, 0.30, 1.0)

## Item preview pose/animation (Jul 2026). Default resting pose: rotated
## 45° to the left and 45° down from straight-on. While the mouse hovers a
## row, its preview spins clockwise continuously; on hover-out it snaps
## straight back to this same default pose (no easing).
const PREVIEW_ROTATION_DEFAULT: Vector3 = Vector3(-45.0, -45.0, 0.0)
const PREVIEW_HOVER_SPIN_DEG_PER_SEC: float = 90.0
## Orthographic camera size — smaller = more zoomed in. 1.6 / 1.5 ≈ 1.0667
## gives a 1.5x zoom over the original framing.
const PREVIEW_CAM_SIZE: float = 0.78

## World-units the object's LARGEST AABB dimension should map to after
## normalization, regardless of its real size — the single knob that
## controls how "full" every preview looks in its fixed-size camera frame.
## ~0.85 leaves a small margin so a rotating/spinning object doesn't clip
## the viewport edge. Tune this visually first if previews look too
## tight/loose overall — it affects every preview uniformly, so this is
## the ONLY number that should ever need adjusting, never a per-item one.
const PREVIEW_TARGET_SIZE: float = 0.5667

## Returns the uniform scale factor that makes `aabb`'s single largest
## dimension equal PREVIEW_TARGET_SIZE. Apply this to a preview's PIVOT
## node (never the mesh/instance child) — composes cleanly with the
## pivot's existing PREVIEW_ROTATION_DEFAULT and the child's own
## `-aabb.get_center()` centering offset with zero extra math needed (a
## uniform scale on an already-centered child stays centered regardless
## of the scale factor). Seed packets (~0.14m) and Generator L (~1.85m)
## both end up reading as the same on-screen size in every preview pool.
static func _preview_normalize_scale(aabb: AABB) -> float:
	var largest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	if largest < 0.0001:
		return 1.0
	return PREVIEW_TARGET_SIZE / largest

## Computes the combined AABB of every MeshInstance3D descendant of
## `root`, correctly expressed in root's OWN local coordinate space —
## i.e. accounting for each mesh's position/rotation relative to root,
## not just merging each mesh's raw local-space AABB as if every child
## sat exactly at root's own origin.
##
## THIS IS THE FIX (Jul 2026) for the "rotates around its feet instead of
## spinning in place" bug: almost every procedural device positions its
## body mesh ABOVE its own root node (so the root represents the
## floor-contact point, e.g. GeneratorObject's body sits at local
## Y = height/2 — see BOX_SIZE.y * 0.5 convention used throughout
## scripts/world/power|water/*.gd). The OLD version of this walk ignored
## that offset entirely, silently treating every child mesh as if it were
## centered at root's own origin — biasing the computed "center" toward
## each object's base. Rotating a pivot around that miscomputed point
## looked like the object orbiting around its feet, not its true middle.
##
## Uses GLOBAL transforms (root_inverse * mi.global_transform) rather
## than a mesh's own local `.transform` — correct regardless of how many
## levels deep a mesh is nested (a direct child, or 2-3 levels down inside
## an imported model), which a single-level-only approach would get wrong.
## Requires `root` to already be inside the SceneTree (global_transform
## must be valid) — call this AFTER add_child(), never before.
static func _combined_local_aabb(root: Node3D) -> Dictionary:
	var combined: AABB = AABB()
	var found_any: bool = false
	var root_inverse: Transform3D = root.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = n as MeshInstance3D
			var relative_transform: Transform3D = root_inverse * mi.global_transform
			var mesh_aabb: AABB = relative_transform * mi.mesh.get_aabb()
			if not found_any:
				combined = mesh_aabb
				found_any = true
			else:
				combined = combined.merge(mesh_aabb)
		for c in n.get_children():
			stack.append(c)
	return { "aabb": combined, "found_any": found_any }

## Preview source for CONSTRUCT_ITEMS tile_ids that have no MeshLibrary
## entry — procedural furniture/devices built in
## BuildModeController.spawn_structure() instead of placed via the gridmap.
## Each path is copied DIRECTLY from that tile_id's own branch in
## spawn_structure() — same asset the real object uses, so the preview
## can't drift out of sync with what actually gets placed. "is_script":
## true → spawn_structure() attaches this .gd script to a bare Node3D
## (e.g. Shelving, WaterDispenser) — mirror that here. false → this is a
## .tscn to instantiate directly (e.g. Bed).
##
## Returns a side-effect-free ghost Mesh for any CONSTRUCT_ITEMS tile_id
## that has no MeshLibrary entry (Bed, Shelving, generators, batteries,
## water/farming devices, etc.) — called from _refresh_submenu_previews()
## to fill in the same viewport slots that already exist for every
## construct-tab item, no separate pool needed. Every branch calls a
## static build_ghost_mesh() helper — NEVER instantiates the real gameplay
## script/scene (see docs/systems/build/README.md for why: a previous
## version of this feature did exactly that and it registered 15 real
## phantom devices — including 3 real running generators — into the live
## PowerManager/WaterManager the instant Build Mode opened).
##
## NOW DELEGATED to GhostModelBuilder.gd — single source of truth for
## both Construct submenu previews and in-world ghosts.

## Builds a detached, side-effect-free instance of the REAL object script/
## scene for a construct-tab preview — sets _is_preview_only BEFORE
## add_child() (required, see that var's own comment on each script) so
## _ready() skips registration/grouping but still runs its real
## mesh-building call(s) unmodified. Returns null if this tile_id isn't in
## GhostModelBuilder.PROCEDURAL_PREVIEW_SOURCES or the resource fails to load.
func _build_procedural_preview_instance(tile_id: int) -> Node3D:
	return GhostModelBuilder.build_real_instance(tile_id)

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:       Control        = null   ## Full-screen draw surface
var _cursor:       Control        = null   ## Code-drawn build/controller cursor
var _banner:       PanelContainer = null
var _banner_label: Label          = null
var _cancel_btn:   Control        = null   ## Red X button

## Submenu nodes (built once, shown/hidden)
var _submenu_root:    Control   = null
var _sub_viewports:   Array     = []   ## SubViewport per construct item
var _sub_vp_textures: Array     = []   ## ViewportTexture handles
var _sub_mesh_instances: Array  = []   ## MeshInstance3D per construct item (parallel to _sub_viewports) — null until _refresh_submenu_previews() fills it
## Shop items (Soil/Seeds/Fertilizer/Resources/Miscellaneous) get their own
## pool, built once in _ready(), since they're not MeshLibrary tiles —
## their preview comes from instantiating the item's own scene/script.
var _shop_viewports:      Array = []
var _shop_vp_textures:    Array = []
var _shop_mesh_instances: Array = []
## True once the construct + shop previews have been built (staggered across
## frames — see _build_submenu_previews_staggered). The previews persist and
## are reused across build-mode sessions, so this only ever builds once.
var _submenu_previews_ready: bool = false
## Which submenu row is currently hovered — used by _process() to know
## which preview (construct or shop pool) to spin, and to snap every other
## one back to PREVIEW_ROTATION_DEFAULT. -1 = none hovered / not on an item row.
var _hovered_preview_index: int = -1
var _hovered_preview_is_shop: bool = false

# ─── External refs ────────────────────────────────────────────────────────────
## Set by BuildModeController after _ready — used to read tile meshes
var gridmap: GridMap  = null
## Camera ref — injected by MainWorld so we can project 3D→2D for the overlay
var camera: Camera3D  = null
## Set each frame by BuildModeController when deconstruct tool is active.
## Sentinel value (-9999 …) means nothing is hovered.
var hovered_deconstruct_cell: Vector3    = Vector3(-9999.0, -9999.0, -9999.0)
## Set each frame when Duplicate or Rotate tool is active and cursor is over a placed object.
var hovered_dupe_rotate_pos: Vector3     = Vector3(-9999.0, -9999.0, -9999.0)
## Set each frame when Deconstruct tool is active and cursor is over a rock chunk.
var hovered_rock_chunk_world_pos: Vector3 = Vector3(-9999.0, -9999.0, -9999.0)

# ─── State ────────────────────────────────────────────────────────────────────
var active_tool:      int   = TOOL_CONSTRUCT
var _submenu_open:    bool  = false
var _workspace: BuildWorkspace = null
var shop_service: RefCounted = null
var shop_wallet: Node = null
## Two-level menu state: "root" = category list, "items" = item list for _active_category
var _submenu_level:    String = "root"
var _active_category:  String = ""
## Controller (Aug 2026): d-pad / LB-RB select a toolbar tab (A opens it);
## d-pad up/down scrolls the open submenu (A picks). Highlighted in
## controller mode.
var _sel_tool: int = TOOL_CONSTRUCT
var _submenu_cursor: int = 0
## Mirrors BuildModeController's ghost state (set via set_ghost_active) — used
## so the controller A button knows when a placement/draw is active and must
## place instead of clicking tabs.
var _ghost_active: bool = false
## Mirrors BuildModeController's wall-draw state (tool 0 + WallDrawMode):
## walls have no ghost, so the HUD must know wall-draw is active to block the
## tabs / make B exit the placement. See set_wall_draw_active().
var _wall_draw_active: bool = false
## Cached copy of BuildModeController's current placement grid. The redesigned
## helper strip renders this as text instead of relying on the retired image
## badges, keeping the information visible without another generated asset.
var _grid_size_value: float = 0.25
## The submenu that launched the current placement (source/level/category),
## recorded at construct item pick. B restores it when it cancels a
## placement. Empty = the placement came from a toolbar tool (wire/pipe)
## with no submenu to return to.
var _placement_menu: Dictionary = {}
## Which data source the submenu is currently browsing — "construct"
## (CATEGORIES, tile ghost-preview placement) or "farming" (FARMING_SHOP_ITEMS,
## buy → spawn near player). See _current_categories()/_open_submenu().
var _submenu_source:   String = "construct"
var _pulse_t:         float = 0.0
var _mouse_pos:       Vector2 = Vector2.ZERO
var _cancel_hovered:  bool  = false
## Brief flash when Undo is clicked (counts down from UNDO_FLASH_TIME to 0)
var _undo_flash_t:    float = 0.0
const UNDO_FLASH_TIME: float = 0.25

## Rock dig confirm dialog state — mirrors whether the shared ConfirmDialogUI
## is open (BuildModeController guards on this, so it must stay in sync).
var dig_confirm_open: bool = false
## Lazy-instantiated shared confirm dialog (Aug 2026 consistency pass — the
## old hand-rolled _draw_dig_confirm() is gone; everything routes through
## ConfirmDialogUI.gd now).
var _dig_confirm_dialog: CanvasLayer = null
## Controller (Aug 2026) — true while the player is within reach of the Build
## Station (set by BuildModeController each frame). While true, A is reserved
## for "Exit Build Mode" and every other A action (menu select, tab click,
## placement) is suppressed in the A branch below.
var _exit_available: bool = false

## Grid-size indicator (Aug 2026) — small TextureRect top-right, beneath the
## main HUD's cash panel, showing the current placement grid size icon.
## Sized no taller than the cash HUD element (44px → use 36px).
const GRID_ICON_DIR: String = "res://assets/ui/build/grid_size/"
const GRID_ICON_SIZE: int = 36
var _grid_size_icon: TextureRect = null

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer   = 10
	visible = false

	# Build flat CONSTRUCT_ITEMS from CATEGORIES (used for 3D preview viewports)
	for cat_items: Array in CATEGORIES.values():
		for item: Dictionary in cat_items:
			CONSTRUCT_ITEMS.append(item)

	# Full-screen canvas for border + toolbar
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.name = "BuildCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_canvas_draw)

	# Banner
	var style: StyleBoxFlat = _make_stylebox(BANNER_BG, Color.TRANSPARENT,
		Vector4i(0, 6, 6, 0))
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_banner.offset_left = 0.0
	_banner.offset_top  = 12.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", style)
	add_child(_banner)

	_banner_label = Label.new()
	_banner_label.text = "⚒  BUILD MODE"
	_banner_label.add_theme_color_override("font_color", BANNER_TEXT)
	_banner_label.add_theme_font_size_override("font_size", 15)
	_banner.add_child(_banner_label)

	# Cancel (X) button — built after banner so we can position after it resizes
	_cancel_btn = _build_cancel_button()
	add_child(_cancel_btn)
	_cancel_btn.visible = false

	# Submenu panel
	_submenu_root = _build_submenu()
	add_child(_submenu_root)
	_submenu_root.visible = false

	# Crisp code-drawn cursor: crosshair over the bunker, pointer over UI.
	_cursor = BuildCursor.new()
	_cursor.z_index = 100
	add_child(_cursor)

	# Grid-size indicator — top-right, directly beneath the main HUD's cash
	# panel (cash occupies y 12-56; this sits at y 60). 36px, well under the
	# cash element's 44px height so the big source icons never overtake the
	# screen.
	_grid_size_icon = TextureRect.new()
	_grid_size_icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_grid_size_icon.offset_left  = -(GRID_ICON_SIZE + 12.0)
	_grid_size_icon.offset_top   = 60.0
	_grid_size_icon.offset_right = -12.0
	_grid_size_icon.offset_bottom = 60.0 + GRID_ICON_SIZE
	## Default TextureRect behavior (EXPAND_KEEP_SIZE) forces the control to the
	## texture's 995px minimum size and draws it at native scale — the huge icons
	## in-game. Ignore the texture size and scale it into the 36px rect.
	_grid_size_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_grid_size_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_grid_size_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid_size_icon)

	## Native desktop workspace. The old hand-drawn menu remains allocated as
	## the stable preview pool, but is never presented or hit-tested.
	_banner.hide()
	_grid_size_icon.hide()
	_submenu_root.hide()
	_workspace = BuildWorkspace.new()
	_workspace.hud = self
	add_child(_workspace)

# ─── Process ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_t  += delta * 2.2
	_mouse_pos = get_viewport().get_mouse_position()
	var cursor_over_ui := pointer_over_ui(_mouse_pos)
	_cursor.set_position(_mouse_pos - (Vector2(5.0, 3.0) if cursor_over_ui else Vector2(17.0, 17.0)))
	if _cursor is BuildCursor:
		(_cursor as BuildCursor).over_ui = cursor_over_ui
	# Undo flash timer
	if _undo_flash_t > 0.0:
		_undo_flash_t = maxf(0.0, _undo_flash_t - delta)
	# Keep cancel X flush-right of the banner every frame
	_reposition_cancel_btn()
	_cursor.visible = not dig_confirm_open and (InputMode.is_controller() or not _submenu_open)
	if _workspace != null:
		_workspace.refresh(active_tool, _submenu_open, _submenu_source,
			_ghost_active or _wall_draw_active, _grid_size_value)
	_canvas.queue_redraw()

# ─── Public API ───────────────────────────────────────────────────────────────
func show_hud() -> void:
	visible = true
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	## NOTE: the construct/shop previews are deliberately NOT built here —
	## building ~55 of them synchronously (or even staggered) on build-mode
	## entry was the entry stutter. They build lazily, staggered, the first
	## time a submenu opens (_open_submenu).

func hide_hud() -> void:
	visible = false
	_submenu_open = false
	_submenu_root.visible = false
	_cancel_btn.visible   = false
	if _workspace != null:
		_workspace.close_all()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func set_active_tool(tool_id: int) -> void:
	active_tool = tool_id
	_canvas.queue_redraw()

## Called by BuildModeController when the placement grid size changes (and on
## build-mode entry) — shows the matching grid-size icon top-right.
func set_grid_size(grid_size: float) -> void:
	_grid_size_value = grid_size
	if _grid_size_icon == null:
		return
	var file: String = "grid_0125.png"
	if absf(grid_size - 0.25) < 0.001:
		file = "grid_025.png"
	elif absf(grid_size - 0.5) < 0.001:
		file = "grid_05.png"
	var tex: Texture2D = load(GRID_ICON_DIR + file) as Texture2D
	if tex != null:
		_grid_size_icon.texture = tex

## Called by BuildModeController when a ghost is active — show cancel X
func set_ghost_active(active: bool) -> void:
	_ghost_active = active
	_cancel_btn.visible = false

## Called by BuildModeController when wall-draw mode starts/stops (walls have
## no ghost — see _wall_draw_active).
func set_wall_draw_active(active: bool) -> void:
	_wall_draw_active = active

## Called by BuildModeController every frame — true while the player is in
## reach of the Build Station, where A must ALWAYS exit build mode.
func set_exit_available(available: bool) -> void:
	_exit_available = available

## Open / close the construct submenu externally
func open_construct_menu() -> void:
	_open_submenu("construct")

func close_construct_menu() -> void:
	if _submenu_open:
		_close_submenu()

## Open the rock dig confirmation dialog
func open_dig_confirm() -> void:
	_ensure_dig_confirm_dialog()
	dig_confirm_open = true
	_set_dig_dialog_cursor(true)
	_dig_confirm_dialog.open("EXPAND BUNKER", "$1,500")

## Close the rock dig confirmation dialog without emitting signals
func close_dig_confirm() -> void:
	dig_confirm_open = false
	_set_dig_dialog_cursor(false)
	if _dig_confirm_dialog != null and is_instance_valid(_dig_confirm_dialog):
		_dig_confirm_dialog.call("close")

## While the shared ConfirmDialogUI (layer 70) is open above this HUD's
## layer-10 tool cursor, the OS cursor must show — it always renders topmost,
## so the player can see where they're clicking — and the in-engine tool
## cursor is hidden for the dialog's duration (Aug 2026). Restored to
## build-mode HIDDEN + hammer on close. Controller mode is untouched
## (InputMode keeps the OS cursor hidden there; the dialog's d-pad selection
## outline is its own cursor).
func _set_dig_dialog_cursor(open: bool) -> void:
	if _cursor != null:
		_cursor.visible = not open
	if open:
		if not InputMode.is_controller():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

## Lazily create the shared ConfirmDialogUI and route its signals onto the
## build-mode dig signals (BuildModeController connects to those).
func _ensure_dig_confirm_dialog() -> void:
	if _dig_confirm_dialog != null and is_instance_valid(_dig_confirm_dialog):
		return
	var dlg_script: GDScript = load("res://scripts/ui/common/ConfirmDialogUI.gd")
	if dlg_script == null:
		push_warning("[BuildModeHUD] ConfirmDialogUI.gd not found")
		return
	_dig_confirm_dialog = CanvasLayer.new()
	_dig_confirm_dialog.set_script(dlg_script)
	_dig_confirm_dialog.name = "ConfirmDialogUI"
	add_child(_dig_confirm_dialog)
	_dig_confirm_dialog.confirmed.connect(_on_dig_confirm_yes)
	_dig_confirm_dialog.cancelled.connect(_on_dig_confirm_no)

func _on_dig_confirm_yes() -> void:
	dig_confirm_open = false
	_set_dig_dialog_cursor(false)
	dig_confirmed.emit()

func _on_dig_confirm_no() -> void:
	dig_confirm_open = false
	_set_dig_dialog_cursor(false)
	dig_cancelled.emit()

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# ── Rock dig confirm dialog — the shared ConfirmDialogUI owns ALL input
	# while open (its _unhandled_input eats everything; YES/NO/B/ESC/A). The
	# build HUD just bails so nothing here double-handles it. ───────────────
	if dig_confirm_open:
		return
	if _workspace != null and _workspace.menu_open():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if _ghost_active or _wall_draw_active:
				cancel_requested.emit()
			else:
				_close_submenu()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if _ghost_active or _wall_draw_active:
				cancel_requested.emit()
			else:
				_close_submenu()
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
			if _ghost_active or _wall_draw_active:
				cancel_requested.emit()
			else:
				_close_submenu()
			get_viewport().set_input_as_handled()
		return

	# Escape: close submenu if open, else cancel ghost
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _submenu_open:
			_close_submenu()
			get_viewport().set_input_as_handled()
			return
		else:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position

		if event.button_index == MOUSE_BUTTON_LEFT:
			# Cancel X button
			if _cancel_btn.visible and _cancel_btn.get_rect().has_point(pos):
				cancel_requested.emit()
				get_viewport().set_input_as_handled()
				return

			# Toolbar slot
			var slot: int = _get_toolbar_slot_at(pos)
			if slot != -1:
				_on_toolbar_click(slot)
				get_viewport().set_input_as_handled()
				return

			# Submenu item
			if _submenu_open:
				var item: int = _get_submenu_item_at(pos)
				if item != -1:
					_on_submenu_item_selected(item)
					get_viewport().set_input_as_handled()
					return
				# Click outside submenu while open → close it
				_close_submenu()
				get_viewport().set_input_as_handled()
				return

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# RMB always cancels ghost / submenu
			if _submenu_open:
				_close_submenu()
			else:
				cancel_requested.emit()
			get_viewport().set_input_as_handled()
			return

	# Track hover for cancel button redraw
	if event is InputEventMouseMotion:
		if _cancel_btn.visible:
			var was: bool = _cancel_hovered
			_cancel_hovered = _cancel_btn.get_rect().has_point(event.position)
			if was != _cancel_hovered:
				_canvas.queue_redraw()

	# ── Controller (Aug 2026) — build-mode menu only ─────────────────────────
	## d-pad / LB-RB cycle the toolbar tabs; d-pad up/down scrolls the open
	## submenu; A opens/selects; B closes the submenu. (The rock-dig confirm
	## dialog is a separate ConfirmDialogUI that owns its own input.)
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_DPAD_LEFT:
			_change_selected_tool(-1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER or event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_change_selected_tool(+1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == JOY_BUTTON_DPAD_UP:
			if _submenu_open:
				_submenu_cursor = maxi(_submenu_cursor - 1, 0)
				_canvas.queue_redraw()
			else:
				## Aug 2026 — D-pad up/down with the submenu closed cycles the
				## placement grid coarser/finer (mirrors the mouse wheel).
				grid_size_step_requested.emit(1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == JOY_BUTTON_DPAD_DOWN:
			if _submenu_open:
				_submenu_cursor = mini(_submenu_cursor + 1, _submenu_current_rows() - 1)
				_canvas.queue_redraw()
			else:
				grid_size_step_requested.emit(-1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == JOY_BUTTON_A:
			## Aug 2026 — the Build Station "Exit Build Mode" action ALWAYS
			## wins while in reach: fall through unhandled so the controller
			## exits build mode, beating menu/submenu selection, tab clicks,
			## and placement.
			if _exit_available:
				return
			## A = left-click in build mode:
			##  1. open submenu      → select the submenu item
			##  2. placing / drawing → place (fall through to the controller;
			##                          the ghost BLOCKS the tabs)
			##  3. cursor over a tab → click that tab
			##  4. deconstruct/dup/move → act on the object under the cursor
			##                          (fall through to the controller)
			##  5. otherwise         → activate the LB/RB-selected tab
			if _submenu_open:
				_on_submenu_item_selected(_submenu_cursor)
				get_viewport().set_input_as_handled()
				return
			if _ghost_active or _wall_draw_active \
				or active_tool == TOOL_WIRE or active_tool == TOOL_WATER_PIPE:
				return
			var slot: int = _cursor_over_toolbar_slot()
			if slot != -1:
				_on_toolbar_click(slot)
				get_viewport().set_input_as_handled()
				return
			if active_tool == 1 or active_tool == 2 or active_tool == 3:
				return
			_on_toolbar_click(_sel_tool)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == JOY_BUTTON_B:
			## B exits an active placement (object ghost, wall draw, wire/pipe
			## draw) and restores the submenu that launched it. With no
			## placement active it walks the submenu back up one level (items
			## → root categories), then exits entirely at the root level.
			if _ghost_active or _wall_draw_active \
				or active_tool == TOOL_WIRE or active_tool == TOOL_WATER_PIPE:
				cancel_requested.emit()
				_restore_placement_menu()
			elif _submenu_open:
				_submenu_back()
			get_viewport().set_input_as_handled()
			return
		else:
			## Consume other pad presses so they never reach the world.
			get_viewport().set_input_as_handled()
			return

# ─── Toolbar click handler ────────────────────────────────────────────────────
func _on_toolbar_click(slot: int) -> void:
	if slot == TOOL_CONSTRUCT:
		if _submenu_open:
			_close_submenu()
		else:
			# Clicking construct while ghost active: cancel ghost, open menu
			cancel_requested.emit()
			_open_submenu()
	elif slot == TOOL_UNDO:
		## Undo is an instant action — no mode switch, just fire the signal.
		## Aug 2026 — does NOT emit cancel_requested, so pressing Undo while
		## placing (ghost preview active) performs the undo and keeps the
		## placement ghost up.
		_close_submenu()
		undo_requested.emit()
		_undo_flash_t = UNDO_FLASH_TIME
	elif slot == TOOL_WIRE:
		## Wire draw tool — toggle on/off (clicking again deselects)
		_close_submenu()
		cancel_requested.emit()
		_placement_menu = {}
		if active_tool == TOOL_WIRE:
			active_tool = TOOL_CONSTRUCT
			tool_selected.emit(TOOL_CONSTRUCT)
		else:
			active_tool = TOOL_WIRE
			tool_selected.emit(TOOL_WIRE)
	elif slot == TOOL_WATER_PIPE:
		## Water pipe draw tool (July 2026) — same toggle-on/off shape as Wire above.
		_close_submenu()
		cancel_requested.emit()
		_placement_menu = {}
		if active_tool == TOOL_WATER_PIPE:
			active_tool = TOOL_CONSTRUCT
			tool_selected.emit(TOOL_CONSTRUCT)
		else:
			active_tool = TOOL_WATER_PIPE
			tool_selected.emit(TOOL_WATER_PIPE)
	elif slot == TOOL_FARMING:
		## Farming shop (Jul 2026, plan §8.1) — same open/close-submenu shape
		## as TOOL_CONSTRUCT, but browsing FARMING_SHOP_ITEMS instead of
		## CATEGORIES, and picking an item spawns it immediately (no ghost).
		if _submenu_open and _submenu_source == "farming":
			_close_submenu()
		else:
			cancel_requested.emit()
			active_tool = TOOL_FARMING
			tool_selected.emit(TOOL_FARMING)
			_open_submenu("farming")
	else:
		# Any other tool: close submenu, cancel ghost, switch tool
		_close_submenu()
		cancel_requested.emit()
		_placement_menu = {}
		active_tool = slot
		tool_selected.emit(slot)
	_canvas.queue_redraw()

# ─── Controller selection / menu-follow helpers ───────────────────────────────
## Index of the toolbar slot under the cursor, or -1. Mirrors the slot rect
## math in _draw_toolbar() exactly.
func _cursor_over_toolbar_slot() -> int:
	if _workspace != null:
		for i in _workspace._tool_buttons.size():
			if _workspace._tool_buttons[i].get_global_rect().has_point(_mouse_pos):
				return BuildWorkspace.TOOL_ORDER[i]
		return -1
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var count: int  = TOOL_LABELS.size()
	var total_w: float = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float = (vp.x - total_w) * 0.5
	var y: float       = vp.y - SLOT_H - 20.0
	for i in count:
		var rect := Rect2(start_x + i * (SLOT_W + SLOT_GAP), y, SLOT_W, SLOT_H)
		if rect.has_point(_mouse_pos):
			return i
	return -1

## Tabs that open a submenu (Construct / Shop).
func _is_menu_tab(tool: int) -> bool:
	return tool == TOOL_CONSTRUCT or tool == TOOL_FARMING

func _menu_source_for(tool: int) -> String:
	return "farming" if tool == TOOL_FARMING else "construct"

## LB/RB / d-pad selection change (Aug 2026). Cycling ALWAYS selects the
## tool immediately — the old tool is de-selected (ghost/draw cancelled by
## the controller's tool_selected handler) and the new one becomes active,
## no A press needed to switch. Menu tabs follow the selection: scrolling
## onto one re-opens ITS menu when a menu was already open; a closed menu
## stays closed until A / cursor opens it (A on a menu tab opens it — see
## the A branch).
func _change_selected_tool(dir: int) -> void:
	var was_open: bool = _submenu_open
	_sel_tool = (_sel_tool + dir + TOOL_LABELS.size()) % TOOL_LABELS.size()

	if _sel_tool == active_tool:
		_canvas.queue_redraw()
		return

	if not _is_menu_tab(_sel_tool):
		## Non-menu tool (wire/pipe/deconstruct/duplicate/move/undo) —
		## switch to it now, closing any open submenu.
		if _submenu_open:
			_close_submenu()
		_placement_menu = {}
		active_tool = _sel_tool
		tool_selected.emit(_sel_tool)
		_canvas.queue_redraw()
		return

	## Menu tab (Construct / Shop) — make it active, then follow the menu if
	## one was already open.
	cancel_requested.emit()
	active_tool = _sel_tool
	tool_selected.emit(_sel_tool)
	if was_open:
		if _submenu_open:
			_close_submenu()
		_open_submenu(_menu_source_for(_sel_tool))
	_canvas.queue_redraw()

# ─── Submenu ──────────────────────────────────────────────────────────────────
## Returns whichever data source the submenu is currently browsing —
## CATEGORIES (tile ghost-preview placement) or FARMING_SHOP_ITEMS
## (buy → spawn near player). See _submenu_source.
func _current_categories() -> Dictionary:
	if _submenu_source == "farming":
		return FARMING_SHOP_ITEMS
	else:
		return CATEGORIES

func _open_submenu(source: String = "construct") -> void:
	_submenu_source = source
	if source == "construct":
		active_tool = TOOL_CONSTRUCT
	_submenu_open  = true
	_submenu_root.visible = false
	if _workspace != null:
		if source == "farming":
			_workspace.show_shop()
		else:
			_workspace.show_catalog()
	if not InputMode.is_controller():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	## Build the previews lazily the FIRST time a submenu opens (not on
	## build-mode entry) — deferred + staggered so opening the menu never
	## hitches. Text rows show immediately; previews pop in as they build.
	if not _submenu_previews_ready:
		call_deferred("_build_submenu_previews_staggered")
	_canvas.queue_redraw()

func _close_submenu() -> void:
	_submenu_open    = false
	_submenu_level   = "root"
	_active_category = ""
	_submenu_root.visible = false
	if _workspace != null:
		_workspace.hide_menus()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_canvas.queue_redraw()

## Go back ONE level in the submenu (B / controller): from the items level
## back up to the root categories of the same menu, and only from the root
## level fully close the menu (exiting build-mode browsing). Mirrors the
## items-level "‹ Back" row.
func _submenu_back() -> void:
	if _submenu_open and _submenu_level == "items":
		_submenu_level   = "root"
		_active_category = ""
		_submenu_cursor  = 0
		_position_submenu()
		_canvas.queue_redraw()
	else:
		_close_submenu()

## Reopen the submenu that launched the current placement (recorded in
## _placement_menu at construct item pick), at the same level + category so
## the player picks up where they left off. No-op if the placement didn't
## come from a submenu (toolbar tools like wire/pipe).
func _restore_placement_menu() -> void:
	if _placement_menu.is_empty():
		return
	var src: String      = _placement_menu.get("source", "construct")
	var level: String    = _placement_menu.get("level", "root")
	var category: String = _placement_menu.get("category", "")
	_placement_menu = {}
	if _submenu_open:
		_close_submenu()
	_open_submenu(src)
	if level == "items":
		_active_category = category
		_submenu_level   = "items"
		_submenu_cursor  = 0
		_position_submenu()
	_canvas.queue_redraw()

func _submenu_current_rows() -> int:
	## How many rows does the current submenu level show?
	var cats: Dictionary = _current_categories()
	if _submenu_level == "root":
		return cats.size()
	else:
		return cats.get(_active_category, []).size() + 1  ## +1 for Back row

func _position_submenu() -> void:
	## Position directly above whichever toolbar slot opened this submenu —
	## Construct (slot 0) normally, or Farming (slot TOOL_FARMING) when
	## _submenu_source == "farming".
	var anchor_slot: int  = TOOL_FARMING if _submenu_source == "farming" else TOOL_CONSTRUCT
	var vp_size: Vector2  = get_viewport().get_visible_rect().size
	var count: int        = TOOL_LABELS.size()
	var total_w: float    = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float    = (vp_size.x - total_w) * 0.5 + anchor_slot * (SLOT_W + SLOT_GAP)
	var toolbar_y: float  = vp_size.y - SLOT_H - 20.0
	var rows: int         = _submenu_current_rows()
	var sub_h: float      = SUB_ITEM_H * rows + SUB_PAD * 2.0

	_submenu_root.set_position(Vector2(start_x, toolbar_y - sub_h - 8.0))
	_submenu_root.custom_minimum_size = Vector2(SUB_W, sub_h)
	_submenu_root.size = Vector2(SUB_W, sub_h)

func _build_submenu() -> Control:
	var root: Control = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.name = "ConstructSubmenu"

	for i in CONSTRUCT_ITEMS.size():
		var item: Dictionary = CONSTRUCT_ITEMS[i]

		# SubViewport for 3D preview
		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(SUB_VP_SIZE, SUB_VP_SIZE)
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.transparent_bg  = true
		vp.disable_3d      = false
		vp.own_world_3d    = true
		root.add_child(vp)
		GraphicsSettings.register_preview_viewport(vp)

		var cam: Camera3D = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = PREVIEW_CAM_SIZE
		vp.add_child(cam)
		cam.position = Vector3(1.0, 1.2, 1.0)
		# look_at requires the node to be in the tree — defer until next frame
		cam.call_deferred("look_at", Vector3.ZERO, Vector3.UP)

		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(1.0, 2.0, 1.0)
		light.light_energy = 3.0
		light.omni_range = 8.0
		vp.add_child(light)
		PreviewPresentation.configure(vp)

		_sub_viewports.append(vp)
		_sub_vp_textures.append(vp.get_texture())
		_sub_mesh_instances.append(null)

	# Shop item previews (Jul 2026) — same viewport/camera/light setup as
	# above, but the model comes from PREVIEW_SOURCES (instantiating the
	# real item scene/script) instead of the gridmap MeshLibrary, since
	# these aren't placeable tiles.
	var shop_ids: Array = PREVIEW_SOURCES.keys()
	for item_id: int in shop_ids:
		var vp2: SubViewport = SubViewport.new()
		vp2.size = Vector2i(SUB_VP_SIZE, SUB_VP_SIZE)
		vp2.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp2.transparent_bg  = true
		vp2.disable_3d      = false
		vp2.own_world_3d    = true
		root.add_child(vp2)
		GraphicsSettings.register_preview_viewport(vp2)

		var cam2: Camera3D = Camera3D.new()
		cam2.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam2.size = PREVIEW_CAM_SIZE
		vp2.add_child(cam2)
		cam2.position = Vector3(1.0, 1.2, 1.0)
		cam2.call_deferred("look_at", Vector3.ZERO, Vector3.UP)

		var light2: OmniLight3D = OmniLight3D.new()
		light2.position = Vector3(1.0, 2.0, 1.0)
		light2.light_energy = 3.0
		light2.omni_range = 8.0
		vp2.add_child(light2)
		PreviewPresentation.configure(vp2)

		_shop_viewports.append(vp2)
		_shop_vp_textures.append(vp2.get_texture())
		_shop_mesh_instances.append(null)

	# Draw surface for the submenu panel
	var draw_ctrl: Control = Control.new()
	draw_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_ctrl.name = "SubDraw"
	root.add_child(draw_ctrl)
	draw_ctrl.draw.connect(_on_submenu_draw.bind(draw_ctrl))

	return root

func _on_submenu_draw(ctrl: Control) -> void:
	var font: Font = UIKit.font()
	var fs_value: int = UIKit.theme_font_size("UI", "value", 13)
	var fs_label: int = UIKit.theme_font_size("UI", "label", 10)
	var fs_state: int = UIKit.theme_font_size("UI", "state", 11)
	var rows: int  = _submenu_current_rows()
	var sub_h: float = SUB_ITEM_H * rows + SUB_PAD * 2.0
	var rect: Rect2  = Rect2(Vector2.ZERO, Vector2(SUB_W, sub_h))
	var mouse_local: Vector2 = _mouse_pos - _submenu_root.position

	# Panel background + border
	ctrl.draw_rect(rect, SUB_BG, true)
	ctrl.draw_rect(rect, SUB_BORDER, false, 1.5)

	var cats: Dictionary = _current_categories()

	# ── Root level: show category names ───────────────────────────────────────
	if _submenu_level == "root":
		var cat_keys: Array = cats.keys()
		for i: int in cat_keys.size():
			var cat_name: String = cat_keys[i]
			var row_y: float     = SUB_PAD + i * SUB_ITEM_H
			var row_rect: Rect2  = Rect2(0, row_y, SUB_W, SUB_ITEM_H)

			# Hover highlight
			if row_rect.has_point(mouse_local):
				ctrl.draw_rect(row_rect, Color(0.251, 0.443, 0.435, 0.15), true)
			# Controller cursor (Aug 2026) — d-pad selection highlight
			if InputMode.is_controller() and i == _submenu_cursor:
				ctrl.draw_rect(row_rect, Color(0.251, 0.443, 0.435, 0.28), true)

			# Separator
			if i < cat_keys.size() - 1:
				ctrl.draw_line(
					Vector2(SUB_PAD, row_y + SUB_ITEM_H),
					Vector2(SUB_W - SUB_PAD, row_y + SUB_ITEM_H),
					Color(0.3, 0.3, 0.3, 0.6), 1.0, true)

			# Category icon prefix
			const CAT_ICONS: Dictionary = {
				"Structure":     "🧱",
				"Furniture":     "🛏",
				"Lighting":      "💡",
				"Power":         "⚡",
				"Water":         "🚰",
				"Farming":       "🌱",
				"Soil":          "🟫",
				"Seeds":         "🌱",
				"Resources":     "📦",
				"Miscellaneous": "🗃",
			}
			var icon: String = CAT_ICONS.get(cat_name, "•")
			ctrl.draw_string(font, Vector2(SUB_PAD, row_y + 30.0),
				icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT)

			# Category name
			ctrl.draw_string(font, Vector2(SUB_PAD + 28.0, row_y + 29.0),
				cat_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_value, COLOR_TEXT)

			# Item count badge
			var n: int = cats[cat_name].size()
			var badge: String = "%d item%s" % [n, "s" if n != 1 else ""]
			ctrl.draw_string(font, Vector2(SUB_PAD + 28.0, row_y + 47.0),
				badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, Color(0.55, 0.55, 0.55, 0.9))

			# Chevron → right edge
			ctrl.draw_string(font, Vector2(SUB_W - 18.0, row_y + 32.0),
				"›", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PRICE_COLOR)

	# ── Items level: show Back row + items in active category ─────────────────
	else:
		var cat_items: Array = cats.get(_active_category, [])

		# Row 0: Back button
		var back_rect: Rect2 = Rect2(0, SUB_PAD, SUB_W, SUB_ITEM_H)
		if back_rect.has_point(mouse_local):
			ctrl.draw_rect(back_rect, Color(0.251, 0.443, 0.435, 0.12), true)
		## Controller cursor (Aug 2026) on the Back row (submenu cursor == 0).
		if InputMode.is_controller() and _submenu_cursor == 0:
			ctrl.draw_rect(back_rect, Color(0.251, 0.443, 0.435, 0.28), true)
		ctrl.draw_string(font, Vector2(SUB_PAD, SUB_PAD + 32.0),
			"‹ Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.251, 0.443, 0.435, 1.0))
		ctrl.draw_string(font, Vector2(SUB_PAD, SUB_PAD + 48.0),
			_active_category, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, Color(0.251, 0.443, 0.435, 0.85))
		# Separator under back
		ctrl.draw_line(
			Vector2(SUB_PAD, SUB_PAD + SUB_ITEM_H),
			Vector2(SUB_W - SUB_PAD, SUB_PAD + SUB_ITEM_H),
			Color(0.251, 0.443, 0.435, 0.35), 1.0, true)

		# Items
		for i: int in cat_items.size():
			var item: Dictionary = cat_items[i]
			var row_y: float    = SUB_PAD + (i + 1) * SUB_ITEM_H   ## +1 for Back row
			var row_rect: Rect2 = Rect2(0, row_y, SUB_W, SUB_ITEM_H)

			# Hover highlight
			if row_rect.has_point(mouse_local):
				ctrl.draw_rect(row_rect, Color(0.251, 0.443, 0.435, 0.15), true)
			# Controller cursor (Aug 2026) — item rows are cursor 1..n.
			if InputMode.is_controller() and _submenu_cursor == i + 1:
				ctrl.draw_rect(row_rect, Color(0.251, 0.443, 0.435, 0.28), true)

			# Separator (not after last)
			if i < cat_items.size() - 1:
				ctrl.draw_line(
					Vector2(SUB_PAD, row_y + SUB_ITEM_H),
					Vector2(SUB_W - SUB_PAD, row_y + SUB_ITEM_H),
					Color(0.3, 0.3, 0.3, 0.6), 1.0, true)

			# 3D preview viewport — construct items look up their flat index in
			# CONSTRUCT_ITEMS; shop items (Soil/Seeds/Fertilizer/Resources/
			# Miscellaneous) look up their index in PREVIEW_SOURCES' key order
			# instead, since "tile_id" there is really an item_id that collides
			# numerically with real CONSTRUCT_ITEMS tile_ids (Wall/Pillar/
			# Shelving) — keeping these two lookups separate avoids a farming/
			# shop row showing the wrong preview.
			var vp_rect: Rect2 = Rect2(SUB_PAD,
				row_y + (SUB_ITEM_H - SUB_VP_SIZE) * 0.5,
				SUB_VP_SIZE, SUB_VP_SIZE)
			if _submenu_source == "construct":
				var flat_idx: int = -1
				for fi: int in CONSTRUCT_ITEMS.size():
					if CONSTRUCT_ITEMS[fi]["tile_id"] == item["tile_id"]:
						flat_idx = fi
						break
				if flat_idx >= 0 and flat_idx < _sub_vp_textures.size() \
						and _sub_vp_textures[flat_idx] != null:
					ctrl.draw_texture_rect(_sub_vp_textures[flat_idx], vp_rect, false)
			else:
				var shop_ids: Array = PREVIEW_SOURCES.keys()
				var shop_idx: int = shop_ids.find(item["tile_id"])
				if shop_idx >= 0 and shop_idx < _shop_vp_textures.size() \
						and _shop_vp_textures[shop_idx] != null:
					ctrl.draw_texture_rect(_shop_vp_textures[shop_idx], vp_rect, false)

			# Name + price
			var name_x: float = SUB_PAD + SUB_VP_SIZE + SUB_GAP
			ctrl.draw_string(font, Vector2(name_x, row_y + 26.0),
				item["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs_value, COLOR_TEXT)
			ctrl.draw_string(font, Vector2(name_x, row_y + 44.0),
				"$%d" % item["price"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs_state, PRICE_COLOR)

## Returns the row index (0-based) within the current submenu level, or -1.
func _get_submenu_item_at(pos: Vector2) -> int:
	if not _submenu_open or not _submenu_root.visible:
		return -1
	var local: Vector2 = pos - _submenu_root.position
	var rows: int      = _submenu_current_rows()
	var sub_h: float   = SUB_ITEM_H * rows + SUB_PAD * 2.0
	if local.x < 0 or local.x > SUB_W or local.y < 0 or local.y > sub_h:
		return -1
	var row: int = int((local.y - SUB_PAD) / SUB_ITEM_H)
	if row >= 0 and row < rows:
		return row
	return -1

## Called when the player clicks a resolved row index inside the open
## submenu (see _get_submenu_item_at()). Row meaning depends on level:
##   - "root" level: row = index into _current_categories().keys() → drill
##     into that category's item list.
##   - "items" level: row 0 = "‹ Back" → return to root. row >= 1 = index
##     (row - 1) into the active category's item array → pick that item.
func _on_submenu_item_selected(item: int) -> void:
	var cats: Dictionary = _current_categories()

	if _submenu_level == "root":
		var cat_keys: Array = cats.keys()
		if item < 0 or item >= cat_keys.size():
			return
		_active_category = cat_keys[item]
		_submenu_level   = "items"
		_submenu_cursor  = 0   ## start at the first item
		_position_submenu()   ## row count changed — resize/reposition panel
		_canvas.queue_redraw()
		return

	# ── "items" level ──
	if item == 0:
		## Back row
		_submenu_level   = "root"
		_active_category = ""
		_submenu_cursor  = 0
		_position_submenu()
		_canvas.queue_redraw()
		return

	var cat_items: Array = cats.get(_active_category, [])
	var idx_in_cat: int  = item - 1   ## row 0 is Back, so shift by one
	if idx_in_cat < 0 or idx_in_cat >= cat_items.size():
		return

	var tile_id: int = cat_items[idx_in_cat]["tile_id"]

	if _submenu_source == "construct":
		## Placeable tile — emit for BuildModeController to start a ghost,
		## then close the submenu (picking a tile always closes it).
		## Record the submenu so B can restore it after cancelling the
		## placement (see _restore_placement_menu).
		_placement_menu = {
			"source": _submenu_source,
			"level": _submenu_level,
			"category": _active_category,
		}
		construct_item_chosen.emit(tile_id)
		_close_submenu()
	else:
		## Farming/shop item — emit to spawn/buy immediately, but per the
		## A6 fix (see HANDOVER.md) the shop submenu stays open after a
		## purchase so the player can buy multiple items in a row.
		farming_item_chosen.emit(tile_id)
		_canvas.queue_redraw()

## Builds every construct + shop preview ONCE, staggered a few per frame, so
## entering build mode never hitches on a synchronous ~55-item build (the
## former _refresh_submenu_previews — the build-mode entry stutter). Static
## previews are set to render-once (UPDATE_ONCE + update_worlds); only the
## hovered one spins live (see _update_preview_hover_spin).
func _build_submenu_previews_staggered() -> void:
	if _submenu_previews_ready:
		return
	if gridmap == null or gridmap.mesh_library == null:
		return
	_submenu_previews_ready = true
	## Construct previews are cheap MeshLibrary fetches — several per frame.
	## Shop previews instantiate real item scenes (.glb / scripts) — heavier,
	## so one per frame.
	const CONSTRUCT_CHUNK: int = 4
	for i in CONSTRUCT_ITEMS.size():
		_build_construct_preview(i)
		if i % CONSTRUCT_CHUNK == CONSTRUCT_CHUNK - 1:
			await get_tree().process_frame
	for i in PREVIEW_SOURCES.size():
		_build_shop_preview(i)
		await get_tree().process_frame

## Sets a preview viewport's render mode: UPDATE_WHEN_VISIBLE while it's the
## hovered (spinning) preview, UPDATE_ONCE otherwise so static previews cost
## one render instead of one per frame. UPDATE_ONCE renders its content a
## single time on the next frame (even while the submenu is hidden) and keeps
## that texture, which the submenu draws via ViewportTexture.
func _set_preview_viewport_live(vp: SubViewport, live: bool) -> void:
	if vp == null:
		return
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if live else SubViewport.UPDATE_ONCE

## Builds one construct-item preview (MeshLibrary mesh, or a full-fidelity
## procedural scene for non-tile items). Called once by the staggered build.
func _build_construct_preview(i: int) -> void:
	if i >= _sub_viewports.size():
		return
	if gridmap == null or gridmap.mesh_library == null:
		return
	var tile_id: int  = CONSTRUCT_ITEMS[i]["tile_id"]
	var vp: SubViewport = _sub_viewports[i]

	# Remove any old pivot/mesh
	for child in vp.get_children():
		if child is Node3D and child is not Camera3D and child is not OmniLight3D:
			child.queue_free()

	var lib: MeshLibrary = gridmap.mesh_library

	## MeshLibrary item — existing single-mesh path, unchanged.
	if lib.get_item_list().has(tile_id):
		var mesh: Mesh = lib.get_item_mesh(tile_id)
		if mesh != null:
			## Pivot fix (Jul 2026) — wrap the mesh in a fixed pivot so it
			## spins around its true visual center. _sub_mesh_instances stores
			## the pivot (see _update_preview_hover_spin).
			var pivot: Node3D = Node3D.new()
			pivot.rotation_degrees = PREVIEW_ROTATION_DEFAULT
			vp.add_child(pivot)

			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = mesh
			pivot.add_child(mi)
			_sub_mesh_instances[i] = pivot

			# Center mesh within the pivot (the pivot itself never moves)
			if mi.mesh != null:
				var aabb: AABB = mi.mesh.get_aabb()
				mi.position = -aabb.get_center()
				pivot.scale = Vector3.ONE * _preview_normalize_scale(aabb)
			_set_preview_viewport_live(vp, false)
			return

	## No MeshLibrary entry — try a full-fidelity procedural preview
	## instead of leaving this slot blank. See _build_procedural_preview_instance().
	var inst: Node3D = _build_procedural_preview_instance(tile_id)
	if inst == null:
		_set_preview_viewport_live(vp, false)
		return   ## no source registered for this tile — stays text-only
	inst.set_process(false)
	inst.set_physics_process(false)

	var pivot2: Node3D = Node3D.new()
	pivot2.rotation_degrees = PREVIEW_ROTATION_DEFAULT
	vp.add_child(pivot2)
	pivot2.add_child(inst)
	## Safety net: wipe any groups this instance's _ready() still joined
	## (construct classes lacking the _is_preview_only guard). See
	## GhostModelBuilder.strip_groups().
	GhostModelBuilder.strip_groups(inst)
	_sub_mesh_instances[i] = pivot2

	## Combined AABB, correctly accounting for each mesh's own offset.
	var aabb_result: Dictionary = _combined_local_aabb(inst)
	if aabb_result["found_any"]:
		var combined: AABB = aabb_result["aabb"]
		inst.position = -combined.get_center()
		pivot2.scale = Vector3.ONE * _preview_normalize_scale(combined)
	_set_preview_viewport_live(vp, false)

# ─── Cancel button ────────────────────────────────────────────────────────────
## the whole node tree renders, so imported models (e.g. FuelCan's .glb)
## work the same as procedurally-built meshes (e.g. BagOfSoilItem). The
## instance's own game logic is disabled (set_process/set_physics_process
## false) since it's a display-only stand-in, never actually held or used.
## Builds one shop-item preview from its PREVIEW_SOURCES entry (instantiating
## the item's own scene/script). Preview-only guard + group strip keep these
## out of the live world. Called once by the staggered build.
func _build_shop_preview(i: int) -> void:
	if i >= _shop_viewports.size():
		return
	var shop_ids: Array = PREVIEW_SOURCES.keys()
	if i >= shop_ids.size():
		return
	var info: Dictionary = PREVIEW_SOURCES[shop_ids[i]]
	var vp: SubViewport = _shop_viewports[i]
	for child in vp.get_children():
		if child is Node3D and child is not Camera3D and child is not OmniLight3D:
			child.queue_free()

	var inst: Node3D = null
	if bool(info.get("is_script", false)):
		var script: GDScript = load(String(info["scene"])) as GDScript
		if script == null:
			_set_preview_viewport_live(vp, false)
			return
		inst = script.new()
		## Aug 2026 fix — must be set BEFORE the node enters the tree, so
		## SeedItem.gd's own _ready() builds its placeholder mesh with the
		## correct species color instead of the "tomato" default.
		if info.has("seed_type") and "seed_type" in inst:
			inst.set("seed_type", info["seed_type"])
		if int(shop_ids[i]) == 15 and "tier" in inst:
			inst.set("tier", "pro")
	else:
		var packed: PackedScene = load(String(info["scene"])) as PackedScene
		if packed == null:
			_set_preview_viewport_live(vp, false)
			return
		inst = packed.instantiate() as Node3D
	if inst == null:
		_set_preview_viewport_live(vp, false)
		return

	if inst is RigidBody3D:
		var rb: RigidBody3D = inst as RigidBody3D
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	inst.set_process(false)
	inst.set_physics_process(false)

	## Preview-only guard — MUST be set before add_child() so _ready() sees
	## it (see PickupableItem._is_preview_only). Without it, every shop
	## preview's real _ready() joined world groups ("pickup", "interactable",
	## ...) and tree-wide NPC/interaction group-scans treated them as real
	## items buried at ~world origin.
	inst.set("_is_preview_only", true)

	## Pivot fix (Jul 2026) — same reasoning as the construct-item builder:
	## rotate a fixed pivot wrapping the instance, not the instance itself.
	var pivot: Node3D = Node3D.new()
	pivot.rotation_degrees = PREVIEW_ROTATION_DEFAULT
	vp.add_child(pivot)
	pivot.add_child(inst)
	## Safety net: wipe any groups this instance's _ready() still joined
	## (and any its children joined, e.g. WallLight's priority proxy).
	## See GhostModelBuilder.strip_groups() — group membership is
	## tree-wide, even though these instances are world-isolated.
	GhostModelBuilder.strip_groups(inst)
	_shop_mesh_instances[i] = pivot

	# Combined AABB, correctly accounting for each mesh's own offset.
	var aabb_result: Dictionary = _combined_local_aabb(inst)
	if aabb_result["found_any"]:
		var combined: AABB = aabb_result["aabb"]
		inst.position = -combined.get_center()
		pivot.scale = Vector3.ONE * _preview_normalize_scale(combined)
	_set_preview_viewport_live(vp, false)

# ─── Cancel button ────────────────────────────────────────────────────────────
func _build_cancel_button() -> Control:
	## Red box with X — lives at the same top-left as the banner.
	## Repositioned every frame in _process so it's always flush-right of the banner.
	var btn: Control = Control.new()
	btn.custom_minimum_size = Vector2(36.0, 36.0)
	btn.size = Vector2(36.0, 36.0)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.name = "CancelBtn"
	btn.draw.connect(_on_cancel_draw.bind(btn))
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_top  = 12.0
	btn.offset_left = 0.0
	return btn

func _reposition_cancel_btn() -> void:
	## Called every process tick — keeps X flush-right of the banner, vertically centred.
	if _banner == null or _cancel_btn == null:
		return
	var bx: float = _banner.offset_left + _banner.size.x + 4.0
	var by: float = _banner.offset_top  + (_banner.size.y - _cancel_btn.size.y) * 0.5
	_cancel_btn.offset_left = bx
	_cancel_btn.offset_top  = by

## Item preview hover animation (Jul 2026). Only meaningful while the
## submenu is open and on the Items level (root-level category rows have
## no preview). Spins whichever row's preview is "selected" — the row under
## the mouse in mouse/keyboard mode, the d-pad-selected row (Aug 2026) in
## controller mode. Every other preview snaps straight back to
## PREVIEW_ROTATION_DEFAULT with no easing, per spec.
func _update_preview_hover_spin(delta: float) -> void:
	var new_hover: int = -1
	var new_is_shop: bool = false
	if _submenu_open and _submenu_level == "items":
		var row: int = _submenu_cursor if InputMode.is_controller() \
			else _get_submenu_item_at(_mouse_pos)
		if row >= 1:   ## row 0 is the Back button, never a preview
			var cats: Dictionary = _current_categories()
			var cat_items: Array = cats.get(_active_category, [])
			var idx_in_cat: int = row - 1
			if idx_in_cat >= 0 and idx_in_cat < cat_items.size():
				var tid: int = cat_items[idx_in_cat]["tile_id"]
				if _submenu_source == "construct":
					for fi: int in CONSTRUCT_ITEMS.size():
						if CONSTRUCT_ITEMS[fi]["tile_id"] == tid:
							new_hover = fi
							break
				else:
					new_hover = PREVIEW_SOURCES.keys().find(tid)
					new_is_shop = true

	if new_hover != _hovered_preview_index or new_is_shop != _hovered_preview_is_shop:
		# Snap the PREVIOUSLY hovered preview back to its default pose and drop
		# it to render-once (it's no longer spinning).
		var old_vp: SubViewport = _get_hover_viewport(_hovered_preview_is_shop, _hovered_preview_index)
		if old_vp != null:
			_set_preview_viewport_live(old_vp, false)
		var old_mi: Node3D = _get_hover_pivot(_hovered_preview_is_shop, _hovered_preview_index)
		if old_mi != null and is_instance_valid(old_mi):
			old_mi.rotation_degrees = PREVIEW_ROTATION_DEFAULT
		_hovered_preview_index = new_hover
		_hovered_preview_is_shop = new_is_shop
		# The newly hovered preview spins live.
		var new_vp: SubViewport = _get_hover_viewport(new_is_shop, new_hover)
		if new_vp != null:
			_set_preview_viewport_live(new_vp, true)

	var mi: Node3D = _get_hover_pivot(_hovered_preview_is_shop, _hovered_preview_index)
	if mi != null and is_instance_valid(mi):
		mi.rotation_degrees.y += PREVIEW_HOVER_SPIN_DEG_PER_SEC * delta

func _get_hover_viewport(is_shop: bool, index: int) -> SubViewport:
	if index < 0:
		return null
	if is_shop:
		return _shop_viewports[index] if index < _shop_viewports.size() else null
	return _sub_viewports[index] if index < _sub_viewports.size() else null

func _get_hover_pivot(is_shop: bool, index: int) -> Node3D:
	if index < 0:
		return null
	if is_shop:
		return _shop_mesh_instances[index] if index < _shop_mesh_instances.size() else null
	return _sub_mesh_instances[index] if index < _sub_mesh_instances.size() else null

func _on_cancel_draw(btn: Control) -> void:
	var r: Rect2  = Rect2(Vector2.ZERO, btn.size)
	var cr: float = 5.0
	var bg: Color = Color(0.55, 0.08, 0.08, 0.88) if not _cancel_hovered \
		else Color(0.80, 0.12, 0.12, 0.95)
	var border: Color = Color(0.90, 0.25, 0.25, 0.80)

	# Rounded fill + border (border now follows the corners — was square)
	UIKit.draw_rounded_rect(btn, r, bg, border, 1.5, cr)

	# X mark
	var pad: float = 9.0
	var xc: Color  = Color(1.0, 0.85, 0.85, 1.0)
	btn.draw_line(Vector2(pad, pad), Vector2(r.size.x - pad, r.size.y - pad), xc, 2.5, true)
	btn.draw_line(Vector2(r.size.x - pad, pad), Vector2(pad, r.size.y - pad), xc, 2.5, true)

# ─── Main canvas draw (border + toolbar) ──────────────────────────────────────
func _on_canvas_draw() -> void:
	_draw_border()
	_draw_deconstruct_overlay()
	_draw_dupe_rotate_overlay()
	_draw_rock_chunk_overlay()
	## Toolbar and menus are real Controls in BuildWorkspace.
	# Trigger submenu redraw
	if _submenu_open and _submenu_root.visible:
		var draw_ctrl: Control = _submenu_root.get_node_or_null("SubDraw")
		if draw_ctrl != null:
			draw_ctrl.queue_redraw()
	# Trigger cancel btn redraw
	if _cancel_btn != null and _cancel_btn.visible:
		_cancel_btn.queue_redraw()

## Draws a red semi-transparent tile overlay when the Deconstruct tool is active
## and the cursor is hovering over a tile. Uses camera projection to find the
## screen-space corners of the 1×1 grid cell.
func _draw_deconstruct_overlay() -> void:
	if active_tool != TOOL_DECONSTRUCT:
		return
	if camera == null:
		return
	# Sentinel check
	if hovered_deconstruct_cell.x < -999.0:
		return

	# The grid cell is 1 unit wide. Sample 4 ground-level corners.
	# We offset slightly above ground (y + 0.05) so the rect isn't z-fighting.
	var half: float  = 0.5
	var y_off: float = 0.05
	var base: Vector3 = hovered_deconstruct_cell + Vector3(0.0, y_off, 0.0)
	var corners_3d: Array[Vector3] = [
		base + Vector3(-half, 0.0, -half),
		base + Vector3( half, 0.0, -half),
		base + Vector3( half, 0.0,  half),
		base + Vector3(-half, 0.0,  half),
	]

	# Project to screen
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector3 in corners_3d:
		pts.append(camera.unproject_position(c))

	# Fill — red, semi-transparent
	_canvas.draw_colored_polygon(pts, Color(0.85, 0.12, 0.08, 0.35))
	# Border — brighter red outline
	var border_col: Color = Color(1.0, 0.25, 0.18, 0.90)
	for i: int in pts.size():
		_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], border_col, 2.0, true)

## Draws a light-blue semi-transparent tile overlay when Duplicate or Move tool
## is active (phase 0 hover) and the cursor is hovering over a placed object.
func _draw_dupe_rotate_overlay() -> void:
	if active_tool != TOOL_DUPLICATE and active_tool != TOOL_MOVE:
		return
	if camera == null:
		return
	if hovered_dupe_rotate_pos.x < -999.0:
		return

	var half: float  = 0.5
	var y_off: float = 0.05
	var base: Vector3 = hovered_dupe_rotate_pos + Vector3(0.0, y_off, 0.0)
	var corners_3d: Array[Vector3] = [
		base + Vector3(-half, 0.0, -half),
		base + Vector3( half, 0.0, -half),
		base + Vector3( half, 0.0,  half),
		base + Vector3(-half, 0.0,  half),
	]

	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector3 in corners_3d:
		pts.append(camera.unproject_position(c))

	# Fill — light blue, semi-transparent
	_canvas.draw_colored_polygon(pts, Color(0.20, 0.60, 1.0, 0.30))
	# Border — brighter blue outline
	var border_col: Color = Color(0.35, 0.75, 1.0, 0.90)
	for i: int in pts.size():
		_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], border_col, 2.0, true)

## Draws a red semi-transparent 4×4 footprint overlay when the Deconstruct tool
## is hovering over a rock chunk. Includes a $2500 cost label above the chunk.
func _draw_rock_chunk_overlay() -> void:
	if active_tool != TOOL_DECONSTRUCT:
		return
	if camera == null:
		return
	# Sentinel check — x < -999 means nothing hovered
	if hovered_rock_chunk_world_pos.x < -999.0:
		return

	# 4×4 chunk footprint (half = 2.0 → 4 units wide/deep)
	# hovered_rock_chunk_world_pos.y = BLOCK_Y (block centre).
	# Raise quad to the top face: BLOCK_HEIGHT/2 + small epsilon above surface.
	# BLOCK_HEIGHT = 2.25 → half = 1.125 → y_off ≈ 1.175 sits just above top face.
	var half: float  = 2.0
	var y_off: float = 1.175
	var base: Vector3 = hovered_rock_chunk_world_pos + Vector3(0.0, y_off, 0.0)
	var corners_3d: Array[Vector3] = [
		base + Vector3(-half, 0.0, -half),
		base + Vector3( half, 0.0, -half),
		base + Vector3( half, 0.0,  half),
		base + Vector3(-half, 0.0,  half),
	]

	# Project corners to screen space
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector3 in corners_3d:
		pts.append(camera.unproject_position(c))

	# Fill — red, semi-transparent
	_canvas.draw_colored_polygon(pts, Color(0.85, 0.12, 0.08, 0.35))
	# Border — brighter red outline, slightly thicker than deconstruct overlay
	var border_col: Color = Color(1.0, 0.25, 0.18, 0.90)
	for i: int in pts.size():
		_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], border_col, 2.5, true)

	# Cost label — centered above the chunk's world position
	# Project a point ~1 unit above the chunk center for label anchor
	var label_world: Vector3 = hovered_rock_chunk_world_pos + Vector3(0.0, 1.0, 0.0)
	var label_screen: Vector2 = camera.unproject_position(label_world)
	var cost_str: String = "$1,500"
	## Iosevka like the rest of Build Mode — was ThemeDB.fallback_font
	## (Godot's generic default), a small but visible typeface mismatch.
	var font: Font = UIKit.font()
	var font_size: int = 14
	var text_size: Vector2 = font.get_string_size(cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos: Vector2  = label_screen - Vector2(text_size.x * 0.5, 0.0)
	# Shadow pass for readability
	_canvas.draw_string(font, text_pos + Vector2(1.0, 1.0), cost_str, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, Color(0.0, 0.0, 0.0, 0.75))
	# Main label — same red tint as border
	_canvas.draw_string(font, text_pos, cost_str, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, Color(1.0, 0.45, 0.35, 1.0))

## Draws a centered Yes/No confirmation panel for rock dig.
## The rock-dig confirm dialog is now the shared ConfirmDialogUI (see
## open_dig_confirm) — the old hand-rolled _draw_dig_confirm() +
## _dig_confirm_yes_rect/_dig_confirm_no_rect hit-testing is gone.

func _draw_border() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var pulse: float     = 0.45 + sin(_pulse_t) * 0.45
	var col: Color       = Color(ACCENT.r, ACCENT.g, ACCENT.b, pulse)
	var ins: float       = BORDER_INSET
	var r: Rect2         = Rect2(ins, ins, vp_size.x - ins * 2.0, vp_size.y - ins * 2.0)
	var cr: float        = 12.0

	for pass_i in 3:
		var w: float = BORDER_W - pass_i * 0.8
		var c: Color = Color(col.r, col.g, col.b, col.a * (1.0 - pass_i * 0.25))
		_canvas.draw_line(r.position + Vector2(cr, 0),          r.position + Vector2(r.size.x-cr, 0),         c, w, true)
		_canvas.draw_line(r.position + Vector2(cr, r.size.y),   r.position + Vector2(r.size.x-cr, r.size.y),  c, w, true)
		_canvas.draw_line(r.position + Vector2(0, cr),          r.position + Vector2(0, r.size.y-cr),         c, w, true)
		_canvas.draw_line(r.position + Vector2(r.size.x, cr),   r.position + Vector2(r.size.x, r.size.y-cr),  c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(cr, cr), cr, PI, PI*1.5), c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(r.size.x-cr, cr), cr, PI*1.5, TAU), c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(cr, r.size.y-cr), cr, PI*0.5, PI), c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(r.size.x-cr, r.size.y-cr), cr, 0.0, PI*0.5), c, w, true)

func _draw_toolbar() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var font: Font       = UIKit.font()
	var fs_small: int    = UIKit.theme_font_size("UI", "small", 9)
	var count: int       = TOOL_LABELS.size()
	var total_w: float   = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float   = (vp_size.x - total_w) * 0.5
	var y: float         = vp_size.y - SLOT_H - 20.0

	for i in count:
		var x: float    = start_x + i * (SLOT_W + SLOT_GAP)
		var rect: Rect2 = Rect2(x, y, SLOT_W, SLOT_H)

		# Undo slot: flash green briefly on click, then return to neutral
		var is_undo: bool   = (i == TOOL_UNDO)
		var undo_flash: bool = is_undo and _undo_flash_t > 0.0

		var slot_bg: Color  = COLOR_BG
		if undo_flash:
			var frac: float = _undo_flash_t / UNDO_FLASH_TIME
			slot_bg = COLOR_BG.lerp(Color(0.10, 0.28, 0.27, 0.88), frac)

		var is_active: bool = (not is_undo) and \
			((i == active_tool) or (i == TOOL_CONSTRUCT and _submenu_open and _submenu_source == "construct") \
				or (i == TOOL_FARMING and _submenu_open and _submenu_source == "farming"))
		var bcol: Color = COLOR_SEL if (is_active or undo_flash) else COLOR_BORDER
		UIKit.draw_rounded_rect(_canvas, rect, slot_bg, bcol, 2.0, SLOT_CORNER)

		## Controller (Aug 2026): white outline on the d-pad selected tab
		## (distinct from the active tool's teal outline), and LB/RB cycle
		## badges on the first (Construct) / last (Shop) tabs.
		if InputMode.is_controller():
			if i == _sel_tool:
				UIKit.draw_rounded_rect(_canvas, rect, Color(0, 0, 0, 0), Color.WHITE, 3.0, SLOT_CORNER)
			if i == 0:
				_canvas.draw_texture_rect(XBOX_LB_ICON, Rect2(x + 2.0, y + 2.0, TOOL_BADGE_SIZE, TOOL_BADGE_SIZE), false)
			elif i == TOOL_LABELS.size() - 1:
				_canvas.draw_texture_rect(XBOX_RB_ICON, Rect2(x + SLOT_W - TOOL_BADGE_SIZE - 2.0, y + 2.0, TOOL_BADGE_SIZE, TOOL_BADGE_SIZE), false)

		# Icon
		var icon: String    = TOOL_ICONS[i]
		var icsz: Vector2   = font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		_canvas.draw_string(font, Vector2(x + SLOT_W*0.5 - icsz.x*0.5, y + 24.0),
			icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

		# Label
		var lbl: String     = TOOL_LABELS[i]
		var lsz: Vector2    = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_small)
		_canvas.draw_string(font, Vector2(x + SLOT_W*0.5 - lsz.x*0.5, y + SLOT_H - 8.0),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_small, COLOR_TEXT)

# ─── Helpers ──────────────────────────────────────────────────────────────────
func _get_toolbar_slot_at(pos: Vector2) -> int:
	if _workspace != null:
		for i in _workspace._tool_buttons.size():
			if _workspace._tool_buttons[i].get_global_rect().has_point(pos):
				return BuildWorkspace.TOOL_ORDER[i]
		return -1
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var count: int       = TOOL_LABELS.size()
	var total_w: float   = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float   = (vp_size.x - total_w) * 0.5
	var y: float         = vp_size.y - SLOT_H - 20.0
	for i in count:
		var x: float = start_x + i * (SLOT_W + SLOT_GAP)
		if Rect2(x, y, SLOT_W, SLOT_H).has_point(pos):
			return i
	return -1

func _arc(center: Vector2, radius: float, from_a: float, to_a: float) -> Array:
	const STEPS: int = 10
	var pts: Array = []
	for s in range(STEPS + 1):
		var a: float = from_a + (to_a - from_a) * float(s) / STEPS
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

func _make_stylebox(bg: Color, border: Color, corners: Vector4i) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.corner_radius_top_left     = corners.x
	s.corner_radius_top_right    = corners.y
	s.corner_radius_bottom_right = corners.z
	s.corner_radius_bottom_left  = corners.w
	s.content_margin_left   = 14.0
	s.content_margin_right  = 14.0
	s.content_margin_top    = 6.0
	s.content_margin_bottom = 6.0
	return s
