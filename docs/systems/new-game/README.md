# New Game: survivor selection

## Purpose

The only way (besides dev tools) to start with residents. After **New Game →
Your survivor → Begin** and the loading screen, the bunker stays hidden
behind black while the player picks **up to three of six** randomized
survivors. Confirm → "Survivors will join when the apocalypse begins." →
the black lifts on Day 1 with the chosen residents standing in front of the
player. Picking nobody is allowed.

## Flow

1. `SurvivorScreen` (character creation) **Begin** sets
   `WorldManager.pending_new_game = true`. Nothing else sets it, so
   Continue/Load (`pending_load_slot`) and every other route are unaffected.
2. `LoadingScreen._finish_world_startup()` consumes the flag. Its text fades
   out (0.3 s) while its dark field stays, then `_hand_to_survivor_select()`
   adds `SurvivorSelectScreen` (CanvasLayer 1001). That screen paints black
   over everything (0.35 s) and the world is handed over beneath it.
3. **The world is paused** for the whole screen (`get_tree().paused`). The
   screen and its portraits run `PROCESS_MODE_ALWAYS`; the clock doesn't
   start until the reveal. If the screen is freed early (quit, tests) it
   unpauses in `_exit_tree`.
4. **Confirm**: `spawn_selected()` adds the chosen residents (see below). The
   content fades (0.3 s), the message fades in **quickly (0.45 s)**, holds
   1.7 s, fades out **slightly slower (0.6 s)**, the tree unpauses, and the
   black lifts over 1.1 s. Reduced motion makes every fade instant but keeps
   the hold, so the message is still readable.

## Screen (archetype D, `docs/ui/QUIET_DESIGN_SYSTEM.md`)

- Pure black. Left column: `NEW GAME` eyebrow, "Choose survivors" (40 px), a
  brass rule that draws in, "Select up to three.", and a live
  "N of 3 selected" counter.
- A 3×2 grid of `Q.tile` toggle cards, centred in the space right of the
  column. Each card holds:
  - **Portrait** (`SurvivorPortrait.gd`): the real Adventurer body in a
    private studio (warm key, cool rim, as the item previews), framed
    head-and-shoulders on the skeleton's Head bone. Focus or selection warms
    the key and turns the survivor slightly towards the player.
  - Name (MUTED → TEXT when focused/selected), a "Selected" caption in
    ACCENT (its space is always reserved so nothing shifts), and "Age N".
  - **Traits**: every trait the survivor has gets a chip. **One** chip shows
    its word; the others are blank, greyed chips: present, but not known.
- At three picks the other cards grey out (disabled, 32% opacity).
  Deselecting re-enables them.
- **Estimate line** under the grid (exact copy from Brannon), updated live
  for the picked survivors + the player:
  "Current bunker population would consume X cans of food and X bottles of
  water a day, on average." The 1-in-10 variant appends " This is not
  mandatory." It's rolled once each time the screen opens.
- **Confirm** is the one primary action. Key hints: `ENTER Select` (A on a
  controller). Hover moves focus with a mouse; keyboard and controller
  navigate the grid natively (`ControllerUINavigation`).
- Layout scales with `min(h/1080, w/1920·1.15)` clamped 0.66–1.4. Portraits
  take whatever height remains after the text block (12 px floors), and
  cards clip, so 720p never spills.

## Data (`SurvivorDraft.gd`)

- Candidates are rolled with **NPC.gd's own** `randomize_personality()` and
  `randomize_age()` on a detached NPC, so ages and traits follow the NPC
  system's distribution. Names are distinct (from `NPC.NPC_NAMES`), gender
  is random, and every candidate has at least one trait word to reveal
  (`get_personality_words()`, passions included).
- A chosen candidate becomes a save dictionary for `NPC.apply_save_dict()`
  (name, seed, age, gender, personality). The resident is spawned with the
  NPC system's own restore path, so they are exactly who was on the card;
  everything else (needs, skills, relationships) is a fresh resident's.
- Spawn: about 2.3 m in front of the player, 1.3 m apart, snapped to the
  navmesh, facing the player.
- **Consumption** is read live from the constants, so it stays right if they
  are rebalanced. Per person per day:
  - Hunger 1.39/h × 24 ÷ 25 per can (2 bites × 12.5) ≈ **1.33 cans**.
  - Thirst 2.08/h × 24 ÷ 43 per bottle (2 drinks × 21.5) ≈ **1.16 bottles**.

  NPCs and the player drain at the same rates. Over a day, what someone eats
  must equal what drains, so this average holds whatever the eating
  behaviour. (The NPC session wasn't running to confirm when this was built.)

## Files

| File | Role |
|---|---|
| `scripts/ui/new_game/SurvivorSelectScreen.gd` | Screen, motion, pick rules, spawn. |
| `scripts/ui/new_game/SurvivorPortrait.gd` | Live 3D portrait per card. |
| `scripts/ui/new_game/SurvivorDraft.gd` | Candidate roll, consumption maths, save dict. |
| `scripts/ui/loading/LoadingScreen.gd` | `_hand_to_survivor_select()` for new games. |
| `scripts/world/core/WorldManager.gd` | `pending_new_game`. |
| `tools/tests/survivor_select_smoke.gd` | Drives the real path (22 checks). |

## Copy

Brannon's text, verbatim: the estimate line, its "This is not mandatory."
variant, the closing message and "Confirm". Functional labels written here:
"Choose survivors", "Select up to three.", "N of 3 selected", "Selected",
"Age N". Rewrite any of them freely.
