class_name UIPanelLayout
extends RefCounted
## Bound the outer panel before container layout; scrolling owns overflow.
## Does not resize fonts or infer a family's intended dimensions.
static func bounded_size(viewport: Vector2, desired: Vector2,
		margin: Vector2 = Vector2(24, 24)) -> Vector2:
	return desired.min((viewport - margin * 2.0).max(Vector2.ONE)).max(Vector2.ONE)

static func fit(panel: Control, viewport: Vector2, desired: Vector2,
		margin: Vector2 = Vector2(24, 24), horizontal: float = 0.5,
		vertical: float = 0.5) -> void:
	var target: Vector2 = bounded_size(viewport, desired, margin)
	# Explicit maximum prevents transient wrapped-label minima from expanding
	# the panel on its first layout pass (Godot 4.6+).
	panel.custom_minimum_size = Vector2.ZERO
	panel.custom_maximum_size = target
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = target
	var spare: Vector2 = (viewport - target - margin * 2.0).max(Vector2.ZERO)
	panel.position = margin.min((viewport - target) * 0.5) + spare * Vector2(
		clampf(horizontal, 0.0, 1.0), clampf(vertical, 0.0, 1.0))
