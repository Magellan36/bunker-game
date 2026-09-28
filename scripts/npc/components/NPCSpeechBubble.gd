extends Node3D
class_name NPCSpeechBubble
## NPCSpeechBubble.gd (Sep 2026) — everything a resident "says" overhead.
##
## Replaces the stacked Label3D text (bark line / "..." / "zZz") that sat on
## top of the debug nameplate. The nameplate is a temporary debug overlay;
## these bubbles are the shipping presentation, so they anchor to the
## resident's HEAD BONE (they follow a resident sitting, lying in bed or
## leaning) and never assume anything else floats above them.
##
##   say(text)        — speech bubble: rounded panel in the in-game UI palette
##                      (UIKit), small tail pointing at the speaker, pops in,
##                      drifts up a touch, fades out.
##   set_typing(on)   — a small pill with three pulsing dots: "talking, not
##                      a line you can read" (conversation turn-taking).
##   set_sleeping(on) — soft "z"s rising and fading beside the head.
##
## Cost: each bubble is drawn ONCE into a small SubViewport (update mode
## ONCE) and shown on a billboard Sprite3D; animation is just transform and
## modulate. The typing pill redraws a few times per second while visible.

const FONT_SIZE: int = 30              ## drawn at 2x for crisp text (SUPERSAMPLE)
const SUPERSAMPLE: float = 2.0
const MAX_TEXT_W: float = 460.0        ## wrap width (supersampled px)
const PAD := Vector2(26.0, 16.0)
const RADIUS: float = 18.0
const TAIL_W: float = 22.0
const TAIL_H: float = 14.0
const SHADOW: float = 6.0
const PIXEL_SIZE: float = 0.0016       ## world metres per supersampled px (fixed_size screen scale)
const HEAD_CLEARANCE: float = 0.30     ## bubble tail tip this far above the head bone
const FALLBACK_HEAD_Y: float = 1.35    ## local Y when no skeleton is available
const HIDE_BEYOND: float = 16.0        ## metres from the camera

const POP_TIME: float = 0.18
const FADE_TIME: float = 0.45
const RISE: float = 0.06

var _npc: Node3D = null
var _head_bone: int = -1
var _skeleton: Skeleton3D = null

var _vp: SubViewport = null
var _canvas: _BubbleCanvas = null
var _sprite: Sprite3D = null
var _say_left: float = 0.0
var _say_total: float = 0.0
var _age: float = 0.0
var _typing: bool = false
var _typing_phase: float = 0.0
var _typing_frame: int = -1
var _mode: String = ""                 ## "" | "say" | "typing"

var _sleeping: bool = false
var _zs: Array[Label3D] = []
var _z_clock: float = 0.0

func setup(npc: Node3D) -> void:
	_npc = npc
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.size = Vector2i(8, 8)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_canvas = _BubbleCanvas.new()
	_vp.add_child(_canvas)
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.fixed_size = true
	_sprite.pixel_size = PIXEL_SIZE / SUPERSAMPLE
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.render_priority = 10
	_sprite.texture = _vp.get_texture()
	_sprite.visible = false
	add_child(_sprite)

func is_showing() -> bool:
	return _mode != ""

func say(text: String, duration: float = 3.4) -> void:
	if text.strip_edges() == "" or _canvas == null:
		return
	_canvas.set_speech(text)
	_render()
	_mode = "say"
	_say_total = duration + clampf(text.length() * 0.03, 0.0, 2.0)   ## longer lines linger
	_say_left = _say_total
	_age = 0.0

func set_typing(on: bool) -> void:
	_typing = on

func set_sleeping(on: bool) -> void:
	_sleeping = on

func tick(delta: float) -> void:
	if _npc == null:
		return
	var head: Vector3 = _head_position()
	global_position = head
	var cam: Camera3D = get_viewport().get_camera_3d()
	var far: bool = cam != null and cam.global_position.distance_to(head) > HIDE_BEYOND
	_tick_bubble(delta, far)
	_tick_zs(delta, far)

# ─── Speech / typing ────────────────────────────────────────────────────────
func _tick_bubble(delta: float, far: bool) -> void:
	if _mode == "say":
		_say_left -= delta
		if _say_left <= 0.0:
			_mode = ""
	if _mode == "" and _typing:
		_mode = "typing"
		_age = 0.0
		_typing_frame = -1
	if _mode == "typing":
		if not _typing:
			_mode = ""
		else:
			_typing_phase += delta
			var frame: int = int(_typing_phase * 3.0) % 3
			if frame != _typing_frame:
				_typing_frame = frame
				_canvas.set_typing(frame)
				_render()
	if _mode == "" or far:
		_sprite.visible = false
		return
	_age += delta
	_sprite.visible = true
	## Pop in with a slight overshoot, drift up, fade out at the end.
	var t: float = clampf(_age / POP_TIME, 0.0, 1.0)
	var s: float = 0.82 + 0.18 * _ease_out_back(t)
	var alpha: float = t
	var rise: float = RISE * clampf(_age / 1.2, 0.0, 1.0)
	if _mode == "say":
		alpha = minf(alpha, clampf(_say_left / FADE_TIME, 0.0, 1.0))
		rise += RISE * (1.0 - clampf(_say_left / FADE_TIME, 0.0, 1.0))
	_sprite.scale = Vector3.ONE * s
	_sprite.modulate = Color(1, 1, 1, alpha)
	_sprite.position = Vector3(0.0, HEAD_CLEARANCE + rise, 0.0)

