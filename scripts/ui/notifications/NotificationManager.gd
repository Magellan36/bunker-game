extends Node
## Central alert service. Live toasts are compact, capped and non-interactive;
## durable run events are also exposed to the pause-menu Bunker Log.

signal history_changed

enum Severity { INFO, WARNING, CRITICAL }

const MAX_QUEUE_LEN := 20
const MAX_VISIBLE_TOASTS := 3
const MAX_HISTORY_LEN := 20
const TOAST_WIDTH := 520.0
const TOAST_HEIGHT := 48.0
const TOAST_GAP := 6.0
const GAP_ABOVE_BAR := 12.0
const FALLBACK_BOTTOM_MARGIN := 140.0
const FADE_TAIL_RATIO := 0.20
const DEFAULT_DURATION := 4.0
const DURATION_SENTINEL := -1.0
const WARNING_DURATION := 6.0
const CRITICAL_DURATION := 8.0
const DEDUPE_WINDOW_MSEC := 2500

const TOAST_FILL_ALPHA := 0.96
const TOAST_BORDER_COLOR := Color("3e3b33")
const TOAST_BORDER_WIDTH := 1.0
const TOAST_TEXT_COLOR := Color("f2e8cf")
const TOAST_CORNER_RADIUS := 7
const TOAST_BG := Color("111615f5")

const SEVERITY_COLOR_INFO := Color("5faee3")
const SEVERITY_COLOR_WARNING := Color("dda42e")
const SEVERITY_COLOR_CRITICAL := Color("df4e4e")

## Live entry: domain, severity, text, detail, duration, age, count.
var _queue: Array[Dictionary] = []
## Journal entry adds fired_at_msec and seen. Newest remains last internally.
var _history: Array[Dictionary] = []
var _canvas: Control

