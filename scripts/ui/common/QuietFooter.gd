extends HBoxContainer
## QuietFooter.gd (Sep 2026) — the shared workspace/inspector footer:
##   [COST TAG] contextual hint line …………… ✓ Saved   [key hints]
## The hint line always describes whatever is focused (QuietFocusController
## feeds it) and falls back to `idle_hint`. See QUIET_DESIGN_SYSTEM.md §3.

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

var idle_hint: String = "":
	set(value):
		idle_hint = value
		if hint_label != null and _current_help.is_empty():
			hint_label.text = idle_hint

var cost_label: Label
var hint_label: Label
var saved_label: Label
var _hints: HBoxContainer
var _saved_tween: Tween
var _current_help: String = ""


func _init() -> void:
	name = "Footer"
	add_theme_constant_override("separation", 14)
	custom_minimum_size.y = 28.0
	cost_label = Q.label("", 11, Q.HEADING)
	cost_label.name = "CostTag"
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.visible = false
	Q.tracked(cost_label, 2)
	add_child(cost_label)
	hint_label = Q.label(idle_hint, 14, Q.MUTED)
	hint_label.name = "Hint"
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_label.clip_text = true
	add_child(hint_label)
	saved_label = Q.label("✓  Saved", 13, Q.ACCENT)
	saved_label.name = "SavedConfirmation"
	saved_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	saved_label.modulate.a = 0.0
	add_child(saved_label)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)
	_hints = HBoxContainer.new()
	_hints.name = "KeyHints"
	_hints.add_theme_constant_override("separation", 22)
	add_child(_hints)


func add_key_hint(key_text: String, action_text: String, keyboard_key: String = "",
		controller_key: String = "") -> void:
	BunkerUIComponents.key_hint(_hints, key_text, action_text, keyboard_key, controller_key)


func show_hint(help: String, cost: String = "") -> void:
	_current_help = help
	var next := help if not help.is_empty() else idle_hint
	if hint_label.text != next:
		hint_label.text = next
		UIFade.content(hint_label)
	cost_label.text = cost.to_upper()
	cost_label.visible = not cost.is_empty()


func flash_saved(text: String = "✓  Saved") -> void:
	saved_label.text = text
	if is_instance_valid(_saved_tween):
		_saved_tween.kill()
	_saved_tween = create_tween()
	_saved_tween.tween_property(saved_label, "modulate:a", 1.0, UIMotion.duration(0.14))
	_saved_tween.tween_interval(1.4)
	_saved_tween.tween_property(saved_label, "modulate:a", 0.0, UIMotion.duration(0.6))


func hide_saved() -> void:
	if is_instance_valid(_saved_tween):
		_saved_tween.kill()
	saved_label.modulate.a = 0.0
