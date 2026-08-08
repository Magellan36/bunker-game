# Plan: Documentation Catch-Up (Cooking Pot, Storage Prompts, NPC Colors)

**Owner of this plan:** UI Claude instance (HUD/menus/Build Mode/Furniture)
**Scope:** Documentation only — `docs/systems/ui/README.md`,
`docs/systems/npc/README.md`, `docs/systems/furniture-items/README.md`,
`HANDOVER.md`. No code changes in this plan.

**Audit performed first:** read every relevant doc's current content
before writing anything below, specifically to avoid duplicating what's
already there. Findings:
- `docs/systems/ui/README.md` is fully caught up through the "Farming Shop
  Seed tile_id Bugfix (Aug 2026)" section — everything after that point
  (cooking pot investigation onward) is undocumented.
- `docs/systems/npc/README.md` already documents `NPCTalkMenuUI.gd`'s bars
  (lines 48-49) but not their color scheme — needs a short addition, not a
  new section.
- `docs/systems/furniture-items/README.md` already documents
  `LightStorage.gd`/`EndTable.gd`/`Dresser.gd` in detail — needs a short
  bullet added to its existing "Common edits" list, not a new section.
- `HANDOVER.md`'s current top section is a different thread's work
  ("Storage-Reject Fallback to Drop") — per established convention, insert
  above it, don't replace.

---

## 1. `docs/systems/ui/README.md`

### Step 1.1 — Add the missing `npc/` row to "Files by subfolder"

This subfolder was never listed (pre-existing gap, not from this arc) —
closing it while auditing. `NPCTalkMenuUI.gd` itself is documented in full
in `docs/systems/npc/README.md`; this is a pointer row only, matching how
the `power/`/`water/` rows already point to their own system docs.

Find this exact line:

```
| `notifications/` | `NotificationManager.gd` (~175) | Central toast/notification system (see "NotificationManager" below) |
```

Replace it with exactly this:

```
| `notifications/` | `NotificationManager.gd` (~175) | Central toast/notification system (see "NotificationManager" below) |
| `npc/` | `NPCTalkMenuUI.gd` | NPC E-panel (needs bars, status, skills, personality) — see `docs/systems/npc/README.md` for full detail; fixed per-stat bar colors as of Aug 2026, see "Cooking Pot UI Fixes..." below is unrelated — see the NPC doc directly for the color table |
```

### Step 1.2 — Amend the `build/` row (it references the seed tile_id bug already; add the separate seed-color bug found in the same investigation)

Find this exact line:

```
| `build/` | `BuildModeHUD.gd` (~1010) | Build-mode toolbar/construct menu/undo/dig-confirm UI. Farming shop's `FARMING_SHOP_ITEMS["Seeds"]` had a duplicate-`tile_id` bug fixed Aug 2026 — see "Farming Shop Seed tile_id Bugfix" below |
```

Replace it with exactly this:

```
| `build/` | `BuildModeHUD.gd` (~1010) | Build-mode toolbar/construct menu/undo/dig-confirm UI. Farming shop's `FARMING_SHOP_ITEMS["Seeds"]` had a duplicate-`tile_id` bug fixed Aug 2026 (see "Farming Shop Seed tile_id Bugfix" below) and a SEPARATE bug where `PREVIEW_SOURCES` never set `seed_type` per-id, so every seed preview looked identical — fixed Aug 2026, see "Cooking Pot UI Fixes + Prompt Overlap Avoidance" below |
```

### Step 1.3 — Amend the `hud/` row (InteractPrompt grew substantially)

Find this exact line:

```
| `hud/` | `HUD.gd` (~290), `NeedsGauge.gd` (~130 — 3-ring concentric stat gauge, replaces old `StatusBars.gd`/`CircleFill.gd`), `StatusEffectIcon.gd` (~70), `StatusEffectsContainer.gd` (~85), `InteractPrompt.gd` (~107 — world-space prompt panel; `Panel/Label` is a BBCode-enabled `RichTextLabel` so items like `WaterBottle` can colour part of their prompt text) | Always-on needs gauge (health/stamina/food/water/sleep), status-effect badge skeleton, interact prompt |
```

Replace it with exactly this:

```
| `hud/` | `HUD.gd` (~290), `NeedsGauge.gd` (~130 — 3-ring concentric stat gauge, replaces old `StatusBars.gd`/`CircleFill.gd`), `StatusEffectIcon.gd` (~70), `StatusEffectsContainer.gd` (~85), `InteractPrompt.gd` (~170 — world-space prompt panel; `Panel/Label` is a BBCode-enabled `RichTextLabel` so items like `WaterBottle` can colour part of their prompt text; grew substantially Aug 2026 — real styling, an icon-preview row, and general pairwise overlap avoidance, see "Cooking Pot UI Fixes + Prompt Overlap Avoidance" below) | Always-on needs gauge (health/stamina/food/water/sleep), status-effect badge skeleton, interact prompt |
```

