extends Control
class_name NeedsGauge
## NeedsGauge.gd
## Composite radial HUD gauge for the 5 survival needs (Jul 2026 redesign,
## replaces the old StatusBars.gd (health/stamina rectangles) + CircleFill.gd
## x3 (food/water/sleep icon circles) with a Medieval-Dynasty-style triple
## concentric ring, per Brannon's reference image.
##
## RING ASSIGNMENTS (center outward):
##   Ring 1 (innermost) — Health (left half, red)  / Food  (right half, orange)
##   Ring 2 (middle)    — Stamina (left half, green) / Water (right half, blue)
## Ring 3 (outermost) — Sleep (RIGHT HALF ONLY, purple). Originally mirrored
##                         both sides; trimmed to right-only per Brannon's
##                         call (Jul 2026 adjustment pass) — left half is
##                         simply never drawn.
##
## Each half-arc is BOTTOM-ANCHORED (Brannon's explicit call): the tip nearest
## the bottom V-gap is always fully drawn at any fill > 0, and the arc grows
## UPWARD toward the top V-gap tip as the stat fills toward 100%. At 0% the
## arc is invisible (zero-length) right at the bottom anchor point.
##
## No icons (Brannon's explicit call, Jul 2026 redesign) — center is a plain
## blank dark circle, matching the reference image exactly.

# ─── Layout constants ────────────────────────────────────────────────────────
const CENTER: Vector2 = Vector2(90.0, 90.0)   ## widget is 180x180, center at (90,90)

const RING1_RADIUS: float = 40.0   ## Health / Food
const RING2_RADIUS: float = 56.0   ## Stamina / Water
const RING3_RADIUS: float = 74.0   ## Sleep

const RING1_THICKNESS: float = 10.0
const RING2_THICKNESS: float = 10.0
const RING3_THICKNESS: float = 9.0

const CENTER_CIRCLE_RADIUS: float = 32.0
const CENTER_CIRCLE_COLOR: Color = Color(0.13, 0.13, 0.13, 0.88)

const TRACK_COLOR: Color = Color(0.08, 0.08, 0.08, 0.90)   ## unfilled arc background, all rings

const GAP_ANGLE_DEG: float = 14.0
const ARC_SEGMENTS: int = 48

const RUGGED_BORDER_COLOR: Color = Color(0.02, 0.02, 0.02, 0.55)
const RUGGED_BORDER_WIDTH: float = 1.4

# ─── Colors (fill) ────────────────────────────────────────────────────────────
const COLOR_HEALTH:  Color = Color(0.81, 0.17, 0.17, 1.0)   # red (Jul 2026 — darkened 5%)
const COLOR_FOOD:    Color = Color(0.90, 0.52, 0.14, 1.0)   # orange (Jul 2026 — darkened 5%)
const COLOR_STAMINA: Color = Color(0.29, 0.81, 0.24, 1.0)   # green (Jul 2026 — darkened 5%)
const COLOR_WATER:   Color = Color(0.24, 0.52, 0.90, 1.0)   # blue (Jul 2026 — darkened 5%)
const COLOR_SLEEP:   Color = Color(0.57, 0.33, 0.81, 1.0)   # purple (Jul 2026 — darkened 5%)

# ─── State (0.0 - 1.0 fractions) ──────────────────────────────────────────────
var _health:  float = 1.0
var _food:    float = 1.0
var _stamina: float = 1.0
var _water:   float = 1.0
var _sleep:   float = 1.0

func _ready() -> void:
	custom_minimum_size = Vector2(180.0, 180.0)
	var grime_mat: ShaderMaterial = ShaderMaterial.new()
	grime_mat.shader = load("res://assets/shaders/grunge_overlay.gdshader")
	material = grime_mat

# ─── Public API — values are 0.0-1.0 fractions (caller, HUD.gd, converts from 0-100) ──
func set_health(frac: float) -> void:
	_health = clampf(frac, 0.0, 1.0)
	queue_redraw()

