extends StaticBody3D
## BreakerBox.gd  — v2.0
## A circuit breaker placed on the wire graph.
##
## CHANGED in v2.0:
##   - E-key interaction NO LONGER trips/resets the breaker.
##   - Instead it opens a CanvasLayer settings panel with:
##       • Zone colour swatch (matching BuildModeController wire palette)
##       • "Allow battery power through" toggle
##       • "Allow generator power through" toggle
##       • Current state label (ONLINE / TRIPPED)
##   - Trip / reset can only be done from PowerTerminal (or PM code).
##   - set_tripped(bool) still works — PM calls it to update the LED.
##
## PowerManager integration:
##   _ready()     → register_wire_node() → register_breaker()
##   _exit_tree() → unregister_breaker() → unregister_wire_node()
##   set_tripped(bool)  — called by PM when trip state changes
##   on_interact()      — opens settings panel

# ─── Debug ────────────────────────────────────────────────────────────────────
## Set false to silence all [BreakerBox] placement/registration prints.
## Matches MainWorld.WIRE_DEBUG — flip both together.
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Colours ──────────────────────────────────────────────────────────────────
const COLOR_BODY:    Color = Color(0.30, 0.30, 0.32, 1.0)
const COLOR_PANEL:   Color = Color(0.20, 0.20, 0.22, 1.0)
const COLOR_LED_ON:  Color = Color(0.10, 0.95, 0.25, 1.0)   ## green = ONLINE
const COLOR_LED_OFF: Color = Color(0.95, 0.18, 0.10, 1.0)   ## red   = TRIPPED

## Zone wire palette — must match BuildModeController._recolor_wire_zones() and PM.
## Index 0 = light blue (default/unbroken zone). Index 1–5 = coloured zones.
## SINGLE SOURCE OF TRUTH: the real palette lives in PowerManager.ZONE_COLORS.
## _palette_col() below pulls from PowerManager (alpha 0.60, matching the wire
## tubes).  This const is ONLY a fallback mirror if PM is unreachable — keep it
## identical to PM's RGB.
const ZONE_COLORS: Array[Color] = [
	Color(0.35, 0.80, 1.00, 0.60),   ## 0 light blue  (default zone)
	Color(0.10, 0.95, 0.35, 0.60),   ## 1 green
	Color(0.95, 0.18, 0.10, 0.60),   ## 2 red
	Color(0.95, 0.90, 0.10, 0.60),   ## 3 yellow
	Color(0.90, 0.10, 0.95, 0.60),   ## 4 magenta
	Color(0.95, 0.55, 0.10, 0.60),   ## 5 orange
]

## Zone palette colour at alpha 0.60, sourced from PowerManager.
## Falls back to the local ZONE_COLORS mirror only if PM is unreachable.
func _palette_col(color_index: int) -> Color:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm != null and pm.has_method("zone_color_at"):
		return pm.call("zone_color_at", color_index, 0.60)
	return ZONE_COLORS[color_index % ZONE_COLORS.size()]

# ─── Box dimensions ───────────────────────────────────────────────────────────
const BOX_SIZE: Vector3 = Vector3(0.36, 0.44, 0.14)

# ─── State ────────────────────────────────────────────────────────────────────
var _tripped:    bool   = false
var _pm_id:      String = ""
var _wire_key:   String = ""
var _breaker_id: String = ""

## Pass-through flags — set by player via settings panel, sent to PM.
var _pass_battery:   bool = true
var _pass_generator: bool = true

## Zone indices on each side of this breaker (-1 = unassigned).
## A breaker borders up to two zones; we store both for display.
var _zone_index:  int = -1   ## primary (first found) — kept for compat
var _zone_index_b: int = -1  ## secondary zone on the other side

# ─── Mesh refs ────────────────────────────────────────────────────────────────
var _led_mat: StandardMaterial3D = null

# ─── Interaction banner ───────────────────────────────────────────────────────
var _banner: Label3D = null

# ─── Settings panel (CanvasLayer) ─────────────────────────────────────────────
var _settings_layer:  CanvasLayer = null
var _settings_canvas: Control     = null
var _settings_open:   bool        = false
var _font: Font = null

## Panel dimensions
const PANEL_W: float = 340.0
const PANEL_H: float = 200.0
const PAD:     float = 14.0
const ROW_H:   float = 36.0   ## height per toggle row

## Colours for settings panel
const UI_BG:     Color = Color(0.05, 0.08, 0.05, 0.96)
const UI_BORDER: Color = Color(0.28, 0.85, 0.32, 0.75)
const UI_TEXT:   Color = Color(0.80, 0.95, 0.82, 0.95)
const UI_DIM:    Color = Color(0.45, 0.55, 0.45, 0.85)
const UI_ON:     Color = Color(0.20, 0.90, 0.35, 1.0)
const UI_OFF:    Color = Color(0.90, 0.28, 0.15, 1.0)
const UI_HEADER: Color = Color(0.22, 0.75, 0.28, 1.0)

