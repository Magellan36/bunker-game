extends Node
class_name PillarRegistry
## PillarRegistry.gd  —  Part A (structure refactor, Jul 2026)
## ─────────────────────────────────────────────────────────────────────────────
## Tiny standalone registry holding the current set of pillar world positions,
## kept in sync by WireGraphBuilder.gd every time it recomputes the bunker
## perimeter (initial pregen solve + every incremental chunk dig/restore).
##
## Mirrors the PowerManager/WaterManager pattern: MainWorld owns one instance,
## adds it to the scene tree, tags it with group "pillar_registry" BEFORE
## add_child() so any consumer can find it via
## `get_tree().get_first_node_in_group("pillar_registry")` without needing a
## direct MainWorld reference.
##
## Current consumer: WaterPipeDrawMode.gd's pillar-clearance nudge (Part B).
## Future consumers (build-mode placement checks, AI pathing, etc.) should
## read via get_all_positions() rather than reaching into WireGraphBuilder.
##
## PILLAR_CLEARANCE_RADIUS — verified (Jul 2026) against the real pillar
## physics footprint: BuildModeController._tile_half_extents() defines
## TILE_PILLAR's collision half-extent as Vector2(0.24, 0.24) (a 0.48×0.48
## box). The worst-case distance from the pillar's center to its corner is
## sqrt(0.24² + 0.24²) ≈ 0.339, so a clearance radius must be at least that to
## guarantee no clipping regardless of the approach angle a pipe leg comes in
## at. 0.34 is that circumscribed-circle radius rounded up with a hair of
## margin — this replaces the earlier 0.5 placeholder, which was safe but
## overly conservative (nudged pipes further from pillars than necessary).
const PILLAR_CLEARANCE_RADIUS: float = 0.34

## key (same "wkey,wkey" string format WireGraphBuilder uses) → Vector3 world position
var _positions: Dictionary = {}


## Replaces the full pillar position set. Called by WireGraphBuilder.gd right
## after it finishes computing `pillar_positions` for a given solve pass
## (both the initial full pregen solve and every incremental chunk rebuild).
func set_all(positions: Dictionary) -> void:
	_positions = positions.duplicate()


## Returns the current pillar positions as key → Vector3. Callers should treat
## this as read-only (it's a duplicate, but don't rely on that — copy again if
## you need to mutate).
func get_all_positions() -> Dictionary:
	return _positions
