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
## Visual treatment (reworked Jul 2026, replacing the original top-right
## domain-tinted stack): each toast is a solid severity-colored rectangle
## (semi-transparent fill, dark semi-transparent border), stacked ABOVE the
## inventory bar — newest toast closest to the bar, older ones pushed
## upward — matching the look/position of the old pre-NotificationManager
## `HUD.show_soft_warning()` single-message toast, just extended to a real
## queue. Domain no longer tints the toast itself (that distinction now
## only lives in NotificationHistoryUI's row text where there's room for
## it) — severity is the one thing a toast needs to communicate at a
## glance here.

enum Severity { INFO, WARNING, CRITICAL }

const MAX_QUEUE_LEN: int = 20

## History cap for the pause-menu notification history panel — separate
## from MAX_QUEUE_LEN (the fading live-toast stack). Independent array, own
## cap, own eviction, never touched by the toast fade/expire logic.
const MAX_HISTORY_LEN: int = 20

## Emitted whenever a new entry is appended to `_history` (i.e. every
## `notify()` call). NotificationHistoryUI listens to this to refresh its
## row list live while the pause menu is open, instead of polling every
## frame.
signal history_changed

const TOAST_WIDTH:      float = 510.0
const TOAST_HEIGHT:     float = 24.0
const TOAST_GAP:        float = 8.0
const GAP_ABOVE_BAR:    float = 12.0    ## gap between the nearest toast and the inventory bar
const FALLBACK_BOTTOM_MARGIN: float = 140.0   ## used when no HUD/inventory bar is found in-scene
const FADE_TAIL_RATIO:  float = 0.20   ## last 20% of lifetime ramps alpha -> 0
const DEFAULT_DURATION: float = 4.0

## Toast fill/border treatment (Jul 2026 rework — back to the old
## `HUD.show_soft_warning()` look/position, extended to a real stacked
## queue): solid severity-colored fill at partial opacity, plus a dark
## semi-transparent border on every toast (Brannon's explicit call).
const TOAST_FILL_ALPHA:   float = 0.62
const TOAST_BORDER_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const TOAST_BORDER_WIDTH: float = 2.0
const TOAST_TEXT_COLOR:   Color = Color(0.96, 0.96, 0.96, 1.0)
const TOAST_CORNER_RADIUS: int = 8   ## rounded rect corners (Jul 2026 follow-up)

## Severity colors — FIXED across all domains (Brannon's explicit call,
## Jul 2026): a WARNING toast is the same yellow-olive whether it's POWER
## or WATER, a CRITICAL toast is always the same dark red, etc. Now used
## as the toast's actual fill color (previously just a thin accent bar).
const SEVERITY_COLOR_INFO:     Color = Color(0x87 / 255.0, 0x87 / 255.0, 0x87 / 255.0, 1.0)
const SEVERITY_COLOR_WARNING:  Color = Color(0x8f / 255.0, 0x94 / 255.0, 0x0d / 255.0, 1.0)
const SEVERITY_COLOR_CRITICAL: Color = Color(0x94 / 255.0, 0x30 / 255.0, 0x2b / 255.0, 1.0)

## Each entry: { domain: UIKit.Domain, severity: Severity, text: String,
##               duration: float, age: float }
var _queue: Array[Dictionary] = []

## History entries: { domain: UIKit.Domain, severity: Severity, text: String,
##                     fired_at_msec: int }. Newest LAST here (append-only,
##                     matches _queue's convention); get_history() reverses
##                     to newest-first for the UI. Independent of _queue —
##                     never mutated/expired, only capped at MAX_HISTORY_LEN.
var _history: Array[Dictionary] = []

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

	_history.append({
		"domain":        domain,
		"severity":      severity,
		"text":          text,
		"fired_at_msec": Time.get_ticks_msec(),
	})
	if _history.size() > MAX_HISTORY_LEN:
		_history.pop_front()   ## drop oldest first, same eviction policy as _queue
	history_changed.emit()