## Hit-test rects (screen space, computed during draw, used in input)
var _rect_close:      Rect2 = Rect2()
var _rect_bat_toggle: Rect2 = Rect2()
var _rect_gen_toggle: Rect2 = Rect2()
var _rect_restart:    Rect2 = Rect2()   ## RESTART button — only live while tripped
var _panel_rect:      Rect2 = Rect2()

## ── TRIPPED banner + RESTART button ────────────────────────────────────────
## When tripped, the panel grows to show a bold TRIPPED banner and a RESTART
## button, and the pass-through toggle pills lock (greyed, clicks ignored) —
## matches both standard breaker trips (via Power Terminal / upgraded
## self-trip) and gives the player a direct in-panel way to reset without
## walking to a terminal.  Shared by BreakerBox and UpgradedBreakerBox alike.
const TRIPPED_BANNER_H: float = 26.0
const RESTART_BTN_H:    float = 28.0
const UI_TRIPPED_BG:    Color = Color(0.28, 0.05, 0.04, 0.95)
const UI_TRIPPED_TEXT:  Color = Color(1.0, 0.65, 0.55, 1.0)
const UI_LOCK_DIM:      Color = Color(0.30, 0.30, 0.30, 0.60)


# ══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	add_to_group("breaker")
	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font
	_build_mesh()
	_build_banner()
	_build_settings_panel()
	_register_with_pm()


func _exit_tree() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return
	if not _breaker_id.is_empty() and pm.has_method("unregister_breaker"):
		pm.call("unregister_breaker", _breaker_id)
	if not _wire_key.is_empty() and pm.has_method("unregister_wire_node"):
		pm.call("unregister_wire_node", _wire_key)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER REGISTRATION
# ══════════════════════════════════════════════════════════════════════════════

func _register_with_pm() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		push_warning("BreakerBox: PowerManager not found")
		return
	_pm_id = str(get_instance_id())
	call_deferred("_register_wire_deferred")