func _render() -> void:
	var size: Vector2 = _canvas.content_size()
	_vp.size = Vector2i(ceili(size.x), ceili(size.y))
	_canvas.size = size
	_canvas.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	## Anchor the tail tip (bottom centre) on the sprite's origin.
	_sprite.offset = Vector2(0.0, size.y * 0.5)

static func _ease_out_back(t: float) -> float:
	var c: float = 1.70158
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)

# ─── Sleep z's ──────────────────────────────────────────────────────────────
const Z_PERIOD: float = 2.6
const Z_COUNT: int = 3

func _tick_zs(delta: float, far: bool) -> void:
	if not _sleeping or far:
		for z: Label3D in _zs:
			z.visible = false
		_z_clock = 0.0
		return
	if _zs.is_empty():
		for i: int in Z_COUNT:
			var z: Label3D = Label3D.new()
			z.text = "z"
			z.font = UIKit.font()
			z.font_size = 72
			z.outline_size = 14
			z.outline_modulate = Color(0.05, 0.06, 0.08, 0.55)
			z.modulate = Color(0.80, 0.86, 0.95, 0.0)
			z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			z.pixel_size = 0.0028
			z.no_depth_test = false
			add_child(z)
			_zs.append(z)
	_z_clock += delta
	for i: int in _zs.size():
		var z: Label3D = _zs[i]
		var p: float = fposmod(_z_clock / Z_PERIOD - float(i) / float(Z_COUNT), 1.0)
		z.visible = true
		## Rise and drift sideways, grow a little, fade in then out.
		z.position = Vector3(0.12 + 0.22 * p, 0.12 + 0.55 * p, 0.0)
		z.scale = Vector3.ONE * (0.55 + 0.55 * p)
		var a: float = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.65, 1.0, p))
		z.modulate.a = 0.85 * a

# ─── Anchor ─────────────────────────────────────────────────────────────────
func _head_position() -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		_skeleton = null
		var model: Node = _npc.get_node_or_null("CharacterModel")
		if model != null:
			_skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
			if _skeleton != null:
				_head_bone = _skeleton.find_bone("Head")
	if _skeleton != null and _head_bone >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone).origin
	return _npc.global_position + Vector3(0.0, FALLBACK_HEAD_Y, 0.0)

## Draws the bubble itself (panel + tail + text, or the typing pill).
class _BubbleCanvas extends Control:
	var _text: String = ""
	var _typing_frame: int = -1
	var _text_size: Vector2 = Vector2.ZERO

	func set_speech(text: String) -> void:
		_text = text
		_typing_frame = -1
		var font: Font = UIKit.font()
		var one_line: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var w: float = minf(one_line.x, MAX_TEXT_W)
		_text_size = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w + 1.0, FONT_SIZE)

	func set_typing(frame: int) -> void:
		_text = ""
		_typing_frame = frame
		_text_size = Vector2(72.0, FONT_SIZE * 0.9)

	func content_size() -> Vector2:
		return _text_size + PAD * 2.0 + Vector2(SHADOW * 2.0, TAIL_H + SHADOW * 2.0)

	func _draw() -> void:
		var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)
		var body := Rect2(Vector2(SHADOW, SHADOW), _text_size + PAD * 2.0)
		var radius: float = minf(RADIUS, body.size.y * 0.5) if _typing_frame >= 0 else RADIUS
		## Soft drop shadow, then panel, then a thin border.
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0.28)
		shadow.set_corner_radius_all(int(radius) + 2)
		draw_style_box(shadow, Rect2(body.position + Vector2(0, 3), body.size))
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(theme.bg.r, theme.bg.g, theme.bg.b, 0.9)
		panel.border_color = Color(theme.border.r, theme.border.g, theme.border.b, 0.45)
		panel.set_border_width_all(2)
		panel.set_corner_radius_all(int(radius))
		panel.anti_aliasing = true
		draw_style_box(panel, body)
		## Tail: a small wedge from the panel's bottom centre to the speaker.
		var cx: float = body.position.x + body.size.x * 0.5
		var by: float = body.end.y - 2.0
		var tail := PackedVector2Array([
			Vector2(cx - TAIL_W * 0.5, by), Vector2(cx + TAIL_W * 0.5, by), Vector2(cx, by + TAIL_H)])
		draw_colored_polygon(tail, panel.bg_color)
		draw_polyline(PackedVector2Array([tail[0] + Vector2(0, 1), tail[2], tail[1] + Vector2(0, 1)]),
			panel.border_color, 2.0, true)
		if _typing_frame >= 0:
			var c: Vector2 = body.get_center()
			for i: int in 3:
				var on: bool = i == _typing_frame
				var col: Color = theme.text if on else Color(theme.text.r, theme.text.g, theme.text.b, 0.35)
				draw_circle(c + Vector2((i - 1) * 22.0, -3.0 if on else 0.0), 6.0 if on else 5.0, col, true, -1.0, true)
			return
		var font: Font = UIKit.font()
		draw_multiline_string(font, body.position + PAD + Vector2(0.0, font.get_ascent(FONT_SIZE)),
			_text, HORIZONTAL_ALIGNMENT_CENTER, _text_size.x + 1.0, FONT_SIZE, -1, theme.text)
