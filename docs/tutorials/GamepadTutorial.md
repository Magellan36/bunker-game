# Gamepad Tutorial (ROUGH DRAFT)

A developer-facing tutorial **script** + **build notes** for onboarding a
brand-new player who is using a **controller only** (Xbox One layout). The
tutorial *wiring* is future work — this doc is the text, structure, and the
controller-specific implementation notes that whoever builds the tutorial
needs.

Target input: Xbox One controller. Every button reference below assumes the
Xbox mapping (`A`, `X`, `Y`, `B`, `LB/RB`, `LT/RT`, d-pad, left/right stick,
`Start`). Where keyboard differs it is noted, but this tutorial assumes a
controller-only player and should never ask for a keyboard key.

The authoritative technical reference for every mechanic below is
[`docs/systems/controller/README.md`](../systems/controller/README.md) — read
it before wiring any of this. This doc is the *tutorial presentation* of the
same systems.

---

## 1. How to read this doc

- **Player-facing copy** — italic blockquotes: the literal text a new player
  should read/see at that moment.
- **Build notes** — `B:` bullets: how to wire it, controller gotchas, which
  system/file owns the behavior, tuning knobs.
- Sections are ordered to teach one mechanic at a time, in the order a real
  player would naturally encounter them. Each section should be a short,
  isolated "do this, feel that" beat — one skill per beat, no information
  dumping.

---

## 2. The Controls Reference (opening screen)

Show a full controller map the instant the game starts (pausable/always
available later from the pause menu):

> *LEFT STICK — Move*
> *RIGHT STICK — Look / Aim*
> *A — Interact / Use*
> *X — Pick up / Put down*
> *Y — Store in backpack*
> *D-PAD — Change selected item*
> *B — Back / Cancel*
> *L3 (click left stick) — Run*
> *R3 (click right stick) — Focus target*
> *LB / RB — (menus) switch tabs*
> *LT / RT — (build) rotate*
> *START — Pause*

**B:** Render this with the real prompt icons
(`assets/ui/prompts/XBOX_*.png`, see `InteractPrompt`) so what the player
sees here matches every in-world prompt exactly. Build this screen in a
controller-nav UI (`ControllerUINavigation`, `stick_navigation=true`). The
tutorial should hold this screen until the player presses any button; note
in the build that `InputMode` is what swaps "which icon shows" everywhere —
the tutorial must not hardcode an input device.

---

## 3. Movement (left stick)

> *Walk into the light. Push the left stick to move — the way you push is
> the way you go.*

**B:** Straightforward — `move_*` actions on the left stick
(`Player._handle_movement`). The camera follows/faces with the right stick;
the model eases toward the right-stick direction when you push it
(`TURN_SMOOTH_SPEED`). Teach facing AFTER movement in the same beat: push
the right stick to turn the character in place. Do not mention keyboard.

---

## 4. Sprint (L3)

> *Click the LEFT STICK to run. Click it again to stop.*

**B:** Two ways exist and the tutorial should teach both subtly:
- **Hold** L3 to run while moving (hold-to-sprint).
- **Click** L3 once to *latch* running while moving; it auto-clears when you
  stop or run out of stamina, or when clicked again (`_sprint_toggle`).
The tutorial should say "click to run" and let the player discover the latch
feels like a toggle. `R3` is reserved for Focus mode — do not confuse the
two stick clicks in the copy.

---

## 5. First interact + item use (A)

Place a WaterBottle on the ground in front of the player.

> *Press A to pick up the bottle.*
> *Now press A again to take a sip.*

**B:** A = `interact` = "use held item / world interact" — a single press
covers both pickup and use depending on context (`InteractionSystem`).
Items stay in their inventory slot even while held; the HUD bar shows them.
This is the cleanest first beat because it teaches that **A does "the thing
in front of you"** — context-sensitive, instant. The prompt above the bottle
shows `[A] Pick up  Water Bottle` (the `[E]` token renders as the A icon in
controller mode).

---

## 6. Inventory & the backpack (d-pad, Y)

> *You have 4 backpack slots at the bottom of the screen. Press D-PAD
> LEFT / RIGHT to change which item you're holding. Press Y to put the item
> away, then press A near the shelf to drop it.*

**B:** 
- d-pad right/left cycles the selected slot (`inv_cycle_next/prev`);
  d-pad up/down jumps to slots 1/3 (`inv_slot_1`/`inv_slot_3`).
- X = pickup/drop; Y = store to the backpack; A = use. The white selection
  outline on the HUD bar tracks the selected slot (`InventoryHUD`).
- Teach this with a shelf: A near a shelf opens the storage UI (see §8);
  Y stores; X drops to the floor.