func _register_wire_deferred() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null or _pm_id.is_empty():
		return
	_wdbg("[BreakerBox] _register_wire_deferred: global_pos=%s pm_id=%s" % [global_position, _pm_id])

	## ── Snap onto the nearest wire edge's axis ─────────────────────────────────
	## Wall-snapping pushes the breaker off the wire plane (e.g. wire at Z=4.50,
	## breaker at Z=4.69).  Naively rounding XZ lands on a different snap row
	## (Z=4.75) which is 0.25 m from the wire — outside _point_on_segment's
	## 0.125 m collinearity tolerance, so the split never fires.
	##
	## Correct approach:
	##   1. Iterate every wire edge.  For each, project the breaker's XZ onto the
	##      edge's axis and check it is within the collinearity band (< 0.2 m
	##      perpendicular) and between the endpoints (t ∈ [0,1]).
	##   2. Among qualifying edges pick the closest (smallest perpendicular dist).
	##   3. Build reg_pos by keeping the edge's perpendicular coordinate exactly
	##      (preserving the wire's Z or X) and rounding only the along-axis
	##      coordinate to the 0.25 m snap grid.
	## This guarantees the breaker node lands on the wire's exact Z/X plane so
	## _split_wire_edge_at() passes the collinearity check and splits correctly,
	## while placing the split point as close as possible to the breaker center.
	const WIRE_GRID_Y:   float = 1.0
	const SNAP_GRID:     float = 0.25
	const PERP_BAND:     float = 0.40   ## max off-axis distance to qualify (wall thickness can push breaker ~0.22 m off wire)
	const SEARCH_RADIUS: float = 1.0    ## max XZ distance from breaker to edge midpoint

	var reg_pos: Vector3 = global_position  ## fallback: raw position
	var snap_axis: String = ""             ## "x" or "z" — wire run axis of the chosen edge (for visual align)

	if pm.has_method("get_wire_edges") and pm.has_method("get_wire_nodes"):
		var all_edges: Array = pm.call("get_wire_edges") as Array
		var all_nodes_arr: Array = pm.call("get_wire_nodes") as Array
		## Build a quick key→pos lookup.
		## Some nodes are auto-created with pos=Vector3.ZERO before
		## register_wire_node() is called for them — reconstruct their
		## position from the snap key integers in that case.
		var node_pos: Dictionary = {}
		for wn: Dictionary in all_nodes_arr:
			var wn_key: String  = wn.get("key", "")
			var wn_pos: Vector3 = wn.get("pos", Vector3.ZERO)
			if wn_pos == Vector3.ZERO and wn_key != "":
				var tok: PackedStringArray = wn_key.split(",")
				if tok.size() == 3:
					wn_pos = Vector3(
						int(tok[0]) * SNAP_GRID,
						int(tok[1]) * SNAP_GRID,
						int(tok[2]) * SNAP_GRID)
			node_pos[wn_key] = wn_pos

		var my_xz: Vector2  = Vector2(global_position.x, global_position.z)
		var best_perp: float = INF
		var best_pos:  Vector3 = Vector3.ZERO
		var found: bool = false
		var best_axis: String = ""   ## records winning edge's run axis for visual align

		for edge: Dictionary in all_edges:
			var a_key: String = edge.get("node_a", "")
			var b_key: String = edge.get("node_b", "")
			if not node_pos.has(a_key) or not node_pos.has(b_key):
				continue
			var a_pos: Vector3 = node_pos[a_key]
			var b_pos: Vector3 = node_pos[b_key]
			var a2: Vector2 = Vector2(a_pos.x, a_pos.z)
			var b2: Vector2 = Vector2(b_pos.x, b_pos.z)
			var ab: Vector2 = b2 - a2
			var len_sq: float = ab.length_squared()
			if len_sq < 0.0001:
				continue
			## Project my_xz onto the A→B axis.
			var ap: Vector2 = my_xz - a2
			var t: float    = ab.dot(ap) / len_sq
			if t < -0.01 or t > 1.01:
				continue   ## outside segment span
			## Perpendicular distance from my point to the line.
			var closest_on_seg: Vector2 = a2 + ab * clampf(t, 0.0, 1.0)
			var perp: float = my_xz.distance_to(closest_on_seg)
			if perp > PERP_BAND:
				continue   ## too far off-axis
			if perp < best_perp:
				best_perp = perp
				## Keep the wire's exact perpendicular coord; snap only along-axis.
				## Determine dominant axis by whichever component of ab is larger.
				var is_x_run: bool = absf(ab.x) >= absf(ab.y)   ## ab.y = ab along Z
				if is_x_run:
					## Wire runs along X → keep a_pos.z exactly, snap X.
					var snapped_x: float = roundf(global_position.x / SNAP_GRID) * SNAP_GRID
					best_pos = Vector3(snapped_x, WIRE_GRID_Y, a_pos.z)
				else:
					## Wire runs along Z → keep a_pos.x exactly, snap Z.
					var snapped_z: float = roundf(global_position.z / SNAP_GRID) * SNAP_GRID
					best_pos = Vector3(a_pos.x, WIRE_GRID_Y, snapped_z)
				best_axis = "x" if is_x_run else "z"
				found = true

		if found:
			reg_pos = best_pos
			snap_axis = best_axis
			_wdbg("[BreakerBox]   edge-snapped reg_pos from %s → %s (perp=%.3fm)" \
				% [global_position, reg_pos, best_perp])
		else:
			## No qualifying edge found — fall back to the old nearest-node search.
			var best_dist: float = 0.5   ## within 0.5 m
			for wn: Dictionary in all_nodes_arr:
				var wn_pos: Vector3 = wn.get("pos", Vector3.ZERO)
				var dx: float = wn_pos.x - global_position.x
				var dz: float = wn_pos.z - global_position.z
				var d: float  = sqrt(dx * dx + dz * dz)
				if d < best_dist:
					best_dist = d
					reg_pos   = wn_pos
			_wdbg("[BreakerBox]   no nearby edge found — nearest-node fallback reg_pos=%s" % reg_pos)

	## ── Align the VISUAL mesh with the electrical cut-point (along-axis) ───────
	## The cut-point (reg_pos) snaps the ALONG-WIRE coordinate to the 0.25 m
	## grid.  Nudge the box's along-axis to reg_pos so its body sits over the
	## cut, while KEEPING the breaker's wall-face offset on the perpendicular
	## axis (reg_pos puts the perp coord on the wire plane, which would embed
	## the box in the wall).  NOTE: the primary zone-seam offset was a missing
	## A→M tube in PowerManager._split_wire_edge_at() — fixed there.  This nudge
	## handles only the residual sub-grid along-axis offset.
	if pm.has_method("register_wire_node"):
		_wire_key = pm.call("register_wire_node", reg_pos, "breaker", _pm_id)
		## Move the box ONLY along the wire run axis so it sits over the cut-point.
		## The perpendicular (wall-face) coordinate is left at global_position so
		## the breaker stays flush against the wall and never embeds into it.
		## snap_axis is "" in the nearest-node fallback path — skip there (no
		## reliable run axis), preserving the breaker's raw placement.
		if snap_axis == "x":
			var new_gp_x: Vector3 = global_position
			new_gp_x.x = reg_pos.x
			global_position = new_gp_x
			_wdbg("[BreakerBox]   visual aligned to cut-point (X-run): global_pos→%s" % new_gp_x)
		elif snap_axis == "z":
			var new_gp_z: Vector3 = global_position
			new_gp_z.z = reg_pos.z
			global_position = new_gp_z
			_wdbg("[BreakerBox]   visual aligned to cut-point (Z-run): global_pos→%s" % new_gp_z)
	_wdbg("[BreakerBox]   wire_key=%s  breaker_id to follow" % _wire_key)
	if pm.has_method("register_breaker") and not _wire_key.is_empty():
		_breaker_id = pm.call("register_breaker", _wire_key, self)
	_wdbg("[BreakerBox]   breaker_id=%s" % _breaker_id)
	_auto_connect_to_nearby_wires(pm)


