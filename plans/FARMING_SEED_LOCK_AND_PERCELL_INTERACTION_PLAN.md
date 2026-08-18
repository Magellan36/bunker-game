# Plan: Per-Cell Seed Lock + Per-Cell Farming Interaction

**Owner of this plan:** Farming/Gardening Claude instance.
**Scope:** `scripts/world/farming/FarmingTray.gd`, `scripts/world/items/BagOfSoilItem.gd`,
`scripts/world/items/SeedItem.gd`, `scripts/world/items/FarmProduceItem.gd`,
`scripts/ui/farming/FarmingTrayUI.gd`, `docs/systems/farming/README.md`.

**Cross-thread flag:** This plan adds a read-only per-cell data API
(`get_cell_seed_lock()`) and new indexed cell mutators
(`fill_soil_at_cell()`, `plant_seed_at_cell()`) that the **NPC thread** will
consume in a future pass to build `FILL_SOIL`/`PLANT_SEED` job types. **Do
not touch any `scripts/npc/*` file in this plan** — a separate document
(`NPC_AGENT_HANDOVER_seed_lock_and_percell_farming.md`) has been handed to
that thread directly. This plan is self-contained and does not depend on
any NPC-side code existing yet.

**Explicitly NOT in scope this pass:** `FertilizerItem.gd` /
`FarmingTray.fertilize_first_open_cell()` are left untouched. They use the
same tray-wide "first open cell" pattern being removed from soil/seed/
harvest in this plan, so they are now inconsistent with the rest of the
tray's interaction model — flagged here for a future pass, not silently
fixed or silently ignored.

---

## 0. Summary of the two features

**Feature A — Per-cell seed lock.** Each tray cell gets a persistent
`String` field, `""` (Any/unrestricted) or a `PlantDatabase` plant-type key
(e.g. `"onion"`). Set via a new dropdown in `FarmingTrayUI` — one dropdown
per cell, listing only seed types the player currently has anywhere in the
bunker (inventory, shelved, or dropped — i.e. every `SeedItem` in the
`"inventory_item"` group with charges > 0), plus an always-present "Any"
option. **This lock only steers the NPC's future auto-planting job — it
never blocks the player's own manual planting.** The dropdown's label
communicates this directly.

**Feature B — Per-cell interaction (both cells of a double tray behave as
two independent 1×1 units).** Today, soil-fill/plant/harvest all operate
on "the tray's first open cell" — a double tray gets treated as one
unit with two backing slots. This plan replaces that with **nearest-cell
targeting**: whichever cell is spatially closest to the acting entity
(player's held-item position, or a future NPC's position) is the one
cell that action affects, one cell per action. This applies to soil
filling, seed planting (including produce replanting), and harvesting —
for both the player and (once built) NPCs. The **only** part of the tray
that still treats both cells as one unit is the `FarmingTrayUI` "Tray
Info" panel, which continues to show both cells' status together (now
with its own per-cell dropdown added).

---

## 1. `scripts/world/farming/FarmingTray.gd`

### 1.1 — New per-cell seed-lock array

Find:

```gdscript
## B1 — fertilizer can be applied to empty (unplanted) soil. "Prepped"
## means fertilizer has been applied to empty soil; when a seed is later
## planted there, it starts already fertilized.
var cell_prepped_fertilizer: Array[String] = []
```

Replace with:

```gdscript
## B1 — fertilizer can be applied to empty (unplanted) soil. "Prepped"
## means fertilizer has been applied to empty soil; when a seed is later
## planted there, it starts already fertilized.
var cell_prepped_fertilizer: Array[String] = []

## Seed Lock plan (Aug 2026) — per-cell NPC auto-plant restriction. ""
## means "Any" (unrestricted, NPC will plant whatever the JobBoard/NPC
## logic picks). A non-empty value is a PlantDatabase plant_type key
## (e.g. "onion") — the ONLY type the NPC's future auto-planting job is
## allowed to plant into this specific cell. Deliberately does NOT gate
## the player's own manual SeedItem/FarmProduceItem on_use() — the player
## can always plant by hand regardless of this value (confirmed with
## Brannon). In-session only for now — not wired into save/load, matching
## the tray's existing soil_filled/planted_type gap (see "Known gaps" in
## docs/systems/farming/README.md).
var cell_seed_lock: Array[String] = []
```

Find:

```gdscript
	cell_prepped_fertilizer.resize(cell_count)
	_soil_mesh_instances.resize(cell_count)
	for i: int in range(cell_count):
		soil_filled[i]  = false
		planted_type[i] = ""
		plant_refs[i]   = null
		cell_prepped_fertilizer[i] = ""
		_soil_mesh_instances[i] = null
```

Replace with:

```gdscript
	cell_prepped_fertilizer.resize(cell_count)
	cell_seed_lock.resize(cell_count)
	_soil_mesh_instances.resize(cell_count)
	for i: int in range(cell_count):
		soil_filled[i]  = false
		planted_type[i] = ""
		plant_refs[i]   = null
		cell_prepped_fertilizer[i] = ""
		cell_seed_lock[i] = ""
		_soil_mesh_instances[i] = null
```

### 1.2 — Seed-lock get/set (add as a new section — place directly after the
`clear_cell()` function and before `func _cell_local_x`)

Find:

```gdscript
func clear_cell(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	planted_type[cell_index] = ""
	plant_refs[cell_index]   = null
	cell_prepped_fertilizer[cell_index] = ""

func _cell_local_x(cell_index: int) -> float:
```

Replace with:

```gdscript
func clear_cell(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	planted_type[cell_index] = ""
	plant_refs[cell_index]   = null
	cell_prepped_fertilizer[cell_index] = ""
	## Seed Lock plan — deliberately NOT cleared on harvest/death. A lock
	## is a standing instruction ("always replant onions here"), not a
	## one-shot flag, so it survives the cell going empty and applies to
	## the next auto-plant too.

## ─── Seed Lock (used by FarmingTrayUI, read by the NPC thread) ──────────────
## "" = Any/unrestricted. Non-empty = a PlantDatabase plant_type key. Does
## NOT gate FarmingTray.plant_seed_at_cell() — see that function's own
## comment. Purely a read/write data field for the NPC thread's future
## PLANT_SEED job discovery to consult.
func get_cell_seed_lock(cell_index: int) -> String:
	if cell_index < 0 or cell_index >= cell_count:
		return ""
	return cell_seed_lock[cell_index]

func set_cell_seed_lock(cell_index: int, seed_type: String) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	cell_seed_lock[cell_index] = seed_type

func _cell_local_x(cell_index: int) -> float:
```

### 1.3 — Cell-proximity resolution helpers (add as a new section — place
directly after `_cell_local_x()`, before the `# ─── Interaction ───` divider)

Find:

```gdscript
func _cell_local_x(cell_index: int) -> float:
	if cell_count == 1:
		return 0.0
	return -0.475 if cell_index == 0 else 0.475

# ─── Interaction ──────────────────────────────────────────────────────────────
```

Replace with:

```gdscript
func _cell_local_x(cell_index: int) -> float:
	if cell_count == 1:
		return 0.0
	return -0.475 if cell_index == 0 else 0.475

# ─── Per-cell targeting (Aug 2026 — treat a double tray as two independent
# 1×1 cells for every action: soil, seed, harvest. A single tray always
# resolves to cell 0. XZ-only distance (matches every other horizontal-only
# proximity check in this file, e.g. GrowLight's own XZ match) — Y doesn't
# matter since cells never differ in height. Used by held items (their own
# global_position while held) and, going forward, by NPC job execution
# (their own global_position at time of acting). ────────────────────────────
func nearest_cell_to(pos: Vector3) -> int:
	if cell_count == 1:
		return 0
	var best_i: int = 0
	var best_d: float = INF
	for i: int in range(cell_count):
		var cell_pos: Vector3 = to_global(Vector3(_cell_local_x(i), 0.0, 0.0))
		var d: float = Vector2(cell_pos.x, cell_pos.z).distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i

## Same nearest-cell search, restricted to cells matching `predicate(i)`.
## Returns -1 if no cell matches. Shared by the three typed lookups below.
func _nearest_matching_cell(pos: Vector3, predicate: Callable) -> int:
	var best_i: int = -1
	var best_d: float = INF
	for i: int in range(cell_count):
		if not predicate.call(i):
			continue
		var cell_pos: Vector3 = to_global(Vector3(_cell_local_x(i), 0.0, 0.0))
		var d: float = Vector2(cell_pos.x, cell_pos.z).distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i

## Used by BagOfSoilItem.on_use() (and, going forward, NPC FILL_SOIL jobs).
func nearest_open_soil_cell_to(pos: Vector3) -> int:
	return _nearest_matching_cell(pos, func(i: int) -> bool: return not soil_filled[i])

## Used by SeedItem/FarmProduceItem.on_use() (and, going forward, NPC
## PLANT_SEED jobs).
func nearest_open_plantable_cell_to(pos: Vector3) -> int:
	return _nearest_matching_cell(pos, func(i: int) -> bool: return soil_filled[i] and planted_type[i] == "")

## Used by on_interact()/get_interact_prompt()/get_prompt_world_pos() below
## (bare-handed E) — resolves the single cell that this E-press addresses,
## via the "player" group lookup convention used elsewhere in this file
## (_show_error() looks up "hud" the same way). Falls back to cell 0 if the
## player node can't be found for any reason.
func _nearest_cell_to_player() -> int:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		return nearest_cell_to((player as Node3D).global_position)
	return 0

# ─── Interaction ──────────────────────────────────────────────────────────────
```

### 1.4 — Replace the tray-wide "first open cell" mutators with indexed
mutators

Find:

```gdscript
## Fills the first unsoiled cell. Returns true if a cell was filled.
func fill_first_open_soil_cell() -> bool:
	for i: int in range(cell_count):
		if not soil_filled[i]:
			soil_filled[i] = true
			_refresh_soil_visual(i)
			_play_soil_fill_puff(i)
			return true
	return false
```

Replace with:

```gdscript
## Fills exactly the given cell. Returns true on success. Replaces the old
## tray-wide fill_first_open_soil_cell() (Aug 2026 per-cell interaction
## pass) — callers now resolve WHICH cell via nearest_open_soil_cell_to()
## first, then commit here.
func fill_soil_at_cell(cell_index: int) -> bool:
	if cell_index < 0 or cell_index >= cell_count:
		return false
	if soil_filled[cell_index]:
		return false
	soil_filled[cell_index] = true
	_refresh_soil_visual(cell_index)
	_play_soil_fill_puff(cell_index)
	return true
```

Find:

```gdscript
## Plants into the first open (soiled, unplanted) cell. Returns true on success.
func plant_first_open_cell(plant_type: String) -> bool:
	for i: int in range(cell_count):
		if soil_filled[i] and planted_type[i] == "":
			planted_type[i] = plant_type
			var plant: FarmPlant = FarmPlant.new()
			add_child(plant)
			plant.setup(self, i, plant_type)
			plant.position = Vector3(_cell_local_x(i), SOIL_LAYER_Y, 0.0)
			plant_refs[i] = plant
			## B7 — if this cell had prepped fertilizer, apply it now and clear it
			if cell_prepped_fertilizer[i] != "":
				plant.apply_fertilizer(cell_prepped_fertilizer[i])
				cell_prepped_fertilizer[i] = ""
			return true
	return false
```

Replace with:

```gdscript
## Plants into exactly the given cell (must already be soiled and empty).
## Returns true on success. Replaces the old tray-wide plant_first_open_cell()
## (Aug 2026 per-cell interaction pass) — callers now resolve WHICH cell via
## nearest_open_plantable_cell_to() first, then commit here. Deliberately
## does NOT consult cell_seed_lock — the lock only constrains the NPC
## thread's own job-discovery/dispatch logic (their choice of WHICH job to
## post/claim), never this low-level mutator. A player (or, per the NPC
## thread's own future logic, an NPC executing a job it already chose)
## calling this directly always succeeds regardless of any lock set here.
func plant_seed_at_cell(cell_index: int, plant_type: String) -> bool:
	if cell_index < 0 or cell_index >= cell_count:
		return false
	if not soil_filled[cell_index] or planted_type[cell_index] != "":
		return false
	planted_type[cell_index] = plant_type
	var plant: FarmPlant = FarmPlant.new()
	add_child(plant)
	plant.setup(self, cell_index, plant_type)
	plant.position = Vector3(_cell_local_x(cell_index), SOIL_LAYER_Y, 0.0)
	plant_refs[cell_index] = plant
	## B7 — if this cell had prepped fertilizer, apply it now and clear it
	if cell_prepped_fertilizer[cell_index] != "":
		plant.apply_fertilizer(cell_prepped_fertilizer[cell_index])
		cell_prepped_fertilizer[cell_index] = ""
	return true
```

### 1.5 — `on_interact()` / `get_interact_prompt()` / `get_prompt_world_pos()`
now act on the single nearest cell, not "any ready cell" / "first open cell"

Find:

```gdscript
func get_interact_prompt() -> String:
	if not is_fully_soiled():
		return "[E] Fill with Soil"
	if _has_ready_cell():
		return "[E] Harvest"
	return "[E] Tray Info"

func _has_ready_cell() -> bool:
	for plant: FarmPlant in plant_refs:
		if plant != null and is_instance_valid(plant) and plant.is_ready():
			return true
	return false

func on_interact() -> void:
	if not is_fully_soiled():
		_show_error("Tray needs soil")
		return

	## Harvest every ready cell immediately, no menu — avoids stranding a
	## second ready cell on a double tray behind an ambiguous follow-up
	## E-press (plan's own reasoning, Group 0 item 19).
	var harvested_any: bool = false
	for plant: FarmPlant in plant_refs.duplicate():
		if plant != null and is_instance_valid(plant) and plant.is_ready():
			plant.harvest()
			harvested_any = true
	if harvested_any:
		return
```

Replace with:

```gdscript
## Aug 2026 per-cell interaction pass — bare-handed E now always addresses
## the ONE cell nearest the player (_nearest_cell_to_player()), never "any
## cell"/"every ready cell". A double tray reads as two independent 1×1
## units: standing closer to the left cell only ever fills/harvests the
## left cell, even if the right cell also needs soil or is also ready.
func get_interact_prompt() -> String:
	var idx: int = _nearest_cell_to_player()
	if not soil_filled[idx]:
		return "[E] Fill with Soil"
	var plant: FarmPlant = plant_refs[idx]
	if plant != null and is_instance_valid(plant) and plant.is_ready():
		return "[E] Harvest"
	return "[E] Tray Info"

func on_interact() -> void:
	var idx: int = _nearest_cell_to_player()
	if not soil_filled[idx]:
		_show_error("Tray needs soil")
		return

	## Harvest only the nearest cell's plant, one cell per E-press (Aug
	## 2026 per-cell interaction pass — was "every ready cell in the tray
	## at once"). If the player wants both cells of a double tray
	## harvested, that's two separate E-presses, one per side.
	var plant: FarmPlant = plant_refs[idx]
	if plant != null and is_instance_valid(plant) and plant.is_ready():
		plant.harvest()
		return
```

Find:

```gdscript
func get_prompt_world_pos() -> Vector3:
	if cell_count == 1:
		return global_position + Vector3(0.0, BASIN_TOP_Y, 0.0)

	## Double tray: which cells have soil? (soil_filled OR planted counts as "used")
	var used_count: int = 0
	var used_index: int = -1
	for i in range(cell_count):
		if soil_filled[i]:
			used_count += 1
			used_index = i

	if used_count == 1:
		## Exactly one side used — anchor over that side
		return global_position + Vector3(_cell_local_x(used_index), BASIN_TOP_Y, 0.0)

	## Both used, or neither used — center of the tray
	return global_position + Vector3(0.0, BASIN_TOP_Y, 0.0)
```

Replace with:

```gdscript
## Aug 2026 per-cell interaction pass — always anchors over whichever cell
## _nearest_cell_to_player() resolves to, replacing the old soil-count-based
## heuristic. This keeps the prompt, the prompt's world position, and
## on_interact()'s actual target in permanent agreement (all three now call
## the same resolution function).
func get_prompt_world_pos() -> Vector3:
	var idx: int = _nearest_cell_to_player()
	return global_position + Vector3(_cell_local_x(idx), BASIN_TOP_Y, 0.0)
```

---

