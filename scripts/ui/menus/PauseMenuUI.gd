extends CanvasLayer
## PauseMenuUI.gd
## ESC pause menu — blurred backdrop + minimalist panel with Continue,
## Save (3 slots), Load (3 slots), Settings (stub), Exit Game (confirm).
##
## Design note: visual style here is a deliberately plain placeholder per the
## user's request ("minimalist, we'll work on design later") — the STRUCTURE
## (blur backdrop, slot buttons, confirm dialog, save/load wiring) is the
## real deliverable this pass; restyling later only touches this file's
## _build_ui()/_style_* helpers, not MainWorld/SaveManager/Player wiring.
##
## Injected by MainWorld._toggle_pause_menu(): world_node, player.
## Game keeps running while this is open (no SceneTree.paused) — only player
## movement is locked (Player.set_movement_locked) and mouse is freed, per the
## "game continues while paused" decision.

# ─── Injected by MainWorld ────────────────────────────────────────────────────
var world_node: Node3D = null
var player:     Node3D = null

# ─── State ────────────────────────────────────────────────────────────────────
var _visible_state: bool = false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

# ─── Root nodes ───────────────────────────────────────────────────────────────
var _blur_rect:   ColorRect = null
var _panel:       Panel     = null
var _vbox:        VBoxContainer = null
var _confirm_layer: CanvasLayer = null   ## separate top layer for the exit-confirm dialog
var _settings_panel: CanvasLayer = null  ## lazy-instantiated GraphicsSettingsPanel, same pattern as MainWorld's own lazy PauseMenuUI instantiation
var _history_ui: Control = null          ## NotificationHistoryUI, sibling of _panel — shows/hides for free with this CanvasLayer's own visible toggle

# ─── Slot button refs (so we can refresh labels on open) ─────────────────────
var _save_slot_buttons: Array[Button] = []
var _load_slot_buttons: Array[Button] = []

const PANEL_W: float = 360.0
const BLUR_SHADER_PATH: String = "res://assets/shaders/pause_blur.gdshader"


func _ready() -> void:
	layer = 200   ## Above HUD (default ~1) and AdminSpawnMenu (128).
	_build_ui()
	visible = false


# ─── Open / close ─────────────────────────────────────────────────────────────
func toggle() -> void:
	if _visible_state:
		close()
	else:
		open()


func open() -> void:
	if _visible_state:
		return
	_visible_state = true
	visible = true
	## Standing convention (July 2026) — see UIFade.gd. _blur_rect stays
	## instant (blurring in would look odd); only the panel content fades.
	UIFade.fade_in(_panel)
	if _history_ui != null:
		UIFade.fade_in(_history_ui)
	_refresh_slot_labels()
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null and player.has_method("set_movement_locked"):
		player.call("set_movement_locked", true)


func close() -> void:
	if not _visible_state:
		return
	_visible_state = false
	visible = false
	_close_confirm_dialog()
	Input.mouse_mode = _prev_mouse_mode
	if player != null and player.has_method("set_movement_locked"):
		player.call("set_movement_locked", false)


func is_open() -> bool:
	return _visible_state


# ─── Input: ESC closes (toggle is driven by MainWorld's ESC handler; this is
## a safety net in case this menu ever receives input directly) ───────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _visible_state:
		return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		## If the exit-confirm dialog is open, ESC cancels that first instead
		## of closing the whole pause menu underneath it.
		if _confirm_layer != null:
			_close_confirm_dialog()
		else:
			close()
		get_viewport().set_input_as_handled()


# ─── UI construction ──────────────────────────────────────────────────────────
func _build_ui() -> void:
	## Full-screen blur backdrop — samples SCREEN_TEXTURE via shader so the
	## paused (but still-running) world behind it reads as blurred+dimmed.
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_STOP   ## eat clicks so world doesn't get them
	## ALWAYS set a sane dim base color first (ColorRect defaults to opaque
	## WHITE otherwise). If the shader below fails to render for any reason
	## (GPU/driver-specific — the shader loading successfully as a Resource
	## does NOT guarantee it compiles/executes correctly on every machine),
	## this dim color is what actually shows instead of a solid white screen.
	_blur_rect.color = Color(0.0, 0.0, 0.0, 0.55)
	var blur_shader: Shader = load(BLUR_SHADER_PATH)
	if blur_shader != null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = blur_shader
		_blur_rect.material = mat
	## else: no material assigned at all — the dim .color set above already
	## covers this case, so the old separate fallback assignment is gone.
	add_child(_blur_rect)

	## Center panel.
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)   ## height grows with content
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -PANEL_W * 0.5
	_panel.offset_right  =  PANEL_W * 0.5
	_panel.offset_top    = -260.0
	_panel.offset_bottom =  260.0

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color     = Color(0.07, 0.07, 0.08, 0.94)
	panel_style.border_color = Color(0.35, 0.35, 0.38, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left   = 20.0
	panel_style.content_margin_right  = 20.0
	panel_style.content_margin_top    = 18.0
	panel_style.content_margin_bottom = 18.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(_vbox)

	## Notification history — sibling of _panel (NOT nested inside it or
	## _blur_rect), positioned independently in the upper-right quadrant.
	## Shows/hides for free with this CanvasLayer's own `visible` toggle.
	var history_script: GDScript = load("res://scripts/ui/notifications/NotificationHistoryUI.gd")
	if history_script != null:
		_history_ui = Control.new()
		_history_ui.set_script(history_script)
		_history_ui.name = "NotificationHistoryUI"
		add_child(_history_ui)
	else:
		push_warning("[PauseMenu] NotificationHistoryUI.gd not found")

	## Title.
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.90, 0.90, 0.92, 1.0))
	_vbox.add_child(title)

	_vbox.add_child(HSeparator.new())

	## Continue.
	_vbox.add_child(_make_button("Continue", _on_continue_pressed))

	_vbox.add_child(_make_section_label("Save"))
	var save_row: HBoxContainer = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(save_row)
	for i: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var btn: Button = _make_button("Slot %d" % i, _on_save_slot_pressed.bind(i))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		save_row.add_child(btn)
		_save_slot_buttons.append(btn)

	_vbox.add_child(_make_section_label("Load"))
	var load_row: HBoxContainer = HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(load_row)
	for i: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var btn2: Button = _make_button("Slot %d" % i, _on_load_slot_pressed.bind(i))
		btn2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_row.add_child(btn2)
		_load_slot_buttons.append(btn2)

	_vbox.add_child(HSeparator.new())

	## Settings — stub, does nothing yet.
	_vbox.add_child(_make_button("Settings", _on_settings_pressed))

	## Exit Game — confirm dialog first.
	var exit_btn: Button = _make_button("Exit Game", _on_exit_pressed)
	exit_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.50, 1.0))
	_vbox.add_child(exit_btn)