func _auto_connect_to_nearby_wires(pm: Node) -> void:
	## NOTE: The primary split is handled by PM._split_wire_edge_at() during
	## register_breaker().  This function exists as a fallback for inward-facing
	## wall breakers whose snap key may not land exactly on an existing edge.
	##
	## Strategy: find the closest collinear wire node along each axis direction
	## (±X and ±Z).  Connect only to the nearest one per direction — at most 2
	## total — so we never create a high-degree junction that confuses zone BFS.
	##
	## "Collinear" = the candidate node shares approximately the same X (for a
	## Z-run wire) or the same Z (for an X-run wire) within 0.15m.
	##
	## IMPORTANT: If the breaker is already embedded in the graph (the split
	## succeeded OR it landed exactly on an existing wire endpoint), skip
	## auto-connect entirely.  Running it when the breaker already has 2+ edges
	## creates tiny orphan stub edges that the BFS sees as separate zones.
	if _wire_key.is_empty() or not pm.has_method("get_wire_nodes") \
			or not pm.has_method("register_wire_edge"):
		return

	## Count edges that already touch our wire node in the PM graph.
	if pm.has_method("get_wire_edges"):
		var existing_count: int = 0
		for edge: Dictionary in (pm.call("get_wire_edges") as Array):
			if edge.get("node_a", "") == _wire_key or edge.get("node_b", "") == _wire_key:
				existing_count += 1
		if existing_count >= 2:
			_wdbg("[BreakerBox] _auto_connect: breaker already has %d edges — SKIPPING stub generation" % existing_count)
			return
		_wdbg("[BreakerBox] _auto_connect: breaker has %d edge(s) — proceeding with auto-connect" % existing_count)

	const SEARCH_RADIUS: float = 2.0   ## wide search, collinearity filter keeps it tight
	const COLINEAR_TOL:  float = 0.15  ## max off-axis deviation to be "on same wall run"

	## Use the PM-registered (wire-snapped) position for all geometry math so
	## collinearity checks work even when the breaker visual is at the wall face.
	var my_pos: Vector3  = global_position
	var all_nodes: Array = pm.get_wire_nodes() as Array
	for wn: Dictionary in all_nodes:
		if wn.get("key", "") == _wire_key:
			my_pos = wn.get("pos", global_position)
			break
	_wdbg("[BreakerBox] _auto_connect_to_nearby_wires: my_pos=%s  total_nodes=%d" % [my_pos, all_nodes.size()])

	## Collect candidates along each axis separately:
	##   neg_x: nodes to my -X that share ~same Z  (X-run wire, going left)
	##   pos_x: nodes to my +X that share ~same Z  (X-run wire, going right)
	##   neg_z: nodes to my -Z that share ~same X  (Z-run wire, going back)
	##   pos_z: nodes to my +Z that share ~same X  (Z-run wire, going front)
	## For each direction, keep only the closest.
	var best: Dictionary = {
		"neg_x": {"key": "", "dist": INF},
		"pos_x": {"key": "", "dist": INF},
		"neg_z": {"key": "", "dist": INF},
		"pos_z": {"key": "", "dist": INF},
	}

	for wn: Dictionary in all_nodes:
		var wn_key: String = wn.get("key", "")
		if wn_key == _wire_key:
			continue
		var wn_pos: Vector3 = wn.get("pos", Vector3.ZERO)
		var dx: float = wn_pos.x - my_pos.x
		var dz: float = wn_pos.z - my_pos.z
		var xz_dist: float = sqrt(dx * dx + dz * dz)
		if xz_dist > SEARCH_RADIUS or xz_dist < 0.05:
			continue

		## X-run candidates (share ~same Z):
		if absf(dz) <= COLINEAR_TOL:
			if dx < 0.0 and xz_dist < best["neg_x"]["dist"]:
				best["neg_x"]["key"]  = wn_key
				best["neg_x"]["dist"] = xz_dist
			elif dx > 0.0 and xz_dist < best["pos_x"]["dist"]:
				best["pos_x"]["key"]  = wn_key
				best["pos_x"]["dist"] = xz_dist

		## Z-run candidates (share ~same X):
		if absf(dx) <= COLINEAR_TOL:
			if dz < 0.0 and xz_dist < best["neg_z"]["dist"]:
				best["neg_z"]["key"]  = wn_key
				best["neg_z"]["dist"] = xz_dist
			elif dz > 0.0 and xz_dist < best["pos_z"]["dist"]:
				best["pos_z"]["key"]  = wn_key
				best["pos_z"]["dist"] = xz_dist

	## Connect to the nearest node in each filled direction.
	for dir: String in best:
		var candidate: Dictionary = best[dir]
		var ckey: String = candidate.get("key", "")
		if not ckey.is_empty():
			_wdbg("[BreakerBox]   → CONNECTING dir=%s to %s (dist=%.3f)" % [dir, ckey, candidate["dist"]])
			pm.call("register_wire_edge", _wire_key, ckey, null)


