extends Node
## NotificationManager.gd
## ─────────────────────────────────────────────────────────────────────────────
## Central toast/notification system (Jul 2026, "UI Kit + Central
## Notification System" plan, Part 2). Skeleton + rendering only in this
## pass — Part 2's actual alert-source wiring (power signals, new water
## signals, player-stats threshold watching) is later work, NOT done here.
## Call `notify()` directly (e.g. from the debug console or a manual test)
## to exercise the queue/rendering pipeline until that wiring lands.
##
## Registered as a true project-level autoload (`project.godot`'s
## `[autoload]` section, alongside `SaveManager`/`WorldManager`/
## `DeviceDatabase`/`GraphicsSettings`) rather than the group-lookup pattern
## `WaterManager`/`PowerManager`/`PlayerStats` use — a notification is a
## global service with no save-specific world state ("show this text for a
## while"), so it needs to be reachable identically from every scene
## without `MainWorld` wiring it up, matching the real autoload precedent
## instead of the per-scene-instance one.
##
## Usage:
##     NotificationManager.notify(UIKit.Domain.POWER,
##         NotificationManager.Severity.CRITICAL, "Grid tripped")
##
## Queue design (Brannon's confirmed spec):
## - Queue-based, newest notification appended at the BOTTOM of the visual
##   stack. Oldest at top, since older entries naturally tend to expire
##   first, no special reordering needed beyond redrawing the whole stack
##   from `_queue` every frame.
## - Each toast fades out independently after its own `duration` (last
##   ~20% of lifetime ramps alpha to 0 — `FADE_TAIL_RATIO`).
## - Queue length is capped defensively (`MAX_QUEUE_LEN = 20`, this pass's
##   own reasonable default per the plan's own suggested number — flag back
##   if a different cap is wanted) so a signal storm can't leak memory;
##   drops the OLDEST entry first when exceeded.
##
## Visual treatment reuses `UIKit` directly — each toast is a small
## `UIKit.draw_panel()` using `UIKit.theme_for(entry.domain)`, so a power
## alert reads green, a water alert reads blue, a neutral one reads
## steel-gray — tying both halves of this plan together. `severity` drives
## which color tints the toast's text/left accent bar WITHIN that domain
## (INFO uses `theme.text`, WARNING uses `theme.warn`, CRITICAL uses
## `theme.crit`) — domain says WHERE it's from, severity says HOW urgent.

enum Severity { INFO, WARNING, CRITICAL }

const MAX_QUEUE_LEN: int = 20

const TOAST_WIDTH:      float = 340.0
const TOAST_HEIGHT:     float = 48.0
const TOAST_GAP:        float = 8.0
const STACK_MARGIN:     Vector2 = Vector2(24.0, 24.0)   ## top-right inset
const ACCENT_BAR_WIDTH: float = 4.0
const FADE_TAIL_RATIO:  float = 0.20   ## last 20% of lifetime ramps alpha -> 0
const DEFAULT_DURATION: float = 4.0

## Each entry: { domain: UIKit.Domain, severity: Severity, text: String,
##               duration: float, age: float }
var _queue: Array[Dictionary] = []

var _canvas: Control = null


func _ready() -> void:
	## Own CanvasLayer, spawned once, always present — same pattern every
	## other panel in this project uses (WaterDispenserUI=60,
	## TransientNotice=65, PauseMenuUI=200, GraphicsSettingsPanel=210).
	## Set above all of those so a toast is never hidden behind an open
	## panel or menu (per the plan's §4.2 "respect other modals" note —
	## toasts keep queueing/rendering in their own corner regardless).
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 220
	layer.name  = "NotificationLayer"
	add_child(layer)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE   ## purely informational, never blocks input
	_canvas.name = "NotificationCanvas"
	layer.add_child(_canvas)
	_canvas.draw.connect(_on_draw)


