# Controller / Gamepad Support (Aug 2026)

The authoritative reference for every gamepad feature in Bunker. Target
input: **Xbox One controller**. All code paths, bindings, tuning constants,
nuances, and known bugs/fixes are documented here for future agents.
Controller-specific behavior is split across the input-mode autoload, the
shared UI navigation component, per-UI wiring, and the build-mode controller.

> **Scope of this doc:** everything gamepad. If a system has controller
> support, it is listed here. `is_controller()` (via `InputMode`) is the
> single "is the player using a gamepad right now?" check used project-wide.

---

## Table of contents

1. [Architecture overview](#architecture-overview)
2. [Autoloads](#autoloads)
3. [Input bindings](#input-bindings)
4. [InputMode — device detection & cursor](#inputmode--device-detection--cursor)
5. [ControllerUINavigation — shared menu navigation](#controlleruinavigation--shared-menu-navigation)
6. [InteractPrompt — icon rendering](#interactprompt--icon-rendering)
7. [Player & world input](#player--world-input)
8. [InteractionSystem gating](#interactionsystem-gating)
9. [Build mode (the big one)](#build-mode-the-big-one)
10. [Per-UI wiring matrix](#per-ui-wiring-matrix)
11. [Known bugs & fixes](#known-bugs--fixes)
12. [Gotchas](#gotchas)
13. [Unfinished / to-do later](#unfinished--to-do-later)
14. [Gamepad tutorial](#gamepad-tutorial)

---

## Architecture overview

- `InputMode` (autoload) — last-input-wins device detection, OS-cursor
  ownership, and the mouse-motion deadzone. **Everywhere that swaps UI for
  controller reads `InputMode.is_controller()`.**
- `FocusMode` (autoload) — focus-mode toggle (Ctrl hold, or right-stick
  click on controller).
- `ControllerUINavigation` (attached per-UI) — d-pad + optional left-stick
  focus navigation, B-close, and slider d-pad support.
- `InteractPrompt` — renders `[E]/[F]/[G]/[Hold E]` tokens as key-caps or
  Xbox icons depending on `InputMode`.
- `BuildModeController` / `BuildModeHUD` — the fully custom build-mode
  controller scheme (cursor, place, rotate, tabs, submenus).
- `InteractionSystem` — gates ALL world input whenever any controller-nav
  UI is open.

---

## Autoloads

| Autoload | File | Role |
|---|---|---|
| `InputMode` | `scripts/core/InputMode.gd` | Last-input-wins device tracking, OS-cursor hiding, mouse-motion deadzone. `is_controller()`/`is_keyboard()`. |
| `FocusMode` | `scripts/core/FocusMode.gd` | Focus-mode toggle (Ctrl hold, or right-stick click). Replaces the old `Input.is_key_pressed(KEY_CTRL)` checks in `InteractionSystem.gd`. |

---

## Input bindings

`project.godot` defines the keyboard defaults + the joypad events. Because
the editor rewrites `project.godot` from memory and can silently drop
hand-added joypad events, **`Player._ensure_joypad_bindings()` re-adds every
controller binding idempotently at boot** (`scripts/player/Player.gd:305`).

| Action | Keyboard | Controller |
|---|---|---|
| `move_*` | WASD | Left stick |
| `sprint` | Shift (hold) | L3 click (hold or latch — see below) |
| `interact` | E | A |
| `pickup` | F | X |
| `store_item` | G | Y |
| `inv_cycle_next` | wheel up | d-pad right |
| `inv_cycle_prev` | wheel down | d-pad left |
| `inv_slot_1` | 1 | d-pad up |
| `inv_slot_3` | 3 | d-pad down |
| `aim_*` | mouse | Right stick (axes 2/3) |
| pause | ESC | **Start button** (`JOY_BUTTON_START`, wired in `MainWorld._unhandled_input`) |

`ui_accept` / `ui_cancel` deliberately have **no** joypad bindings in
`project.godot` — `ControllerUINavigation` adds A/B at runtime so keyboard
Enter/Esc and controller A/B coexist without double-firing.

**Unbound:** `JOY_BUTTON_SELECT` (see [Unfinished](#unfinished--to-do-later)).

---

## InputMode — device detection & cursor

`scripts/core/InputMode.gd`. **Last-input-wins.** Joypad button/motion
events → controller mode; key / mouse-button events → mouse mode; mouse
MOTION is handled specially (below).

### Mouse-motion deadzone

A tiny accidental mouse nudge while using the controller must not flip the
mode (it used to flap every prompt + cursor). Motion events with
`relative < MOUSE_MOTION_MIN_PX (1.0)` are ignored entirely; the rest
accumulate over a `MOUSE_MOTION_WINDOW_SEC (0.25s)` window, and only
crossing `MOUSE_MOTION_THRESHOLD_PX (4.0)` within it — a deliberate move —
flips to mouse mode. A mouse **button** or **key** press still flips
immediately. Joypad input clears the accumulator.

### Build-mode warp suppression

`set_suppress_mouse_motion(bool)` — while the build-mode controller cursor
is warping the OS mouse on behalf of the right stick, mouse-MOTION events
are ignored for mode-flipping. **Required** because `Input.warp_mouse()`
emits *real* mouse-motion events; without this the mode flaps
controller↔mouse every frame. A real mouse button or key still flips.

### OS cursor ownership

`InputMode._process()` hides the OS cursor (`MOUSE_MODE_HIDDEN`) whenever a
controller is the active device — this overrides the `MOUSE_MODE_VISIBLE`
every UI sets on open, so no system cursor appears over any menu in
controller mode. The previous mode is stashed and restored **once** when the
player switches back to mouse/keyboard (so a UI cursor reappears where it
was). Build mode draws its own crosshair and also hides the OS cursor.

---

## ControllerUINavigation — shared menu navigation

`scripts/ui/common/ControllerUINavigation.gd`. Attach as a child of any
Control/CanvasLayer UI (`ui_root = self`) to get gamepad navigation.

- **d-pad:** moves focus one cardinal step per press.
- **Left stick** (opt-in `stick_navigation = true`): analog "best guess"
  focus movement with repeat-while-held. Defaults **off** for in-game UIs
  (the stick stays reserved for movement) and is **on** for menus where
  movement is locked (character creation, pause, admin, graphics settings).
- **A (`ui_accept`):** activates the focused button (bound at runtime).
- **B (`ui_cancel`):** closes this UI, **topmost-aware** — only the topmost
  open controller UI closes, so stacked UIs (pause → settings) cancel one at
  a time. `close_on_cancel = false` for UIs that must not close on B
  (character creation).
- Registers in the `controller_ui_nav` group while its `ui_root` is visible
  (via the public `is_active()`). **`InteractionSystem` uses this group to
  gate all world input while any controller-nav UI is open.**

### Focus movement algorithm (nearest-ahead)

`_move_focus(dir)` — the closest candidate **in the pressed direction**
wins: forward distance (`along`, the projection onto the pressed axis) is
the **primary** key; horizontal offset (`perp`) only breaks exact ties.
Candidates must lie within `MIN_DIR_DOT (0.3)` of the pressed direction.
This keeps vertical lists (e.g. graphics settings' stacked option rows)
stepping **exactly one row at a time** even when controls sit at different
X positions (wide OptionButtons vs narrow CheckBoxes), while bottom-row
buttons (e.g. priority `◄`/`►`) still land on the **nearest** button above
instead of leaping to a far-away vertically-aligned one. First press with
no focus accepts anything in the general direction and falls back to the
first focusable.

### Slider d-pad support (flow rate, etc.)

A focused `Slider` **owns horizontal d-pad**: left/right adjusts the value
by `slider.step` per press (`_adjust_focused_slider`, step falls back to 1.0
if 0). d-pad up/down still moves focus away. Vertical lists keep working.

**Hold-repeat with acceleration** (`_tick_slider_repeat`), polled per-frame
while a direction is held on a focused slider:

| Constant | Value | Meaning |
|---|---|---|
| `SLIDER_HOLD_DELAY` | 1.0 s | nothing extra during the first second of holding (the initial press already stepped once) |
| `SLIDER_START_INTERVAL` | 0.2 s | ~5 steps/sec when repeat kicks in |
| `SLIDER_MIN_INTERVAL` | 0.01 s | 100 steps/sec max |
| `SLIDER_RAMP_TIME` | 3.0 s | holding time to ramp from start → min interval |
| `SLIDER_REPEAT_MAX_STEP_MULT` | 500.0 | each repeat's step also ramps 1× → 500× slider step |

So the water-dispenser flow-rate slider (step = 1 mL/day) ramps both the
repeat **rate** (up to 100/sec) and each repeat's **step** (up to 500
mL/day), letting a player sweep the full 3000 mL/day range in ~2s of holding.

### `is_active()`

Public wrapper over the internal visibility check (`ui_root` in-tree +
visible) — other systems ask "is this UI open?" via it (e.g.
`InteractionSystem._any_controller_ui_open`).

---

## InteractPrompt — icon rendering

`scripts/ui/hud/InteractPrompt.gd`. `_prompt_to_bbcode()` converts a prompt
string like `[F] Pick up Flashlight` into BBCode, replacing key tokens with
inline icons based on `InputMode.is_controller()`. Everything else passes
through verbatim (the label keeps parsing its own BBCode).

- **Tokens:** `[E]`, `[F]`, `[G]`, `[0-9]`, and **`[Hold X]`** (e.g.
  `[Hold E] Refill Bottle` — the water-bottle refill and fuel-can refuel
  prompts). `[Hold X]` renders as `Hold <icon>`.
- **Mapping:** controller `E→XBOX_A`, `F→XBOX_X`, `G→XBOX_Y`; keyboard
  `E/F/G/0-9` key-caps. `XBOX_BUTTONS` / `KEY_CAPS` consts in
  `InteractPrompt.gd:46-55`.
- **Icons:** `assets/ui/prompts/*.png` (0-9, E/F/G, XBOX_A/B/X/Y/LB/RB), 16px.
- The token matcher is strict (`[word key]` shape only) so BBCode tags
  (`[color=…]`, `[/img]`, …) never collide.

---

## Player & world input

`scripts/player/Player.gd` + `InteractionSystem.gd`.

- **Movement:** left stick (`move_*`). Right-stick facing eases the model
  toward the stick direction via `lerp_angle` (`TURN_SMOOTH_SPEED = 12.0`),
  falling back to movement direction when idle.
- **Sprint:** L3 click — hold to run, or **click to latch** running while
  moving (`_sprint_toggle`, auto-clears on stop/exhaustion or another click).
- **Interact / use:** A (`interact`). Instant tap. Using a held item is
  select-with-d-pad then A.
- **Pickup / drop / shelf-place:** X (`pickup`).
- **Store:** Y (`store_item`).
- **Inventory:** d-pad right/left cycle the selected slot; d-pad up/down
  jump to slots 1/3. Items stay in-slot while held.
- **Focus mode:** right-stick click (`JOY_BUTTON_RIGHT_STICK`) toggles.
- **Sit:** A on a chair (via `interact`).
- **Look-steer in build mode is DISABLED** — `Player._build_mode_active()`
  reads `InteractionSystem.build_mode_active` and gates aim-steer so the
  right stick is free to drive the build cursor.

---

## InteractionSystem gating

`InteractionSystem._unhandled_input()` returns immediately (all world
input) when:

1. build mode is active (`build_mode_active`), **or**
2. **any controller-nav UI is open** (`_any_controller_ui_open()` scans the
   `controller_ui_nav` group), **or**
3. a known per-UI ref is open (`_shelf_ui_open()` / `_basket_ui_open()` /
   `_research_ui_open()` / `_npc_ui_open()`).

The same gate hides the interaction prompt. **This is what keeps A owned by
the open UI** — a press with nothing focused can never fall through to the
world interact and pop open a *different* UI near the player. The gate
clears when the UI closes (exit button, B, or walk-away proximity close —
all hide the ui_root, de-registering the nav).

---

## Build mode (the big one)

Owned by `BuildModeController` (world) + `BuildModeHUD` (UI). The controller
scheme is fully custom — the shared nav does NOT drive build mode.

### Right-stick cursor

`_update_controller_cursor()` reads the **raw** right-stick axes
(bypassing the action deadzone), applies a radial deadzone, smooths, and
warps the OS mouse so every raycast/hover helper follows.

| Constant | Value | Meaning |
|---|---|---|
| `CURSOR_DEADZONE` | 0.2 | radial deadzone; below = idle, above = re-normalized with a smooth ramp (no jump at the edge) |
| `CURSOR_SMOOTH` | 12.0 | exponential smoothing rate (1/s) on the aim — kills jitter |
| `CURSOR_MAX_SPEED` | 0.55 | cursor speed at full deflection, fraction of viewport height/sec |
| quadratic curve | `speed = MAX × aim²` | light pushes = fine control, full deflection = fast |

The cursor snaps to zero the instant the stick returns to the deadzone
(no release-linger/drift). While driving, `InputMode` mouse-motion
mode-flipping is suppressed (see [InputMode](#inputmode--device-detection--cursor)).
`BuildModeHUD` hides the OS cursor and draws its own crosshair.

### Buttons

| Input | Action |
|---|---|
| **A** | Left-click at the cursor: place ghost, place a wall/wire/pipe segment, deconstruct/duplicate/move the object under the cursor. If a submenu is open, selects the highlighted item. If the cursor is over a toolbar tab, clicks that tab. Near the Build Station, **exits build mode** (see below). |
| **B** | Active placement → cancel it (and restore the submenu that launched it). Open submenu → back **one level** (`_submenu_back`: items → root; root → close). Wire/pipe → `cancel_placement()` — cancels the in-progress draw but **stays on the Wire/Pipe tab**. |
| **LB / RB or d-pad L/R** | Cycle toolbar tabs and **auto-select** the tool (`_change_selected_tool`) — the old tool's ghost/draw is cancelled and the new tool activates immediately, no A needed. Menu tabs follow: scrolling onto one reopens ITS menu if a menu was already open; a closed menu stays closed until A opens it. |
| **d-pad U/D** | Scroll the open submenu (moves the selection cursor). |
| **LT / RT** | Rotate the placement ghost CCW/CW once per press (triggers report as axes, `TRIGGER_THRESHOLD = 0.5`, edge-detected in `_process`). |
| **Start** | Pause (see [Player & world input](#player--world-input)). |

### Toolbar & submenus

`TOOL_LABELS`: Construct(0) / Deconstruct(1) / Duplicate(2) / Move(3) /
Undo(4) / Wire(5) / Pipe(6) / Shop(7). Menu-tabs = Construct + Shop. A
controller-mode white outline marks the d-pad-selected tab; LB/RB cycle
badges show on the first/last tabs. The HUD A branch blocks tabs while a
placement/draw is active (walls too — `_wall_draw_active` is synced to the
HUD via `set_wall_draw_active`, since walls have no ghost).

### Rock-dig confirm dialog

d-pad L/R toggles YES/NO (`_dig_confirm_selection`, defaults YES), A
confirms the highlighted choice, B cancels (= NO). A white outline marks the
selected button in controller mode. All paths (mouse/ESC/controller) share
`_resolve_dig_choice()`.

### "Exit Build Mode" prompt

The Build Station shows `[E] Close Build Mode` (A icon on controller) while
the player is within `BUILD_STATION_EXIT_REACH (2.5 m)`. **A ALWAYS exits
build mode when in reach** — it takes priority over every other A action
(placement, drawing, tab clicks, menus). The controller's input handler
checks proximity first, and the HUD is told via `set_exit_available(true)`
each frame so its A branch lets the press fall through. (The dig-confirm
dialog still takes precedence while open.)

### HUD state sync

`BuildModeController` → `BuildModeHUD`: `set_ghost_active`, `set_wall_draw_active`,
`set_exit_available`, `set_active_tool`. The HUD's A branch uses these to
decide whether A places/blocks-tabs or falls through to the controller.

---

## Per-UI wiring matrix

| UI | Notes |
|---|---|
| Character creation | Nav (`close_on_cancel=false`, `stick_navigation=true`); right-stick orbits/pans the preview; A confirms; swatch buttons navigable. Name field is keyboard-only (see unfinished). |
| Pause menu | **Start button opens it** (and toggles); nav with `stick_navigation=true` (movement locked while paused); B closes; submenus stack on top and close one-at-a-time. |
| Admin / Graphics settings | Nav + `stick_navigation=true`, B close. Vertical option rows step one row per d-pad press (nearest-ahead). |
| NPC talk | Nav; **Talk auto-focused on open**; requests/jobs/ask-about sub-boxes revealed by Talk become focusable. `InteractionSystem` gated (see above). |
| Farming tray | Nav + B close. |
| Power (terminal / priority / zone customize / generator inspect) | Nav + B close; priority panel proximity-closes. |
| Water (dispenser / info) | Nav + B close. **Flow-rate slider is selectable**; d-pad L/R adjusts by 1 mL/day with hold-repeat acceleration (see [ControllerUINavigation](#controlleruinavigation--shared-menu-navigation)). Grabber circle gains a white outline while hovered (mouse) or focused (controller). |
| Confirm dialog | Nav + B close. |
| Storage | Slot selection (white outlines), A carry / Y store, A/Y badges. |
| Research station | D-pad/right-stick navigation with left-stick movement retained; the real Water Hookup Output node is selected on open; LB/RB cycle tabs; A/Enter activate the focused node or research action; scrollbars remain selectable. |
| Build mode | Full custom scheme (see above). |

Badge/highlight convention: controller selection indicators are white
outlines; `TAB_BADGE_SIZE`/`TOOL_BADGE_SIZE = 20`.

---

## Known bugs & fixes

These were real runtime errors/behaviors — documented so they are never
re-introduced.

- **`Player.get_held_item()` freed-instance crash.** A held item freed
  outside the normal drop/give cleanup left `held_item` dangling. Fixes:
  read the field into an **untyped** local (a typed `var x: Node = held_item`
  throws on a dead ref *before* any guard can run) and gate on
  **`is_instance_valid()` alone** (`item != null` is NOT reliable — a freed
  ref can compare equal to null in Godot 4). `Player.gd:227`.
- **`on_use()` freeing a held item.** Consumables (`queue_free()` their
  own node when depleted). `queue_free()` defers the free to end-of-frame,
  so `is_instance_valid()` alone was still true right after `on_use()`.
  Fixed with `held_item.is_queued_for_deletion()` and — critically —
  **clearing the inventory slot** (`inventory.clear_slot(_held_from_slot)`),
  because items stay in-slot while held. `InteractionSystem.gd:341`.
- **Inventory slot dangling ref → `ItemPreviewKit.set_item` crash.** A
  consumed item left its slot pointing at a freed node; the next
  `inventory_changed` fed the dead ref to the typed `set_item`. Fixed at the
  source (clear_slot) and defended in `InventoryHUD._set_preview` (only pass
  null or `is_instance_valid` items to `set_item`).
- **`UIKit.make_button` null callable.** `ResearchStationUI` builds a
  button with `Callable()` and attaches the real handler later; `make_button`
  now skips connecting when `cb.is_null()`.
- **InputMode mode-flapping.** Two causes: (1) build-mode `warp_mouse`
  emitting real motion events → fixed with `set_suppress_mouse_motion`;
  (2) any sub-pixel mouse jitter flipping the mode → fixed with the
  mouse-motion deadzone (see [InputMode](#inputmode--device-detection--cursor)).
- **`is_hovered()` not on `HSlider`.** The flow-rate grabber hover state is
  tracked via `mouse_entered`/`mouse_exited` on `WaterDispenserUI`
  (`_slider_hovered` flag) — do not call `is_hovered()` on a slider.
- **`[Hold E]` prompt never swapped icons.** The token matcher only handled
  `[X]`; extended to `[Hold X]` (`[<action> X]`) rendering as
  `Hold <icon>`.
- **Wire/pipe B jumped to Construct.** B in a draw mode deactivated it AND
  returned to a construct ghost. Now B calls `cancel_placement()` — cancels
  the in-progress draw but stays on the Wire/Pipe tab.
- **Pause had no Start button / stick nav.** `JOY_BUTTON_START` now toggles
  pause; `stick_navigation=true` was added to Pause/Admin/Graphics navs
  (their comments already claimed it, it was never enabled).

---

## Gotchas

- **Freed refs compare `== null` in Godot 4.** Never use `x != null` to
  detect a dangling reference — always `is_instance_valid(x)`. This burned
  us twice (Player.get_held_item, InventoryHUD previews).
- **`queue_free()` defers.** Check `is_queued_for_deletion()` when you need
  to react to a pending free in the same frame (held-item consume path).
- **`Input.warp_mouse()` emits real motion events.** Any warp must be
  paired with `InputMode.set_suppress_mouse_motion(true)` while active, or
  the mode flaps.
- **CanvasLayer is NOT a CanvasItem** — no `is_visible_in_tree()`; use
  `.visible` (see `ControllerUINavigation._node_visible`).
- **`ui_accept`/`ui_cancel` have no joypad bindings in project.godot** —
  `ControllerUINavigation` adds A/B at runtime; Player's
  `_ensure_joypad_bindings` re-adds the rest at boot (project.godot rewrites
  can drop hand-added events).
- **A CollisionShape3D must be a DIRECT child** of its CollisionObject3D
  (nested under a plain Node3D it doesn't register with the physics server).
- **Triggers report as AXES** (0..1), not buttons — poll with edge
  detection for once-per-press actions (build rotate).
- **The left stick is consumed by nav `_input`** when `stick_navigation` is
  on — enable it only for UIs where movement is locked.

---

## Unfinished / to-do later

- **Battery/breaker inspectors (September 2026):** now extracted native panels
  with D-pad/A/B navigation, movement retained, and shared walk-away closing.
  See `scripts/ui/README.md`. Farming seed dropdowns suspend only the panel's
  nav input processing while their native popup owns input; the world gate
  remains active.
- **"Select" button** (`JOY_BUTTON_SELECT`) is **unbound** — candidate for a
  Player-stats panel. Not yet implemented.
- **PowerTerminalUI per-row priority arrows** are drawn glyphs with mouse
  hit-tests, not focusable controls — controller users cannot adjust
  priority from the terminal list (use the per-device PowerPriorityUI, whose
  `◄`/`►` ARE controller-navigable).
- **NPC talk panel height** (900px + expansions) can overflow small windows;
  sub-buttons remain d-pad reachable but may be off-screen. Scroll container
  is a future polish.
- **Character-creation name field** is keyboard-only (no on-screen keyboard).

---

## Gamepad tutorial

A separate developer-facing tutorial script + build notes for onboarding a
brand-new controller-only player lives in
[`docs/tutorials/GamepadTutorial.md`](../tutorials/GamepadTutorial.md).