func set_food(frac: float) -> void:
	_food = clampf(frac, 0.0, 1.0)
	queue_redraw()

func set_stamina(frac: float) -> void:
	_stamina = clampf(frac, 0.0, 1.0)
	queue_redraw()

func set_water(frac: float) -> void:
	_water = clampf(frac, 0.0, 1.0)
	queue_redraw()

func set_sleep(frac: float) -> void:
	_sleep = clampf(frac, 0.0, 1.0)
	queue_redraw()

# ─── Drawing ──────────────────────────────────────────────────────────────────
func _draw() -> void:
	var gap: float = deg_to_rad(GAP_ANGLE_DEG)

	# Center blank circle
	draw_circle(CENTER, CENTER_CIRCLE_RADIUS, CENTER_CIRCLE_COLOR)
	UIKit.draw_rugged_circle(self, CENTER, CENTER_CIRCLE_RADIUS, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 500.0)

	# Ring 1 — Health (left) / Food (right)
	_draw_left_half(RING1_RADIUS, RING1_THICKNESS, gap, _health, COLOR_HEALTH)
	_draw_right_half(RING1_RADIUS, RING1_THICKNESS, gap, _food, COLOR_FOOD)

	# Ring 2 — Stamina (left) / Water (right)
	_draw_left_half(RING2_RADIUS, RING2_THICKNESS, gap, _stamina, COLOR_STAMINA)
	_draw_right_half(RING2_RADIUS, RING2_THICKNESS, gap, _water, COLOR_WATER)

	# Ring 3 — Sleep (right side ONLY, per Brannon's call — left half is
	# intentionally never drawn, not just zeroed out, so nothing renders
	# there, not even an empty track).
	_draw_right_half(RING3_RADIUS, RING3_THICKNESS, gap, _sleep, COLOR_SLEEP)

## Left-half arc: track spans [bottom_edge, top_edge] going clockwise through
## 9 o'clock. Bottom-anchored: fill arc always starts at bottom_edge (fixed)
## and grows toward top_edge as fill increases.
func _draw_left_half(radius: float, thickness: float, gap: float, fill: float, color: Color) -> void:
	var bottom_edge: float = PI / 2.0 + gap
	var top_edge:    float = 3.0 * PI / 2.0 - gap
	draw_arc(CENTER, radius, bottom_edge, top_edge, ARC_SEGMENTS, TRACK_COLOR, thickness, true)
	if fill > 0.0:
		var current_end: float = bottom_edge + (top_edge - bottom_edge) * fill
		draw_arc(CENTER, radius, bottom_edge, current_end, ARC_SEGMENTS, color, thickness, true)
	UIKit.draw_rugged_arc(self, CENTER, radius + thickness * 0.5, bottom_edge, top_edge,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, radius)
	UIKit.draw_rugged_arc(self, CENTER, radius - thickness * 0.5, bottom_edge, top_edge,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, radius + 100.0)

## Right-half arc: track spans [top_edge, bottom_edge] going clockwise through
## 3 o'clock. Bottom-anchored: fill arc always ENDS at bottom_edge (fixed)
## and its start grows toward top_edge as fill increases.
func _draw_right_half(radius: float, thickness: float, gap: float, fill: float, color: Color) -> void:
	var top_edge:    float = -PI / 2.0 + gap
	var bottom_edge: float = PI / 2.0 - gap
	draw_arc(CENTER, radius, top_edge, bottom_edge, ARC_SEGMENTS, TRACK_COLOR, thickness, true)
	if fill > 0.0:
		var sweep_range: float = bottom_edge - top_edge
		var current_start: float = bottom_edge - sweep_range * fill
		draw_arc(CENTER, radius, current_start, bottom_edge, ARC_SEGMENTS, color, thickness, true)
	UIKit.draw_rugged_arc(self, CENTER, radius + thickness * 0.5, top_edge, bottom_edge,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, radius + 200.0)
	UIKit.draw_rugged_arc(self, CENTER, radius - thickness * 0.5, top_edge, bottom_edge,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, radius + 300.0)