# Feature Plan v2 — End Table + Dresser (Light Storage, Shared StorageUI)

**Supersedes** `END_TABLE_DRESSER_LIGHT_STORAGE_PLAN.md` (v1) entirely. v1's Part 4 (LightStorageUI.gd) and Part 5h/5i (second CanvasLayer, `_shelf_ui_open()` extension) are dead — the Aug 2026 **Storage UI Unification** pass made one shared `StorageUI.gd` serve every container via a 4-method contract, and `MainWorld._setup_storage_ui()` already injects `_storage_ui`/`_interaction_system` into every `"shelving"`-group member that declares those properties. New storage types need **zero UI code**.

**Starting point:** three scripts already exist on disk this session, uncommitted — `scripts/world/furniture/LightStorage.gd` (adapted to the contract), `EndTable.gd`, `Dresser.gd`. **Do not rewrite them from scratch.** Part 1 is a required-final-state checklist: verify each numbered item against the existing files and patch only what's missing or different. Parts 2+ are the untouched wiring/docs work.

Locked decisions (unchanged from v1): eligibility = `"inventory_item"` group; End Table capacity 2, Dresser capacity 6; no stacking; stored items hidden (frozen, invisible, collision-off children of the furniture, in the `"shelved"` group); both join `"shelving"` for the duck-typed E/F contract; tile IDs 32/33; $60/$150 in Furniture category; Dresser 1.90×0.90 × ~1.55 m tall.

---

## Part 1 — `LightStorage.gd` required final state (verify/patch the existing file)

**1.1 Storage model — fixed-size array.** `stored` must be a fixed-size Array of length `capacity`, initialized to nulls in `_ready()` (`stored.resize(capacity)`), with `stored[i] = item_or_null`. NOT an append/remove list — StorageUI addresses slots positionally via `get_slot_display(slot_idx)`, so indices must be stable when a middle slot is emptied. `is_full()` = no null entry; storing fills the first null slot.

**1.2 Properties.** `@export var capacity`, `display_name`, `prompt_height`, plus UI-shape exports `grid_cols: int`, `grid_rows: int`, `row_labels: Array[String]` (subclasses set all in `_init()`; base builds the config dict from them so subclasses stay mesh-only). Injected refs named exactly `_storage_ui` and `_interaction_system` — these names are load-bearing: `MainWorld._setup_storage_ui()`'s loop (`MainWorld.gd:575-580`) injects by checking `"_storage_ui" in node` / `"_interaction_system" in node` on every `"shelving"` member. Plus `_is_preview_only := false`.

**1.3 `_ready()` order.** `collision_layer = 5`, `collision_mask = 0`, `stored.resize(capacity)`, `_build_mesh()`, THEN `if _is_preview_only: return`, THEN `add_to_group("shelving")`. Mesh before guard (GrowLight lesson); group after guard (previews must never join).

**1.4 E/F duck-type contract** (what InteractionSystem calls on `"shelving"` members):
- `on_e_interact()` → exactly `Shelving.gd:209-213`: warn-and-return if `_storage_ui == null`, else `_storage_ui.open(self)`.
- `on_f_interact()` → resolve `_interaction_system` if null, then `_try_store_held(_interaction_system.held_item)` when non-null.
- `on_interact()` → legacy shim calling `on_f_interact()`.
- `get_e_prompt()` → `"[E] Open %s" % display_name.to_lower()`.
- `get_f_prompt()` → `""` unless a held item exists, is in `"inventory_item"`, and `not is_full()`; then `"[F] Store item"`.
- `get_prompt_world_pos()` → `global_position + Vector3(0, prompt_height, 0)`.

**1.5 Store path `_try_store_held(item)`.** Reject with HUD `show_soft_warning` when not `inventory_item` ("Too big for the …") or full ("… is full"). On accept, run the InteractionSystem release sequence copied from `Shelving._try_place_item()` lines ~334-351 verbatim (`_is_holding_e = false`; `knocked_out` disconnect; `_held_from_slot`/inventory `retrieve_item` clearing; `held_item = null`; `is_held`/`_hold_point`/`from_inventory` resets), then absorb: `freeze = true`, `collision_layer = 0`, `collision_mask = 0`, `visible = false`, `add_to_group("shelved")`, reparent to `self` at `position = Vector3.ZERO`, write into first null slot. No metadata layer-saving — restoration uses the codebase's canonical values (1.6/1.7).