### Step 1.4 — Amend the end of the "Storage UI Unification (Aug 2026)" section

Find this exact block (the section's current final paragraph):

```
Visual style deliberately NOT changed in this pass — `StorageUI.gd` kept
the existing look (14px corner radius, its own dark palette) rather than
moving onto the `UIKit` domain-stripe system Power/Water/Farming/Pause
use. That's a separate, not-yet-requested decision.
```

Replace it with exactly this (keeps that paragraph, appends a new one
right after covering the follow-up work):

```
Visual style deliberately NOT changed in this pass — `StorageUI.gd` kept
the existing look (14px corner radius, its own dark palette) rather than
moving onto the `UIKit` domain-stripe system Power/Water/Farming/Pause
use. That's a separate, not-yet-requested decision.

**Follow-up (Aug 2026) — prompt exclusivity rule + Dresser/End Table
fix.** Two real bugs found and fixed after the initial unification:

1. `LightStorage.gd` (the shared base `Dresser.gd`/`EndTable.gd` extend)
   only joined the `"shelving"` group, never `"interactable"`. Shelving.gd
   joins both — `InteractionSystem.gd`'s empty-handed candidate-gathering
   requires `"interactable"` membership for one of its two passes and
   explicitly excludes `"shelving"` members from the other, so Shelving
   slipped through via the first pass while Dresser/End Table fell into
   the gap between both and never got a prompt at all. Fixed with one
   `add_to_group("interactable")` call.
2. `LightStorage.get_f_prompt()` returned `""` (nothing) when full,
   unlike `Shelving.gd`'s existing `"[F] Shelf full"` — now returns
   `"<name> Full"` to match.

**New standing rule**: while the player holds a storable item near any
`"shelving"`-group object (Shelf, Dresser, End Table, and any future
storage furniture), only ONE prompt line shows — `get_f_prompt()`'s text
if it has something to say (Store or Full), falling back to
`get_e_prompt()` only when it doesn't. Previously both always showed
together, which was actively misleading: while anything is held, `E` is
bound to the held item's own action, never to a nearby shelf's
`on_e_interact()`.

This rule needed to be applied in TWO places —
`InteractionSystem._update_prompt()` has entirely separate code paths for
"holding something" (CASE 1) vs "empty-handed" (CASE 2), each with its own
copy of the shelving-prompt logic. An earlier pass only fixed CASE 2, which
is why the bug persisted for held items. Both are now fixed, along with a
second, unrelated bug in CASE 2 specifically: it discovered `"shelving"`
objects via `Area3D` signal tracking, which never fires for a body that
spawns already inside the player's trigger volume (exactly what happens
placing furniture via Build Mode while standing next to it) — CASE 2 now
also does a direct per-frame group scan, matching the timing-safe approach
CASE 1's `_nearest_shelf()` already used. All of this lives in
`InteractionSystem.gd` (Player-thread-owned) — handed off as a standalone
plan rather than applied directly by the UI thread.
```

### Step 1.5 — Add the new "Cooking Pot UI Fixes + Prompt Overlap Avoidance" section

Find this exact line (the start of the "Extension points" section, at the
very end of the file):

```
## Extension points
```

Insert the following **immediately before** that line:

```
## Cooking Pot UI Fixes + Prompt Overlap Avoidance (Aug 2026)
`CookingPot.gd` has no dedicated modal panel — it's driven entirely by the
shared `InteractPrompt.gd` floating prompt (text + up to 3 live 3D
ingredient icon previews), the same panel every interactable in the game
uses. Several real bugs found and fixed here, all traced to root cause
rather than patched by symptom:

- **Icons vanished on pickup**: `InteractionSystem._update_prompt()`'s
  held-item branch (CASE 1) never looked up `get_slot_icon_descriptors()`
  at all — only the empty-handed branch (CASE 2) did. Fixed generically
  (works for any held item implementing that method, not cooking-
  specific).
- **Icons/prompt vanished on drop until leaving and re-entering range**: a
  dropped item was never re-added to `InteractionSystem._tracked_bodies`
  (the `Area3D`-signal-tracked set CASE 2 scans) — same root cause as the
  Dresser/End Table timing bug above. Fixed in `_quick_drop()`.
- **"DONE — Take Dish" prompt went blank while the pot sat on a Stove**: a
  regression from the "Cooking recipe best-fit dish naming" commit added
  `if _host_stove != null: return ""` to `CookingPot.get_interact_prompt()`
  — but `Stove.get_interact_prompt()` delegates to that exact same
  function for its own ready-dish text, so the early-return silenced both
  objects' prompts at once whenever the pot was actually on a stove (the
  normal cooking setup). Removed the early-return.
- **Food Can preview rendered as an empty circle**: its descriptor used
  `is_script: true` (bare `Script.new()`, no children), but
  `FoodCan.gd`'s own `_ready()` expects a pre-built `MeshInstance3D` CHILD
  node (`get_node_or_null("MeshInstance3D")`) — unlike `FarmProduceItem`,
  which builds its mesh procedurally in code. Fixed by pointing the
  descriptor at `FoodCan.tscn` (packed-scene mode) instead of the script.
- **All 12 seed packets in the Build Mode Farming Shop preview looked
  identical**: `BuildModeHUD.PREVIEW_SOURCES` mapped every seed `tile_id`
  to the same generic `SeedItem.gd` script but never set its `seed_type`
  export var before instantiating — unlike produce, which already gets
  its `produce_type` set correctly nearby in the same file. Every seed
  silently defaulted to `seed_type`'s own `"tomato"` fallback.
  `PlantDatabase.get_seed_packet_color()` already supported all 12 species
  correctly; it just never received the right value. Fixed by adding
  `seed_type` to each of the 12 `PREVIEW_SOURCES` entries (matching
  `FarmingShopHelper.SHOP_ITEM_INFO`'s `"type"` field exactly) and setting
  it on the instance before it enters the tree.

**Layout**: middle ingredient icon sits 15% higher than the two flanking
it (a fixed pixel offset baked into the scene template, not computed at
runtime — `HBoxContainer`'s auto-layout can't offset one child, so
`IconRow` is a plain `Control` with each slot's position set explicitly).
Icon size and the outer panel's padding went through a few iterations —
final state is back to the original 32px icon size (a 2x-larger version
was tried and explicitly reverted per Brannon's call), with the panel's
top/bottom content margins symmetric (`10.0` each) so plain-text prompts
(the vast majority — "[F] Pick up crate," "[E] Wall Light," etc., which
have no icon row at all) read as properly vertically centered. Ingredient
previews render at the same 45°/45° resting rotation used everywhere else
in the project (`Vector3(-45, -45, 0)`, matching `BuildModeHUD`'s
`PREVIEW_ROTATION_DEFAULT` and `InventoryHUD`'s own previews) — static, no
hover-spin.

**Prompt overlap avoidance** (`InteractPrompt._resolve_overlaps()`): a
general, non-cooking-specific pairwise layout pass. When two visible
prompt panels would overlap on screen (e.g. a Cooking Pot placed on a
Stove — two separate objects, two separate panels, positioned very close
together), the one with a non-empty icon row outranks a plain-text one
(ties broken by whichever is closer to the player); the lower-priority
panel gets pushed directly below the higher one with a fixed gap. Panels
that don't overlap are completely unaffected — this only activates when
two real panels' rects actually intersect on screen. Runs a few passes so
a chain of 3+ overlapping panels all separate out.

**Panel styling** (this affects EVERY interactable's prompt in the game,
not just cooking — `InteractPrompt.tscn` is one shared template): the
outer panel had zero custom `StyleBoxFlat` at all before this pass — no
theme resource defines one, so it rendered with Godot's raw default
`PanelContainer` look the whole time. Now uses a dark/rounded style
matching the rest of the project's palette (8px corner radius — rounder
than the 4px modal-panel standard, intentionally, same "smaller-scale
identity" precedent as `StorageUI.gd`'s 14px). Confirmed with Brannon this
project-wide change is wanted, not something to scope down to cooking
only.
```

---

## 2. `docs/systems/npc/README.md`

Find this exact block:

```
- **`NPCTalkMenuUI.gd`** (`scripts/ui/npc/`) — the E-panel: live
  Health/Energy/Hunger/Thirst/Mood bars, Status line, Skills, Personality,
```

Replace it with exactly this (only the first line changes — the second
line and whatever follows it stays exactly as-is, this just appends a
sentence):

```
- **`NPCTalkMenuUI.gd`** (`scripts/ui/npc/`) — the E-panel: live
  Health/Energy/Hunger/Thirst/Mood bars (Aug 2026 — fixed per-stat colors
  matching the player's own `NeedsGauge` palette: Health red, Energy
  purple, Thirst blue, all copied exactly; Hunger yellow reuses the
  project's other established yellow since the player HUD has none; Mood
  is `#bca0dc` exactly. No longer recolors by value the way it used to —
  see `docs/systems/ui/README.md`'s `UIKit`/`NeedsGauge` sections for the
  broader palette convention this now matches), Status line, Skills, Personality,
