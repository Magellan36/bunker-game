# NPC System (Aug 2026)

**Read this before opening any `scripts/npc/`, `scripts/ui/npc/`, or
`scenes/npc/` file.** Only open the actual source for the specific
function you're changing.

---

## Purpose

Basic NPC system: wandering NPCs that roam the dug-out bunker area and
can be interacted with via a simple Talk menu. No task system, no
pathfinding, no persistence — this is the minimal viable NPC foundation.

---

## Responsibilities

- **NPC.gd** (`scripts/npc/`): wandering behavior (IDLE/WANDERING state
  machine), collision with all bunker structures, [E] Talk interaction
  that opens `NPCTalkMenuUI`
- **NPCTalkMenuUI.gd** (`scripts/ui/npc/`): modal menu with "Talk" button
  → placeholder dialogue ("...") + "Close" button. Built on shared
  `UIKit` menu builders for visual consistency.
- **NPC.tscn** (`scenes/npc/`): `CharacterBody3D` with capsule
  mesh/collision. **No custom `collision_layer`/`collision_mask`** — uses
  Godot defaults (layer 1) which correctly collides with all bunker
  structures (walls, pillars, furniture, appliances on layer 5).
- **MainWorld.gd** (`scripts/world/core/`): provides
  `get_cleared_cell_bounds_world()` → Rect2 of all cleared cells (pregen
  + player-dug) for NPC wander bounds.
- **AdminMenu.gd** (`scripts/ui/menus/`): "Spawn NPC" button in F7 menu
  (NPC section) — spawns `NPC.tscn` 2m in front of player.

---

## Non-responsibilities

- **No task system** — no filter replacement, crop harvesting, water
  collection, generator repair. `current_task` and `assign_task()`/`perform_task()`
  are stubbed in `NPC.gd` as explicit `FUTURE WORK` extension points.
- **No pathfinding/NavMesh** — wandering is random-point + collision
  redirect only (`_check_stuck()` redirects on collision or lack of
  movement).
- **No save/load persistence** — spawned NPCs disappear on reload.
- **No dialogue system** — `NPCTalkMenuUI` is a single placeholder line
  ("...") + Close button. Dialogue trees, branching, NPC-specific lines
  are explicitly out of scope.
- **No NPC variety** — single "Survivor" capsule model, single name.

---

## Files

| File | Lines | Role |
|---|---|---|
| `scripts/npc/NPC.gd` | ~200 | NPC wandering + Talk interaction |
| `scripts/ui/npc/NPCTalkMenuUI.gd` | ~100 | Talk menu (Talk button → "..." + Close) |
| `scenes/npc/NPC.tscn` | ~20 | CharacterBody3D + capsule mesh/collision |
| `scripts/world/core/MainWorld.gd` | +~30 | `get_cleared_cell_bounds_world()` for wander bounds |
| `scripts/ui/menus/AdminMenu.gd` | +~20 | "Spawn NPC" button in F7 menu |

---

## Public API

### `NPC` (`class_name NPC`, extends `CharacterBody3D`)

**Exports (tunable per-instance):**
- `move_speed: float = 2.2`
- `acceleration: float = 8.0`
- `npc_name: String = "Survivor"`
- `arrival_distance: float = 0.5`
- `idle_time_min: float = 1.5`
- `idle_time_max: float = 4.0`
- `wander_margin: float = 0.8`

**Signals:**
- None currently (future: `talk_started`, `talk_ended`)

**Methods:**
- `get_interact_prompt() -> String` — returns `"[E] Talk to Survivor"`
- `on_interact() -> void` — opens `NPCTalkMenuUI`
- `assign_task(task: Node) -> void` — **stub** (future task system)
- `perform_task(delta: float) -> void` — **stub** (future task system)

**Internal state (do not access externally):**
- `_state: NPCState` (IDLE/WANDERING)
- `_idle_timer`, `_wander_target`, `_stuck_check_timer`, `_stuck_check_last_pos`
- `current_task: Node` — **future use only**, currently always `null`

---

### `NPCTalkMenuUI` (`class_name NPCTalkMenuUI`, extends `CanvasLayer`)

**Signals:**
- None (self-contained, closes on button/ESC)

**Methods:**
- `open(npc_name: String) -> void` — builds MENU state, shows panel
- `close() -> void` — tears down, hides panel

**States:**
- **MENU** — NPC name + "Talk" button
- **DIALOGUE** — placeholder line ("...") + "Close" button
- **COMMANDS** (Part 19) — four command buttons revealed after Talk:
  "Go eat something", "Go drink something", "Take a load off", "Harvest the plants"