func notify_wire_placed(wn_key: String, wn_pos: Vector3) -> void:
	if _wire_key.is_empty():
		return
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null or not pm.has_method("register_wire_edge"):
		return
	## Use the PM-registered position (wire-snapped) rather than global_position
	## so the collinearity check works even when the breaker visual is at the
	## wall face (slightly off the wire grid).
	const SEARCH_RADIUS: float = 2.0
	const COLINEAR_TOL:  float = 0.15
	## Resolve our actual registered position from PM.
	var my_pos: Vector3 = global_position
	if pm.has_method("get_wire_nodes"):
		for wn: Dictionary in (pm.get_wire_nodes() as Array):
			if wn.get("key", "") == _wire_key:
				my_pos = wn.get("pos", global_position)
				break
	var dx: float = wn_pos.x - my_pos.x
	var dz: float = wn_pos.z - my_pos.z
	var dist: float = sqrt(dx * dx + dz * dz)
	if dist > SEARCH_RADIUS or dist < 0.05:
		return
	## Must be collinear: shares same X (Z-run) or same Z (X-run).
	if absf(dz) <= COLINEAR_TOL or absf(dx) <= COLINEAR_TOL:
		_wdbg("[BreakerBox] notify_wire_placed → connecting to %s" % wn_key)
		pm.call("register_wire_edge", _wire_key, wn_key, null)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER INTERFACE
# ══════════════════════════════════════════════════════════════════════════════

## Called by PM when trip state changes (LED + banner update only).
func set_tripped(on: bool) -> void:
	_tripped = on
	_sync_led()
	_sync_banner()
	## If settings panel is open, refresh it.
	if _settings_open and _settings_canvas != null:
		_settings_canvas.queue_redraw()


# ══════════════════════════════════════════════════════════════════════════════
# INTERACTION SYSTEM INTERFACE
# ══════════════════════════════════════════════════════════════════════════════

func get_interact_prompt() -> String:
	return "Breaker Settings [E]"


func on_interact() -> void:
	## Refresh zone index from PM before opening.
	_refresh_zone_index()
	_open_settings()


func set_player_in_range(in_range: bool) -> void:
	if _banner != null:
		_banner.visible = in_range
	if in_range:
		_sync_banner()
	## Close settings panel when player walks away.
	if not in_range and _settings_open:
		_close_settings()


# ══════════════════════════════════════════════════════════════════════════════
# SETTINGS PANEL
# ══════════════════════════════════════════════════════════════════════════════

func _build_settings_panel() -> void:
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 60
	_settings_layer.visible = false
	add_child(_settings_layer)

	_settings_canvas = Control.new()
	_settings_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_settings_canvas.name = "BreakerSettingsCanvas"
	_settings_layer.add_child(_settings_canvas)
	_settings_canvas.draw.connect(_on_settings_draw)
	_settings_canvas.gui_input.connect(_on_settings_input)


func _open_settings() -> void:
	if _settings_open:
		_close_settings()
		return
	_settings_open = true
	_settings_layer.visible = true
	_settings_canvas.queue_redraw()


func _close_settings() -> void:
	_settings_open = false
	_settings_layer.visible = false


