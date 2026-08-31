extends Control
class_name StatusEffectIcon
## StatusEffectIcon.gd
## ─────────────────────────────────────────────────────────────────────────
## Single reusable status-effect badge: a small icon centered inside a ring.
## Two independent modes, selected per-badge at setup time:
##
##   1. TIMER mode (original, Jul 2026 skeleton) — the ring depletes
##      CLOCKWISE as a fixed duration counts down on its own via
##      _process(). Used by AdminMenu's generic test-effect row.
##
##   2. MEDICAL mode (Aug 2026, Pass 1) — the ring is driven EXTERNALLY,
##      once per tick, by PlayerMedical/NPCMedical via update_medical().
##      No internal countdown. Two fills share the same ring track rather
##      than being separate concentric rings, per
##      docs/systems/medical/README.md's "Healing (the Healed ring)":
##        - severity_frac (0-1): how much of the circle is "filled" at all
##          — 1.0 for a pinned-severity condition (Open Wound, Broken,
##          Burns), severity/100 for a live one (Bleeding, Infection,
##          Fractured).
##        - heal_frac (0-1): the Healed fill, drawn OVER the start of the
##          severity arc in a distinct color. Callers must keep
##          heal_frac <= severity_frac themselves (PlayerMedical already
##          clamps heal_progress to severity before passing it in) — this
##          file does not re-clamp, since silently clamping here would
##          hide a caller bug instead of surfacing it.
##      Conditions with no Healed ring of their own (Bleeding, Infection —
##      see the design doc's "Severity / progress model") simply never
##      have update_medical() called with a nonzero heal_frac.
##
## Usage (medical):
##     var badge := StatusEffectIcon.new()
##     badge.setup_medical("open_wound_LEFT_ARM", null, Color(0.85, 0.3, 0.2))
##     badge.update_medical(1.0, 0.4, "Open Wound (Left Arm)\nHealing...")
##
## Usage (timer, unchanged):
##     var badge := StatusEffectIcon.new()
##     badge.setup("poisoned", some_icon_texture, 12.0, Color(0.85, 0.3, 0.2))

signal expired(effect_id: String)

const RADIUS: float    = 22.0
const THICKNESS: float = 4.0
const BG_RING_COLOR: Color = Color(0.15, 0.15, 0.15, 0.85)
const PANEL_COLOR:   Color = Color(0.10, 0.10, 0.10, 0.90)
const ICON_SIZE: float = 22.0
const PLACEHOLDER_COLOR: Color = Color(0.55, 0.55, 0.55, 0.90)   ## blank grey "no icon yet" fill
const RUGGED_BORDER_COLOR: Color = Color(0.02, 0.02, 0.02, 0.55)
const RUGGED_BORDER_WIDTH: float = 1.2

## Healed-fill overlay color — shared across every medical badge regardless
## of the condition's own severity ring_color, so "blue = healing progress"
## reads consistently at a glance. Matches the design doc's "blue ring"
## description.
const HEAL_COLOR: Color = Color(0.30, 0.60, 0.95, 1.0)

var effect_id: String = ""
var _icon: Texture2D = null
var _ring_color: Color = Color(0.86, 0.57, 0.19, 1.0)   ## Jul 2026 — darkened 5%

## ── TIMER mode state ────────────────────────────────────────────────────
var _total_duration: float = 1.0
var _remaining: float = 1.0

## ── MEDICAL mode state ──────────────────────────────────────────────────
var _is_medical: bool = false
var _severity_frac: float = 1.0
var _heal_frac: float = 0.0
var _has_heal_ring: bool = false

## ── Outer ring state (Aug 2026, Pass 2) ─────────────────────────────────
## A genuinely SEPARATE concentric ring, distinct from the severity/Healed
## overlay above — currently only used for Open Wound (Infected)'s
## Infection Severity, per docs/systems/medical/README.md's confirmed
## "2 rings total, not 3" model (severity+Healed share one ring; Infection
## gets its own). Live + bidirectional, no Healed fill of its own — same
## reasoning as Bleeding's single ring.
var _has_outer_ring: bool = false
var _outer_frac: float = 0.0
var _outer_color: Color = Color(0.75, 0.55, 0.15, 1.0)
const OUTER_RING_GAP: float = 0.0   ## touching/hugging the main ring's outer edge, not floating separate from it
const OUTER_RING_THICKNESS: float = 3.0

func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 6.0, RADIUS * 2.0 + 6.0)
	var grime_mat: ShaderMaterial = ShaderMaterial.new()
	grime_mat.shader = load("res://assets/shaders/grunge_overlay.gdshader")
	material = grime_mat
	mouse_filter = Control.MOUSE_FILTER_STOP   ## needed for tooltip_text to show on hover

## Starts (or restarts) this badge in TIMER mode, showing `icon` (may be
## null — blank center) with a depletion ring in `ring_color`, counting
## down from `duration` seconds. Emits `expired` with `id` once remaining
## time hits 0 — the container is responsible for removing/freeing this
## node when it does.
func setup(id: String, icon: Texture2D, duration: float, ring_color: Color) -> void:
	effect_id       = id
	_icon           = icon
	_total_duration = maxf(duration, 0.01)
	_remaining      = _total_duration
	_ring_color     = ring_color
	_is_medical     = false
	queue_redraw()

