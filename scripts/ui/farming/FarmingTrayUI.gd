extends CanvasLayer
## FarmingTrayUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §9.1, revised by Polish Plan Group 0 (items 19/19a/19b).
## Opened by bare-handed E on a fully-soiled FarmingTray whenever no cell is
## ready to harvest (a ready cell harvests immediately instead — see
## FarmingTray.on_interact()). Same UIKit-based hand-drawn panel convention as
## WaterDispenserUI.gd/GeneratorInspectUI.gd — NEUTRAL domain (steel-gray),
## since Farming is its own system, not Water or Power.
##
## Priority ◄► widget copied from WaterDispenserUI.gd's own verbatim.
##
## Group 0 additions (replaces the old separate PlantInfoUI.gd panel, now
## deleted):
##   19a — one inset block per occupied cell (has a live FarmPlant): plant
##         name, "Health: X%", a flat #e3ad30 growth bar + numeric
##         "Growth: NN%" label, and a NOT READY (red) / READY (green) line.
##   19b — an inset warning bubble shown only when water_fraction < 1.0,
##         mirroring the "LOAD" inline sub-panel style already used by
##         PowerPriorityUI.gd's toggle row (filled rect + border, not a
##         TransientNotice toast).
##
## Panel height is no longer a fixed constant — it grows/shrinks with 0/1/2
## occupied cells and whether the water bubble is showing, recomputed every
## frame via _layout_metrics() so both the drawn panel and the real Button
## children (close/priority arrows) always agree on where things are.
##
## Signals:
##   closed — player dismissed the panel (Escape / E / close button)

signal closed

var _theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

## Same universal green→red priority legend as WaterDispenserUI.gd/PowerPriorityUI.gd.
const PRIO_COLORS: Array[Color] = [
	Color(0.30, 1.00, 0.46, 1.00),
	Color(0.62, 0.92, 0.32, 1.00),
	Color(0.98, 0.85, 0.20, 1.00),
	Color(1.00, 0.58, 0.16, 1.00),
	Color(1.00, 0.30, 0.20, 1.00),
]
const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5

const PANEL_W: float = 380.0

## Growth bar fill — single flat color, NOT a gradient (matches WaterInfoUI's/
## the purifier filter meter's own flat-fill convention).
const GROWTH_BAR_COLOR: Color = Color(0.89, 0.68, 0.19, 1.0)   ## #e3ad30
const WARN_COLOR: Color = Color(1.00, 0.72, 0.10, 1.00)
const READY_COLOR: Color = Color(0.30, 1.00, 0.46, 1.00)
const NOT_READY_COLOR: Color = Color(1.00, 0.30, 0.20, 1.00)

## ── Fixed-section metrics (used by both _layout_metrics() and _on_draw()) ──
const TOP_PAD: float = 20.0
const HEADER_H: float = 44.0
const CONNECTION_H: float = 40.0
const WATER_BLOCK_H: float = 70.0   ## label + value + bar + gap
const BUBBLE_H: float = 52.0
const BUBBLE_GAP_AFTER: float = 16.0
const PLANT_BLOCK_H: float = 126.0   ## Polish Plan Group 1 item 4: +16 for the "Ready in ~X days" line; Fertilizer plan: +18 for the fertilized-status line
const PLANT_BLOCK_GAP: float = 10.0
const PRIORITY_BLOCK_H: float = 112.0
const BOTTOM_PAD: float = 20.0

var _tray: FarmingTray = null
var _is_open: bool = false

var _arrow_row_y: float = 0.0
var _current_panel_h: float = 300.0

var _canvas:    Control = null
var _close_btn: Button  = null
var _dec_btn:   Button  = null
var _inc_btn:   Button  = null

func _ready() -> void:
	layer   = 60
	visible = false
	set_process(false)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "FarmingTrayCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_build_controls()

func _build_controls() -> void:
	_dec_btn = Button.new()
	_dec_btn.clip_text    = false
	_dec_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dec_btn.focus_mode   = Control.FOCUS_NONE
	_dec_btn.text         = "◄"
	_dec_btn.pressed.connect(_on_dec_pressed)
	add_child(_dec_btn)

	_inc_btn = Button.new()
	_inc_btn.clip_text    = false
	_inc_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_inc_btn.focus_mode   = Control.FOCUS_NONE
	_inc_btn.text         = "►"
	_inc_btn.pressed.connect(_on_inc_pressed)
	add_child(_inc_btn)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.focus_mode   = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