---

## 7. Eating & drinking (select slot + A)

> *Select your Food Can with the D-PAD, then press A to eat it.*

**B:** The player must *select* the slot first (d-pad) then *use* (A).
Consumables deplete and free themselves — the slot auto-clears
(`InteractionSystem` clear_slot fix). The tutorial should make the player
eat and drink so they see the needs bars respond, but keep it short — this
is a "feel it once" beat.

---

## 8. Storage UI (A, Y, B)

Open a shelf near the player.

> *Press A to open the shelf.*
> *Press Y to carry an item. Press Y again to put it back. Press B to close.*

**B:** `StorageUI` is a controller-nav UI. Items/slots are selectable with
white outlines; A carry, Y store. **B always closes the UI** (topmost-aware
nav). The tutorial must teach that **while a UI is open, the controller
belongs to that UI** — A/Y/B do UI things, not world things; world input is
gated (`InteractionSystem._any_controller_ui_open`). This is a key mental
model to establish early: *menus swallow the pad until you close them.*

---

## 9. The pause menu (START)

> *Press START to open the Pause menu. Move with the D-PAD or LEFT STICK.
> Press B to close it.*

**B:** `Start` toggles the pause menu (`MainWorld._unhandled_input`);
ESC does the same on keyboard. The pause menu nav has `stick_navigation=true`
(left stick navigates; safe because movement is locked while paused). Teach
that the pause menu is the anchor for Settings and Admin (both also
stick/d-pad navigable, stacked one-at-a-time). The player should learn early
where Settings lives for the rest of the tutorial (e.g. if they want to
adjust graphics).

---

## 10. Power / water / farming UIs (d-pad, sliders)

Open a water dispenser.

> *Press A to open the dispenser. Use the D-PAD to move between options.
> When FLOW RATE is selected, press D-PAD LEFT / RIGHT to change it by 1.
> Hold the D-PAD to keep changing it — it speeds up.*

**B:** This is the slider mechanic — unique to gamepad. A focused slider
owns horizontal d-pad (`ControllerUINavigation` slider support); hold for
>1s to auto-repeat with acceleration up to 100 steps/sec, and the step
itself grows up to 500 mL/day so the full 3000 mL/day range is quick. The
grabber circle gets a white outline when selected. The tutorial should make
the player set a specific value (e.g. "set the flow rate to 500") so they
experience the hold-to-accelerate. Same nav pattern for power panels,
farming tray, etc. — the d-pad moves focus, A activates, B closes.

---

## 11. Research station (LB/RB tabs, auto-select)

> *Press A to open the Research Station. The top research is already
> selected — press A to start it. Press LB / RB to switch tabs; the top
> option on each tab is selected automatically.*

**B:** `ResearchStationUI` auto-selects the top-most research on open and on
every tab change, so A is immediately ready. LB/RB cycle tabs. This beat
teaches the **LB/RB = switch tabs** convention that carries into the build
mode toolbar.

---

## 12. NPC talk (d-pad, A)

> *Press A to talk to the resident. Move through the options with the
> D-PAD. Talk opens their requests — pick one and press A.*

**B:** `NPCTalkMenuUI` auto-focuses **Talk** on open; Talk reveals the
Requests/Jobs/Ask-About sub-boxes which then become d-pad focusable. While
the talk UI is open, the pad is owned by it (gated). B closes. This is the
first "conversation tree" beat — keep it linear (one NPC, one request).

---

## 13. Build mode (the centerpiece)

Enter build mode. **This is the longest section and must be broken into
micro-beats** — do not dump the whole scheme at once.

### 13.1 Entering & the cursor

> *Press A on the Build Station to enter Build Mode. Move the cursor with
> the RIGHT STICK. The white crosshair follows your stick — that's your
> cursor.*

**B:** Entering build mode is `interact` (A) on the Build Station. The
right-stick cursor is the game's **only** cursor in build mode (the OS
cursor is hidden; `BuildModeHUD` draws the crosshair). Teach the analog feel
first: light push = fine movement, hard push = fast (quadratic curve). The
right stick does NOT look around in build mode — it drives the cursor.

### 13.2 Placing an object

> *Move the cursor over the floor. Press A to place.*

**B:** A = left-click at the cursor (place ghost / confirm). The ghost
tints green/red for valid/invalid. This is the core "point + A" loop.

### 13.3 Rotating (LT/RT)

> *Press LT or RT to rotate the object before you place it.*

**B:** LT/RT rotate the ghost CW/CCW once per press, only while a ghost is
active. Teach rotate-before-place explicitly — it's a two-button combo new
players won't guess.