**Transitions:**
- MENU → "Talk" button → DIALOGUE + COMMANDS
- DIALOGUE + COMMANDS → "Close" button / ESC → close

---

## Key Implementation Details

### Wander Bounds
- Uses `MainWorld.get_cleared_cell_bounds_world()` which returns a
  `Rect2` covering all cleared cells (pregen interior + player-dug
  chunks). Each cell key in `_cleared_cells` is `"cx,cz"` representing a
  1×1 world-unit cell at `(cx, cz)` to `(cx+1, cz+1)`.
- `wander_margin` (default 0.8) keeps NPCs away from bounding box edges.
- If bounds unavailable (no cleared cells), NPC stays at current position.

### Collision
- NPC uses **default collision layer/mask (1/1)** — same as Player.
- All bunker structures (walls, pillars, furniture, appliances) are on
  **layer 5** (bits for layer 1 + layer 3) which **includes layer 1**.
- This means NPCs automatically collide with everything solid without
  any custom layer setup. **Do not change collision layers.**

### Stuck Detection
- `_check_stuck()` runs every frame while WANDERING:
  - If `get_slide_collision_count() > 0` → immediate `_enter_idle()`
  - Every 1s: if moved < 0.15 units → `_enter_idle()` (prevents
    pushing against obstacles forever)

### Talk Interaction
- NPC adds itself to `"interactable"` and `"npc"` groups in `_ready()`.
- `InteractionSystem.gd` detects NPC via `("is_cookpot_container" in held_item)` check — wait, that's for CookingPot. Actually:
  - NPC adds itself to `"interactable"` group.
  - `InteractionSystem._update_prompt()` CASE 1 (holding item) checks `held_item.has_method("get_interact_prompt")` — NPC doesn't have this when held (it's not holdable).
  - Actually, NPC is in `"interactable"` group and has `on_interact()` and `get_interact_prompt()`.
  - `InteractionSystem._try_interact()` Pass 1 (RigidBody3D) and Pass 2 (StaticBody3D) both check `body.has_method("on_interact")`.
  - NPC is a `CharacterBody3D` (not StaticBody3D), so it's caught in Pass 1 via `detect_area.get_overlapping_bodies()`.
  - Pressing E calls `on_interact()` → `_open_talk_menu()`.

### Talk Menu
- Built on shared `UIKit` builders (`build_modal_backdrop`,
  `build_centered_panel`, `make_button`) — same as PauseMenuUI's
  confirm dialog.
- Two states: MENU (Talk button) → DIALOGUE (placeholder "..." + Close).
- Layer 70 (above HUD, below AdminMenu 128 / PauseMenuUI 200).
- ESC closes at any state.

---

## Admin Spawn
- F7 Admin Menu → NPC section → "Spawn NPC" button
- Spawns `NPC.tscn` 2m in front of player (using player's
  `-global_transform.basis.z * 2.0 + Vector3(0, 0.5, 0)`)
- Injected `world_node` (MainWorld) used for parenting
- No cash cost (cheat menu)

**F7 NPC Section (Part 19)** — additional adjuster rows:
- Health +20 / Health -20 (clamp 0–100, mirrors existing Energy/Hunger/Thirst rows)
- All need adjusters use shared `_adjust_all_npc_need(field, delta)` helper

---

## Common Edits

### New NPC variant (future)
1. Duplicate `NPC.gd` → `NewNPC.gd`, change `class_name`, tweak exports.
2. Duplicate `NPC.tscn` → `NewNPC.tscn`, attach new script.
3. Add spawn callback in `AdminMenu.gd` following `_on_spawn_npc_pressed` pattern.
4. No collision layer changes needed.

### Add dialogue (future)
1. Extend `NPCTalkMenuUI.gd` or create `NPCDialogueUI.gd`.
2. Replace `_build_dialogue_state()` with dialogue tree logic.
3. Add NPC-specific dialogue data (resource or export on NPC).
3. Update `NPC._open_talk_menu()` to open new UI.

### Adjust wander behavior
- Modify `_pick_wander_target()` for different bounds logic.
- Add `NavigationServer3D` pathfinding when task system exists.
- Tunables: `move_speed`, `acceleration`, `arrival_distance`,
  `idle_time_min/max`, `wander_margin`.

---

## Forbidden Edits