func _on_settings_draw() -> void:
	if not _settings_open:
		return

	## Panel grows by TRIPPED_BANNER_H + RESTART_BTN_H while tripped so the
	## banner and restart button have room without cramping the existing rows.
	var extra_h: float   = (TRIPPED_BANNER_H + RESTART_BTN_H + 8.0) if _tripped else 0.0
	var panel_h: float   = PANEL_H + extra_h

	var vp: Vector2  = _settings_canvas.get_viewport_rect().size
	var px: float    = (vp.x - PANEL_W) * 0.5
	var py: float    = (vp.y - panel_h) * 0.5

	## Background dim
	_settings_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.45), true)

	## Panel bg + border
	_panel_rect = Rect2(px, py, PANEL_W, panel_h)
	_settings_canvas.draw_rect(_panel_rect, UI_BG, true)
	_settings_canvas.draw_rect(_panel_rect, UI_BORDER, false, 2.0)

	## ── TRIPPED banner (only while tripped) ────────────────────────────────
	## Bold red strip across the top so a tripped breaker is unmissable the
	## instant the panel opens — separate from the smaller "State:" label
	## further down, which stays for the at-a-glance zone/state summary.
	var content_top: float = py
	if _tripped:
		var banner_rect: Rect2 = Rect2(px, py, PANEL_W, TRIPPED_BANNER_H)
		_settings_canvas.draw_rect(banner_rect, UI_TRIPPED_BG, true)
		_settings_canvas.draw_rect(banner_rect, UI_OFF, false, 1.5)
		_ds("⚠  TRIPPED — power isolated", Vector2(px + PAD, py + TRIPPED_BANNER_H * 0.5 + 5.0), UI_TRIPPED_TEXT, 12)
		content_top += TRIPPED_BANNER_H

	## ── Title bar ─────────────────────────────────────────────────────────────
	var title_y: float = content_top + PAD + 11.0
	_ds("⚡ BREAKER SETTINGS", Vector2(px + PAD, title_y), UI_HEADER, 13)

	## ── Zone colour swatches (one per side of the breaker, up to 2) ──────────
	## Zone A — always present
	var swatch_a_col: Color = _zone_color()
	swatch_a_col.a = 1.0
	var swatch_size: float = 18.0
	var swatch_gap: float  = 4.0
	## If we have a second zone, show both side-by-side; otherwise centre the single swatch.
	var has_b: bool = _zone_index_b >= 0
	var swatches_total_w: float = swatch_size + (swatch_gap + swatch_size if has_b else 0.0)
	var swatch_start_x: float = px + PANEL_W - PAD - swatches_total_w
	var swatch_y: float = content_top + PAD + 1.0

	## Zone A swatch
	var swatch_a_rect: Rect2 = Rect2(swatch_start_x, swatch_y, swatch_size, swatch_size)
	_settings_canvas.draw_rect(swatch_a_rect, swatch_a_col, true)
	_settings_canvas.draw_rect(swatch_a_rect, UI_BORDER, false, 1.5)
	var lbl_a: String = "Z%d" % maxi(0, _zone_index)
	_ds(lbl_a, Vector2(swatch_a_rect.position.x + 1.0, swatch_y + swatch_size + 3.0), UI_DIM, 8)

	## Zone B swatch (only when breaker borders a second zone)
	if has_b:
		var swatch_b_col: Color = _zone_color_b()
		swatch_b_col.a = 1.0
		var swatch_b_rect: Rect2 = Rect2(swatch_start_x + swatch_size + swatch_gap, swatch_y, swatch_size, swatch_size)
		_settings_canvas.draw_rect(swatch_b_rect, swatch_b_col, true)
		_settings_canvas.draw_rect(swatch_b_rect, UI_BORDER, false, 1.5)
		var lbl_b: String = "Z%d" % _zone_index_b
		_ds(lbl_b, Vector2(swatch_b_rect.position.x + 1.0, swatch_y + swatch_size + 3.0), UI_DIM, 8)
		## Small divider pip between the two
		var mid_x: float = swatch_start_x + swatch_size + swatch_gap * 0.5
		_settings_canvas.draw_line(
			Vector2(mid_x, swatch_y + 3.0),
			Vector2(mid_x, swatch_y + swatch_size - 3.0),
			UI_BORDER * Color(1, 1, 1, 0.4), 1.0)

	## ── State label ───────────────────────────────────────────────────────────
	var state_y: float = title_y + 20.0
	var state_str: String = "TRIPPED" if _tripped else "ONLINE"
	var state_col: Color  = UI_OFF if _tripped else UI_ON
	_ds("State:  %s" % state_str, Vector2(px + PAD, state_y), state_col, 11)

	## ── Separator ─────────────────────────────────────────────────────────────
	var sep_y: float = state_y + 14.0
	_settings_canvas.draw_line(
		Vector2(px + PAD, sep_y),
		Vector2(px + PANEL_W - PAD, sep_y),
		UI_BORDER * Color(1, 1, 1, 0.5), 1.0)

	## ── Toggle rows ───────────────────────────────────────────────────────────
	## While tripped, pills are LOCKED — greyed out and their clicks ignored in
	## _on_settings_input (the values still reflect the forced-off state that
	## _self_trip_upgraded_breaker() set on PM's side; a standard breaker
	## tripped via Power Terminal keeps whatever pass-through values it had,
	## since the standard trip path doesn't force them off).
	var row1_y: float = sep_y + 10.0
	var row2_y: float = row1_y + ROW_H

	_rect_bat_toggle = _draw_toggle_row(
		"Allow battery power through", _pass_battery,
		px, row1_y, _tripped)

	_rect_gen_toggle = _draw_toggle_row(
		"Allow generator power through", _pass_generator,
		px, row2_y, _tripped)

	## ── Info line ─────────────────────────────────────────────────────────────
	var info_y: float = row2_y + ROW_H + 4.0
	var info_text: String = "Toggles locked while tripped" if _tripped else "Trip / reset via Power Terminal"
	_ds(info_text, Vector2(px + PAD, info_y), UI_DIM, 9)

	## ── RESTART button (only while tripped) ───────────────────────────────────
	if _tripped:
		var restart_y: float = info_y + 14.0
		_rect_restart = Rect2(px + PAD, restart_y, PANEL_W - PAD * 2.0, RESTART_BTN_H)
		_settings_canvas.draw_rect(_rect_restart, Color(0.06, 0.16, 0.08, 0.90), true)
		_settings_canvas.draw_rect(_rect_restart, UI_ON * Color(1, 1, 1, 0.85), false, 1.5)
		_ds("⟳  RESTART BREAKER", Vector2(px + PAD + 10.0, restart_y + RESTART_BTN_H * 0.5 + 5.0), UI_ON, 12)
	else:
		_rect_restart = Rect2()   ## no hit target when not tripped

	## ── Close button ──────────────────────────────────────────────────────────
	_rect_close = Rect2(px + PANEL_W - PAD - 24.0, py + panel_h - PAD - 20.0, 24.0, 20.0)
	_settings_canvas.draw_rect(_rect_close, Color(0.25, 0.06, 0.06, 0.90), true)
	_settings_canvas.draw_rect(_rect_close, UI_OFF * Color(1, 1, 1, 0.7), false, 1.5)
	_ds("✕", Vector2(_rect_close.position.x + 5.0, _rect_close.position.y + 14.0), Color(1.0, 0.7, 0.7, 1.0), 11)

	_ds("[ESC] close", Vector2(px + PAD, py + panel_h - PAD - 10.0), UI_DIM, 9)