```

---

## 3. `docs/systems/furniture-items/README.md`

Find this exact block:

```
- Storage-full/too-big rejection (Dresser/End Table/Shelf) now falls
  back to a normal drop instead of blocking F entirely — see Player
  subsystem's `docs/systems/player/README.md` for the fallback mechanism
  (`InteractionSystem._quick_drop()`).
```

Replace it with exactly this:

```
- Storage-full/too-big rejection (Dresser/End Table/Shelf) now falls
  back to a normal drop instead of blocking F entirely — see Player
  subsystem's `docs/systems/player/README.md` for the fallback mechanism
  (`InteractionSystem._quick_drop()`).
- **Aug 2026 fix**: `LightStorage.gd` only joined the `"shelving"` group,
  never `"interactable"` (unlike `Shelving.gd`, which joins both) — this
  meant Dresser/End Table never showed an empty-handed prompt at all, they
  fell into a gap between `InteractionSystem`'s two candidate-gathering
  passes. Fixed with one `add_to_group("interactable")` call in
  `LightStorage._ready()`. Also fixed `get_f_prompt()` returning `""`
  (nothing) when full — now returns `"<name> Full"`, matching
  `Shelving.gd`'s existing `"[F] Shelf full"` pattern. Full detail in
  `docs/systems/ui/README.md`'s "Storage UI Unification" section.