**1.6 StorageUI contract method 1-2.**
```gdscript
func get_slot_display(slot_idx: int) -> Array:
	if slot_idx < 0 or slot_idx >= stored.size() or stored[slot_idx] == null:
		return [null, 0]
	return [stored[slot_idx], 1]

func get_ui_config() -> Dictionary:
	return {
		"title": display_name.to_upper(),
		"slot_count": capacity,
		"grid_cols": grid_cols,
		"grid_rows": grid_rows,
		"display_order": [],              ## identity
		"row_labels": row_labels,
		"supports_stacking": false,
		"primary_button_icon": "↑",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}
```

**1.7 StorageUI contract methods 3-4.** Mirror `Shelving.retrieve_to_carry/retrieve_to_inventory` (`Shelving.gd:469-533`) with two mandatory deltas because our items are hidden children of the furniture, which shelf items never are: **(a) reparent to world root** (group `"world"`, fallback `get_parent()`) before the hand-off, setting `global_position = self.global_position + Vector3(0, 0.6, 0)` so the item exists at a sane world transform when `pickup()`/`add_item()` runs; **(b) restore `visible = true`** in BOTH paths (shelf's carry path never hides items so it skips this — ours cannot). Everything else matches shelf semantics exactly:
- `take_for_carry(slot_idx, isys) -> bool`: false on bad index / null slot / `isys.held_item != null`. Clear slot to null; `remove_from_group("shelved")`; visible; reparent per (a); `freeze = false`, `freeze_mode = FREEZE_MODE_KINEMATIC`, `collision_layer = 2`, `collision_mask = 1`, `gravity_scale = 1.0`, zero both velocities; connect `knocked_out` → `isys._on_item_knocked_out` if not connected; `from_inventory = false` if present; `item.pickup(isys.hold_point)` if it has the method; `isys.held_item = item`, `isys._held_from_slot = -1`; return true.
- `take_for_inventory(slot_idx, inv) -> bool`: false on bad index / null slot. Clear slot; `remove_from_group("shelved")`; `freeze = false`; `visible = true`; `collision_layer = 1`, `collision_mask = 1`; zero velocities; reparent per (a); `inv.add_item(item)`; return true.

**1.8 `eject_all_items()` — REQUIRED, easy to miss, destructive if missing.** Deconstruct (`BuildModeController.gd:1805`) and build-undo (`BuildUndoStack.gd:59`) duck-call `eject_all_items()` on removed objects. Shelving and Stove implement it; a LightStorage without it has its stored items **silently freed along with the furniture node** on deconstruct/undo, because they're children. Implement: for each non-null slot — `remove_from_group("shelved")`, `visible = true`, `freeze = false`, `collision_layer = 1`, `collision_mask = 1`, zero velocities, reparent to world root, `global_position = self.global_position + Vector3(0.3 * (i + 1), 0.6, 0.15 * (i % 2))` (spread so items don't interpenetrate), clear slot to null.

**1.9 Remove v1 leftovers if present in the draft:** any `take_item(index)` method, `light_storage_layers` metadata save/restore, `_light_storage_ui` property name, or a UI-script reference — all superseded by 1.5-1.7.

## Part 2 — `EndTable.gd` / `Dresser.gd` (verify the existing files)
Meshes/dimensions per v1 (End Table: Table.gd legs+top verbatim, cabinet box 0.70×0.40×0.70 at y 0.50 with collision, drawer face+knob on local -Z; Dresser: body 1.90×1.50×0.90 with collision, top slab 1.96×0.05×0.96, 2×3 drawer faces+knobs on -Z; both keep `static func build_ghost_mesh()` returning the bounding BoxMesh). Confirm each `_init()` sets the full export set from 1.2:
- **EndTable:** capacity 2, display_name "End Table", prompt_height 1.2, grid_cols 2, grid_rows 1, row_labels `["Drawer"]`.
- **Dresser:** capacity 6, display_name "Dresser", prompt_height 1.9, grid_cols 2, grid_rows 3, row_labels `["Top drawers", "Middle drawers", "Bottom drawers"]`.