- **Don't change NPC collision layer/mask** — default 1/1 is correct
  for colliding with all bunker structures (layer 5 includes layer 1).
- **Don't add pathfinding/NavMesh** — current wander is intentional
  minimal implementation; pathfinding is future work.
- **Don't wire `current_task` or `perform_task()`** — these are
  explicit `FUTURE WORK` stubs; wait for task system design.
- **Don't add save/load for NPCs** — explicitly out of scope for this
  pass; will be part of save/load overhaul.
- **Don't add dialogue branching** — `NPCTalkMenuUI` is intentionally
  minimal; dialogue system is a separate future pass.

---

## Known Tradeoffs / Tech Debt

- No pathfinding → NPCs can get stuck in corners temporarily (mitigated
  by `_check_stuck()` redirect).
- No persistence → NPCs vanish on save/load.
- Single placeholder dialogue line — no personality, no info transfer.
- Single NPC type — no visual/behavioral variety.
- Wander bounds are AABB of cleared cells, not exact dug shape — NPCs
  may wander slightly into undug rock areas at chunk boundaries (margin
  helps but isn't perfect).

---

## Extension Points

- **Task system** → fill in `assign_task()`/`perform_task()` when
  `NPCState.WORKING` is added. See `FUTURE WORK` comments in `NPC.gd`.
- **Dialogue system** → replace `NPCTalkMenuUI._build_dialogue_state()`
  with dialogue tree; add NPC-specific lines via export or resource.
- **NPC variety** → new scenes/scripts following same pattern; add
  spawn buttons in AdminMenu.
- **Save/load** → add NPC registry to `SaveManager` phase (when
  save/load overhaul happens).
- **Eat/Drink activities (Part 17)** — both now continue automatically
  across multiple items within a single activity run (e.g., drink from
  dispenser until thirst ≥ 90, or eat multiple food items until hunger ≥ 55)
  rather than fully exiting and restarting between each one.
- **Stuck recovery (Part 18)** — gated on `_movement_locked` instead of
  `nav_finished()`. Activities (Drink/Eat/Job-work) halt via their own
  range checks (`PICKUP_RANGE`, `USE_RANGE`, `WORK_RANGE`), which are
  decoupled from the nav agent's internal arrival threshold. The old
  `nav_finished()` gate caused false stuck-aborts mid-activity because
  the nav agent didn't know the activity had intentionally stopped.
  `_movement_locked` is raised by `halt_movement()`/`lock_movement()` and
  cleared only when `nav_steer()` resumes travel — a direct read of
  "an activity wants me stationary."
- **Player Commands (Part 19)** — four commands via `NPCTalkMenuUI` after
  pressing Talk: "Go eat", "Go drink", "Take a load off" (bed→chair
  fallback), "Harvest the plants". Each force-starts an existing activity
  class directly via `NPCBrain.force_command()`: `EatActivity`,
  `DrinkActivity`, `CommandRestActivity` (tries LieActivity then
  SitActivity), `CommandHarvestActivity` (finds nearest HARVEST job).
  Reuses automatic system's activity classes for identical behavior.
  **Priority note:** Part 14's pass-out override (checked every frame)
  preempts commands — a commanded NPC with 0 Energy will immediately
  pass out instead of executing the command.

---

## Related Systems

- **InteractionSystem** (`scripts/player/InteractionSystem.gd`) —
  handles [E] Talk via `_try_interact()` → calls `on_interact()`.
- **MainWorld** (`scripts/world/core/MainWorld.gd`) — provides
  `get_cleared_cell_bounds_world()` for wander bounds.
- **AdminMenu** (`scripts/ui/menus/AdminMenu.gd`) — spawn button.
- **UIKit** (`scripts/ui/common/UIKit.gd`) — shared menu builders
  used by `NPCTalkMenuUI`.

---

## Testing Checklist (for in-editor verification)

1. Open project in Godot — zero script errors/warnings.
2. Run game, press F7 → Admin Menu shows NPC section with "Spawn NPC".
3. Click "Spawn NPC" → NPC capsule appears 2m in front.
4. Watch 15-20s: wanders, pauses, walks, never walks through walls/
   pillars/furniture.
5. Walk up, press E → "Survivor" popup with "Talk" button.
6. Click "Talk" → placeholder "..." + "Close" button.
7. Click Close / press ESC → popup closes.
8. Dig new area → NPC eventually wanders into it.
9. Spawn second NPC → both wander independently, no errors.
10. All existing F7 buttons (Power, Time, Water, Economy, Farming,
    Status) still work.