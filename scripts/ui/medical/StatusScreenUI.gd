extends CanvasLayer
class_name StatusScreenUI
## StatusScreenUI.gd
## Medical Status Screen (Layer 3 deep-dive) — Aug 2026.
## Full design: docs/systems/medical/README.md's "Presentation" section
## ("Layer 3 — Future Status Screen") and "Body-part-differentiated symptom
## effects" (this screen reuses PlayerMedical's existing per-condition
## tooltip text / ring colors rather than inventing a second description
## of the same data — see get_status_detail_text()/get_condition_ring_
## color() on PlayerMedical).
##
## NON-MODAL BY DESIGN (Brannon's explicit call) — unlike PauseMenuUI/
## StorageUI/etc, opening this screen does NOT pause anything and does NOT
## lock player movement (no SceneTree.paused, no Player.set_job_locked()).
## The world keeps running — NPCs, hazards, the game clock, everything —
## while the player browses their own condition list. Toggled with [Tab]
## (MainWorld._unhandled_input()), not tied to any existing menu. Mouse is
## set VISIBLE while open so the diagram/tabs are clickable, same as every
## other panel — that's the one practical concession to "modal-feeling"
## this makes; movement/camera-look just aren't blocked at the game-logic
## level while the cursor is up.
##
## PLAYER-ONLY FOR NOW, BUT NPC-SHAPED ON PURPOSE: per Brannon's explicit
## direction, this same screen is expected to eventually be reachable for
## NPCs too (via NPCTalkMenuUI), showing that NPC's own conditions instead
## of the player's. Nothing NPC-side is wired yet — but this file takes
## explicit player_medical/player_stats refs (injected by MainWorld) rather
## than reaching into the "player_medical"/"player_stats" groups itself,
## specifically so a future NPC-facing instance (or a refactor to accept
## any entity's Medical component) doesn't require restructuring this file.
##
## FUTURE WORK (flagged, not built): applying a held treatment item
## directly from this screen (skipping the existing hold-item-then-[E]
## injury-selection submenu) — Brannon wants to explore this later. For
## now this screen is read-only; the submenu remains the one treatment
## path. See docs/systems/medical/README.md's "Injury-selection submenu".
##
## ALSO ANTICIPATED, NOT BUILT: this screen is expected to eventually show
## POSITIVE effects too (a caffeine boost from coffee, a well-fed work
## bonus, etc.), not just injuries/illnesses — hence it stays fully
## openable/browsable even with zero active conditions (a clean/healthy
## diagram, empty detail pane) rather than being gated behind "you have an
## injury." Nothing about buffs is implemented; this is a structural note
## for whoever eventually adds them.

const PANEL_W: float = 900.0
const PANEL_H: float = 560.0
const LEFT_PANE_W: float = 300.0

## Body-diagram button placement (Aug 2026 placeholder geometry — Brannon's
## explicit call: basic placeholder shapes for now, real art later). Each
## entry is a rect (x, y, w, h) relative to the diagram sub-panel's
## top-left, laid out as a rough front-view humanoid silhouette: head top-
## center, torso below it, arms flanking the torso's upper half, legs
## flanking below the torso. Purely a first-pass layout — revisit once real
## art exists (the art will likely dictate exact proportions). All six
## parts are included and clickable even though Torso/Head currently have
## zero symptom effects (deferred per the design doc) — both can already
## receive real Open Wound injuries and must be inspectable here regardless
## (per Brannon's explicit confirmation).
const BODY_LAYOUT: Dictionary = {
	MedicalCondition.BodyPart.HEAD:      Rect2(105.0,  20.0,  60.0,  50.0),
	MedicalCondition.BodyPart.TORSO:     Rect2( 85.0,  80.0, 100.0, 130.0),
	MedicalCondition.BodyPart.LEFT_ARM:  Rect2( 20.0,  90.0,  55.0, 110.0),
	MedicalCondition.BodyPart.RIGHT_ARM: Rect2(195.0,  90.0,  55.0, 110.0),
	MedicalCondition.BodyPart.LEFT_LEG:  Rect2( 85.0, 220.0,  45.0, 140.0),
	MedicalCondition.BodyPart.RIGHT_LEG: Rect2(140.0, 220.0,  45.0, 140.0),
}