## Draw one toggle row; returns its hit rect.
## locked=true (only while tripped) greys the whole row and the pill so it
## reads as disabled — _on_settings_input separately refuses to act on the
## hit rect while _tripped, so this is purely visual confirmation of that.
func _draw_toggle_row(label: String, value: bool, px: float, ry: float, locked: bool = false) -> Rect2:
	var row_rect: Rect2 = Rect2(px + PAD, ry, PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_settings_canvas.draw_rect(row_rect, Color(0.10, 0.14, 0.10, 0.60), true)
	_settings_canvas.draw_rect(row_rect, UI_BORDER * Color(1, 1, 1, 0.35), false, 1.0)

	var text_y: float = ry + 20.0
	var text_col: Color = UI_LOCK_DIM if locked else UI_TEXT
	_ds(label, Vector2(px + PAD + 6.0, text_y), text_col, 10)

	## Toggle pill on right
	var pill_w: float = 42.0
	var pill_h: float = 18.0
	var pill_x: float = px + PANEL_W - PAD - pill_w - 4.0
	var pill_y: float = ry + (ROW_H - pill_h) * 0.5 - 2.0
	var pill_rect: Rect2 = Rect2(pill_x, pill_y, pill_w, pill_h)
	var pill_col: Color  = UI_LOCK_DIM if locked else (UI_ON if value else UI_DIM)
	_settings_canvas.draw_rect(pill_rect, pill_col * Color(1, 1, 1, 0.75), true)
	_settings_canvas.draw_rect(pill_rect, pill_col, false, 1.5)
	var pill_label_col: Color = Color(0.7, 0.7, 0.7, 0.8) if locked else Color(1, 1, 1, 0.95)
	_ds("ON" if value else "OFF", Vector2(pill_x + 9.0, pill_y + 12.0), pill_label_col, 9)

	return row_rect


func _on_settings_input(event: InputEvent) -> void:
	if not _settings_open:
		return

	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_settings()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mpos: Vector2 = (event as InputEventMouseButton).position

		if _rect_close.has_point(mpos):
			_close_settings()
			get_viewport().set_input_as_handled()
			return

		if _tripped and _rect_restart.has_point(mpos):
			_request_restart()
			get_viewport().set_input_as_handled()
			return

		## Pass-through toggles are LOCKED while tripped — ignore clicks on
		## either pill entirely (the pills already render greyed via _tripped
		## passed into _draw_toggle_row, so this matches the visual state).
		if not _tripped:
			if _rect_bat_toggle.has_point(mpos):
				_pass_battery = not _pass_battery
				_send_passthrough_to_pm()
				_settings_canvas.queue_redraw()
				get_viewport().set_input_as_handled()
				return

			if _rect_gen_toggle.has_point(mpos):
				_pass_generator = not _pass_generator
				_send_passthrough_to_pm()
				_settings_canvas.queue_redraw()
				get_viewport().set_input_as_handled()
				return

		## Eat all clicks inside the panel so they don't pass to the world.
		if _panel_rect.has_point(mpos):
			get_viewport().set_input_as_handled()


## Player clicked RESTART while tripped.  Calls PowerManager.reset_breaker(),
## which un-trips this breaker and re-solves.  NOTE: reset_breaker() only
## clears the "tripped" flag — it does NOT restore pass_battery/pass_generator
## to their pre-trip values (a standard breaker tripped via Power Terminal
## never touched those flags anyway; an upgraded breaker's self-trip forced
## them to false).  After restart the player must manually re-enable any
## pass-through they want — this matches the plan's "pass-throughs become
## re-toggleable again" wording (re-toggleable, not auto-restored).
func _request_restart() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm != null and pm.has_method("reset_breaker") and not _breaker_id.is_empty():
		pm.call("reset_breaker", _breaker_id)
		_settings_canvas.queue_redraw()


func _send_passthrough_to_pm() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm != null and pm.has_method("set_breaker_passthrough") \
			and not _breaker_id.is_empty():
		pm.call("set_breaker_passthrough", _breaker_id, _pass_battery, _pass_generator)


## Query PM for the wire zone index of this breaker's snap key.
func _refresh_zone_index() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null or not pm.has_method("get_zone_snapshot"):
		_zone_index   = -1
		_zone_index_b = -1
		return
	var zones: Array = pm.call("get_zone_snapshot")
	_zone_index   = -1
	_zone_index_b = -1
	## Collect up to two zone indices that list this breaker's wire key
	## in their breaker_keys array (one zone per side of the breaker).
	var found: Array[int] = []
	for zd: Dictionary in zones:
		var brk_keys: Array = zd.get("breaker_keys", [])
		for bk: String in brk_keys:
			if bk == _wire_key:
				found.append(int(zd.get("zone_index", 0)))
				break   ## One match per zone is enough.
	if found.size() >= 1:
		_zone_index = found[0]
	if found.size() >= 2:
		_zone_index_b = found[1]


func _zone_color() -> Color:
	if _zone_index < 0:
		return Color(0.50, 0.50, 0.50, 0.60)   ## grey = unassigned
	return _palette_col(_zone_index)

func _zone_color_b() -> Color:
	if _zone_index_b < 0:
		return Color(0.50, 0.50, 0.50, 0.60)
	return _palette_col(_zone_index_b)


# ══════════════════════════════════════════════════════════════════════════════
# MESH BUILD
# ══════════════════════════════════════════════════════════════════════════════

func _build_mesh() -> void:
	## ── Main body ─────────────────────────────────────────────────────────────
	var body_mi:   MeshInstance3D = MeshInstance3D.new()
	var body_mesh: BoxMesh        = BoxMesh.new()
	body_mesh.size = BOX_SIZE
	body_mi.mesh   = body_mesh
	body_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.80
	body_mat.metallic     = 0.50
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)
	body_mi.create_trimesh_collision()
	for child: Node in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## ── Front control panel ───────────────────────────────────────────────────
	var panel_mi:   MeshInstance3D = MeshInstance3D.new()
	var panel_mesh: BoxMesh        = BoxMesh.new()
	panel_mesh.size  = Vector3(BOX_SIZE.x * 0.80, BOX_SIZE.y * 0.60, 0.03)
	panel_mi.mesh    = panel_mesh
	panel_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, BOX_SIZE.z * 0.5 + 0.015)
	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = COLOR_PANEL
	panel_mat.roughness    = 0.70
	panel_mi.set_surface_override_material(0, panel_mat)
	add_child(panel_mi)

	## ── LED indicator ─────────────────────────────────────────────────────────
	var led_mi:   MeshInstance3D = MeshInstance3D.new()
	var led_mesh: BoxMesh        = BoxMesh.new()
	led_mesh.size  = Vector3(0.06, 0.06, 0.03)
	led_mi.mesh    = led_mesh
	led_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5 + BOX_SIZE.y * 0.15, BOX_SIZE.z * 0.5 + 0.035)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color              = COLOR_LED_ON
	_led_mat.emission_enabled          = true
	_led_mat.emission                  = COLOR_LED_ON
	_led_mat.emission_energy_multiplier = 2.0
	led_mi.set_surface_override_material(0, _led_mat)
	add_child(led_mi)

	## ── Breaker lever ─────────────────────────────────────────────────────────
	var lever_mi:   MeshInstance3D = MeshInstance3D.new()
	var lever_mesh: BoxMesh        = BoxMesh.new()
	lever_mesh.size  = Vector3(0.055, 0.13, 0.025)
	lever_mi.mesh    = lever_mesh
	lever_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5 - BOX_SIZE.y * 0.10, BOX_SIZE.z * 0.5 + 0.040)
	var lever_mat: StandardMaterial3D = StandardMaterial3D.new()
	lever_mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0)
	lever_mat.roughness    = 0.60
	lever_mi.set_surface_override_material(0, lever_mat)
	add_child(lever_mi)


