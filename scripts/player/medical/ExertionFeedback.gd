extends CanvasLayer
## Medical-owned additive feedback, below the HUD and all device panels.
## Never changes the existing power/critical vignette or captures input.

var player: Node = null
var _shade: ColorRect
var _label: Label
var _strength: float = 0.0
var _notice_seconds: float = 0.0
var _notice: String = ""

func _ready() -> void:
	layer = 0
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float strength = 0.0; void fragment() { float edge = smoothstep(0.28, 0.72, length((UV - vec2(0.5)) * vec2(1.0, 1.15))); COLOR = vec4(0.015, 0.02, 0.025, edge * strength); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	_shade.material = material
	root.add_child(_shade)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 90.0
	_label.offset_bottom = 152.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.94, 0.80, 0.60))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
	_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_label)
	add_to_group("exertion_feedback")

func show_accident(message: String) -> void:
	_notice = message
	_notice_seconds = 6.0

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var state = player.exertion
	var pushing: bool = state.legs_active or state.arms_active
	var target: float = (0.16 + 0.24 * state.intensity()) if pushing else 0.0
	if player.dead:
		target = 0.0
	_strength = move_toward(_strength, target * player.exertion_feedback_strength, delta * 0.35)
	_shade.visible = _strength > 0.001
	(_shade.material as ShaderMaterial).set_shader_parameter("strength", _strength)
	_notice_seconds = maxf(0.0, _notice_seconds - delta)
	var message: String = ""
	if pushing:
		message = "OVEREXERTING — slow down and put down the load" if state.legs_active and state.arms_active else (
			"OVEREXERTING — put down the load" if state.arms_active else "OVEREXERTING — stop sprinting to recover")
	elif state.exhausted or state.intensity() > 0.05:
		message = "Catching your breath"
	elif player.stamina < 20.0:
		message = "Stamina low — pushing past empty risks injury"
	if _notice_seconds > 0.0:
		message = _notice + ("\n" + message if not message.is_empty() else "")
	_label.text = "" if player.dead else message
	_label.visible = not _label.text.is_empty()
