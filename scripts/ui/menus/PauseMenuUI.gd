extends CanvasLayer
## PauseMenuUI.gd
## ESC pause menu — blurred backdrop + minimalist panel with Continue,
## Save (3 slots), Load (3 slots), Settings, Exit Game (confirm).
##
## Jul 2026 — restyled onto the shared UIKit menu-builder helpers
## (build_modal_backdrop/build_centered_panel/make_button/
## make_section_label) as part of the "unify every menu" pass. Structure
## and all wiring (MainWorld/SaveManager/Player) unchanged — only
## construction/styling code moved into UIKit.
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
## Lazy-instantiated shared ConfirmDialogUI (Aug 2026 consistency pass) —
## replaces the hand-rolled exit-confirm layer. Layer 210, above the pause
## menu (200). Set to 210 via the dialog's stacking_layer export.
var _confirm_dialog: CanvasLayer = null
var _exit_confirmed_connected: bool = false
var _settings_panel: CanvasLayer = null  ## lazy-instantiated GraphicsSettingsPanel, same pattern as MainWorld's own lazy PauseMenuUI instantiation
var _history_ui: Control = null          ## NotificationHistoryUI, sibling of _panel — shows/hides for free with this CanvasLayer's own visible toggle

# ─── Slot button refs (so we can refresh labels on open) ──────────────────────
var _save_slot_buttons: Array[Button] = []
var _load_slot_buttons: Array[Button] = []

const PANEL_H: float = 520.0   ## fixed height (Jul 2026 — was implicit via offset_top/bottom math)


func _ready() -> void:
	layer = 200   ## Above HUD (default ~1) and AdminMenu (128).
	_build_ui()
	visible = false
	## Controller navigation (Aug 2026) — d-pad + left stick drive focus
	## (stick_navigation is safe here: movement is locked while paused),
	## B closes this UI. See scripts/ui/common/ControllerUINavigation.gd.
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	controller_nav.stick_navigation = true
	add_child(controller_nav)


# ─── Open / close ───────────────────────────────────────────────────────────
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
		if _confirm_dialog != null and _confirm_dialog.has_method("is_open") \
				and _confirm_dialog.call("is_open"):
			_close_confirm_dialog()
		else:
			close()
		get_viewport().set_input_as_handled()


# ─── UI construction ────────────────────────────────────────────────────────
func _build_ui() -> void:
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

	## Full-screen blur backdrop — samples SCREEN_TEXTURE via shader so the
	## paused (but still-running) world behind it reads as blurred+dimmed.
	_blur_rect = UIKit.build_modal_backdrop()
	add_child(_blur_rect)

	## Center panel — fixed size, always correctly centered regardless of
	## how much content ends up inside it (see UIKit.build_centered_panel).
	_panel = UIKit.build_centered_panel(UIKit.MENU_PANEL_W, PANEL_H, theme)
	var panel_style: StyleBoxFlat = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	panel_style.content_margin_left   = 20.0
	panel_style.content_margin_right  = 20.0
	panel_style.content_margin_top    = 24.0   ## Jul 2026 — +6px top-padding pass, was 18.0
	panel_style.content_margin_bottom = 18.0
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
	title.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", theme.header)
	title.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(title)

	_vbox.add_child(HSeparator.new())

	## Continue.
	_vbox.add_child(UIKit.make_button("Continue", _on_continue_pressed))

	_vbox.add_child(UIKit.make_section_label("Save", theme))
	var save_row: HBoxContainer = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(save_row)
	for i: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var btn: Button = UIKit.make_button("Slot %d" % i, _on_save_slot_pressed.bind(i))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		save_row.add_child(btn)
		_save_slot_buttons.append(btn)

	_vbox.add_child(UIKit.make_section_label("Load", theme))
	var load_row: HBoxContainer = HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(load_row)
	for i: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var btn2: Button = UIKit.make_button("Slot %d" % i, _on_load_slot_pressed.bind(i))
		btn2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_row.add_child(btn2)
		_load_slot_buttons.append(btn2)

	_vbox.add_child(HSeparator.new())

	## Settings.
	_vbox.add_child(UIKit.make_button("Settings", _on_settings_pressed))

	## Exit Game — confirm dialog first. Red text is a deliberate "danger"
	## signal, kept as a per-instance override on top of the shared button
	## style, not a base-style inconsistency.
	var exit_btn: Button = UIKit.make_button("Exit Game", _on_exit_pressed)
	exit_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.50, 1.0))
	_vbox.add_child(exit_btn)


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


# ─── Button handlers ────────────────────────────────────────────────────────
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
	_ensure_confirm_dialog()
	_confirm_dialog.open("Exit to desktop?", "Any unsaved progress will be lost.")
	## Spawn-once/reuse dialog — connect confirmed to quit exactly once (the
	## dialog is only ever opened by the Exit button here, so confirmed is
	## always "quit").
	if not _exit_confirmed_connected:
		_confirm_dialog.confirmed.connect(func() -> void: get_tree().quit())
		_exit_confirmed_connected = true


## Lazy-create the shared ConfirmDialogUI above the pause menu's layer.
func _ensure_confirm_dialog() -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		return
	var dlg_script: GDScript = load("res://scripts/ui/common/ConfirmDialogUI.gd")
	if dlg_script == null:
		push_warning("[PauseMenuUI] ConfirmDialogUI.gd not found")
		return
	_confirm_dialog = CanvasLayer.new()
	_confirm_dialog.set_script(dlg_script)
	_confirm_dialog.name = "ConfirmDialogUI"
	_confirm_dialog.set("stacking_layer", 210)
	add_child(_confirm_dialog)


func _close_confirm_dialog() -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		_confirm_dialog.call("close")