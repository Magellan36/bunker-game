extends CanvasLayer
## WaterDispenserUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## The water system's first INTERACTIVE panel (Jul 2026) — a real rate slider
## + on/off toggle for WaterDispenser, built as a genuine Control/HSlider/
## CheckBox node tree (mirrors GraphicsSettingsPanel.gd's precedent), NOT
## hand-drawn _draw() calls like WaterInfoUI.gd/PowerPriorityUI.gd. This is a
## meaningfully different shape than those read-only info popups (interactive
## slider + toggle vs. static stat display), so it gets its own file rather
## than being forced into WaterInfoUI.gd.
##
## Lifecycle: spawned once by WaterDispenser.on_interact(), reused on
## subsequent opens — same spawn-once-reuse pattern as every other water/
## power device panel in this project.
##
## Everything is pulled live every frame while open (no caching) — the slider
## max (dynamic ceiling, see WaterSolver.get_dynamic_max_for_device()) and the
## actual effective rate both need to react instantly to any OTHER device's
## priority/on-off/slider changing anywhere in the network, per the plan.
##
## Signals:
##   closed — player dismissed the panel (Escape / E / close button)

signal closed

# ─── Palette (matches WaterInfoUI's blue accent — same system, same theme) ───
const BG_COLOR:     Color = Color(0.06, 0.08, 0.10, 0.97)
const BORDER_COLOR: Color = Color(0.35, 0.70, 0.95, 0.90)
const TEXT_COLOR:   Color = Color(0.85, 0.92, 0.97, 0.95)
const OK_COLOR:     Color = Color(0.35, 0.85, 1.00, 1.00)
const WARN_COLOR:   Color = Color(1.00, 0.72, 0.10, 1.00)
const CRIT_COLOR:   Color = Color(1.00, 0.35, 0.30, 1.00)

const PANEL_W: float = 360.0

var _dispenser: WaterDispenser = null
var _is_open: bool = false

# ─── Node refs ────────────────────────────────────────────────────────────────
var _backdrop:      ColorRect       = null
var _panel:         Panel           = null
var _vbox:          VBoxContainer   = null
var _title_lbl:     Label           = null
var _fill_lbl:      Label           = null
var _rate_slider:   HSlider         = null
var _rate_lbl:      Label           = null
var _effective_lbl: Label           = null
var _on_check:      CheckBox        = null
var _quality_lbl:   Label           = null
var _max_hint_lbl:  Label           = null


func _ready() -> void:
	layer   = 60
	visible = false
	set_process(false)
	_build_ui()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position -= Vector2(PANEL_W * 0.5, 150.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_vbox.position = Vector2(18.0, 16.0)
	_vbox.custom_minimum_size = Vector2(PANEL_W - 36.0, 0.0)
	_panel.add_child(_vbox)

	_title_lbl = Label.new()
	_title_lbl.text = "WATER DISPENSER"
	_title_lbl.add_theme_font_size_override("font_size", 16)
	_title_lbl.add_theme_color_override("font_color", BORDER_COLOR)
	_vbox.add_child(_title_lbl)
	_vbox.add_child(HSeparator.new())

	_fill_lbl = Label.new()
	_fill_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	_vbox.add_child(_fill_lbl)

	_vbox.add_child(HSeparator.new())

	var rate_hdr: Label = Label.new()
	rate_hdr.text = "Requested Rate"
	rate_hdr.add_theme_font_size_override("font_size", 11)
	rate_hdr.add_theme_color_override("font_color", TEXT_COLOR)
	_vbox.add_child(rate_hdr)

	_rate_slider = HSlider.new()
	_rate_slider.min_value = 0.0
	_rate_slider.max_value = 0.0   ## Set live every frame from the dynamic max — see _pull_live().
	_rate_slider.step      = 10.0
	_rate_slider.custom_minimum_size = Vector2(0.0, 24.0)
	_rate_slider.value_changed.connect(_on_rate_changed)
	_vbox.add_child(_rate_slider)

	_rate_lbl = Label.new()
	_rate_lbl.add_theme_font_size_override("font_size", 11)
	_rate_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	_vbox.add_child(_rate_lbl)

	_max_hint_lbl = Label.new()
	_max_hint_lbl.add_theme_font_size_override("font_size", 9)
	_max_hint_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.62, 0.80))
	_vbox.add_child(_max_hint_lbl)

	_vbox.add_child(HSeparator.new())

	_effective_lbl = Label.new()
	_effective_lbl.add_theme_color_override("font_color", OK_COLOR)
	_vbox.add_child(_effective_lbl)

	_vbox.add_child(HSeparator.new())

	_on_check = CheckBox.new()
	_on_check.text = "Dispenser On"
	_on_check.toggled.connect(_on_toggle)
	_vbox.add_child(_on_check)

	_vbox.add_child(HSeparator.new())

	_quality_lbl = Label.new()
	_quality_lbl.add_theme_font_size_override("font_size", 10)
	_quality_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.62, 0.80))
	_vbox.add_child(_quality_lbl)

	_vbox.add_child(HSeparator.new())

	var close_btn: Button = Button.new()
	close_btn.text = "Close  [ESC / E]"
	close_btn.pressed.connect(close)
	_vbox.add_child(close_btn)


