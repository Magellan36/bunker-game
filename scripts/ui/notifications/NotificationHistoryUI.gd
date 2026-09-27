class_name NotificationHistoryUI
extends Control
## Filterable Log embedded in the pause menu. It is a view over the
## manager's bounded run history; it never owns or mutates gameplay state.
## Sep 2026 quiet pass (QUIET_DESIGN_SYSTEM): text filter tabs with a sliding
## underline, hairline rows (eyebrow · message · detail | age · new/×N),
## smooth scrolling, no icons or stripes.

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const SEGMENTED: GDScript = preload("res://scripts/ui/common/QuietSegmented.gd")
const SMOOTH_SCROLL: GDScript = preload("res://scripts/ui/common/SmoothScroll.gd")

const FILTERS: Array[String] = ["All", "Critical", "Inventory", "Power", "Water", "Farming"]
const ROW_HEIGHT := 60.0

var _filter := "All"
var _event_count: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _empty: Label
var _tabs: Control
var _filter_buttons: Dictionary = {}
var _row_time_labels: Array[Label] = []
var _row_entries: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	BunkerPanelStyle.apply(self)
	_build()
	NotificationManager.history_changed.connect(_rebuild_rows)
	_rebuild_rows()

func _build() -> void:
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 0)
	add_child(body)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	body.add_child(title_row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 4)
	title_row.add_child(titles)
	titles.add_child(Q.eyebrow("Bunker activity", 12))
	var title: Label = Q.label("Log", 26, Q.TEXT)
	title.name = "LogTitle"
	titles.add_child(title)
	_event_count = Q.label("", 12, Q.MUTED)
	_event_count.name = "EventCount"
	_event_count.size_flags_vertical = Control.SIZE_SHRINK_END
	title_row.add_child(_event_count)
	body.add_child(_gap(16.0))
	_tabs = SEGMENTED.new()
	_tabs.name = "LogFilters"
	var no_read_only: Array[int] = []
	_tabs.call("setup", FILTERS, no_read_only, 14, false)
	_tabs.connect("segment_pressed", func(index: int) -> void: _set_filter(FILTERS[index]))
	body.add_child(_tabs)
	var buttons: Array[Button] = _tabs.call("get_buttons")
	for i: int in FILTERS.size():
		_filter_buttons[FILTERS[i]] = buttons[i]
		buttons[i].set_meta(&"help", "Show %s events." % FILTERS[i].to_lower()
			if FILTERS[i] != "All" else "Show every recorded event.")
	body.add_child(_gap(10.0))
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", Q.hairline())
	line.add_theme_constant_override("separation", 1)
	body.add_child(line)
	_scroll = ScrollContainer.new()
	_scroll.name = "BunkerLogScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	Q.scrollbar(_scroll.get_v_scroll_bar())
	SMOOTH_SCROLL.attach(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 0)
	_scroll.add_child(_rows)
	_empty = Q.label("Nothing recorded here yet.", 14, Q.MUTED)
	_empty.custom_minimum_size.y = 64
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tabs.call("set_active", 0, false)

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and is_inside_tree():
		_rebuild_rows()
		## Preserve NEW badges during this visit; the manager marks the backing
		## entries after this frame so the next pause-open starts clean.
		NotificationManager.call_deferred("mark_history_seen")

func _set_filter(filter_name: String) -> void:
	_filter = filter_name
	var index := FILTERS.find(filter_name)
	if _tabs != null and index >= 0:
		_tabs.call("set_active", index, is_visible_in_tree())
	_rebuild_rows()

func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	_row_time_labels.clear()
	_row_entries.clear()
	var history: Array[Dictionary] = NotificationManager.get_history()
	_event_count.text = "%d event%s" % [history.size(), "" if history.size() == 1 else "s"]
	for entry: Dictionary in history:
		if _matches(entry):
			_row_entries.append(entry)
			_rows.add_child(_make_row(entry))
	if _row_entries.is_empty():
		_rows.add_child(_empty.duplicate())
	_scroll.scroll_vertical = 0
	if visible:
		NotificationManager.call_deferred("mark_history_seen")

func _matches(entry: Dictionary) -> bool:
	match _filter:
		"Critical":
			return int(entry.severity) == NotificationManager.Severity.CRITICAL
		"Power":
			return int(entry.domain) == UIKit.Domain.POWER
		"Water":
			return int(entry.domain) == UIKit.Domain.WATER
		"Farming":
			return int(entry.domain) == UIKit.Domain.FARMING
		"Inventory":
			return int(entry.domain) == UIKit.Domain.INVENTORY
		_:
			return true

func _make_row(entry: Dictionary) -> Control:
	var severity := int(entry.severity) as NotificationManager.Severity
	var domain := int(entry.domain) as UIKit.Domain
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", Q.row_box(4.0, 8.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	var eyebrow_text := NotificationManager.domain_label(domain)
	if severity != NotificationManager.Severity.INFO:
		eyebrow_text = "●  %s  ·  %s" % [eyebrow_text, NotificationManager.severity_label(severity)]
	var eyebrow: Label = Q.eyebrow(eyebrow_text, 11)
	if severity != NotificationManager.Severity.INFO:
		eyebrow.add_theme_color_override("font_color", NotificationManager.severity_color(severity))
	copy.add_child(eyebrow)
	var message: Label = Q.label(str(entry.text), 15, Q.TEXT)
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message.clip_text = true
	copy.add_child(message)
	var detail := str(entry.get("detail", ""))
	if not detail.is_empty():
		var detail_label: Label = Q.label(detail, 13, Q.MUTED)
		detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail_label.clip_text = true
		copy.add_child(detail_label)
	var meta := VBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 2)
	row.add_child(meta)
	var age: Label = Q.label(_format_age(int(entry.fired_at_msec)), 12, Q.MUTED)
	age.custom_minimum_size.x = 84
	age.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(age)
	_row_time_labels.append(age)
	var count := int(entry.get("count", 1))
	if count > 1:
		var count_label: Label = Q.label("×%d" % count, 12, Q.MUTED)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.add_child(count_label)
	elif not bool(entry.get("seen", true)):
		var new_label: Label = Q.label("new", 12, Q.ACCENT)
		new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.add_child(new_label)
	return panel

func _process(_delta: float) -> void:
	if not visible:
		return
	for i: int in mini(_row_time_labels.size(), _row_entries.size()):
		_row_time_labels[i].text = _format_age(int(_row_entries[i].fired_at_msec))

func _format_age(fired_at_msec: int) -> String:
	var elapsed := maxi(0, int((Time.get_ticks_msec() - fired_at_msec) / 1000.0))
	if elapsed < 10:
		return "just now"
	if elapsed < 60:
		return "%d s ago" % elapsed
	var minutes := elapsed / 60
	if minutes < 60:
		return "%d min ago" % minutes
	return "%d h ago" % (minutes / 60)
