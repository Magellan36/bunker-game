extends Control
class_name StatusEffectsContainer
## StatusEffectsContainer.gd
## ─────────────────────────────────────────────────────────────────────────────
## Holds active StatusEffectIcon badges in a FIXED, hand-placed layout that
## mirrors Brannon's Medieval Dynasty reference screenshot (a staggered
## triangle, not a plain vertical list) — top badge is the OLDEST active
## effect, and each newer effect takes the next slot down. No cap on how
## many effects can be active (Jul 2026 call — "we'll see what happens past
## 3 and go from there"); the 3 SLOT_OFFSETS below are hand-tuned to match
## the reference image (Jul 2026 fix: top/slot-0 and bottom/slot-2 share the
## same X, forming a straight vertical column; the middle/slot-1 badge sits
## 12.5px left of that column). Anything beyond slot index 2 falls back to
## FALLBACK_SPACING straight down from slot 2 so it never crashes or
## overlaps — it just won't match the reference stagger past 3 badges.
##
## No placeholder is drawn for empty slots (Brannon's explicit call) — an
## empty slot is simply the absence of a child node there.
##
## Usage (future callers):
##     var hud: Node = get_tree().get_first_node_in_group("hud")
##     if hud != null and ("status_effects" in hud):
##         var se: StatusEffectsContainer = hud.get("status_effects") as StatusEffectsContainer
##         se.add_effect("poisoned", null, 12.0, Color(0.85, 0.3, 0.2))
##         se.remove_effect("poisoned")   # early removal, e.g. cured

const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(20.0, 0.0),     ## slot 0 — top (oldest). X anchors the shared column.
	Vector2(7.5, 56.0),     ## slot 1 — middle, shifted LEFT of the shared column
	                         ##          by 25% of a badge's width (50 * 0.25 = 12.5,
	                         ##          20.0 - 12.5 = 7.5). Jul 2026 fix.
	Vector2(20.0, 112.0),   ## slot 2 — bottom. X now MATCHES slot 0 exactly
	                         ##          (Jul 2026 fix — was 4.0, off by 16px).
]
const FALLBACK_SPACING: float = 56.0   ## slot index 3+, straight down from slot 2

var _order: Array[String] = []          ## effect ids, oldest first (index 0 = top)
var _badges: Dictionary = {}            ## effect_id (String) -> StatusEffectIcon

## Adds a new badge at the bottom of the stack, or restarts an existing one
## in place with the same id (re-applying a still-active effect refreshes
## its duration instead of stacking a duplicate badge / changing its slot).
func add_effect(id: String, icon: Texture2D, duration: float, ring_color: Color) -> void:
	if _badges.has(id) and is_instance_valid(_badges[id]):
		(_badges[id] as StatusEffectIcon).setup(id, icon, duration, ring_color)
		return
	var badge: StatusEffectIcon = StatusEffectIcon.new()
	add_child(badge)
	badge.expired.connect(_on_badge_expired)
	badge.setup(id, icon, duration, ring_color)
	_badges[id] = badge
	_order.append(id)
	_reflow()

## Removes a badge early (e.g. the effect was cured before its timer ran
## out). Safe to call with an id that isn't currently active (no-op).
func remove_effect(id: String) -> void:
	if not _badges.has(id):
		return
	var badge: StatusEffectIcon = _badges[id]
	_badges.erase(id)
	_order.erase(id)
	if is_instance_valid(badge):
		badge.queue_free()
	_reflow()

func _on_badge_expired(id: String) -> void:
	remove_effect(id)

## Repositions every active badge according to its current index in
## `_order` (0 = oldest = top slot). Called after every add/remove so the
## remaining badges always slide up into the earlier slots.
func _reflow() -> void:
	for i in range(_order.size()):
		var badge: StatusEffectIcon = _badges[_order[i]]
		if not is_instance_valid(badge):
			continue
		badge.position = _slot_position(i)

func _slot_position(index: int) -> Vector2:
	if index < SLOT_OFFSETS.size():
		return SLOT_OFFSETS[index]
	var last: Vector2 = SLOT_OFFSETS[SLOT_OFFSETS.size() - 1]
	var extra: int = index - (SLOT_OFFSETS.size() - 1)
	return Vector2(last.x, last.y + FALLBACK_SPACING * float(extra))