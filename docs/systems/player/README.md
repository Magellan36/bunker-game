# Player System

**Read this before opening `Player.gd`, `PlayerStats.gd`, or `InteractionSystem.gd`.**
Only open the actual source for the specific function you're changing.

## Purpose
Owns the player character's movement/stamina, survival needs + game clock, and
all pickup/drop/store/scroll interaction logic. These three scripts are
separate but tightly coupled (all live under `scripts/player/`, all wired
together by `MainWorld`).

## Responsibilities
- `Player.gd`: WASD movement (camera-relative), sprint + stamina drain/regen,
  facing rotation, the `interacted` input signal, and the movement-lock used
  by the pause menu.
- `PlayerStats.gd`: food/water/sleep/health drain over a real-time-to-game-time
  clock, starvation/dehydration health damage, the `H:MM AM/PM` game clock +
  day counter, and save/load support for elapsed time.
- `InteractionSystem.gd` (~686 lines): the ONLY place pickup/drop/store/scroll
  logic lives. Owns `held_item`, inventory slot activation/deactivation, and
  the floating interact prompt (built each frame from whatever's held or
  nearby). E is a pure instant tap (use/interact fires on press, no hold
  behavior); G is the separate instant store/put-away key (see Jul 2026 entry
  below).

## Non-responsibilities
- **Does not own inventory slot storage itself** — `InventoryManager.gd`
  (`scripts/ui/inventory/`, see `docs/systems/ui/README.md`) holds the actual
  4-slot array; `InteractionSystem` only calls its `activate_item`/
  `deactivate_item`/`add_item`/`remove_item` API.
- **Does not own item pickup/drop physics logic itself** — each item script
  (`PickupItem.gd` base + its subclasses, see `docs/systems/furniture-items/`)
  implements its own `pickup()`/`drop()`/`place()`; `InteractionSystem` only
  calls those methods and tracks which slot/hand an item currently occupies.
- **Does not own HUD rendering** — `InteractionSystem` calls
  `prompt.set_prompts(...)`/`hide_prompt()` and `inventory_hud.set_selected(...)`,
  it never touches Control nodes directly (see `docs/systems/ui/README.md`).
- **Does not own build-mode input** — both `Player._handle_interaction_input()`
  and `InteractionSystem._unhandled_input()` early-return whenever
  `build_mode_active` is true; `BuildModeController` owns all input then.

## Files
| File | Lines | Role |
|---|---|---|
| `Player.gd` | ~120 | `CharacterBody3D` — movement, sprint/stamina, facing, movement-lock |
| `PlayerStats.gd` | ~170 | Survival needs (food/water/sleep/health) + game clock |
| `InteractionSystem.gd` | ~686 | Pickup/drop/store/scroll, interact prompt builder |

## Public API
**`Player`** (`class_name Player`, extends `CharacterBody3D`):
`set_movement_locked(locked: bool)` — used by `PauseMenuUI`/any future
full-screen modal to block WASD/sprint/interact without pausing the
`SceneTree` (grid/generators keep running). Public vars: `stamina: float`
(0–100, read by HUD), `camera_yaw_rad: float` (set every frame by
`MainWorld`/`GameCamera` so input stays camera-relative).

**`PlayerStats`** (`class_name PlayerStats`, extends `Node`):
`replenish_food/water/sleep/health(amount: float)`, `get_time_display() ->
String`, `get_elapsed() -> float` / `set_elapsed(value: float)` (save/load —
see Persistence). Public vars: `food/water/sleep/health: float` (0–100),
`time_multiplier: float` (dev-tool time warp, F12), `current_day: int`.

**`InteractionSystem`** (`class_name InteractionSystem`, extends `Node3D`):
No public methods beyond `_ready()`/input handlers — it's driven entirely by
`_unhandled_input()` and `_process()`. External systems configure it by
setting its public vars directly (no setters): `inventory: Node`
(`InventoryManager` ref), `prompt: Node` (`InteractPrompt` ref),
`inventory_hud: Node`, `shelf_ui: Node`, `build_mode_active: bool`. Public
var `held_item: RigidBody3D` (currently held item, `null` if empty-handed) and
`selected_slot: int` (-1 = none) are read by other systems (e.g. HUD) but
never written externally.