## Returns the notification history, NEWEST FIRST (opposite append order of
## the internal array) — direct consumption order for NotificationHistoryUI.
func get_history() -> Array[Dictionary]:
	var out: Array[Dictionary] = _history.duplicate()
	out.reverse()
	return out


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
	var center_x: float = (vp.x - TOAST_WIDTH) * 0.5

	## Anchor above the inventory bar — same reasoning as the old
	## `HUD.show_soft_warning()` (Brannon's explicit call to bring that
	## position/shape back). Falls back to a fixed bottom margin if no
	## HUD is present in the current scene (e.g. a menu/preview context).
	var bar_top: float = vp.y - FALLBACK_BOTTOM_MARGIN
	var hud: Node = _canvas.get_tree().get_first_node_in_group("hud")
	if hud != null and ("inventory_hud" in hud):
		var inv: Control = hud.get("inventory_hud") as Control
		if inv != null and is_instance_valid(inv):
			bar_top = inv.get_global_rect().position.y

	## Newest toast (last in _queue) sits closest to the bar; older
	## entries stack upward above it — iterate newest-first.
	var bottom_y: float = bar_top - GAP_ABOVE_BAR
	for i: int in range(_queue.size() - 1, -1, -1):
		var entry: Dictionary = _queue[i]
		var rect: Rect2 = Rect2(center_x, bottom_y - TOAST_HEIGHT, TOAST_WIDTH, TOAST_HEIGHT)
		_draw_toast(rect, entry)
		bottom_y -= TOAST_HEIGHT + TOAST_GAP


func _draw_toast(rect: Rect2, entry: Dictionary) -> void:
	var severity: Severity = entry["severity"]
	var text: String       = entry["text"]
	var age: float          = float(entry["age"])
	var duration: float     = float(entry["duration"])

	var alpha: float = _fade_alpha(age, duration)

	## Solid severity-colored fill (semi-transparent) + dark semi-transparent
	## border on every toast — Brannon's explicit Jul 2026 call to bring
	## back the old show_soft_warning() look, just severity-colored instead
	## of the old flat dark/amber panel. Rounded corners (Jul 2026 follow-up)
	## need a real StyleBoxFlat — plain draw_rect() has no corner radius.
	var fill: Color = _severity_color(severity)
	fill.a = TOAST_FILL_ALPHA * alpha
	var border: Color = TOAST_BORDER_COLOR
	border.a *= alpha

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color     = fill
	sb.border_color = border
	sb.set_border_width_all(TOAST_BORDER_WIDTH)
	sb.set_corner_radius_all(TOAST_CORNER_RADIUS)
	sb.draw(_canvas.get_canvas_item(), rect)

	var text_color: Color = TOAST_TEXT_COLOR
	text_color.a *= alpha
	var text_pos: Vector2 = rect.position + Vector2(14.0, rect.size.y * 0.5 + 5.0)
	UIKit.draw_shadowed_text(_canvas, text_pos, text, 13, text_color)


func _severity_color(severity: Severity) -> Color:
	match severity:
		Severity.WARNING:
			return SEVERITY_COLOR_WARNING
		Severity.CRITICAL:
			return SEVERITY_COLOR_CRITICAL
		_:
			return SEVERITY_COLOR_INFO


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