# ══════════════════════════════════════════════════════════════════════════════
# BANNER
# ══════════════════════════════════════════════════════════════════════════════

func _build_banner() -> void:
	var lbl: Label3D = Label3D.new()
	lbl.text          = "[E] Breaker Settings"
	lbl.font_size     = 48
	lbl.pixel_size    = 0.0018
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate      = Color(0.90, 0.95, 0.90, 1.0)
	lbl.position      = Vector3(0.0, BOX_SIZE.y + 0.18, 0.0)
	lbl.visible       = false
	add_child(lbl)
	_banner = lbl


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL SYNC
# ══════════════════════════════════════════════════════════════════════════════

func _sync_led() -> void:
	if _led_mat == null:
		return
	var col: Color = COLOR_LED_OFF if _tripped else COLOR_LED_ON
	_led_mat.albedo_color = col
	_led_mat.emission     = col


func _sync_banner() -> void:
	if _banner == null:
		return
	if _tripped:
		_banner.text     = "[E] Breaker Settings  (TRIPPED)"
		_banner.modulate = Color(1.0, 0.55, 0.15, 1.0)
	else:
		_banner.text     = "[E] Breaker Settings"
		_banner.modulate = Color(0.90, 0.95, 0.90, 1.0)


## Shorthand draw helper for the CanvasLayer draw callbacks.
func _ds(text: String, pos: Vector2, col: Color, size: int) -> void:
	_settings_canvas.draw_string(
		_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	_settings_canvas.draw_string(
		_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