## Signals produced
| File | Signal | Params | Fires when |
|---|---|---|---|
| `Player.gd` | `interacted` | — | Player presses the "interact" action (only used when NOT holding an item — see `InteractionSystem`, which owns the actual E-key logic once an item's in hand) |
| `Player.gd` | `stamina_changed` | `new_value: float` | Every physics frame stamina changes |
| `PlayerStats.gd` | `food_changed` / `water_changed` / `sleep_changed` / `health_changed` | `value: float` | Every `_process()` tick (needs) or on `replenish_*()` |
| `PlayerStats.gd` | `time_changed` | `hour, minute, is_pm, display` | Game clock minute ticks over |
| `PlayerStats.gd` | `day_changed` | `day: int` | Game day rolls over |

`InteractionSystem.gd` produces no signals of its own — it reaches directly
into whatever it's holding (`held_item.knocked_out`, `held_item.picked_up`,
etc.) and calls methods on `prompt`/`inventory_hud` instead of emitting.

## Signals/events consumed
- `InteractionSystem` connects to `detect_area.body_entered/body_exited`
  (its own `Area3D`) to maintain `_tracked_bodies` — the authoritative set of
  nearby interactables (StaticBody3D nodes are tracked separately in
  `_static_in_range` since Jolt's `Area3D` signals never fire for them).
- `InteractionSystem` connects to each held item's `knocked_out` signal
  (`_on_item_knocked_out`) while it's held, to detect the item being yanked
  out of the player's hand (obstruction/distance check owned by the item
  itself, e.g. `WaterBottle.gd`'s `KNOCK_DISTANCE`/`KNOCK_LINGER_TIME`).

## Ownership
None of these three are autoloads. `Player.tscn`'s root node runs
`Player.gd`; `InteractionSystem.gd` is a child node under the player scene
(`@onready var player: CharacterBody3D = get_parent()`). `PlayerStats` is
instantiated/wired by `MainWorld` and found elsewhere via
`get_tree().get_first_node_in_group("player_stats")`.

## Persistence
`PlayerStats.get_elapsed()`/`set_elapsed()` back the `game_elapsed`
`SaveManager` field (see `docs/systems/world-core/README.md`) — saving the
single raw elapsed-seconds float is sufficient; day/hour/minute recompute
automatically next frame. `player_position` is also a registered
`SaveManager` field but its getter/setter live on `MainWorld`, not `Player`
itself. **Not persisted:** stamina, food/water/sleep/health values,
held/inventory item state (tracked gap, not scheduled — see
`docs/systems/world-core/README.md` Known tradeoffs).

## Call graph (brief)
```
Player._physics_process() → _handle_movement() (WASD/sprint/stamina)
                           → _handle_interaction_input() → interacted.emit()
                             (only relevant when InteractionSystem.held_item == null)

InteractionSystem._unhandled_input()
  → scroll wheel  → _scroll_slot(dir) → _put_item_back_to_slot()/_bring_item_to_hand_from_slot()
  → F (pickup)    → _try_pickup() / _quick_drop() / shelf.on_f_interact()
  → E (tap)       → held_item.on_use() / _try_interact() (world objects: generators, breakers, etc.)
                    (fires instantly on press; `_is_holding_e` stays true only
                    to drive per-frame continuous-hold actions like
                    `FuelCan.refuel_tick()` — it no longer gates a store action)
  → G (tap)       → _store_item() / _put_item_back_to_slot() (instant, no hold/progress bar)
InteractionSystem._process() → _update_prompt() → prompt.set_prompts(...)/hide_prompt()

PlayerStats._process() → _tick_needs() → food/water/sleep drain, starvation health drain
                        → _tick_clock() → time_changed/day_changed
```

## Common edits
- **New player stat/need:** add the field + drain rate + signal to
  `PlayerStats.gd` following the `food`/`water`/`sleep` pattern; add a
  `replenish_*()` method; wire `HUD.gd` to the new signal (see
  `docs/systems/ui/README.md`).
- **New item interaction verb (beyond use/store/pickup/drop):** add the input
  branch in `InteractionSystem._unhandled_input()`. E and G are both plain
  one-shot `is_action_pressed()` taps — there is no tap-vs-hold
  disambiguation anymore. If a new verb needs continuous per-frame behavior
  while a key is held (like `FuelCan.refuel_tick()` or `WaterBottle.
  bottle_refill_tick()`), follow the `_is_holding_e` +
  `_tick_continuous_refuel()`/`_tick_continuous_bottle_refill()` pattern
  instead (Jul 2026 — both ticks now run side by side in `_process()`; a
  held item only reacts to whichever tick its own `has_method()` check
  matches).
- **Store/put-away key (Jul 2026):** store is bound to `store_item` (G), not
  E. The old "hold E to store" hold-and-progress-bar mechanic was retired
  entirely in favor of an instant, no-progress-bar G tap — see
  `_store_hold_t`/`_use_pending`/`_tick_store_hold()` removal in the source.
- **New prompt line for an item/object:** implement
  `get_use_prompt()`/`get_interact_prompt()`/`get_f_prompt()`/`get_e_prompt()`
  on the item/object itself (duck-typed via `has_method()`) —
  `InteractionSystem._update_prompt()` already calls these generically, no
  central registry to update.
- **Prompt cap + E-target fix (Jul 2026):** Case 2 (empty-handed) prompts are
  capped at `MAX_VISIBLE_PROMPTS` (3) - candidates are sorted by distance to
  the player first, then sliced to the closest 3, so a crowded room never
  shows more than 3 floating prompts at once. Separately, `_try_interact()`
  now filters BOTH passes (RigidBody3D overlap + StaticBody3D group scan) to
  only consider bodies where `has_method("on_interact")` is true before
  comparing distances. Some items (e.g. `FuelCan`) sit in the `"interactable"`
  group only so their `get_prompt_text()`/`get_use_prompt()` lines show up
  while held - they have no `on_interact()` of their own. Previously they
  could still win the closest-node comparison and silently swallow the E
  press (nothing implements `on_interact()` on the "closest" node -> no
  fallback to the next-closest thing that actually responds). Any new
  interactable-only item that intentionally has no `on_interact()` will
  correctly be skipped and never block E for something further away.

## Forbidden edits
- **Don't let `held_item` bypass the `_held_from_slot` convention.**
  `_held_from_slot == -1` means "picked up fresh from the world" — every
  other piece of pickup/drop/store logic (dual follow-speeds, knockout
  checks, culling) keys off this. A new code path that sets `held_item`
  directly without also setting `_held_from_slot` correctly will desync the
  inventory HUD.
- **Don't add a second global light/stat dimmer or clock driver** — there is
  exactly one `PlayerStats` instance (found via group `"player_stats"|`) and
  one game clock; don't create a second timer elsewhere.

## Known tradeoffs / tech debt
- No automated tests.
- Survival stat/inventory state isn't saved (see Persistence above).
- `InteractionSystem.gd` is a single ~686-line file covering pickup, drop,
  store, scroll, AND prompt-building — a plausible future split candidate
  (e.g. extract prompt-building into its own `_owner`-pattern helper the same
  way `BuildModeController`'s Stage 10 extraction did) but not currently
  scheduled; only split it if a genuinely self-contained new feature needs
  its own file (see repo-wide "no god files" rule in `HANDOVER.md`).

## Extension points
- New item types just need to implement the same duck-typed method surface
  existing items already do (see `docs/systems/furniture-items/README.md`'s
  Public API list) — `InteractionSystem` never special-cases a specific item
  class by name.
- New full-screen modals that should block player input: call
  `Player.set_movement_locked(true/false)` the same way `PauseMenuUI` does,
  and gate `InteractionSystem` the same way `build_mode_active`/`shelf_ui`
  already are (a new `Node`-typed "blocks input" flag if a third modal type
  is ever added, rather than hardcoding a 3rd special case inline).
