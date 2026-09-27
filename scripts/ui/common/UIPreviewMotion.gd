class_name UIPreviewMotion
extends RefCounted
## Assign the latest image immediately, then soften its arrival. Labels/actions
## never describe an older delayed image. Repeated identical updates are no-ops.
const TWEEN_META: StringName = &"preview_motion_tween"

static func swap(preview: TextureRect, fallback: CanvasItem, texture: Texture2D,
		force: bool = false) -> void:
	if not is_instance_valid(preview):
		return
	if not force and preview.has_meta(&"preview_initialized") and preview.texture == texture:
		return
	preview.set_meta(&"preview_initialized", true)
	var previous: Variant = preview.get_meta(TWEEN_META) if preview.has_meta(TWEEN_META) else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	preview.texture = texture
	preview.modulate.a = 1.0 if texture != null else 0.0
	if is_instance_valid(fallback):
		fallback.visible = texture == null
		fallback.modulate.a = 1.0
	if texture == null or UIMotion.reduced() or not preview.is_visible_in_tree():
		return
	preview.modulate.a = 0.75
	var tween: Tween = preview.create_tween()
	preview.set_meta(TWEEN_META, tween)
	tween.tween_property(preview, "modulate:a", 1.0, UIMotion.CONTENT).set_trans(
		Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