func _ready() -> void:
	var notification_layer := CanvasLayer.new()
	notification_layer.layer = 220
	notification_layer.name = "NotificationLayer"
	add_child(notification_layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.name = "NotificationCanvas"
	notification_layer.add_child(_canvas)
	_canvas.draw.connect(_on_draw)

## Existing call signature remains source-compatible: duration is still the
## fourth argument. `journal=false` is reserved for immediate UI feedback that
## should not clutter the run log; `detail` supplies an optional second line.
func notify(domain: UIKit.Domain, severity: Severity, text: String,
		duration: float = DURATION_SENTINEL, journal: bool = true,
		detail: String = "") -> void:
	var parts := _split_message(text, detail)
	var resolved_duration := duration
	if resolved_duration == DURATION_SENTINEL:
		resolved_duration = _default_duration_for_severity(severity)
	var now := Time.get_ticks_msec()
	var key := _dedupe_key(domain, severity, str(parts.title), str(parts.detail))
	var live := _find_recent(_queue, key, now, false)
	if live >= 0:
		_queue[live].age = 0.0
		_queue[live].duration = resolved_duration
		_queue[live].count = int(_queue[live].get("count", 1)) + 1
		_queue[live].last_at_msec = now
		## Move the refreshed event to the newest/lowest visual position.
		var refreshed: Dictionary = _queue.pop_at(live)
		_queue.append(refreshed)
	else:
		_queue.append({
			"domain": domain,
			"severity": severity,
			"text": str(parts.title),
			"detail": str(parts.detail),
			"duration": resolved_duration,
			"age": 0.0,
			"count": 1,
			"key": key,
			"last_at_msec": now,
		})
	if _queue.size() > MAX_QUEUE_LEN:
		_queue.pop_front()
	if journal:
		_append_history(domain, severity, str(parts.title), str(parts.detail), key, now)
	if _canvas != null:
		_canvas.queue_redraw()

## Short-lived interaction acknowledgement. It still appears as a toast, but
## never enters Bunker Log. Use this for "bag empty", +material, etc.; real
## state changes and warnings continue to use notify().
func feedback(domain: UIKit.Domain, severity: Severity, text: String,
		duration: float = DURATION_SENTINEL, detail: String = "") -> void:
	notify(domain, severity, text, duration, false, detail)

func _append_history(domain: UIKit.Domain, severity: Severity, text: String,
		detail: String, key: String, now: int) -> void:
	var recent := _find_recent(_history, key, now, true)
	if recent >= 0:
		_history[recent].count = int(_history[recent].get("count", 1)) + 1
		_history[recent].fired_at_msec = now
		_history[recent].last_at_msec = now
		_history[recent].seen = false
		var refreshed: Dictionary = _history.pop_at(recent)
		_history.append(refreshed)
	else:
		_history.append({
			"domain": domain,
			"severity": severity,
			"text": text,
			"detail": detail,
			"fired_at_msec": now,
			"last_at_msec": now,
			"count": 1,
			"seen": false,
			"key": key,
		})
	if _history.size() > MAX_HISTORY_LEN:
		_history.pop_front()
	history_changed.emit()

func _find_recent(entries: Array[Dictionary], key: String, now: int,
		history_entries: bool) -> int:
	for i: int in range(entries.size() - 1, -1, -1):
		if str(entries[i].get("key", "")) != key:
			continue
		var stamp := int(entries[i].get("last_at_msec", now))
		if history_entries and now - stamp > DEDUPE_WINDOW_MSEC:
			return -1
		if not history_entries and float(entries[i].get("age", 0.0)) > 2.5:
			return -1
		return i
	return -1

func _dedupe_key(domain: int, severity: int, text: String, detail: String) -> String:
	return "%d|%d|%s|%s" % [domain, severity, text, detail]

func _split_message(text: String, explicit_detail: String) -> Dictionary:
	if not explicit_detail.is_empty():
		return {"title": text, "detail": explicit_detail}
	var divider := text.find(" — ")
	if divider >= 0:
		return {"title": text.left(divider), "detail": text.substr(divider + 3)}
	return {"title": text, "detail": ""}

func get_history() -> Array[Dictionary]:
	var out: Array[Dictionary] = _history.duplicate(true)
	out.reverse()
	return out

func mark_history_seen() -> void:
	for entry: Dictionary in _history:
		entry.seen = true

func clear_transient_queue() -> void:
	_queue.clear()
	if _canvas != null:
		_canvas.queue_redraw()

func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	for entry: Dictionary in _queue:
		entry.age = float(entry.age) + delta
	_queue = _queue.filter(func(entry: Dictionary) -> bool:
		return float(entry.age) < float(entry.duration))
	_canvas.queue_redraw()

func _on_draw() -> void:
	if _queue.is_empty():
		return
	var viewport := _canvas.get_viewport().get_visible_rect().size
	var center_x := (viewport.x - TOAST_WIDTH) * 0.5
	var bar_top := viewport.y - FALLBACK_BOTTOM_MARGIN
	var hud := _canvas.get_tree().get_first_node_in_group("hud")
	if hud != null and "inventory_hud" in hud:
		var inventory_bar := hud.get("inventory_hud") as Control
		if is_instance_valid(inventory_bar):
			bar_top = inventory_bar.get_global_rect().position.y
	var visible_count := mini(MAX_VISIBLE_TOASTS, _queue.size())
	var first := _queue.size() - visible_count
	var bottom_y := bar_top - GAP_ABOVE_BAR
	for i: int in range(_queue.size() - 1, first - 1, -1):
		var rect := Rect2(center_x, bottom_y - TOAST_HEIGHT, TOAST_WIDTH, TOAST_HEIGHT)
		_draw_toast(rect, _queue[i])
		bottom_y -= TOAST_HEIGHT + TOAST_GAP
	var hidden := _queue.size() - visible_count
	if hidden > 0:
		_draw_overflow(Vector2(center_x + 8, bottom_y - 2), hidden)

func _draw_toast(rect: Rect2, entry: Dictionary) -> void:
	var alpha := _fade_alpha(float(entry.age), float(entry.duration))
	var severity := int(entry.severity) as Severity
	var accent := severity_color(severity)
	var background := TOAST_BG
	background.a *= alpha
	var border := TOAST_BORDER_COLOR
	border.a *= alpha
	var shell := StyleBoxFlat.new()
	shell.bg_color = background
	shell.border_color = border
	shell.set_border_width_all(int(TOAST_BORDER_WIDTH))
	shell.set_corner_radius_all(TOAST_CORNER_RADIUS)
	shell.draw(_canvas.get_canvas_item(), rect)
	var stripe := accent
	stripe.a *= alpha
	_canvas.draw_rect(Rect2(rect.position + Vector2(0, 6), Vector2(5, rect.size.y - 12)), stripe, true)
	var icon_rect := Rect2(rect.position + Vector2(10, 6), Vector2(36, 36))
	var icon_bg := Color("181d1d")
	icon_bg.a *= alpha
	var icon_edge := BunkerPanelStyle.BRASS.darkened(0.32)
	icon_edge.a *= alpha
	var icon_shell := StyleBoxFlat.new()
	icon_shell.bg_color = icon_bg
	icon_shell.border_color = icon_edge
	icon_shell.set_border_width_all(1)
	icon_shell.set_corner_radius_all(5)
	icon_shell.draw(_canvas.get_canvas_item(), icon_rect)
	var domain := int(entry.domain) as UIKit.Domain
	var icon_color := domain_color(domain)
	icon_color.a *= alpha
	_canvas.draw_texture_rect(BunkerPanelStyle.icon(domain_symbol(domain)),
		icon_rect.grow(-7), false, icon_color)
	var domain_text := "%s  •  %s" % [domain_label(domain), severity_label(severity)]
	var domain_tint := accent if severity != Severity.INFO else domain_color(domain)
	domain_tint.a *= alpha
	UIKit.draw_shadowed_text(_canvas, rect.position + Vector2(56, 15), domain_text, 10, domain_tint)
	var message := _ellipsize(str(entry.text), rect.size.x - 122, 14)
	var text_color := TOAST_TEXT_COLOR
	text_color.a *= alpha
	UIKit.draw_shadowed_text(_canvas, rect.position + Vector2(56, 36), message, 14, text_color)
	var detail := str(entry.get("detail", ""))
	if not detail.is_empty():
		## Keep compact 48px toast height: detail replaces the right metadata
		## column rather than creating a third text line.
		var detail_text := _ellipsize(detail, 120, 10)
		var detail_color := BunkerPanelStyle.BRASS.lightened(0.30)
		detail_color.a *= alpha
		var width := UIKit.font().get_string_size(detail_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		UIKit.draw_shadowed_text(_canvas,
			rect.position + Vector2(rect.size.x - width - 10, 15), detail_text, 10, detail_color)
	var count := int(entry.get("count", 1))
	if count > 1:
		var badge := "×%d" % count
		var badge_color := accent
		badge_color.a *= alpha
		var badge_width := UIKit.font().get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		UIKit.draw_shadowed_text(_canvas,
			rect.position + Vector2(rect.size.x - badge_width - 10, 36), badge, 11, badge_color)

func _draw_overflow(position: Vector2, hidden: int) -> void:
	var text := "+%d earlier alert%s" % [hidden, "" if hidden == 1 else "s"]
	UIKit.draw_shadowed_text(_canvas, position, text, 10, BunkerPanelStyle.MUTED)

func _ellipsize(text: String, max_width: float, size: int) -> String:
	if UIKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_width:
		return text
	var result := text
	while result.length() > 1 and UIKit.font().get_string_size(
			result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
		result = result.left(result.length() - 1)
	return result + "…"

func severity_color(severity: Severity) -> Color:
	match severity:
		Severity.WARNING:
			return SEVERITY_COLOR_WARNING
		Severity.CRITICAL:
			return SEVERITY_COLOR_CRITICAL
		_:
			return SEVERITY_COLOR_INFO

func severity_label(severity: Severity) -> String:
	match severity:
		Severity.WARNING:
			return "WARNING"
		Severity.CRITICAL:
			return "CRITICAL"
		_:
			return "INFO"

func domain_label(domain: UIKit.Domain) -> String:
	match domain:
		UIKit.Domain.POWER:
			return "POWER"
		UIKit.Domain.WATER:
			return "WATER"
		UIKit.Domain.FARMING:
			return "FARMING"
		_:
			return "GENERAL"

func domain_color(domain: UIKit.Domain) -> Color:
	return UIKit.theme_for(domain).accent

func domain_symbol(domain: UIKit.Domain) -> String:
	match domain:
		UIKit.Domain.POWER:
			return "power"
		UIKit.Domain.WATER:
			return "water"
		UIKit.Domain.FARMING:
			return "plant"
		_:
			return "general"

func _default_duration_for_severity(severity: Severity) -> float:
	match severity:
		Severity.WARNING:
			return WARNING_DURATION
		Severity.CRITICAL:
			return CRITICAL_DURATION
		_:
			return DEFAULT_DURATION

func _fade_alpha(age: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	var ratio := age / duration
	var fade_start := 1.0 - FADE_TAIL_RATIO
	if ratio <= fade_start:
		return 1.0
	return clampf(1.0 - (ratio - fade_start) / FADE_TAIL_RATIO, 0.0, 1.0)

## PowerManager owns detection; this adapter only produces player-facing copy.
func connect_power_signals() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var pm := tree.get_first_node_in_group("power_manager")
	if pm == null:
		return
	if pm.has_signal("grid_tripped") and not pm.grid_tripped.is_connected(_on_pm_grid_tripped):
		pm.grid_tripped.connect(_on_pm_grid_tripped)
	if pm.has_signal("grid_restored") and not pm.grid_restored.is_connected(_on_pm_grid_restored):
		pm.grid_restored.connect(_on_pm_grid_restored)
	if pm.has_signal("grid_offline") and not pm.grid_offline.is_connected(_on_pm_grid_offline):
		pm.grid_offline.connect(_on_pm_grid_offline)
	if pm.has_signal("overloaded_started") \
			and not pm.overloaded_started.is_connected(_on_pm_overloaded_started):
		pm.overloaded_started.connect(_on_pm_overloaded_started)
	if pm.has_signal("overloaded_ended") \
			and not pm.overloaded_ended.is_connected(_on_pm_overloaded_ended):
		pm.overloaded_ended.connect(_on_pm_overloaded_ended)
	if pm.has_signal("generator_started") \
			and not pm.generator_started.is_connected(_on_pm_generator_started):
		pm.generator_started.connect(_on_pm_generator_started)
	if pm.has_signal("generator_stopped") \
			and not pm.generator_stopped.is_connected(_on_pm_generator_stopped):
		pm.generator_stopped.connect(_on_pm_generator_stopped)
	if pm.has_signal("generator_fuel_low") \
			and not pm.generator_fuel_low.is_connected(_on_pm_generator_fuel_low):
		pm.generator_fuel_low.connect(_on_pm_generator_fuel_low)
	if pm.has_signal("battery_low") and not pm.battery_low.is_connected(_on_pm_battery_low):
		pm.battery_low.connect(_on_pm_battery_low)
	if pm.has_signal("battery_drained") \
			and not pm.battery_drained.is_connected(_on_pm_battery_drained):
		pm.battery_drained.connect(_on_pm_battery_drained)
	if pm.has_signal("breaker_tripped") \
			and not pm.breaker_tripped.is_connected(_on_pm_breaker_tripped):
		pm.breaker_tripped.connect(_on_pm_breaker_tripped)
	if pm.has_signal("breaker_reset") and not pm.breaker_reset.is_connected(_on_pm_breaker_reset):
		pm.breaker_reset.connect(_on_pm_breaker_reset)

func _power_device_name(kind: String, device_id: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var pm := tree.get_first_node_in_group("power_manager") if tree != null else null
	if pm == null:
		return kind.capitalize()
	var registry_name := "_generators" if kind == "generator" else (
		"_batteries" if kind == "battery" else "_breakers")
	var devices: Dictionary = pm.get(registry_name)
	var device: Dictionary = devices.get(device_id, {})
	var node: Node = device.get("node") as Node
	if is_instance_valid(node):
		if node.has_method("get_display_name"):
			return str(node.call("get_display_name"))
		if node.has_method("_get_display_name"):
			return str(node.call("_get_display_name"))
		if kind == "battery" and "battery_tier" in node:
			return ["Battery S", "Battery M", "Battery L"][clampi(int(node.get("battery_tier")), 0, 2)]
		if kind == "breaker":
			var zone_name := str(node.get("_zone_name")) if "_zone_name" in node else ""
			return "%s breaker" % zone_name if not zone_name.is_empty() else "Circuit breaker"
	return kind.capitalize()

func _on_pm_grid_tripped() -> void:
	notify(UIKit.Domain.POWER, Severity.CRITICAL, "Power grid tripped",
		DURATION_SENTINEL, true, "Reduce load, then restart generators")

func _on_pm_grid_restored() -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "Power grid restored",
		DURATION_SENTINEL, true, "Restart stopped generators")

func _on_pm_grid_offline() -> void:
	notify(UIKit.Domain.POWER, Severity.CRITICAL, "Power grid offline",
		DURATION_SENTINEL, true, "No generators or batteries available")

func _on_pm_overloaded_started() -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING, "Power grid overloaded",
		DURATION_SENTINEL, true, "Load shedding is active")

func _on_pm_overloaded_ended() -> void:
	notify(UIKit.Domain.POWER, Severity.INFO, "Power grid load back to normal")

func _on_pm_generator_started(gen_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.INFO,
		"%s started" % _power_device_name("generator", gen_id))

func _on_pm_generator_stopped(gen_id: String, reason: String) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING,
		"%s stopped" % _power_device_name("generator", gen_id),
		DURATION_SENTINEL, true, reason.capitalize())

func _on_pm_generator_fuel_low(gen_id: String, fuel_pct: float) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING,
		"%s fuel reserve low" % _power_device_name("generator", gen_id),
		DURATION_SENTINEL, true, "%d%% remaining" % int(round(fuel_pct)))

func _on_pm_battery_low(bat_id: String, charge_pct: float) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING,
		"%s charge low" % _power_device_name("battery", bat_id),
		DURATION_SENTINEL, true, "%d%% remaining" % int(round(charge_pct)))

func _on_pm_battery_drained(bat_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING,
		"%s drained" % _power_device_name("battery", bat_id))

func _on_pm_breaker_tripped(breaker_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.CRITICAL,
		"%s tripped" % _power_device_name("breaker", breaker_id),
		DURATION_SENTINEL, true, "Connected circuit lost power")

func _on_pm_breaker_reset(breaker_id: String) -> void:
	notify(UIKit.Domain.POWER, Severity.INFO,
		"%s reset" % _power_device_name("breaker", breaker_id))
