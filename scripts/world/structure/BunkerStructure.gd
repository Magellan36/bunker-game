extends RefCounted
class_name BunkerStructure
## BunkerStructure.gd  —  Part A (structure refactor, Jul 2026)
## ─────────────────────────────────────────────────────────────────────────────
## Pure static helper consolidating the scattered "is this GridMap tile a
## wall or a pillar?" check that was previously hand-duplicated as
## `tid == TILE_WALL or tid == TILE_PILLAR` (or the equivalent magic-number
## `tid == 1 or tid == 2`) across 8 call sites in BuildModeController.gd,
## WallSnapHelpers.gd, and WaterHookup.gd.
##
## This does NOT change the GridMap tile-ID mechanism, does NOT turn
## walls/pillars into scripted Node classes, and does NOT own any state —
## it is a stateless static utility only. Tile IDs stay meaningful GridMap
## indices owned by BuildModeController (TILE_WALL=1, TILE_PILLAR=2).
##
## Callers pass their own TILE_WALL/TILE_PILLAR constants in (each file that
## needs this already declares its own local copies of those constants, e.g.
## WireGraphBuilder.gd's per-function `const TILE_WALL/TILE_PILLAR`) so this
## helper has zero coupling to BuildModeController beyond the ids matching.
##
## See docs/systems/structure/README.md for the full call-site list.

const TILE_WALL: int   = 1
const TILE_PILLAR: int = 2


## Returns true if the given GridMap item id is a wall or a pillar tile.
static func is_wall_or_pillar(tile_id: int) -> bool:
	return tile_id == TILE_WALL or tile_id == TILE_PILLAR