## Queues a new toast. `domain` picks the color scheme (WATER/POWER/
## NEUTRAL), `severity` picks the accent tint within that scheme.
func notify(domain: UIKit.Domain, severity: Severity, text: String, duration: float = DEFAULT_DURATION) -> void:
	_queue.append({
		"domain":   domain,
		"severity": severity,
		"text":     text,
		"duration": duration,
		"age":      0.0,
	})
	if _queue.size() > MAX_QUEUE_LEN:
		_queue.pop_front()   ## drop oldest first — defensive cap, not expected in normal play
	if _canvas != null:
		_canvas.queue_redraw()


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	for entry: Dictionary in _queue:
		entry["age"] = float(entry["age"]) + delta
	_queue = _queue.filter(func(e: Dictionary) -> bool: return float(e["age"]) < float(e["duration"]))
	_canvas.queue_redraw()   ## fade ramps continuously, needs a redraw every frame while anything is queued


func _on_draw() -> void:
	if _queue.is_empty():
		return
	var vp: Vector2 = _canvas.get_viewport().get_visible_rect().size
	var y: float = STACK_MARGIN.y
	for entry: Dictionary in _queue:
		var rect: Rect2 = Rect2(vp.x - STACK_MARGIN.x - TOAST_WIDTH, y, TOAST_WIDTH, TOAST_HEIGHT)
		_draw_toast(rect, entry)
		y += TOAST_HEIGHT + TOAST_GAP


func _draw_toast(rect: Rect2, entry: Dictionary) -> void:
	var domain: UIKit.Domain     = entry["domain"]
	var severity: Severity      = entry["severity"]
	var text: String            = entry["text"]
	var age: float               = float(entry["age"])
	var duration: float          = float(entry["duration"])

	var alpha: float = _fade_alpha(age, duration)
	var theme: UIKit.UITheme = _theme_with_alpha(UIKit.theme_for(domain), alpha)

	UIKit.draw_panel(_canvas, rect, theme, 1.5)

	## Left accent bar — severity color, full toast height. Gives a
	## colorblind-safer secondary cue alongside the accent text color
	## itself (both encode the same severity).
	var accent: Color = _severity_color(theme, severity)
	var accent_rect: Rect2 = Rect2(rect.position, Vector2(ACCENT_BAR_WIDTH, rect.size.y))
	_canvas.draw_rect(accent_rect, Color(accent.r, accent.g, accent.b, accent.a), true)

	var text_pos: Vector2 = rect.position + Vector2(ACCENT_BAR_WIDTH + 14.0, rect.size.y * 0.5 + 5.0)
	UIKit.draw_shadowed_text(_canvas, text_pos, text, 13, accent)


func _severity_color(theme: UIKit.UITheme, severity: Severity) -> Color:
	match severity:
		Severity.WARNING:
			return theme.warn
		Severity.CRITICAL:
			return theme.crit
		_:
			return theme.text


## Last FADE_TAIL_RATIO of the toast's lifetime ramps alpha 1.0 -> 0.0;
## flat 1.0 before that.
func _fade_alpha(age: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	var ratio: float = age / duration
	var fade_start: float = 1.0 - FADE_TAIL_RATIO
	if ratio <= fade_start:
		return 1.0
	return clampf(1.0 - (ratio - fade_start) / FADE_TAIL_RATIO, 0.0, 1.0)


## Returns a copy of `theme` with every color's alpha multiplied by
## `alpha` — lets one shared Theme fade uniformly without UIKit's drawing
## primitives needing their own alpha parameter.
func _theme_with_alpha(theme: UIKit.UITheme, alpha: float) -> UIKit.UITheme:
	var t: UIKit.UITheme = UIKit.UITheme.new()
	t.bg     = Color(theme.bg.r, theme.bg.g, theme.bg.b, theme.bg.a * alpha)
	t.border = Color(theme.border.r, theme.border.g, theme.border.b, theme.border.a * alpha)
	t.header = Color(theme.header.r, theme.header.g, theme.header.b, theme.header.a * alpha)
	t.text   = Color(theme.text.r, theme.text.g, theme.text.b, theme.text.a * alpha)
	t.dim    = Color(theme.dim.r, theme.dim.g, theme.dim.b, theme.dim.a * alpha)
	t.ok     = Color(theme.ok.r, theme.ok.g, theme.ok.b, theme.ok.a * alpha)
	t.warn   = Color(theme.warn.r, theme.warn.g, theme.warn.b, theme.warn.a * alpha)
	t.crit   = Color(theme.crit.r, theme.crit.g, theme.crit.b, theme.crit.a * alpha)
	return t