func open(tray: FarmingTray) -> void:
	_tray    = tray
	_is_open = true
	visible  = true
	set_process(true)
	_close_btn.visible = true
	_dec_btn.visible   = true
	_inc_btn.visible   = true
	_reposition_controls()
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	_dec_btn.visible   = false
	_inc_btn.visible   = false
	closed.emit()

func is_open() -> bool:
	return _is_open

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_E:
			close()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - _current_panel_h) * 0.5
		if Rect2(px, py, PANEL_W, _current_panel_h).has_point((event as InputEventMouseButton).position):
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _tray == null or not is_instance_valid(_tray):
		close()
		return
	_reposition_controls()
	_canvas.queue_redraw()

func _on_dec_pressed() -> void:
	_apply_priority(-1)

func _on_inc_pressed() -> void:
	_apply_priority(1)

func _apply_priority(delta: int) -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	_tray.priority = clampi(_tray.priority + delta, PRIORITY_MIN, PRIORITY_MAX)
	_canvas.queue_redraw()

## Shared occupied-cell/bubble/height computation — used to keep the real
## Button children and the hand-drawn content in perfect agreement every
## frame (occupied cell count and the water bubble can both change live
## while the panel is open: growth ticks, harvests, water fraction shifts).
func _layout_metrics(t: FarmingTray) -> Dictionary:
	var occupied: int = 0
	for plant: FarmPlant in t.plant_refs:
		if plant != null and is_instance_valid(plant):
			occupied += 1

	var show_bubble: bool = t.get_water_fraction() < 1.0

	var h: float = TOP_PAD + HEADER_H + CONNECTION_H + WATER_BLOCK_H
	if show_bubble:
		h += BUBBLE_H + BUBBLE_GAP_AFTER
	h += float(occupied) * PLANT_BLOCK_H + (maxf(0.0, float(occupied) - 1.0)) * PLANT_BLOCK_GAP
	if occupied > 0:
		h += PLANT_BLOCK_GAP   ## gap between plant blocks and priority section
	h += PRIORITY_BLOCK_H + BOTTOM_PAD

	return {
		"panel_h": h,
		"occupied": occupied,
		"show_bubble": show_bubble,
	}

func _reposition_controls() -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	var metrics: Dictionary = _layout_metrics(_tray)
	_current_panel_h = float(metrics["panel_h"])

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - _current_panel_h) * 0.5

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

	var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + _current_panel_h - PRIORITY_BLOCK_H + 40.0)
	var arrow_sz: Vector2 = Vector2(48.0, 48.0)
	_dec_btn.size = arrow_sz
	_inc_btn.size = arrow_sz
	_dec_btn.position = Vector2(px + 36.0, arrow_y)
	_inc_btn.position = Vector2(px + PANEL_W - 36.0 - arrow_sz.x, arrow_y)
	_style_arrow_btn(_dec_btn, _tray.priority > PRIORITY_MIN)
	_style_arrow_btn(_inc_btn, _tray.priority < PRIORITY_MAX)

func _style_arrow_btn(btn: Button, enabled: bool) -> void:
	btn.disabled = not enabled
	btn.add_theme_font_override("font", UIKit.font())
	btn.add_theme_font_size_override("font_size", 22)
	var fg: Color = _theme.header if enabled else Color(0.30, 0.34, 0.36, 1.0)
	for sname: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(sname, UIKit.button_stylebox(_theme, enabled, sname == "hover"))
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)

