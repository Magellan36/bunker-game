extends CanvasLayer
## AdminMenu.gd
## F8 general-purpose admin controls panel — distinct from AdminSpawnMenu.gd
## (F10, spawns physical objects). This one is for direct system cheats/
## debug toggles that don't correspond to a placeable object.
## Injected refs set by MainWorld._toggle_admin_menu().

# ─── Injected by MainWorld ────────────────────────────────────────────────────
var world_node: Node3D = null

# ─── State ───────────────────────────────────────────────────────────────────
var _visible_state: bool = false
var _panel:         Panel        = null
var _vbox:          VBoxContainer = null

const ADMIN_POWER_STEP_WATTS: float = 1000.0

func _ready() -> void:
	layer = 128   ## On top of everything — same as AdminSpawnMenu
	_build_ui()
	visible = false

func toggle() -> void:
	_visible_state = not _visible_state
	visible = _visible_state
	if _visible_state:
		## Standing convention (July 2026) — see UIFade.gd.
		UIFade.fade_in(_panel)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ─── UI Construction (mirrors AdminSpawnMenu.gd's styling) ────────────────────
func _build_ui() -> void:
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(260, 160)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -130.0
	_panel.offset_right  = 130.0
	_panel.offset_top    = -80.0
	_panel.offset_bottom = 80.0

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.08, 0.10, 0.92)
	style.border_color = Color(0.30, 0.30, 0.35, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var header: Label = Label.new()
	header.text = "[F8]  Admin Controls"
	header.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80, 1.0))
	header.add_theme_font_size_override("font_size", 13)
	header.position = Vector2(10, 8)
	_panel.add_child(header)

	var sep: HSeparator = HSeparator.new()
	sep.position = Vector2(8, 28)
	sep.size     = Vector2(244, 2)
	_panel.add_child(sep)

	var sec: Label = Label.new()
	sec.text = "─── Power ───"
	sec.add_theme_color_override("font_color", Color(0.45, 0.60, 0.55, 1.0))
	sec.add_theme_font_size_override("font_size", 10)
	sec.position = Vector2(10, 36)
	_panel.add_child(sec)

	_vbox = VBoxContainer.new()
	_vbox.position = Vector2(8, 56)
	_vbox.custom_minimum_size = Vector2(244, 0)
	_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(_vbox)

	_vbox.add_child(_make_button("+ %d w Power" % int(ADMIN_POWER_STEP_WATTS), _on_add_power_pressed))
	_vbox.add_child(_make_button("- %d w Power" % int(ADMIN_POWER_STEP_WATTS), _on_remove_power_pressed))

func _make_button(label: String, cb: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(244, 28)
	btn.add_theme_font_size_override("font_size", 12)

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color     = Color(0.15, 0.16, 0.18, 0.90)
	btn_style.border_color = Color(0.28, 0.28, 0.32, 0.80)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", btn_style)

	var hover_style: StyleBoxFlat = btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color     = Color(0.22, 0.30, 0.25, 0.95)
	hover_style.border_color = Color(0.45, 0.65, 0.50, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.pressed.connect(cb)
	return btn

# ─── Button callbacks ──────────────────────────────────────────────────────────
func _get_power_manager() -> PowerManager:
	return get_tree().get_first_node_in_group("power_manager") as PowerManager

func _on_add_power_pressed() -> void:
	var pm: PowerManager = _get_power_manager()
	if pm != null:
		pm.admin_add_power(ADMIN_POWER_STEP_WATTS)

func _on_remove_power_pressed() -> void:
	var pm: PowerManager = _get_power_manager()
	if pm != null:
		pm.admin_add_power(-ADMIN_POWER_STEP_WATTS)