## 2. `scripts/world/items/BagOfSoilItem.gd`

Find:

```gdscript
func on_use() -> void:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray needing soil nearby")
		return

	if not tray.fill_first_open_soil_cell():
		return
```

Replace with:

```gdscript
## Aug 2026 per-cell interaction pass — targets the single tray cell
## nearest to this held item (== roughly the player's hand position), not
## "the tray's first open cell". A double tray fills whichever side the
## player is standing closer to.
func on_use() -> void:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray needing soil nearby")
		return

	var cell_index: int = tray.nearest_open_soil_cell_to(global_position)
	if cell_index < 0 or not tray.fill_soil_at_cell(cell_index):
		return
```

*(No other changes needed in this file — `_find_nearest_tray_needing_soil()`
still just needs to find a tray with ANY open cell, which
`has_open_soil_cell()` already does correctly.)*

---

## 3. `scripts/world/items/SeedItem.gd`

Find:

```gdscript
func on_use() -> void:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray ready to plant nearby")
		return

	if not tray.plant_first_open_cell(seed_type):
		return
```

Replace with:

```gdscript
## Aug 2026 per-cell interaction pass — targets the single tray cell
## nearest to this held item, not "the tray's first open cell". Note this
## deliberately ignores FarmingTray.cell_seed_lock entirely — the lock only
## constrains the NPC thread's own auto-planting, never the player's manual
## on_use() (confirmed with Brannon, Seed Lock plan).
func on_use() -> void:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray ready to plant nearby")
		return

	var cell_index: int = tray.nearest_open_plantable_cell_to(global_position)
	if cell_index < 0 or not tray.plant_seed_at_cell(cell_index, seed_type):
		return
```

---

## 4. `scripts/world/items/FarmProduceItem.gd`

Only the replant branch of `on_use()` changes (the eat/cook branches are
untouched).

Find:

```gdscript
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray != null:
		if tray.plant_first_open_cell(produce_type):
			queue_free()
		return
```

Replace with:

```gdscript
	## Aug 2026 per-cell interaction pass — same nearest-cell targeting as
	## SeedItem.on_use(); also deliberately ignores cell_seed_lock for the
	## same reason (player manual planting is never gated by the lock).
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray != null:
		var cell_index: int = tray.nearest_open_plantable_cell_to(global_position)
		if cell_index >= 0 and tray.plant_seed_at_cell(cell_index, produce_type):
			queue_free()
		return
```

---

## 5. `scripts/ui/farming/FarmingTrayUI.gd`

This is the largest change. Summary of what's changing:
- Every cell now gets its own block in the panel — occupied cells keep the
  existing plant-info block (name/health/growth/ready/fertilized), empty
  cells (unsoiled OR soiled-but-unplanted) get a new, shorter block. **Both
  block types now also carry a seed-lock dropdown.**
- Two real `OptionButton` controls are added (`_seed_lock_dd_0`,
  `_seed_lock_dd_1`), positioned per-frame like the existing priority
  arrow buttons. The second is hidden entirely for single trays.
- `OptionButton`'s built-in popup already scrolls natively when its item
  list exceeds screen height — **do not build a custom scrolling
  container**, just populate a normal `OptionButton`.

### 5.1 — New constants

Find:

```gdscript
const PLANT_BLOCK_H: float = 126.0   ## Polish Plan Group 1 item 4: +16 for the "Ready in ~X days" line; Fertilizer plan: +18 for the fertilized-status line
const PLANT_BLOCK_GAP: float = 10.0
const PRIORITY_BLOCK_H: float = 112.0
const BOTTOM_PAD: float = 20.0
```

Replace with:

```gdscript
## Seed Lock plan (Aug 2026) — +34 to PLANT_BLOCK_H for the seed-lock
## dropdown row appended to every cell block (occupied or empty).
const PLANT_BLOCK_H: float = 160.0   ## was 126 (Fertilizer plan) — +34 seed-lock row
const EMPTY_CELL_BLOCK_H: float = 96.0   ## title + status line + seed-lock row, no growth/health
const PLANT_BLOCK_GAP: float = 10.0
const PRIORITY_BLOCK_H: float = 112.0
const BOTTOM_PAD: float = 20.0
const SEED_LOCK_DD_H: float = 28.0
const SEED_LOCK_LABEL_H: float = 16.0   ## "SEED LOCK" label above the dropdown
```

### 5.2 — Per-cell dropdown controls (declare + build + position)

Find:

```gdscript
var _canvas:    Control = null
var _close_btn: Button  = null
var _dec_btn:   Button  = null
var _inc_btn:   Button  = null
```

Replace with:

```gdscript
var _canvas:    Control = null
var _close_btn: Button  = null
var _dec_btn:   Button  = null
var _inc_btn:   Button  = null

## Seed Lock plan (Aug 2026) — one dropdown per cell (index 0 = left/only
## cell, index 1 = right cell on a double tray, hidden entirely on single
## trays). Each entry in _seed_lock_options[i] is a parallel array to the
## OptionButton's own items: index 0 is always "" (Any), the rest are
## PlantDatabase plant_type keys for whatever's currently in stock (plus
## the currently-locked type even if out of stock — see
## _refresh_seed_lock_dropdown()). Rebuilt only when the underlying list
## actually changes, so an open popup never gets yanked shut mid-frame.
var _seed_lock_dd:      Array[OptionButton] = [null, null]
var _seed_lock_options: Array = [[], []]   ## Array[Array[String]], parallel to each dd's items
```

Find:

```gdscript
	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.focus_mode   = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	add_child(_close_btn)
```

