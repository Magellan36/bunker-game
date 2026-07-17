# Handover — BunkerGame

**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

## What just shipped (this session)
F8 admin controls menu — a cheat/debug tool distinct from the existing F10
`AdminSpawnMenu`. Two stackable buttons: **+1000w Power** and **-1000w
Power**, simulating an infinitely-fueled generator wired into the grid.

### How it works
- `PowerRegistry.register_generator()` gained an `infinite: bool = false`
  param (stored on the generator dict).
- `PowerManager.register_generator()` passes it through; `_tick_generators()`
  skips fuel drain entirely when `gen.infinite == true`.
- `PowerManager.admin_add_power(delta_watts: float)` — new public method.
  Finds-or-creates one hidden generator (`ADMIN_GEN_ID =
  "admin_cheat_gen"`, `infinite=true`) and attaches it to the wire graph via
  a `no_visual` logical-only edge, offset by exactly `PowerGraph.SNAP_GRID`
  (0.25m) from the first node returned by `get_wire_nodes()`. This
  deliberately avoids `register_wire_edge()`'s automatic intermediate-joint
  stepping loop blowing up over distance if a far sentinel position were
  used instead. Watts accumulate on the single generator (clicking +1000w
  twice = +2000w total) rather than spawning a new generator per click;
  clamped to >= 0, fully unregisters (generator + wire node) at exactly 0.
- `scripts/ui/menus/AdminMenu.gd` (new file) — F8 CanvasLayer panel,
  mirrors `AdminSpawnMenu.gd`'s lifecycle/styling (`layer=128`, lazy init,
  `UIFade.fade_in()`, brutalist Panel/StyleBoxFlat theme).
- `MainWorld.gd` — F8 `_unhandled_input` handler +
  `_toggle_admin_cheat_menu()` (lazy-init, same pattern as F10's toggle),
  `_admin_cheat_menu` var, dev-tools header comment updated to list F8/F10.

### Verified
- `tools/godot_check.sh /tmp/Godot_v4.6.3-stable_linux.x86_64` → **PASS**,
  no parse/compile errors, run after all edits.
- Docs updated same commit: `docs/systems/power/README.md` (Public API
  section: `register_generator()` `infinite` param note, new Known
  tradeoffs bullet on the admin-gen wire-attach approach and its one known
  gap — see below), `PROJECT_SUMMARY.md` (menus/ folder listing now shows
  `AdminMenu (F8 power cheat)`).
- Committed and pushed to `main` (`5aa622a`). Not yet tested in-editor by
  Brannon.

### Known gap (documented, not yet handled)
If the wire graph is completely empty (player hasn't placed/dug any wires
yet), `admin_add_power()` has no node to attach to and the admin generator
stays unconnected — no power actually flows even though the generator
exists. Low priority (only affects a fresh, wire-free save), flagged in the
README's Known tradeoffs, not fixed this pass.

## Next up for Brannon to test
1. Pull latest `main`.
2. Press **F8** in-editor — confirm panel opens (distinct from F10's spawn
   menu).
3. Click **+1000w Power** twice — check `total_capacity_watts`/HUD draw
   reflects +2000w total (should power previously-shed items if capacity
   was the bottleneck).
4. Click **-1000w Power** down to 0 — confirm the hidden generator fully
   unregisters (no lingering phantom wire node/generator) and load drops
   back to pre-cheat baseline.
5. Confirm no regression to F10 `AdminSpawnMenu` or any existing real
   generator's registration/fuel behavior.
6. Report back any bugs (especially: does it behave correctly on a
   fresh/no-wires save — the known gap above).

## Then: Save/Load system
Per Brannon's direction, next planned work area is the **save/load system**
(`SaveManager` autoload — currently: generic field-registry pattern, any
system registers getter/setter under a string key, wired fields so far are
player position, cash, game clock elapsed seconds; saves to
`user://save_slot_1/2/3.json`, load skips unregistered keys).

Before starting: **read `docs/systems/world-core/README.md`** (SaveManager
lives there) and re-familiarize with the field-registry pattern, plus check
whether any newer systems shipped since (Water, Power priority overrides,
zone rename/color, admin cheat generator — this one is intentionally NOT a
save/load candidate, it's a debug tool) need their own registered
save/load fields. Ask Brannon which fields/systems he wants persisted next
before writing code — don't assume scope.

## Standing conventions (don't relitigate)
- All file ops via GitHub HTTPS only (token in `.env`) — read repo → edit
  sandbox → push → Brannon pulls in Godot. No zip downloads.
- Godot 4.6.3 strict syntax, statically typed GDScript, no deprecated G3.
- No compiler in sandbox — always run `tools/godot_check.sh` before
  reporting a fix/feature done.
- Doc-update discipline: system README + `PROJECT_SUMMARY.md` updates go in
  the *same commit* as the code change — never drifts.
- No god files — new self-contained features get their own file/folder.
- Credit-efficient sessions: read `PROJECT_SUMMARY.md` + relevant
  `docs/systems/*/README.md` first; only open source files that are
  actually relevant to the surgical change at hand.