## Injected by MainWorld (see _setup_status_screen()) — explicit refs, not
## group lookups, per this file's own "player-only for now, NPC-shaped on
## purpose" header note above.
var player_medical: PlayerMedical = null
var player_stats: PlayerStats = null

var _is_open: bool = false
var _canvas: Control = null
var _panel: PanelContainer = null
var _limb_buttons: Dictionary = {}       ## BodyPart(int) -> Button
var _limb_badge_rows: Dictionary = {}    ## BodyPart(int) -> Control (holds the mini status dots)
var _selected_part: int = -1             ## MedicalCondition.BodyPart, -1 = none selected yet

var _detail_header: Label = null
var _detail_empty_label: Label = null
var _detail_scroll: ScrollContainer = null
var _detail_vbox: VBoxContainer = null
var _needs_cap_row: Label = null

## Per-selected-limb expand state, keyed by condition id — a given body
## part only ever has one active condition per id at a time, so id alone
## disambiguates within the CURRENT selection. Cleared whenever the
## selected limb changes (see _on_limb_selected()) — deliberately not
## persisted across limbs, so switching limbs always starts collapsed.
var _expanded_tabs: Dictionary = {}

## Change-detection state (Aug 2026 fix — see _refresh_detail_pane()'s own
## comment for the bug this fixes). _built_tab_ids tracks which condition
## ids the CURRENT tab Buttons actually represent; _tab_widgets holds
## direct refs to each one's header/body/label so an unchanged tab can be
## updated in place instead of destroyed and recreated.
var _built_part: int = -2             ## -2 = never built yet, distinct from -1 ("no limb selected")
var _built_tab_ids: Array = []
var _tab_widgets: Dictionary = {}     ## condition.id(String) -> {header, body_label, body_margin, label}

## Same change-detection idea for the limb diagram (Aug 2026 fix) — the
## limb Buttons themselves are never rebuilt (only their mini-dot children
## were, every refresh tick, unconditionally) — this skips that work too
## when nothing on that limb actually changed.
var _limb_style_state: Dictionary = {}   ## BodyPart(int) -> [has_conditions: bool, selected: bool]
var _badge_signature: Dictionary = {}    ## BodyPart(int) -> Array of condition ids currently shown

const BG_COLOR: Color = Color(0.09, 0.09, 0.10, 0.96)
const BORDER_COLOR: Color = Color(0.45, 0.47, 0.42, 0.75)
const HEADER_COLOR: Color = Color(0.85, 0.87, 0.80, 1.0)
const TEXT_COLOR: Color = Color(0.80, 0.82, 0.78, 0.95)
const DIM_COLOR: Color = Color(0.55, 0.57, 0.53, 0.75)
const LIMB_BG: Color = Color(0.18, 0.19, 0.17, 0.85)
const LIMB_BG_ACTIVE: Color = Color(0.30, 0.16, 0.14, 0.90)   ## has an active condition
const LIMB_BG_SELECTED: Color = Color(0.24, 0.24, 0.30, 0.95)
const TAB_BG: Color = Color(0.15, 0.16, 0.14, 0.90)

func _ready() -> void:
	layer = 150
	visible = false
	set_process(false)

	## Controller support (standing convention — every interactive panel
	## gets this, see docs/systems/ui/README.md's "Controller support").
	## D-pad/stick moves focus by screen position across every focusable
	## Control this file builds (limb buttons AND tab headers alike, both
	## real Buttons), so d-pad-right from the rightmost limb naturally
	## lands in the detail pane's tab list and vice versa — no separate
	## "move to other pane" logic needed, per Brannon's "seamless" ask.
	## A -> ui_accept presses whatever's focused (selects a limb, or
	## expands/collapses a tab); B closes the whole screen automatically
	## (ControllerUINavigation's own topmost-aware B-close), same as every
	## other panel in the project.
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	controller_nav.stick_navigation = true
	add_child(controller_nav)

	_build_ui()

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	set_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_reposition_panel()
	UIFade.fade_in(_panel)
	_refresh_limb_badges()
	_refresh_detail_pane()

