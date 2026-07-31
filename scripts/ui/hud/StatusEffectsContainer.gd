extends VBoxContainer
class_name StatusEffectsContainer
## StatusEffectsContainer.gd
## ─────────────────────────────────────────────────────────────────────────────
## Holds N active StatusEffectIcon badges, stacked vertically, positioned to
## the right of NeedsGauge on the HUD (Jul 2026 skeleton pass — see
## StatusEffectIcon.gd's own header). SKELETON ONLY: nothing calls
## add_effect() anywhere in the codebase yet. A future plan wires real
## gameplay effects (poison, cold, well-fed, etc.) into this by calling
## add_effect() from wherever that effect is applied to the player.
##
## Usage (future callers):
##     var hud: Node = get_tree().get_first_node_in_group("hud")
##     hud.status_effects.add_effect("poisoned", poison_icon, 12.0, Color(0.85,0.3,0.2))
##     hud.status_effects.remove_effect("poisoned")   # early removal, e.g. cured

var _badges: Dictionary = {}   ## effect_id (String) -> StatusEffectIcon

func _ready() -> void:
	add_theme_constant_override("separation", 8)

## Adds a new badge, or restarts an existing one with the same id (e.g.
## re-applying a still-active effect refreshes its duration instead of
## stacking a duplicate badge).
func add_effect(id: String, icon: Texture2D, duration: float, ring_color: Color) -> void:
	if _badges.has(id) and is_instance_valid(_badges[id]):
		(_badges[id] as StatusEffectIcon).setup(id, icon, duration, ring_color)
		return
	var badge: StatusEffectIcon = StatusEffectIcon.new()
	add_child(badge)
	badge.expired.connect(_on_badge_expired)
	badge.setup(id, icon, duration, ring_color)
	_badges[id] = badge

## Removes a badge early (e.g. the effect was cured before its timer ran out).
## Safe to call with an id that isn't currently active (no-op).
func remove_effect(id: String) -> void:
	if not _badges.has(id):
		return
	var badge: StatusEffectIcon = _badges[id]
	_badges.erase(id)
	if is_instance_valid(badge):
		badge.queue_free()

func _on_badge_expired(id: String) -> void:
	remove_effect(id)