## ─────────────────────────────────────────────────────────────────────────────
## Power signal wiring (Part 3 step 4 of the UI Kit + Notifications plan,
## Jul 2026). Thin adapter only — PowerManager already does all the actual
## detection work, this just translates its signals into notify() calls.
##
## PowerManager is a per-scene instance (group "power_manager"), not an
## autoload, so it doesn't exist yet when this autoload's own _ready() runs.
## MainWorld calls connect_power_signals() once, deferred, right after it
## creates PowerManager for that scene (mirrors the existing
## _connect_power_hud_signals() pattern already in MainWorld.gd). Guarded
## with is_connected() checks so calling this more than once is harmless.
##
## Severity mapping (Brannon's call, Jul 2026):
##   CRITICAL — grid_tripped, grid_offline (total outage)
##   WARNING  — overloaded_started, breaker_tripped, battery_drained,
##              generator_stopped (localized problems, not full outage)
##   INFO     — grid_restored, overloaded_ended, generator_started,
##              breaker_reset (recovery events), generator_fuel_low,
##              battery_low (early warning thresholds)
##
## grid_tripped/grid_restored/grid_offline previously routed through
## HUD.show_soft_warning() from MainWorld — that duplicate ad-hoc path is
## removed from MainWorld in this same pass so the toast is the ONE place
## these events surface (not two overlapping notifications for one event).
func connect_power_signals() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var pm: Node = tree.get_first_node_in_group("power_manager")
	if pm == null:
		return

	if pm.has_signal("grid_tripped") and not pm.grid_tripped.is_connected(_on_pm_grid_tripped):
		pm.grid_tripped.connect(_on_pm_grid_tripped)
	if pm.has_signal("grid_restored") and not pm.grid_restored.is_connected(_on_pm_grid_restored):
		pm.grid_restored.connect(_on_pm_grid_restored)
	if pm.has_signal("grid_offline") and not pm.grid_offline.is_connected(_on_pm_grid_offline):
		pm.grid_offline.connect(_on_pm_grid_offline)
	if pm.has_signal("overloaded_started") and not pm.overloaded_started.is_connected(_on_pm_overloaded_started):
		pm.overloaded_started.connect(_on_pm_overloaded_started)
	if pm.has_signal("overloaded_ended") and not pm.overloaded_ended.is_connected(_on_pm_overloaded_ended):
		pm.overloaded_ended.connect(_on_pm_overloaded_ended)
	if pm.has_signal("generator_started") and not pm.generator_started.is_connected(_on_pm_generator_started):
		pm.generator_started.connect(_on_pm_generator_started)
	if pm.has_signal("generator_stopped") and not pm.generator_stopped.is_connected(_on_pm_generator_stopped):
		pm.generator_stopped.connect(_on_pm_generator_stopped)
	if pm.has_signal("generator_fuel_low") and not pm.generator_fuel_low.is_connected(_on_pm_generator_fuel_low):
		pm.generator_fuel_low.connect(_on_pm_generator_fuel_low)
	if pm.has_signal("battery_low") and not pm.battery_low.is_connected(_on_pm_battery_low):
		pm.battery_low.connect(_on_pm_battery_low)
	if pm.has_signal("battery_drained") and not pm.battery_drained.is_connected(_on_pm_battery_drained):
		pm.battery_drained.connect(_on_pm_battery_drained)
	if pm.has_signal("breaker_tripped") and not pm.breaker_tripped.is_connected(_on_pm_breaker_tripped):
		pm.breaker_tripped.connect(_on_pm_breaker_tripped)
	if pm.has_signal("breaker_reset") and not pm.breaker_reset.is_connected(_on_pm_breaker_reset):
		pm.breaker_reset.connect(_on_pm_breaker_reset)


func _on_pm_grid_tripped() -> void:
	notify(UIKit.Domain.POWER, Severity.CRITICAL, "⚡ POWER GRID TRIPPED — reduce load, then restart generators")

func _on_pm_grid_restored() -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "✓ GRID RESTORED — restart generators to restore power")

func _on_pm_grid_offline() -> void:
	notify(UIKit.Domain.POWER, Severity.CRITICAL, "✗ POWER GRID OFFLINE — no generators or batteries")

func _on_pm_overloaded_started() -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING, "⚠ Power grid overloaded — load shedding active")

func _on_pm_overloaded_ended() -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "✓ Power grid load back to normal")

func _on_pm_generator_started(gen_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "Generator %s started" % gen_id)

func _on_pm_generator_stopped(gen_id: String, reason: String) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING, "Generator %s stopped (%s)" % [gen_id, reason])

func _on_pm_generator_fuel_low(gen_id: String, fuel_pct: float) -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "Generator %s fuel low (%d%%)" % [gen_id, int(round(fuel_pct))])

func _on_pm_battery_low(bat_id: String, charge_pct: float) -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "Battery %s charge low (%d%%)" % [bat_id, int(round(charge_pct))])

func _on_pm_battery_drained(bat_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING, "Battery %s drained" % bat_id)

func _on_pm_breaker_tripped(breaker_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING, "Breaker %s tripped" % breaker_id)

func _on_pm_breaker_reset(breaker_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "Breaker %s reset" % breaker_id)