```

---

## 4. `HANDOVER.md`

Insert a new top section, above whatever is currently there (a different
thread's "Storage-Reject Fallback to Drop" work — do not delete it).

Find the first line of the file (whatever it currently is) and insert this
immediately before it:

```markdown
# Handover — Cooking Pot UI Fixes, Storage Prompt Rules, NPC Colors (Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode/Furniture).

## What changed
- **Cooking Pot UI**: fixed the icon row disappearing on pickup (CASE 1
  never looked up icon descriptors) and on drop (items never got
  re-tracked after `_quick_drop()`); fixed the "DONE — Take Dish" prompt
  going blank while the pot sat on a Stove (a regression from the dish-
  naming commit); fixed Food Can rendering as an empty preview circle
  (wrong instantiation mode); fixed all 12 seed packets looking identical
  in the Build Mode shop preview (missing per-id `seed_type`). Layout:
  middle ingredient icon 15% higher, panel padding made symmetric, icon
  size settled back to original 32px after a 2x version was tried and
  reverted, previews now use the same 45°/45° resting rotation as
  everywhere else in the project.
- **Prompt overlap avoidance**: general pairwise layout pass in
  `InteractPrompt.gd` — any two overlapping prompt panels (e.g. Cooking
  Pot + the Stove it's sitting on) now stack instead of overlapping,
  icon-bearing prompts on top. Not cooking-specific, applies project-wide.
- **`InteractPrompt.tscn` panel styling**: gave the shared floating prompt
  (used by every interactable in the game) real dark/rounded styling for
  the first time — it had zero custom stylebox before this arc.
- **Storage prompt exclusivity rule**: while holding a storable item near
  a Shelf/Dresser/End Table, only one prompt line shows now (Store/Full,
  not also "Open"). Needed fixing in two separate code paths in
  `InteractionSystem.gd` (CASE 1 held-item vs CASE 2 empty-handed).
- **Dresser/End Table empty-handed prompt bug, fixed**: `LightStorage.gd`
  was missing `"interactable"` group membership — Shelving has it,
  Dresser/End Table didn't, so they never got a prompt.
- **Handed a separate plan to the Player thread** for the remaining
  `InteractionSystem.gd` half of the storage-prompt fix (CASE 1's
  un-fixed copy of the exclusivity logic, and a timing-safe group-scan
  for CASE 2, since `Area3D` signals don't fire for furniture that spawns
  already inside the player's trigger volume).
- **NPC meter colors**: `NPCTalkMenuUI.gd`'s 5 need bars now use fixed
  per-stat colors (Health red, Energy purple, Hunger yellow, Thirst blue,
  Mood `#bca0dc`) instead of recoloring by value — matches the player's
  own `NeedsGauge` convention.

## Files Modified
`scripts/ui/hud/InteractPrompt.gd`, `scenes/ui/InteractPrompt.tscn`,
`scripts/world/items/CookingPot.gd`, `scripts/ui/build/BuildModeHUD.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/player/InteractionSystem.gd` (partially — see handed-off plan for
the remainder)

## Next Up
- Confirm the Player thread has applied the handed-off
  `InteractionSystem.gd` fixes (CASE 1 exclusivity + CASE 2 timing-safe
  shelving scan) — until then, Dresser/End Table's empty-handed prompt and
  Shelving's held-item exclusivity remain broken.
- `ShelfUI`/`BasketUI`-era visual identity for `StorageUI.gd` still
  hasn't been brought onto the `UIKit` domain-stripe system — still a
  deliberate, deferred decision, not forgotten.

---

```