## Starts (or restarts) this badge in MEDICAL mode. No countdown — call
## update_medical() to drive the ring afterward, once per tick, from
## PlayerMedical/NPCMedical.
func setup_medical(id: String, icon: Texture2D, ring_color: Color, has_heal_ring: bool) -> void:
	effect_id      = id
	_icon          = icon
	_ring_color    = ring_color
	_has_heal_ring = has_heal_ring
	_is_medical    = true
	_severity_frac = 1.0
	_heal_frac     = 0.0
	queue_redraw()

## Updates a MEDICAL-mode badge's fill fractions and hover tooltip. Safe to
## call every frame — only triggers a redraw, no allocation beyond the
## tooltip string the caller already built.
func update_medical(severity_frac: float, heal_frac: float, tooltip: String) -> void:
	_severity_frac = clampf(severity_frac, 0.0, 1.0)
	_heal_frac     = heal_frac
	tooltip_text   = tooltip
	queue_redraw()

## Sets/updates the separate outer ring (currently Infection severity
## only — see the class field comment above). Pass has_outer=false to hide
## it again (e.g. a cured infection reverting the wound to plain Open
## Wound). Safe to call every frame like update_medical().
func set_outer_ring(has_outer: bool, frac: float, color: Color) -> void:
	_has_outer_ring = has_outer
	_outer_frac     = clampf(frac, 0.0, 1.0)
	_outer_color    = color
	queue_redraw()

func _process(delta: float) -> void:
	if _is_medical:
		return   ## medical badges are driven externally via update_medical()
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	queue_redraw()
	if _remaining <= 0.0:
		expired.emit(effect_id)

func _draw() -> void:
	var center: Vector2 = Vector2(RADIUS + 3.0, RADIUS + 3.0)
	draw_circle(center, RADIUS - THICKNESS * 0.5, PANEL_COLOR)
	draw_arc(center, RADIUS, 0.0, TAU, 48, BG_RING_COLOR, THICKNESS, true)

	if _is_medical:
		_draw_medical_rings(center)
	else:
		_draw_timer_ring(center)

	if _icon != null:
		var half: float = ICON_SIZE * 0.5
		var dst: Rect2 = Rect2(center - Vector2(half, half), Vector2(ICON_SIZE, ICON_SIZE))
		draw_texture_rect(_icon, dst, false)
	else:
		## Blank grey placeholder — no real icon art exists yet (Jul 2026).
		draw_circle(center, ICON_SIZE * 0.5, PLACEHOLDER_COLOR)
	UIKit.draw_rugged_circle(self, center, RADIUS + THICKNESS * 0.5, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 700.0)
	UIKit.draw_rugged_circle(self, center, RADIUS - THICKNESS * 0.5, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 850.0)
	if _has_outer_ring:
		_draw_outer_ring(center)

## Draws the outer ring's background + fill arcs, then its own rugged
## border on both edges — matching the same UIKit.draw_rugged_circle
## treatment the main ring gets, just at the outer ring's own radius/
## thickness and with different jitter seeds so the two borders don't
## look identical/mirrored to each other.
func _draw_outer_ring(center: Vector2) -> void:
	var outer_radius: float = RADIUS + THICKNESS * 0.5 + OUTER_RING_GAP + OUTER_RING_THICKNESS * 0.5
	draw_arc(center, outer_radius, 0.0, TAU, 48, BG_RING_COLOR, OUTER_RING_THICKNESS, true)
	if _outer_frac > 0.0:
		var end_angle: float = -PI / 2.0 + TAU * _outer_frac
		draw_arc(center, outer_radius, -PI / 2.0, end_angle, 48, _outer_color, OUTER_RING_THICKNESS, true)
	UIKit.draw_rugged_circle(self, center, outer_radius + OUTER_RING_THICKNESS * 0.5, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 1000.0)
	UIKit.draw_rugged_circle(self, center, outer_radius - OUTER_RING_THICKNESS * 0.5, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 1150.0)

func _draw_timer_ring(center: Vector2) -> void:
	if _total_duration <= 0.0:
		return
	var frac: float = _remaining / _total_duration
	if frac > 0.0:
		var end_angle: float = -PI / 2.0 + TAU * frac
		draw_arc(center, RADIUS, -PI / 2.0, end_angle, 48, _ring_color, THICKNESS, true)

## Draws the severity arc, then — if this condition tracks natural healing
## — the Healed fill OVER the start of that same arc. heal_frac is drawn
## trusting the caller's clamp (heal_frac <= severity_frac); see the class
## doc comment for why this file doesn't re-clamp it.
func _draw_medical_rings(center: Vector2) -> void:
	if _severity_frac > 0.0:
		var severity_end: float = -PI / 2.0 + TAU * _severity_frac
		draw_arc(center, RADIUS, -PI / 2.0, severity_end, 48, _ring_color, THICKNESS, true)
	if _has_heal_ring and _heal_frac > 0.0:
		var heal_end: float = -PI / 2.0 + TAU * _heal_frac
		draw_arc(center, RADIUS, -PI / 2.0, heal_end, 48, HEAL_COLOR, THICKNESS, true)