Replace with:

```gdscript
	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.focus_mode   = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	## Seed Lock plan — two dropdowns built up front (cell 1's is hidden
	## via _reposition_controls() on single trays), styled with the
	## project's existing settings_controls_theme() so OptionButton stops
	## using Godot's default grey chrome (same theme GraphicsSettingsPanel
	## already applies to its own OptionButtons).
	var dd_theme: Theme = UIKit.settings_controls_theme()
	for i: int in range(2):
		var dd: OptionButton = OptionButton.new()
		dd.theme        = dd_theme
		dd.mouse_filter = Control.MOUSE_FILTER_STOP
		dd.focus_mode   = Control.FOCUS_NONE
		dd.fit_to_longest_item = false
		dd.clip_text    = true
		var captured_i: int = i
		dd.item_selected.connect(func(index: int) -> void: _on_seed_lock_selected(captured_i, index))
		add_child(dd)
		_seed_lock_dd[i] = dd
```

### 5.3 — Selection handler (add as a new function, place directly after
`_apply_priority()`)

Find:

```gdscript
func _apply_priority(delta: int) -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	_tray.priority = clampi(_tray.priority + delta, PRIORITY_MIN, PRIORITY_MAX)
	_canvas.queue_redraw()
```

Replace with:

```gdscript
func _apply_priority(delta: int) -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	_tray.priority = clampi(_tray.priority + delta, PRIORITY_MIN, PRIORITY_MAX)
	_canvas.queue_redraw()

## Seed Lock plan — writes straight through to the tray on selection.
## `option_index` is an index into _seed_lock_options[cell_index], NOT a
## plant_type — index 0 is always "" (Any).
func _on_seed_lock_selected(cell_index: int, option_index: int) -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	var options: Array = _seed_lock_options[cell_index]
	if option_index < 0 or option_index >= options.size():
		return
	_tray.set_cell_seed_lock(cell_index, String(options[option_index]))
```

### 5.4 — Live-scan helper for "seed types currently in the bunker" (add as
a new function, place directly after `_on_seed_lock_selected()`)

```gdscript
## Seed Lock plan — every SeedItem instance anywhere in the bunker
## (inventory, shelved, or dropped all use the same "inventory_item" group
## membership — see SeedItem._ready()) with charges remaining. Returns
## unique plant_type keys, alphabetically sorted by display name for a
## stable, readable dropdown order.
func _get_available_seed_types() -> Array[String]:
	var seen: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("inventory_item"):
		if node is SeedItem and "_charges" in node and node._charges > 0:
			seen[(node as SeedItem).seed_type] = true
	var types: Array[String] = []
	for t: String in seen.keys():
		types.append(t)
	types.sort_custom(func(a: String, b: String) -> bool:
		return PlantDatabase.get_display_name(a) < PlantDatabase.get_display_name(b))
	return types
```

### 5.5 — Populate/sync each dropdown (add as a new function, place
directly after `_get_available_seed_types()`)

```gdscript
## Seed Lock plan — rebuilds dd's item list ONLY when the underlying set of
## options actually changed (compares against _seed_lock_options[cell_index]
## first), so an open popup is never yanked shut by a same-value refresh.
## Always keeps the CURRENTLY LOCKED type visible even if it's out of
## stock right now (a lock is a standing instruction, not tied to current
## inventory — see FarmingTray.cell_seed_lock's own comment), tagged
## "(none in stock)" so the player understands why the plant hasn't shown
## up yet.
func _refresh_seed_lock_dropdown(cell_index: int) -> void:
	var dd: OptionButton = _seed_lock_dd[cell_index]
	if dd == null or _tray == null or not is_instance_valid(_tray):
		return

	var current_lock: String = _tray.get_cell_seed_lock(cell_index)
	var available: Array[String] = _get_available_seed_types()

	var new_options: Array = [""]   ## index 0 always "Any"
	for t: String in available:
		new_options.append(t)
	if current_lock != "" and not (current_lock in available):
		new_options.append(current_lock)

	if new_options == _seed_lock_options[cell_index]:
		## No change to the option SET — but the lock itself could still
		## have changed (e.g. cleared elsewhere) on a rare path; keep
		## selection in sync without touching item_count/items.
		var idx: int = new_options.find(current_lock)
		if idx >= 0 and dd.selected != idx:
			dd.select(idx)
		return

	_seed_lock_options[cell_index] = new_options
	dd.clear()
	for i: int in range(new_options.size()):
		var val: String = String(new_options[i])
		if val == "":
			dd.add_item("Any (NPC auto-plant)")
		elif val == current_lock and not (val in available):
			dd.add_item("%s (none in stock)" % PlantDatabase.get_display_name(val))
		else:
			dd.add_item(PlantDatabase.get_display_name(val))
	var sel_idx: int = new_options.find(current_lock)
	dd.select(maxi(sel_idx, 0))
```

### 5.6 — Wire the refresh into `_process()` and `open()`

Find:

```gdscript
func open(tray: FarmingTray) -> void:
	_tray    = tray
	_is_open = true
	visible  = true
	set_process(true)
	_close_btn.visible = true
	_dec_btn.visible   = true
	_inc_btn.visible   = true
	_reposition_controls()
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()
```

Replace with:

```gdscript
func open(tray: FarmingTray) -> void:
	_tray    = tray
	_is_open = true
	visible  = true
	set_process(true)
	_close_btn.visible = true
	_dec_btn.visible   = true
	_inc_btn.visible   = true
	_seed_lock_dd[0].visible = true
	_seed_lock_dd[1].visible = tray.cell_count == 2
	## Force a full rebuild on open (bypasses the "no change" skip in
	## _refresh_seed_lock_dropdown() by clearing the cache first) so a
	## freshly-opened panel never shows a stale list from whatever tray
	## was open last.
	_seed_lock_options = [[], []]
	_refresh_seed_lock_dropdown(0)
	if tray.cell_count == 2:
		_refresh_seed_lock_dropdown(1)
	_reposition_controls()
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()
```

Find:

```gdscript
func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	_dec_btn.visible   = false
	_inc_btn.visible   = false
	closed.emit()
```

Replace with:

```gdscript
func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	_dec_btn.visible   = false
	_inc_btn.visible   = false
	_seed_lock_dd[0].visible = false
	_seed_lock_dd[1].visible = false
	closed.emit()
```

Find:

```gdscript
func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _tray == null or not is_instance_valid(_tray):
		close()
		return
	_reposition_controls()
	_canvas.queue_redraw()
```

Replace with:

```gdscript
func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _tray == null or not is_instance_valid(_tray):
		close()
		return
	## Live-refresh (Seed Lock plan) — the player can pick up/drop/use
	## seeds while this panel is open (e.g. walk to a shelf mid-session),
	## so the available-types list needs to track that. Cheap no-op most
	## frames thanks to the option-set comparison inside the function.
	_refresh_seed_lock_dropdown(0)
	if _tray.cell_count == 2:
		_refresh_seed_lock_dropdown(1)
	_reposition_controls()
	_canvas.queue_redraw()
```

### 5.7 — Layout metrics: every cell now contributes height, not just
occupied ones

Find:

```gdscript
func _layout_metrics(t: FarmingTray) -> Dictionary:
	var occupied: int = 0
	for plant: FarmPlant in t.plant_refs:
		if plant != null and is_instance_valid(plant):
			occupied += 1

	var show_bubble: bool = t.get_water_fraction() < 1.0

	var h: float = TOP_PAD + HEADER_H + CONNECTION_H + WATER_BLOCK_H
	if show_bubble:
		h += BUBBLE_H + BUBBLE_GAP_AFTER
	h += float(occupied) * PLANT_BLOCK_H + (maxf(0.0, float(occupied) - 1.0)) * PLANT_BLOCK_GAP
	if occupied > 0:
		h += PLANT_BLOCK_GAP   ## gap between plant blocks and priority section
	h += PRIORITY_BLOCK_H + BOTTOM_PAD

	return {
		"panel_h": h,
		"occupied": occupied,
		"show_bubble": show_bubble,
	}
```

Replace with:

```gdscript
## Seed Lock plan — every cell now draws a block (occupied cells get the
## taller plant-info block, empty cells get the shorter EMPTY_CELL_BLOCK_H
## block), not just occupied ones, since the seed-lock dropdown must be
## reachable regardless of whether anything's currently planted there.
func _layout_metrics(t: FarmingTray) -> Dictionary:
	var occupied: int = 0
	var cells_h: float = 0.0
	for i: int in range(t.cell_count):
		var plant: FarmPlant = t.plant_refs[i]
		if plant != null and is_instance_valid(plant):
			occupied += 1
			cells_h += PLANT_BLOCK_H
		else:
			cells_h += EMPTY_CELL_BLOCK_H
	if t.cell_count > 1:
		cells_h += float(t.cell_count - 1) * PLANT_BLOCK_GAP

	var show_bubble: bool = t.get_water_fraction() < 1.0

	var h: float = TOP_PAD + HEADER_H + CONNECTION_H + WATER_BLOCK_H
	if show_bubble:
		h += BUBBLE_H + BUBBLE_GAP_AFTER
	h += cells_h + PLANT_BLOCK_GAP   ## gap between cell blocks and priority section
	h += PRIORITY_BLOCK_H + BOTTOM_PAD

	return {
		"panel_h": h,
		"occupied": occupied,
		"show_bubble": show_bubble,
	}
```

### 5.8 — Position the two dropdowns each frame

Find:

```gdscript
	var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + _current_panel_h - PRIORITY_BLOCK_H + 40.0)
	var arrow_sz: Vector2 = Vector2(48.0, 48.0)
	_dec_btn.size = arrow_sz
	_inc_btn.size = arrow_sz
	_dec_btn.position = Vector2(px + 36.0, arrow_y)
	_inc_btn.position = Vector2(px + PANEL_W - 36.0 - arrow_sz.x, arrow_y)
	_style_arrow_btn(_dec_btn, _tray.priority > PRIORITY_MIN)
	_style_arrow_btn(_inc_btn, _tray.priority < PRIORITY_MAX)
```

Replace with:

```gdscript
	var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + _current_panel_h - PRIORITY_BLOCK_H + 40.0)
	var arrow_sz: Vector2 = Vector2(48.0, 48.0)
	_dec_btn.size = arrow_sz
	_inc_btn.size = arrow_sz
	_dec_btn.position = Vector2(px + 36.0, arrow_y)
	_inc_btn.position = Vector2(px + PANEL_W - 36.0 - arrow_sz.x, arrow_y)
	_style_arrow_btn(_dec_btn, _tray.priority > PRIORITY_MIN)
	_style_arrow_btn(_inc_btn, _tray.priority < PRIORITY_MAX)

	## Seed Lock plan — positioned via the same running-cy walk _on_draw()
	## uses, recomputed independently here since Button children can't be
	## positioned from inside a `draw`-signal callback. Must stay in exact
	## sync with _on_draw()'s own cy math below (both start from the same
	## TOP_PAD/HEADER_H/CONNECTION_H/WATER_BLOCK_H/bubble header and walk
	## the same per-cell block heights) — if you change one, change both.
	var cell_cy: float = py + 26.0 + HEADER_H + CONNECTION_H + WATER_BLOCK_H
	if bool(_layout_metrics(_tray)["show_bubble"]):
		cell_cy += BUBBLE_H + BUBBLE_GAP_AFTER
	var dd_w: float = PANEL_W - 48.0 - 12.0
	for i: int in range(_tray.cell_count):
		var plant: FarmPlant = _tray.plant_refs[i]
		var occupied_here: bool = plant != null and is_instance_valid(plant)
		var block_h: float = PLANT_BLOCK_H if occupied_here else EMPTY_CELL_BLOCK_H
		var dd: OptionButton = _seed_lock_dd[i]
		dd.position = Vector2(px + 24.0 + 6.0, cell_cy + block_h - SEED_LOCK_DD_H - 10.0)
		dd.size     = Vector2(dd_w, SEED_LOCK_DD_H)
		cell_cy += block_h
		if i < _tray.cell_count - 1:
			cell_cy += PLANT_BLOCK_GAP
```

### 5.9 — Draw loop: every cell, occupied or not

Find:

```gdscript
	## 19a — one inset block per occupied cell (has a live FarmPlant).
	var occupied: int = int(metrics["occupied"])
	if occupied > 0:
		for i: int in range(t.cell_count):
			var plant: FarmPlant = t.plant_refs[i]
			if plant == null or not is_instance_valid(plant):
				continue
			cy = _draw_plant_block(plant, cx, cy, bar_w)
		cy += PLANT_BLOCK_GAP
```

Replace with:

```gdscript
	## 19a, extended by the Seed Lock plan — one block per cell now,
	## occupied or not, so the seed-lock dropdown is always reachable.
	for i: int in range(t.cell_count):
		var plant: FarmPlant = t.plant_refs[i]
		if plant != null and is_instance_valid(plant):
			cy = _draw_plant_block(plant, cx, cy, bar_w)
		else:
			cy = _draw_empty_cell_block(t, i, cx, cy, bar_w)
	cy += PLANT_BLOCK_GAP
```

### 5.10 — New empty-cell block drawer + shrink the seed-lock label into
the existing plant block (add `_draw_empty_cell_block()` directly after
`_draw_plant_block()`, and extend `_draw_plant_block()` with the label)

Find:

```gdscript
	if plant.is_fertilized():
		var pct: int = int(round(plant.fertilizer_bonus * 100.0))
		var fert_label: String = "Fertilized (%s, +%d%% growth)" % [plant.fertilizer_tier.capitalize(), pct]
		_draw_str(fert_label, Vector2(bx, by), READY_COLOR, 11)
	else:
		_draw_str("Not Fertilized", Vector2(bx, by), _theme.dim, 11)

	return cy + PLANT_BLOCK_H
```

Replace with:

```gdscript
	if plant.is_fertilized():
		var pct: int = int(round(plant.fertilizer_bonus * 100.0))
		var fert_label: String = "Fertilized (%s, +%d%% growth)" % [plant.fertilizer_tier.capitalize(), pct]
		_draw_str(fert_label, Vector2(bx, by), READY_COLOR, 11)
	else:
		_draw_str("Not Fertilized", Vector2(bx, by), _theme.dim, 11)
	by += 22.0

	## Seed Lock plan — label sits directly above the real OptionButton
	## positioned by _reposition_controls(); wording makes the NPC-only
	## scope explicit right where the player sets it.
	_draw_str("SEED LOCK (NPC auto-plant only)", Vector2(bx, by), _theme.dim, 9)

	return cy + PLANT_BLOCK_H

## Empty-cell counterpart to _draw_plant_block() — Seed Lock plan. Drawn
## for any cell with no live FarmPlant (unsoiled, or soiled-but-unplanted).
## Shorter than a plant block (no health/growth/ready/fertilized rows) but
## still carries the seed-lock dropdown, since a lock is meant to be set
## BEFORE something is planted.
func _draw_empty_cell_block(t: FarmingTray, cell_index: int, cx: float, cy: float, bar_w: float) -> float:
	var block_rect: Rect2 = Rect2(cx - 4.0, cy - 4.0, bar_w + 8.0, EMPTY_CELL_BLOCK_H - PLANT_BLOCK_GAP)
	_canvas.draw_rect(block_rect, Color(0.09, 0.10, 0.11, 0.70), true)
	_canvas.draw_rect(block_rect, Color(_theme.border.r, _theme.border.g, _theme.border.b, 0.45), false, 1.0)

	var bx: float = cx + 6.0
	var by: float = cy + 12.0

	var title: String = ("CELL %d" % (cell_index + 1)) if t.cell_count > 1 else "CELL"
	_draw_str(title, Vector2(bx, by), _theme.header, 12)
	by += 20.0

	var status: String = "Needs Soil" if not t.soil_filled[cell_index] else "Empty — Ready to Plant"
	_draw_str(status, Vector2(bx, by), _theme.dim, 11)
	by += 26.0

	_draw_str("SEED LOCK (NPC auto-plant only)", Vector2(bx, by), _theme.dim, 9)

	return cy + EMPTY_CELL_BLOCK_H
```

**Header comment update** — since `_draw_plant_block()` is no longer only
called for occupied cells conditionally guarded by `occupied > 0`, and the
file header's Group 0 description of "19a — one inset block per occupied
cell" is now only half true, update the doc comment block at the top of
the file:

Find:

```gdscript
## Group 0 additions (replaces the old separate PlantInfoUI.gd panel, now
## deleted):
##   19a — one inset block per occupied cell (has a live FarmPlant): plant
##         name, "Health: X%", a flat #e3ad30 growth bar + numeric
##         "Growth: NN%" label, and a NOT READY (red) / READY (green) line.
```

Replace with:

```gdscript
## Group 0 additions (replaces the old separate PlantInfoUI.gd panel, now
## deleted):
##   19a — one inset block per CELL (Seed Lock plan, Aug 2026, widened from
##         "per occupied cell"): occupied cells get plant name, "Health: X%",
##         a flat #e3ad30 growth bar + numeric "Growth: NN%" label, and a
##         NOT READY (red) / READY (green) line; empty cells get a shorter
##         status-only block. Every cell's block also carries a seed-lock
##         dropdown (NPC auto-plant restriction — see FarmingTray.gd's
##         cell_seed_lock).
```

---

## 6. Documentation update — `docs/systems/farming/README.md`

Add a new dated section at the end of the file (after the "Common edits —
adding a new plant species" section, before "Known gaps"):

```markdown
## Per-cell seed lock + per-cell interaction (Aug 2026)
- **Seed lock** — `FarmingTray.cell_seed_lock: Array[String]`, one entry
  per cell, `""` = Any. Set via a new dropdown per cell in
  `FarmingTrayUI._draw_plant_block()`/`_draw_empty_cell_block()`, backed by
  a real `OptionButton` positioned in `_reposition_controls()`. Options are
  built from `FarmingTrayUI._get_available_seed_types()` — every `SeedItem`
  in the `"inventory_item"` group (inventory + shelved + dropped, all use
  that group) with `_charges > 0`, deduped by `seed_type`. **This lock only
  constrains the NPC thread's own auto-planting job discovery/dispatch —
  it is read-only data from this system's perspective and does NOT gate
  `FarmingTray.plant_seed_at_cell()`, so the player's manual `SeedItem`/
  `FarmProduceItem.on_use()` always ignores it.** In-session only — not
  wired into save/load, same gap category as the rest of this system's
  per-cell state (see "Known gaps" below).
- **Per-cell interaction** — soil-fill, seed-plant, and harvest all now
  resolve to exactly ONE cell per action, via
  `FarmingTray.nearest_cell_to()`/`nearest_open_soil_cell_to()`/
  `nearest_open_plantable_cell_to()` (XZ-distance to the acting entity's
  position — the held item's `global_position` for the player, and,
  going forward, the acting NPC's position for NPC jobs). A double tray
  now behaves as two fully independent 1×1 cells for every action except
  the `FarmingTrayUI` "Tray Info" panel, which still shows both cells at
  once. `FarmingTray.fill_first_open_soil_cell()`/`plant_first_open_cell()`
  (tray-wide "first open cell") were removed and replaced with indexed
  `fill_soil_at_cell(cell_index)`/`plant_seed_at_cell(cell_index, type)`.
  **`FertilizerItem`/`fertilize_first_open_cell()` were deliberately left
  on the old tray-wide pattern this pass** — flagged as inconsistent with
  the rest of the tray now, not yet fixed.
```

Also update the existing "Known gaps" section's Group 7 bullet — find:

```markdown
- **Group 7 items** (double-stack grow-light guard, save schema pre-shape,
  tray deconstruct/refund rule, `get_trays_needing_attention()`) — the last
  remaining group, not yet started.
```

Replace with:

```markdown
- **Group 7 items** (double-stack grow-light guard, save schema pre-shape,
  tray deconstruct/refund rule, `get_trays_needing_attention()`) — the last
  remaining group, not yet started.
- **Fertilizer per-cell consistency** — `FertilizerItem`/
  `FarmingTray.fertilize_first_open_cell()` still use the tray-wide
  "first open cell" pattern that soil/seed/harvest moved away from in the
  Aug 2026 per-cell interaction pass (see that section above). Flagged,
  not yet converted.
```

---

## 7. Manual test checklist (leave this in the handoff notes for Brannon)

1. Single tray — fill soil, plant, harvest all still work exactly as
   before (single-tray behavior is unchanged; `nearest_cell_to()` always
   returns 0 when `cell_count == 1`).
2. Double tray — stand closer to the left cell, use a Bag of Soil: only
   the left cell fills. Repeat on the right: only the right cell fills.
3. Double tray, both cells soiled and both plants ready — bare-handed E
   harvests only the nearer plant; a second E-press (now standing closer
   to the other side, or after moving) harvests the other one
   independently.
4. Open Tray Info on a double tray with one occupied + one empty cell —
   confirm both a plant block AND an empty-cell block render, each with
   its own seed-lock dropdown, panel height matches (no clipped/overlapped
   rows).
5. With only Onion, Chili Pepper, and Garlic seeds anywhere in the bunker
   (inventory + shelf + ground, mixed), open a tray's dropdown — confirm
   exactly those 3 species + "Any" appear, nothing else.
6. Set a lock, then use up every seed of that type — reopen the panel,
   confirm the locked type still shows (tagged "none in stock") and stays
   selected, rather than silently reverting to "Any".
7. Set a lock to (e.g.) "Onion", then manually plant a Tomato seed by
   hand into that same cell — confirm it succeeds (lock never blocks the
   player).
8. Popup scroll — temporarily hold seeds for many species at once (F7
   admin spawn buttons help here), confirm the dropdown's native popup
   scrolls correctly instead of running off-screen.