# ─── Open / Close ─────────────────────────────────────────────────────────────
func open(dispenser: WaterDispenser) -> void:
	_dispenser = dispenser
	_is_open   = true
	visible    = true
	set_process(true)
	_pull_live()
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_panel)


func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	closed.emit()


func is_open() -> bool:
	return _is_open


# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()


# ─── Live refresh ─────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _dispenser == null or not is_instance_valid(_dispenser):
		close()
		return
	_pull_live()


func _pull_live() -> void:
	var d: WaterDispenser = _dispenser
	if d == null or not is_instance_valid(d):
		return

	## Fill level.
	_fill_lbl.text = "%.0f / %.0f mL" % [d.current_fill_mL, WaterDispenser.MAX_STORAGE_ML]

	## Dynamic slider max — reacts live to any other device's priority/on-off/
	## slider changing anywhere in the network (WaterSolver.gd).
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	var dynamic_max: float = 0.0
	if wm != null:
		dynamic_max = wm.get_dynamic_max_mL_per_day(d.get_node_key(), d.priority)
	_rate_slider.max_value = dynamic_max

	## Reflect the dispenser's own current requested rate (source of truth —
	## WaterDispenser._process() reclamps this every solve pass, so this can
	## drop on its own even while the panel sits open and untouched).
	_rate_slider.value = d.requested_rate_mL_per_day
	_rate_lbl.text = "%.0f mL/day  (%.2f mL/min)" % [d.requested_rate_mL_per_day, d.requested_rate_mL_per_day / 1440.0]
	_max_hint_lbl.text = "Network max right now: %.0f mL/day" % dynamic_max

	## Current EFFECTIVE (actually received) rate — can be less than
	## requested if this device's tier is oversubscribed elsewhere.
	var effective_day: float = 0.0
	if wm != null and not d.get_node_key().is_empty():
		var info: Dictionary = wm.get_received_rate_mL(d.get_node_key())
		effective_day = float(info.get("mL_per_day", 0.0))
	var eff_col: Color = OK_COLOR
	if not d.is_on:
		eff_col = Color(0.55, 0.55, 0.55, 1.0)
	elif effective_day < d.requested_rate_mL_per_day - 1.0:
		eff_col = WARN_COLOR
	_effective_lbl.add_theme_color_override("font_color", eff_col)
	_effective_lbl.text = "Receiving: %.0f mL/day  (%.2f mL/min)" % [effective_day, effective_day / 1440.0]

	_on_check.set_block_signals(true)
	_on_check.button_pressed = d.is_on
	_on_check.set_block_signals(false)

	_quality_lbl.text = "Water Quality: %.0f%%  (placeholder — not yet simulated)" % d.stored_water_quality


# ─── Handlers ─────────────────────────────────────────────────────────────────
func _on_rate_changed(value: float) -> void:
	if _dispenser == null or not is_instance_valid(_dispenser):
		return
	_dispenser.set_requested_rate(value)

func _on_toggle(pressed: bool) -> void:
	if _dispenser == null or not is_instance_valid(_dispenser):
		return
	_dispenser.set_on(pressed)
