extends CanvasLayer
class_name ZoneCustomizeUI
## ZoneCustomizeUI.gd  (July 2026)
## ─────────────────────────────────────────────────────────────────────────────
## Small reusable popup for customizing a wire zone's PLAYER-facing display:
## RENAME (typed text, replaces the default "Z0"/"Z1"/etc label) or RECOLOR
## (pick from a fixed 16-swatch palette). Opened by PowerTerminalUI for the
## terminal's OWN connected zone only — a terminal can only customize the
## zone it's wired into (see PowerTerminal.gd / PowerTerminalUI.gd).
##
## Persistence: PowerManager.set_zone_name()/set_zone_color_override() store
## the change keyed by the zone's stable "zone_key" identity (see
## ZoneCustomization.gd) — it survives wire add/remove/expansion exactly like
## the game's auto-assigned zone colors already do, and (per design) a
## player-picked color is NEVER overridden by the auto graph-coloring
## algorithm even if it clashes with a bordering zone's color.
##
## LIFECYCLE — same spawn-once/reuse pattern as PowerPriorityUI/
## GeneratorInspectUI: the caller keeps one instance alive (added directly to
## the scene tree root) and calls open_rename()/open_color() on it each time;
## it is never queue_free()d, only hidden via close().
##
## Built as a real Control node tree (per the "new panels use real Controls,
## not hand-drawn _draw()" convention — see GraphicsSettingsPanel.gd) since
## renaming needs a real LineEdit for text entry.
##
## MODES — only one mode's controls are visible at a time:
##   open_rename(zone_key, current_name)          — LineEdit + Apply button.
##     Enter or Apply commits and emits name_changed.
##   open_color(zone_key, current_display_color)  — 4x4 grid of the 16 fixed
##     swatches from DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES. Clicking one
##     commits immediately and emits color_changed. current_display_color is
##     used only to highlight a matching swatch if the zone's current color
##     happens to already be one of the 16 choices — harmless no-op otherwise.

signal closed
signal name_changed(zone_key: String, new_name: String)
signal color_changed(zone_key: String, new_color: Color)

# ─── Palette — matches PowerTerminalUI/PowerPriorityUI military theme ───────
const BG_COLOR:     Color = Color(0.07, 0.08, 0.07, 0.97)
const BORDER_COLOR: Color = Color(0.38, 0.85, 0.40, 0.80)
const HEADER_COLOR: Color = Color(0.32, 0.90, 0.38, 1.00)
const TEXT_COLOR:   Color = Color(0.82, 0.95, 0.84, 0.95)
const DIM_COLOR:    Color = Color(0.45, 0.55, 0.46, 0.80)

const PANEL_W:      float = 300.0
const SWATCH_SIZE:  float = 44.0
const SWATCH_GAP:   int   = 8
const GRID_COLS:    int   = 4

var _zone_key: String = ""

var _panel:     Panel = null
var _vbox:      VBoxContainer = null
var _title_lbl: Label = null

var _rename_box: VBoxContainer = null
var _name_edit:  LineEdit = null

var _color_box:      VBoxContainer = null
var _swatch_buttons: Array[Button] = []