## Part 3 — Wiring
**(a)** `BuildModeController.gd` constants: `TILE_END_TABLE: int = 32`, `TILE_DRESSER: int = 33` (comment style per neighbors).
**(b)** `BuildModeHUD.gd` — SCOPED EXCEPTION, exactly two data lines in CATEGORIES → "Furniture" after Chair (~line 48), nothing else in the file:
```gdscript
		{ "tile_id": 32, "name": "End Table",    "price": 60  },
		{ "tile_id": 33, "name": "Dresser",      "price": 150 },
```
**(c)** `spawn_structure()`: two branches after Chair (~line 1198) shaped like the Table branch (script-load, `set_meta("tile_id", …)`, add → `global_position` → `rotation_degrees`, return), PLUS the Shelving branch's injection block verbatim (`BuildModeController.gd:1212-1220`): resolve `InteractionSystem` via `get_parent().get_node_or_null("InteractionSystem")` → `set("_interaction_system", …)`, resolve the world node's `"StorageUI"` child → `set("_storage_ui", …)`. Without this, mid-session-placed units warn "not injected" on E.
**(d)** `GhostModelBuilder.PROCEDURAL_PREVIEW_SOURCES`: `32:` → EndTable.gd, `33:` → Dresser.gd, `"is_script": true`.
**(e)** `GhostPreview.gd`: fallback ghost branches after Chair's (~line 249) calling the two `build_ghost_mesh()` statics via `load()` + `has_method` guard; extend the floor-standing `snap_pos.y = 0.5` elif (~line 593) with both new tiles.
**(f)** `_is_position_occupied_for_tile()` (~line 2836): add both tiles to the outer furniture `if` AND the inner `et !=` filter (registry-only overlap; avoids the floor-collider false positive).
**(g)** `_ghost_half_extents_for_tile()`: `TILE_END_TABLE → Vector2(0.45, 0.45)`, `TILE_DRESSER → Vector2(0.95, 0.48)`.
**(h)** `MainWorld.gd`: **NO changes.** `_setup_storage_ui()`'s existing group loop covers pre-placed units automatically via the property-name checks (1.2).
**(i)** `InteractionSystem.gd`: **no changes required** — `shelf_ui` already points at the shared StorageUI instance, so input-blocking while our panel is open works today. *Optional cosmetic:* `var light_storage_ui: Node = null` (~line 42) + a third check in `_shelf_ui_open()`; if taken, include the standard Player-thread commit note. Skipping it is fine.

## Part 4 — Documentation (same commit)
1. `docs/systems/furniture-items/README.md` — "Light Storage (End Table / Dresser)" section: eligibility = `inventory_item`; capacities 2/6, no stacking; hidden-children storage model; **uses the shared StorageUI via the 4-method contract** (`get_ui_config` / `get_slot_display` / `take_for_carry` / `take_for_inventory`) — no UI code of its own; `"shelving"` group = the generic E/F container contract; `eject_all_items()` requirement for any container whose items are children; tile IDs/prices.
2. `docs/systems/build/README.md` — tile table rows 32/33; wiring checklist: cite these two as the current reference example of complete new-object wiring, including spawn-branch StorageUI injection for storage types.
3. Storage/UI doc (wherever the Unification pass documented the contract — likely `docs/systems/ui/README.md` or furniture-items): add LightStorage to the list of contract implementers alongside Shelving/Basket.
4. `HANDOVER.md` — entry: "End Table + Dresser (Light Storage) — Aug 2026": decisions header, contract-based UI (no new UI files), files added/touched, the eject_all_items child-item gotcha.

## Part 5 — Verification (Brannon, in-editor)
1. **Placement:** both in Construct → Furniture at $60/$150; real-model spinning previews; correctly-sized non-colliding ghosts with facing arrow; green/red overlap vs other furniture correct; sits flush at floor; drawers face the arrow direction after rotation.
2. **Store:** FoodCan + F → stored, vanishes; fill to capacity → "… is full" warning on the next; Crate (non-inventory item) → no F prompt, F drops normally.
3. **Shared UI:** E opens StorageUI titled END TABLE / DRESSER with the right grid (2×1 / 2×3) and row labels; ↑ Carry hands the item back (blocked with full hands, per config); ⊕ sends to pocket inventory; slot indices stay stable when a middle drawer is emptied; panel blocks world E/F while open; shelf and basket UIs still work unchanged.
4. **Injection both paths:** a unit placed mid-session opens its UI with no "not injected" warning; if any pre-placed test unit exists at world build, it opens too.
5. **Eject:** store 2 items in an End Table, deconstruct it → both items pop out beside it, visible, grabbable. Repeat via build-undo on a Dresser.
6. **Ecosystem:** hidden stored can isn't stashed by a held Basket, gets no prompts, invisible to scans; E fairness (basket + loose can at feet + dresser 2 m) unchanged; items set physically on the End Table top rest normally; moving a unit with the Move tool carries its stored items and they remain retrievable.