func _on_draw() -> void:
	if not _is_open:
		return
	var t: FarmingTray = _tray
	if t == null or not is_instance_valid(t):
		return

	var metrics: Dictionary = _layout_metrics(t)
	_current_panel_h = float(metrics["panel_h"])
	var show_bubble: bool = bool(metrics["show_bubble"])

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - _current_panel_h) * 0.5

	UIKit.draw_backdrop(_canvas, vp, 0.60)
	var panel: Rect2 = Rect2(px, py, PANEL_W, _current_panel_h)
	UIKit.draw_panel(_canvas, panel, _theme)
	UIKit.draw_close_button(_canvas, panel, _theme)

	var cx: float = px + 24.0
	var cy: float = py + 20.0

	var tray_name: String = "TRAY (SINGLE)" if t.cell_count == 1 else "TRAY (DOUBLE)"
	UIKit.draw_header(_canvas, Vector2(cx, cy), tray_name, _theme, PANEL_W - 48.0, 16)
	cy += HEADER_H

	## Connection status.
	var connected: bool = t.is_connected_to_water()
	_draw_str("CONNECTION", Vector2(cx, cy), _theme.dim, 10)
	var conn_str: String = "CONNECTED" if connected else "DISCONNECTED"
	var conn_col: Color  = _theme.ok if connected else _theme.crit
	_draw_str(conn_str, Vector2(cx, cy + 14.0), conn_col, 13)
	cy += CONNECTION_H

	## Demand vs received.
	var demand: float = t.get_current_demand_mL_per_day()
	var water_fraction: float = t.get_water_fraction()
	var received: float = water_fraction * demand
	_draw_str("WATER (RECEIVED / DEMAND)", Vector2(cx, cy), _theme.dim, 10)
	_draw_str("%.0f / %.0f mL/day" % [received, demand], Vector2(cx, cy + 14.0), _theme.text, 13)
	cy += 32.0

	var bar_w: float = PANEL_W - 48.0
	var bar_h: float = 14.0
	UIKit.draw_bar(_canvas, Rect2(cx, cy, bar_w, bar_h), water_fraction, _theme)
	cy += bar_h + 24.0

	## 19b — water-insufficiency warning bubble. Persistent tray state, shown
	## every time the panel is open while water_fraction < 1.0 (not
	## edge-triggered — that's a separate, out-of-scope low-health toast).
	if show_bubble:
		var bubble_rect: Rect2 = Rect2(cx - 4.0, cy - 4.0, bar_w + 8.0, BUBBLE_H - 8.0)
		_canvas.draw_rect(bubble_rect, Color(0.14, 0.10, 0.04, 0.75), true)
		_canvas.draw_rect(bubble_rect, Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, 0.55), false, 1.0)
		var pct: int = int(round(water_fraction * 100.0))
		var msg: String = "Water levels insufficient (%d%% of demand met) — this will slow plant growth." % pct
		var wrap_w: float = bar_w - 12.0
		var line_count: int = _wrapped_line_count(msg, wrap_w, 10)
		var line_h: float = 10.0 + 5.0
		var text_block_h: float = float(line_count) * line_h - 5.0
		var text_x: float = cx + 6.0
		var text_y: float = bubble_rect.position.y + (bubble_rect.size.y - text_block_h) * 0.5
		_draw_wrapped(msg, Vector2(text_x, text_y), wrap_w, WARN_COLOR, 10)
		cy += BUBBLE_H + BUBBLE_GAP_AFTER

	## 19a — one inset block per occupied cell (has a live FarmPlant).
	var occupied: int = int(metrics["occupied"])
	if occupied > 0:
		for i: int in range(t.cell_count):
			var plant: FarmPlant = t.plant_refs[i]
			if plant == null or not is_instance_valid(plant):
				continue
			cy = _draw_plant_block(plant, cx, cy, bar_w)
		cy += PLANT_BLOCK_GAP

	## Priority.
	_draw_str("PRIORITY", Vector2(cx, cy), _theme.dim, 10)
	_arrow_row_y = cy + 16.0
	var prio_col: Color = PRIO_COLORS[clampi(t.priority - 1, 0, 4)]
	var prio_label: String = "%d" % t.priority
	var lsz: Vector2 = UIKit.font().get_string_size(prio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	_canvas.draw_string(UIKit.font(), Vector2(px + PANEL_W * 0.5 - lsz.x * 0.5, _arrow_row_y + 34.0),
		prio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, prio_col)

## Draws one plant info block (name, health%, growth bar + numeric label,
## READY/NOT READY) and returns the new `cy` after it (plus the inter-block gap).
func _draw_plant_block(plant: FarmPlant, cx: float, cy: float, bar_w: float) -> float:
	var block_rect: Rect2 = Rect2(cx - 4.0, cy - 4.0, bar_w + 8.0, PLANT_BLOCK_H - PLANT_BLOCK_GAP)
	_canvas.draw_rect(block_rect, Color(0.09, 0.10, 0.11, 0.70), true)
	_canvas.draw_rect(block_rect, Color(_theme.border.r, _theme.border.g, _theme.border.b, 0.45), false, 1.0)

	var bx: float = cx + 6.0
	var by: float = cy + 6.0

	_draw_str(PlantDatabase.get_display_name(plant.plant_type).to_upper(), Vector2(bx, by), _theme.header, 12)

	var ready: bool = plant.is_ready()
	var ready_str: String = "READY" if ready else "NOT READY"
	var ready_col: Color = READY_COLOR if ready else NOT_READY_COLOR
	var rsz: Vector2 = UIKit.font().get_string_size(ready_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	_draw_str(ready_str, Vector2(cx - 4.0 + (bar_w + 8.0) - 6.0 - rsz.x, by), ready_col, 11)
	by += 20.0

	var health_col: Color = _theme.ok if plant.health >= 60.0 else (_theme.warn if plant.health >= 25.0 else _theme.crit)
	_draw_str("Health: %d%%" % int(round(plant.health)), Vector2(bx, by), health_col, 11)
	by += 20.0

	var growth_pct: int = int(round(plant.progress * 100.0))
	_draw_str("Growth: %d%%" % growth_pct, Vector2(bx, by), _theme.text, 11)
	by += 20.0

	## Polish Plan Group 1 item 4 — "Ready in ~X days" countdown, using the
	## plant's live growth rate (cached each hour tick, 0 while stalled with
	## no light/water). Color-graded via WaterQualityColor's existing
	## red/yellow/green step convention, fed `progress` as a 0-100 scale
	## (a stand-in "how close to ready" value — not a water quality, but the
	## same visual language the plan calls for).
	## B4 — Dormant/Stalled/Ready status text
	if ready:
		_draw_str("Status: Ready", Vector2(bx, by), READY_COLOR, 11)
	elif plant.progress <= 0.0 and plant.water_fraction <= 0.0:
		_draw_str("Status: Dormant", Vector2(bx, by), NOT_READY_COLOR, 11)
	elif plant.growth_per_hour_current <= 0.0:
		var reasons: Array[String] = []
		if plant.water_fraction <= 0.0:
			reasons.append("No Water")
		if plant._light_speed_cached <= FarmPlant.LIGHT_FLOOR_SPEED:
			reasons.append("No Light")
		var reason_text: String = "(%s)" % ", ".join(reasons)
		_draw_str("Status: Stalled %s" % reason_text, Vector2(bx, by), NOT_READY_COLOR, 11)
	else:
		var hours_left: float = (1.0 - plant.progress) / plant.growth_per_hour_current
		var hours_left_int: int = int(ceil(hours_left))
		var countdown_col: Color = WaterQualityColor.get_color(plant.progress * 100.0)
		_draw_str("Status: %d hours until harvest" % hours_left_int, Vector2(bx, by), countdown_col, 11)
	by += 16.0

	var block_bar_w: float = bar_w - 12.0
	var block_bar_h: float = 10.0
	UIKit.draw_bar(_canvas, Rect2(bx, by, block_bar_w, block_bar_h), plant.progress, _theme, GROWTH_BAR_COLOR)
	by += 18.0

	## Fertilizer plan — fertilized-status line, one more per-cell readout
	## reusing READY_COLOR for the positive case (visual consistency with the
	## READY label, not a new shade).
	if plant.is_fertilized():
		var pct: int = int(round(plant.fertilizer_bonus * 100.0))
		var fert_label: String = "Fertilized (%s, +%d%% growth)" % [plant.fertilizer_tier.capitalize(), pct]
		_draw_str(fert_label, Vector2(bx, by), READY_COLOR, 11)
	else:
		_draw_str("Not Fertilized", Vector2(bx, by), _theme.dim, 11)

	return cy + PLANT_BLOCK_H

## Simple word-wrap for the 19b warning bubble — same font size the caller
## draws at, wraps to fit `max_w`, one shadowed line per row.
func _wrapped_line_count(text: String, max_w: float, size: int) -> int:
	var words: PackedStringArray = text.split(" ")
	var line: String = ""
	var count: int = 0
	for w: String in words:
		var candidate: String = (line + " " + w) if line != "" else w
		var sz: Vector2 = UIKit.font().get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		if sz.x > max_w and line != "":
			count += 1
			line = w
		else:
			line = candidate
	if line != "":
		count += 1
	return count

## Simple word-wrap for the 19b warning bubble — same font size the caller
## draws at, wraps to fit `max_w`, one shadowed line per row.
func _draw_wrapped(text: String, pos: Vector2, max_w: float, color: Color, size: int) -> void:
	var words: PackedStringArray = text.split(" ")
	var line: String = ""
	var y: float = pos.y
	for w: String in words:
		var candidate: String = (line + " " + w) if line != "" else w
		var sz: Vector2 = UIKit.font().get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		if sz.x > max_w and line != "":
			UIKit.draw_shadowed_text(_canvas, Vector2(pos.x, y), line, size, color)
			y += float(size) + 5.0
			line = w
		else:
			line = candidate
	if line != "":
		UIKit.draw_shadowed_text(_canvas, Vector2(pos.x, y), line, size, color)

func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	UIKit.draw_shadowed_text(_canvas, pos, text, size, color)
