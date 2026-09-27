extends Node
## Central alert service. Live toasts are compact, capped and non-interactive;
## durable run events are also exposed to the pause-menu Bunker Log.
## Sep 2026 quiet pass: toasts are native quiet cards stacked top-right under
## the cash readout, avoiding registered surfaces (QuietControls.avoid_toasts).

signal history_changed

enum Severity { INFO, WARNING, CRITICAL }

const MAX_QUEUE_LEN := 20
const MAX_VISIBLE_TOASTS := 3
const MAX_HISTORY_LEN := 20
## Quiet toasts (Sep 2026, decision D2): top-right, under the cash readout.
const TOAST_WIDTH := 360.0
const TOAST_GAP := 8.0
const TOAST_EDGE := 24.0
const TOAST_TOP_FALLBACK := 72.0
const TOAST_GAP_BELOW_CASH := 12.0
## Controls that toasts must never cover (see QuietControls.avoid_toasts()).
const TOAST_AVOID_GROUP := &"ui_toast_avoid"
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const FADE_TAIL_RATIO := 0.20
const DEFAULT_DURATION := 4.0
const DURATION_SENTINEL := -1.0
const WARNING_DURATION := 6.0
const CRITICAL_DURATION := 8.0
const DEDUPE_WINDOW_MSEC := 2500

const SEVERITY_COLOR_INFO := Color("86a9bf")
const SEVERITY_COLOR_WARNING := Color("f0b861")
const SEVERITY_COLOR_CRITICAL := Color("df7669")

## Live entry: domain, severity, text, detail, duration, age, count.
var _queue: Array[Dictionary] = []
## Journal entry adds fired_at_msec and seen. Newest remains last internally.
var _history: Array[Dictionary] = []
var _canvas: Control
var _views: Dictionary = {}          ## instance_id -> toast PanelContainer
var _overflow_label: Label

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
	# Autoload canvases have no theme owner: give toasts the project font.
	BunkerUIComponents.apply_theme(_canvas)
	_overflow_label = Q.label("", 12, Q.MUTED)
	_overflow_label.name = "Overflow"
	_overflow_label.visible = false
	_canvas.add_child(_overflow_label)

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
	for view: PanelContainer in _views.values():
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()

func _process(delta: float) -> void:
	if _queue.is_empty() and _views.is_empty():
		return
	## While a modal workspace is open, ordinary alerts wait (they are already
	## in the Log) and appear when it closes; critical alerts still break through.
	var held := _modal_open()
	for entry: Dictionary in _queue:
		if not held or int(entry.severity) == Severity.CRITICAL:
			entry.age = float(entry.age) + delta
	_queue = _queue.filter(func(entry: Dictionary) -> bool:
		return float(entry.age) < float(entry.duration))
	_layout_toasts(delta, held)


# ── Quiet toast presentation (Sep 2026, QUIET_DESIGN_SYSTEM §3, decision D2) ──
# Top-right under the cash readout, newest on top, native controls. Surfaces
# that must never be covered register with QuietControls.avoid_toasts().

func _layout_toasts(delta: float, held: bool) -> void:
	var viewport := _canvas.get_viewport().get_visible_rect().size
	var shown: Array[Dictionary] = []
	for i: int in range(_queue.size() - 1, -1, -1):
		var entry: Dictionary = _queue[i]
		if held and int(entry.severity) != Severity.CRITICAL:
			continue
		shown.append(entry)
		if shown.size() >= MAX_VISIBLE_TOASTS:
			break
	var hidden := 0
	for entry: Dictionary in _queue:
		if not (held and int(entry.severity) != Severity.CRITICAL):
			hidden += 1
	hidden -= shown.size()

	var keep: Dictionary = {}
	var heights := 0.0
	for entry: Dictionary in shown:
		var view := _view_for(entry)
		keep[view.get_instance_id()] = true
		heights += view.get_combined_minimum_size().y + TOAST_GAP
	var column := _toast_column(viewport, heights, held)
	var y := column.position.y
	for entry: Dictionary in shown:
		var view: PanelContainer = entry.view
		var target := Vector2(column.position.x, y)
		if not view.visible:
			view.visible = true
			view.position = target + Vector2(18.0, 0.0)
		view.position = view.position.lerp(target, UIMotion.weight(delta, 14.0))
		var appear: float = minf(float(view.get_meta(&"appear", 0.0)) + delta / 0.22, 1.0)
		view.set_meta(&"appear", appear if not UIMotion.reduced() else 1.0)
		view.modulate.a = float(view.get_meta(&"appear")) * _fade_alpha(float(entry.age), float(entry.duration))
		_refresh_view(view, entry)
		y += view.size.y + TOAST_GAP
	_overflow_label.visible = hidden > 0
	if hidden > 0:
		_overflow_label.text = "+%d more" % hidden
		_overflow_label.position = Vector2(column.end.x - _overflow_label.size.x, y)
	## Retire views whose entries left the queue (or are held back).
	for id: int in _views.keys():
		if not keep.has(id):
			var view: PanelContainer = _views[id]
			_views.erase(id)
			_retire_view(view)


