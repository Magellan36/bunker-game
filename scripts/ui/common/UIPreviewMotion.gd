class_name UIPreviewMotion
extends RefCounted
## Restrained preview cross-fade shared by item cards. Existing pooled
## SubViewports remain intact; this only animates their TextureRect surfaces.

const FADE_OUT: float = 0.07
const FADE_IN: float = 0.14
const TWEEN_META: StringName = &"preview_motion_tween"


static func swap(preview: TextureRect, fallback: CanvasItem, texture: Texture2D,
		force: bool = false) -> void:
	if preview == null:
		return
	var previous_tween: Variant = preview.get_meta(TWEEN_META, null)
	if previous_tween is Tween and (previous_tween as Tween).is_valid():
		(previous_tween as Tween).kill()
	if not force and preview.texture == texture:
		preview.modulate.a = 1.0 if texture != null else 0.0
		if fallback != null:
			fallback.modulate.a = 0.0 if texture != null else 1.0
			fallback.visible = texture == null
		return
	var tween: Tween = preview.create_tween()
	preview.set_meta(TWEEN_META, tween)
	if preview.texture == null or texture == null:
		preview.texture = texture
		preview.modulate.a = 0.0 if texture != null else 1.0
		if fallback != null:
			fallback.visible = true
			fallback.modulate.a = 1.0 if texture == null else 0.0
		tween.set_parallel(true)
		tween.tween_property(preview, "modulate:a", 1.0 if texture != null else 0.0,
			FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if fallback != null:
			tween.tween_property(fallback, "modulate:a", 0.0 if texture != null else 1.0,
				FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.finished.connect(_finish_fallback.bind(fallback, texture == null), CONNECT_ONE_SHOT)
		return
	tween.tween_property(preview, "modulate:a", 0.0, FADE_OUT).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN)
	tween.tween_callback(_assign_texture.bind(preview, texture))
	tween.tween_property(preview, "modulate:a", 1.0, FADE_IN).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)


static func _assign_texture(preview: TextureRect, texture: Texture2D) -> void:
	if is_instance_valid(preview):
		preview.texture = texture


static func _finish_fallback(fallback: CanvasItem, should_show: bool) -> void:
	if is_instance_valid(fallback):
		fallback.visible = should_show