## Deliberately does NOT touch SceneTree.paused or call
## Player.set_job_locked() — see this file's header comment. Movement/
## camera-look are only indirectly affected by the mouse cursor being
## visible while open, same tradeoff every other mouse-driven panel in
## this project already makes.
func close() -> void:
	_is_open = false
	visible = false
	set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Close key handling (Aug 2026 fix — moved from _unhandled_input() to
## _input()). Godot's default InputMap binds [Tab] to the built-in
## ui_focus_next action, which the Control/GUI input system consumes
## BEFORE _unhandled_input() ever runs — so as soon as any Button in this
## screen had focus (which is immediately, once a limb or tab is
## selected), Tab silently became "move focus to the next control" instead
## of reaching this screen's close handler at all. _input() runs strictly
## before GUI/focus processing, so consuming it here guarantees Tab always
## closes the screen regardless of what's focused. Also handles the
## gamepad equivalent — JOY_BUTTON_BACK (the Xbox controller's View
## button, still commonly called "Select," carried over from the Xbox 360/
## PlayStation naming) — which has no default UI-action binding, so it
## never had this problem, but is handled in the same place for symmetry.
func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	var is_close: bool = (event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE)) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK)
	if is_close:
		close()
		get_viewport().set_input_as_handled()

## Live refresh while open — condition state changes in real time (a
## fracture escalating, infection severity climbing) and this screen is
## non-modal, so it should reflect that without needing to be closed and
## reopened. Throttled, not every-frame — this is glanceable info, not a
## live-updating gauge, and the game keeps running underneath regardless.
const REFRESH_INTERVAL: float = 0.25
var _refresh_accum: float = 0.0

func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_limb_badges()
		_refresh_detail_pane()

# ─── UI construction ────────────────────────────────────────────────────────
func _build_ui() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	## No full-screen backdrop dim (unlike PauseMenuUI) — deliberately, per
	## "world keeps running": the game stays fully visible around/behind
	## this panel, only the panel itself blocks mouse input.
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", sb)
	_canvas.add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(root_vbox)

	# ── Header row ──
	var header_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "STATUS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	var close_hint := Label.new()
	close_hint.text = "[TAB / Select] Close"
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", DIM_COLOR)
	header_row.add_child(close_hint)
	root_vbox.add_child(header_row)

	# ── Needs-cap reason row (Aug 2026, simplified) ── hidden unless a need is
	# actually capped right now. Plainly shown, not a hover tooltip —
	# Brannon's explicit call: the player can infer the drained needs are
	# the cause without also being told which needs by name here (covered
	# elsewhere, in the needs gauge itself), and the tutorial covers the
	# rest. Keeps the caution-icon prefix (⚠) it had before; only the text
	# format changed. Text itself comes straight from
	# PlayerMedical.get_needs_cap_reason_text().
	_needs_cap_row = Label.new()
	_needs_cap_row.text = ""
	_needs_cap_row.add_theme_font_size_override("font_size", 13)
	_needs_cap_row.add_theme_color_override("font_color", Color(0.85, 0.55, 0.20, 1.0))
	_needs_cap_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_needs_cap_row.visible = false
	root_vbox.add_child(_needs_cap_row)

	root_vbox.add_child(HSeparator.new())

	# ── Body row: diagram (left) | detail (right) ──
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 16)
	body_row.custom_minimum_size = Vector2(PANEL_W - 32.0, PANEL_H - 90.0)
	root_vbox.add_child(body_row)

	_build_diagram_pane(body_row)
	body_row.add_child(VSeparator.new())
	_build_detail_pane(body_row)

func _reposition_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - PANEL_H) * 0.5)

func _build_diagram_pane(parent: Control) -> void:
	var diagram_area := Control.new()
	diagram_area.custom_minimum_size = Vector2(LEFT_PANE_W, PANEL_H - 90.0)
	parent.add_child(diagram_area)

	for part in BODY_LAYOUT.keys():
		var rect: Rect2 = BODY_LAYOUT[part]
		var btn := Button.new()
		btn.position = rect.position
		btn.size = rect.size
		btn.focus_mode = Control.FOCUS_ALL
		btn.text = ""
		_style_limb_button(btn, false, false)
		btn.pressed.connect(_on_limb_selected.bind(part))
		diagram_area.add_child(btn)
		_limb_buttons[part] = btn

		## Mini status-dot row (Aug 2026) — see _refresh_limb_badges().
		var badge_row := Control.new()
		badge_row.position = Vector2(4.0, 4.0)
		badge_row.size = Vector2(rect.size.x - 8.0, 12.0)
		badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge_row)
		_limb_badge_rows[part] = badge_row