func _toast_column(viewport: Vector2, height: float, held: bool) -> Rect2:
	var right := viewport.x - TOAST_EDGE
	var top := TOAST_TOP_FALLBACK
	var hud := _canvas.get_tree().get_first_node_in_group("hud")
	if hud != null and "cash_panel" in hud:
		var cash := hud.get("cash_panel") as Control
		if is_instance_valid(cash) and cash.is_visible_in_tree():
			top = cash.get_global_rect().end.y + TOAST_GAP_BELOW_CASH
	if held:
		## Modal workspace open: critical alerts sit top-centre over the dim.
		return Rect2((viewport.x - TOAST_WIDTH) * 0.5, 12.0, TOAST_WIDTH, height)
	for pass_index: int in range(3):
		var column := Rect2(right - TOAST_WIDTH, top, TOAST_WIDTH, height)
		var moved := false
		for obstacle: Rect2 in _obstacles(false):
			if not column.intersects(obstacle):
				continue
			if obstacle.position.y <= top + 4.0:
				top = obstacle.end.y + TOAST_GAP_BELOW_CASH   # a strip at the anchor (SHOP)
			else:
				right = obstacle.position.x - 16.0            # a docked panel below
			moved = true
		if not moved:
			break
	return Rect2(maxf(right - TOAST_WIDTH, TOAST_EDGE), top, TOAST_WIDTH, height)


func _obstacles(modal: bool) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node: Node in _canvas.get_tree().get_nodes_in_group(TOAST_AVOID_GROUP):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var layer := _canvas_layer_of(control)
		if layer != null and not layer.visible:
			continue
		if bool(control.get_meta(&"toast_modal", false)) == modal:
			rects.append(control.get_global_rect())
	return rects


func _modal_open() -> bool:
	return not _obstacles(true).is_empty()


func _canvas_layer_of(node: Node) -> CanvasLayer:
	var current := node.get_parent()
	while current != null:
		if current is CanvasLayer:
			return current as CanvasLayer
		current = current.get_parent()
	return null


func _view_for(entry: Dictionary) -> PanelContainer:
	# A card is retired (faded + freed) when its entry leaves the visible set,
	# e.g. while held behind a modal workspace. The entry may come back later,
	# so validate before any type check (`is` on a freed object errors) and
	# never reuse a card that is mid-retirement.
	var existing: Variant = entry.get("view")
	if is_instance_valid(existing) and existing is PanelContainer \
			and not (existing as PanelContainer).has_meta(&"retiring"):
		return existing
	entry.erase("view")
	var view := PanelContainer.new()
	view.name = "Toast"
	view.visible = false
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.custom_minimum_size.x = TOAST_WIDTH
	view.add_theme_stylebox_override("panel", Q.toast_box())
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 2)
	view.add_child(body)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(top)
	var eyebrow: Label = Q.eyebrow("", 11)
	eyebrow.name = "Eyebrow"
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(eyebrow)
	var count: Label = Q.label("", 12, Q.MUTED)
	count.name = "Count"
	top.add_child(count)
	var title: Label = Q.label("", 15, Q.TEXT)
	title.name = "Title"
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(title)
	var detail: Label = Q.label("", 13, Q.MUTED)
	detail.name = "Detail"
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.visible = false
	body.add_child(detail)
	view.set_meta(&"eyebrow", eyebrow)
	view.set_meta(&"count", count)
	view.set_meta(&"title", title)
	view.set_meta(&"detail", detail)
	_canvas.add_child(view)
	entry.view = view
	_views[view.get_instance_id()] = view
	return view


func _refresh_view(view: PanelContainer, entry: Dictionary) -> void:
	var severity := int(entry.severity) as Severity
	var domain := int(entry.domain) as UIKit.Domain
	var eyebrow := view.get_meta(&"eyebrow") as Label
	var text := domain_label(domain)
	if severity != Severity.INFO:
		text = "●  %s  ·  %s" % [text, severity_label(severity)]
	if eyebrow.text != text:
		eyebrow.text = text
		eyebrow.add_theme_color_override("font_color",
			Q.HEADING if severity == Severity.INFO else severity_color(severity))
	(view.get_meta(&"title") as Label).text = str(entry.text)
	var detail := view.get_meta(&"detail") as Label
	detail.text = str(entry.get("detail", ""))
	detail.visible = not detail.text.is_empty()
	var count := int(entry.get("count", 1))
	(view.get_meta(&"count") as Label).text = "×%d" % count if count > 1 else ""
	# Controls grow but never shrink on their own: fit the card to its content.
	var fitted := view.get_combined_minimum_size()
	if not view.size.is_equal_approx(fitted):
		view.size = fitted


func _retire_view(view: PanelContainer) -> void:
	if not is_instance_valid(view):
		return
	view.set_meta(&"retiring", true)
	if UIMotion.reduced() or not view.visible:
		view.queue_free()
		return
	var tween := view.create_tween().set_parallel(true)
	tween.tween_property(view, "modulate:a", 0.0, 0.18)
	tween.tween_property(view, "position:x", view.position.x + 12.0, 0.18)
	tween.chain().tween_callback(view.queue_free)


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
		UIKit.Domain.INVENTORY:
			return "INVENTORY"
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
		UIKit.Domain.INVENTORY:
			return "storage"
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
		DURATION_SENTINEL, true, "%s remaining" % UIFormat.percent(fuel_pct))

func _on_pm_battery_low(bat_id: String, charge_pct: float) -> void:
	notify(UIKit.Domain.POWER, Severity.WARNING,
		"%s charge low" % _power_device_name("battery", bat_id),
		DURATION_SENTINEL, true, "%s remaining" % UIFormat.percent(charge_pct))

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