## Shared minimalist button factory — flat dark style, no icons. Restyle here
## later without touching any of the wiring above.
func _make_button(text: String, cb: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, 32.0)
	btn.add_theme_font_size_override("font_size", 13)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.14, 0.14, 0.16, 0.95)
	style.border_color = Color(0.30, 0.30, 0.33, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)

	var hover: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover.bg_color     = Color(0.20, 0.20, 0.23, 0.98)
	hover.border_color = Color(0.55, 0.55, 0.60, 1.0)
	btn.add_theme_stylebox_override("hover", hover)

	btn.pressed.connect(cb)
	return btn


func _make_section_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 1.0))
	return lbl


## Refreshes save/load slot button labels to show occupied/empty + timestamp.
## Called every time the menu opens so slot info is always current.
func _refresh_slot_labels() -> void:
	for i: int in range(_save_slot_buttons.size()):
		var slot: int = i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		if info.get("exists", false):
			_save_slot_buttons[i].text = "Slot %d\n(overwrite)" % slot
		else:
			_save_slot_buttons[i].text = "Slot %d\n(empty)" % slot

	for i: int in range(_load_slot_buttons.size()):
		var slot: int = i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		if info.get("exists", false):
			_load_slot_buttons[i].text = "Slot %d\nDay %s  %s" % [
				slot, str(info.get("day", "?")), str(info.get("time_display", "?"))]
			_load_slot_buttons[i].disabled = false
		else:
			_load_slot_buttons[i].text = "Slot %d\n(empty)" % slot
			_load_slot_buttons[i].disabled = true


# ─── Button handlers ──────────────────────────────────────────────────────────
func _on_continue_pressed() -> void:
	close()

func _on_save_slot_pressed(slot: int) -> void:
	SaveManager.save_game(slot)
	_refresh_slot_labels()

func _on_load_slot_pressed(slot: int) -> void:
	SaveManager.load_game(slot)
	close()

func _on_settings_pressed() -> void:
	if _settings_panel == null:
		var script: GDScript = load("res://scripts/ui/menus/GraphicsSettingsPanel.gd")
		if script == null:
			push_warning("[PauseMenu] GraphicsSettingsPanel.gd not found")
			return
		_settings_panel = CanvasLayer.new()
		_settings_panel.set_script(script)
		_settings_panel.name = "GraphicsSettingsPanel"
		## Added as a sibling of this menu (both are children of MainWorld,
		## the same parent PauseMenuUI itself was added to) rather than a
		## child of PauseMenuUI, so its own `layer` ordering applies cleanly.
		get_parent().add_child(_settings_panel)
	if _settings_panel.has_method("open"):
		_settings_panel.open()

func _on_exit_pressed() -> void:
	_open_confirm_dialog(
		"Exit to desktop? Any unsaved progress will be lost.",
		func() -> void: get_tree().quit())


# ─── Minimalist confirm dialog (custom, no ConfirmationDialog node — keeps
## the same plain Control-node style as the rest of this menu) ───────────────
func _open_confirm_dialog(message: String, on_confirm: Callable) -> void:
	_close_confirm_dialog()   ## safety: never stack two

	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 210   ## above the pause menu itself
	add_child(_confirm_layer)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(dim)

	var panel: Panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -180.0
	panel.offset_right  =  180.0
	panel.offset_top    = -70.0
	panel.offset_bottom =  70.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.10, 0.10, 0.11, 0.98)
	style.border_color = Color(0.45, 0.45, 0.48, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left   = 16.0
	style.content_margin_right  = 16.0
	style.content_margin_top    = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	_confirm_layer.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var lbl: Label = Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.90, 1.0))
	vbox.add_child(lbl)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	var yes_btn: Button = _make_button("Yes", func() -> void:
		_close_confirm_dialog()
		on_confirm.call())
	yes_btn.custom_minimum_size = Vector2(100.0, 30.0)
	row.add_child(yes_btn)

	var no_btn: Button = _make_button("No", _close_confirm_dialog)
	no_btn.custom_minimum_size = Vector2(100.0, 30.0)
	row.add_child(no_btn)


func _close_confirm_dialog() -> void:
	if _confirm_layer != null and is_instance_valid(_confirm_layer):
		_confirm_layer.queue_free()
	_confirm_layer = null