### 13.4 The toolbar & tabs (LB/RB, d-pad)

> *Press LB or RB to cycle the tools at the bottom — Deconstruct,
> Duplicate, Move, Wire, Pipe, Shop. The tool you land on is selected
> immediately.*

**B:** Cycling **auto-selects** the tool — the old tool's ghost/draw is
cancelled, the new one activates. No confirm needed. Construct/Shop open
their submenus; d-pad U/D scrolls a submenu, A picks.

### 13.5 Deconstruct / Duplicate / Move

> *Select DECONSTRUCT, point at an object, press A. Select MOVE, press A on
> an object, then A again where you want it.*

**B:** Deconstruct/duplicate/move all operate on the object under the
cursor with A. Move is a two-press flow (pick up, confirm spot) — teach it
with a single object so the player sees both presses.

### 13.6 Wire & Pipe (B cancels, stays on tab)

> *Select WIRE. Press A on one connection point, then A on another to draw a
> wire. Press B to cancel a wire you started — you'll stay on the Wire tool.*

**B:** Wire/Pipe draw segment-per-click. **B cancels the in-progress draw
but stays on the Wire/Pipe tab** (`cancel_placement`) — a deliberate
departure from "B backs out to Construct". Teach this explicitly so the
player doesn't expect B to leave the tool.

### 13.7 Walls

> *Select CONSTRUCT, pick a wall, then press A and drag with the RIGHT
> STICK to draw a wall run. Release and press A again to build it.*

**B:** Walls are a drag-draw (A + stick). While drawing, the tabs are
blocked (A places, not clicks). This is the most complex single mechanic —
give it its own beat and an open area.

### 13.8 The Shop

> *Select SHOP. Pick what you want to buy and press A.*

**B:** Shop (Farming tab) purchases spawn items near the player — no ghost.
The menu stays open so the player can buy several things; B walks back one
level at a time (items → root), then closes.

### 13.9 Expanding the bunker (rock dig)

> *Point at a rock face and choose to expand the bunker. It costs $1,500.
> Press A to confirm, or B to back out.*

**B:** The confirm dialog is d-pad L/R to select YES/NO, A to confirm. The
default is YES.

### 13.10 Exiting build mode

> *Stand next to the Build Station and press A to leave Build Mode.*

**B:** Near the station, **A ALWAYS exits build mode** — even mid-placement
or with a menu open. This overrides every other A action in reach. The
prompt `[A] Close Build Mode` shows above the station. End the build-mode
tutorial here so the player's last build-mode memory is "A near the station
exits".

---

## 14. General build notes for the tutorial wiring

- **Never ask for a keyboard key.** Everything must be expressible with the
  controller. If a tutorial step needs something controller can't do yet
  (e.g. typing a name in character creation), skip or auto-skip that step.
- **Gate each beat on the actual mechanic**, not on fake state. Use the same
  signals/state the game already tracks (e.g. "item stored in slot" for §6,
  "wire placed" for §13.6) so the tutorial can't desync from reality.
- **The pad belongs to whatever UI is open.** Reinforce this at every UI
  beat: while a menu is open, A/B/d-pad do menu things; world input is
  gated. It's the single most important mental model for controller players
  in this game.
- **Progress prompts use `InteractPrompt` tokens** (`[E]`/`[F]`/`[G]`/
  `[Hold E]`) so the icons match the active device automatically. Never
  hand-draw a button label.
- **The tutorial system itself should be a controller-nav UI**
  (`ControllerUINavigation`, `stick_navigation=true`, `close_on_cancel` per
  section) so the player can navigate tutorial text with the same controls
  they're learning.
- **Pause must always work** during the tutorial (`Start`) — it's the
  escape hatch if the player gets lost.
- **Revisit `docs/systems/controller/README.md`** for exact constants,
  files, and known bugs before changing any behavior the tutorial teaches —
  several sections describe intentional tuning (cursor deadzone/smoothness,
  slider hold-repeat ramp, build-mode B/stay-on-tab).

---

## 15. Suggested beat order (summary)

1. Controls reference (idle screen)
2. Movement + facing
3. Sprint (L3)
4. Pickup + use (A) — water bottle
5. Inventory + backpack (d-pad, Y)
6. Eat / drink (select + A)
7. Storage UI (A, Y, B) — *establish "pad belongs to the open UI"*
8. Pause (START)
9. Water dispenser (sliders + hold-repeat)
10. Research station (LB/RB tabs + auto-select)
11. NPC talk (d-pad + Talk)
12. Build mode (13.1–13.10, micro-beats)
13. Short "you did it" outro with a recap of the full controls map