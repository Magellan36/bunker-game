extends RefCounted
class_name ZoneCustomization
## ZoneCustomization.gd  —  player-set zone name/color overrides (July 2026)
## ─────────────────────────────────────────────────────────────────────────────
## Small key→value store for the two things a player can customize about a
## wire zone via its Power Terminal: display name and display color.
##
## IDENTITY: keyed by "zone_key" — the SAME stable zone identity PowerManager's
## built-in auto-color registry already uses internally (there: the local var
## `zone_sort_key[zi]`, computed in get_wire_zones_with_colors() as the zone's
## min NON-breaker node key, or "__MAIN__" for the single unbroken perimeter
## zone). That key survives every wire/perimeter rebuild unchanged as long as
## the zone's own topology doesn't change, so overrides persist across wire
## additions/removals and bunker expansion exactly like auto-assigned colors
## do. Same known tradeoff the base system already accepts: if a zone MERGES
## or SPLITS such that its lowest node key moves to a different zone, that
## zone's override is orphaned (falls back to the game-chosen default) — this
## is acceptable and mirrors how the base color registry already behaves on
## zone-boundary changes (see PowerManager.get_wire_zones_with_colors() doc).
##
## SCOPE — deliberately just a store + tiny query helpers. No solver
## entanglement, no signals of its own (PowerManager re-emits/handles that).
## Kept as its own file rather than bolted onto PowerManager.gd (already very
## large) since this is a fully self-contained new feature — same "no god
## files" reasoning as every prior _owner-pattern extraction in this folder.
##
## DESIGN — same `_owner` back-reference pattern as PowerGraph.gd/
## PowerRegistry.gd/PowerSolver.gd, even though here it's a NEW addition
## rather than an extraction. `_owner` is kept for API symmetry / in case a
## future method needs to reach back into PowerManager (e.g. to validate a
## zone_key still exists) — not currently used.

var _owner: PowerManager = null

## zone_key -> String (player-chosen display name). Absent = use default "Z%d".
var _names: Dictionary = {}

## zone_key -> Color (player-chosen display color, full RGBA incl. alpha as
## picked; callers re-apply their own alpha via zone_display_color()).
## Absent = use the game's auto-assigned palette color.
var _colors: Dictionary = {}

func _init(owner: PowerManager) -> void:
	_owner = owner


## Returns the player-set name override, or "" if none is set.
func get_name_override(zone_key: String) -> String:
	return String(_names.get(zone_key, ""))


## Sets (or clears, if new_name is blank) the display name override for a zone.
func set_name_override(zone_key: String, new_name: String) -> void:
	var trimmed: String = new_name.strip_edges()
	if trimmed.is_empty():
		_names.erase(zone_key)
	else:
		_names[zone_key] = trimmed


func has_color_override(zone_key: String) -> bool:
	return _colors.has(zone_key)


## Returns the player-set color override. Only meaningful when
## has_color_override(zone_key) is true — callers should check that first.
func get_color_override(zone_key: String) -> Color:
	return _colors.get(zone_key, Color.WHITE)


## Sets the color override for a zone. Always persists once set — the caller
## (PowerManager.zone_display_color()) is responsible for checking this
## BEFORE falling back to the algorithmic graph-coloring palette, so an
## override is never silently discarded just because it happens to match (or
## clash with) a neighboring zone's auto-assigned color.
func set_color_override(zone_key: String, new_color: Color) -> void:
	_colors[zone_key] = new_color


## Deep-copy snapshot / restore — mirrors PowerManager's
## snapshot_zone_colors()/restore_zone_colors() pattern for consistency, even
## though overrides are NOT currently wired into that undo flow (they're
## meant to persist through wire-topology changes by design, unlike the
## auto-color registry which undo explicitly rewinds). Exposed for any future
## caller that needs it.
func snapshot() -> Dictionary:
	return {
		"names":  _names.duplicate(true),
		"colors": _colors.duplicate(true),
	}

func restore(snap: Dictionary) -> void:
	_names  = (snap.get("names", {}) as Dictionary).duplicate(true)
	_colors = (snap.get("colors", {}) as Dictionary).duplicate(true)
