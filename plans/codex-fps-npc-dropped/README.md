# Codex FPS pass — NPC optimizations dropped by the NPC-overhaul merge

**Status:** parked (Brannon, 2026-09-27: "just list them for now").

Codex's four-pass FPS optimization (session `01a0da76`, Sep 25–26 2026) landed
on `testing` in `5b1fc85`. The later NPC overhaul (`claude/gifted-planck-32j7ii`)
was merged into `testing` as `1066f1a` with its NPC code taken as canonical.
That merge dropped the five NPC-side optimizations below. Every other FPS
change survived: water, power, build, shelving, farming, items, interaction
and graphics settings. The build-preview pool changes were later replaced on
purpose by `PreviewStudio`.

Each `*.patch.txt` file holds Codex's original hunks. They were written
against the pre-overhaul code (`e1de69c`), so they must be re-derived onto the
current NPC code, not applied as-is.

| File (pre-overhaul) | Optimization | Present in canonical code? |
|---|---|---|
| `NPCBrain.gd` | `_think()` returns early while the current activity is non-interruptible, skipping every world query whose winner would be rejected anyway | No |
| `NPC.gd` | `_handle_physics_pushes` shape query throttled to 10 Hz (random phase per NPC); prunes the stale push-cooldown map above 128 entries | No (function exists, unthrottled) |
| `NPCCompanionship.gd` | `_cleanup()` rate-limited to once per second (forced on `begin`) | File no longer exists in the overhaul |
| `queries/NPCJobQueries.gd` | `find_cooking_action_target()`: one stove walk resolves serve / power / ingredient / pot, replacing four separate scans in utility scoring | No |
| `activities/CookingActivity.gd` | Uses the combined query on activity entry | No |

`NPCDoorCoordinator.gd`'s cleanup throttle and the `BunkerNavMesh.gd` changes
did survive.