func _build_detail_pane(parent: Control) -> void:
	var detail_vbox := VBoxContainer.new()
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 8)
	parent.add_child(detail_vbox)

	_detail_header = Label.new()
	_detail_header.text = "Select a body part"
	_detail_header.add_theme_font_size_override("font_size", 15)
	_detail_header.add_theme_color_override("font_color", HEADER_COLOR)
	detail_vbox.add_child(_detail_header)

	_detail_empty_label = Label.new()
	_detail_empty_label.text = "No injuries or illnesses here."
	_detail_empty_label.add_theme_font_size_override("font_size", 13)
	_detail_empty_label.add_theme_color_override("font_color", DIM_COLOR)
	_detail_empty_label.visible = false
	detail_vbox.add_child(_detail_empty_label)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_vbox.add_child(_detail_scroll)

	_detail_vbox = VBoxContainer.new()
	_detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_vbox.add_theme_constant_override("separation", 6)
	_detail_scroll.add_child(_detail_vbox)

func _style_limb_button(btn: Button, has_conditions: bool, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = LIMB_BG_SELECTED if selected else (LIMB_BG_ACTIVE if has_conditions else LIMB_BG)
	normal.border_color = Color(0.85, 0.30, 0.25, 0.85) if has_conditions else BORDER_COLOR
	normal.set_border_width_all(2 if (has_conditions or selected) else 1)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.12)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)

# ─── Data refresh ────────────────────────────────────────────────────────────
func _on_limb_selected(part: int) -> void:
	_selected_part = part
	_expanded_tabs.clear()
	_refresh_limb_badges()
	_refresh_detail_pane()

## Mini status dots (Aug 2026) — one small colored circle per active
## condition on that limb, using the exact same ring colors the ambient
## HUD badges already use (PlayerMedical.get_condition_ring_color()), so a
## limb's at-a-glance state here always matches what the HUD is showing —
## "each limb should show a mini version of the injuries the HUD displays."
## Aug 2026 fix: only touches a limb's stylebox/dots when that limb's own
## (has_conditions, selected) state or condition-id set actually changed
## since the last refresh — previously rebuilt every limb's dot row
## unconditionally on every REFRESH_INTERVAL tick, which was wasteful (the
## limb Buttons themselves were never destroyed by this, so it wasn't the
## cause of the focus/click bug below, but no reason to keep doing it).
func _refresh_limb_badges() -> void:
	if player_medical == null:
		return
	for part in BODY_LAYOUT.keys():
		var conditions: Array[MedicalCondition] = player_medical.get_conditions_for_body_part(part)
		var has_conditions: bool = not conditions.is_empty()
		var selected: bool = part == _selected_part
		var style_state: Array = [has_conditions, selected]
		if _limb_style_state.get(part, null) != style_state:
			_style_limb_button(_limb_buttons[part], has_conditions, selected)
			_limb_style_state[part] = style_state

		var ids: Array = []
		for c: MedicalCondition in conditions:
			ids.append(c.id)
		if _badge_signature.get(part, []) == ids:
			continue   ## same conditions present — dot row already correct
		_badge_signature[part] = ids

		var row: Control = _limb_badge_rows[part]
		for child in row.get_children():
			child.queue_free()
		var x: float = 0.0
		for c: MedicalCondition in conditions:
			var dot := Panel.new()
			dot.position = Vector2(x, 0.0)
			dot.size = Vector2(9.0, 9.0)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot_sb := StyleBoxFlat.new()
			dot_sb.bg_color = player_medical.get_condition_ring_color(c)
			dot_sb.set_corner_radius_all(5)
			dot.add_theme_stylebox_override("panel", dot_sb)
			row.add_child(dot)
			x += 12.0