func _ready() -> void:
	layer   = 60   ## Above PowerTerminalUI (layer 50) so it opens on top of it.
	visible = false
	_build_ui()


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color        = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position -= Vector2(PANEL_W * 0.5, 130.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 12)
	_vbox.position = Vector2(16.0, 16.0)
	_vbox.custom_minimum_size = Vector2(PANEL_W - 32.0, 0.0)
	_panel.add_child(_vbox)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 14)
	_title_lbl.add_theme_color_override("font_color", HEADER_COLOR)
	_vbox.add_child(_title_lbl)
	_vbox.add_child(HSeparator.new())

	## ── Rename mode controls ─────────────────────────────────────────────────
	_rename_box = VBoxContainer.new()
	_rename_box.add_theme_constant_override("separation", 8)
	_vbox.add_child(_rename_box)

	var name_lbl: Label = Label.new()
	name_lbl.text = "Zone name"
	name_lbl.add_theme_color_override("font_color", DIM_COLOR)
	_rename_box.add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.max_length        = 18
	_name_edit.placeholder_text  = "Z0"
	_name_edit.text_submitted.connect(_on_name_submitted)
	_rename_box.add_child(_name_edit)

	var apply_btn: Button = Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(func() -> void: _on_name_submitted(_name_edit.text))
	_rename_box.add_child(apply_btn)

	## ── Color mode controls ──────────────────────────────────────────────────
	_color_box = VBoxContainer.new()
	_color_box.add_theme_constant_override("separation", 8)
	_vbox.add_child(_color_box)

	var color_lbl: Label = Label.new()
	color_lbl.text = "Pick a zone color"
	color_lbl.add_theme_color_override("font_color", DIM_COLOR)
	_color_box.add_child(color_lbl)

	var grid: GridContainer = GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", SWATCH_GAP)
	grid.add_theme_constant_override("v_separation", SWATCH_GAP)
	_color_box.add_child(grid)

	_swatch_buttons.clear()
	for i: int in DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES.size():
		var swatch_color: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[i]
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		var sbox: StyleBoxFlat = StyleBoxFlat.new()
		sbox.bg_color = swatch_color
		sbox.set_border_width_all(2)
		sbox.border_color = Color(0.0, 0.0, 0.0, 0.4)
		btn.add_theme_stylebox_override("normal", sbox)
		var sbox_hover: StyleBoxFlat = sbox.duplicate()
		sbox_hover.border_color = Color(1.0, 1.0, 1.0, 0.9)
		btn.add_theme_stylebox_override("hover", sbox_hover)
		btn.add_theme_stylebox_override("pressed", sbox_hover)
		btn.pressed.connect(_on_swatch_pressed.bind(i))
		grid.add_child(btn)
		_swatch_buttons.append(btn)

	_vbox.add_child(HSeparator.new())
	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	_vbox.add_child(close_btn)


## Opens in RENAME mode for the given zone.
func open_rename(zone_key: String, current_name: String) -> void:
	_zone_key = zone_key
	_title_lbl.text     = "RENAME ZONE"
	_rename_box.visible = true
	_color_box.visible  = false
	_name_edit.text     = current_name
	visible = true
	UIFade.fade_in(_panel)   ## Standing convention (July 2026) — see UIFade.gd.
	## Deferred so it grabs focus after this frame's layout/visibility settle.
	_name_edit.call_deferred("grab_focus")
	_name_edit.call_deferred("select_all")


## Opens in COLOR-PICK mode for the given zone.
func open_color(zone_key: String, current_display_color: Color) -> void:
	_zone_key = zone_key
	_title_lbl.text     = "ZONE COLOR"
	_rename_box.visible = false
	_color_box.visible  = true
	_highlight_matching_swatch(current_display_color)
	visible = true
	UIFade.fade_in(_panel)


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _on_name_submitted(text: String) -> void:
	name_changed.emit(_zone_key, text)
	close()


func _on_swatch_pressed(index: int) -> void:
	var c: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[index]
	color_changed.emit(_zone_key, c)
	close()


func _highlight_matching_swatch(current_color: Color) -> void:
	for i: int in _swatch_buttons.size():
		var btn: Button = _swatch_buttons[i]
		var swatch_color: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[i]
		var is_match: bool = swatch_color.is_equal_approx(current_color)
		var sbox: StyleBoxFlat = (btn.get_theme_stylebox("normal") as StyleBoxFlat).duplicate()
		sbox.border_color = Color(1.0, 1.0, 1.0, 0.95) if is_match else Color(0.0, 0.0, 0.0, 0.4)
		sbox.set_border_width_all(3 if is_match else 2)
		btn.add_theme_stylebox_override("normal", sbox)