## Aug 2026 fix — this previously destroyed and recreated every tab Button
## unconditionally on every REFRESH_INTERVAL tick (~4x/sec), even when
## nothing about the selected limb's conditions had changed. That's what
## was causing the reported bug: a gamepad-focused tab Button would get
## queue_free()'d out from under ControllerUINavigation's focus roughly
## every quarter second, so focus kept resetting ("de-selects... and
## refreshes"); a mouse click straddling a rebuild between press and
## release could land its release on a brand-new Button that never saw the
## press, silently eating the click ("need several clicks"). AdminMenu
## never has this problem because it builds its rows once in _ready() and
## never touches them again.
##
## Fix: only tear down and rebuild the tab list when the selected limb
## changes, or the actual SET of condition ids on it changes (one
## resolved, a new one appeared, etc.) — tracked via _built_part/
## _built_tab_ids. Otherwise, every still-present tab's detail text is
## just updated in place via its stored _tab_widgets entry, touching
## nothing about the Button nodes themselves — so gamepad focus, hover
## state, and any in-progress mouse click all survive a refresh tick
## exactly like they do in AdminMenu.
func _refresh_detail_pane() -> void:
	if player_medical != null:
		var reason: String = player_medical.get_needs_cap_reason_text()
		_needs_cap_row.visible = reason != ""
		_needs_cap_row.text = ("⚠ " + reason) if reason != "" else ""

	if _selected_part == -1:
		_detail_header.text = "Select a body part"
		_detail_empty_label.visible = false
		if _built_part != -1:
			_clear_tabs()
			_built_part = -1
			_built_tab_ids = []
		return

	_detail_header.text = MedicalCondition.body_part_label(_selected_part)

	if player_medical == null:
		return
	var conditions: Array[MedicalCondition] = player_medical.get_conditions_for_body_part(_selected_part)
	_detail_empty_label.visible = conditions.is_empty()

	var current_ids: Array = []
	for c: MedicalCondition in conditions:
		current_ids.append(c.id)

	if _selected_part != _built_part or current_ids != _built_tab_ids:
		_clear_tabs()
		for c: MedicalCondition in conditions:
			_add_condition_tab(c)
		_built_part = _selected_part
		_built_tab_ids = current_ids
	else:
		## Same conditions still present — refresh each tab's detail text in
		## place, no node churn at all.
		for c: MedicalCondition in conditions:
			var w: Dictionary = _tab_widgets.get(c.id, {})
			if not w.is_empty():
				(w["body_label"] as Label).text = player_medical.get_status_detail_text(c)

func _clear_tabs() -> void:
	for child in _detail_vbox.get_children():
		child.queue_free()
	_tab_widgets.clear()

## Expandable tab per condition (Aug 2026) — same ▶/▼ click-to-toggle idiom
## AdminMenu.gd's collapsible sections already use, reused here rather than
## inventing a second expand/collapse convention. Body text reuses
## PlayerMedical.get_status_detail_text() verbatim — the exact same
## numeric detail the ambient HUD tooltip already shows for this
## condition, not a second description of the same data. Only called from
## _refresh_detail_pane()'s rebuild branch now, never on every tick — see
## that function's own comment.
func _add_condition_tab(condition: MedicalCondition) -> void:
	var header := Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_ALL
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var expanded: bool = bool(_expanded_tabs.get(condition.id, false))
	var label: String = "%s%s" % [condition.id.capitalize(), " (Infected)" if (condition.id == "open_wound" and condition.is_infected) else ""]
	header.text = "%s  %s" % ["▼" if expanded else "▶", label]
	var header_sb := StyleBoxFlat.new()
	header_sb.bg_color = TAB_BG
	header_sb.set_corner_radius_all(4)
	header_sb.content_margin_left = 8.0
	header.add_theme_stylebox_override("normal", header_sb)
	var header_hover := header_sb.duplicate() as StyleBoxFlat
	header_hover.bg_color = header_hover.bg_color.lightened(0.08)
	header.add_theme_stylebox_override("hover", header_hover)
	header.add_theme_stylebox_override("focus", header_hover)
	header.add_theme_color_override("font_color", TEXT_COLOR)
	_detail_vbox.add_child(header)

	var body := Label.new()
	body.text = player_medical.get_status_detail_text(condition)
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", DIM_COLOR)
	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.visible = expanded
	body_margin.add_child(body)
	_detail_vbox.add_child(body_margin)

	_tab_widgets[condition.id] = {"header": header, "body_label": body, "body_margin": body_margin, "label": label}

	header.pressed.connect(func() -> void:
		var now_expanded: bool = not bool(_expanded_tabs.get(condition.id, false))
		_expanded_tabs[condition.id] = now_expanded
		header.text = "%s  %s" % ["▼" if now_expanded else "▶", label]
		body_margin.visible = now_expanded
	)
